# res://UI/Cursor/game_cursor.gd
## Custom in-game cursor: texture + hover/selection visuals. Click routing is handled elsewhere.
class_name GameCursor
extends CanvasLayer

const GROUP_INTERACTIBLE := &"cursor_interactible"

const TEX_POINTER := preload("res://Assets/Cursor/pointer_l.png")
const TEX_HAND_OPEN := preload("res://Assets/Cursor/hand_open.png")
const TEX_HAND_CLOSED := preload("res://Assets/Cursor/hand_closed.png")
const TEX_HAND_POINT := preload("res://Assets/Cursor/hand_point.png")

## Physics layers: Ground (1) + units (2). Put doors/hostages on one of these and add to group `cursor_interactible`.
@export var ray_collision_mask: int = 1 | 2
@export var ray_length: float = 4096.0

@export var hotspot_pointer: Vector2 = Vector2(29.0, 23.0)
@export var hotspot_hand: Vector2 = Vector2(16.0, 8.0)
## Uniform scale for drawn cursor vs source art (hotspot uses the same factor for alignment).
@export var cursor_base_scale: float = 0.5

@export var tilt_degrees: float = -9.0
@export var click_scale: float = 0.9
@export var shake_duration: float = 0.3
@export var shake_amplitude_px: float = 10.0

@onready var _follower: Control = $Follower
@onready var _inner: Control = $Follower/Inner
@onready var _sprite: TextureRect = $Follower/Inner/TextureRect

var _input_router: Node
var _shake_tween: Tween
var _mod_tween: Tween
var _was_interactible_hover: bool = false


func _ready() -> void:
	layer = 100
	_input_router = get_node_or_null("/root/InputRouter")
	_inner.pivot_offset = hotspot_hand
	_sprite.texture = TEX_POINTER
	_sprite.custom_minimum_size = TEX_POINTER.get_size()
	_reset_visual_state()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var over_ui := _is_mouse_over_blocking_ui()

	if over_ui:
		_apply_texture(TEX_POINTER, hotspot_pointer)
		_reset_visual_state()
		_follower.global_position = mouse - _hotspot_pointer_screen()
		_was_interactible_hover = false
		return

	var panning := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	if panning:
		_apply_texture(TEX_HAND_CLOSED, hotspot_hand)
		_reset_visual_state()
		_follower.global_position = mouse - _hotspot_hand_screen()
		_was_interactible_hover = false
		return

	var hit := _raycast_cursor(mouse)
	var selected: Node = _input_router.get_selected_unit() if _input_router and _input_router.has_method("get_selected_unit") else null

	var hovering_unit: bool = false
	var unit_node: Node = null
	var hovering_interact: bool = false

	if hit:
		var c: Object = hit.get("collider")
		if c is Node and _resolve_unit_from_hit(c as Node) != null:
			hovering_unit = true
			unit_node = _resolve_unit_from_hit(c as Node)
		elif c is Node and (c as Node).is_in_group(GROUP_INTERACTIBLE):
			hovering_interact = true

	if hovering_unit:
		if selected and unit_node == selected:
			_apply_texture(TEX_HAND_CLOSED, hotspot_hand)
		else:
			_apply_texture(TEX_HAND_OPEN, hotspot_hand)
		_reset_visual_state()
		_apply_left_click_pose()
		_follower.global_position = mouse - _hotspot_hand_screen()
		_was_interactible_hover = false
		return

	if hovering_interact:
		_apply_texture(TEX_HAND_POINT, hotspot_hand)
		var has_selection := selected != null
		var clicking := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

		if has_selection or clicking:
			_stop_shake_tweens()
			_inner.position = Vector2.ZERO
			_inner.rotation_degrees = tilt_degrees
			_inner.scale = _scale_click()
		else:
			_inner.rotation_degrees = 0.0
			_inner.scale = _scale_rest()
			if not _was_interactible_hover:
				_play_interactible_need_selection_feedback()

		_follower.global_position = mouse - _hotspot_hand_screen()
		_was_interactible_hover = true
		return

	_was_interactible_hover = false
	_stop_shake_tweens()
	_apply_texture(TEX_POINTER, hotspot_pointer)
	_reset_visual_state()
	_apply_left_click_pose()
	_follower.global_position = mouse - _hotspot_pointer_screen()


func _hotspot_pointer_screen() -> Vector2:
	return hotspot_pointer * cursor_base_scale


func _hotspot_hand_screen() -> Vector2:
	return hotspot_hand * cursor_base_scale


func _scale_rest() -> Vector2:
	return Vector2(cursor_base_scale, cursor_base_scale)


func _scale_click() -> Vector2:
	return Vector2(cursor_base_scale * click_scale, cursor_base_scale * click_scale)


func _apply_left_click_pose() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_inner.rotation_degrees = tilt_degrees
	_inner.scale = _scale_click()


func _is_mouse_over_blocking_ui() -> bool:
	var c: Control = get_viewport().gui_get_hovered_control()
	if c == null:
		return false
	return c.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _raycast_cursor(screen_pos: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var ray := CameraScreenRay.world_ray_for_pick(cam, screen_pos)
	var from: Vector3 = ray["origin"]
	var dir: Vector3 = ray["dir"]
	var to := from + dir * ray_length
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = ray_collision_mask
	return space.intersect_ray(q)


func _is_unit_collider(n: Node) -> bool:
	if n.has_method(&"is_unit"):
		return bool(n.call(&"is_unit"))
	return false


func _resolve_unit_from_hit(n: Node) -> Node:
	var p: Node = n
	while p != null:
		if _is_unit_collider(p):
			return p
		p = p.get_parent()
	return null


func _apply_texture(tex: Texture2D, _hotspot: Vector2) -> void:
	if _sprite.texture != tex:
		_sprite.texture = tex
		_sprite.custom_minimum_size = tex.get_size()


func _reset_visual_state() -> void:
	_stop_shake_tweens()
	_inner.position = Vector2.ZERO
	_inner.rotation_degrees = 0.0
	_inner.scale = _scale_rest()
	_sprite.modulate = Color.WHITE


func _stop_shake_tweens() -> void:
	if _shake_tween != null:
		_shake_tween.kill()
		_shake_tween = null
	if _mod_tween != null:
		_mod_tween.kill()
		_mod_tween = null


func _play_interactible_need_selection_feedback() -> void:
	_stop_shake_tweens()
	_inner.rotation_degrees = 0.0
	_inner.scale = _scale_rest()
	_inner.position = Vector2.ZERO
	_sprite.modulate = Color.WHITE

	var amp := shake_amplitude_px * cursor_base_scale
	var seg := shake_duration / 4.0
	_shake_tween = create_tween()
	_shake_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shake_tween.tween_property(_inner, "position:x", amp, seg)
	_shake_tween.tween_property(_inner, "position:x", -amp, seg)
	_shake_tween.tween_property(_inner, "position:x", amp * 0.45, seg)
	_shake_tween.tween_property(_inner, "position:x", 0.0, seg)

	_mod_tween = create_tween()
	_mod_tween.tween_property(_sprite, "modulate", Color(1.0, 0.35, 0.35, 1.0), shake_duration * 0.4)
	_mod_tween.tween_property(_sprite, "modulate", Color.WHITE, shake_duration * 0.6).set_delay(shake_duration * 0.4)
