# res://Prefabs/camera_map.gd
extends Node3D

@onready var camera_free: Node3D = $CameraFree
@onready var camera_top: Node3D = $CameraTop

var _top_active: bool = false


func _ready() -> void:
	camera_free.global_position = Vector3.ZERO
	camera_top.global_position = Vector3.ZERO
	camera_free.reset_to_defaults()
	camera_top.reset_to_defaults()
	_set_active(false)


func _set_active(use_top: bool) -> void:
	_top_active = use_top
	camera_top.set_active(use_top)
	camera_free.set_active(not use_top)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_alternate"):
		_set_active(not _top_active)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"camera_reset_defaults"):
		if _top_active:
			camera_top.reset_to_defaults()
		else:
			camera_free.reset_to_defaults()
		get_viewport().set_input_as_handled()
