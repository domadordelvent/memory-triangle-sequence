extends Node
## Short synthesized UI effects, shared across scene changes.
signal muted_changed(is_muted: bool)
const SAMPLE_RATE := 44100
const VOLUME_DB := -12.0
var muted: bool = false
var correct_sound: AudioStreamWAV
var wrong_sound: AudioStreamWAV
var player: AudioStreamPlayer


func _ready() -> void:
	correct_sound = _make_sound([659.25, 987.77], 0.11, 0.12)
	wrong_sound = _make_sound([220.0, 174.61], 0.10, 0.25)
	player = AudioStreamPlayer.new()
	player.name = "Player"
	player.volume_db = VOLUME_DB
	player.max_polyphony = 1
	add_child(player)


func _exit_tree() -> void:
	player.stop()
	player.stream = null
	correct_sound = null
	wrong_sound = null


func play_correct() -> void:
	_play(correct_sound)


func play_wrong() -> void:
	_play(wrong_sound)


func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	if muted:
		player.stop()
	muted_changed.emit(muted)


func _play(sound: AudioStreamWAV) -> void:
	if muted:
		return
	# Ignore repeated requests for an effect already playing; a different
	# result replaces it immediately instead of adding another voice.
	if player.playing and player.stream == sound:
		return
	player.stop()
	player.stream = sound
	player.play()


func _make_sound(notes: Array[float], note_seconds: float, harmonic: float) -> AudioStreamWAV:
	var sample_count := roundi(notes.size() * note_seconds * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in range(sample_count):
		var time := float(index) / SAMPLE_RATE
		var note := mini(floori(time / note_seconds), notes.size() - 1)
		var local_time := time - note * note_seconds
		var attack := clampf(local_time / 0.006, 0.0, 1.0)
		var release := clampf((note_seconds - local_time) / 0.025, 0.0, 1.0)
		var envelope := attack * release * exp(-3.0 * local_time / note_seconds)
		var phase := TAU * notes[note] * local_time
		var wave := (sin(phase) + harmonic * sin(phase * 2.0)) / (1.0 + harmonic)
		data.encode_s16(index * 2, int(wave * envelope * 0.6 * 32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = SAMPLE_RATE
	sound.stereo = false
	sound.data = data
	return sound
