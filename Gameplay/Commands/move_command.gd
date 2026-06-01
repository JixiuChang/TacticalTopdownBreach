# ~/Gameplay/Commands/move_command.gd
class_name MoveCommand
extends Command  

var path: PackedVector3Array = PackedVector3Array()
var current_index: int = 0
var arrival_threshold: float = 0.1

var move_speed: MovementEnums.MovementSpeed = MovementEnums.MovementSpeed.HOLDING
var move_stance: MovementEnums.Stance = MovementEnums.Stance.STANDING
var weapon_state: MovementEnums.WeaponState = MovementEnums.WeaponState.LOW

var calculated_speed: float = 0.0

var last_footstep_time: float = 0.0
var elapsed_time: float = 0.0
var indicator_started: bool = false

func _init(
	p: PackedVector3Array = PackedVector3Array(),
	start: float = 0.0,
	m_speed: MovementEnums.MovementSpeed = MovementEnums.MovementSpeed.WALKING,
	m_stance: MovementEnums.Stance = MovementEnums.Stance.STANDING,
	w_state: MovementEnums.WeaponState = MovementEnums.WeaponState.LOW
) -> void:
	path = p
	start_time = start
	move_speed = m_speed
	move_stance = m_stance
	weapon_state = w_state
	
	if !MovementEnums.is_valid_combination(move_speed, move_stance, weapon_state):
		var fixed = MovementEnums.fix_combination(move_speed, move_stance, weapon_state)
		move_speed = fixed.move_speed
		move_stance = fixed.move_stance
		weapon_state = fixed.weapon_state
	
	calculated_speed = MovementEnums.calculate_speed(move_speed, move_stance, weapon_state)
	_recalculate_duration()


func set_path(p: PackedVector3Array) -> void:
	path = p
	current_index = 0
	elapsed_time = 0.0
	last_footstep_time = 0.0
	indicator_started = false
	_recalculate_duration()


## Refreshes the movement profile (speed/stance/weapon) so an already-queued
## command reflects the unit's current state after a re-plan. `calculated_speed`
## is recomputed; call `set_path` afterwards to recompute `duration`.
func set_movement_profile(
	m_speed: MovementEnums.MovementSpeed,
	m_stance: MovementEnums.Stance,
	w_state: MovementEnums.WeaponState
) -> void:
	move_speed = m_speed
	move_stance = m_stance
	weapon_state = w_state
	if !MovementEnums.is_valid_combination(move_speed, move_stance, weapon_state):
		var fixed = MovementEnums.fix_combination(move_speed, move_stance, weapon_state)
		move_speed = fixed.move_speed
		move_stance = fixed.move_stance
		weapon_state = fixed.weapon_state
	calculated_speed = MovementEnums.calculate_speed(move_speed, move_stance, weapon_state)
	_recalculate_duration()


func _recalculate_duration() -> void:
	if path.size() > 1:
		var total_distance: float = 0.0
		for i in range(path.size() - 1):
			total_distance += path[i].distance_to(path[i + 1])
		duration = total_distance / calculated_speed if calculated_speed > 0.0 else 0.0
	else:
		duration = 0.0


func execute(unit: Node, delta: float) -> void:
	if completed || cancelled || path.is_empty():
		return

	if not indicator_started and unit != null and unit.has_method("play_path_indicator"):
		indicator_started = true
		unit.call("play_path_indicator", path)
	
	elapsed_time += delta
	
	_sync_movement_profile_from_unit(unit)
	if _remaining_path_blocked_by_unit(unit):
		if unit != null and unit.has_method("stop_path_indicator"):
			unit.call("stop_path_indicator")
		if GameStateManager.get_phase() == GameStateManager.GamePhase.EXECUTING:
			GameStateManager.pause_execution()
		return
	
	if current_index < path.size():
		var half_h := _unit_half_height(unit)
		var pos: Vector3 = unit.global_position
		# Per-frame distance budget. Consume it ACROSS waypoints so passing a
		# corner never wastes part of the frame; otherwise multi-waypoint paths
		# fall behind the time schedule and stop short of the final endpoint.
		var budget: float = calculated_speed * delta
		var guard: int = 0
		while budget > 1e-5 and current_index < path.size() and guard < 4096:
			guard += 1
			var target_feet: Vector3 = path[current_index]
			var target_center := Vector3(target_feet.x, target_feet.y + half_h, target_feet.z)
			var to_xz := Vector2(target_center.x - pos.x, target_center.z - pos.z)
			var dist := to_xz.length()
			if dist <= maxf(budget, arrival_threshold):
				# Reached this waypoint: snap (aligns Y for layer transitions) and advance.
				pos = target_center
				budget -= dist
				current_index += 1
			else:
				var dir := to_xz / maxf(dist, 1e-6)
				pos = Vector3(pos.x + dir.x * budget, pos.y, pos.z + dir.y * budget)
				budget = 0.0
		unit.global_position = pos
		
		_check_footstep(unit, elapsed_time)
		if unit != null and unit.has_method("update_path_indicator_progress"):
			unit.call("update_path_indicator_progress", unit.global_position, current_index)
	
	if current_index >= path.size():
		_snap_to_end(unit)
		if unit != null and unit.has_method("stop_path_indicator"):
			unit.call("stop_path_indicator")
		complete()


func _unit_half_height(unit: Node) -> float:
	var h: Variant = unit.get("current_height")
	if h is float or h is int:
		return float(h) * 0.5
	return 0.9


func _snap_to_end(unit: Node) -> void:
	if unit == null or path.is_empty():
		return
	var end_feet := path[path.size() - 1]
	var half_h := _unit_half_height(unit)
	unit.global_position = Vector3(end_feet.x, end_feet.y + half_h, end_feet.z)


## Called by the command queue when the timeline fast-forwards past this command's
## window. Guarantees the unit lands exactly on the planned endpoint.
func finalize(unit: Node) -> void:
	_snap_to_end(unit)
	if unit != null and unit.has_method("stop_path_indicator"):
		unit.call("stop_path_indicator")


func _remaining_path_blocked_by_unit(unit: Node) -> bool:
	if unit == null or not (unit is Node3D):
		return false
	var u3 := unit as Node3D
	var world := u3.get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	var exclude := []
	if u3 is CollisionObject3D:
		exclude.append((u3 as CollisionObject3D).get_rid())
	var from := u3.global_position + Vector3.UP * 0.2
	var start_idx := clampi(current_index, 0, path.size() - 1)
	for i in range(start_idx, path.size()):
		var to := path[i] + Vector3.UP * 0.2
		if from.distance_to(to) < 0.01:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 2
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var c : Variant = hit.get("collider")
			# Only treat explicit dynamic blockers (e.g. enemies) as execution-stopping obstacles.
			if c is Node and (c as Node).is_in_group(&"execution_path_blocker"):
				return true
		from = to
	return false

func _sync_movement_profile_from_unit(unit: Node) -> void:
	if unit == null:
		return
	var speed_v: Variant = unit.get("current_movement_speed")
	var stance_v: Variant = unit.get("current_stance")
	var weapon_v: Variant = unit.get("current_weapon_state")
	var unit_speed: MovementEnums.MovementSpeed = int(speed_v) if speed_v is int else MovementEnums.MovementSpeed.WALKING
	var unit_stance: MovementEnums.Stance = int(stance_v) if stance_v is int else MovementEnums.Stance.STANDING
	var unit_weapon: MovementEnums.WeaponState = int(weapon_v) if weapon_v is int else MovementEnums.WeaponState.LOW
	if unit_speed == move_speed and unit_stance == move_stance and unit_weapon == weapon_state:
		return
	set_movement_profile(unit_speed, unit_stance, unit_weapon)

func _check_footstep(unit: Node, elapsed: float) -> void:
	if !MovementEnums.should_play_footstep(move_speed):
		return
	
	var interval = MovementEnums.get_footstep_interval(move_speed)
	
	if elapsed - last_footstep_time >= interval:
		var sound_params = MovementEnums.get_footstep_sound_params(move_speed, move_stance)
		
		if unit.has_method("emit_footstep_sound"):
			unit.emit_footstep_sound(
				move_speed,
				move_stance,
				sound_params.radius,
				sound_params.volume
			)
		
		last_footstep_time = elapsed

func capture_state() -> Dictionary:
	var state = super.capture_state()
	state["path"] = path
	state["current_index"] = current_index
	state["movement_speed"] = move_speed
	state["stance"] = move_stance
	state["weapon_state"] = weapon_state
	state["calculated_speed"] = calculated_speed
	state["last_footstep_time"] = last_footstep_time
	state["elapsed_time"] = elapsed_time
	state["type"] = "MoveCommand"
	return state

func restore_state(state: Dictionary) -> void:
	super.restore_state(state)
	path = state.get("path", PackedVector3Array())
	current_index = state.get("current_index", 0)
	move_speed = state.get("movement_speed", MovementEnums.MovementSpeed.WALKING)
	move_stance = state.get("stance", MovementEnums.Stance.STANDING)
	weapon_state = state.get("weapon_state", MovementEnums.WeaponState.LOW)
	calculated_speed = state.get("calculated_speed", 0.0)
	last_footstep_time = state.get("last_footstep_time", 0.0)
	elapsed_time = state.get("elapsed_time", 0.0)
	
	if calculated_speed == 0.0:
		calculated_speed = MovementEnums.calculate_speed(move_speed, move_stance, weapon_state)
	indicator_started = false
