# ~/Core/GameState/game_state_manager.gd
extends Node

#Game Phase
const GamePhase = preload("res://Core/GameState/game_phase.gd").GamePhase
var current_phase: GamePhase = GamePhase.BRIEFING

#Game Phase Actions
signal phase_changed(new_phase: GamePhase)
signal execution_completed()
signal objective_failure()
signal objective_success()
signal rewind_requested(target_time: float)

#Objective State
var objective_completed: bool = false
var objective_failed: bool = false
var execution_complete: bool = false

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
		#if time_simulator.has_signal("time_expired"):
			#time_simulator.time_expired.connect(_on_time_expired)

func _get_phase_name(phase: GamePhase) -> String:
	match phase:
		GamePhase.BRIEFING:
			return "BRIEFING"
		GamePhase.PLANNING:
			return "PLANNING"
		GamePhase.EXECUTING:
			return "EXECUTING"
		GamePhase.DEBRIEFING:
			return "DEBRIEFING"
		_:
			return "UNKNOWN"

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

func is_planning() -> bool:
	return current_phase == GamePhase.PLANNING

func is_executing() -> bool:
	return current_phase == GamePhase.EXECUTING

func is_debrief() -> bool:
	return current_phase == GamePhase.DEBRIEFING

func _on_phase_entered(phase: GamePhase) -> void:
	match phase:
		GamePhase.PLANNING:
			_reset_execution_phase()
			if time_simulator:
				time_simulator.pause()
		GamePhase.EXECUTING:
			if time_simulator:
				time_simulator.start_execution()
		GamePhase.DEBRIEFING:
			if time_simulator:
				time_simulator.pause()
				time_simulator.enable_rewind()
	
func _reset_execution_phase() -> void:
	execution_complete = false
