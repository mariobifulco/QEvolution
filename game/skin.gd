extends RefCounted

const INK := Color("#edf1ff")
const MUTED := Color("#a2aecc")
const FAINT := Color("#7b8aaf")
const PANEL := Color("#11172c")
const BORDER := Color("#2b3658")
const AQUA := Color("#76eee1")
const LILAC := Color("#c1adff")
const AMBER := Color("#f8cb77")


static func box(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 10,
		inset_x: int = 12, inset_y: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = inset_x
	style.content_margin_right = inset_x
	style.content_margin_top = inset_y
	style.content_margin_bottom = inset_y
	return style


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, box(Color("#1a2340"), BORDER, 8))
		theme.set_stylebox("hover", type, box(Color("#263354"), Color("#586990"), 8))
		theme.set_stylebox("pressed", type, box(Color("#303057"), LILAC.darkened(0.36), 8))
		theme.set_stylebox("disabled", type, box(Color("#141c32"), Color("#26304a"), 8))
		var focus := box(Color.TRANSPARENT, AQUA, 8)
		focus.set_border_width_all(2)
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, INK)
		theme.set_color("font_disabled_color", type, Color("#687595"))
	theme.set_stylebox("panel", "PopupMenu", box(Color("#161e37"), BORDER, 8))
	theme.set_stylebox("hover", "PopupMenu", box(Color("#2e3b61"), Color.TRANSPARENT, 5))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_stylebox("normal", "LineEdit", box(Color("#0d1326"), BORDER, 7, 8, 6))
	theme.set_stylebox("normal", "TextEdit", box(Color("#0a1021"), BORDER, 8))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_color", "TextEdit", INK)
	theme.set_stylebox("scroll", "HScrollBar", box(Color("#121a30"), Color.TRANSPARENT, 5, 0, 4))
	theme.set_stylebox("grabber", "HScrollBar", box(Color("#354568"), Color.TRANSPARENT, 5, 0, 4))
	return theme


static func accent(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(AQUA, AQUA, 8, 16, 8))
	button.add_theme_stylebox_override("hover", box(Color("#a0fff4"), AQUA, 8, 16, 8))
	button.add_theme_stylebox_override("pressed", box(Color("#61ccbf"), AQUA, 8, 16, 8))
	for property in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(property, Color("#071d24"))


static func gate_color(gate: String) -> Color:
	if gate in ["CX", "RZZ"]:
		return LILAC
	if gate == "M":
		return AMBER
	return AQUA
