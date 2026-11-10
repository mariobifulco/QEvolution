extends Node3D

const Lab = preload("res://game/lab.gd")
const Qpu = preload("res://game/qpu.gd")
const PANEL_SIZE := Vector2(2.12, 1.325)
const CANVAS_SIZE := Vector2i(1440, 900)
const MODEL_ANCHOR := Vector3(1.06, -0.09, -2.8)
const OFF_PANEL := Vector2(-32, -32)

var _canvas: SubViewport
var _rig: Node3D
var _panel: MeshInstance3D
var _model: Node3D
var _pointer: MeshInstance3D
var _hands: Array[XRController3D] = []
var _hand := 0
var _placed := false
var _pressed := false
var _inside := false
var _last_pos := OFF_PANEL
var _scroll_delay := 0.0


func _ready() -> void:
	var origin := XROrigin3D.new()
	add_child(origin)
	origin.add_child(XRCamera3D.new())
	for side in ["right_hand", "left_hand"]:
		var hand := XRController3D.new()
		hand.tracker = side
		hand.pose = &"aim"
		origin.add_child(hand)
		_hands.append(hand)

	_rig = Node3D.new()
	_rig.hide()
	add_child(_rig)
	_canvas = SubViewport.new()
	_canvas.size = CANVAS_SIZE
	_canvas.disable_3d = true
	_canvas.gui_embed_subwindows = true
	_canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_canvas)

	var quad := QuadMesh.new()
	quad.size = PANEL_SIZE
	var screen := StandardMaterial3D.new()
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.albedo_texture = _canvas.get_texture()
	_panel = MeshInstance3D.new()
	_panel.mesh = quad
	_panel.material_override = screen
	_panel.position = Vector3(-0.67, -0.08, -2.8)
	_rig.add_child(_panel)

	_model = Qpu.new()
	_model.position = MODEL_ANCHOR
	_model.scale = Vector3.ONE * 0.32
	_rig.add_child(_model)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-39, -19, 0)
	light.light_energy = 1.35
	_rig.add_child(light)

	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("#f8cb77")
	_pointer = MeshInstance3D.new()
	_pointer.mesh = sphere
	_pointer.material_override = glow
	_pointer.hide()
	add_child(_pointer)

	var lab := Lab.new()
	lab.presentation_changed.connect(_model.display)
	_canvas.add_child(lab)
	lab.stage.view_changed.connect(_arrange_model)
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr != null:
		xr.pose_recentered.connect(func(): _placed = false)
	_arrange_model(lab.stage.yaw, lab.stage.pitch, lab.stage.zoom, lab.stage.focus)


func _arrange_model(yaw: float, pitch: float, zoom: float, focus: int) -> void:
	var center := Qpu.POSITIONS[focus] as Vector3 if focus >= 0 else Vector3.ZERO
	_model.rotation = Vector3(pitch * 0.65 - 0.13, -yaw, 0)
	_model.scale = Vector3.ONE * 0.32 * zoom * (1.45 if focus >= 0 else 1.0)
	_model.position = MODEL_ANCHOR - _model.transform.basis * center


func _process(delta: float) -> void:
	if not _placed:
		var tracker := XRServer.get_tracker(&"head") as XRPositionalTracker
		var pose := tracker.get_pose(&"default") if tracker != null else null
		if pose == null or not pose.has_tracking_data:
			return
		var head_pose := pose.get_adjusted_transform()
		var forward := -head_pose.basis.z
		_rig.position = head_pose.origin
		_rig.rotation.y = atan2(-forward.x, -forward.z)
		_rig.show()
		_placed = true

	var alternate := 1 - _hand
	if not _pressed and _hands[alternate].get_is_active() and (
		not _hands[_hand].get_is_active() or _trigger(_hands[alternate])):
		_hand = alternate
	var hand := _hands[_hand]
	var uv := OFF_PANEL
	_pointer.hide()
	if hand.get_is_active():
		var local := _panel.global_transform.affine_inverse() * hand.global_transform
		var direction := -local.basis.z
		if direction.z < -0.001:
			var distance := -local.origin.z / direction.z
			var hit := local.origin + direction * distance
			if distance > 0.0 and absf(hit.x) < PANEL_SIZE.x / 2.0 and absf(hit.y) < PANEL_SIZE.y / 2.0:
				uv = (Vector2(hit.x, -hit.y) / PANEL_SIZE + Vector2(0.5, 0.5)) * Vector2(CANVAS_SIZE)
				_pointer.global_position = _panel.to_global(hit + Vector3(0, 0, 0.014))
				_pointer.show()
	_send_pointer(uv, hand.get_is_active() and _trigger(hand))
	_scroll_delay -= delta
	if _inside and _scroll_delay <= 0.0:
		var axis: Vector2 = hand.get_vector2(&"primary")
		if absf(axis.x) >= 0.65:
			_send_button(MOUSE_BUTTON_WHEEL_RIGHT if axis.x > 0.0 else MOUSE_BUTTON_WHEEL_LEFT, uv, true)
			_scroll_delay = 0.15


func _trigger(hand: XRController3D) -> bool:
	return hand.is_button_pressed(&"trigger_click") or hand.get_float(&"trigger") > 0.65 \
		or hand.is_button_pressed(&"ax_button")


func _send_pointer(pos: Vector2, held: bool) -> void:
	var inside := pos != OFF_PANEL
	if inside and not _inside:
		_canvas.notify_mouse_entered()
	if pos != _last_pos:
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.relative = pos - _last_pos if inside and _inside else Vector2.ZERO
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
		_canvas.push_input(motion, true)
	if _pressed and not held:
		_pressed = false
		_send_button(MOUSE_BUTTON_LEFT, pos, false)
	elif not _pressed and held and inside:
		_pressed = true
		_send_button(MOUSE_BUTTON_LEFT, pos, true)
	if not inside and _inside:
		_canvas.notify_mouse_exited()
	_inside = inside
	_last_pos = pos


func _send_button(button: MouseButton, pos: Vector2, down: bool) -> void:
	var click := InputEventMouseButton.new()
	click.position = pos
	click.global_position = pos
	click.button_index = button
	click.pressed = down
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	_canvas.push_input(click, true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_canvas.push_input(event, true)
		get_viewport().set_input_as_handled()
