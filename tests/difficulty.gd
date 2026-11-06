extends SceneTree
const Session = preload("res://flow.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func play_round(session: Node, success: bool) -> void:
	if session.stage != session.Stage.MEMORIZE:
		check(session.start_round(), "The next model round starts")
	check(session.original.size() == session.sequence_length, "Generated sequence length follows difficulty")
	session._prepare_options()
	check(session.options.size() == 4, "Every difficulty has four recall choices")
	var seen := {}
	var correct_index := -1
	for index in range(session.options.size()):
		var candidate: Array = session.options[index]
		seen[str(candidate)] = true
		check(candidate.size() == session.sequence_length, "Every recall choice has the current length")
		for color in candidate:
			check(color in [0, 1, 2], "Long sequences reuse only the existing colors")
		if candidate == session.original:
			correct_index = index
	check(seen.size() == 4 and correct_index >= 0, "Recall choices remain unique and include the correct sequence")
	session.stage = session.Stage.RECALL
	var score_before: int = session.score
	var streak_before: int = session.consecutive_successes
	check(not session.choose(-1) and session.consecutive_successes == streak_before, "Invalid recall input does not count as failure")
	var chosen := correct_index if success else (correct_index + 1) % 4
	check(session.choose(chosen) == success, "Recall outcome is unchanged")
	check(session.score == score_before + (10 if success else 0), "Difficulty changes preserve the ten-point scoring rule")
	var after := [session.score, session.sequence_length, session.consecutive_successes, session.display_time]
	check(not session.choose(chosen), "Duplicate recall events are rejected")
	check(after == [session.score, session.sequence_length, session.consecutive_successes, session.display_time], "Duplicate events cannot advance difficulty or reset the streak")


func test_progression() -> void:
	var session := Session.new()
	root.add_child(session)
	var saved_scores: Array = session.high_scores.entries.duplicate(true)
	check(session.sequence_length == 2 and session.difficulty_level == 1 and session.display_time == 3.0, "Initial length, level, and display time are preserved")
	play_round(session, true)
	play_round(session, true)
	check(session.sequence_length == 2 and session.consecutive_successes == 2 and session.display_time == 3.0, "Two successes do not raise difficulty")
	play_round(session, false)
	check(session.consecutive_successes == 0 and session.sequence_length == 2 and session.display_time == 3.0, "An early failure resets only the streak")
	for attempt in range(3):
		play_round(session, true)
	check(session.sequence_length == 3 and session.difficulty_level == 2 and is_equal_approx(session.display_time, 2.9), "The third consecutive success adds one triangle and removes 0.1 seconds")
	check(session.consecutive_successes == 0, "Each difficulty increase starts a fresh success streak")
	play_round(session, true)
	play_round(session, true)
	play_round(session, false)
	check(session.sequence_length == 3 and session.difficulty_level == 2 and is_equal_approx(session.display_time, 2.9) and session.consecutive_successes == 0, "A later failure keeps the increased difficulty and speed")
	play_round(session, true)
	play_round(session, true)
	check(session.sequence_length == 3, "Wins separated by failure do not combine into a promotion")
	play_round(session, true)
	check(session.sequence_length == 4 and session.difficulty_level == 3 and is_equal_approx(session.display_time, 2.8), "A new three-win streak raises difficulty again")

	# Reset the session, then exercise the floor and continued length growth.
	session.stage = session.Stage.MENU
	check(session.start_round(), "A fresh session can start")
	check(session.sequence_length == 2 and session.consecutive_successes == 0 and session.score == 0 and session.display_time == 3.0, "New games reset progression and retain the original initial timing")
	for wins in range(1, 91):
		play_round(session, true)
		check(session.display_time >= 0.5, "Display time never falls below half a second")
		if wins == 72:
			check(session.sequence_length == 26 and is_equal_approx(session.display_time, 0.6), "The last step before the time floor is 0.6 seconds")
		if wins == 75:
			check(session.sequence_length == 27 and session.display_time == 0.5, "The twenty-fifth promotion reaches exactly 0.5 seconds")
		if wins == 90:
			check(session.sequence_length == 32 and session.difficulty_level == 31 and session.display_time == 0.5, "Sequence length continues increasing while time stays clamped")
	check(session.score == 900, "Ninety successful rounds still score 900 points")
	play_round(session, false)
	check(session.sequence_length == 32 and session.display_time == 0.5 and session.consecutive_successes == 0 and session.score == 900, "Failure at the time floor keeps difficulty, timing, and score")
	check(session.high_scores.entries == saved_scores, "Round progression does not mutate the saved leaderboard")
	session.free()


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


func test_floor_in_game() -> void:
	var flow := root.get_node("Flow")
	# Use a high-level result state to exercise the real half-second timer.
	flow.stage = flow.Stage.RESULT
	flow.sequence_length = 27
	flow.consecutive_successes = 2
	change_scene_to_file("res://triangles.tscn")
	await wait_for_scene("res://triangles.tscn")
	var started_at := Time.get_ticks_msec()
	current_scene.get_node("%Start").pressed.emit()
	check(flow.original.size() == 27 and current_scene.get_node("%Memory").order.size() == 27, "The real scene displays the full high-difficulty sequence")
	check(current_scene.get_node("%MemoryTimer").wait_time == 0.5, "The real memorization timer uses the clamped display duration")
	check(current_scene.get_node("%Round").text.contains("DIFFICULTY 26"), "The triangle screen shows the current difficulty")
	await create_timer(0.35).timeout
	check(flow.stage == flow.Stage.MEMORIZE and current_scene.get_node("%Memory").visible, "The sequence remains visible before the half-second limit")
	await wait_for_scene("res://math.tscn")
	var duration := Time.get_ticks_msec() - started_at
	check(duration >= 450 and duration < 1500, "High-level memorization ends after approximately half a second")
	print("Minimum display duration: %d ms" % duration)
	check(current_scene.get_node("%Round").text.contains("DIFFICULTY 26"), "The arithmetic screen also shows the current difficulty")
	current_scene.get_node("%Answer").text = str(flow.left + flow.right)
	current_scene.get_node("%Submit").pressed.emit()
	await wait_for_scene("res://triangles.tscn")
	var correct_index: int = flow.options.find(flow.original)
	current_scene.get_node("%Choices").get_child((correct_index + 1) % 4).pressed.emit()
	check(flow.consecutive_successes == 0 and flow.sequence_length == 27 and flow.display_time == 0.5, "An actual failed recall resets the streak without lowering difficulty")
	check(current_scene.get_node("%NextRoundTimer").wait_time == 2.0, "The automatic transition pause remains two seconds")
	await create_timer(1.0).timeout
	check(flow.stage == flow.Stage.RESULT, "Failed high-level rounds still show their result before advancing")
	var expected_round: int = flow.round_number + 1
	var deadline := Time.get_ticks_msec() + 4000
	while flow.round_number < expected_round:
		if Time.get_ticks_msec() > deadline:
			push_error("High-level round did not progress automatically")
			quit(1)
			return
		await process_frame
	check(flow.round_number == expected_round and flow.sequence_length == 27 and current_scene.get_node("%MemoryTimer").wait_time == 0.5, "Automatic progression keeps the failed round's difficulty and time floor")
	current_scene.get_node("%FinishGame").pressed.emit()
	await wait_for_scene("res://triangles.tscn")
	current_scene.get_node("%Start").pressed.emit()
	check(flow.difficulty_level == 1 and flow.sequence_length == 2 and flow.display_time == 3.0 and current_scene.get_node("%MemoryTimer").wait_time == 3.0, "The next game restores the original three-second starting timer")
	current_scene.get_node("%FinishGame").pressed.emit()
	await wait_for_scene("res://triangles.tscn")


func _run() -> void:
	test_progression()
	await test_floor_in_game()
	print("PASS: three-win progression, variable-length sequences and choices, failure streak reset, unchanged scoring, half-second time floor, difficulty labels, automatic transitions, and new-game reset" if failures.is_empty() else "FAIL: %d checks" % failures.size())
	quit(0 if failures.is_empty() else 1)
