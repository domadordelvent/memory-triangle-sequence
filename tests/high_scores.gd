extends SceneTree
## Uses uniquely named test files; never replaces the player's high_scores.cfg.
const Scores = preload("res://high_scores.gd")
var failures: Array[String] = []
var flow: Node
var prefix: String
var test_files: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func test_path(suffix: String) -> String:
	var path := prefix + suffix + ".cfg"
	test_files.append(path)
	return path


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


func complete_round() -> void:
	await wait_for_scene("res://math.tscn")
	var answer := current_scene.get_node("%Answer") as LineEdit
	answer.text = str(flow.left + flow.right)
	answer.text_submitted.emit(answer.text)
	await wait_for_scene("res://triangles.tscn")
	var correct: int = flow.options.find(flow.original)
	check(correct >= 0, "Recall contains the original sequence")
	current_scene.get_node("%Choices").get_child(correct).pressed.emit()


func finish_from_button() -> void:
	current_scene.get_node("%FinishGame").pressed.emit()
	check(not flow.finish_game(), "Repeated Finish Game requests are ignored")
	await wait_for_scene("res://triangles.tscn")
	check(flow.stage == flow.Stage.MENU, "Finishing returns to the main screen")
	check(current_scene.get_node("%HighScoresPanel").visible, "Top 3 is visible on the main screen")
	check(not current_scene.get_node("%FinishGame").visible, "Finished games cannot be finished again")


func check_menu_layout() -> void:
	for dimensions in [Vector2i(480, 480), Vector2i(720, 720), Vector2i(960, 720), Vector2i(720, 960), Vector2i(1280, 960)]:
		root.size = dimensions
		await create_timer(0.03, true, false, true).timeout
		var content := current_scene.get_node("Center/Content") as Control
		var physical := root.get_final_transform() * content.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(physical), "Leaderboard fits the main screen at %s" % dimensions)
	root.size = Vector2i(720, 720)


func test_ranking() -> String:
	var path := test_path("ranking")
	var scores := Scores.new(path)
	check(scores.entries.is_empty() and scores.load_error == OK, "Missing save starts with an empty leaderboard")
	check(not scores.qualifies(0) and not scores.qualifies(-1), "Only positive scores qualify")
	check(scores.record("Ada", 10) == OK, "First score saves")
	check(scores.record("Lin", 30) == OK, "Higher score saves")
	check(scores.record("Bea", 20) == OK, "Middle score saves")
	check(scores.entries == [{"name": "Lin", "score": 30}, {"name": "Bea", "score": 20}, {"name": "Ada", "score": 10}], "Entries rank from highest to lowest")
	var before := FileAccess.get_file_as_string(path)
	check(not scores.qualifies(10) and scores.record("Tie at cutoff", 10) == ERR_INVALID_PARAMETER, "A tie cannot displace third place on a full board")
	check(FileAccess.get_file_as_string(path) == before, "Rejected scores leave the saved leaderboard unchanged")
	check(scores.record("Eve", 30) == OK, "A tied higher score can replace a lower score")
	check(scores.entries == [{"name": "Lin", "score": 30}, {"name": "Eve", "score": 30}, {"name": "Bea", "score": 20}], "Earlier equal scores rank first")
	check(scores.record("Grace", 40) == OK and scores.entries.size() == 3, "Only the highest three scores are retained")
	check(Scores.new(path).entries == scores.entries, "Fresh instances load all saved names, scores, and tie order")
	return path


func test_validation() -> void:
	var scores := Scores.new(test_path("names"))
	check(scores.record("   \n\t ", 10) == OK and scores.entries[0]["name"] == "Player", "Blank names use Player")
	check(scores.record(" W".repeat(20) + "\nName\t", 20) == OK, "Long names can be saved")
	var name: String = scores.entries[0]["name"]
	check(name.length() <= 24 and not name.contains("\n") and not name.contains("\t"), "Names are bounded and kept on one line")

	var path := test_path("invalid")
	var save := ConfigFile.new()
	save.set_value("scores", "top_three", [
		{"name": "First tie", "score": 40}, {"name": "Second tie", "score": 40},
		{"name": "Lower", "score": 5}, {"name": "Higher", "score": 70},
		{"name": "Negative", "score": -2}, {"name": "Text score", "score": "90"},
		{"name": 17, "score": 80}, {"score": 100}, "bad entry"
	])
	check(save.save(path) == OK, "Malformed-entry fixture saves")
	var loaded := Scores.new(path)
	check(loaded.entries == [{"name": "Higher", "score": 70}, {"name": "First tie", "score": 40}, {"name": "Second tie", "score": 40}], "Loading filters invalid entries, sorts, trims, and preserves ties")
	save.set_value("scores", "top_three", "invalid leaderboard")
	check(save.save(path) == OK, "Malformed-container fixture saves")
	loaded = Scores.new(path)
	check(loaded.entries.is_empty() and loaded.load_error == ERR_INVALID_DATA, "Malformed leaderboard data is handled without crashing")


func test_ui() -> void:
	flow = root.get_node("Flow")
	var path := test_path("ui")
	flow.high_scores = Scores.new(path)
	Engine.time_scale = 30.0
	change_scene_to_file("res://triangles.tscn")
	await wait_for_scene("res://triangles.tscn")
	check(current_scene.get_node("%HighScoresPanel").visible, "Empty Top 3 is shown before starting")
	await check_menu_layout()

	# Complete and finish a qualifying game from its result screen.
	current_scene.get_node("%Start").pressed.emit()
	check(not current_scene.get_node("%HighScoresPanel").visible, "Leaderboard does not displace the active round layout")
	await complete_round()
	check(flow.score == 10, "Correct recall earns ten points")
	await finish_from_button()
	var dialog := current_scene.get_node("%NameDialog") as ConfirmationDialog
	check(dialog.visible and flow.pending_score == 10, "Qualifying finished games ask for a player name")
	current_scene.get_node("%Start").pressed.emit()
	check(flow.round_number == 1 and flow.score == 10, "Name entry blocks competing new-game input")

	# A failed save keeps the prompt and score available for retry.
	flow.high_scores.storage_path = prefix + "missing/high_scores.cfg"
	current_scene.get_node("%PlayerName").text = " Ada "
	dialog.confirmed.emit()
	check(dialog.visible and current_scene.get_node("%NameError").visible, "Save errors remain visible with a retry option")
	check(flow.pending_score == 10 and flow.high_scores.entries.is_empty(), "Save failures do not consume or duplicate the score")
	flow.high_scores.storage_path = path
	dialog.confirmed.emit()
	check(not dialog.visible and flow.pending_score == 0, "Successful save closes the name dialog")
	check(not current_scene.get_node("%Start").disabled, "New games are available after saving")
	check(flow.high_scores.entries == [{"name": "Ada", "score": 10}], "Entered name and final score are recorded")
	dialog.confirmed.emit()
	check(flow.high_scores.entries.size() == 1 and flow.submit_high_score("Again") == ERR_UNAVAILABLE, "Each finished game can be submitted only once")

	# Skipping a qualifying score does not save a second entry.
	current_scene.get_node("%Start").pressed.emit()
	check(flow.score == 0 and flow.round_number == 1, "Starting a new game resets only the session counters")
	await complete_round()
	await finish_from_button()
	current_scene.get_node("%NameDialog").canceled.emit()
	check(flow.pending_score == 0 and flow.high_scores.entries.size() == 1, "Skip leaves existing scores unchanged")

	# Finish from the arithmetic scene after an automatic round transition.
	current_scene.get_node("%Start").pressed.emit()
	await complete_round()
	await wait_for_scene("res://math.tscn")
	check(flow.round_number == 2 and flow.score == 10, "Automatic transitions preserve the session score")
	await finish_from_button()
	check(current_scene.get_node("%NameDialog").visible, "Finish Game also prompts from the arithmetic scene")
	current_scene.get_node("%PlayerName").text = ""
	current_scene.get_node("%PlayerName").text_submitted.emit("")
	check(flow.high_scores.entries == [{"name": "Ada", "score": 10}, {"name": "Player", "score": 10}], "Blank names and tied session scores are handled consistently")

	# A two-round game ranks above the earlier games.
	current_scene.get_node("%Start").pressed.emit()
	await complete_round()
	await complete_round()
	check(flow.score == 20, "The score accumulates across automatic rounds")
	await finish_from_button()
	current_scene.get_node("%PlayerName").text = "Bea"
	current_scene.get_node("%NameDialog").confirmed.emit()
	var expected := [{"name": "Bea", "score": 20}, {"name": "Ada", "score": 10}, {"name": "Player", "score": 10}]
	check(flow.high_scores.entries == expected, "Named finished games form the expected Top 3")
	check(Scores.new(path).entries == expected, "Named games survive a complete model reload")
	var rows := current_scene.get_node("%LeaderboardRows")
	check(rows.get_node("Name0").text == "1. Bea" and rows.get_node("Points0").text == "20", "Main screen displays first-place name and points")
	check(rows.get_node("Name1").text == "2. Ada" and rows.get_node("Points2").text == "10", "Main screen displays the remaining ranked scores")
	await check_menu_layout()

	# Ties at a full cutoff and zero-score sessions do not prompt.
	current_scene.get_node("%Start").pressed.emit()
	await complete_round()
	await finish_from_button()
	check(not current_scene.get_node("%NameDialog").visible and flow.pending_score == 0, "Nonqualifying scores do not open name entry")
	check(flow.high_scores.entries == expected, "A tied cutoff leaves the Top 3 unchanged")
	current_scene.get_node("%Start").pressed.emit()
	await finish_from_button()
	check(not current_scene.get_node("%NameDialog").visible and flow.score == 0, "Zero-score games do not qualify")
	await create_timer(0.15, true, false, true).timeout
	check(flow.stage == flow.Stage.MENU, "Finishing cancels old memorization and automatic-transition timers")
	check(flow.high_scores.entries == expected, "Finishing without qualification preserves the leaderboard")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 2 and arguments[0] == "--verify":
		var loaded := Scores.new(arguments[1])
		check(loaded.entries == [{"name": "Grace", "score": 40}, {"name": "Lin", "score": 30}, {"name": "Eve", "score": 30}], "Scores and deterministic ties survive a fresh Godot process")
		print("PASS: leaderboard persisted across a fresh Godot process" if failures.is_empty() else "FAIL: restart persistence")
		quit(0 if failures.is_empty() else 1)
		return

	prefix = "user://high_scores_test_%d_" % OS.get_process_id()
	var ranking_path := test_ranking()
	test_validation()
	await test_ui()
	Engine.time_scale = 1.0
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "tests/high_scores.gd", "--", "--verify", ranking_path], output, true)
	for line in output:
		print(str(line).strip_edges())
	check(exit_code == 0, "A fresh Godot process reloads the persisted Top 3")
	for path in test_files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PASS: Top 3 ranking, tie policy, local save/load, names, invalid data, save retry, one submission per game, main-screen display, and Finish Game from both scenes" if failures.is_empty() else "FAIL: %d checks" % failures.size())
	quit(0 if failures.is_empty() else 1)
