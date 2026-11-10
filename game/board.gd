extends Control

signal slot_used(column: int, wire: int, gate: String)
signal erase_requested(column: int)

const Palette = preload("res://game/skin.gd")
const Qpu = preload("res://game/qpu.gd")
const LABEL_WIDTH := 70.0
const COLUMN_WIDTH := 61.0
const HEADER := 29.0
const ROW := 49.0
const MIN_COLUMNS := 10

var ops: Array[Dictionary] = []
var selected := -1
var active := -1
var locked := false
var pending := Vector2i(-1, -1)
var _cell := Vector2i(-1, -1)
var _keyboard := Vector2i.ZERO


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func(): _cell = Vector2i(-1, -1); queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	get_parent().get_h_scroll_bar().value_changed.connect(func(_offset: float): queue_redraw())
	accessibility_name = "Circuit editor grid. Use arrows to move and Enter to use a slot."
	refresh()


func refresh() -> void:
	custom_minimum_size = Vector2(LABEL_WIDTH + _columns() * COLUMN_WIDTH + 9, HEADER + ROW * 4 + 10)
	_keyboard.x = mini(_keyboard.x, _columns() - 1)
	queue_redraw()


func _columns() -> int:
	return maxi(MIN_COLUMNS, ops.size() + 1)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0c1224"))
	for row in 4:
		var y := HEADER + ROW * row
		if row % 2 == 0:
			draw_rect(Rect2(0, y, size.x, ROW), Color("#10182e"))
		draw_line(Vector2(LABEL_WIDTH - 9, y + ROW / 2), Vector2(size.x - 9, y + ROW / 2),
			Color("#384668"), 1.5, true)
	for column in _columns():
		var x := LABEL_WIDTH + column * COLUMN_WIDTH
		var column_rect := Rect2(x, 0, COLUMN_WIDTH, HEADER + ROW * 4)
		draw_line(Vector2(x, HEADER), Vector2(x, HEADER + ROW * 4), Color("#202d49"), 1)
		if column == active or column == selected:
			var color := Palette.AQUA if column == active else Palette.LILAC
			draw_rect(column_rect, Color(color, 0.09))
			draw_rect(Rect2(x, 0, COLUMN_WIDTH, 2), color)
		draw_string(font, Vector2(x, 19), "%02d" % (column + 1), HORIZONTAL_ALIGNMENT_CENTER,
			COLUMN_WIDTH, 11, Palette.MUTED if column < ops.size() else Palette.FAINT.darkened(0.10))
		if column >= ops.size():
			for row in 4:
				draw_circle(_center(column, row), 2, Color("#596889"), true, -1, true)

	var focused := _cell if _cell.x >= 0 else _keyboard if has_focus() else Vector2i(-1, -1)
	if focused.x >= 0 and focused.x < _columns():
		var rect := Rect2(_center(focused.x, focused.y) - Vector2(28, 22), Vector2(56, 44))
		draw_rect(rect, Color(Palette.LILAC, 0.11))
		draw_rect(rect, Color(Palette.LILAC, 0.54), false, 1)

	for i in ops.size():
		var op := ops[i]
		var color := Palette.gate_color(op.gate)
		var wires: Array = op.wires
		if wires.size() > 1:
			draw_line(_center(i, wires.min()), _center(i, wires.max()), color, 2.0, true)
		for index in wires.size():
			var point := _center(i, wires[index])
			if op.gate == "CX":
				if index == 0:
					draw_circle(point, 6.5, color, true, -1, true)
				else:
					draw_circle(point, 11.0, Color("#241d42"), true, -1, true)
					draw_circle(point, 11.0, color, false, 2.0, true)
					draw_line(point - Vector2(7, 0), point + Vector2(7, 0), color, 2.0, true)
					draw_line(point - Vector2(0, 7), point + Vector2(0, 7), color, 2.0, true)
			else:
				_gate_chip(font, point, op.gate, color)
	if pending.x >= 0:
		var marker := _center(pending.x, pending.y)
		draw_circle(marker, 18.0, Palette.LILAC, false, 2.0, true)
		draw_circle(marker, 5.0, Palette.LILAC, true, -1, true)
	_draw_wire_labels(font)


func _draw_wire_labels(font: Font) -> void:
	var scroll := get_parent() as ScrollContainer
	var x := float(scroll.scroll_horizontal)
	draw_rect(Rect2(x, 0, LABEL_WIDTH, HEADER), Color("#0c1224"))
	for row in 4:
		var y := HEADER + ROW * row
		var mid := y + ROW / 2
		draw_rect(Rect2(x, y, LABEL_WIDTH, ROW), Color("#10182e") if row % 2 == 0 else Color("#0c1224"))
		draw_line(Vector2(x + LABEL_WIDTH - 9, mid), Vector2(x + LABEL_WIDTH, mid), Color("#384668"), 1.5)
		draw_circle(Vector2(x + 14, mid), 3, Qpu.COLORS[row], true, -1, true)
		draw_string(font, Vector2(x + 24, mid + 4), "%s  q%d" % [Qpu.NAMES[row], row],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Qpu.COLORS[row])


func _gate_chip(font: Font, point: Vector2, gate: String, color: Color) -> void:
	var rect := Rect2(point - Vector2(20, 15), Vector2(40, 30))
	var style := Palette.box(Color("#182a3b") if color == Palette.AQUA else Color("#292442"), color, 6, 0, 0)
	draw_style_box(style, rect)
	draw_string(font, Vector2(rect.position.x, point.y + 5), gate, HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x, 13, color)


func _center(column: int, wire: int) -> Vector2:
	return Vector2(LABEL_WIDTH + COLUMN_WIDTH * (column + 0.5), HEADER + ROW * (wire + 0.5))


func _slot(pos: Vector2) -> Vector2i:
	var scroll := get_parent() as ScrollContainer
	if pos.x < scroll.scroll_horizontal + LABEL_WIDTH:
		return Vector2i(-1, -1)
	var slot := Vector2i(floori((pos.x - LABEL_WIDTH) / COLUMN_WIDTH), floori((pos.y - HEADER) / ROW))
	if slot.x < 0 or slot.x >= _columns() or slot.y < 0 or slot.y >= 4:
		return Vector2i(-1, -1)
	return slot


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_cell = _slot(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var slot := _slot(event.position)
		if slot.x < 0:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			_keyboard = slot
			slot_used.emit(slot.x, slot.y, "")
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not locked and slot.x < ops.size():
			erase_requested.emit(slot.x)
			accept_event()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: _keyboard.x = maxi(_keyboard.x - 1, 0)
			KEY_RIGHT: _keyboard.x = mini(_keyboard.x + 1, _columns() - 1)
			KEY_UP: _keyboard.y = maxi(_keyboard.y - 1, 0)
			KEY_DOWN: _keyboard.y = mini(_keyboard.y + 1, 3)
			KEY_ENTER, KEY_SPACE: slot_used.emit(_keyboard.x, _keyboard.y, "")
			KEY_DELETE, KEY_BACKSPACE:
				if not locked and _keyboard.x < ops.size():
					erase_requested.emit(_keyboard.x)
			_: return
		_cell = Vector2i(-1, -1)
		keep_visible(_keyboard.x)
		queue_redraw()
		accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var slot := _slot(at_position)
	if slot.x < 0 or slot.x >= ops.size():
		return ""
	var op := ops[slot.x]
	var wires := PackedStringArray()
	for wire: int in op.wires:
		wires.append(Qpu.NAMES[wire])
	var angle := " · %.1f°" % rad_to_deg(op.angle) if op.has("angle") and op.gate in ["RX", "RY", "RZ", "RZZ"] else ""
	return "Step %d · %s · %s%s" % [slot.x + 1, op.gate, " → ".join(wires), angle]


func keep_visible(column: int) -> void:
	if column < 0:
		return
	var scroll := get_parent() as ScrollContainer
	var x := LABEL_WIDTH + COLUMN_WIDTH * column
	var bar := scroll.get_h_scroll_bar()
	if x < bar.value + LABEL_WIDTH:
		bar.value = maxf(0.0, x - LABEL_WIDTH)
	elif x + COLUMN_WIDTH > bar.value + scroll.size.x:
		bar.value = x + COLUMN_WIDTH - scroll.size.x


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return not locked and data is Dictionary and data.has("palette_gate") and _slot(at_position).x >= 0


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var slot := _slot(at_position)
	slot_used.emit(slot.x, slot.y, data.palette_gate)
