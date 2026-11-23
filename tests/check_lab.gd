extends SceneTree

const Quantum = preload("res://game/quantum.gd")
const Qasm = preload("res://game/qasm.gd")
const Lab = preload("res://game/lab.gd")
const XrLab = preload("res://game/xr_lab.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_simulator()
	_check_qasm()
	await _check_workbench()
	await _check_xr_panel()
	print("QEvolution checks finished with %d failures." % failures)
	quit(1 if failures > 0 else 0)


func _check_simulator() -> void:
	for qubit_count in range(1, Quantum.MAX_QUBITS + 1):
		var compact := Quantum.initial(qubit_count)
		_expect(compact.size() == 2 << qubit_count, "State size matches the circuit width")
		for wire in range(qubit_count):
			compact = _apply(compact, "X", [wire])
		var all_wires := range(qubit_count)
		var values := Quantum.probabilities(compact, all_wires)
		_expect(values.size() == 1 << qubit_count and _near(values[-1], 1.0), "Full-width outcome probabilities")
		var compact_metrics := Quantum.metrics(compact)
		_expect(compact_metrics.bloch.size() == qubit_count and _near(compact_metrics.core, 0.0), "Metrics match active qubits")
	var three := _apply(_apply(_apply(Quantum.initial(3), "H", [0]), "CX", [0, 1]), "CX", [0, 2])
	_expect(_near(Quantum.metrics(three).core, 1.0), "GHZ entanglement for three qubits")
	var asymmetric := _apply(Quantum.initial(3), "X", [0])
	_expect(_near(Quantum.probabilities(asymmetric, [0, 1, 2])[4], 1.0), "Histogram labels follow circuit wire order")
	var state := Quantum.initial()
	var initial := Quantum.metrics(state)
	_expect(initial.bloch[0].is_equal_approx(Vector3(0, 0, 1)), "Initial Bloch vector")
	_expect(_near(initial.core, 0) and _near(initial.pairs[0], 0), "Initial separability")
	state = _apply(state, "H", [0])
	_expect(Quantum.metrics(state).bloch[0].is_equal_approx(Vector3.RIGHT), "H creates |+⟩")
	var bell := _apply(state, "CX", [0, 1])
	var metrics := Quantum.metrics(bell)
	_expect(_near(metrics.pairs[0], 1) and _near(metrics.pairs[1], 0), "Bell concurrence")
	_expect(_near(metrics.singles[0], 1) and _near(metrics.singles[2], 0), "Bell one-versus-three cuts")
	_expect(_near(metrics.cuts[0], 0) and _near(metrics.cuts[1], 1) and _near(metrics.core, 0), "Bell partitions")
	var two_pairs := _apply(_apply(bell, "H", [2]), "CX", [2, 3])
	metrics = Quantum.metrics(two_pairs)
	_expect(_near(metrics.pairs[0], 1) and _near(metrics.pairs[5], 1), "Two independent Bell pairs")
	_expect(_near(metrics.cuts[0], 0) and _near(metrics.cuts[2], 2) and _near(metrics.core, 0), "Two bits across a 2|2 cut")

	var ghz := _apply(_apply(bell, "CX", [0, 2]), "CX", [0, 3])
	metrics = Quantum.metrics(ghz)
	_expect(_near(metrics.core, 1) and _near(metrics.pairs[0], 0), "GHZ core without pair concurrence")
	var measurement := Quantum.step(ghz, {"gate": "M", "wires": [0, 1, 2, 3]}, 0.75)
	_expect(_near(measurement.probabilities[0], 0.5) and _near(measurement.probabilities[15], 0.5)
		and measurement.sample == 15, "GHZ outcome distribution and draw")
	_expect(_near(measurement.state[30], 1) and _near(Quantum.metrics(measurement.state).core, 0), "Projection collapses the state")
	var partial := Quantum.step(bell, {"gate": "M", "wires": [1]}, 0.25)
	_expect(_near(partial.probabilities[1], 0.5) and partial.sample == 0 and _near(partial.state[0], 1), "Partial measurement projects partners")
	var ordering := Quantum.step(_apply(Quantum.initial(), "X", [0]), {"gate": "M", "wires": [0, 3]})
	_expect(ordering.sample == 2 and Quantum.bit_string(ordering.sample, 2) == "10", "Measurement label wire order")

	var phase := _apply(_apply(state, "Z", [0]), "H", [0])
	_expect(_near(phase[2], 1), "Z phase becomes observable through interference")
	var y := _apply(Quantum.initial(), "Y", [0])
	_expect(_near(y[2], 0) and _near(y[3], 1), "Y retains the imaginary phase")
	var rx := Quantum.metrics(_apply(Quantum.initial(), "RX", [0], PI / 2)).bloch[0] as Vector3
	var ry := Quantum.metrics(_apply(Quantum.initial(), "RY", [0], PI / 2)).bloch[0] as Vector3
	var rz := Quantum.metrics(_apply(state, "RZ", [0], PI / 2)).bloch[0] as Vector3
	_expect(rx.is_equal_approx(Vector3.DOWN) and ry.is_equal_approx(Vector3.RIGHT)
		and rz.is_equal_approx(Vector3.UP), "Rotation signs and Bloch axes")
	var rzz := _apply(_apply(state, "H", [1]), "RZZ", [0, 1], PI / 2)
	_expect(_near(Quantum.metrics(rzz).pairs[0], 1), "RZZ entangles two |+⟩ qubits")

	var w := Quantum.initial()
	w[0] = 0.0
	for index in [1, 2, 4, 8]:
		w[index * 2] = 0.5
	metrics = Quantum.metrics(w)
	_expect(_near(metrics.pairs[0], 0.5) and _near(metrics.cuts[0], 1.0)
		and _near(metrics.core, 0.8112781245), "Mixed pair concurrence for W₄")


func _check_qasm() -> void:
	var parser := Qasm.new()
	var program := 'OPENQASM 3.0;\ninclude "stdgates.inc";\nqubit[2] a; qubit[2] b;\nbit[2] c;\n'
	program += '/* comment\nwith a ; */ h a; // broadcast\nrx((pi + π) / 4) b[1];\n'
	program += 'cx a[0], b[0]; rzz(-1/2 + 2e-2) b[1], a[0];\nc = measure b;'
	var parsed := parser.parse(program)
	_expect(not parsed.has("error"), "Import a supported OpenQASM program: %s" % parsed.get("error", ""))
	if parsed.has("ops"):
		_expect(parsed.ops.size() == 6 and parsed.ops[2].wires == [3], "Register offsets and broadcast")
		_expect(_near(parsed.ops[2].angle, PI / 2) and _near(parsed.ops[4].angle, -0.48), "QASM angle evaluation")
		var roundtrip := parser.parse(Qasm.encode(parsed.ops))
		_expect(roundtrip.get("ops", []) == parsed.ops, "QASM export and reimport")
	var small := parser.parse("OPENQASM 3.0; qubit[3] q; h q[0];")
	_expect(small.get("qubit_count") == 3, "QASM preserves unused declared qubits")
	var encoded := Qasm.encode(small.ops, small.qubit_count)
	_expect(parser.parse(encoded) == small, "QASM round trip preserves compact register width")

	var reversed := parser.parse("OPENQASM 3.0; qubit[4] q; bit[2] c; measure q[{3, 0}] -> c;")
	_expect(reversed.has("ops") and reversed.ops[0].wires == [3, 0], "Measurement index set and arrow assignment")
	var compact := parser.parse('OPENQASM 3.0; include  "stdgates.inc"; qubit[4]q; rx(1e-45)q[0];')
	_expect(compact.has("ops") and compact.ops[0].angle > 0.0, "Compact syntax and small scientific angles")
	if compact.has("ops"):
		_expect(parser.parse(Qasm.encode(compact.ops)).get("ops", []) == compact.ops, "Small angles survive export")
	var prefix := "OPENQASM 3.0;\nqubit[4] q;\n"
	for invalid in ["swap q[0], q[1];", "reset q[0];", "h() q[0];", "cx q[1], q[1];",
			"rx(1/0) q[0];", "rx(sin(1)) q[0];", "rx(1) q[4];", "h q[0]", "bit[1] c; c = measure q[0];",
			"qubit a;", "measure q[{0, 0}];", "m q[0];", "gate h a { x a; } h q[0];"]:
		_expect(parser.parse(prefix + invalid).has("error"), "Reject invalid input: " + invalid)
	var error := parser.parse(prefix + "// line three\nreset q[0];")
	_expect(error.get("error", "").begins_with("Line 4"), "Validation reports original line number")


func _check_workbench() -> void:
	var lab := Lab.new()
	root.add_child(lab)
	await process_frame
	var board: Control = lab._board
	_expect(lab._qubit_count == 1 and board.qubit_count == 1 and lab.stage.model._arrows.size() == 1
		and lab._ops[0].gate == "H" and lab._next_button.disabled, "Starter circuit uses one wire and one Bloch sphere")
	_expect(lab._palette_buttons["CX"].disabled and lab._palette_buttons["RZZ"].disabled, "Paired gates need two wires")
	_expect(lab._histogram.probabilities == PackedFloat64Array([1.0, 0.0]), "Initial histogram shows |0⟩")
	await _capture("initial")
	lab._run_button.pressed.emit()
	lab._next_button.pressed.emit()
	var superposition: PackedFloat64Array = lab._histogram.probabilities
	_expect(_near(superposition[0], 0.5) and _near(superposition[1], 0.5), "Hadamard updates the live histogram")
	_expect(lab.stage.model._arrows[0].visible and lab._histogram.is_visible_in_tree(), "Hadamard keeps both views visible")
	await _capture("hadamard")
	lab._run_button.pressed.emit()
	for width in range(2, 5):
		lab._add_qubit_button.pressed.emit()
		_expect(lab._qubit_count == width and lab.stage.model._arrows.size() == width
			and lab._histogram.probabilities.size() == 1 << width, "Adding a qubit resizes both views")
	_expect(lab._add_qubit_button.disabled, "Maximum circuit width")
	lab._add_qubit()
	_expect(lab._qubit_count == 4, "Qubits cannot be added beyond the limit")
	lab._undo_button.pressed.emit()
	_expect(lab._qubit_count == 3 and lab.stage.model._arrows.size() == 3, "Undo restores circuit width")
	lab._load_example(1)
	_expect(lab._qubit_count == 2 and lab._ops[2].wires == [0, 1], "Bell example uses two qubits")
	lab._run_button.pressed.emit()
	lab._next_button.pressed.emit()
	lab._next_button.pressed.emit()
	var bell: PackedFloat64Array = lab._histogram.probabilities
	_expect(_near(lab._frames[2].metrics.pairs[0], 1) and _near(bell[0], 0.5) and _near(bell[3], 0.5),
		"Bell pair updates the simulation and both views")
	await _capture("bell")
	lab._next_button.pressed.emit()
	var result: int = lab._frames[3].sample
	_expect(lab.stage.model._arrows.size() == 2 and lab._histogram.is_visible_in_tree()
		and _near(lab._histogram.probabilities[result], 1.0), "Measurement keeps the 3D state visible beside the collapsed probabilities")
	await _capture("measurement")
	lab._back_button.pressed.emit()
	_expect(lab._cursor == 2 and lab._histogram.probabilities == bell, "Back restores the prior probability distribution")
	lab._next_button.pressed.emit()
	_expect(lab._frames[3].sample == result, "Forward preserves the recorded measurement")
	lab._run_button.pressed.emit()
	lab._add_qubit_button.pressed.emit()
	var controlled_gate := {"source": 1, "wire": 0}
	_expect(not board._can_drop_data(board._center(1, 2), controlled_gate), "Paired gate cannot move outside the circuit")
	board._drop_data(board._center(1, 1), controlled_gate)
	_expect(lab._ops[1].wires == [1, 2], "Dragging a paired gate preserves control and target order")
	lab._undo_button.pressed.emit()
	_expect(lab._ops[1].wires == [0, 1], "Undo restores both operands of a moved gate")
	lab._challenge_picker.select(3)
	lab._challenge_picker.item_selected.emit(3)
	lab._palette_buttons["H"].pressed.emit()
	board.slot_used.emit(0, 0, "")
	for wire in [1, 2, 3]:
		board._drop_data(board._center(lab._ops.size(), 0), {"palette_gate": "CX"})
		board.slot_used.emit(lab._ops.size(), wire, "")
	lab._run_button.pressed.emit()
	for i in 4:
		lab._next_button.pressed.emit()
	_expect(lab._solved and _near(lab._frames.back().metrics.core, 1), "Drag/drop and paired placement solve the GHZ challenge")
	lab._model_mode.select(1)
	lab._model_mode.item_selected.emit(1)
	_expect("AB | CD" in lab._model_info.text, "Section selector exposes cut entropy")
	await _capture("ghz")
	lab._run_button.pressed.emit()
	lab._open_qasm()
	lab._qasm_text.text = "OPENQASM 3.0; qubit[4] q; reset q[0];"
	lab._import_qasm()
	_expect(lab._qasm_layer.visible and lab._ops.size() == 4, "Invalid import leaves the circuit intact")
	await _capture("qasm")
	lab._qasm_text.text = "OPENQASM 3.0; qubit[3] q; ry(pi/2) q[2];"
	lab._import_qasm()
	_expect(not lab._qasm_layer.visible and lab._ops.size() == 1 and lab._ops[0].wires == [2] and lab._qubit_count == 3, "Valid QASM replaces the editor circuit")
	lab._undo_button.pressed.emit()
	_expect(lab._ops.size() == 4 and lab._qubit_count == 4, "Undo restores the circuit and width before import")
	_check_qubit_removal(lab)
	lab.queue_free()


func _check_qubit_removal(lab: Control) -> void:
	var source := "OPENQASM 3.0; qubit[4] q; h q[0]; x q[1]; cx q[0], q[1];"
	source += " rx(pi/2) q[3]; cx q[3], q[2]; measure q[{3, 1, 0}]; measure q[1];"
	lab._open_qasm()
	lab._qasm_text.text = source
	lab._import_qasm()
	var popup: PopupMenu = lab._remove_qubit_menu.get_popup()
	_expect(not lab._remove_qubit_menu.disabled and popup.item_count == 4, "Removal menu offers each wire")
	var original: Array = lab._ops.duplicate(true)
	lab._run_button.pressed.emit()
	_expect(lab._remove_qubit_menu.disabled, "Qubit removal is disabled during playback")
	lab._run_button.pressed.emit()
	popup.id_pressed.emit(1)
	_expect(lab._qubit_count == 3 and lab._board.qubit_count == 3 and lab.stage.model._arrows.size() == 3
		and lab._histogram.probabilities.size() == 8 and popup.item_count == 3, "Removing a wire resizes the editor and both views")
	_expect(lab._ops.size() == 4 and lab._ops[0].gate == "H" and lab._ops[1].wires == [2]
		and _near(lab._ops[1].angle, PI / 2) and lab._ops[2].wires == [2, 1]
		and lab._ops[3].gate == "M" and lab._ops[3].wires == [2, 0], "Removal drops affected gates and preserves surviving operands in order")
	lab._undo_button.pressed.emit()
	_expect(lab._qubit_count == 4 and lab._ops == original, "Undo restores the removed wire and its original operations")
	for wire in [3, 2, 1]:
		popup.id_pressed.emit(wire)
	_expect(lab._qubit_count == 1 and lab._remove_qubit_menu.disabled, "Removal stops at one wire")
	lab._remove_qubit(0)
	_expect(lab._qubit_count == 1, "The last qubit cannot be removed")


func _check_xr_panel() -> void:
	if XRServer.get_tracker(&"head") != null:
		return
	var xr := XrLab.new()
	var head := XRPositionalTracker.new()
	head.name = &"head"
	var pose := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	head.set_pose(&"default", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(head)
	root.add_child(xr)
	await process_frame
	await process_frame
	_expect(xr._rig.visible and xr._rig.position.is_equal_approx(pose.origin), "VR stage anchors to tracked head")
	var lab: Control = xr._canvas.get_child(0)
	var stage_rect: Rect2 = lab.stage.get_global_rect()
	var chart_rect: Rect2 = lab._histogram.get_global_rect()
	_expect(not stage_rect.intersects(chart_rect) and Rect2(Vector2.ZERO, Vector2(XrLab.CANVAS_SIZE)).encloses(chart_rect),
		"The model and histogram occupy separate visible areas of the lab")
	var button: Button = lab._palette_buttons["H"]
	var from := button.get_global_rect().get_center()
	var to: Vector2 = lab._board.global_position + lab._board._center(1, 0)
	xr._send_pointer(from, false)
	xr._send_pointer(from, true)
	xr._send_pointer(from + Vector2(20, 0), true)
	xr._send_pointer(to, true)
	xr._send_pointer(to, false)
	_expect(lab._ops.size() == 2 and lab._ops.back().gate == "H", "Viewport pointer can drag a gate onto the board")
	lab._palette_buttons["X"].pressed.emit()
	lab._board.slot_used.emit(1, 0, "")
	lab._add_qubit_button.pressed.emit()
	await process_frame
	var first: Vector2 = lab._board.global_position + lab._board._center(0, 0)
	var moved: Vector2 = lab._board.global_position + lab._board._center(2, 1)
	xr._send_pointer(first, false)
	xr._send_pointer(first, true)
	xr._send_pointer(first + Vector2(20, 0), true)
	xr._send_pointer(moved, true)
	xr._send_pointer(moved, false)
	_expect(lab._ops[0].gate == "X" and lab._ops[2].wires == [1] and lab._selected == 2,
		"Dragging a placed gate changes its order and wire")
	_send_key(xr._canvas, KEY_DELETE)
	_expect(lab._ops.size() == 2 and lab._ops[0].gate == "X", "Delete removes the selected gate")
	lab._undo_button.pressed.emit()
	_expect(lab._ops.size() == 3 and lab._ops[2].wires == [1], "Undo restores the deleted gate")
	lab._undo_button.pressed.emit()
	_expect(lab._ops[0].gate == "H" and lab._ops[1].gate == "X", "Undo restores the original position")
	xr._send_pointer(first, false)
	xr._send_pointer(first, true)
	xr._send_pointer(first, false)
	_expect(lab._selected == 0, "Clicking a gate selects it")
	lab._open_qasm()
	_send_key(xr._canvas, KEY_DELETE)
	_expect(lab._ops.size() == 3, "Delete in OpenQASM leaves the circuit intact")
	lab._close_qasm()
	var picker: OptionButton = lab._challenge_picker
	var center := picker.get_global_rect().get_center()
	xr._send_pointer(center, true)
	xr._send_pointer(center, false)
	await process_frame
	_expect(picker.get_popup().visible, "VR viewport opens an embedded option menu")
	var popup := picker.get_popup()
	var item := Vector2(popup.position) + Vector2(popup.size.x / 2.0, 48)
	xr._send_pointer(item, true)
	xr._send_pointer(item, false)
	_expect(lab._mission == 1, "VR viewport selects an embedded option")
	popup.hide()
	var run: Button = lab._run_button
	lab._load_example(0)
	await process_frame
	var uv := run.get_global_rect().get_center() / Vector2(XrLab.CANVAS_SIZE) - Vector2(0.5, 0.5)
	var hit: Vector3 = xr._panel.to_global(Vector3(uv.x * XrLab.PANEL_SIZE.x, -uv.y * XrLab.PANEL_SIZE.y, 0))
	var hand := XRControllerTracker.new()
	hand.name = &"right_hand"
	var hand_position := Vector3(0.2, 1.2, 0.0)
	hand.set_pose(&"aim", Transform3D(Basis.looking_at(hit - hand_position), hand_position),
		Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(hand)
	hand.set_input(&"trigger_click", true)
	await process_frame
	await process_frame
	hand.set_input(&"trigger_click", false)
	await process_frame
	await process_frame
	_expect(lab._running and xr._pointer.visible, "Tracked controller ray activates playback")
	XRServer.remove_tracker(hand)
	XRServer.remove_tracker(head)
	xr.queue_free()


func _send_key(viewport: Viewport, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	viewport.push_input(event, true)


func _capture(label: String) -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path := argument.trim_prefix("--capture=") + "/" + label + ".png"
			_expect(root.get_texture().get_image().save_png(path) == OK, "Saved " + label + " screenshot")


func _apply(state: PackedFloat64Array, gate: String, wires: Array, angle: float = 0.0) -> PackedFloat64Array:
	return Quantum.step(state, {"gate": gate, "wires": wires, "angle": angle}).state


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 1.0e-6


func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
