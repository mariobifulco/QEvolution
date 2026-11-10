extends Control

const Quantum = preload("res://game/quantum.gd")
const Qasm = preload("res://game/qasm.gd")
const Qpu = preload("res://game/qpu.gd")
const Palette = preload("res://game/skin.gd")
const Board = preload("res://game/board.gd")
const Stage = preload("res://game/stage.gd")
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
const MISSIONS := ["Free lab", "Bell pair", "Two Bell pairs", "Four-way entanglement"]
const GOALS := [
	"Build a circuit freely or choose a challenge.",
	"Entangle A and B maximally while C and D stay pure. Hint: H, then CX.",
	"Create two independent Bell pairs, AB and CD. Look for two bright edges.",
	"Entangle all four qubits across every cut. Aim for a 1-bit core.",
]

signal presentation_changed(metrics: Dictionary, frame: Dictionary, section: int, histogram: bool)

var stage: Control
var _board: Control
var _palette_buttons: Dictionary = {}
var _editor_controls: Array[Control] = []
var _undo_button: Button
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
var _stage_badge: Label
var _model_info: Label
var _model_mode: OptionButton
var _focus_menu: OptionButton
var _wire_readouts: Array[Label] = []
var _challenge_picker: OptionButton
var _challenge_hint: Label
var _qasm_layer: Control
var _qasm_text: TextEdit
var _qasm_status: Label
var _timer: Timer

var _ops: Array[Dictionary] = []
var _undo: Array = []
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

	var root_margin := _margin(self, 28, 20)
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := _stack(root_margin, 13)
	var header := _row(root, 13)
	header.custom_minimum_size.y = 50
	var logo := TextureRect.new()
	logo.texture = ICON
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(45, 45)
	header.add_child(logo)
	var branding := _stack(header, 0)
	branding.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_heading(branding, "QEvolution", 25)
	_label(branding, "Q U A N T U M   C I R C U I T   L A B", 10, Palette.MUTED)
	_space(header)
	_badge(header, "4 QUBITS", Palette.LILAC)
	_badge(header, "●   IDEAL SIMULATOR", Palette.AQUA)

	var columns := _row(root, 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var work := _card(columns, Color("#11172c"), 18, 15)
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.size_flags_stretch_ratio = 1.23
	var work_col := _stack(work, 9)
	_build_workbench(work_col)
	var inspect := _card(columns, Color("#11172c"), 18, 15)
	inspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect.size_flags_stretch_ratio = 1.0
	var inspect_col := _stack(inspect, 9)
	_build_inspector(inspect_col)

	var footer := _row(root, 10)
	_label(footer, "QEVOLUTION  /  STATE VECTOR LAB", 11, Palette.FAINT)
	_space(footer)
	_label(footer, "OpenQASM 3.0     /     Noiseless simulation     /     All-to-all topology", 11, Palette.FAINT)
	_build_qasm_overlay()

	_timer = Timer.new()
	_timer.wait_time = 0.76
	_timer.timeout.connect(_advance)
	add_child(_timer)


func _build_workbench(work: VBoxContainer) -> void:
	var top := _row(work, 8)
	var titles := _stack(top, 1)
	_label(titles, "01  /  WORKBENCH", 12, Palette.AQUA)
	_heading(titles, "Circuit Composer", 32)
	_space(top)
	var examples := MenuButton.new()
	examples.text = "Examples  ▾"
	examples.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(examples)
	for name_ in ["Bell pair", "Two Bell pairs", "GHZ₄", "Phase interference"]:
		examples.get_popup().add_item(name_)
	examples.get_popup().id_pressed.connect(func(id: int): _replace_ops(_example(id), "Example loaded."))
	_editor_controls.append(examples)
	_editor_controls.append(_button(top, "OpenQASM", _open_qasm, "Import or copy OpenQASM 3.0"))
	_label(work, "Place gates on four wires, then replay the state one operation at a time.", 14, Palette.MUTED)

	var tools := _stack(_card(work, Color("#0d1428"), 10, 8), 6)
	var gate_row := _row(tools, 5)
	for gate in Quantum.GATES:
		var tile := _button(gate_row, gate, _arm.bind(gate), GATE_HELP[gate])
		tile.toggle_mode = true
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_color_override("font_color", Palette.gate_color(gate))
		tile.set_drag_forwarding(_drag_gate.bind(gate), Callable(), Callable())
		_palette_buttons[gate] = tile
		_editor_controls.append(tile)

	var angles := _row(tools, 8)
	_label(angles, "ROTATION", 11, Palette.MUTED)
	_angle = SpinBox.new()
	_angle.min_value = -360
	_angle.max_value = 360
	_angle.allow_greater = true
	_angle.allow_lesser = true
	_angle.step = 0.0
	_angle.value = 90.0
	_angle.suffix = "°"
	_angle.custom_minimum_size.x = 92
	_angle.tooltip_text = "Angle for RX, RY, RZ or RZZ in degrees. Select a placed rotation to adjust it."
	_angle.value_changed.connect(_edit_angle)
	angles.add_child(_angle)
	_space(angles)
	_editor_controls.append(_button(angles, "Measure all", _append_measurement, "Append a joint measurement of A, B, C and D"))
	_editor_controls.append(_button(angles, "Select", _arm.bind(""), "Cancel the active tool and select an existing gate"))

	var board_frame := _card(work, Color("#0c1224"), 1, 1)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 242
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	board_frame.add_child(scroll)
	_board = Board.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.slot_used.connect(_use_slot)
	_board.erase_requested.connect(_remove)
	scroll.add_child(_board)

	var edits := _row(work, 6)
	_work_hint = _label(edits, "", 13, Palette.MUTED)
	_work_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_work_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_undo_button = _button(edits, "Undo", _undo_edit, "Undo the last circuit edit")
	_delete_button = _button(edits, "Delete", func(): _remove(_selected), "Delete the selected operation")
	_editor_controls.append(_button(edits, "Clear", func(): _replace_ops([], "Circuit cleared.")))

	var transport := _stack(_card(work, Color("#141d35"), 11, 8), 6)
	var position := _row(transport, 8)
	_step_label = _label(position, "", 12, Palette.AQUA)
	_step_info = _label(position, "", 13, Palette.MUTED)
	_step_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var controls := _row(transport, 6)
	_run_button = _button(controls, "Run circuit", _toggle_run)
	Palette.accent(_run_button)
	_space(controls)
	_restart_button = _button(controls, "New run", _restart, "Return to the start and draw new measurement samples")
	_back_button = _button(controls, "← Back", func(): _show_step(_cursor - 1), "Return to the previous state")
	_play_button = _button(controls, "▶ Play", _toggle_play)
	_next_button = _button(controls, "Next →", func(): _show_step(_cursor + 1), "Apply the next operation")

	var challenge := _stack(_card(work, Color("#171a34"), 11, 7), 2)
	var challenge_row := _row(challenge, 8)
	_label(challenge_row, "◇   CHALLENGE", 11, Palette.LILAC)
	_space(challenge_row)
	_challenge_picker = OptionButton.new()
	for title in MISSIONS:
		_challenge_picker.add_item(title)
	_challenge_picker.item_selected.connect(_choose_mission)
	challenge_row.add_child(_challenge_picker)
	_challenge_hint = _label(challenge, "", 13, Palette.MUTED)


func _build_inspector(inspect: VBoxContainer) -> void:
	var top := _row(inspect, 8)
	var titles := _stack(top, 1)
	_label(titles, "02  /  STATE VISUALIZER", 12, Palette.AQUA)
	_heading(titles, "Quantum Processor", 32)
	_space(top)
	_badge(top, "LIVE MODEL", Palette.LILAC)
	_label(inspect, "A tetrahedron of local states and entanglement.", 14, Palette.MUTED)

	stage = Stage.new()
	stage.custom_minimum_size.y = 346
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspect.add_child(stage)
	var overlay := _margin(stage, 23, 20)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var overlay_col := _stack(overlay, 5)
	overlay_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_badge = _label(overlay_col, "", 11, Palette.AQUA)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_col.add_child(spacer)
	_label(overlay_col, "DRAG TO ORBIT   /   SCROLL TO ZOOM", 10, Palette.MUTED)

	var view_controls := _row(inspect, 5)
	_model_mode = OptionButton.new()
	for label in ["Tetrahedron", "AB | CD", "AC | BD", "AD | BC", "Histogram"]:
		_model_mode.add_item(label)
	_model_mode.set_item_disabled(4, true)
	_model_mode.item_selected.connect(func(_index: int): _render_model())
	view_controls.add_child(_model_mode)
	_focus_menu = OptionButton.new()
	for label in ["Focus: all", "Focus: A", "Focus: B", "Focus: C", "Focus: D"]:
		_focus_menu.add_item(label)
	_focus_menu.item_selected.connect(func(index: int): stage.focus_on(index - 1))
	view_controls.add_child(_focus_menu)
	_space(view_controls)
	_button(view_controls, "⟲", func(): stage.orbit(-0.24), "Orbit left")
	_button(view_controls, "⟳", func(): stage.orbit(0.24), "Orbit right")
	_button(view_controls, "−", func(): stage.magnify(1.0 / 1.2), "Zoom out")
	_button(view_controls, "+", func(): stage.magnify(1.2), "Zoom in")
	_button(view_controls, "Reset", _reset_view, "Reset the camera")
	_model_info = _label(inspect, "", 14, Palette.AQUA)

	var readouts := _row(inspect, 6)
	for wire in 4:
		var card := _card(readouts, Color("#101a30"), 8, 5)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tile := _stack(card, 1)
		_label(tile, "%s  /  q%d" % [Qpu.NAMES[wire], wire], 12, Qpu.COLORS[wire])
		_wire_readouts.append(_label(tile, "", 12, Palette.INK))
	_label(inspect, "VECTOR  Bloch length    /    EDGE  Concurrence    /    FACE  1|3 entropy", 11, Palette.MUTED)
	_label(inspect, "SECTION  2|2 entropy    /    CORE  Minimum entropy across all seven cuts", 11, Palette.MUTED)


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
	if _running:
		return null
	var chip := Label.new()
	chip.text = "  %s  " % gate
	chip.add_theme_color_override("font_color", Palette.gate_color(gate))
	chip.add_theme_stylebox_override("normal", Palette.box(Color("#29304c"), Palette.gate_color(gate)))
	_palette_buttons[gate].set_drag_preview(chip)
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
	elif column < _ops.size():
		_selected = column
		if _ops[column].gate in Quantum.ROTATIONS:
			_angle_is_syncing = true
			_angle.value = rad_to_deg(_ops[column].angle)
			_angle_is_syncing = false
		_refresh_editor()


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
	_insert(_ops.size(), _operation("M", [0, 1, 2, 3]))


func _record_edit() -> void:
	_undo.append(_ops.duplicate())
	if _undo.size() > 40:
		_undo.pop_front()


func _replace_ops(ops: Array[Dictionary], message: String) -> void:
	if _running:
		_toggle_run()
	_record_edit()
	_ops = ops
	_selected = -1
	_pending = Vector2i(-1, -1)
	_armed = ""
	_refresh_editor()
	if not message.is_empty():
		_hint(message)


func _undo_edit() -> void:
	if _undo.is_empty():
		return
	_ops = _undo.pop_back()
	_selected = -1
	_pending = Vector2i(-1, -1)
	_armed = ""
	_refresh_editor()
	_hint("Last edit undone.")


func _remove(index: int) -> void:
	if _running or index < 0 or index >= _ops.size():
		return
	_record_edit()
	_ops.remove_at(index)
	_selected = -1
	_pending = Vector2i(-1, -1)
	_refresh_editor()


func _edit_angle(degrees: float) -> void:
	if _angle_is_syncing or _running or not is_finite(degrees):
		return
	if _selected >= 0 and _ops[_selected].gate in Quantum.ROTATIONS:
		_record_edit()
		_ops[_selected] = _operation(_ops[_selected].gate, _ops[_selected].wires)
		_refresh_editor()


func _refresh_editor() -> void:
	_board.ops = _ops
	_board.pending = _pending
	_board.selected = _selected if not _running else -1
	_board.locked = _running
	_board.refresh()
	for control in _editor_controls:
		control.disabled = _running
	for gate in _palette_buttons:
		_palette_buttons[gate].set_pressed_no_signal(_armed == gate and not _running)
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
		_hint(_describe(_ops[_selected]))
	else:
		_hint("Drag a gate onto a wire, or select a gate and click a slot.")


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
	var initial := Quantum.initial()
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
	_step_label.text = "STEP %02d / %02d" % [_cursor, _ops.size()]
	_step_info.text = "Initial state  |0000⟩" if _cursor == 0 else _describe(_ops[_cursor - 1])


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
	var prev_mode := _model_mode.selected
	_model_mode.set_item_disabled(4, not measurement)
	if measurement:
		_model_mode.select(4)
	elif prev_mode == 4:
		_model_mode.select(0)
	_render_model()
	_check_goal(frame.metrics)


func _render_model() -> void:
	var frame := _frames[_cursor]
	var metrics: Dictionary = frame.metrics
	var mode := _model_mode.selected
	var histogram := mode == 4 and frame.has("probabilities")
	var section := mode - 1 if mode > 0 and mode < 4 else -1
	if stage.histogram != histogram:
		_focus_menu.select(0)
	_focus_menu.disabled = histogram
	stage.display(metrics, frame, section, histogram)
	presentation_changed.emit(metrics, frame, section, histogram)
	for wire in 4:
		_wire_readouts[wire].text = "|r| %.2f   S %.2f" % [metrics.bloch[wire].length(), metrics.singles[wire]]
		_wire_readouts[wire].tooltip_text = "Bloch vector (%.3f, %.3f, %.3f) · Opposite face entropy %.3f bits" % [
			metrics.bloch[wire].x, metrics.bloch[wire].y, metrics.bloch[wire].z, metrics.singles[wire]]
	if histogram:
		var wires := _wire_names(frame.wires)
		var outcome := Quantum.bit_string(frame.sample, frame.wires.size())
		_stage_badge.text = "MEASUREMENT  /  " + " ".join(wires)
		_model_info.text = "Sample  %s    •    %.1f%% chance    •    %s" % [
			outcome, 100.0 * frame.probabilities[frame.sample], " · ".join(wires)]
		var distribution := PackedStringArray()
		for value in frame.probabilities.size():
			if frame.probabilities[value] > Quantum.EPS or value == frame.sample:
				distribution.append("%s   %.2f%%" % [
					Quantum.bit_string(value, frame.wires.size()), 100.0 * frame.probabilities[value]])
		_model_info.tooltip_text = "\n".join(distribution)
	else:
		_stage_badge.text = "PURE STATE  /  |ψ⟩"
		var detail := "Core entropy   %.3f bits" % maxf(metrics.core, 0.0)
		if section >= 0:
			detail += "     •     %s   %.3f bits" % [
				_model_mode.get_item_text(mode), maxf(metrics.cuts[section], 0.0)]
		_model_info.text = detail
		var pairs := PackedStringArray()
		for i in Quantum.PAIRS.size():
			pairs.append("%s   %.3f" % ["".join(_wire_names(Quantum.PAIRS[i])), metrics.pairs[i]])
		_model_info.tooltip_text = "Pair concurrence\n" + "\n".join(pairs)


func _reset_view() -> void:
	stage.reset_view()
	_focus_menu.select(0)


func _choose_mission(index: int) -> void:
	_mission = index
	_solved = false
	if index > 0:
		_replace_ops([], "Build a circuit for this challenge.")
	_refresh_challenge()


func _check_goal(metrics: Dictionary) -> void:
	if _mission == 0 or _solved or not _running:
		return
	match _mission:
		1: _solved = metrics.pairs[0] >= 0.999 and metrics.bloch[2].length() >= 0.999 and metrics.bloch[3].length() >= 0.999
		2: _solved = metrics.pairs[0] >= 0.999 and metrics.pairs[5] >= 0.999
		3: _solved = metrics.core >= 0.999
	_refresh_challenge()


func _refresh_challenge() -> void:
	_challenge_hint.text = "✓  Challenge complete · %s" % MISSIONS[_mission] if _solved else GOALS[_mission]
	_challenge_hint.add_theme_color_override("font_color", Palette.AQUA if _solved else Palette.MUTED)


func _open_qasm() -> void:
	_qasm_text.text = Qasm.encode(_ops)
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
		_replace_ops(parsed.ops, "Loaded %d operations from OpenQASM." % parsed.ops.size())
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


func _example(index: int) -> Array[Dictionary]:
	var circuit: Array[Dictionary] = [{"gate": "H", "wires": [0]}, {"gate": "CX", "wires": [0, 1]}]
	match index:
		1: circuit.append_array([{"gate": "H", "wires": [2]}, {"gate": "CX", "wires": [2, 3]}])
		2: circuit.append_array([{"gate": "CX", "wires": [0, 2]}, {"gate": "CX", "wires": [0, 3]}])
		3:
			circuit = [{"gate": "H", "wires": [0]}, {"gate": "RZ", "wires": [0], "angle": PI},
				{"gate": "H", "wires": [0]}]
	circuit.append({"gate": "M", "wires": [0, 1, 2, 3]})
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


func _badge(parent: Node, text: String, color: Color) -> void:
	var badge := _card(parent, Color("#171f38"), 10, 6)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(badge, text, 11, color)


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
