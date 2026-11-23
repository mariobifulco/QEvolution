extends RefCounted
## A deliberately bounded OpenQASM 3.0 circuit importer.

const Quantum = preload("res://game/quantum.gd")
const RZZ := "gate rzz(theta) a, b { cx a, b; rz(theta) b; cx a, b; }"
const IDENT := "[A-Za-z_][A-Za-z_0-9]*"
const NUMBER := "(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?"

var _header := RegEx.create_from_string("^\\s*OPENQASM\\s+3\\.0\\s*;")
var _comments := RegEx.create_from_string("(?s)/\\*.*?\\*/|//[^\\r\\n]*")
var _rzz := RegEx.create_from_string(
	"^gate\\s+rzz\\s*\\(\\s*theta\\s*\\)\\s+a\\s*,\\s*b\\s*\\{"
	+ "\\s*cx\\s+a\\s*,\\s*b\\s*;\\s*rz\\s*\\(\\s*theta\\s*\\)\\s*b\\s*;"
	+ "\\s*cx\\s+a\\s*,\\s*b\\s*;\\s*\\}")
var _include := RegEx.create_from_string('^include\\s+"stdgates\\.inc"$')
var _declaration := RegEx.create_from_string("^(qubit|bit)(?:\\s*\\[\\s*([0-9]+)\\s*\\]\\s*|\\s+)(" + IDENT + ")$")
var _legacy := RegEx.create_from_string("^(qreg|creg)\\s+(" + IDENT + ")\\s*\\[\\s*([0-9]+)\\s*\\]$")
var _ref := RegEx.create_from_string("^(" + IDENT + ")(?:\\s*\\[\\s*([0-9]+|\\{[0-9,\\s]+\\})\\s*\\])?$")
var _measure := RegEx.create_from_string("(?s)^(?:(.+?)\\s*=\\s*)?measure\\s+(.+?)(?:\\s*->\\s*(.+))?$")
var _gate := RegEx.create_from_string("(?s)^(" + IDENT + ")(?:\\s*\\((.*)\\)\\s*|\\s+)(.+)$")
var _comma := RegEx.create_from_string(",(?![^\\[]*\\])")
var _angle_token := RegEx.create_from_string(NUMBER + "|pi|tau|euler|π|τ|ℇ|[()+*/-]|\\s+")


func parse(source: String) -> Dictionary:
	if source.length() > 65536:
		return {"error": "OpenQASM input is limited to 65,536 characters."}
	var chunks := PackedStringArray()
	var previous_end := 0
	for comment in _comments.search_all(source):
		chunks.append(source.substr(previous_end, comment.get_start() - previous_end))
		chunks.append(" " + "\n".repeat(comment.get_string().count("\n")))
		previous_end = comment.get_end()
	chunks.append(source.substr(previous_end))
	source = "".join(chunks).trim_prefix("\uFEFF")
	var header := _header.search(source)
	if header == null:
		return {"error": "Start the program with OPENQASM 3.0;"}

	var qubits := {}
	var bits := {}
	var ops: Array[Dictionary] = []
	var qubit_count := 0
	var include_seen := false
	var rzz_seen := false
	var cursor := header.get_end()
	while cursor < source.length():
		while cursor < source.length() and source[cursor] in " \t\r\n":
			cursor += 1
		if cursor == source.length():
			break
		var line := source.count("\n", 0, cursor) + 1
		var definition := _rzz.search(source.substr(cursor))
		if definition != null:
			if rzz_seen:
				return _error(line, "RZZ is already defined.")
			rzz_seen = true
			cursor += definition.get_end()
			continue
		var end := source.find(";", cursor)
		if end == -1:
			return _error(line, "Expected a semicolon.")
		var statement := source.substr(cursor, end - cursor).strip_edges()
		cursor = end + 1
		if _include.search(statement) != null:
			if include_seen:
				return _error(line, "stdgates.inc was already included.")
			include_seen = true
			continue

		var declaration := _declaration.search(statement)
		var legacy := _legacy.search(statement)
		if declaration != null or legacy != null:
			var match_: RegExMatch = declaration if declaration != null else legacy
			var kind := match_.get_string(1)
			var size := match_.get_string(2 if declaration != null else 3)
			var name := match_.get_string(3 if declaration != null else 2)
			var width := 1 if size.is_empty() else size.to_int()
			if qubits.has(name) or bits.has(name) or width < 1 or width > Quantum.MAX_QUBITS:
				return _error(line, "Use a unique register name and a size from 1 to 4.")
			var is_qubit := kind in ["qubit", "qreg"]
			var offset := qubit_count if is_qubit else 0
			if is_qubit:
				if qubit_count + width > Quantum.MAX_QUBITS:
					return _error(line, "The QPU has four qubits.")
				qubit_count += width
			var registers: Dictionary = qubits if is_qubit else bits
			registers[name] = {"values": range(offset, offset + width), "vector": not size.is_empty()}
			continue

		var measurement := _measure.search(statement)
		if measurement != null:
			var read := _operand(measurement.get_string(2), qubits)
			if read.is_empty():
				return _error(line, "Measurement must use a declared qubit or register.")
			var left := measurement.get_string(1)
			var right := measurement.get_string(3)
			if not left.is_empty() or not right.is_empty():
				var write := _operand(left if right.is_empty() else right, bits)
				if (not left.is_empty() and not right.is_empty()) or write.is_empty() \
					or write.values.size() != read.values.size() or write.vector != read.vector:
					return _error(line, "Measurement destination must match the qubit operand.")
			ops.append({"gate": "M", "wires": read.values})
		else:
			var call := _gate.search(statement)
			if call == null or call.get_string(1).to_upper() not in Quantum.GATES \
				or call.get_string(1) != call.get_string(1).to_lower() or call.get_string(1) == "m":
				return _error(line, "Unsupported statement or gate. Use H, X, Y, Z, RX, RY, RZ, CX, RZZ or measure.")
			var gate := call.get_string(1).to_upper()
			var angle := 0.0
			if gate in Quantum.ROTATIONS:
				angle = _angle(call.get_string(2))
				if not is_finite(angle):
					return _error(line, "Use a finite angle in radians, such as pi/2.")
			elif call.get_start(2) >= 0:
				return _error(line, "%s takes no angle." % gate)
			var args := call.get_string(3)
			var operands := _comma.sub(args, "\u001f", true).split("\u001f")
			if operands.size() != (2 if gate in ["CX", "RZZ"] else 1):
				return _error(line, "Wrong number of operands for %s." % gate)
			var a := _operand(operands[0], qubits)
			var b := _operand(operands[1], qubits) if operands.size() == 2 else {}
			if a.is_empty() or (operands.size() == 2 and b.is_empty()):
				return _error(line, "Gate operands must reference declared qubits in range.")
			if not b.is_empty() and a.vector and b.vector and a.values.size() != b.values.size():
				return _error(line, "Broadcast registers must have the same size.")
			var width := maxi(a.values.size(), b.values.size() if not b.is_empty() else 1)
			for i in width:
				var wires := [a.values[i if a.vector else 0]]
				if not b.is_empty():
					var other: int = b.values[i if b.vector else 0]
					if other == wires[0]:
						return _error(line, "%s needs two different qubits." % gate)
					wires.append(other)
				ops.append({"gate": gate, "wires": wires, "angle": angle})
		if ops.size() > Quantum.MAX_STEPS:
			return _error(line, "Use at most %d operations." % Quantum.MAX_STEPS)

	if qubit_count == 0:
		return {"error": "Declare at least one qubit, for example qubit[4] q;"}
	return {"ops": ops, "qubit_count": qubit_count}


func _operand(source: String, registers: Dictionary) -> Dictionary:
	var ref := _ref.search(source.strip_edges())
	if ref == null or not registers.has(ref.get_string(1)):
		return {}
	var register: Dictionary = registers[ref.get_string(1)]
	var selector := ref.get_string(2)
	if selector.is_empty():
		return register
	if not register.vector:
		return {}
	var is_set := selector.begins_with("{")
	var indices := selector.trim_prefix("{").trim_suffix("}").split(",")
	var values := []
	for token in indices:
		var index := token.strip_edges()
		if not index.is_valid_int() or index.to_int() >= register.values.size():
			return {}
		var value: int = register.values[index.to_int()]
		if values.has(value):
			return {}
		values.append(value)
	return {"values": values, "vector": is_set}


func _angle(source: String) -> float:
	if source.length() > 256:
		return NAN
	var expression := ""
	var cursor := 0
	var depth := 0
	var expect_value := true
	for match_ in _angle_token.search_all(source):
		if match_.get_start() != cursor:
			return NAN
		cursor = match_.get_end()
		var token := match_.get_string()
		if token.strip_edges().is_empty():
			continue
		match token:
			"(":
				if not expect_value:
					return NAN
				depth += 1
			")":
				if expect_value or depth == 0:
					return NAN
				depth -= 1
			"+", "-":
				if expect_value:
					if token == "-":
						expression += " -"
					continue
				expect_value = true
			"*", "/":
				if expect_value:
					return NAN
				expect_value = true
			_:
				if not expect_value:
					return NAN
				expect_value = false
				match token:
					"pi", "π": token = "PI"
					"tau", "τ": token = "TAU"
					"euler", "ℇ": token = "2.718281828459045"
					_:
						if token.is_valid_int():
							token += ".0"
		expression += " " + token
	if cursor != source.length() or depth != 0 or expect_value:
		return NAN
	var evaluator := Expression.new()
	if evaluator.parse(expression) != OK:
		return NAN
	var result: Variant = evaluator.execute([], null, false, true)
	if evaluator.has_execute_failed() or (not result is float and not result is int):
		return NAN
	return float(result)


func _error(line: int, message: String) -> Dictionary:
	return {"error": "Line %d · %s" % [line, message]}


static func encode(ops: Array[Dictionary], qubit_count: int = Quantum.MAX_QUBITS) -> String:
	var lines := PackedStringArray(["OPENQASM 3.0;", 'include "stdgates.inc";'])
	for op in ops:
		if op.gate == "RZZ":
			lines.append(RZZ)
			break
	lines.append("qubit[%d] q;" % qubit_count)
	lines.append("")
	var all_wires := range(qubit_count)
	for op in ops:
		var operands := PackedStringArray()
		for wire: int in op.wires:
			operands.append("q[%d]" % wire)
		if op.gate == "M":
			if op.wires == all_wires:
				lines.append("measure q;")
			elif op.wires.size() > 1:
				var indices := PackedStringArray()
				for wire: int in op.wires:
					indices.append(str(wire))
				lines.append("measure q[{%s}];" % ", ".join(indices))
			else:
				lines.append("measure %s;" % operands[0])
		else:
			var gate: String = op.gate.to_lower()
			if op.gate in Quantum.ROTATIONS:
				gate += "(" + JSON.stringify(op.angle, "", true, true) + ")"
			lines.append("%s %s;" % [gate, ", ".join(operands)])
	return "\n".join(lines) + "\n"
