extends RefCounted
## A project-local Top 3. Equal scores retain the order in which they were saved.
const SAVE_PATH := "user://high_scores.cfg"
const MAX_ENTRIES := 3
const MAX_NAME_LENGTH := 24
var entries: Array[Dictionary] = []
var storage_path: String
var load_error: Error = OK


func _init(path: String = SAVE_PATH) -> void:
	storage_path = path
	load_error = load_scores()


func qualifies(points: int) -> bool:
	return points > 0 and (entries.size() < MAX_ENTRIES or points > int(entries[-1]["score"]))


func record(player_name: String, points: int) -> Error:
	if not qualifies(points):
		return ERR_INVALID_PARAMETER
	var updated: Array[Dictionary] = entries.duplicate(true)
	_insert_ranked(updated, {"name": _clean_name(player_name), "score": points})
	var save := ConfigFile.new()
	save.set_value("scores", "top_three", updated)
	var error := save.save(storage_path)
	if error == OK:
		entries = updated
	return error


func load_scores() -> Error:
	entries.clear()
	var save := ConfigFile.new()
	var error := save.load(storage_path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		return error
	var saved: Variant = save.get_value("scores", "top_three", [])
	if not saved is Array:
		return ERR_INVALID_DATA
	for value in saved:
		if value is Dictionary and value.get("score") is int and value["score"] > 0 and value.get("name") is String:
			_insert_ranked(entries, {"name": _clean_name(value["name"]), "score": value["score"]})
	return OK


func _insert_ranked(target: Array[Dictionary], entry: Dictionary) -> void:
	var position := 0
	while position < target.size() and int(target[position]["score"]) >= int(entry["score"]):
		position += 1
	target.insert(position, entry)
	if target.size() > MAX_ENTRIES:
		target.resize(MAX_ENTRIES)


func _clean_name(value: String) -> String:
	var cleaned := value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(MAX_NAME_LENGTH)
	return cleaned if not cleaned.is_empty() else "Player"
