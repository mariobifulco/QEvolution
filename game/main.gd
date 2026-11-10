extends Node

const Lab = preload("res://game/lab.gd")
const XrLab = preload("res://game/xr_lab.gd")


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		add_child(XrLab.new())
	else:
		add_child(Lab.new())
