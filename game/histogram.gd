extends Control

const Quantum = preload("res://game/quantum.gd")
const Palette = preload("res://game/skin.gd")
const LEFT := 44.0
const RIGHT := 12.0
const TOP := 19.0
const BOTTOM := 25.0

var probabilities := PackedFloat64Array()
var _width := 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)


func display(state: PackedFloat64Array, qubit_count: int) -> void:
	_width = qubit_count
	probabilities = Quantum.probabilities(state, range(qubit_count))
	accessibility_name = "Computational-basis probabilities, qubits in circuit order"
	queue_redraw()


func _draw() -> void:
	if probabilities.is_empty():
		return
	var font := get_theme_default_font()
	var bottom := size.y - BOTTOM
	var height := bottom - TOP
	var spacing := (size.x - LEFT - RIGHT) / probabilities.size()
	var bar_width := minf(72.0, spacing * 0.64)
	for percent: int in [0, 50, 100]:
		var y := bottom - height * percent / 100.0
		draw_line(Vector2(LEFT, y), Vector2(size.x - RIGHT, y), Palette.BORDER, 1)
		draw_string(font, Vector2(0, y + 4), "%d%%" % percent, HORIZONTAL_ALIGNMENT_RIGHT, LEFT - 8, 11, Palette.MUTED)
	for value in probabilities.size():
		var probability := clampf(probabilities[value], 0.0, 1.0)
		var x := LEFT + spacing * (value + 0.5)
		var bar_height := probability * height
		if bar_height > 0.0:
			draw_rect(Rect2(x - bar_width * 0.5, bottom - bar_height, bar_width, bar_height), Palette.AQUA.darkened(0.32))
			draw_line(Vector2(x - bar_width * 0.5, bottom - bar_height),
				Vector2(x + bar_width * 0.5, bottom - bar_height), Palette.AQUA, 2)
			if probabilities.size() <= 8 and probability >= 0.005:
				draw_string(font, Vector2(x - spacing * 0.5, bottom - bar_height - 5),
					"%.1f%%" % (probability * 100.0), HORIZONTAL_ALIGNMENT_CENTER, spacing, 11, Palette.INK)
		draw_string(font, Vector2(x - spacing * 0.5, bottom + 17), Quantum.bit_string(value, _width),
			HORIZONTAL_ALIGNMENT_CENTER, spacing, 11, Palette.INK if probability > Quantum.EPS else Palette.MUTED)


func _get_tooltip(at_position: Vector2) -> String:
	if probabilities.is_empty() or at_position.x < LEFT or at_position.x >= size.x - RIGHT:
		return ""
	var value := floori((at_position.x - LEFT) * probabilities.size() / (size.x - LEFT - RIGHT))
	return "|%s⟩ · %.2f%%" % [Quantum.bit_string(value, _width), probabilities[value] * 100.0]
