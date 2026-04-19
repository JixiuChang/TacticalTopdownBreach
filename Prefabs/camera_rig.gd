# res://Prefabs/camera_rig.gd
extends Node3D

enum FreecamToggle { ON, OFF }

## When `tactical_floor_heights` is empty, this is the tactical floor Y (click plane) and matches rig `global_position.y`. Q/E smooth adjust uses this plane.
@export var camera_height: float = 0.0
@export var camera_height_min: float = 0.0
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

## Perspective: distance pivot→camera along view. Lower bound can rise with pitch via `_freecam_arm_min_after_pitch()`.
@export var freecam_arm_min_user: float = 0.05
@export var freecam_arm_max_user: float = 16.0

## Ortho top-down: 3D distance (m) from floor anchor to camera. Anchor uses `top_down_absolute_plane_y` (world Y), not pivot stacking.
@export var top_down_arm_min_user: float = 0.05
@export var top_down_arm_max_user: float = 0.5

## Top-down: rig `global_position.y` and the Y of the floor anchor for zoom distance. For now world 0; freecam / `get_tactical_click_plane_y()` unchanged for picking.
@export var top_down_absolute_plane_y: float = 0.0

@export var pitch_min: float = -85.0
@export var pitch_max: float = -18.0

@export var top_down_arm: float = 0.25
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
@export var freecam_default_arm: float = 4.0

@export_group("Defaults: top-down (first toggle into mode / I key)")
@export var topdown_default_position_xz: Vector2 = Vector2.ZERO
@export var topdown_default_yaw_degrees: float = 0.0
@export var topdown_default_arm: float = 0.25
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

## 2+ entries: Q/E switches discrete floors (rig Y = that height). 1 entry: fixed plane at that Y. Empty: rig Y / click plane = `camera_height` (initialized from `default_tactical_plane_y` in `_ready`).
@export var tactical_floor_heights: PackedFloat32Array = PackedFloat32Array()
@export var default_tactical_plane_y: float = 0.0

@onready var pivot: Node3D = $Pivot
@onready var cam: Camera3D = $Pivot/Camera3D

var _arm: float = 4.0
var _yaw: float = 0.0
var _pitch: float = -35.0
## Euler X in degrees while orthographic top-down (starts straight down).
var _top_down_pitch_deg: float = -90.0
var _rmb: bool = false
var _mmb: bool = false
## Baseline arm for pairing `top_down_ortho_size` with scroll-adjusted `top_down_arm` (ortho alone ignores depth).
var _top_down_arm_ortho_ref: float = 0.25

var _freecam_has_snapshot: bool = false
var _fc_px: float
var _fc_pz: float
var _fc_yaw: float
var _fc_pitch: float
var _fc_arm: float

var _topdown_has_snapshot: bool = false
var _tactical_floor_index: int = 0
var _td_px: float
var _td_pz: float
var _td_yaw: float
var _td_arm: float
var _td_ortho: float
var _td_ortho_ref: float


func _ready() -> void:
	cam.current = true
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
	top_down_arm = clampf(top_down_arm, top_down_arm_min_user, top_down_arm_max_user)
	_top_down_arm_ortho_ref = top_down_arm
	global_position.x = 0.0
	global_position.z = 0.0
	_sync_rig_plane_y()
	_apply_mode(true)


## World Y for mouse ray ∩ horizontal plane (InputRouter / planning). Empty `tactical_floor_heights`: returns `camera_height` (tactical plane = rig Y).
func get_tactical_click_plane_y() -> float:
	if tactical_floor_heights.size() >= 2:
		var i := clampi(_tactical_floor_index, 0, tactical_floor_heights.size() - 1)
		return tactical_floor_heights[i]
	if tactical_floor_heights.size() == 1:
		return tactical_floor_heights[0]
	return camera_height


## Index into `tactical_floor_heights`（离散楼层时供关卡脚本使用）。
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


func _sync_rig_plane_y() -> void:
	if freecam_toggle == FreecamToggle.OFF:
		global_position.y = top_down_absolute_plane_y
	else:
		global_position.y = get_tactical_click_plane_y()


func _physics_process(_delta: float) -> void:
	_sync_rig_plane_y()


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


func _top_down_floor_anchor_world() -> Vector3:
	return Vector3(global_position.x, top_down_absolute_plane_y, global_position.z)


func _freecam_arm_min_after_pitch() -> float:
	var bz: Vector3 = pivot.global_transform.basis.z
	if bz.y <= 0.001:
		return freecam_arm_min_user
	var geom_y := zoom_margin_above_plane / bz.y
	return maxf(freecam_arm_min_user, geom_y)


func _pivot_rotation_basis() -> void:
	pivot.rotation = Vector3(deg_to_rad(_pitch), _yaw, 0.0)


func _update_free_camera() -> void:
	if freecam_toggle != FreecamToggle.ON:
		return
	pivot.position = Vector3.ZERO
	_pivot_rotation_basis()
	_arm = clampf(_arm, _freecam_arm_min_after_pitch(), freecam_arm_max_user)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.position = Vector3(0.0, 0.0, _arm)
	cam.rotation = Vector3.ZERO


func _apply_top_down_camera() -> void:
	_sync_rig_plane_y()
	# Identity pivot: top-down pose is entirely in `cam` global transform (world pos = intended offset from y=0 plane).
	pivot.position = Vector3.ZERO
	pivot.rotation = Vector3.ZERO
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_down_arm = clampf(top_down_arm, top_down_arm_min_user, top_down_arm_max_user)
	var rx := global_position.x
	var rz := global_position.z
	var py := top_down_absolute_plane_y
	cam.global_position = Vector3(rx, py + top_down_arm, rz)
	cam.global_rotation = Vector3(deg_to_rad(_top_down_pitch_deg), _yaw, 0.0)
	var anchor := _top_down_floor_anchor_world()
	var dist := cam.global_position.distance_to(anchor)
	if dist > 1e-6:
		var d_target := clampf(dist, top_down_arm_min_user, top_down_arm_max_user)
		top_down_arm *= d_target / dist
		cam.global_position = Vector3(rx, py + top_down_arm, rz)
	else:
		top_down_arm = top_down_arm_min_user
		cam.global_position = Vector3(rx, py + top_down_arm, rz)
	var arm_s := maxf(top_down_arm, 0.01)
	cam.size = top_down_ortho_size * (_top_down_arm_ortho_ref / arm_s)
	_arm = top_down_arm


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
	_sync_rig_plane_y()
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
	_arm = clampf(freecam_default_arm, freecam_arm_min_user, freecam_arm_max_user)
	_update_free_camera()


func _apply_topdown_defaults() -> void:
	global_position.x = topdown_default_position_xz.x
	global_position.z = topdown_default_position_xz.y
	_sync_rig_plane_y()
	_yaw = deg_to_rad(topdown_default_yaw_degrees)
	_top_down_pitch_deg = topdown_default_pitch_degrees
	top_down_arm = topdown_default_arm
	top_down_ortho_size = topdown_default_ortho_size
	_top_down_arm_ortho_ref = topdown_default_arm
	_apply_top_down_camera()
