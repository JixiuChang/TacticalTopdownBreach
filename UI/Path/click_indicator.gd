class_name ClickIndicatorFX
extends Node3D

@onready var ring: Node3D = $Ring
@onready var dot: Node3D = $Dot

const DURATION_SEC := 1.0

## Unshaded mesh tint. Default pure white for “neutral” ground clicks; tactical units override via `set_surface_color`.
var _surface_color: Color = Color.WHITE

var _time: float = 0.0


func _ready() -> void:
	if _is_child_of_tactical_unit():
		top_level = true
	scale = Vector3(0.25, 0.25, 0.25)
	_apply_surface_color_recursive(ring, _surface_color)
	_apply_surface_color_recursive(dot, _surface_color)
	_apply_idle_visual_state()
	set_process(false)


func set_surface_color(c: Color) -> void:
	_surface_color = c
	if !is_inside_tree():
		return
	if is_instance_valid(ring):
		_apply_surface_color_recursive(ring, _surface_color)
	if is_instance_valid(dot):
		_apply_surface_color_recursive(dot, _surface_color)


func _apply_idle_visual_state() -> void:
	dot.visible = true
	dot.scale = Vector3.ONE
	ring.visible = false
	ring.scale = Vector3.ONE


## Move to `world_pos` and replay ring shrink; dot stays visible after animation.
func play_at(world_pos: Vector3) -> void:
	rotation_degrees = Vector3(-90, 0, 0)
	global_position = world_pos
	# GLB mesh origins are often not at the root; snap so the dot's world center matches the hit point.
	if is_instance_valid(dot):
		global_position += world_pos - dot.global_position
	visible = true
	_time = 0.0
	dot.visible = true
	dot.scale = Vector3.ONE
	ring.visible = true
	ring.scale = Vector3.ONE
	set_process(true)


func set_idle_at(world_pos: Vector3) -> void:
	rotation_degrees = Vector3(-90, 0, 0)
	global_position = world_pos
	if is_instance_valid(dot):
		global_position += world_pos - dot.global_position
	visible = true
	_apply_idle_visual_state()
	set_process(false)


func _is_child_of_tactical_unit() -> bool:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("is_unit") and bool(n.call("is_unit")):
			return true
		n = n.get_parent()
	return false


func _apply_surface_color_recursive(n: Node, color: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
	for child in n.get_children():
		_apply_surface_color_recursive(child, color)


func _process(delta: float) -> void:
	_time += delta
	var u: float = clampf(_time / DURATION_SEC, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - u, 3.0)
	var scale_val: float = lerpf(1.0, 0.0, eased)
	ring.scale = Vector3.ONE * scale_val
	if u >= 1.0:
		ring.visible = false
		ring.scale = Vector3.ONE
		if not _is_child_of_tactical_unit():
			visible = false
			dot.visible = false
		set_process(false)
