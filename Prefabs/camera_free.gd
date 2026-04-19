# res://Prefabs/camera_free.gd
extends Node3D

@export var camera_height: float = 0.0
@export var camera_height_min: float = 0.0
@export var camera_height_max: float = 8.0
@export var move_speed: float = 12.0
@export var pan_speed: float = 0.02
@export var orbit_speed: float = 0.22
@export var freecam_mmb_yaw_mult: float = 1.0
@export var freecam_mmb_pitch_mult: float = 1.0
@export var zoom_step: float = 1.08

@export var freecam_arm_min_user: float = 0.2
@export var freecam_arm_max_user: float = 16.0
@export var pitch_min: float = -85.0
@export var pitch_max: float = -18.0
@export var zoom_margin_above_plane: float = 0.6

@export var default_position_xz: Vector2 = Vector2.ZERO
@export var default_yaw_degrees: float = 0.0
@export var default_pitch_degrees: float = -35.0
@export var default_arm: float = 4.0

@export var action_fwd: StringName = &"camera_forward"
@export var action_back: StringName = &"camera_back"
@export var action_left: StringName = &"camera_left"
@export var action_right: StringName = &"camera_right"
@export var action_height_down: StringName = &"floorplan_down"
@export var action_height_up: StringName = &"floorplan_up"
@export var camera_height_adjust_speed: float = 3.0

@export var tactical_floor_heights: PackedFloat32Array = PackedFloat32Array()
@export var default_tactical_plane_y: float = 0.0

@onready var location: Node3D = $Location
@onready var pivot: Node3D = $Pivot
@onready var cam: Camera3D = $Pivot/Camera3D

var _arm: float = 4.0
var _yaw: float = 0.0
var _pitch: float = -35.0
var _rmb: bool = false
var _mmb: bool = false
var _tactical_floor_index: int = 0


func _ready() -> void:
	cam.current = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if tactical_floor_heights.is_empty():
		camera_height = default_tactical_plane_y
	camera_height = clampf(camera_height, camera_height_min, camera_height_max)
	if tactical_floor_heights.size() >= 2:
		_tactical_floor_index = clampi(_closest_floor_index(camera_height), 0, tactical_floor_heights.size() - 1)
		camera_height = clampf(
			tactical_floor_heights[_tactical_floor_index],
			camera_height_min,
			camera_height_max
		)
	_arm = clampf(_arm, freecam_arm_min_user, freecam_arm_max_user)
	global_position = Vector3.ZERO
	location.position = Vector3.ZERO
	_sync_location()
	_update_camera()


func set_active(active: bool) -> void:
	cam.current = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if active:
		_update_camera()


func reset_to_defaults() -> void:
	global_position = Vector3.ZERO
	location.position = Vector3.ZERO
	global_position.x = default_position_xz.x
	global_position.z = default_position_xz.y
	_yaw = deg_to_rad(default_yaw_degrees)
	_pitch = default_pitch_degrees
	_arm = clampf(default_arm, freecam_arm_min_user, freecam_arm_max_user)
	if tactical_floor_heights.is_empty():
		camera_height = default_tactical_plane_y
	camera_height = clampf(camera_height, camera_height_min, camera_height_max)
	_sync_location()
	_update_camera()


func get_tactical_click_plane_y() -> float:
	if tactical_floor_heights.size() >= 2:
		var i := clampi(_tactical_floor_index, 0, tactical_floor_heights.size() - 1)
		return tactical_floor_heights[i]
	if tactical_floor_heights.size() == 1:
		return tactical_floor_heights[0]
	return camera_height


func get_tactical_floor_index() -> int:
	if tactical_floor_heights.size() >= 2:
		return clampi(_tactical_floor_index, 0, tactical_floor_heights.size() - 1)
	if tactical_floor_heights.size() == 1:
		return 0
	return 0


func _closest_floor_index(world_y: float) -> int:
	var best_i := 0
	var best_d := INF
	for i: int in tactical_floor_heights.size():
		var d := absf(tactical_floor_heights[i] - world_y)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _physics_process(_delta: float) -> void:
	global_position.y = get_tactical_click_plane_y()
	_sync_location()


func _sync_location() -> void:
	location.global_position = Vector3(global_position.x, get_tactical_click_plane_y(), global_position.z)


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


func _process(delta: float) -> void:
	var ix := Input.get_axis(action_left, action_right)
	var iz := Input.get_axis(action_fwd, action_back)
	if absf(ix) > 0.001 or absf(iz) > 0.001:
		var fr := _camera_planar_forward_right()
		var f: Vector3 = fr[0]
		var r: Vector3 = fr[1]
		global_position += (f * (-iz) + r * ix) * move_speed * delta
	if tactical_floor_heights.size() >= 2:
		if Input.is_action_just_pressed(action_height_up):
			_tactical_floor_index = mini(_tactical_floor_index + 1, tactical_floor_heights.size() - 1)
			camera_height = clampf(
				tactical_floor_heights[_tactical_floor_index],
				camera_height_min,
				camera_height_max
			)
		elif Input.is_action_just_pressed(action_height_down):
			_tactical_floor_index = maxi(_tactical_floor_index - 1, 0)
			camera_height = clampf(
				tactical_floor_heights[_tactical_floor_index],
				camera_height_min,
				camera_height_max
			)
	else:
		var ih := Input.get_axis(action_height_down, action_height_up)
		if absf(ih) > 0.001:
			camera_height = clampf(
				camera_height + ih * camera_height_adjust_speed * delta,
				camera_height_min,
				camera_height_max
			)


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
			var sr := cam.global_transform.basis.x
			var sf := Vector3(cam.global_transform.basis.z.x, 0.0, cam.global_transform.basis.z.z)
			if sf.length_squared() > 1e-6:
				sf = sf.normalized()
			var pan := (-sr * rel.x - sf * rel.y) * pan_speed
			global_position.x += pan.x
			global_position.z += pan.z
		elif _mmb:
			var base := orbit_speed * 0.01
			var dy_rad := rel.y * base * freecam_mmb_pitch_mult
			var dx_rad := rel.x * base * freecam_mmb_yaw_mult
			_yaw += dx_rad
			_pitch = clampf(_pitch - rad_to_deg(dy_rad), pitch_min, pitch_max)
			_update_camera()
			get_viewport().set_input_as_handled()


func _zoom_scroll(direction: int, scroll_factor: float = 1.0) -> void:
	var f := maxf(scroll_factor, 0.001)
	var mult := pow(zoom_step, f)
	if direction < 0:
		_arm /= mult
	else:
		_arm *= mult
	_update_camera()


func _freecam_arm_min_after_pitch() -> float:
	var bz: Vector3 = pivot.global_transform.basis.z
	if bz.y <= 0.001:
		return freecam_arm_min_user
	var geom_y := zoom_margin_above_plane / bz.y
	return maxf(freecam_arm_min_user, geom_y)


func _pivot_rotation_basis() -> void:
	pivot.rotation = Vector3(deg_to_rad(_pitch), _yaw, 0.0)


func _update_camera() -> void:
	_sync_location()
	pivot.position = Vector3.ZERO
	_pivot_rotation_basis()
	_arm = clampf(_arm, _freecam_arm_min_after_pitch(), freecam_arm_max_user)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.position = Vector3(0.0, 0.0, _arm)
	cam.rotation = Vector3.ZERO
