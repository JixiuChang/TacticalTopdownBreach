# res://Scenes/unit_navigation.gd
class_name UnitNavigation
extends Node

# ============================================
# 路径规划管理器
# 连接 input_router、path_visualizer 和 command_queue
# ============================================

var input_router: Node = null
var path_visual: Node = null
const MAX_PATH_POINTS: int = 256
const PATH_QUEUE_MAX: int = 64

var _unit_keypoint_queues: Dictionary = {}  # key: unit instance id, value: Array[Vector3]
var _unit_endpoints: Dictionary = {}  # key: unit instance id, value: Vector3

func _ready() -> void:
	# 查找 InputRouter
	input_router = get_node_or_null("/root/InputRouter")
	if !input_router:
		input_router = get_tree().get_first_node_in_group("input_router")
	
	# 查找或创建 PathVisualizer
	path_visual = get_node_or_null("/root/PathVisualizer")
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
	if unit == null or not ("command_queue" in unit):
		return
	if final_path.size() < 2:
		return
	var endpoint_requested: Vector3 = final_path[final_path.size() - 1]
	if unit.has_method("play_click_indicator_at"):
		unit.call("play_click_indicator_at", endpoint_requested)
	print("Endpoint set for unit ", unit.name, ": ", endpoint_requested)
	
	var command_queue = unit.get("command_queue")
	if command_queue == null:
		return

	var unit_id := unit.get_instance_id()
	var previous_endpoint := _get_or_init_endpoint(unit)
	var previous_queue := _get_or_init_queue(unit).duplicate()

	_push_keypoint(unit, previous_endpoint)
	_set_endpoint(unit, endpoint_requested)

	var waypoint_chain := _get_or_init_queue(unit).duplicate()
	waypoint_chain.append(endpoint_requested)
	var planned := await _build_path_from_waypoints(unit, waypoint_chain)
	var reachable: bool = bool(planned.get("reachable", false))
	var full_path: PackedVector3Array = planned.get("path", PackedVector3Array())

	if not reachable or full_path.size() < 2:
		print("Endpoint cannot be reached, reverting endpoint for unit ", unit.name)
		_unit_endpoints[unit_id] = previous_endpoint
		_unit_keypoint_queues[unit_id] = previous_queue
		if unit.has_method("play_click_indicator_at"):
			unit.call("play_click_indicator_at", previous_endpoint)
		return

	var current_command = command_queue.get_current_command()
	if current_command && current_command is MoveCommand:
		(current_command as MoveCommand).set_path(_cap_path_points(full_path))
		if path_visual:
			path_visual.visualize_path(unit, (current_command as MoveCommand).path)
		return

	# 创建新的 MoveCommand
	var move_command = MoveCommand.new(
		_cap_path_points(full_path),
		0.0,  # start_time 将由 command_queue 设置
		MovementEnums.MovementSpeed.WALKING,
		MovementEnums.Stance.STANDING,
		MovementEnums.WeaponState.LOW
	)
	command_queue.add_command(move_command)
	if path_visual:
		path_visual.visualize_path(unit, move_command.path)
	print("Path planned for unit: ", unit.name, " - Path points: ", move_command.path.size())


func _cap_path_points(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() <= MAX_PATH_POINTS:
		return path
	var capped := PackedVector3Array()
	var start := path.size() - MAX_PATH_POINTS
	for i in range(start, path.size()):
		capped.append(path[i])
	return capped


func _unit_start_point(unit: Node) -> Vector3:
	# Always start planning from the unit's current 2D ground location (XZ + ground Y),
	# not from previous command endpoint. This keeps chain order: unit -> keypoint1 -> ... -> endpoint.
	return _unit_ground_point(unit)


func _unit_ground_point(unit: Node) -> Vector3:
	if not (unit is Node3D):
		return Vector3.ZERO
	var u3 := unit as Node3D
	var p := u3.global_position
	var h: Variant = unit.get("current_height")
	var hh := 0.9
	if h is float or h is int:
		hh = float(h) * 0.5
	p.y -= hh
	return p


func _build_path_from_waypoints(unit: Node, waypoints: Array) -> Dictionary:
	var nav_agent := unit.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav_agent == null:
		return {"reachable": false, "path": PackedVector3Array()}
	var nav_map: RID = nav_agent.get_navigation_map()
	var nav_valid := nav_map.is_valid()

	var from := _unit_start_point(unit)
	var full := PackedVector3Array()
	full.append(from)
	for w in waypoints:
		if not (w is Vector3):
			continue
		var to: Vector3 = w
		if from.distance_to(to) < 0.01:
			continue
		var seg: PackedVector3Array = PackedVector3Array()
		if nav_valid:
			# Treat gameplay as 2D pathing on XZ plane, even if rendered in 3D.
			var from_on_nav: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, from)
			var to_on_nav: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to)
			seg = NavigationServer3D.map_get_path(nav_map, from_on_nav, to_on_nav, true)
			if seg.size() < 2:
				seg = PackedVector3Array()
			else:
				from = to_on_nav
		else:
			# Fallback for scenes without NavigationRegion3D (e.g., flat test maps).
			if unit.has_method("calculate_path_to"):
				var fallback: Variant = await unit.call("calculate_path_to", to)
				if fallback is PackedVector3Array:
					seg = fallback as PackedVector3Array
		if seg.size() < 2:
			return {"reachable": false, "path": PackedVector3Array()}
		for i in range(1, seg.size()):
			full.append(seg[i])
		if not nav_valid:
			from = to
	return {"reachable": full.size() >= 2, "path": full}


func _get_or_init_queue(unit: Node) -> Array:
	var key := unit.get_instance_id()
	if not _unit_keypoint_queues.has(key):
		_unit_keypoint_queues[key] = []
	return _unit_keypoint_queues[key]


func _get_or_init_endpoint(unit: Node) -> Vector3:
	var key := unit.get_instance_id()
	if _unit_endpoints.has(key):
		return _unit_endpoints[key]
	var ep := _unit_start_point(unit)
	_unit_endpoints[key] = ep
	return ep


func _set_endpoint(unit: Node, endpoint: Vector3) -> void:
	_unit_endpoints[unit.get_instance_id()] = endpoint


func _push_keypoint(unit: Node, point: Vector3) -> void:
	var q := _get_or_init_queue(unit)
	if q.size() > 0:
		var last: Variant = q[q.size() - 1]
		if last is Vector3 and (last as Vector3).distance_to(point) < 0.05:
			return
	q.append(point)
	while q.size() > PATH_QUEUE_MAX:
		q.pop_front()

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
		var p: PackedVector3Array = (current_command as MoveCommand).path
		if p.size() > 0:
			_set_endpoint(unit, p[p.size() - 1])
