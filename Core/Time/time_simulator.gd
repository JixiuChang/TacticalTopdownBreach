# ~/Core/Time/time_simulator.gd
extends Node

var fixed_delta: float = 0.1
var accumulator: float = 0.0
var min_executed_time: float = 180.0
var mode: String = "paused"  # paused, playing, rewinding

var simulation_time: float = 180.0

const START_TIME: float = 180.0
const END_TIME: float = 0.0

var snapshot_interval: float = 5.0
var snapshots: Array[Dictionary] = []
var max_snapshots: int = 36

var event_snapshots: Array[Dictionary] = [] 
var max_event_snapshots: int = 100

signal time_advanced(new_time: float)
signal time_expired()
signal rewind_completed

var game_state_manager: Node = null

func _ready() -> void:
	set_process_mode(Node.PROCESS_MODE_ALWAYS)
	call_deferred("_get_game_state_manager")

func _get_game_state_manager() -> void:
	game_state_manager = get_node_or_null("/root/GameStateManager")
	if not game_state_manager:
		var root = get_tree().root
		for child in root.get_children():
			if child.name == "GameStateManager":
				game_state_manager = child
				break

func _physics_process(delta: float) -> void:
	if mode == "playing":
		_update_simulation(delta)

func _update_simulation(frame_delta: float) -> void:
	accumulator += frame_delta
	
	var max_steps = 10
	var steps = 0
	
	while accumulator >= fixed_delta and steps < max_steps:
		advance()
		accumulator -= fixed_delta
		steps += 1
	
	if accumulator > fixed_delta * 2.0:
		print("Warning: Low framerate. Accumulator: ", accumulator)

func _should_advance() -> bool:
	if not game_state_manager: return false
	if not game_state_manager.is_executing(): return false
	if simulation_time <= END_TIME: return false
	return true

func advance() -> void:
	if not _should_advance(): return
	
	simulation_time -= fixed_delta
	
	if simulation_time < min_executed_time:
		min_executed_time = simulation_time
	
	if simulation_time <= END_TIME:
		simulation_time = END_TIME
		min_executed_time = END_TIME
		time_expired.emit()
		mode = "paused"
		accumulator = 0.0
		return
	
	if _should_create_snapshot():
		create_snapshot()
	
	time_advanced.emit(simulation_time)

func _should_create_snapshot() -> bool:
	var current_interval = int(simulation_time / snapshot_interval)
	var previous_interval = int((simulation_time + fixed_delta) / snapshot_interval)
	return current_interval < previous_interval

func create_snapshot() -> void:
	var snapshot = {
		"time": simulation_time,
		"game_state": _capture_game_state()
	}
	
	snapshots.append(snapshot)
	
	if snapshots.size() > max_snapshots:
		snapshots.pop_front()

func create_event_snapshot(event_type: String, event_data: Dictionary = {}) -> void:
	var snapshot = {
		"time": simulation_time,
		"event_type": event_type,
		"event_data": event_data,
		"game_state": _capture_game_state()
	}
	event_snapshots.append(snapshot)
	
	if event_snapshots.size() > max_event_snapshots:
		event_snapshots.pop_front()

func _capture_game_state() -> Dictionary:
	var state = {}
	var snapshotable_objects = get_tree().get_nodes_in_group("snapshotable")
	for obj in snapshotable_objects:
		if obj.has_method("capture_state"):
			state[obj.get_path()] = obj.capture_state()
	return state

func start_execution() -> void:
	mode = "playing"
	accumulator = 0.0
	if simulation_time >= START_TIME:
		simulation_time = START_TIME
		min_executed_time = START_TIME
		snapshots.clear()
		create_snapshot()

func pause() -> void:
	mode = "paused"
	accumulator = 0.0

func enable_rewind() -> void:
	mode = "rewinding"
	accumulator = 0.0

func rewind_to(target_time: float) -> bool:
	if mode != "rewinding" and mode != "paused": return false
	
	if target_time < END_TIME or target_time > START_TIME: return false
	
	var snapshot = _find_snapshot_for_time(target_time)
	if snapshot:
		_restore_snapshot(snapshot)
		simulation_time = snapshot.time
	else:
		simulation_time = START_TIME
	
	accumulator = 0.0
	rewind_completed.emit()
	return true

func _find_snapshot_for_time(time: float) -> Dictionary:
	var best_snapshot = {}
	var best_time = -1.0
	
	for snapshot in event_snapshots:
		var snapshot_time = snapshot.time
		if snapshot_time <= time && snapshot_time > best_time:
			best_time = snapshot_time
			best_snapshot = snapshot
	
	if best_time < 0:
		for snapshot in snapshots:
			var snapshot_time = snapshot.time
			if snapshot_time <= time && snapshot_time > best_time:
				best_time = snapshot_time
				best_snapshot = snapshot
	
	return best_snapshot

func _restore_snapshot(snapshot: Dictionary) -> void:
	var game_state = snapshot.get("game_state", {})
	var snapshotable_objects = get_tree().get_nodes_in_group("snapshotable")
	for obj in snapshotable_objects:
		var path = obj.get_path()
		if game_state.has(path) and obj.has_method("restore_state"):
			obj.restore_state(game_state[path])

func reset() -> void:
	simulation_time = START_TIME
	min_executed_time = START_TIME
	mode = "paused"
	accumulator = 0.0
	snapshots.clear()

func get_min_executed_time() -> float:
	return min_executed_time

func get_current_time() -> float:
	return simulation_time

func format_time(seconds: float) -> String:
	var minutes = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%02d:%02d" % [minutes, secs]
