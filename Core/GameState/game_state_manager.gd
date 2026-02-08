# ~/Core/GameState/game_state_manager.gd
extends Node

#Game Phase
const GamePhase = GamePhaseEnum.GamePhase
var current_phase: GamePhase = GamePhase.BRIEFING

#Game Phase Actions
signal phase_changed(new_phase: GamePhase)

#Objective State
var objective_completed: bool = false
var objective_failed: bool = false

#Timer
var time_simulator: Node = null

#Timer Constants
const ROUND_DURATION: float = 180.0
const START_TIME: float = 180.0
const END_TIME: float = 0.0

#Function
func _ready() -> void:
	set_phase(GamePhase.BRIEFING)
	call_deferred("_get_time_simulator")

func _get_time_simulator() -> void:
	if has_node("/root/TimeSimulator"):
		time_simulator = get_node("/root/TimeSimulator")
		time_simulator.time_expired.connect(_on_timeout)

func _get_phase_name(phase: GamePhase) -> String:
	match phase:
		GamePhase.BRIEFING: return "BRIEFING"
		GamePhase.PLANNING: return "PLANNING"
		GamePhase.EXECUTING: return "EXECUTING"
		GamePhase.DEBRIEFING: return "DEBRIEFING"
		_: return "UNKNOWN"

func get_phase() -> GamePhase:
	return current_phase

func set_phase(new_phase: GamePhase) -> void:
	if current_phase != new_phase:
		var old_phase = current_phase
		current_phase = new_phase
		phase_changed.emit(new_phase)
		print("Game Phase Updated: ", _get_phase_name(old_phase), " -> ", _get_phase_name(current_phase)) 
		_on_phase_entered(new_phase)

func is_phase(phase: GamePhase) -> bool:
	return phase == current_phase

func is_executing() -> bool:
	return current_phase == GamePhase.EXECUTING

func phase_enter(new_phase: GamePhase) -> bool:
	if _can_enter_phase(new_phase):
		set_phase(new_phase)
		return true
	print("Invalid transition from ", _get_phase_name(current_phase), " to ", _get_phase_name(new_phase))
	return false

func _can_enter_phase(new_phase: GamePhase) -> bool:
	match current_phase:
		GamePhase.BRIEFING: return new_phase == GamePhase.PLANNING
		GamePhase.PLANNING: return new_phase == GamePhase.EXECUTING
		GamePhase.EXECUTING: return new_phase == GamePhase.PLANNING || new_phase == GamePhase.DEBRIEFING
		GamePhase.DEBRIEFING: return new_phase == GamePhase.PLANNING
	return false

func start_execution() -> bool:
	if current_phase == GamePhase.PLANNING:
		if time_simulator:
			time_simulator.start_execution()
		return phase_enter(GamePhase.EXECUTING)
	return false

func pause_execution() -> bool:
	if current_phase == GamePhase.EXECUTING:
		if time_simulator:
			time_simulator.pause()
		return phase_enter(GamePhase.PLANNING)
	return false

func on_timeout() -> void:
	if current_phase == GamePhase.EXECUTING:
		if not objective_completed:
			objective_failed = true
		_debrief()

func on_objective_completion() -> void:
	objective_completed = true
	_debrief()

func on_execution_completion() -> void:
	if current_phase == GamePhase.EXECUTING:
		_debrief()

func _debrief() -> void:
	if objective_completed || objective_failed:
		if time_simulator:
			time_simulator.pause()
		phase_enter(GamePhase.DEBRIEFING)
	else:
		if time_simulator:
			time_simulator.pause()
		phase_enter(GamePhase.PLANNING)

func backlog_from_debrief(target_time: float) -> bool:
	if current_phase == GamePhase.DEBRIEFING:
		if target_time >= END_TIME and target_time <= START_TIME:
			if time_simulator:
				var min_time = time_simulator.get_min_executed_time()
				
				if target_time >= min_time:
					if time_simulator.rewind_to(target_time):
						reset_objective_state()
						return phase_enter(GamePhase.PLANNING)
				else:
					print("Cannot rewind to time before execution: ", target_time, " (min executed: ", min_time, ")")
	return false

func reset_gamestate() -> void:
	reset_objective_state()
	
	if time_simulator:
		time_simulator.reset()
	
	set_phase(GamePhase.BRIEFING)

func reset_objective_state() -> void:
	objective_completed = false
	objective_failed = false

func _on_phase_entered(phase: GamePhase) -> void:
	if !time_simulator: return
	
	match phase:
		GamePhase.PLANNING:
			time_simulator.pause()
		GamePhase.EXECUTING:
			time_simulator.start_execution()
		GamePhase.DEBRIEFING:
			time_simulator.pause()
			time_simulator.enable_rewind()

func _on_timeout() -> void:
	on_timeout()
