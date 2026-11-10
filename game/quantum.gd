extends RefCounted
## Four-qubit state vector. Complex numbers occupy adjacent real and imaginary doubles.

const PAIRS := [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]
const GATES := ["H", "X", "Y", "Z", "RX", "RY", "RZ", "CX", "RZZ", "M"]
const ROTATIONS := ["RX", "RY", "RZ", "RZZ"]
const MAX_STEPS := 256
const EPS := 1.0e-12


static func initial() -> PackedFloat64Array:
	var state := PackedFloat64Array()
	state.resize(32)
	state[0] = 1.0
	return state


static func step(state: PackedFloat64Array, op: Dictionary, draw: float = 0.0) -> Dictionary:
	var next := state.duplicate()
	var wires: Array = op.wires
	var gate: String = op.gate
	if gate == "M":
		return _measure(next, wires, draw)
	var first := 1 << int(wires[0])
	if gate == "CX":
		var target := 1 << int(wires[1])
		for i in 16:
			if i & first and not i & target:
				for component in 2:
					next[2 * i + component] = state[2 * (i | target) + component]
					next[2 * (i | target) + component] = state[2 * i + component]
	elif gate == "RZZ":
		var second := 1 << int(wires[1])
		for i in 16:
			var parity := bool(i & first) != bool(i & second)
			_phase(next, 2 * i, float(op.angle) * (0.5 if parity else -0.5))
	else:
		var angle: float = op.get("angle", 0.0)
		var c := cos(angle / 2.0)
		var s := sin(angle / 2.0)
		for i in 16:
			if i & first:
				continue
			var a := 2 * i
			var b := 2 * (i | first)
			var ar := state[a]
			var ai := state[a + 1]
			var br := state[b]
			var bi := state[b + 1]
			match gate:
				"H":
					_write(next, a, (ar + br) * sqrt(0.5), (ai + bi) * sqrt(0.5))
					_write(next, b, (ar - br) * sqrt(0.5), (ai - bi) * sqrt(0.5))
				"X":
					_write(next, a, br, bi)
					_write(next, b, ar, ai)
				"Y":
					_write(next, a, bi, -br)
					_write(next, b, -ai, ar)
				"Z":
					_write(next, b, -br, -bi)
				"RX":
					_write(next, a, c * ar + s * bi, c * ai - s * br)
					_write(next, b, c * br + s * ai, c * bi - s * ar)
				"RY":
					_write(next, a, c * ar - s * br, c * ai - s * bi)
					_write(next, b, s * ar + c * br, s * ai + c * bi)
				"RZ":
					_phase(next, a, -angle / 2.0)
					_phase(next, b, angle / 2.0)
	return {"state": next}


static func _write(data: PackedFloat64Array, i: int, re: float, im: float) -> void:
	data[i] = re
	data[i + 1] = im


static func _phase(data: PackedFloat64Array, i: int, angle: float) -> void:
	var re := data[i]
	var im := data[i + 1]
	_write(data, i, re * cos(angle) - im * sin(angle), re * sin(angle) + im * cos(angle))


static func _outcome(index: int, wires: Array) -> int:
	var value := 0
	for wire: int in wires:
		value = (value << 1) | ((index >> wire) & 1)
	return value


static func _measure(state: PackedFloat64Array, wires: Array, draw: float) -> Dictionary:
	var probabilities := PackedFloat64Array()
	probabilities.resize(1 << wires.size())
	for i in 16:
		probabilities[_outcome(i, wires)] += state[2 * i] ** 2 + state[2 * i + 1] ** 2
	var total := 0.0
	for probability in probabilities:
		total += probability
	var remaining := clampf(draw, 0.0, 1.0) * total
	var sampled := 0
	for value in probabilities.size():
		if probabilities[value] > 0.0:
			sampled = value
			remaining -= probabilities[value]
			if remaining < 0.0:
				break
	var norm := sqrt(probabilities[sampled])
	for i in 16:
		var keep := _outcome(i, wires) == sampled
		_write(state, 2 * i, state[2 * i] / norm if keep else 0.0,
			state[2 * i + 1] / norm if keep else 0.0)
	for value in probabilities.size():
		probabilities[value] /= total
	return {"state": state, "probabilities": probabilities, "sample": sampled, "wires": wires}


static func bit_string(value: int, width: int) -> String:
	var result := ""
	for bit in range(width - 1, -1, -1):
		result += str((value >> bit) & 1)
	return result


static func metrics(state: PackedFloat64Array) -> Dictionary:
	var bloch: Array[Vector3] = []
	var singles := PackedFloat64Array()
	for wire in 4:
		var mask := 1 << wire
		var x := 0.0
		var y := 0.0
		var z := 0.0
		for i in 16:
			if i & mask:
				continue
			var a := 2 * i
			var b := 2 * (i | mask)
			x += 2.0 * (state[a] * state[b] + state[a + 1] * state[b + 1])
			y += 2.0 * (state[a] * state[b + 1] - state[a + 1] * state[b])
			z += state[a] ** 2 + state[a + 1] ** 2 - state[b] ** 2 - state[b + 1] ** 2
		var length := clampf(sqrt(x * x + y * y + z * z), 0.0, 1.0)
		bloch.append(Vector3(x, y, z))
		singles.append(_entropy((1.0 + length) / 2.0) + _entropy((1.0 - length) / 2.0))

	var cuts := PackedFloat64Array()
	var concurrence := PackedFloat64Array()
	for pair in PAIRS:
		var matrix := _partition(state, pair)
		# The first three pairs give the three distinct 2|2 cuts.
		if cuts.size() < 3:
			var entropy := 0.0
			for value in _gram_eigenvalues(matrix):
				entropy += _entropy(value)
			cuts.append(entropy)
		concurrence.append(_concurrence(matrix))
	return {"bloch": bloch, "singles": singles, "cuts": cuts,
		"pairs": concurrence, "core": minf(Array(singles).min(), Array(cuts).min())}


static func _entropy(p: float) -> float:
	return -p * log(p) / log(2.0) if p > EPS and p < 1.0 else 0.0


static func _partition(state: PackedFloat64Array, pair: Array) -> PackedFloat64Array:
	var rest := []
	for wire in 4:
		if not pair.has(wire):
			rest.append(wire)
	var matrix := state.duplicate()
	for basis in 16:
		var row := _outcome(basis, pair)
		var col := _outcome(basis, rest)
		_write(matrix, 2 * (4 * row + col), state[2 * basis], state[2 * basis + 1])
	return matrix


static func _concurrence(matrix: PackedFloat64Array) -> float:
	# Wootters' singular values from the ensemble spin-flip overlap F^T (Y ⊗ Y) F.
	# Columns of F are the unnormalized conditional pair states.
	var overlap := PackedFloat64Array()
	overlap.resize(32)
	for i in 4:
		for j in 4:
			var re := 0.0
			var im := 0.0
			for k in 4:
				var a := 2 * (4 * k + i)
				var b := 2 * (4 * (3 - k) + j)
				var sign := -1.0 if k == 0 or k == 3 else 1.0
				re += sign * (matrix[a] * matrix[b] - matrix[a + 1] * matrix[b + 1])
				im += sign * (matrix[a] * matrix[b + 1] + matrix[a + 1] * matrix[b])
			_write(overlap, 2 * (4 * i + j), re, im)
	var largest := 0.0
	var total := 0.0
	for value in _gram_eigenvalues(overlap):
		var singular := sqrt(value) if value > EPS else 0.0
		largest = maxf(largest, singular)
		total += singular
	return clampf(2.0 * largest - total, 0.0, 1.0)


static func _gram_eigenvalues(matrix: PackedFloat64Array) -> PackedFloat64Array:
	# Represent the 4×4 Hermitian Gram matrix as an 8×8 real symmetric matrix.
	# Each eigenvalue appears twice. The small fixed size allows cyclic Jacobi.
	var real := PackedFloat64Array()
	real.resize(64)
	for i in 4:
		for j in 4:
			var re := 0.0
			var im := 0.0
			for k in 4:
				var a := 2 * (4 * k + i)
				var b := 2 * (4 * k + j)
				re += matrix[a] * matrix[b] + matrix[a + 1] * matrix[b + 1]
				im += matrix[a] * matrix[b + 1] - matrix[a + 1] * matrix[b]
			real[i * 8 + j] = re
			real[i * 8 + j + 4] = -im
			real[(i + 4) * 8 + j] = im
			real[(i + 4) * 8 + j + 4] = re

	for sweep in 20:
		var changed := false
		for p in 8:
			for q in range(p + 1, 8):
				var off := real[p * 8 + q]
				if absf(off) < EPS:
					continue
				changed = true
				var pp := real[p * 8 + p]
				var qq := real[q * 8 + q]
				var theta := 0.5 * atan2(2.0 * off, qq - pp)
				var c := cos(theta)
				var s := sin(theta)
				real[p * 8 + p] = c * c * pp - 2.0 * s * c * off + s * s * qq
				real[q * 8 + q] = s * s * pp + 2.0 * s * c * off + c * c * qq
				real[p * 8 + q] = 0.0
				real[q * 8 + p] = 0.0
				for i in 8:
					if i == p or i == q:
						continue
					var a := real[i * 8 + p]
					var b := real[i * 8 + q]
					real[i * 8 + p] = c * a - s * b
					real[p * 8 + i] = real[i * 8 + p]
					real[i * 8 + q] = s * a + c * b
					real[q * 8 + i] = real[i * 8 + q]
		if not changed:
			break
	var diagonal := PackedFloat64Array()
	for i in 8:
		diagonal.append(real[i * 8 + i])
	diagonal.sort()
	return PackedFloat64Array([diagonal[0], diagonal[2], diagonal[4], diagonal[6]])
