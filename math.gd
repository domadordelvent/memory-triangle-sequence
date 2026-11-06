extends Control
const Visuals = preload("res://visuals.gd")
@onready var answer: LineEdit = %Answer
@onready var feedback: Label = %Feedback


func _ready() -> void:
	Visuals.apply(self)
	%Submit.pressed.connect(_submit)
	%FinishGame.pressed.connect(Flow.finish_game)
	answer.text_submitted.connect(func(_text: String): _submit())
	if Flow.stage != Flow.Stage.MATH:
		Flow.stage = Flow.Stage.MENU
		get_tree().change_scene_to_file.call_deferred("res://triangles.tscn")
		return
	%Round.text = "ROUND %d  /  MATH  /  SCORE %d  /  DIFFICULTY %d" % [Flow.round_number, Flow.score, Flow.difficulty_level]
	%Question.text = "%d + %d = ?" % [Flow.left, Flow.right]
	answer.grab_focus()


func _submit() -> void:
	if Flow.stage != Flow.Stage.MATH:
		return
	if Flow.submit_answer(answer.text):
		FeedbackAudio.play_correct()
		%Submit.disabled = true
		answer.editable = false
	else:
		FeedbackAudio.play_wrong()
		feedback.text = "Not quite. Try again." if answer.text.strip_edges().is_valid_int() else "Enter a whole number, then press Enter."
		feedback.modulate = Color("f19baa")
		answer.grab_focus()
		answer.select_all()
