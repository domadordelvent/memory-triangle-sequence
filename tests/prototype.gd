extends SceneTree
## godot --path . --script tests/prototype.gd
var failures: Array[String] = []
var flow: Node


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


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


func wait_for_round(number: int) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while flow.round_number < number:
		if Time.get_ticks_msec() > deadline:
			push_error("Timed out waiting for automatic round %d" % number)
			quit(1)
			return
		await process_frame
	check(flow.round_number == number, "Automatic progression starts exactly one next round")


func check_layout() -> void:
	for dimensions in [Vector2i(480, 480), Vector2i(720, 720), Vector2i(960, 720), Vector2i(720, 960), Vector2i(1280, 960)]:
		root.size = dimensions
		await create_timer(0.05, true, false, true).timeout
		var content := current_scene.get_node("Center/Content") as Control
		var physical := root.get_final_transform() * content.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(physical), "Content fits %s during %s" % [dimensions, flow.stage])


func _run() -> void:
	flow = root.get_node("Flow")
	change_scene_to_file("res://triangles.tscn")
	await wait_for_scene("res://triangles.tscn")
	check(flow.stage == flow.Stage.MENU, "Game waits for Start Game")
	check(current_scene.get_node("%Start").text == "Start Game", "Start button label")
	await check_layout()
	root.size = Vector2i(720, 720)
	current_scene.get_node("%Start").pressed.emit()
	var original: Array = flow.original.duplicate()
	check(original.size() == 2 and flow.difficulty_level == 1, "Games start with two triangles at difficulty one")
	check(current_scene.get_node("%Memory").order == original, "All original triangles displayed together")
	check(current_scene.get_node("%MemoryTimer").wait_time == 3.0, "Memorization lasts three seconds")
	current_scene.get_node("%Start").pressed.emit()
	check(not flow.start_round(), "An active round rejects another round start")
	check(flow.round_number == 1 and flow.original == original, "Repeated Start input cannot reset the round")
	await create_timer(2.8).timeout
	check(flow.stage == flow.Stage.MEMORIZE, "Still memorizing before three seconds")
	await wait_for_scene("res://math.tscn")
	check(flow.original == original, "Original sequence survives scene transition")
	await check_layout()
	var sequences := {}
	var questions := {}
	var expected_score := 0
	var outcomes: Array[bool] = [true, true, true, false, true, true, false, true, true, true, false, true]
	for round_index in range(12):
		var math := current_scene
		var answer := math.get_node("%Answer") as LineEdit
		var streak_before: int = flow.consecutive_successes
		answer.text = "not a number"
		answer.text_submitted.emit(answer.text)
		check(flow.stage == flow.Stage.MATH and not math.get_node("%Feedback").text.is_empty(), "Non-numeric input allows retry")
		answer.text = str(flow.left + flow.right + 1)
		math.get_node("%Submit").pressed.emit()
		check(flow.stage == flow.Stage.MATH, "Wrong arithmetic keeps same question")
		check(flow.consecutive_successes == streak_before, "Arithmetic retries do not reset the recall streak")
		questions["%d+%d" % [flow.left, flow.right]] = true
		sequences[str(flow.original)] = true
		answer.text = str(flow.left + flow.right)
		answer.text_submitted.emit(answer.text)
		await wait_for_scene("res://triangles.tscn")
		check(flow.stage == flow.Stage.RECALL, "Correct arithmetic unlocks recall")
		check(not current_scene.get_node("%Memory").visible, "Original is hidden during recall")
		check(flow.options.size() == 4, "Exactly four choices")
		var matches := 0
		var unique := {}
		var correct_index := -1
		for index in range(flow.options.size()):
			unique[str(flow.options[index])] = true
			var candidate: Array = flow.options[index]
			check(candidate.size() == flow.original.size(), "Choices match the current sequence length")
			for color in candidate:
				check(color in [0, 1, 2], "Choices use the existing triangle colors")
			if candidate.size() >= 3:
				var sorted: Array = candidate.duplicate()
				var sorted_original: Array = flow.original.duplicate()
				sorted.sort()
				sorted_original.sort()
				check(sorted == sorted_original, "Longer choices preserve the original color counts")
			if flow.options[index] == flow.original:
				matches += 1
				correct_index = index
		check(matches == 1 and unique.size() == 4, "Exactly one correct, four unique options")
		if round_index == 0:
			await check_layout()
		var selected := correct_index if outcomes[round_index] else (correct_index + 1) % 4
		if selected == correct_index:
			expected_score += 10
		var completed_round: int = flow.round_number
		var completed_at := Time.get_ticks_msec()
		current_scene.get_node("%Choices").get_child(selected).pressed.emit()
		check(flow.stage == flow.Stage.RESULT, "Choice completes the round")
		check(flow.score == expected_score, "Correct recall earns ten points; incorrect recall leaves the score unchanged")
		check(current_scene.get_node("%Feedback").text.begins_with("Correct!" if outcomes[round_index] else "Incorrect."), "Clear success/failure feedback")
		check(current_scene.get_node("%Memory").order == flow.original, "Result shows original sequence")
		check(not current_scene.get_node("%Start").visible, "No Next Round button is needed after either outcome")
		var next_round_timer := current_scene.get_node("%NextRoundTimer") as Timer
		check(next_round_timer.wait_time == 2.0 and not next_round_timer.is_stopped(), "Either recall outcome schedules a two-second transition")
		var remaining := next_round_timer.time_left
		for button in current_scene.get_node("%Choices").get_children():
			(button as Button).pressed.emit()
		current_scene.get_node("%Start").pressed.emit()
		check(flow.round_number == completed_round and flow.stage == flow.Stage.RESULT, "Repeated result input cannot skip the pause")
		check(is_equal_approx(next_round_timer.time_left, remaining), "Repeated recall signals do not restart the result timer")
		if round_index == 0:
			await check_layout()
			await create_timer(1.0).timeout
			check(flow.stage == flow.Stage.RESULT and flow.round_number == completed_round, "Result remains visible before two seconds")
			current_scene.get_node("%Choices").get_child(selected).pressed.emit()
			current_scene.get_node("%Start").pressed.emit()
			check(flow.stage == flow.Stage.RESULT and flow.round_number == completed_round, "Late repeated input still cannot skip the pause")
		if round_index < 11:
			await wait_for_round(completed_round + 1)
			check(flow.stage == flow.Stage.MEMORIZE, "Automatic progression enters memorization")
			check(current_scene.get_node("%Memory").visible, "Automatic progression displays the new sequence")
			check(is_equal_approx(current_scene.get_node("%MemoryTimer").wait_time, flow.display_time), "Automatic rounds use the current difficulty display time")
			var next_original: Array = flow.original.duplicate()
			var memory_time_left: float = current_scene.get_node("%MemoryTimer").time_left
			current_scene.get_node("%Start").pressed.emit()
			next_round_timer.timeout.emit()
			next_round_timer.timeout.emit()
			check(not flow.start_round(), "Active automatic rounds reject competing starts")
			check(flow.round_number == completed_round + 1 and flow.original == next_original, "Duplicate callbacks cannot start simultaneous rounds")
			check(is_equal_approx(current_scene.get_node("%MemoryTimer").time_left, memory_time_left), "Duplicate starts cannot reset memorization")
			if round_index == 0:
				var transition_msec := Time.get_ticks_msec() - completed_at
				check(transition_msec >= 1900 and transition_msec < 2800, "Next round starts after two seconds without a click or timer reset")
				print("Automatic transition delay: %d ms" % transition_msec)
				await create_timer(2.8).timeout
				check(flow.stage == flow.Stage.MEMORIZE, "Automatic sequence stays visible for the full memorization period")
			await wait_for_scene("res://math.tscn")
			if round_index == 0:
				Engine.time_scale = 30.0
	check(sequences.size() > 1 and questions.size() > 1, "Orders and sums vary across rounds")
	check(flow.round_number == 12, "Repeated rounds remain playable")
	print("PASS: two-second automatic progression after both outcomes, no overlapping rounds, initial three-second memorization, adaptive difficulty, arithmetic retries, state across two scenes, unique options, randomized rounds, and responsive layouts" if failures.is_empty() else "FAIL: %d checks" % failures.size())
	# Drain the new feedback audio before this test shuts down the mixer.
	paused = true
	var audio := root.get_node("FeedbackAudio")
	audio.player.stop()
	audio.player.stream = null
	await create_timer(0.1, true, false, true).timeout
	quit(0 if failures.is_empty() else 1)
