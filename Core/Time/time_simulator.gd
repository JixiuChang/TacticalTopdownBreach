# ~/Core/Time/time_simulator.gd
extends Node

#delta
var fixed_delta: float = 0.1
var mode: String = "paused" #paused, playing, rewind

#Timer Constant
var simulation_time: float = 180.0
const ROUND_DURATION: float = 180.0
const START_TIME: float = 180.0
const END_TIME: float = 0.0

#Rewind Snapshot Setting
var snapshot_interval: float = 5.0
var snapshots: Array[Dictionary] = []

var command_history: Array[Dictionary] = []

#Timer Actions
signal time_advanced(new_time: float)
signal time_expired()
signal snapshot_created(time: float, snapshot: Dictionary)
signal rewinded(target_time: float)
signal rewind_completed

var game_state_manager: Node = null

func _ready() -> void:
	call_deferred("_get_game_state_manager")

func _get_game_state_manager() -> void:
	if has_node("/root/GameStateManager"):
		game_state_manager = get_node("/root/GameStateManager")


	
