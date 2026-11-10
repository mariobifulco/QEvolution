extends Node3D

const Quantum = preload("res://game/quantum.gd")
const COLORS := [Color("#70f3e5"), Color("#ba9cff"), Color("#f8cb77"), Color("#ff8fac")]
const NAMES := ["A", "B", "C", "D"]
const POSITIONS := [
	Vector3(0.0, 1.58, 0.0),
	Vector3(-1.49, -0.53, 0.86),
	Vector3(1.49, -0.53, 0.86),
	Vector3(0.0, -0.53, -1.72),
]
const RADIUS := 0.36

var _tetra: Node3D
var _histogram: Node3D
var _arrows: Array[Node3D] = []
var _edges: Array[MeshInstance3D] = []
var _faces: Array[MeshInstance3D] = []
var _section: Node3D
var _core: Node3D
var _core_material: StandardMaterial3D


func _ready() -> void:
	_tetra = Node3D.new()
	add_child(_tetra)
	_histogram = Node3D.new()
	add_child(_histogram)
	_histogram.hide()
	for pair in Quantum.PAIRS:
		_edges.append(_beam(_tetra, POSITIONS[pair[0]], POSITIONS[pair[1]], 0.026, Color("#48567c")))
	for wire in 4:
		var triangle := PackedVector3Array()
		for other in 4:
			if other != wire:
				triangle.append(POSITIONS[other])
		_faces.append(_surface(_tetra, triangle, COLORS[wire]))
		_bloch_sphere(wire)

	_section = Node3D.new()
	_tetra.add_child(_section)
	_core = Node3D.new()
	_tetra.add_child(_core)
	_core_material = _material(Color("#ffd077"))
	_core_material.emission_enabled = true
	var nucleus := _ball(_core, Vector3.ZERO, 0.15, _core_material)
	nucleus.mesh.radial_segments = 32
	for axis in [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD]:
		_ring(_core, Vector3.ZERO, axis, 0.25, Color(1.0, 0.77, 0.37, 0.58))
	_core.hide()
	for radius in [0.65, 1.3, 2.15]:
		_ring(self, Vector3(0, -1.17, 0), Vector3.UP, radius, Color(0.33, 0.45, 0.75, 0.19))
	for i in range(-3, 4):
		_path(self, PackedVector3Array([Vector3(i * 0.58, -1.18, -1.74),
			Vector3(i * 0.58, -1.18, 1.74)]), Color(0.35, 0.48, 0.75, 0.075))
		_path(self, PackedVector3Array([Vector3(-1.74, -1.18, i * 0.58),
			Vector3(1.74, -1.18, i * 0.58)]), Color(0.35, 0.48, 0.75, 0.075))


func display(metrics: Dictionary, frame: Dictionary, section: int, histogram: bool) -> void:
	_histogram.visible = histogram and frame.has("probabilities")
	_tetra.visible = not _histogram.visible
	if _histogram.visible:
		_show_histogram(frame)
		return
	for wire in 4:
		var v: Vector3 = metrics.bloch[wire]
		var arrow := _arrows[wire]
		arrow.visible = v.length() > 0.001
		if arrow.visible:
			var direction := Vector3(v.x, v.z, -v.y).normalized()
			var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
			arrow.basis = Basis.looking_at(direction, up).scaled_local(Vector3(1, 1, v.length()))
		var face_color: Color = COLORS[wire]
		face_color.a = metrics.singles[wire] * 0.26
		_faces[wire].material_override.albedo_color = face_color
		_faces[wire].visible = face_color.a > 0.001

	for i in _edges.size():
		var concurrence: float = metrics.pairs[i]
		var edge := _edges[i]
		var radius := 0.015 + concurrence * 0.067
		edge.mesh.top_radius = radius
		edge.mesh.bottom_radius = radius
		edge.material_override.albedo_color = Color("#505e89").lerp(Color("#76f3e4"), concurrence)

	var strength: float = metrics.core
	_core.visible = strength > 0.001
	_core.scale = Vector3.ONE * (0.30 + strength * 1.27)
	_core_material.emission = Color("#ffba54") * (0.45 + strength * 0.55)
	_core_material.emission_energy_multiplier = strength
	_clear(_section)
	if section >= 0:
		_show_section(section, metrics.cuts[section])


func _bloch_sphere(wire: int) -> void:
	var anchor: Vector3 = POSITIONS[wire]
	var color: Color = COLORS[wire]
	_ball(_tetra, anchor, RADIUS, _material(Color(color, 0.14), true))
	_ring(_tetra, anchor, Vector3.UP, RADIUS, Color(color, 0.78))
	_ring(_tetra, anchor, Vector3.FORWARD, RADIUS, Color(color, 0.78))
	_ring(_tetra, anchor, Vector3.RIGHT, RADIUS, Color(color, 0.48))
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_path(_tetra, PackedVector3Array([anchor - axis * RADIUS, anchor + axis * RADIUS]), Color(color, 0.28))
	_ball(_tetra, anchor, 0.027, _material(color))
	_tag(_tetra, "%s  /  q%d" % [NAMES[wire], wire], anchor + Vector3.UP * 0.47, color, 0.006)
	var arrow := Node3D.new()
	arrow.position = anchor
	_tetra.add_child(arrow)
	_beam(arrow, Vector3.ZERO, Vector3.FORWARD * 0.30, 0.022, color)
	var tip := _beam(arrow, Vector3.FORWARD * RADIUS, Vector3.FORWARD * 0.27, 0.054, color)
	tip.mesh.bottom_radius = 0.0
	_arrows.append(arrow)


func _show_section(section: int, entropy: float) -> void:
	var a: Vector3 = POSITIONS[0]
	var b: Vector3 = POSITIONS[section + 1]
	var rest: Array = POSITIONS.duplicate()
	rest.erase(a)
	rest.erase(b)
	var corners := PackedVector3Array([(a + rest[0]) / 2, (a + rest[1]) / 2,
		(b + rest[1]) / 2, (b + rest[0]) / 2])
	var outline := corners.duplicate()
	outline.append(corners[0])
	_path(_section, outline, Color(0.80, 0.67, 1.0, 0.70))
	for i in corners.size():
		corners[i] *= sqrt(clampf(entropy / 2.0, 0.0, 1.0))
	if entropy > 0.001:
		_surface(_section, corners, Color(0.76, 0.57, 1.0, 0.57))


func _show_histogram(frame: Dictionary) -> void:
	_clear(_histogram)
	var values: Array[int] = []
	for i in frame.probabilities.size():
		if frame.probabilities[i] > Quantum.EPS or i == frame.sample:
			values.append(i)
	var spacing := minf(1.85, 4.9 / values.size())
	var half_width := maxf(1.45, values.size() * spacing * 0.53)
	var label_size := minf(0.007, spacing * 0.013)
	for tick in 5:
		var y := -1.06 + 0.6 * tick
		_path(_histogram, PackedVector3Array([
			Vector3(-half_width, y, -0.31), Vector3(half_width, y, -0.31)]), Color("#35466c"))
		_tag(_histogram, "%d%%" % (25 * tick), Vector3(-half_width - 0.21, y, -0.31),
			Color("#9aabd5"), 0.0037)
	for index in values.size():
		var value := values[index]
		var probability: float = frame.probabilities[value]
		var sampled: bool = value == frame.sample
		var color := Color("#f8cb77") if sampled else Color("#70e8dc")
		var base := Vector3((index - (values.size() - 1) / 2.0) * spacing, -1.06, 0.0)
		var height := 2.40 * probability
		_box(_histogram, base + Vector3.UP * height / 2.0, Vector3(spacing * 0.64, height, 0.48),
			color.darkened(0.42))
		_box(_histogram, base + Vector3.UP * height, Vector3(spacing * 0.64, 0.025, 0.48), color)
		var label_pos := base + Vector3(0.0, -0.035, 0.36)
		_tag(_histogram, Quantum.bit_string(value, frame.wires.size()), label_pos, color, label_size)
		_tag(_histogram, "%.1f%%" % (probability * 100.0), base + Vector3.UP * (height + 0.16),
			Color("#edf2ff"), label_size * 0.78)


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _ball(parent: Node3D, pos: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = 2.0 * radius
	mesh.radial_segments = 24
	mesh.rings = 12
	return _mesh(parent, mesh, pos, mat)


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := _material(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.46
	_mesh(parent, mesh, pos, mat)


func _beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 12
	mesh.rings = 0
	var beam := _mesh(parent, mesh, (a + b) / 2.0, _material(color))
	beam.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return beam


func _ring(parent: Node3D, pos: Vector3, normal: Vector3, radius: float, color: Color) -> void:
	var points := PackedVector3Array()
	var orientation := Quaternion(Vector3.UP, normal)
	for i in 65:
		var angle := TAU * i / 64.0
		points.append(pos + orientation * Vector3(cos(angle), 0.0, sin(angle)) * radius)
	_path(parent, points, color)


func _path(parent: Node3D, points: PackedVector3Array, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_mesh(parent, mesh, Vector3.ZERO, _material(color, true))


func _surface(parent: Node3D, corners: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, corners.size() - 1):
		for point in [corners[0], corners[i], corners[i + 1]]:
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	return _mesh(parent, mesh, Vector3.ZERO, _material(color, true))


func _tag(parent: Node3D, caption: String, pos: Vector3, color: Color, pixel: float) -> void:
	var tag := Label3D.new()
	tag.text = caption
	tag.position = pos
	tag.modulate = color
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = pixel
	tag.font_size = 26
	tag.outline_size = 8
	tag.outline_modulate = Color("#0b1228")
	parent.add_child(tag)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
