# ~/Gameplay/Commands/command_queue.gd
class_name CommandQueue
extends Node

var commands: Array[Command] = []
var unit: Node = null
var time_simulator: Node = null

var current_time: float = 180.0

signal command_completed(command: Command)
signal all_commands_completed

func _ready() -> void:
	add_to_group("snapshotable")
	call_deferred("_get_time_simulator")

func _get_time_simulator() -> void:
	if has_node("/root/TimeSimulator"):
		time_simulator = get_node("/root/TimeSimulator")
		time_simulator.time_advanced.connect(_on_time_advanced)

func _on_time_advanced(new_time: float) -> void:
	current_time = new_time
	_process_commands()

func _process_commands() -> void:
	if !unit || !time_simulator || commands.is_empty(): return
	
	var fixed_delta = time_simulator.fixed_delta
	var max_iterations = commands.size() + 1
	
	while !commands.is_empty() && max_iterations > 0:
		max_iterations -= 1
		
		var current_command = commands[0]
		
		if !current_command.should_start(current_time):
			break
		
		if current_command.should_end(current_time):
			current_command.complete()
			command_completed.emit(current_command)
			commands.pop_front()
			
			if commands.is_empty():
				all_commands_completed.emit()
				break
			
			continue
		else:
			current_command.execute(unit, fixed_delta)
			break
	
	if max_iterations == 0:
		push_warning("Command Queue: Max Iteration Reached, possible infinite loop?")

func add_command(command: Command) -> void:
	if !command: return
	
	var start_time: float
	if commands.is_empty():
		if time_simulator:
			start_time = time_simulator.get_current_time()
		else:
			start_time = current_time
	else:
		var last_command = commands[commands.size() - 1]
		start_time = last_command.start_time + last_command.duration
	
	command.start_time = start_time
	commands.append(command)

func clear_commands() -> void:
	for command in commands:
		command.cancel()
	commands.clear()

func cancel_current_command() -> void:
	if commands.is_empty(): return
	
	var current_command = commands[0]
	current_command.cancel()
	commands.pop_front()
	
	if commands.is_empty():
		all_commands_completed.emit()

func get_current_command() -> Command:
	if commands.is_empty(): return null
	return commands[0]

func peek_command() -> Command:
	if commands.size() < 2: return null
	return commands[1]

func get_queue_size() -> int:
	return commands.size()

func get_all_commands() -> Array[Command]:
	return commands.duplicate()

func capture_state() -> Dictionary:
	var commands_state = []
	for cmd in commands:
		commands_state.append(cmd.capture_state())
	
	return {
		"commands": commands_state,
		"current_time": current_time
	}

func restore_state(state: Dictionary) -> void:
	commands.clear()
	
	var commands_state = state.get("commands", [])
	for cmd_state in commands_state:
		var cmd_type = cmd_state.get("type", "")
		var command: Command = null
		
		if cmd_type == "MoveCommand" || cmd_state.has("path"):
			command = MoveCommand.new()
			command.restore_state(cmd_state)
		
		if command:
			commands.append(command)
	
	current_time = state.get("current_time", 180.0)
