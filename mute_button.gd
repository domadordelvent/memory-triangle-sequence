extends Button
## Both screens share the same session mute setting.


func _ready() -> void:
	toggled.connect(FeedbackAudio.set_muted)
	FeedbackAudio.muted_changed.connect(_sync)
	_sync(FeedbackAudio.muted)


func _sync(is_muted: bool) -> void:
	set_pressed_no_signal(is_muted)
	text = "Unmute" if is_muted else "Mute"
	tooltip_text = "Turn feedback sounds on" if is_muted else "Turn feedback sounds off"
	accessibility_name = text + " feedback sounds"
