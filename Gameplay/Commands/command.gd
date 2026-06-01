# ~/Gameplay/Commands/command.gd
class_name Command
extends RefCounted

var start_time: float = 0.0
var duration: float = 0.0

var completed: bool = false
var cancelled: bool = false

func execute(unit: Node, delta: float) -> void:
	pass

func should_start(current_time: float) -> bool:
	# Timeline counts down (180 -> 0), so command starts when current_time <= start_time.
	return current_time <= start_time && !completed && !cancelled

func should_end(current_time: float) -> bool:
	# End when countdown passed start_time - duration.
	return current_time <= (start_time - duration) || completed || cancelled

func cancel() -> void:
	cancelled = true
	completed = true

func complete() -> void:
	completed = true

## Called when the queue force-completes this command because the timeline
## advanced past its window. Subclasses snap the unit to its final state here.
func finalize(unit: Node) -> void:
	pass

func capture_state() -> Dictionary:
	return {
		"start_time": start_time,
		"duration": duration,
		"completed": completed,
		"cancelled": cancelled
	}

func restore_state(state: Dictionary) -> void:
	start_time = state.get("start_time", 0.0)
	duration = state.get("duration", 0.0)
	completed = state.get("completed", false)
	cancelled = state.get("cancelled", false)
