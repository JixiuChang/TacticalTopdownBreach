# res://Prefabs/tactical_unit.gd
class_name TacticalUnit
extends CharacterBody3D

var unit_id: int = -1
var unit_name: String = "Unit"

var unit_radius: float = 0.5
var unit_height: float = 1.8
var collision_shape: CollisionShape3D = null

var navigation_agent: NavigationAgent3D = null

var current_stance: MovementEnums.Stance = MovementEnums.Stance.STANDING
var current_weapon_state: MovementEnums.WeaponState = MovementEnums.WeaponState.LOW
var current_height: float = 1.8

var command_queue: CommandQueue = null
@export var footstep_sound: AudioStreamPlayer3D = null

## Tint for the child `ClickIndicator` (unshaded). Set from spawn slots later, or per-instance in the inspector.
@export var click_indicator_color: Color = Color.WHITE

func _ready() -> void:
	add_to_group("units")
	add_to_group("snapshotable")
	
	collision_layer = 2  # 单位层
	collision_mask = 1   # 地面层
	
	command_queue = get_node_or_null("CommandQueue")
	if !command_queue:
		command_queue = CommandQueue.new()
		command_queue.name = "CommandQueue"
		add_child(command_queue)
	
	command_queue.unit = self
	
	_setup_collision()
	_setup_navigation_agent()
	set_height(MovementEnums.get_stance_height(current_stance))
	_apply_click_indicator_color()


func set_click_indicator_color(c: Color) -> void:
	click_indicator_color = c
	_apply_click_indicator_color()


func _apply_click_indicator_color() -> void:
	var ci := get_node_or_null("ClickIndicator") as ClickIndicatorFX
	if ci != null:
		ci.set_surface_color(click_indicator_color)


func _capsule_shape_middle_height(full_height: float, radius: float) -> float:
	return maxf(full_height - 2.0 * radius, 0.05)


## Keeps CapsuleShape3D (physics) and CapsuleMesh (BodyMesh) aligned with `current_height` / `unit_radius`.
func _sync_capsule_collision_and_mesh() -> void:
	var r := unit_radius
	var h_full := current_height
	if collision_shape != null:
		var shape = collision_shape.shape
		if shape is CapsuleShape3D:
			var cap := shape as CapsuleShape3D
			cap.radius = r
			cap.height = _capsule_shape_middle_height(h_full, r)
	var mi := get_node_or_null("BodyMesh") as MeshInstance3D
	if mi != null and mi.mesh is CapsuleMesh:
		var cm := mi.mesh as CapsuleMesh
		cm.radius = r
		cm.height = h_full
	if navigation_agent != null:
		navigation_agent.radius = r
		navigation_agent.height = h_full


func _setup_collision() -> void:
	collision_shape = get_node_or_null("CollisionShape3D")
	
	if !collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
	
	var shape = collision_shape.shape
	if !shape || !(shape is CapsuleShape3D):
		shape = CapsuleShape3D.new()
		collision_shape.shape = shape
	
	_sync_capsule_collision_and_mesh()

func _setup_navigation_agent() -> void:
	navigation_agent = get_node_or_null("NavigationAgent3D")
	
	if !navigation_agent:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.name = "NavigationAgent3D"
		add_child(navigation_agent)
	
	navigation_agent.radius = unit_radius
	navigation_agent.height = current_height
	navigation_agent.path_desired_distance = 0.1
	navigation_agent.target_desired_distance = 0.1
	navigation_agent.path_max_distance = 1000.0
	
	navigation_agent.avoidance_enabled = false  
	
	await get_tree().physics_frame

func set_stance(new_stance: MovementEnums.Stance) -> void:
	if current_stance == new_stance:
		return
	
	current_stance = new_stance
	var new_height = MovementEnums.get_stance_height(new_stance)
	set_height(new_height)

func set_weapon_state(new_weapon_state: MovementEnums.WeaponState) -> void:
	current_weapon_state = new_weapon_state

func set_height(new_height: float) -> void:
	current_height = new_height
	
	var current_pos = global_position
	current_pos.y = new_height / 2.0 
	global_position = current_pos
	_sync_capsule_collision_and_mesh()

func calculate_path_to(target: Vector3) -> PackedVector3Array:
	if !navigation_agent:
		push_warning("TacticalUnit: NavigationAgent3D not found!")
		return PackedVector3Array()
	
	navigation_agent.target_position = target
	
	await navigation_agent.navigation_finished
	
	var path = navigation_agent.get_current_navigation_path()
	
	if path.is_empty():
		# 检查是否可以直接到达
		var direct_path = PackedVector3Array()
		direct_path.append(global_position)
		direct_path.append(target)
		return direct_path
	
	if path.size() > 0 && path[0].distance_to(global_position) > 0.5:
		var corrected_path = PackedVector3Array()
		corrected_path.append(global_position)
		for i in range(path.size()):
			corrected_path.append(path[i])
		return corrected_path
	
	return path

func is_target_reachable(target: Vector3) -> bool:
	var path = await calculate_path_to(target)
	return !path.is_empty()

func get_nearest_reachable_point(target: Vector3, search_radius: float = 5.0) -> Vector3:
	if await is_target_reachable(target):
		return target
	
	var best_point = target
	var best_distance = INF
	
	var search_steps = 8
	var angle_step = TAU / search_steps
	
	for radius in range(1, int(search_radius) + 1):
		for step in range(search_steps):
			var angle = angle_step * step
			var offset = Vector3(
				cos(angle) * radius,
				0,
				sin(angle) * radius
			)
			var test_point = target + offset
			
			if await is_target_reachable(test_point):
				var distance = target.distance_to(test_point)
				if distance < best_distance:
					best_distance = distance
					best_point = test_point
		
		if best_distance < INF:
			return best_point
	
	return target

func emit_footstep_sound(
	speed: MovementEnums.MovementSpeed,
	stance: MovementEnums.Stance,
	radius: float,
	volume: float
) -> void:
	if footstep_sound:
		footstep_sound.volume_db = linear_to_db(volume)
		footstep_sound.play()

func is_unit() -> bool:
	return true

func get_unit_id() -> int:
	return unit_id

func get_unit_name() -> String:
	return unit_name

func capture_state() -> Dictionary:
	var state = {
		"position": global_position,
		"stance": current_stance,
		"weapon_state": current_weapon_state,
		"height": current_height,
		"unit_radius": unit_radius
	}
	
	if command_queue:
		state["command_queue"] = command_queue.capture_state()
	
	return state

func restore_state(state: Dictionary) -> void:
	global_position = state.get("position", Vector3.ZERO)
	current_stance = state.get("stance", MovementEnums.Stance.STANDING)
	current_weapon_state = state.get("weapon_state", MovementEnums.WeaponState.LOW)
	current_height = state.get("height", 1.8)
	unit_radius = state.get("unit_radius", 0.5)
	
	set_stance(current_stance)
	set_weapon_state(current_weapon_state)
	set_height(current_height)
	
	if command_queue && state.has("command_queue"):
		command_queue.restore_state(state["command_queue"])

func get_unit_bounds() -> Dictionary:
	return {
		"center": global_position,
		"radius": unit_radius,
		"height": current_height,
		"top": global_position.y + current_height / 2.0,
		"bottom": global_position.y - current_height / 2.0
	}
