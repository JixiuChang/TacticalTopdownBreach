# res://Prefabs/camera_top.gd
extends Node3D

## World Y of the floor anchor (Location). Tactical pick uses this when this camera is current.
@export var anchor_plane_y: float = 0.0
## Minimum distance (m) from anchor plane to camera along world +Y: closest zoom-in limit.
@export var height_min: float = 0.075
## Maximum distance (m) from anchor plane to camera along world +Y: farthest zoom-out limit (raise this to allow zooming farther).
@export var height_max: float = 0.5
@export var move_speed: float = 12.0
@export var zoom_step: float = 1.08
@export var top_down_rmb_drag_scale: float = 0.01
@export var top_down_mmb_pan_mult: float = 0.02
@export var orbit_speed: float = 0.22
@export var top_down_ortho_size: float = 22.0

@export var default_height: float = 0.35
@export var default_yaw_degrees: float = 0.0

@export var action_fwd: StringName = &"camera_forward"
@export var action_back: StringName = &"camera_back"
@export var action_left: StringName = &"camera_left"
@export var action_right: StringName = &"camera_right"

@onready var location: Node3D = $Location
@onready var pivot: Node3D = $Pivot
@onready var cam: Camera3D = $Pivot/Camera3D

var _height: float = 0.35
var _yaw: float = 0.0
var _rmb: bool = false
var _mmb: bool = false
var _ortho_ref: float = 0.35


func _ready() -> void:
	cam.current = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_height = clampf(default_height, height_min, height_max)
	_ortho_ref = _height
	_yaw = deg_to_rad(default_yaw_degrees)
	global_position = Vector3.ZERO
	location.position = Vector3.ZERO
	_apply_camera()


func set_active(active: bool) -> void:
	cam.current = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if active:
		_apply_camera()


func reset_to_defaults() -> void:
	global_position = Vector3.ZERO
	location.position = Vector3.ZERO
	_height = clampf(default_height, height_min, height_max)
	_ortho_ref = _height
	_yaw = deg_to_rad(default_yaw_degrees)
	_apply_camera()


func get_tactical_click_plane_y() -> float:
	return anchor_plane_y


func get_tactical_floor_index() -> int:
	return 0


func _physics_process(_delta: float) -> void:
	global_position.y = anchor_plane_y
	_sync_location()


func _sync_location() -> void:
	location.global_position = Vector3(global_position.x, anchor_plane_y, global_position.z)


func _process(delta: float) -> void:
	var ix := Input.get_axis(action_left, action_right)
	var iz := Input.get_axis(action_fwd, action_back)
	if absf(ix) > 0.001 or absf(iz) > 0.001:
		var fr := _camera_planar_forward_right()
		var f: Vector3 = fr[0]
		var r: Vector3 = fr[1]
		global_position += (f * (-iz) + r * ix) * move_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rmb = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_mmb = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_scroll(-1, event.factor)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_scroll(1, event.factor)
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		if _rmb:
			var fr_td := _camera_planar_forward_right()
			var f_td: Vector3 = fr_td[0]
			var r_td: Vector3 = fr_td[1]
			global_position += (f_td * rel.y - r_td * rel.x) * top_down_mmb_pan_mult
			get_viewport().set_input_as_handled()
		elif _mmb:
			var d := orbit_speed * top_down_rmb_drag_scale
			_yaw += rel.x * d
			_apply_camera()
			get_viewport().set_input_as_handled()


func _zoom_scroll(direction: int, scroll_factor: float = 1.0) -> void:
	var f := maxf(scroll_factor, 0.001)
	var mult := pow(zoom_step, f)
	# Wheel up → move toward `height_min` (closer to anchor / zoom in); wheel down → toward `height_max` (farther / zoom out).
	if direction < 0:
		_height /= mult
	else:
		_height *= mult
	_height = clampf(_height, height_min, height_max)
	_apply_camera()


func _camera_planar_forward_right() -> Array:
	var b := cam.global_transform.basis
	var view_xz := Vector3(b.z.x, 0.0, b.z.z)
	var forward: Vector3
	if view_xz.length_squared() > 1e-8:
		forward = Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	else:
		var up_on_screen := Vector3(b.y.x, 0.0, b.y.z)
		if up_on_screen.length_squared() > 1e-8:
			forward = up_on_screen.normalized()
		else:
			var yaw_basis := Basis.from_euler(Vector3(0.0, _yaw, 0.0))
			var fz := Vector3(-yaw_basis.z.x, 0.0, -yaw_basis.z.z)
			if fz.length_squared() > 1e-8:
				forward = fz.normalized()
			else:
				forward = Vector3(0.0, 0.0, -1.0)
	var right := Vector3(b.x.x, 0.0, b.x.z)
	if right.length_squared() < 1e-8:
		right = Vector3.UP.cross(forward)
		if right.length_squared() < 1e-8:
			right = Vector3(1.0, 0.0, 0.0)
		else:
			right = right.normalized()
	else:
		right = right.normalized()
	return [forward, right]


func _apply_camera() -> void:
	_sync_location()
	pivot.position = Vector3.ZERO
	pivot.rotation = Vector3(0.0, _yaw, 0.0)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0.0, _height, 0.0)
	cam.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	# Larger `_height` (farther from anchor) → larger ortho half-extent → more world visible (zoom out).
	var ref := maxf(_ortho_ref, 0.01)
	cam.size = top_down_ortho_size * (_height / ref)
