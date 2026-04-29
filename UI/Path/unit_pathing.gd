# ~/UI/Path/unit_pathing.gd
class_name UnitPathing
extends Node3D

# ============================================
# 路径可视化系统
# 在规划阶段绘制路径
# ============================================

var path_lines: Dictionary = {}  # unit -> Line3D
var path_time_labels: Dictionary = {}  # unit -> Label3D (时间标签)

const PATH_COLOR: Color = Color.CYAN
const PATH_WIDTH: float = 0.16
const PATH_Y_LIFT: float = 0.06
const TIME_LABEL_OFFSET: Vector3 = Vector3(0, 2, 0)

func _ready() -> void:
	add_to_group("path_visualizer")

func visualize_path(unit: Node, path: PackedVector3Array) -> void:
	if path.is_empty():
		clear_path(unit)
		return
	
	# 创建或更新路径线
	_create_path_line(unit, path)
	
	# 创建时间标签
	_create_time_label(unit, path)

func _create_path_line(unit: Node, path: PackedVector3Array) -> void:
	# 移除旧的路径线
	if path_lines.has(unit):
		var old_line = path_lines[unit]
		if is_instance_valid(old_line):
			old_line.queue_free()
	
	# 创建新的路径线
	var line = Line3D.new()
	line.name = "PathLine_" + str(unit.get_instance_id())
	add_child(line)
	
	line.width = PATH_WIDTH
	var c: Variant = unit.get("click_indicator_color")
	line.default_color = c if c is Color else PATH_COLOR
	var lifted := PackedVector3Array()
	for p in path:
		lifted.append(Vector3(p.x, p.y + PATH_Y_LIFT, p.z))
	line.points = lifted
	
	path_lines[unit] = line

func _create_time_label(unit: Node, path: PackedVector3Array) -> void:
	# 移除旧的时间标签
	if path_time_labels.has(unit):
		var old_label = path_time_labels[unit]
		if is_instance_valid(old_label):
			old_label.queue_free()
	
	# 计算路径完成时间
	var command_queue = unit.get("command_queue")
	if !command_queue:
		return
	
	var total_time = 0.0
	var current_command = command_queue.get_current_command()
	if current_command && current_command is MoveCommand:
		total_time = current_command.duration
	else:
		# 计算新路径的时间
		var distance = 0.0
		for i in range(path.size() - 1):
			distance += path[i].distance_to(path[i + 1])
		
		# 使用默认速度计算时间
		var default_speed = MovementEnums.calculate_speed(
			MovementEnums.MovementSpeed.WALKING,
			MovementEnums.Stance.STANDING,
			MovementEnums.WeaponState.LOW
		)
		total_time = distance / default_speed if default_speed > 0 else 0.0
	
	# 创建时间标签
	var label = Label3D.new()
	label.text = _format_time(total_time)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = path[path.size() - 1] + TIME_LABEL_OFFSET
	label.name = "TimeLabel_" + str(unit.get_instance_id())
	add_child(label)
	
	path_time_labels[unit] = label

func _format_time(seconds: float) -> String:
	var minutes = int(seconds) / 60
	var secs = int(seconds) % 60
	var milliseconds = int((seconds - int(seconds)) * 100)
	return "%02d:%02d.%02d" % [minutes, secs, milliseconds]

func clear_path(unit: Node) -> void:
	if path_lines.has(unit):
		var line = path_lines[unit]
		if is_instance_valid(line):
			line.queue_free()
		path_lines.erase(unit)
	
	if path_time_labels.has(unit):
		var label = path_time_labels[unit]
		if is_instance_valid(label):
			label.queue_free()
		path_time_labels.erase(unit)

func get_path_at_screen_position(unit: Node, screen_pos: Vector2) -> Dictionary:
	# 检查屏幕位置是否在路径上
	if !path_lines.has(unit):
		return {}
	
	var camera = get_viewport().get_camera_3d()
	if !camera:
		return {}
	
	var line = path_lines[unit]
	if !is_instance_valid(line):
		return {}
	
	# 检查路径点
	var path = line.points
	var closest_index = -1
	var closest_distance = INF
	
	for i in range(path.size()):
		var world_pos = path[i]
		var screen_point = camera.unproject_position(world_pos)
		var distance = screen_point.distance_to(screen_pos)
		
		if distance < 20.0 && distance < closest_distance:  # 20像素容差
			closest_distance = distance
			closest_index = i
	
	if closest_index >= 0:
		return {
			"unit": unit,
			"path_index": closest_index,
			"position": path[closest_index]
		}
	
	return {}
