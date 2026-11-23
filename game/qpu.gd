extends Node3D

const Quantum = preload("res://game/quantum.gd")
const COLORS := [Color("#70f3e5"), Color("#ba9cff"), Color("#f8cb77"), Color("#ff8fac")]
const NAMES := ["A", "B", "C", "D"]
const LAYOUTS := [
	[Vector3.ZERO],
	[Vector3(-0.81, 0.0, 0.0), Vector3(0.81, 0.0, 0.0)],
	[Vector3(0.0, 0.82, 0.0), Vector3(-1.01, -0.56, 0.0), Vector3(1.01, -0.56, 0.0)],
	[Vector3(0.0, 1.32, 0.0), Vector3(-1.31, -0.44, 0.76),
		Vector3(1.31, -0.44, 0.76), Vector3(0.0, -0.44, -1.52)],
]
const RADIUS := 0.36

var qubit_count := 0
var _state_model: Node3D
var _arrows: Array[Node3D] = []
var _edges: Array[MeshInstance3D] = []
var _faces: Array[MeshInstance3D] = []
var _section: Node3D
var _core: Node3D
var _core_material: StandardMaterial3D


func qubit_position(wire: int) -> Vector3:
	return LAYOUTS[qubit_count - 1][wire]


func _build(count: int) -> void:
	qubit_count = count
	if _state_model != null:
		remove_child(_state_model)
		_state_model.queue_free()
	_arrows.clear()
	_edges.clear()
	_faces.clear()
	_state_model = Node3D.new()
	add_child(_state_model)
	for pair in Quantum.pairs_for(count):
		_edges.append(_beam(_state_model, qubit_position(pair[0]), qubit_position(pair[1]),
			0.026, Color("#48567c")))
	for wire in count:
		_bloch_sphere(wire)

	if count == Quantum.MAX_QUBITS:
		for wire in count:
			var triangle := PackedVector3Array()
			for other in count:
				if other != wire:
					triangle.append(qubit_position(other))
			_faces.append(_surface(_state_model, triangle, COLORS[wire]))
		_section = Node3D.new()
		_state_model.add_child(_section)
		_core = Node3D.new()
		_state_model.add_child(_core)
		_core_material = _material(Color("#ffd077"))
		_core_material.emission_enabled = true
		var nucleus := _ball(_core, Vector3.ZERO, 0.15, _core_material)
		nucleus.mesh.radial_segments = 32
		for axis in [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD]:
			_ring(_core, Vector3.ZERO, axis, 0.25, Color(1.0, 0.77, 0.37, 0.58))


func display(metrics: Dictionary, section: int) -> void:
	if qubit_count != metrics.bloch.size():
		_build(metrics.bloch.size())
	for wire in qubit_count:
		var v: Vector3 = metrics.bloch[wire]
		var arrow := _arrows[wire]
		arrow.visible = v.length() > 0.001
		if arrow.visible:
			var direction := Vector3(v.x, v.z, -v.y).normalized()
			var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
			arrow.basis = Basis.looking_at(direction, up).scaled_local(Vector3(1, 1, v.length()))

	for i in _edges.size():
		var concurrence: float = metrics.pairs[i]
		var edge := _edges[i]
		var radius := 0.015 + concurrence * 0.067
		edge.mesh.top_radius = radius
		edge.mesh.bottom_radius = radius
		edge.material_override.albedo_color = Color("#505e89").lerp(Color("#76f3e4"), concurrence)

	if qubit_count != Quantum.MAX_QUBITS:
		return
	for wire in qubit_count:
		var face_color: Color = COLORS[wire]
		face_color.a = metrics.singles[wire] * 0.26
		_faces[wire].material_override.albedo_color = face_color
		_faces[wire].visible = face_color.a > 0.001

	var strength: float = metrics.core
	_core.visible = strength > 0.001
	_core.scale = Vector3.ONE * (0.30 + strength * 1.27)
	_core_material.emission = Color("#ffba54") * (0.45 + strength * 0.55)
	_core_material.emission_energy_multiplier = strength
	_clear(_section)
	if section >= 0:
		_show_section(section, metrics.cuts[section])


func _bloch_sphere(wire: int) -> void:
	var anchor := qubit_position(wire)
	var color: Color = COLORS[wire]
	_ball(_state_model, anchor, RADIUS, _material(Color(color, 0.14), true))
	_ring(_state_model, anchor, Vector3.UP, RADIUS, Color(color, 0.78))
	_ring(_state_model, anchor, Vector3.FORWARD, RADIUS, Color(color, 0.78))
	_ring(_state_model, anchor, Vector3.RIGHT, RADIUS, Color(color, 0.48))
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_path(_state_model, PackedVector3Array([anchor - axis * RADIUS, anchor + axis * RADIUS]), Color(color, 0.28))
	_ball(_state_model, anchor, 0.027, _material(color))
	if qubit_count == 1:
		_tag(_state_model, "X", anchor + Vector3.RIGHT * 0.45, color, 0.004)
		_tag(_state_model, "Y", anchor + Vector3.FORWARD * 0.45, color, 0.004)
		_tag(_state_model, "Z", anchor + Vector3.UP * 0.45, color, 0.004)
	else:
		_tag(_state_model, "%s  /  q%d" % [NAMES[wire], wire], anchor + Vector3.UP * 0.47, color, 0.006)
	var arrow := Node3D.new()
	arrow.position = anchor
	_state_model.add_child(arrow)
	_beam(arrow, Vector3.ZERO, Vector3.FORWARD * 0.30, 0.022, color)
	var tip := _beam(arrow, Vector3.FORWARD * RADIUS, Vector3.FORWARD * 0.27, 0.054, color)
	tip.mesh.bottom_radius = 0.0
	_arrows.append(arrow)


func _show_section(section: int, entropy: float) -> void:
	var a := qubit_position(0)
	var b := qubit_position(section + 1)
	var rest: Array = LAYOUTS[qubit_count - 1].duplicate()
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
