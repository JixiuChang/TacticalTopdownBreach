# ~/Gameplay/Units/unit_navigation.gd
class_name UnitNavigation
extends Node

# ============================================
# 路径规划管理器
# 连接 input_router、path_visualizer 和 command_queue
# ============================================

var input_router: Node = null
var path_visual: Node = null

func _ready() -> void:
	# 查找 InputRouter
	input_router = get_node_or_null("/root/InputRouter")
	if !input_router:
		input_router = get_tree().get_first_node_in_group("input_router")
	
	# 查找或创建 PathVisualizer
	path_visual = get_node_or_null("/root/Path")
	if !path_visual:
		path_visual = UnitPathing.new()
		path_visual.name = "PathVisualizer"
		get_tree().root.add_child.call_deferred(path_visual)
	
	# 连接信号
	if input_router:
		if input_router.has_signal("path_drawing_started"):
			input_router.path_drawing_started.connect(_on_path_drawing_started)
		if input_router.has_signal("path_drawing_updated"):
			input_router.path_drawing_updated.connect(_on_path_drawing_updated)
		if input_router.has_signal("path_drawing_finished"):
			input_router.path_drawing_finished.connect(_on_path_drawing_finished)
		if input_router.has_signal("unit_selected"):
			input_router.unit_selected.connect(_on_unit_selected)

func _on_path_drawing_started(unit: Node, start_pos: Vector3) -> void:
	return

func _on_path_drawing_updated(unit: Node, current_path: PackedVector3Array) -> void:
	# 更新路径可视化
	if path_visual:
		path_visual.visualize_path(unit, current_path)

func _on_path_drawing_finished(unit: Node, final_path: PackedVector3Array) -> void:
	# 路径绘制完成，创建 MoveCommand
	if unit == null or not ("command_queue" in unit):
		return
	
	var command_queue = unit.get("command_queue")
	if command_queue == null:
		return
	
	# 如果从路径中间点开始编辑，需要删除后面的命令
	if command_queue.get_queue_size() > 0:
		var current_command = command_queue.get_current_command()
		if current_command && current_command is MoveCommand:
			# 检查是否需要删除后续命令
			# 这里简化处理：删除当前命令，创建新命令
			command_queue.cancel_current_command()
	
	# 创建新的 MoveCommand
	var move_command = MoveCommand.new(
		final_path,
		0.0,  # start_time 将由 command_queue 设置
		MovementEnums.MovementSpeed.WALKING,
		MovementEnums.Stance.STANDING,
		MovementEnums.WeaponState.LOW
	)
	
	# 添加到命令队列
	command_queue.add_command(move_command)
	
	# 更新可视化
	if path_visual:
		path_visual.visualize_path(unit, final_path)
	
	print("Path planned for unit: ", unit.name, " - Path points: ", final_path.size())

func _on_unit_selected(unit: Node) -> void:
	# 单位被选中，显示其当前路径
	if unit == null or not ("command_queue" in unit):
		return
	
	var command_queue = unit.get("command_queue")
	if command_queue == null:
		return
	
	var current_command = command_queue.get_current_command()
	if current_command && current_command is MoveCommand:
		if path_visual:
			path_visual.visualize_path(unit, current_command.path)
