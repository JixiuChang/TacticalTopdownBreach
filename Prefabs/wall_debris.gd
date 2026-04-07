# ~/Prefabs/wall_debris.gd
extends RigidBody3D

# 碎片不再自动清理，由时间模拟器管理
# 碎片需要加入快照系统以支持时间回溯

var creation_time: float = -1.0  # 碎片创建时的时间
var parent_wall_path: NodePath = NodePath()  # 父墙壁的路径（用于追踪）

func _ready() -> void:
	# 加入快照组，让时间模拟器追踪
	add_to_group("snapshotable")
	
	# 记录创建时间
	var time_sim = get_node_or_null("/root/TimeSimulator")
	if time_sim:
		creation_time = time_sim.get_current_time()
	
	# 设置物理属性
	gravity_scale = 1.0
	contact_monitor = true
	max_contacts_reported = 1
	
	# 设置质量（较轻的碎片）
	mass = 0.5
	
	# 如果没有初始旋转速度，添加随机旋转
	if angular_velocity.length() < 0.1:
		angular_velocity = Vector3(
			randf_range(-2.0, 2.0),
			randf_range(-2.0, 2.0),
			randf_range(-2.0, 2.0)
		)

# ============================================
# 时间模拟器集成：快照系统
# ============================================

func capture_state() -> Dictionary:
	var state = {
		"position": global_position,
		"rotation": rotation,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"frozen": freeze,
		"creation_time": creation_time,
		"parent_wall_path": str(parent_wall_path)
	}
	return state

func restore_state(state: Dictionary) -> void:
	# 恢复位置和旋转
	global_position = state.get("position", Vector3.ZERO)
	rotation = state.get("rotation", Vector3.ZERO)
	
	# 恢复速度
	linear_velocity = state.get("linear_velocity", Vector3.ZERO)
	angular_velocity = state.get("angular_velocity", Vector3.ZERO)
	
	# 恢复冻结状态
	freeze = state.get("frozen", false)
	
	# 恢复创建时间
	creation_time = state.get("creation_time", -1.0)
	
	# 恢复父墙壁路径
	var path_str = state.get("parent_wall_path", "")
	if path_str != "":
		parent_wall_path = NodePath(path_str)

func set_parent_wall(wall: Node) -> void:
	if wall:
		parent_wall_path = wall.get_path()

func get_creation_time() -> float:
	return creation_time
