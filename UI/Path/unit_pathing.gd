# ~/UI/Path/unit_pathing.gd
class_name UnitPathing
extends Node3D

# ============================================
# 路径可视化系统
# 在规划阶段绘制路径
# ============================================

var path_lines: Dictionary = {}  # unit -> Line3D
var path_time_labels: Dictionary = {}  # unit -> Label3D (时间标签)
var path_waypoint_markers: Dictionary = {}  # unit -> Node3D (航点标记容器)

const PATH_COLOR: Color = Color.CYAN
const PATH_WIDTH: float = 0.16
const PATH_Y_LIFT: float = 0.06
const TIME_LABEL_OFFSET: Vector3 = Vector3(0, 2, 0)
const WAYPOINT_MARKER_RADIUS: float = 0.18
const WAYPOINT_MARKER_Y_LIFT: float = 0.12

func _ready() -> void:
	add_to_group("path_visualizer")

func visualize_path(unit: Node, path: PackedVector3Array, waypoints: Array = []) -> void:
	if path.is_empty():
		clear_path(unit)
		return
	
	# 创建或更新路径线
	_create_path_line(unit, path)
	
	# 创建航点标记（玩家放置的点，可点选裁剪）
	_create_waypoint_markers(unit, waypoints)
	
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

func _create_waypoint_markers(unit: Node, waypoints: Array) -> void:
	# 移除旧的航点标记
	if path_waypoint_markers.has(unit):
		var old_root = path_waypoint_markers[unit]
		if is_instance_valid(old_root):
			old_root.queue_free()
		path_waypoint_markers.erase(unit)
	
	if waypoints.is_empty():
		return
	
	var root := Node3D.new()
	root.name = "Waypoints_" + str(unit.get_instance_id())
	add_child(root)
	
	var col: Variant = unit.get("click_indicator_color")
	var marker_color: Color = col if col is Color else PATH_COLOR
	
	for i in range(waypoints.size()):
		var wp: Variant = waypoints[i]
		if not (wp is Vector3):
			continue
		var p: Vector3 = wp
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = WAYPOINT_MARKER_RADIUS
		sphere.height = WAYPOINT_MARKER_RADIUS * 2.0
		marker.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = marker_color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Endpoint (last waypoint) drawn slightly larger for clarity.
		if i == waypoints.size() - 1:
			marker.scale = Vector3.ONE * 1.4
		marker.material_override = mat
		marker.position = Vector3(p.x, p.y + WAYPOINT_MARKER_Y_LIFT, p.z)
		root.add_child(marker)
	
	path_waypoint_markers[unit] = root

func _create_time_label(unit: Node, path: PackedVector3Array) -> void:
	# 移除旧的时间标签
	if path_time_labels.has(unit):
		var old_label = path_time_labels[unit]
		if is_instance_valid(old_label):
			old_label.queue_free()
	
	# 计算到达时刻（基于倒计时时间线，与屏幕时钟一致）
	var command_queue = unit.get("command_queue")
	if !command_queue:
		return
	
	var arrival_time := _compute_arrival_time(unit, path, command_queue)
	
	# 创建时间标签
	var label = Label3D.new()
	label.text = TimeSimulator.format_time(arrival_time)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = path[path.size() - 1] + TIME_LABEL_OFFSET
	label.name = "TimeLabel_" + str(unit.get_instance_id())
	add_child(label)
	
	path_time_labels[unit] = label

## 到达时刻 = 命令开始时刻 - 行进耗时（倒计时时间线）。无命令时退回当前模拟时刻推算。
func _compute_arrival_time(unit: Node, path: PackedVector3Array, command_queue: Node) -> float:
	var current_command = command_queue.get_current_command()
	if current_command && current_command is MoveCommand:
		var mc := current_command as MoveCommand
		return maxf(mc.start_time - mc.duration, 0.0)
	
	var distance: float = 0.0
	for i in range(path.size() - 1):
		distance += path[i].distance_to(path[i + 1])
	
	var speed_v: Variant = unit.get("current_movement_speed")
	var stance_v: Variant = unit.get("current_stance")
	var weapon_v: Variant = unit.get("current_weapon_state")
	var unit_speed: MovementEnums.MovementSpeed = int(speed_v) if speed_v is int else MovementEnums.MovementSpeed.WALKING
	var unit_stance: MovementEnums.Stance = int(stance_v) if stance_v is int else MovementEnums.Stance.STANDING
	var unit_weapon: MovementEnums.WeaponState = int(weapon_v) if weapon_v is int else MovementEnums.WeaponState.LOW
	var planned_speed: float = MovementEnums.calculate_speed(unit_speed, unit_stance, unit_weapon)
	var travel_time: float = distance / planned_speed if planned_speed > 0.0 else 0.0
	return maxf(TimeSimulator.get_current_time() - travel_time, 0.0)

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
	
	if path_waypoint_markers.has(unit):
		var markers = path_waypoint_markers[unit]
		if is_instance_valid(markers):
			markers.queue_free()
		path_waypoint_markers.erase(unit)

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
