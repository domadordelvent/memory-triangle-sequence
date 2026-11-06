extends RefCounted

static func box(fill: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


static func apply(control: Control) -> void:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color("e4ebf3"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill: String = {"normal": "334657", "hover": "40576b", "pressed": "293c4d", "disabled": "283947"}[state]
		theme.set_stylebox(state, "Button", box(fill, "526779"))
		theme.set_color("font_" + state + "_color", "Button", Color("edf3f8"))
	theme.set_color("font_color", "Button", Color("edf3f8"))
	var focus := box("334657", "a8c8df")
	focus.bg_color.a = 0.0
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("normal", "LineEdit", box("223340", "526779"))
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_color("font_color", "LineEdit", Color("edf3f8"))
	control.theme = theme
