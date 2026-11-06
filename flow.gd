extends Node
## The two scenes share round state through this lightweight autoload.
const HighScores = preload("res://high_scores.gd")
enum Stage { MENU, MEMORIZE, MATH, RECALL, RESULT, ENDED }
const INITIAL_SEQUENCE_LENGTH := 2
const INITIAL_DISPLAY_TIME := 3.0
const MIN_DISPLAY_TIME := 0.5
const DISPLAY_TIME_STEP := 0.1
const SUCCESSES_PER_LEVEL := 3
var stage: Stage = Stage.MENU
var original: Array[int] = []
var options: Array = []
var left: int = 0
var right: int = 0
var round_number: int = 0
var score: int = 0
var sequence_length: int = INITIAL_SEQUENCE_LENGTH
var consecutive_successes: int = 0
var difficulty_level: int:
	get:
		return sequence_length - INITIAL_SEQUENCE_LENGTH + 1
var display_time: float:
	get:
		return maxf(MIN_DISPLAY_TIME, INITIAL_DISPLAY_TIME - (difficulty_level - 1) * DISPLAY_TIME_STEP)
var pending_score: int = 0
var high_scores := HighScores.new()


func _ready() -> void:
	if high_scores.load_error != OK:
		push_warning("Could not load high scores; starting with an empty leaderboard.")


func start_round() -> bool:
	if pending_score > 0 or (stage != Stage.MENU and stage != Stage.RESULT):
		return false
	if stage == Stage.MENU:
		score = 0
		round_number = 0
		sequence_length = INITIAL_SEQUENCE_LENGTH
		consecutive_successes = 0
	round_number += 1
	original.clear()
	# Reuse the three colors in shuffled groups as the sequence grows.
	while original.size() < sequence_length:
		var colors: Array[int] = [0, 1, 2]
		colors.shuffle()
		for color in colors:
			original.append(color)
			if original.size() == sequence_length:
				break
	left = randi_range(1, 9)
	right = randi_range(1, 9)
	options.clear()
	stage = Stage.MEMORIZE
	return true


func show_math() -> void:
	stage = Stage.MATH
	get_tree().change_scene_to_file("res://math.tscn")


func submit_answer(text: String) -> bool:
	var value := text.strip_edges()
	if stage != Stage.MATH or not value.is_valid_int() or value.to_int() != left + right:
		return false
	_prepare_options()
	stage = Stage.RECALL
	get_tree().change_scene_to_file("res://triangles.tscn")
	return true


func _prepare_options() -> void:
	var distractors: Array = []
	# Bounded sampling avoids enumerating permutations of long sequences.
	for attempt in range(12):
		var candidate: Array = original.duplicate()
		candidate.shuffle()
		_add_distractor(distractors, candidate)
	# The first group of three colors is distinct, so these swaps guarantee
	# enough alternatives for longer sequences even if sampling repeats.
	for first in range(mini(3, original.size())):
		for second in range(first + 1, mini(3, original.size())):
			var candidate: Array = original.duplicate()
			candidate[first] = original[second]
			candidate[second] = original[first]
			_add_distractor(distractors, candidate)
	# Two triangles have only two orderings; include other color pairs.
	if distractors.size() < 3:
		for position in range(mini(2, original.size())):
			for color in range(3):
				var candidate: Array = original.duplicate()
				candidate[position] = color
				if candidate.size() == 2 and candidate[0] == candidate[1]:
					continue
				_add_distractor(distractors, candidate)
	distractors.shuffle()
	options = [original.duplicate(), distractors[0], distractors[1], distractors[2]]
	options.shuffle()


func _add_distractor(distractors: Array, candidate: Array) -> void:
	if candidate != original and not distractors.has(candidate):
		distractors.append(candidate)


func choose(index: int) -> bool:
	if stage != Stage.RECALL or index < 0 or index >= options.size():
		return false
	stage = Stage.RESULT
	var correct: bool = options[index] == original
	if correct:
		score += 10
		consecutive_successes += 1
		if consecutive_successes == SUCCESSES_PER_LEVEL:
			sequence_length += 1
			consecutive_successes = 0
	else:
		consecutive_successes = 0
	return correct


func finish_game() -> bool:
	if stage == Stage.MENU or stage == Stage.ENDED:
		return false
	pending_score = score if high_scores.qualifies(score) else 0
	stage = Stage.ENDED
	get_tree().change_scene_to_file("res://triangles.tscn")
	return true


func submit_high_score(player_name: String) -> Error:
	if pending_score <= 0:
		return ERR_UNAVAILABLE
	var error := high_scores.record(player_name, pending_score)
	if error == OK:
		pending_score = 0
	return error


func skip_high_score() -> void:
	pending_score = 0
