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
	_expect(lab._ops.size() == 3 and lab._next_button.disabled, "Starter circuit and edit state")
	lab._run_button.pressed.emit()
	lab._next_button.pressed.emit()
	lab._next_button.pressed.emit()
	_expect(_near(lab._frames[2].metrics.pairs[0], 1), "Next updates the simulation and visualizer")
	await _capture("bell")
	lab._next_button.pressed.emit()
	var result: int = lab._frames[3].sample
	_expect(lab.stage.histogram and lab._model_mode.selected == 4, "Measurement opens 3D histogram")
	await _capture("measurement")
	lab._back_button.pressed.emit()
	_expect(not lab.stage.histogram and lab._cursor == 2, "Back restores the previous model")
	lab._next_button.pressed.emit()
	_expect(lab._frames[3].sample == result, "Forward preserves the recorded measurement")
	lab._run_button.pressed.emit()
	lab._challenge_picker.select(3)
	lab._challenge_picker.item_selected.emit(3)
	lab._palette_buttons["H"].pressed.emit()
	board.slot_used.emit(0, 0, "")
	for wire in [1, 2, 3]:
		board._drop_data(Vector2(70 + 61 * lab._ops.size() + 30, 53), {"palette_gate": "CX"})
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
	lab._qasm_text.text = "OPENQASM 3.0; qubit[4] q; ry(pi/2) q[2];"
	lab._import_qasm()
	_expect(not lab._qasm_layer.visible and lab._ops.size() == 1 and lab._ops[0].wires == [2], "Valid QASM replaces the editor circuit")
	lab._undo_button.pressed.emit()
	_expect(lab._ops.size() == 4, "Undo restores the circuit before import")
	lab.queue_free()


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
	var button: Button = lab._palette_buttons["H"]
	var from := button.get_global_rect().get_center()
	var to: Vector2 = lab._board.global_position + Vector2(70 + 61 * 3 + 30, 53)
	xr._send_pointer(from, false)
	xr._send_pointer(from, true)
	xr._send_pointer(from + Vector2(20, 0), true)
	xr._send_pointer(to, true)
	xr._send_pointer(to, false)
	_expect(lab._ops.size() == 4 and lab._ops.back().gate == "H", "Viewport pointer can drag a gate onto the board")
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
	lab._ops = lab._example(0)
	lab._refresh_editor()
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
