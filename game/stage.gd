extends Control

const Qpu = preload("res://game/qpu.gd")

signal view_changed(yaw: float, pitch: float, zoom: float, focus: int)

var model: Node3D
var camera: Camera3D
var yaw := 0.41
var pitch := 0.19
var zoom := 1.0
var focus := -1
var _orbiting := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	clip_contents = true
	var canvas := SubViewportContainer.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.stretch = true
	add_child(canvas)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	canvas.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	model = Qpu.new()
	world.add_child(model)
	camera = Camera3D.new()
	camera.fov = 36.0
	camera.current = true
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-43, -28, 0)
	light.light_energy = 1.1
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 130, 0)
	fill.light_color = Color("#9d9cf0")
	fill.light_energy = 0.65
	world.add_child(fill)
	resized.connect(queue_redraw)
	reset_view()


func display(metrics: Dictionary, section: int) -> void:
	var changed: bool = model.qubit_count != metrics.bloch.size()
	model.display(metrics, section)
	if changed:
		reset_view()


func orbit(delta: float) -> void:
	yaw += delta
	_update_camera()


func magnify(factor: float) -> void:
	zoom = clampf(zoom * factor, 0.63, 2.65)
	_update_camera()


func focus_on(wire: int) -> void:
	focus = wire
	zoom = 1.0
	_update_camera()


func reset_view() -> void:
	yaw = 0.41
	pitch = 0.19
	zoom = 1.0
	focus = -1
	_update_camera()


func _update_camera() -> void:
	var center := Vector3(0, 0.10, 0)
	var distance := float([2.5, 3.65, 4.7, 5.8][maxi(0, model.qubit_count - 1)])
	if focus >= 0:
		center = model.qubit_position(focus)
		distance = 2.25
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = center + direction * distance / zoom
	camera.look_at(center)
	view_changed.emit(yaw, pitch, zoom, focus)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			magnify(1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)
		else:
			return
		accept_event()
	elif event is InputEventMouseMotion and _orbiting:
		yaw -= event.relative.x * 0.012
		pitch = clampf(pitch + event.relative.y * 0.012, -1.25, 1.25)
		_update_camera()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b1228"))
	for x in range(16, int(size.x), 24):
		for y in range(16, int(size.y), 24):
			draw_circle(Vector2(x, y), 0.75, Color(0.40, 0.50, 0.76, 0.20))
