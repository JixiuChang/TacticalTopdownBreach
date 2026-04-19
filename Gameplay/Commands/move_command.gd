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
	
	if path.size() > 1:
		var total_distance = 0.0
		for i in range(path.size() - 1):
			total_distance += path[i].distance_to(path[i + 1])
		duration = total_distance / calculated_speed if calculated_speed > 0.0 else 0.0
	else:
		duration = 0.0


func set_path(p: PackedVector3Array) -> void:
	path = p
	current_index = 0
	elapsed_time = 0.0
	last_footstep_time = 0.0
	if path.size() > 1:
		var total_distance := 0.0
		for i in range(path.size() - 1):
			total_distance += path[i].distance_to(path[i + 1])
		duration = total_distance / calculated_speed if calculated_speed > 0.0 else 0.0
	else:
		duration = 0.0


func execute(unit: Node, delta: float) -> void:
	if completed || cancelled || path.is_empty():
		return
	
	elapsed_time += delta
	
	_apply_unit_state(unit)
	
	if current_index < path.size():
		var target = path[current_index]
		var current_pos = unit.global_position
		var distance = current_pos.distance_to(target)
		var move_distance = calculated_speed * delta
		
		if distance <= arrival_threshold:
			unit.global_position = target
			current_index += 1
		else:
			var direction = (target - current_pos).normalized()
			unit.global_position = current_pos + direction * min(move_distance, distance)
		
		_check_footstep(unit, elapsed_time)
	
	if current_index >= path.size():
		if path.size() > 0:
			unit.global_position = path[path.size() - 1]	
		complete()

func _apply_unit_state(unit: Node) -> void:
	if unit.has_method("set_stance"):
		unit.set_stance(move_stance)
	
	if unit.has_method("set_weapon_state"):
		unit.set_weapon_state(weapon_state)
	
	if unit.has_method("set_height"):
		var height = MovementEnums.get_stance_height(move_stance)
		unit.set_height(height)

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
