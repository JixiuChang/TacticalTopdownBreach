# ~/Gameplay/Units/movement_enums.gd
class_name MovementEnums
extends Node

enum MovementSpeed {
	HOLDING,  #Speed 0 
	WALKING,  #Speed 1
	SPRINTING #speed 3
}

enum Stance {
	STANDING,     
	CROUCHING 
}

enum WeaponState {
	LOW, 
	AIMING 
}

enum MovementMode {
	STANDING_HOLDING_LOW,
	STANDING_WALKING_LOW,
	STANDING_SPRINTING_LOW,
	
	CROUCHING_HOLDING_LOW,
	CROUCHING_WALKING_LOW,
	
	STANDING_HOLDING_AIMING,
	STANDING_WALKING_AIMING,
	
	CROUCHING_HOLDING_AIMING,
	CROUCHING_WALKING_AIMING
}

const SPEED_VALUES = {
	MovementSpeed.HOLDING: 0.0,
	MovementSpeed.WALKING: 1.5,
	MovementSpeed.SPRINTING: 4.5
}

const STANCE_SPEED_MODIFIERS ={ 
	Stance.STANDING: 1.0,
	Stance.CROUCHING: 0.7
}

const WEAPON_SPEED_MODIFIERS = {
	WeaponState.LOW: 1.0,
	WeaponState.AIMING: 0.5
}

const STANCE_HEIGHTS = {
	Stance.STANDING: 1.8,
	Stance.CROUCHING: 1.0,
}

const FOOTSTEP_INTERVALS = {
	MovementSpeed.WALKING: 0.6,
	MovementSpeed.SPRINTING: 0.2
}

const FOOTSTEP_RADIUS = {
	MovementSpeed.HOLDING: 0,
	MovementSpeed.WALKING: 6,
	MovementSpeed.SPRINTING: 30
}

const FOOTSTEP_MULTIPLIER = {
	Stance.STANDING: 1,
	Stance.CROUCHING: 0.3
}

static func calculate_speed(movement_speed: MovementSpeed, stance: Stance, weapon_state: WeaponState) -> float:
	var base_speed = SPEED_VALUES.get(movement_speed, 0.0)
	var stance_mod = STANCE_SPEED_MODIFIERS.get(stance, 1.0)
	var weapon_mod = WEAPON_SPEED_MODIFIERS.get(weapon_state, 1.0)
	return base_speed * stance_mod * weapon_mod

static func get_stance_height(stance: Stance) -> float:
	return STANCE_HEIGHTS.get(stance, 1.8)

static func get_footstep_interval(movement_speed: MovementSpeed) -> float:
	return FOOTSTEP_INTERVALS.get(movement_speed, 0.5)

static func get_footstep_radius(movement_speed: MovementSpeed) -> float:
	return FOOTSTEP_RADIUS.get(movement_speed, 0.0)

static func get_footstep_volume_multiplier(stance: Stance) -> float:
	return FOOTSTEP_MULTIPLIER.get(stance, 1.0)

static func calculate_footstep_volume(movement_speed: MovementSpeed, stance: Stance, base_volume: float = 1.0) -> float:
	if movement_speed == MovementSpeed.HOLDING:
		return 0.0  # 静止时无音效
	
	var stance_mult = get_footstep_volume_multiplier(stance)
	return base_volume * stance_mult

static func is_valid_combination(movement_speed: MovementSpeed, stance: Stance, weapon_state: WeaponState) -> bool:
	# , gun always lowered at speed 3
	if movement_speed == MovementSpeed.SPRINTING && weapon_state != WeaponState.LOW:
		return false
	
	# always holding or walking in crouching
	if stance == Stance.CROUCHING && movement_speed == MovementSpeed.SPRINTING:
		return false
	
	#movement speed always holding or half of walking if in walking state while aiming
	if weapon_state == WeaponState.AIMING && movement_speed == MovementSpeed.SPRINTING:
		return false
	
	return true

static func fix_combination(movement_speed: MovementSpeed, stance: Stance, weapon_state: WeaponState) -> Dictionary:
	var fixed_speed = movement_speed
	var fixed_stance = stance
	var fixed_weapon = weapon_state
	
	# sprint lowers weapon
	if fixed_speed == MovementSpeed.SPRINTING:
		fixed_weapon = WeaponState.LOW
	
	# crouching stops sprint
	if fixed_stance == Stance.CROUCHING && fixed_speed == MovementSpeed.SPRINTING:
		fixed_speed = MovementSpeed.WALKING
	
	# aiming stops sprint
	if fixed_weapon == WeaponState.AIMING && fixed_speed == MovementSpeed.SPRINTING:
		fixed_speed = MovementSpeed.WALKING
	
	return {
		"movement_speed": fixed_speed,
		"stance": fixed_stance,
		"weapon_state": fixed_weapon
	}

static func parse_movement_speed(str: String) -> MovementSpeed:
	match str.to_upper():
		"HOLDING", "0": return MovementSpeed.HOLDING
		"WALKING", "WALK", "1": return MovementSpeed.WALKING
		"SPRINTING", "SPRINT", "3": return MovementSpeed.SPRINTING
		_: return MovementSpeed.WALKING

static func parse_stance(str: String) -> Stance:
	match str.to_upper():
		"STANDING", "STAND", "2": return Stance.STANDING
		"CROUCHING", "CROUCH", "1": return Stance.CROUCHING
		_: return Stance.STANDING

static func parse_weapon_state(str: String) -> WeaponState:
	match str.to_upper():
		"LOW", "0": return WeaponState.LOW
		"AIMING", "1": return WeaponState.AIMING
		_: return WeaponState.LOW

static func movement_speed_to_string(movement_speed: MovementSpeed) -> String:
	match movement_speed:
		MovementSpeed.HOLDING: return "HOLDING"
		MovementSpeed.WALKING: return "WALKING"
		MovementSpeed.SPRINTING: return "SPRINTING"
		_: return "UNKNOWN"

static func stance_to_string(stance: Stance) -> String:
	match stance:
		Stance.STANDING: return "STANDING"
		Stance.CROUCHING: return "CROUCHING"
		_: return "UNKNOWN"

static func weapon_state_to_string(weapon_state: WeaponState) -> String:
	match weapon_state:
		WeaponState.LOW: return "LOW"
		WeaponState.AIMING: return "AIMING"
		_: return "UNKNOWN"

static func get_movement_mode_description(movement_speed: MovementSpeed, stance: Stance, weapon_state: WeaponState) -> String:
	var speed_str = movement_speed_to_string(movement_speed)
	var stance_str = stance_to_string(stance)
	var weapon_str = weapon_state_to_string(weapon_state)
	return "%s_%s_%s" % [stance_str, speed_str, weapon_str]

static func should_play_footstep(movement_speed: MovementSpeed) -> bool:
	return movement_speed != MovementSpeed.HOLDING

static func get_footstep_sound_params(movement_speed: MovementSpeed, stance: Stance) -> Dictionary:
	return {
		"interval": get_footstep_interval(movement_speed),
		"radius": get_footstep_radius(movement_speed),
		"volume_multiplier": get_footstep_volume_multiplier(stance),
		"volume": calculate_footstep_volume(movement_speed, stance),
		"should_play": should_play_footstep(movement_speed)
	}
