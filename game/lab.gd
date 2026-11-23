extends Control

const Quantum = preload("res://game/quantum.gd")
const Qasm = preload("res://game/qasm.gd")
const Qpu = preload("res://game/qpu.gd")
const Palette = preload("res://game/skin.gd")
const Board = preload("res://game/board.gd")
const Stage = preload("res://game/stage.gd")
const Histogram = preload("res://game/histogram.gd")
const ICON = preload("res://game/icon.svg")

const GATE_HELP := {
	"H": "Hadamard · create or undo superposition",
	"X": "Pauli X · flip 0 and 1",
	"Y": "Pauli Y · flip with a phase",
	"Z": "Pauli Z · flip the phase of |1⟩",
	"RX": "Rotate around the X axis",
	"RY": "Rotate around the Y axis",
	"RZ": "Rotate around the Z axis",
	"CX": "Controlled X · choose the control, then the target",
	"RZZ": "ZZ rotation · choose two qubits",
	"M": "Measure one qubit in the computational basis",
}
const EXAMPLES := ["Hadamard", "Bell pair", "Two Bell pairs", "GHZ₄", "Phase interference"]
const EXAMPLE_WIDTHS := [1, 2, 4, 4, 1]
const MISSION_WIDTHS := [1, 2, 4, 4]
const CUT_NAMES := ["AB | CD", "AC | BD", "AD | BC"]
const MISSIONS := ["Free lab", "Bell pair", "Two Bell pairs", "Four-way entanglement"]
const GOALS := [
	"Build a circuit freely or choose a challenge.",
	"Entangle A and B maximally. Hint: H, then CX.",
	"Create two independent Bell pairs, AB and CD. Look for two bright edges.",
	"Entangle all four qubits with at least 1 bit of entropy across each cut.",
]

signal presentation_changed(metrics: Dictionary, section: int)

var stage: Control
var _histogram: Control
var _measurement_info: Label
var _board: Control
var _palette_buttons: Dictionary = {}
var _editor_controls: Array[Control] = []
var _undo_button: Button
var _add_qubit_button: Button
var _remove_qubit_menu: MenuButton
var _qubit_label: Label
var _delete_button: Button
var _run_button: Button
var _play_button: Button
var _back_button: Button
var _next_button: Button
var _restart_button: Button
var _angle: SpinBox
var _work_hint: Label
var _step_label: Label
var _step_info: Label
var _model_info: Label
var _model_mode: OptionButton
var _focus_menu: OptionButton
var _wire_readouts: Array[Label] = []
var _wire_cards: Array[Control] = []
var _challenge_picker: OptionButton
var _challenge_hint: Label
var _qasm_layer: Control
var _qasm_text: TextEdit
var _qasm_status: Label
var _timer: Timer

var _qubit_count := 1
var _ops: Array[Dictionary] = []
var _undo: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
var _parser := Qasm.new()
var _rng := RandomNumberGenerator.new()
var _mission := 0
var _solved := false
var _running := false
var _cursor := 0
var _armed := ""
var _pending := Vector2i(-1, -1)
var _selected := -1
var _angle_is_syncing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Palette.make_theme()
	_build()
	_ops = _example(0)
	_reset_frames()
	_refresh_editor()
	_refresh_frame()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#080e1e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root_margin := _margin(self, 28, 22)
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := _stack(root_margin, 17)
	var header := _row(root, 12)
	var logo := TextureRect.new()
	logo.texture = ICON
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(42, 42)
	header.add_child(logo)
	var branding := _stack(header, 0)
	_heading(branding, "QEvolution", 24)
	_label(branding, "Quantum circuit lab", 13, Palette.MUTED)

	var columns := _row(root, 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var work := _stack(columns, 12)
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.size_flags_stretch_ratio = 1.13
	_build_workbench(work)
	columns.add_child(VSeparator.new())
	var inspect := _stack(columns, 12)
	inspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_inspector(inspect)

	_build_qasm_overlay()

	_timer = Timer.new()
	_timer.wait_time = 0.76
	_timer.timeout.connect(_advance)
	add_child(_timer)


func _build_workbench(work: VBoxContainer) -> void:
	var editor := _stack(_card(work, Palette.PANEL, 16, 14), 10)
	var top := _row(editor, 8)
	_heading(top, "Circuit", 23)
	_space(top)
	var examples := MenuButton.new()
	examples.text = "Examples  ▾"
	examples.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(examples)
	for example in EXAMPLES:
		examples.get_popup().add_item(example)
	examples.get_popup().id_pressed.connect(_load_example)
	_editor_controls.append(examples)
	_editor_controls.append(_button(top, "OpenQASM", _open_qasm, "Import or copy OpenQASM 3.0"))

	var gate_row := _row(editor, 5)
	_label(gate_row, "Gates", 13, Palette.MUTED)
	for gate in Quantum.GATES:
		var tile := _button(gate_row, gate, _arm.bind(gate), GATE_HELP[gate])
		tile.toggle_mode = true
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_color_override("font_color", Palette.gate_color(gate))
		tile.set_drag_forwarding(_drag_gate.bind(gate), Callable(), Callable())
		_palette_buttons[gate] = tile

	var board_header := _row(editor, 8)
	_qubit_label = _label(board_header, "", 14, Palette.INK)
	_space(board_header)
	_remove_qubit_menu = MenuButton.new()
	_remove_qubit_menu.text = "Remove qubit  ▾"
	_remove_qubit_menu.tooltip_text = "Remove a wire and the gates that use it. Undo restores the circuit."
	_remove_qubit_menu.get_popup().id_pressed.connect(_remove_qubit)
	board_header.add_child(_remove_qubit_menu)
	_add_qubit_button = _button(board_header, "+ Add qubit", _add_qubit, "Add a wire initialized in |0⟩")
	var board_frame := _card(editor, Color("#0c1224"), 1, 1)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	board_frame.add_child(scroll)
	_board = Board.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.slot_used.connect(_use_slot)
	_board.erase_requested.connect(_remove)
	_board.move_requested.connect(_move_gate)
	scroll.add_child(_board)

	var edits := _row(editor, 6)
	_label(edits, "Rotation", 13, Palette.MUTED)
	_angle = SpinBox.new()
	_angle.min_value = -360
	_angle.max_value = 360
	_angle.allow_greater = true
	_angle.allow_lesser = true
	_angle.step = 0.0
	_angle.value = 90.0
	_angle.suffix = "°"
	_angle.custom_minimum_size.x = 92
	_angle.tooltip_text = "Select a rotation gate to edit its angle in degrees."
	_angle.value_changed.connect(_edit_angle)
	edits.add_child(_angle)
	_editor_controls.append(_button(edits, "Measure all", _append_measurement, "Measure all circuit wires together"))
	_space(edits)
	_editor_controls.append(_button(edits, "Select", _arm.bind(""), "Cancel the active gate tool"))
	_undo_button = _button(edits, "Undo", _undo_edit, "Undo the last circuit edit")
	_delete_button = _button(edits, "Delete", func(): _remove(_selected), "Delete or Backspace removes the selected gate")
	_editor_controls.append(_button(edits, "Clear", func(): _replace_ops([], "Circuit cleared.")))

	_work_hint = _label(editor, "", 13, Palette.MUTED)
	_work_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var transport := _stack(_card(work, Palette.PANEL, 16, 12), 9)
	var position := _row(transport, 8)
	_heading(position, "Playback", 17)
	_space(position)
	_step_label = _label(position, "", 13, Palette.AQUA)
	var controls := _row(transport, 6)
	_run_button = _button(controls, "Run circuit", _toggle_run)
	Palette.accent(_run_button)
	_space(controls)
	_restart_button = _button(controls, "New run", _restart, "Return to the start and draw new measurement samples")
	_back_button = _button(controls, "← Back", func(): _show_step(_cursor - 1), "Return to the previous state")
	_play_button = _button(controls, "▶ Play", _toggle_play)
	_next_button = _button(controls, "Next →", func(): _show_step(_cursor + 1), "Apply the next operation")
	_step_info = _label(transport, "", 13, Palette.MUTED)
	_step_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var challenge := _stack(_card(work, Palette.PANEL, 16, 12), 6)
	var challenge_row := _row(challenge, 8)
	_heading(challenge_row, "Challenge", 17)
	_space(challenge_row)
	_challenge_picker = OptionButton.new()
	for title in MISSIONS:
		_challenge_picker.add_item(title)
	_challenge_picker.item_selected.connect(_choose_mission)
	challenge_row.add_child(_challenge_picker)
	_challenge_hint = _label(challenge, "", 13, Palette.MUTED)
	_challenge_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_inspector(inspect: VBoxContainer) -> void:
	var state_card := _card(inspect, Palette.PANEL, 16, 14)
	state_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var state := _stack(state_card, 8)
	var controls := _row(state, 6)
	_heading(controls, "Quantum state", 23)
	_space(controls)
	_model_mode = OptionButton.new()
	_model_mode.add_item("Tetrahedron")
	for label in CUT_NAMES:
		_model_mode.add_item(label)
	_model_mode.item_selected.connect(func(_index: int): _render_model())
	controls.add_child(_model_mode)
	_focus_menu = OptionButton.new()
	_focus_menu.item_selected.connect(func(index: int): stage.focus_on(index - 1))
	controls.add_child(_focus_menu)
	_button(controls, "Reset view", _reset_view, "Reset the camera")

	stage = Stage.new()
	stage.custom_minimum_size.y = 258
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.tooltip_text = "Drag to orbit. Scroll to zoom."
	var viewport_card := _card(state, Color("#0b1228"), 1, 1)
	viewport_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_card.add_child(stage)

	var view_row := _row(state, 4)
	_model_info = _label(view_row, "", 13, Palette.MUTED)
	_model_info.mouse_filter = Control.MOUSE_FILTER_PASS
	_model_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_button(view_row, "⟲", func(): stage.orbit(-0.24), "Orbit left")
	_button(view_row, "⟳", func(): stage.orbit(0.24), "Orbit right")
	_button(view_row, "−", func(): stage.magnify(1.0 / 1.2), "Zoom out")
	_button(view_row, "+", func(): stage.magnify(1.2), "Zoom in")

	var readouts := _row(state, 6)
	for wire in Quantum.MAX_QUBITS:
		var card := _card(readouts, Color("#101a30"), 9, 5)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tile := _stack(card, 2)
		_label(tile, "%s  /  q%d" % [Qpu.NAMES[wire], wire], 12, Qpu.COLORS[wire])
		_wire_readouts.append(_label(tile, "", 12, Palette.INK))
		_wire_readouts.back().mouse_filter = Control.MOUSE_FILTER_PASS
		_wire_cards.append(card)

	var chart := _stack(_card(inspect, Palette.PANEL, 16, 14), 4)
	var chart_header := _row(chart, 8)
	_heading(chart_header, "Outcome probabilities", 19)
	_space(chart_header)
	_label(chart_header, "Computational basis", 12, Palette.MUTED)
	_histogram = Histogram.new()
	_histogram.custom_minimum_size.y = 154
	chart.add_child(_histogram)
	_measurement_info = _label(chart, "", 13, Palette.MUTED)
	_measurement_info.mouse_filter = Control.MOUSE_FILTER_PASS
	_measurement_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _build_qasm_overlay() -> void:
	_qasm_layer = ColorRect.new()
	_qasm_layer.color = Color(0.018, 0.028, 0.06, 0.88)
	_qasm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_qasm_layer)
	var centered := CenterContainer.new()
	centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_qasm_layer.add_child(centered)
	var shell := _card(centered, Palette.PANEL, 20, 17)
	shell.custom_minimum_size = Vector2(690, 494)
	var body := _stack(shell, 10)
	var title := _row(body, 8)
	_heading(title, "OpenQASM 3.0", 26)
	_space(title)
	_button(title, "Close", _close_qasm)
	_label(body, "Edit or paste a program with up to four qubits and the supported gates.", 14, Palette.MUTED)
	_qasm_text = TextEdit.new()
	_qasm_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_qasm_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_qasm_text.add_theme_font_size_override("font_size", 16)
	_qasm_text.tooltip_text = "OpenQASM source code"
	body.add_child(_qasm_text)
	_qasm_status = _label(body, "", 13, Palette.MUTED)
	_qasm_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := _row(body, 8)
	_button(actions, "Paste from clipboard", func(): _qasm_text.text = DisplayServer.clipboard_get())
	_button(actions, "Copy text", _copy_qasm)
	_space(actions)
	Palette.accent(_button(actions, "Validate & load", _import_qasm))
	_qasm_layer.hide()


func _drag_gate(_position: Vector2, gate: String) -> Variant:
	if _palette_buttons[gate].disabled:
		return null
	_palette_buttons[gate].set_drag_preview(Board.gate_preview(gate))
	return {"palette_gate": gate}


func _arm(gate: String) -> void:
	_armed = "" if _armed == gate else gate
	_pending = Vector2i(-1, -1)
	_selected = -1
	_refresh_editor()


func _use_slot(column: int, wire: int, dragged: String) -> void:
	if _running:
		return
	column = mini(column, _ops.size())
	if not dragged.is_empty():
		_armed = dragged
		_pending = Vector2i(-1, -1)
		_selected = -1
	if _pending.x >= 0:
		if wire == _pending.y:
			_hint("Choose a different wire for the second qubit.")
			return
		_insert(_pending.x, _operation(_armed, [_pending.y, wire]))
	elif not _armed.is_empty():
		if _armed in ["CX", "RZZ"]:
			_pending = Vector2i(column, wire)
			_refresh_editor()
		else:
			_insert(column, _operation(_armed, [wire]))
	else:
		_select_gate(column if column < _ops.size() else -1)


func _select_gate(index: int) -> void:
	_selected = index
	if index >= 0 and _ops[index].gate in Quantum.ROTATIONS:
		_angle_is_syncing = true
		_angle.value = rad_to_deg(_ops[index].angle)
		_angle_is_syncing = false
	_refresh_editor()


func _move_gate(source: int, destination: int, wire_offset: int) -> void:
	if _running:
		return
	destination = mini(destination, _ops.size() - 1)
	if destination != source or wire_offset != 0:
		_record_edit()
		var op := _ops.pop_at(source) as Dictionary
		if wire_offset != 0:
			op = op.duplicate()
			op.wires = op.wires.map(func(wire: int): return wire + wire_offset)
		_ops.insert(destination, op)
	_armed = ""
	_pending = Vector2i(-1, -1)
	_select_gate(destination)
	_board.keep_visible.call_deferred(destination)


func _operation(gate: String, wires: Array) -> Dictionary:
	return {"gate": gate, "wires": wires, "angle": deg_to_rad(_angle.value) if gate in Quantum.ROTATIONS else 0.0}


func _insert(index: int, op: Dictionary) -> void:
	if _ops.size() >= Quantum.MAX_STEPS:
		_hint("The circuit already has %d operations." % Quantum.MAX_STEPS)
		return
	if not is_finite(op.angle):
		_hint("Enter a finite rotation angle.")
		return
	_record_edit()
	_ops.insert(index, op)
	_armed = ""
	_pending = Vector2i(-1, -1)
	_selected = index
	_refresh_editor()
	_board.keep_visible.call_deferred(index)


func _append_measurement() -> void:
	_insert(_ops.size(), _operation("M", range(_qubit_count)))


func _add_qubit() -> void:
	if not _running and _qubit_count < Quantum.MAX_QUBITS:
		_replace_ops(_ops, "", _qubit_count + 1)


func _remove_qubit(wire: int) -> void:
	if _running or _qubit_count <= 1 or wire < 0 or wire >= _qubit_count:
		return
	var remaining: Array[Dictionary] = []
	for op in _ops:
		var operands: Array = op.wires
		if operands.has(wire) and (op.gate != "M" or operands.size() == 1):
			continue
		var updated := op.duplicate()
		updated.wires = []
		for operand: int in operands:
			if operand != wire:
				updated.wires.append(operand - 1 if operand > wire else operand)
		remaining.append(updated)
	_replace_ops(remaining, "Removed qubit %s. Use Undo to restore the circuit." % Qpu.NAMES[wire], _qubit_count - 1)


func _record_edit() -> void:
	_undo.append({"ops": _ops.duplicate(), "qubit_count": _qubit_count})
	if _undo.size() > 40:
		_undo.pop_front()


func _replace_ops(ops: Array[Dictionary], message: String, qubit_count: int = 0) -> void:
	if _running:
		_toggle_run()
	_record_edit()
	_set_circuit(ops, _qubit_count if qubit_count == 0 else qubit_count)
	if not message.is_empty():
		_hint(message)


func _undo_edit() -> void:
	if _undo.is_empty():
		return
	var previous := _undo.pop_back() as Dictionary
	_set_circuit(previous.ops, previous.qubit_count)
	_hint("Last edit undone.")


func _set_circuit(ops: Array[Dictionary], qubit_count: int) -> void:
	var resized := _qubit_count != qubit_count
	_qubit_count = qubit_count
	_ops = ops
	_selected = -1
	_pending = Vector2i(-1, -1)
	_armed = ""
	if resized:
		_reset_frames()
	_refresh_editor()
	if resized:
		_refresh_frame()


func _remove(index: int) -> void:
	if _running or index < 0 or index >= _ops.size():
		return
	_record_edit()
	_ops.remove_at(index)
	_selected = -1
	_pending = Vector2i(-1, -1)
	_refresh_editor()


func _unhandled_key_input(event: InputEvent) -> void:
	if _running or _selected < 0 or _qasm_layer.visible or not event.is_pressed() or event.is_echo():
		return
	if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and not get_viewport().gui_get_focus_owner() is LineEdit:
		_remove(_selected)
		get_viewport().set_input_as_handled()


func _edit_angle(degrees: float) -> void:
	if _angle_is_syncing or _running or not is_finite(degrees):
		return
	if _selected >= 0 and _ops[_selected].gate in Quantum.ROTATIONS:
		_record_edit()
		_ops[_selected] = _operation(_ops[_selected].gate, _ops[_selected].wires)
		_refresh_editor()


func _refresh_editor() -> void:
	_board.qubit_count = _qubit_count
	_board.ops = _ops
	_board.pending = _pending
	_board.selected = _selected if not _running else -1
	_board.locked = _running
	_board.refresh()
	for control in _editor_controls:
		control.disabled = _running
	for gate in _palette_buttons:
		_palette_buttons[gate].disabled = _running or (_qubit_count < 2 and gate in ["CX", "RZZ"])
		_palette_buttons[gate].set_pressed_no_signal(_armed == gate and not _running)
	_refresh_qubit_controls()
	_angle.editable = not _running
	_delete_button.disabled = _running or _selected < 0
	_undo_button.disabled = _running or _undo.is_empty()
	_run_button.disabled = not _running and _ops.is_empty()
	_run_button.text = "Edit circuit" if _running else "Run circuit"
	_refresh_transport()
	_refresh_challenge()
	if _running:
		_hint("Circuit locked during playback.")
	elif _pending.x >= 0:
		_hint("%s · Choose a second wire after %s." % [_armed, Qpu.NAMES[_pending.y]])
	elif not _armed.is_empty():
		_hint("%s · Pick a wire and step." % _armed)
	elif _selected >= 0:
		_hint("%s  ·  Drag to move or press Delete to remove." % _describe(_ops[_selected]))
	else:
		_hint("Drag gates onto a wire or click a gate, then a slot.")


func _refresh_qubit_controls() -> void:
	_add_qubit_button.disabled = _running or _qubit_count >= Quantum.MAX_QUBITS
	_remove_qubit_menu.disabled = _running or _qubit_count <= 1
	_qubit_label.text = "%d %s · max %d" % [_qubit_count, "qubit" if _qubit_count == 1 else "qubits", Quantum.MAX_QUBITS]
	var popup := _remove_qubit_menu.get_popup()
	if popup.item_count != _qubit_count:
		popup.clear()
		for wire in _qubit_count:
			popup.add_item("%s  /  q%d" % [Qpu.NAMES[wire], wire], wire)


func _toggle_run() -> void:
	_running = not _running
	_timer.stop()
	_pending = Vector2i(-1, -1)
	_armed = ""
	_selected = -1
	_reset_frames()
	_refresh_editor()
	_refresh_frame()


func _reset_frames() -> void:
	_cursor = 0
	var initial := Quantum.initial(_qubit_count)
	_frames = [{"state": initial, "metrics": Quantum.metrics(initial)}]


func _restart() -> void:
	_timer.stop()
	_reset_frames()
	_refresh_frame()


func _toggle_play() -> void:
	if _timer.is_stopped() and _cursor < _ops.size():
		_timer.start()
		_advance()
	else:
		_timer.stop()
	_refresh_transport()


func _advance() -> void:
	_show_step(_cursor + 1, false)


func _show_step(index: int, pause: bool = true) -> void:
	if not _running:
		return
	if pause:
		_timer.stop()
	_cursor = clampi(index, 0, _ops.size())
	if _cursor == _frames.size():
		var frame := Quantum.step(_frames.back().state, _ops[_cursor - 1], _rng.randf())
		frame.metrics = Quantum.metrics(frame.state)
		_frames.append(frame)
	if _cursor >= _ops.size() or _frames[_cursor].has("probabilities"):
		_timer.stop()
	_refresh_frame()


func _refresh_transport() -> void:
	_back_button.disabled = not _running or _cursor == 0
	_next_button.disabled = not _running or _cursor >= _ops.size()
	_play_button.disabled = _next_button.disabled
	_play_button.text = "▶ Play" if _timer.is_stopped() else "Ⅱ Pause"
	_restart_button.disabled = not _running or _frames.size() <= 1
	_step_label.text = "Step %d / %d" % [_cursor, _ops.size()]
	_step_info.text = "Initial state  |%s⟩" % "0".repeat(_qubit_count) if _cursor == 0 else _describe(_ops[_cursor - 1])


func _refresh_frame() -> void:
	var frame := _frames[_cursor]
	_board.active = _cursor - 1
	_board.queue_redraw()
	_board.keep_visible(_board.active)
	_refresh_transport()
	var measurement := frame.has("probabilities")
	if _running:
		if _cursor == 0:
			_hint("Press Next to apply the first gate.")
		elif _cursor == _ops.size():
			_hint("Run complete. Step back or start a new run.")
		elif measurement:
			_hint("Measurement recorded. Press Next to continue.")
		else:
			_hint("Use Back and Next to inspect each state.")
	_sync_visualizer_controls()
	_render_model()
	_histogram.display(frame.state, _qubit_count)
	_show_measurement_info(frame)
	_check_goal(frame.metrics)


func _sync_visualizer_controls() -> void:
	if _focus_menu.item_count == _qubit_count + 1:
		return
	_focus_menu.clear()
	_focus_menu.add_item("Focus: all")
	for wire in _qubit_count:
		_focus_menu.add_item("Focus: %s" % Qpu.NAMES[wire])
	_focus_menu.select(0)
	_focus_menu.visible = _qubit_count > 1
	_model_mode.select(0)
	_model_mode.visible = _qubit_count == Quantum.MAX_QUBITS
	for wire in Quantum.MAX_QUBITS:
		_wire_cards[wire].visible = wire < _qubit_count


func _render_model() -> void:
	var metrics: Dictionary = _frames[_cursor].metrics
	var section := _model_mode.selected - 1 if _qubit_count == Quantum.MAX_QUBITS else -1
	presentation_changed.emit(metrics, section)
	stage.display(metrics, section)
	for wire in _qubit_count:
		var vector: Vector3 = metrics.bloch[wire]
		_wire_readouts[wire].text = "X %.2f   Y %.2f   Z %.2f" % [vector.x, vector.y, vector.z] if _qubit_count == 1 else (
			"|r| %.2f   S %.2f" % [vector.length(), metrics.singles[wire]])
		_wire_readouts[wire].tooltip_text = "Bloch vector (%.3f, %.3f, %.3f) · Entanglement entropy %.3f bits" % [
			vector.x, vector.y, vector.z, metrics.singles[wire]]
	match _qubit_count:
		1: _model_info.text = "Bloch sphere"
		2: _model_info.text = "Pair concurrence  %.3f" % metrics.pairs[0]
		3, 4: _model_info.text = "Minimum cut entropy  %.3f bits" % metrics.core
	if section >= 0:
		_model_info.text = "%s  ·  %.3f bits" % [CUT_NAMES[section], metrics.cuts[section]]
	var pairs := Quantum.pairs_for(_qubit_count)
	var pair_readouts := PackedStringArray()
	for i in pairs.size():
		pair_readouts.append("%s   %.3f" % ["".join(_wire_names(pairs[i])), metrics.pairs[i]])
	_model_info.tooltip_text = "Pair concurrence\n" + "\n".join(pair_readouts) if not pair_readouts.is_empty() else ""


func _show_measurement_info(frame: Dictionary) -> void:
	if not frame.has("probabilities"):
		_measurement_info.text = "Bit order: " + " · ".join(_wire_names(range(_qubit_count)))
		_measurement_info.tooltip_text = ""
		_measurement_info.add_theme_color_override("font_color", Palette.MUTED)
		return
	var wires := " · ".join(_wire_names(frame.wires))
	var outcome := Quantum.bit_string(frame.sample, frame.wires.size())
	_measurement_info.text = "Measured %s on %s  ·  %.1f%% before collapse" % [
		outcome, wires, 100.0 * frame.probabilities[frame.sample]]
	var distribution := PackedStringArray(["Measurement probabilities before collapse"])
	for value in frame.probabilities.size():
		if frame.probabilities[value] > Quantum.EPS:
			distribution.append("%s   %.2f%%" % [
				Quantum.bit_string(value, frame.wires.size()), 100.0 * frame.probabilities[value]])
	_measurement_info.tooltip_text = "\n".join(distribution)
	_measurement_info.add_theme_color_override("font_color", Palette.AMBER)


func _reset_view() -> void:
	stage.reset_view()
	_focus_menu.select(0)


func _choose_mission(index: int) -> void:
	_mission = index
	_solved = false
	if index > 0:
		_replace_ops([], "Build a circuit for this challenge.", MISSION_WIDTHS[index])
	_refresh_challenge()


func _check_goal(metrics: Dictionary) -> void:
	if _mission == 0 or _solved or not _running or _qubit_count < MISSION_WIDTHS[_mission]:
		return
	match _mission:
		1:
			_solved = metrics.pairs[0] >= 0.999
			for wire in range(2, _qubit_count):
				_solved = _solved and metrics.bloch[wire].length() >= 0.999
		2: _solved = metrics.pairs[0] >= 0.999 and metrics.pairs[5] >= 0.999
		3: _solved = metrics.core >= 0.999
	_refresh_challenge()


func _refresh_challenge() -> void:
	_challenge_hint.text = "✓  Challenge complete · %s" % MISSIONS[_mission] if _solved else GOALS[_mission]
	_challenge_hint.add_theme_color_override("font_color", Palette.AQUA if _solved else Palette.MUTED)


func _open_qasm() -> void:
	_qasm_text.text = Qasm.encode(_ops, _qubit_count)
	_qasm_status.text = "Supported: H, X, Y, Z, RX, RY, RZ, CX, RZZ and measure."
	_qasm_status.add_theme_color_override("font_color", Palette.MUTED)
	_qasm_layer.show()
	_qasm_text.grab_focus()


func _close_qasm() -> void:
	_qasm_layer.hide()


func _copy_qasm() -> void:
	DisplayServer.clipboard_set(_qasm_text.text)
	_qasm_status.text = "Copied to clipboard."
	_qasm_status.add_theme_color_override("font_color", Palette.AQUA)


func _import_qasm() -> void:
	var parsed := _parser.parse(_qasm_text.text)
	if parsed.has("error"):
		_qasm_status.text = parsed.error
		_qasm_status.add_theme_color_override("font_color", Palette.AMBER)
	else:
		_replace_ops(parsed.ops, "Loaded %d operations from OpenQASM." % parsed.ops.size(), parsed.qubit_count)
		_close_qasm()


func _wire_names(wires: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for wire: int in wires:
		names.append(Qpu.NAMES[wire])
	return names


func _describe(op: Dictionary) -> String:
	var name_: String = "Measure" if op.gate == "M" else op.gate
	if op.gate in Quantum.ROTATIONS:
		name_ += " %.2f°" % rad_to_deg(op.angle)
	return "%s  ·  %s" % [name_, (" → " if op.gate == "CX" else " · ").join(_wire_names(op.wires))]


func _hint(message: String) -> void:
	_work_hint.text = message
	_work_hint.tooltip_text = message


func _load_example(index: int) -> void:
	_replace_ops(_example(index), "Example loaded.", EXAMPLE_WIDTHS[index])


func _example(index: int) -> Array[Dictionary]:
	var circuit: Array[Dictionary] = [{"gate": "H", "wires": [0]}]
	if index == 0:
		return circuit
	if index == 4:
		circuit.append_array([{"gate": "RZ", "wires": [0], "angle": PI}, {"gate": "H", "wires": [0]}])
	else:
		circuit.append({"gate": "CX", "wires": [0, 1]})
		match index:
			2: circuit.append_array([{"gate": "H", "wires": [2]}, {"gate": "CX", "wires": [2, 3]}])
			3: circuit.append_array([{"gate": "CX", "wires": [0, 2]}, {"gate": "CX", "wires": [0, 3]}])
	circuit.append({"gate": "M", "wires": range(EXAMPLE_WIDTHS[index])})
	return circuit


func _row(parent: Node, gap: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	parent.add_child(row)
	return row


func _stack(parent: Node, gap: int) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", gap)
	parent.add_child(stack)
	return stack


func _space(parent: Node) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


func _margin(parent: Node, x: int, y: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, x)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, y)
	parent.add_child(margin)
	return margin


func _card(parent: Node, fill: Color, x: int, y: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(fill, Palette.BORDER, 11, x, y))
	parent.add_child(card)
	return card


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _heading(parent: Node, text: String, size: int) -> Label:
	var label := _label(parent, text, size, Palette.INK)
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.52
	label.add_theme_font_override("font", font)
	return label


func _button(parent: Node, caption: String, action: Callable, hint: String = "") -> Button:
	var button := Button.new()
	button.text = caption
	button.tooltip_text = hint
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	parent.add_child(button)
	return button
