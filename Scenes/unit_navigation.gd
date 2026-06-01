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
	add_to_group("unit_navigation")
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
		if input_router.has_signal("path_trim_requested"):
			input_router.path_trim_requested.connect(_on_path_trim_requested)
		if input_router.has_signal("path_clear_requested"):
			input_router.path_clear_requested.connect(_on_path_clear_requested)

func _on_path_drawing_started(unit: Node, start_pos: Vector3) -> void:
	return

func _on_path_drawing_updated(unit: Node, current_path: PackedVector3Array) -> void:
	# 更新路径可视化
	if path_visual:
		path_visual.visualize_path(unit, current_path)

# 新增航点：把当前端点压入关键点队列，新点成为端点；不可达则回滚。
func _on_path_drawing_finished(unit: Node, final_path: PackedVector3Array) -> void:
	if unit == null or not ("command_queue" in unit):
		return
	if final_path.size() < 2:
		return
	var endpoint_requested: Vector3 = final_path[final_path.size() - 1]
	if unit.has_method("play_click_indicator_at"):
		unit.call("play_click_indicator_at", endpoint_requested)

	var unit_id := unit.get_instance_id()
	var had_endpoint := _unit_endpoints.has(unit_id)
	var previous_endpoint: Vector3 = _unit_endpoints.get(unit_id, Vector3.ZERO)
	var previous_queue := _get_or_init_queue(unit).duplicate()

	# Only chain a keypoint once a real endpoint already exists; the unit's own
	# feet position is injected by `_unit_start_point`, so it is never a keypoint.
	if had_endpoint:
		_push_keypoint(unit, previous_endpoint)
	_set_endpoint(unit, endpoint_requested)

	var ok := await replan_unit(unit)
	if not ok:
		print("Endpoint cannot be reached, reverting endpoint for unit ", unit.name)
		if had_endpoint:
			_unit_endpoints[unit_id] = previous_endpoint
		else:
			_unit_endpoints.erase(unit_id)
		_unit_keypoint_queues[unit_id] = previous_queue
		var revert_ep := previous_endpoint if had_endpoint else _unit_ground_point(unit)
		if unit.has_method("play_click_indicator_at"):
			unit.call("play_click_indicator_at", revert_ep)
		return
	print("Endpoint set for unit ", unit.name, ": ", endpoint_requested)


# ============================================
# 路径编辑 API（规划真源 = 关键点队列 + 端点）
# ============================================

## 重新根据规划真源构建路径，刷新命令、可视化与点击指示器。返回是否可达。
func replan_unit(unit: Node) -> bool:
	if unit == null:
		return false
	var waypoints := _plan_waypoints(unit)
	if waypoints.is_empty():
		_apply_empty_plan(unit)
		return true
	var planned := await _build_path_from_waypoints(unit, waypoints)
	var reachable: bool = bool(planned.get("reachable", false))
	var full_path: PackedVector3Array = planned.get("path", PackedVector3Array())
	if not reachable or full_path.size() < 2:
		return false
	full_path = _cap_path_points(full_path)
	_commit_path(unit, full_path)
	if path_visual and path_visual.has_method("visualize_path"):
		path_visual.visualize_path(unit, full_path, waypoints)
	var ep: Vector3 = waypoints[waypoints.size() - 1]
	if unit.has_method("play_click_indicator_at"):
		unit.call("play_click_indicator_at", ep)
	return true


## 部分删除：移除最近放置的航点（撤销一步）；只剩端点时清空整条路径。
func pop_last_waypoint(unit: Node) -> void:
	if unit == null:
		return
	var key := unit.get_instance_id()
	if not _unit_endpoints.has(key):
		return
	var q := _get_or_init_queue(unit)
	if q.size() > 0:
		var new_ep: Vector3 = q[q.size() - 1]
		q.remove_at(q.size() - 1)
		_unit_endpoints[key] = new_ep
		await replan_unit(unit)
	else:
		clear_plan(unit)


## 完整清空一个单位的路径规划。
func clear_plan(unit: Node) -> void:
	if unit == null:
		return
	var key := unit.get_instance_id()
	_unit_keypoint_queues[key] = []
	_unit_endpoints.erase(key)
	_apply_empty_plan(unit)


## 把路径裁剪到离 world_pos 最近的航点（含该航点作为新端点）。
func trim_plan_to_world(unit: Node, world_pos: Vector3) -> void:
	if unit == null:
		return
	var key := unit.get_instance_id()
	var waypoints := _plan_waypoints(unit)
	if waypoints.is_empty():
		return
	var best_i := -1
	var best_d := INF
	for i in waypoints.size():
		var wp: Vector3 = waypoints[i]
		var d := Vector2(wp.x - world_pos.x, wp.z - world_pos.z).length()
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return
	var new_queue: Array = []
	for i in range(best_i):
		new_queue.append(waypoints[i])
	_unit_keypoint_queues[key] = new_queue
	_unit_endpoints[key] = waypoints[best_i]
	await replan_unit(unit)


func _on_path_trim_requested(unit: Node, world_pos: Vector3) -> void:
	await trim_plan_to_world(unit, world_pos)


func _on_path_clear_requested(unit: Node) -> void:
	clear_plan(unit)


## 规划真源展开为有序航点：关键点队列 + 端点（均为脚底空间世界坐标）。
func _plan_waypoints(unit: Node) -> Array:
	var key := unit.get_instance_id()
	var q := _get_or_init_queue(unit).duplicate()
	if _unit_endpoints.has(key):
		q.append(_unit_endpoints[key])
	return q


## 把展开后的完整路径写入 MoveCommand：已有则复用并按当前单位状态刷新速度。
func _commit_path(unit: Node, full_path: PackedVector3Array) -> void:
	var command_queue = unit.get("command_queue")
	if command_queue == null:
		return
	var profile := _unit_move_profile(unit)
	var current_command = command_queue.get_current_command()
	if current_command and current_command is MoveCommand:
		var mc := current_command as MoveCommand
		mc.set_movement_profile(profile.speed, profile.stance, profile.weapon)
		mc.set_path(full_path)
		return
	var move_command := MoveCommand.new(
		full_path,
		0.0,  # start_time 由 command_queue 设置
		profile.speed,
		profile.stance,
		profile.weapon
	)
	command_queue.add_command(move_command)


## 清空命令与可视化，并把点击指示器移回脚底。
func _apply_empty_plan(unit: Node) -> void:
	var command_queue = unit.get("command_queue")
	if command_queue and command_queue.has_method("clear_commands"):
		command_queue.clear_commands()
	if path_visual and path_visual.has_method("clear_path"):
		path_visual.clear_path(unit)
	if unit.has_method("play_click_indicator_at"):
		unit.call("play_click_indicator_at", _unit_ground_point(unit))


func _unit_move_profile(unit: Node) -> Dictionary:
	var speed_v: Variant = unit.get("current_movement_speed")
	var stance_v: Variant = unit.get("current_stance")
	var weapon_v: Variant = unit.get("current_weapon_state")
	return {
		"speed": int(speed_v) if speed_v is int else int(MovementEnums.MovementSpeed.WALKING),
		"stance": int(stance_v) if stance_v is int else int(MovementEnums.Stance.STANDING),
		"weapon": int(weapon_v) if weapon_v is int else int(MovementEnums.WeaponState.LOW),
	}


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


## Vertical gap (meters) above which two consecutive waypoints are treated as
## belonging to different 2D layers (floors). Q/E switch the planning layer.
const LAYER_HEIGHT_THRESHOLD: float = 0.45


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
		var seg: PackedVector3Array = await _plan_segment(unit, nav_map, nav_valid, from, to)
		if seg.size() < 2:
			return {"reachable": false, "path": PackedVector3Array()}
		for i in range(1, seg.size()):
			full.append(seg[i])
		# Continue the chain from the actual reached point (projected onto the
		# layer's navmesh), so each subsequent segment stays continuous.
		from = seg[seg.size() - 1]
	return {"reachable": full.size() >= 2, "path": full}


## Plans a single waypoint-to-waypoint segment. Each layer is its own 2D
## navigation surface; a segment that changes layer is routed through a stair
## bridge when one is registered (future Q/E inter-layer links plug in here).
func _plan_segment(unit: Node, nav_map: RID, nav_valid: bool, from: Vector3, to: Vector3) -> PackedVector3Array:
	if absf(from.y - to.y) > LAYER_HEIGHT_THRESHOLD:
		var bridge := get_tree().get_first_node_in_group(&"stair_path_bridge")
		if bridge != null and bridge.has_method(&"plan_stair_path"):
			var planned: Variant = bridge.call(&"plan_stair_path", from, to, unit)
			if planned is PackedVector3Array and (planned as PackedVector3Array).size() >= 2:
				return planned as PackedVector3Array
	if nav_valid:
		# Treat gameplay as 2D pathing on the layer's XZ plane, even if rendered in 3D.
		var from_on_nav: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, from)
		var to_on_nav: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to)
		var seg: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from_on_nav, to_on_nav, true)
		if seg.size() >= 2:
			return seg
		return PackedVector3Array()
	# Fallback for scenes without a NavigationRegion3D (e.g. flat test maps).
	if unit.has_method("calculate_path_to"):
		var fallback: Variant = await unit.call("calculate_path_to", to)
		if fallback is PackedVector3Array:
			return fallback as PackedVector3Array
	return PackedVector3Array()


func _get_or_init_queue(unit: Node) -> Array:
	var key := unit.get_instance_id()
	if not _unit_keypoint_queues.has(key):
		_unit_keypoint_queues[key] = []
	return _unit_keypoint_queues[key]


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
	# 单位被选中，显示其当前路径（规划真源持久保存，不在此处改写端点）。
	if unit == null or not ("command_queue" in unit):
		return
	
	var command_queue = unit.get("command_queue")
	if command_queue == null:
		return
	
	var current_command = command_queue.get_current_command()
	if current_command && current_command is MoveCommand:
		if path_visual and path_visual.has_method("visualize_path"):
			path_visual.visualize_path(unit, (current_command as MoveCommand).path, _plan_waypoints(unit))
