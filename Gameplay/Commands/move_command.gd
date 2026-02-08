# ~/Gameplay/Commands/move_command.gd
class_name MoveCommand
extends Command  # ✅ 修复：应该继承 Command，不是 Node

# 基础属性
var path: PackedVector3Array = PackedVector3Array()
var current_index: int = 0
var speed: float = 3.0
var arrival_threshold: float = 0.1

# ============================================
# 构造函数（支持无参数，用于 restore_state）
# ============================================
func _init(p: PackedVector3Array = PackedVector3Array(), start: float = 0.0, move_speed: float = 3.0) -> void:
	path = p
	start_time = start
	speed = move_speed
	
	# 计算持续时间
	if path.size() > 1:
		var total_distance = 0.0
		for i in range(path.size() - 1):
			total_distance += path[i].distance_to(path[i + 1])
		duration = total_distance / speed
	else:
		duration = 0.0

# ============================================
# 执行逻辑
# ============================================
func execute(unit: Node, delta: float) -> void:
	if completed || cancelled || path.is_empty():
		return
	
	if current_index < path.size():
		var target = path[current_index]
		var current_pos = unit.global_position
		var distance = current_pos.distance_to(target)
		var move_distance = speed * delta
		
		if distance <= arrival_threshold:
			unit.global_position = target
			current_index += 1
		else:
			var direction = (target - current_pos).normalized()
			unit.global_position = current_pos + direction * min(move_distance, distance)
	
	if current_index >= path.size():
		if path.size() > 0:
			unit.global_position = path[path.size() - 1]
		complete()

# ============================================
# 快照系统支持
# ============================================
func capture_state() -> Dictionary:
	var state = super.capture_state()
	state["path"] = path
	state["current_index"] = current_index
	state["speed"] = speed
	state["type"] = "MoveCommand"
	return state

func restore_state(state: Dictionary) -> void:
	super.restore_state(state)
	path = state.get("path", PackedVector3Array())
	current_index = state.get("current_index", 0)
	speed = state.get("speed", 3.0)
