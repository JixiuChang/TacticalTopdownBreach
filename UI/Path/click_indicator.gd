class_name ClickIndicatorFX
extends Node3D

@onready var ring: Node3D = $Ring
@onready var dot: Node3D = $Dot

const DURATION_SEC := 1.0
const LIGHT_BLUE := Color(0.68, 0.88, 1.0, 1.0)

var _time: float = 0.0


func _ready() -> void:
	scale = Vector3(0.25, 0.25, 0.25)
	_apply_light_blue_recursive(ring)
	_apply_light_blue_recursive(dot)
	_apply_idle_visual_state()
	set_process(false)


func _apply_idle_visual_state() -> void:
	dot.visible = true
	dot.scale = Vector3.ONE
	ring.visible = false
	ring.scale = Vector3.ONE


## Move to `world_pos` and replay ring shrink; dot stays visible after animation.
func play_at(world_pos: Vector3) -> void:
	global_position = world_pos
	visible = true
	_time = 0.0
	dot.visible = true
	dot.scale = Vector3.ONE
	ring.visible = true
	ring.scale = Vector3.ONE
	set_process(true)


func _apply_light_blue_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := StandardMaterial3D.new()
		m.albedo_color = LIGHT_BLUE
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
	for child in n.get_children():
		_apply_light_blue_recursive(child)


func _process(delta: float) -> void:
	_time += delta
	var u: float = clampf(_time / DURATION_SEC, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - u, 3.0)
	var scale_val: float = lerpf(1.0, 0.0, eased)
	ring.scale = Vector3.ONE * scale_val
	if u >= 1.0:
		ring.visible = false
		ring.scale = Vector3.ONE
		set_process(false)
