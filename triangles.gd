extends Control
const Visuals = preload("res://visuals.gd")
const Strip = preload("res://triangle_strip.gd")
@onready var subtitle: Label = %Subtitle
@onready var memory: Control = %Memory
@onready var choices: GridContainer = %Choices
@onready var feedback: Label = %Feedback
@onready var start: Button = %Start
@onready var memory_timer: Timer = %MemoryTimer
@onready var next_round_timer: Timer = %NextRoundTimer
@onready var high_scores_panel: PanelContainer = %HighScoresPanel
@onready var name_dialog: ConfirmationDialog = %NameDialog
@onready var player_name: LineEdit = %PlayerName


func _ready() -> void:
	Visuals.apply(self)
	start.pressed.connect(_start_round)
	%FinishGame.pressed.connect(Flow.finish_game)
	name_dialog.confirmed.connect(_save_high_score)
	name_dialog.canceled.connect(_skip_high_score)
	player_name.text_submitted.connect(func(_text: String): _save_high_score())
	high_scores_panel.add_theme_stylebox_override("panel", Visuals.box("1c2a36", "334657"))
	_update_high_scores()
	memory_timer.timeout.connect(_finish_memorizing)
	next_round_timer.timeout.connect(_start_round)
	memory.hide()
	choices.hide()
	if Flow.stage == Flow.Stage.RECALL:
		_show_choices()
	else:
		if Flow.stage == Flow.Stage.ENDED:
			Flow.stage = Flow.Stage.MENU
			%Round.text = "FINAL SCORE: %d  /  DIFFICULTY %d" % [Flow.score, Flow.difficulty_level]
		else:
			%Round.text = "DIFFICULTY 1  /  2 TRIANGLES  /  3.0 SECONDS"
		subtitle.text = "Remember the colors. Solve a sum. Recall the order."
		feedback.text = "Start with 2 triangles shown for 3 seconds."
		start.text = "Start Game"
		start.disabled = Flow.pending_score > 0
		if Flow.pending_score > 0:
			%NamePrompt.text = "You scored %d points! Enter your name:" % Flow.pending_score
			name_dialog.popup_centered()
			player_name.grab_focus()
		else:
			start.grab_focus()


func _start_round() -> void:
	if not next_round_timer.is_stopped() or not Flow.start_round():
		return
	high_scores_panel.hide()
	%FinishGame.show()
	%Round.text = "ROUND %d  /  MEMORIZE  /  SCORE %d  /  DIFFICULTY %d" % [Flow.round_number, Flow.score, Flow.difficulty_level]
	subtitle.text = "Remember this order from left to right."
	feedback.text = "You have %.1f seconds." % Flow.display_time
	feedback.modulate = Color.WHITE
	for child in choices.get_children():
		child.queue_free()
	choices.hide()
	start.hide()
	memory.set_order(Flow.original)
	memory.show()
	memory_timer.start(Flow.display_time)


func _finish_memorizing() -> void:
	if Flow.stage != Flow.Stage.MEMORIZE:
		return
	memory.hide()
	Flow.show_math()


func _show_choices() -> void:
	high_scores_panel.hide()
	%FinishGame.show()
	%Round.text = "ROUND %d  /  RECALL  /  SCORE %d  /  DIFFICULTY %d" % [Flow.round_number, Flow.score, Flow.difficulty_level]
	subtitle.text = "Which sequence did you see?"
	feedback.text = "Choose the original order from left to right."
	start.hide()
	choices.show()
	for index in range(Flow.options.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(258, 142)
		button.tooltip_text = "Sequence %d" % (index + 1)
		button.accessibility_name = "Sequence %d" % (index + 1)
		var strip := Control.new()
		strip.set_script(Strip)
		button.add_child(strip)
		strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		strip.offset_left = 12
		strip.offset_right = -12
		strip.set_order(Flow.options[index])
		button.pressed.connect(_choose.bind(index))
		choices.add_child(button)
	(choices.get_child(0) as Button).grab_focus()


func _choose(index: int) -> void:
	if Flow.stage != Flow.Stage.RECALL:
		return
	var previous_level: int = Flow.difficulty_level
	var correct := Flow.choose(index)
	if correct:
		FeedbackAudio.play_correct()
	else:
		FeedbackAudio.play_wrong()
	choices.hide()
	for button in choices.get_children():
		button.disabled = true
	feedback.text = "Correct! You remembered the sequence." if correct else "Incorrect. The original sequence is shown below."
	if Flow.difficulty_level > previous_level:
		feedback.text = "Correct! Next round: %d triangles, %.1f seconds." % [Flow.sequence_length, Flow.display_time]
	feedback.modulate = Color("83d5aa") if correct else Color("f19baa")
	%Round.text = "ROUND %d  /  COMPLETE  /  SCORE %d  /  DIFFICULTY %d" % [Flow.round_number, Flow.score, Flow.difficulty_level]
	memory.set_order(Flow.original)
	memory.show()
	start.hide()
	subtitle.text = "Next round starts in 2 seconds."
	next_round_timer.start()


func _update_high_scores() -> void:
	var rows: GridContainer = %LeaderboardRows
	for rank in range(3):
		var entry: Dictionary = Flow.high_scores.entries[rank] if rank < Flow.high_scores.entries.size() else {}
		var player := rows.get_node("Name%d" % rank) as Label
		var points := rows.get_node("Points%d" % rank) as Label
		player.text = "%d. %s" % [rank + 1, entry.get("name", "—")]
		player.tooltip_text = str(entry.get("name", ""))
		points.text = str(entry["score"]) if not entry.is_empty() else "—"


func _save_high_score() -> void:
	if Flow.pending_score <= 0:
		return
	var error := Flow.submit_high_score(player_name.text)
	if error != OK:
		%NameError.text = "Could not save your score. Try again or choose Skip."
		%NameError.show()
		return
	name_dialog.hide()
	_update_high_scores()
	feedback.text = "Your score has been saved."
	start.disabled = false
	start.grab_focus()


func _skip_high_score() -> void:
	Flow.skip_high_score()
	name_dialog.hide()
	start.disabled = false
	start.grab_focus()
