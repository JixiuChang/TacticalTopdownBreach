# res://Prefabs/camera_rig.gd
extends Node3D

enum FreecamToggle { ON, OFF }

## World Y of the rig (horizontal pan plane / pivot height above ground at y=0).
@export var camera_height: float = 2.0
@export var camera_height_min: float = 0.2
@export var camera_height_max: float = 8.0

## ON = perspective free camera; OFF = orthographic top-down.
@export var freecam_toggle: FreecamToggle = FreecamToggle.ON
@export var move_speed: float = 12.0
@export var pan_speed: float = 0.02
@export var orbit_speed: float = 0.22
## MMB: `_yaw` is radians, `_pitch` is degrees; vertical delta uses the same radian rate as horizontal then `rad_to_deg`, so equal mults = equal orbit speed.
@export var freecam_mmb_yaw_mult: float = 1.0
## Match `freecam_mmb_yaw_mult` for same sideways vs vertical drag speed (fixed arm; wheel zooms).
@export var freecam_mmb_pitch_mult: float = 1.0
@export var zoom_step: float = 1.08

@export var arm_min_user: float = 4.0
@export var arm_max: float = 90.0

@export var pitch_min: float = -85.0
@export var pitch_max: float = -18.0

@export var top_down_arm: float = 22.0
@export var top_down_ortho_size: float = 22.0
## Ortho frustum half-extent at startup `top_down_arm`; wheel changes arm and scales size so zoom is visible.
## Top-down **middle** button: horizontal drag only (yaw). Vertical mouse motion ignored.
@export var top_down_rmb_drag_scale: float = 0.01
## Top-down **right** button pan on XZ like WASD (mouse up = same world delta as `camera_back`).
@export var top_down_mmb_pan_mult: float = 0.02

@export_group("Defaults: freecam (first toggle into mode / I key)")
@export var freecam_default_position_xz: Vector2 = Vector2.ZERO
@export var freecam_default_yaw_degrees: float = 0.0
@export var freecam_default_pitch_degrees: float = -35.0
@export var freecam_default_arm: float = 20.0

@export_group("Defaults: top-down (first toggle into mode / I key)")
@export var topdown_default_position_xz: Vector2 = Vector2.ZERO
@export var topdown_default_yaw_degrees: float = 0.0
@export var topdown_default_arm: float = 22.0
@export var topdown_default_ortho_size: float = 22.0
@export var topdown_default_pitch_degrees: float = -90.0

## When pitch would put the camera through the floor, freecam arm is floored by this margin above y=0.
@export var zoom_margin_above_plane: float = 0.6

@export var action_toggle: StringName = &"toggle_freecam"
@export var action_reset_camera: StringName = &"camera_reset_defaults"
@export var action_fwd: StringName = &"camera_forward"
@export var action_back: StringName = &"camera_back"
@export var action_left: StringName = &"camera_left"
@export var action_right: StringName = &"camera_right"
@export var action_height_down: StringName = &"floorplan_down"
@export var action_height_up: StringName = &"floorplan_up"
@export var camera_height_adjust_speed: float = 3.0

@onready var pivot: Node3D = $Pivot
@onready var cam: Camera3D = $Pivot/Camera3D

var _arm: float = 20.0
var _yaw: float = 0.0
var _pitch: float = -35.0
## Euler X in degrees while orthographic top-down (starts straight down).
var _top_down_pitch_deg: float = -90.0
var _rmb: bool = false
var _mmb: bool = false
## Baseline arm for pairing `top_down_ortho_size` with scroll-adjusted `top_down_arm` (ortho alone ignores depth).
var _top_down_arm_ortho_ref: float = 22.0

var _freecam_has_snapshot: bool = false
var _fc_px: float
var _fc_pz: float
var _fc_yaw: float
var _fc_pitch: float
var _fc_arm: float

var _topdown_has_snapshot: bool = false
var _td_px: float
var _td_pz: float
var _td_yaw: float
var _td_arm: float
var _td_ortho: float
var _td_ortho_ref: float


func _ready() -> void:
	cam.current = true
	camera_height = clampf(camera_height, camera_height_min, camera_height_max)
	_arm = clampf(_arm, arm_min_user, arm_max)
	_top_down_arm_ortho_ref = top_down_arm
	_apply_mode(true)


func _physics_process(_delta: float) -> void:
	global_position.y = clampf(camera_height, camera_height_min, camera_height_max)


## Forward (W / screen-up on the ground) and right (D / screen-right), both unit vectors on XZ from current camera pose.
func _camera_planar_forward_right() -> Array:
	var b := cam.global_transform.basis
	var view_xz := Vector3(b.z.x, 0.0, b.z.z)
	var forward: Vector3
	# When look direction is nearly vertical (ortho top-down), `-Z` has no usable XZ projection — use camera +Y (top of viewport).
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
	var ih := Input.get_axis(action_height_down, action_height_up)
	if absf(ih) > 0.001:
		camera_height = clampf(
			camera_height + ih * camera_height_adjust_speed * delta,
			camera_height_min,
			camera_height_max
		)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(action_toggle):
		if freecam_toggle == FreecamToggle.ON:
			_save_freecam_state()
			freecam_toggle = FreecamToggle.OFF
			if _topdown_has_snapshot:
				_restore_topdown_state()
			else:
				_apply_topdown_defaults()
		else:
			_save_topdown_state()
			freecam_toggle = FreecamToggle.ON
			if _freecam_has_snapshot:
				_restore_freecam_state()
			else:
				_apply_freecam_defaults()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(action_reset_camera):
		if freecam_toggle == FreecamToggle.ON:
			_apply_freecam_defaults()
		else:
			_apply_topdown_defaults()
		get_viewport().set_input_as_handled()
		return

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
		if freecam_toggle == FreecamToggle.OFF:
			if _rmb:
				var fr_td := _camera_planar_forward_right()
				var f_td: Vector3 = fr_td[0]
				var r_td: Vector3 = fr_td[1]
				# Same basis as WASD; horizontal drag sign inverted vs raw rel.x (grab-style pan).
				global_position += (f_td * rel.y - r_td * rel.x) * top_down_mmb_pan_mult
				get_viewport().set_input_as_handled()
			elif _mmb:
				var d := orbit_speed * top_down_rmb_drag_scale
				_yaw += rel.x * d
				_apply_top_down_camera()
				get_viewport().set_input_as_handled()
		elif _rmb:
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
			_update_free_camera()
			get_viewport().set_input_as_handled()


## Freecam: wheel up = zoom in (camera moves forward, shorter arm); down = zoom out (back). Top-down wheel inverted vs freecam. Top-down clamps cam Y to [H/2, 2H].
func _zoom_scroll(direction: int, scroll_factor: float = 1.0) -> void:
	var f := maxf(scroll_factor, 0.001)
	var mult := pow(zoom_step, f)
	if freecam_toggle == FreecamToggle.OFF:
		if direction < 0:
			top_down_arm *= mult
		else:
			top_down_arm /= mult
		_apply_top_down_camera()
		return
	if direction < 0:
		_arm /= mult
	else:
		_arm *= mult
	_update_free_camera()


func _min_zoom_cam_world_y() -> float:
	return camera_height_min


func _max_zoom_cam_world_y() -> float:
	return camera_height_max


## Top-down only: arm clamped so camera world Y stays in [H/2, 2H]. Pivot must already be set for top-down.
func _clamp_top_down_arm_for_cam_height(arm_desired: float) -> float:
	var axis_local := Vector3(0.0, 1.0, 0.0)
	var d: Vector3 = pivot.global_transform.basis * axis_local
	if d.length_squared() > 1e-12:
		d = d.normalized()
	var dy: float = d.y
	var y0: float = pivot.global_position.y
	var y_lo := _min_zoom_cam_world_y()
	var y_hi := _max_zoom_cam_world_y()
	var geom_lo := maxf(arm_min_user, zoom_margin_above_plane)
	var arm := maxf(arm_desired, 0.01)
	if absf(dy) > 1e-4:
		var t0 := (y_lo - y0) / dy
		var t1 := (y_hi - y0) / dy
		var t_y_lo := minf(t0, t1)
		var t_y_hi := maxf(t0, t1)
		var t_lo := maxf(t_y_lo, geom_lo)
		var t_hi := t_y_hi
		if t_lo > t_hi:
			arm = t_hi
		else:
			arm = clampf(arm, t_lo, t_hi)
	else:
		var s_lo := maxf(geom_lo, camera_height_min)
		var s_hi := camera_height_max
		arm = clampf(arm, s_lo, s_hi)
	return arm


func _freecam_arm_min_after_pitch() -> float:
	var bz: Vector3 = pivot.global_transform.basis.z
	if bz.y <= 0.001:
		return arm_min_user
	var geom_y := zoom_margin_above_plane / bz.y
	return maxf(arm_min_user, geom_y)


func _pivot_rotation_basis() -> void:
	pivot.rotation = Vector3(deg_to_rad(_pitch), _yaw, 0.0)


func _update_free_camera() -> void:
	if freecam_toggle != FreecamToggle.ON:
		return
	pivot.position = Vector3.ZERO
	_pivot_rotation_basis()
	_arm = clampf(_arm, _freecam_arm_min_after_pitch(), arm_max)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.position = Vector3(0.0, 0.0, _arm)
	cam.rotation = Vector3.ZERO


func _apply_top_down_camera() -> void:
	pivot.position = Vector3.ZERO
	pivot.rotation = Vector3(deg_to_rad(_top_down_pitch_deg), _yaw, 0.0)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_down_arm = _clamp_top_down_arm_for_cam_height(top_down_arm)
	var arm_s := maxf(top_down_arm, 0.01)
	cam.size = top_down_ortho_size * (_top_down_arm_ortho_ref / arm_s)
	_arm = top_down_arm
	cam.position = Vector3(0.0, top_down_arm, 0.0)
	cam.rotation = Vector3.ZERO


func _apply_mode(_initial: bool) -> void:
	if freecam_toggle == FreecamToggle.OFF:
		_apply_top_down_camera()
	else:
		_update_free_camera()


func _save_freecam_state() -> void:
	_fc_px = global_position.x
	_fc_pz = global_position.z
	_fc_yaw = _yaw
	_fc_pitch = _pitch
	_fc_arm = _arm
	_freecam_has_snapshot = true


func _save_topdown_state() -> void:
	_td_px = global_position.x
	_td_pz = global_position.z
	_td_yaw = _yaw
	_td_arm = top_down_arm
	_td_ortho = top_down_ortho_size
	_td_ortho_ref = _top_down_arm_ortho_ref
	_topdown_has_snapshot = true


func _restore_freecam_state() -> void:
	global_position.x = _fc_px
	global_position.z = _fc_pz
	_yaw = _fc_yaw
	_pitch = _fc_pitch
	_arm = _fc_arm
	_update_free_camera()


func _restore_topdown_state() -> void:
	global_position.x = _td_px
	global_position.z = _td_pz
	_yaw = _td_yaw
	top_down_arm = _td_arm
	top_down_ortho_size = _td_ortho
	_top_down_arm_ortho_ref = _td_ortho_ref
	_apply_top_down_camera()


func _apply_freecam_defaults() -> void:
	global_position.x = freecam_default_position_xz.x
	global_position.z = freecam_default_position_xz.y
	_yaw = deg_to_rad(freecam_default_yaw_degrees)
	_pitch = freecam_default_pitch_degrees
	_arm = clampf(freecam_default_arm, arm_min_user, arm_max)
	_update_free_camera()


func _apply_topdown_defaults() -> void:
	global_position.x = topdown_default_position_xz.x
	global_position.z = topdown_default_position_xz.y
	_yaw = deg_to_rad(topdown_default_yaw_degrees)
	_top_down_pitch_deg = topdown_default_pitch_degrees
	top_down_arm = topdown_default_arm
	top_down_ortho_size = topdown_default_ortho_size
	_top_down_arm_ortho_ref = topdown_default_arm
	_apply_top_down_camera()
