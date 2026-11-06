extends SceneTree
var failures: Array[String] = []
var feedback: Node


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func check_wave(sound: AudioStreamWAV, description: String) -> void:
	check(sound.format == AudioStreamWAV.FORMAT_16_BITS and not sound.stereo, description + " uses mono PCM")
	check(sound.get_length() > 0.1 and sound.get_length() < 0.5, description + " is a short effect")
	var pcm := sound.data
	var peak := 0.0
	for index in range(0, pcm.size(), 2):
		peak = maxf(peak, absf(float(pcm.decode_s16(index)) / 32767.0))
	check(peak > 0.1 and peak < 1.0, description + " has audible, unclipped samples")
	var output_peak := peak * db_to_linear(feedback.player.volume_db)
	check(output_peak > 0.01 and output_peak < 0.2, description + " stays at moderate output volume")
	check(pcm.decode_s16(0) == 0 and absi(pcm.decode_s16(pcm.size() - 2)) <= 2, description + " has smooth silent endpoints")


func test_playback() -> void:
	var player: AudioStreamPlayer = feedback.player
	check_wave(feedback.correct_sound, "Correct-answer sound")
	check_wave(feedback.wrong_sound, "Wrong-answer sound")
	check(feedback.correct_sound.data != feedback.wrong_sound.data, "Correct and wrong effects have different audio data")
	check(player.max_polyphony == 1 and feedback.get_child_count() == 1, "Feedback uses only one audio voice")
	check(not player.playing, "Feedback does not play at startup")
	var completions: Array[bool] = []
	player.finished.connect(func(): completions.append(true))
	feedback.play_correct()
	check(player.playing and player.stream == feedback.correct_sound, "Positive sound starts playback")
	await create_timer(0.35).timeout
	check(not player.playing and completions.size() == 1, "Positive sound finishes naturally")
	feedback.play_wrong()
	await create_timer(0.08).timeout
	var position := player.get_playback_position()
	check(position > 0.01, "Error sound advances through its samples")
	feedback.play_wrong()
	check(player.get_playback_position() >= position - 0.005, "Repeated error requests do not restart or stack the playing effect")
	feedback.play_correct()
	check(player.playing and player.stream == feedback.correct_sound, "An opposite result replaces the previous effect immediately")
	print("Feedback effects: positive %.2f s, error %.2f s, volume %.1f dB" % [feedback.correct_sound.get_length(), feedback.wrong_sound.get_length(), player.volume_db])


func wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while current_scene == null or current_scene.scene_file_path != path:
		if Time.get_ticks_msec() > deadline:
			push_error("Timed out waiting for " + path)
			quit(1)
			return
		await process_frame
	await process_frame
	await process_frame


func check_control_layout() -> void:
	for dimensions in [Vector2i(480, 480), Vector2i(720, 720), Vector2i(960, 720), Vector2i(720, 960), Vector2i(1280, 960)]:
		root.size = dimensions
		await create_timer(0.02, true, false, true).timeout
		var mute := current_scene.get_node("%Mute") as Button
		var button_rect := root.get_final_transform() * mute.get_global_rect()
		var content := current_scene.get_node("Center/Content") as Control
		var content_rect := root.get_final_transform() * content.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button_rect), "Mute control fits %s" % dimensions)
		check(not button_rect.intersects(content_rect), "Mute control does not overlap game content at %s" % dimensions)
	root.size = Vector2i(720, 720)


func finish_game() -> void:
	current_scene.get_node("%FinishGame").pressed.emit()
	await wait_for_scene("res://triangles.tscn")
	if current_scene.get_node("%NameDialog").visible:
		current_scene.get_node("%NameDialog").canceled.emit()


func test_answer_feedback() -> void:
	var player: AudioStreamPlayer = feedback.player
	var shared_player_id := player.get_instance_id()
	var flow := root.get_node("Flow")
	var saved_scores: Array = flow.high_scores.entries.duplicate(true)
	change_scene_to_file("res://triangles.tscn")
	await wait_for_scene("res://triangles.tscn")
	var menu_mute := current_scene.get_node("%Mute") as Button
	check(menu_mute.text == "Mute" and not menu_mute.button_pressed, "Main screen initially offers Mute")
	menu_mute.button_pressed = true
	check(feedback.muted and not player.playing and menu_mute.text == "Unmute", "Muting stops the current sound immediately and updates the button")
	feedback.play_wrong()
	feedback.play_correct()
	check(not player.playing, "Both effects stay silent while muted")
	await check_control_layout()

	Engine.time_scale = 30.0
	current_scene.get_node("%Start").pressed.emit()
	await wait_for_scene("res://math.tscn")
	var math_mute := current_scene.get_node("%Mute") as Button
	check(math_mute.text == "Unmute" and math_mute.button_pressed, "Mute state survives the arithmetic scene transition")
	await check_control_layout()
	var answer := current_scene.get_node("%Answer") as LineEdit
	answer.text = str(flow.left + flow.right + 1)
	current_scene.get_node("%Submit").pressed.emit()
	check(not player.playing, "Incorrect arithmetic is silent while muted")
	math_mute.button_pressed = false
	check(not feedback.muted and math_mute.text == "Mute", "Arithmetic-screen Unmute enables feedback")
	current_scene.get_node("%Submit").pressed.emit()
	check(player.playing and player.stream == feedback.wrong_sound, "Incorrect arithmetic plays the error sound")
	player.stop()
	answer.text = "not a number"
	answer.text_submitted.emit(answer.text)
	check(player.playing and player.stream == feedback.wrong_sound, "Invalid arithmetic input plays the error sound")
	answer.text = str(flow.left + flow.right)
	answer.text_submitted.emit(answer.text)
	check(player.playing and player.stream == feedback.correct_sound, "Correct arithmetic replaces the error sound with positive feedback")
	await wait_for_scene("res://triangles.tscn")
	check(feedback.player.get_instance_id() == shared_player_id and player.playing, "Accepted-answer audio survives the scene change")
	check(current_scene.get_node("%Mute").text == "Mute", "Unmuted state survives the recall scene transition")
	await check_control_layout()

	player.stop()
	var correct: int = flow.options.find(flow.original)
	current_scene.get_node("%Choices").get_child((correct + 1) % 4).pressed.emit()
	check(player.playing and player.stream == feedback.wrong_sound, "An incorrect sequence choice plays the error sound")
	check(flow.score == 0 and flow.consecutive_successes == 0, "Wrong-answer audio does not change score or streak rules")
	current_scene.get_node("%Mute").button_pressed = true
	check(not player.playing and feedback.muted, "Mute also stops error feedback during results")
	await finish_game()
	check(current_scene.get_node("%Mute").text == "Unmute", "Mute state survives Finish Game and return to the main screen")

	current_scene.get_node("%Start").pressed.emit()
	await wait_for_scene("res://math.tscn")
	current_scene.get_node("%Answer").text = str(flow.left + flow.right)
	current_scene.get_node("%Submit").pressed.emit()
	check(not player.playing, "Correct arithmetic also stays silent while muted")
	await wait_for_scene("res://triangles.tscn")
	current_scene.get_node("%Mute").button_pressed = false
	player.stop()
	correct = flow.options.find(flow.original)
	var chosen := current_scene.get_node("%Choices").get_child(correct) as Button
	chosen.pressed.emit()
	check(player.playing and player.stream == feedback.correct_sound, "A correct sequence choice plays positive feedback")
	check(flow.score == 10 and flow.consecutive_successes == 1 and flow.sequence_length == 2, "Positive feedback preserves score and difficulty rules")
	feedback.play_wrong()
	chosen.pressed.emit()
	check(player.stream == feedback.wrong_sound and flow.score == 10, "Ignored duplicate choices do not emit accepted-answer feedback")
	player.stop()
	await finish_game()
	check(flow.high_scores.entries == saved_scores, "Feedback and mute tests leave the leaderboard unchanged")
	current_scene.get_node("%Mute").button_pressed = true
	feedback.play_correct()
	check(not player.playing, "Muted requests do not queue a sound")
	current_scene.get_node("%Mute").button_pressed = false
	check(not player.playing, "Unmuting does not replay discarded requests")
	Engine.time_scale = 1.0


func _run() -> void:
	feedback = root.get_node("FeedbackAudio")
	await test_playback()
	await test_answer_feedback()
	# Let the audio mixer release stopped playbacks before this test exits.
	paused = true
	feedback.player.stop()
	feedback.player.stream = null
	await create_timer(0.1, true, false, true).timeout
	print("PASS: generated moderate-volume effects, natural playback completion, no stacked/restarted repeats, correct/wrong arithmetic and recall triggers, cross-scene audio, mute/unmute, and control layout" if failures.is_empty() else "FAIL: %d checks" % failures.size())
	quit(0 if failures.is_empty() else 1)
