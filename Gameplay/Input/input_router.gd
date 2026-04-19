# ~/Gameplay/Input/input_router.gd
extends Node

## Emitted with the selected unit, or `null` when selection is cleared.
signal unit_selected(unit: Node)
## PLANNING + LMB: same ground pick as `_screen_to_world` / path start. UI clicks never reach here.
signal planning_ground_pick(hit_position: Vector3, collider: Object)
signal path_drawing_started(unit: Node, start_position: Vector3)
signal path_drawing_updated(unit: Node, current_path: PackedVector3Array)
signal path_drawing_finished(unit: Node, final_path: PackedVector3Array)
signal path_clicked(unit: Node, path_index: int, position: Vector3)

var player_keybind: Node = null
var selected_unit: Node = null  # 只能选择一个单位

# 拖拽状态
var is_dragging: bool = false
var drag_start_position: Vector3 = Vector3.ZERO
var drag_start_path_index: int = -1  # 如果从路径上开始拖拽，记录路径点索引
var current_drag_path: PackedVector3Array = PackedVector3Array()

# 路径检测
var path_visualizer: Node = null

## 无带 `get_tactical_click_plane_y()` 的相机祖先时的回退 Y。
@export var ground_plane_y: float = 0.0
@export var screen_to_ground_use_plane_projection: bool = true
## After a ground pick (physics or plane fallback), clamp world X/Z to ±this value (meters). Matches finite ground in test scene (20×20 m).
@export var ground_pick_clamp_half_extent: float = 10.0

const _GROUND_FORWARD_LEN := 10_000.0
const _VERT_PROBE_UP := 512.0
const _VERT_PROBE_DOWN := 1024.0

## 拖拽采样：相邻关键点最小世界距离（防止点过密）。
@export var keypoint_min_distance: float = 0.22
## 松手时累计屏幕位移小于此视为「点一下」（用导航补到最后落点）；大于则保留手绘折线。
@export var ground_click_max_screen_drag_px: float = 14.0
## 点在路径上后松手：屏幕位移小于此才截断路径（避免拖拽误截断）。
@export var path_trim_max_screen_drag_px: float = 14.0
## 垂直差大于此且场景存在组 `stair_path_bridge` 的节点且实现 `plan_stair_path(from,to)->PackedVector3Array` 时走楼梯桥；否则退回导航网格。
@export var stair_height_threshold: float = 0.45

var _drag_screen_accum: float = 0.0
var _pending_path_trim: Dictionary = {}
var _path_click_screen_accum: float = 0.0

func _ready() -> void:
	if has_node("/root/PlayerKeybind"):
		player_keybind = get_node("/root/PlayerKeybind")
	else:
		player_keybind = get_node_or_null("../PlayerKeybind")
	
	# 查找路径可视化器
	path_visualizer = get_node_or_null("/root/PathVisualizer")
	if !path_visualizer:
		path_visualizer = get_tree().get_first_node_in_group("path_visualizer")
	
	if not GameStateManager.phase_changed.is_connected(_on_game_phase_changed):
		GameStateManager.phase_changed.connect(_on_game_phase_changed)

func _on_game_phase_changed(new_phase: GameStateManager.GamePhase) -> void:
	if new_phase != GameStateManager.GamePhase.EXECUTING:
		return
	if not is_dragging:
		return
	_cancel_active_path_drag()

func _cancel_active_path_drag() -> void:
	is_dragging = false
	drag_start_position = Vector3.ZERO
	drag_start_path_index = -1
	_drag_screen_accum = 0.0
	_pending_path_trim.clear()
	_path_click_screen_accum = 0.0
	current_drag_path.clear()
	if not selected_unit:
		return
	var command_queue = selected_unit.get("command_queue")
	if command_queue:
		var current_command = command_queue.get_current_command()
		if current_command and current_command is MoveCommand:
			if path_visualizer and path_visualizer.has_method("visualize_path"):
				path_visualizer.visualize_path(selected_unit, current_command.path)
			return
	if path_visualizer and path_visualizer.has_method("clear_path"):
		path_visualizer.clear_path(selected_unit)

func _input(event: InputEvent) -> void:
	if not player_keybind: return
	# Briefing / fullscreen overlays add nodes to this group; block game interactions.
	if get_tree().get_first_node_in_group("briefing_blocks_input") != null:
		return
	
	var current_phase = GameStateManager.get_phase()
	
	match current_phase:
		GameStateManager.GamePhase.PLANNING:
			_handle_planning_input(event)
		GameStateManager.GamePhase.EXECUTING:
			_handle_executing_input(event)
		GameStateManager.GamePhase.DEBRIEFING:
			_handle_debrief_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if not player_keybind:
		return
	if get_tree().get_first_node_in_group("briefing_blocks_input") != null:
		return
	
	var current_phase = GameStateManager.get_phase()
	match current_phase:
		GameStateManager.GamePhase.PLANNING:
			if event is InputEventMouseButton:
				_handle_mouse_button(event)
				var mb := event as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT:
					get_viewport().set_input_as_handled()
			elif event is InputEventMouseMotion:
				var mm := event as InputEventMouseMotion
				if not _pending_path_trim.is_empty():
					_path_click_screen_accum += mm.relative.length()
				if is_dragging:
					_handle_mouse_motion(mm)
					get_viewport().set_input_as_handled()
		GameStateManager.GamePhase.EXECUTING:
			if event is InputEventMouseButton:
				var mb2 := event as InputEventMouseButton
				if mb2.button_index == MOUSE_BUTTON_LEFT:
					get_viewport().set_input_as_handled()
		_:
			pass

func _handle_planning_input(event: InputEvent) -> void:
	if event.is_action_pressed(player_keybind.TOGGLE_EXECUTION_KEY):
		GameStateManager.start_execution()
		return

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	
	# 与 NAD-LAB 示例一致：用视口当前鼠标像素（与 `get_mouse_position()` 同源），避免与自定义光标帧不同步。
	var mouse_pos := get_viewport().get_mouse_position()
	var ground_hit := _raycast_ground(mouse_pos)
	var world_position := Vector3.ZERO
	if not ground_hit.is_empty():
		world_position = ground_hit["position"]
	
	if event.pressed and not ground_hit.is_empty():
		planning_ground_pick.emit(ground_hit["position"], ground_hit["collider"])
	
	if event.pressed:
		_on_mouse_press(world_position, mouse_pos)
	else:
		_on_mouse_release(world_position, mouse_pos)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if !is_dragging:
		return
	
	_drag_screen_accum += event.relative.length()
	var mouse_pos := get_viewport().get_mouse_position()
	var world_position = _screen_to_world(mouse_pos)
	
	if world_position == Vector3.ZERO:
		return
	
	# 更新拖拽路径
	_update_drag_path(world_position)

func _on_mouse_press(world_pos: Vector3, screen_pos: Vector2) -> void:
	var clicked_unit := _raycast_unit(screen_pos)
	if clicked_unit:
		_pending_path_trim.clear()
		_path_click_screen_accum = 0.0
		if selected_unit == clicked_unit:
			_deselect_unit()
		else:
			_select_unit(clicked_unit)
		return
	
	if selected_unit:
		var path_click_result := _check_path_click(selected_unit, screen_pos)
		if path_click_result:
			if selected_unit != path_click_result.unit:
				_select_unit(path_click_result.unit)
			_pending_path_trim = {
				"unit": path_click_result.unit,
				"path_index": path_click_result.path_index,
			}
			_path_click_screen_accum = 0.0
			return
	
	if selected_unit:
		_pending_path_trim.clear()
		_path_click_screen_accum = 0.0
		_start_new_path_drag(selected_unit, world_pos)

func _on_mouse_release(world_pos: Vector3, screen_pos: Vector2) -> void:
	if not _pending_path_trim.is_empty():
		var u: Node = _pending_path_trim.get("unit") as Node
		var idx: int = int(_pending_path_trim.get("path_index", -1))
		_pending_path_trim.clear()
		if _path_click_screen_accum <= path_trim_max_screen_drag_px and u != null and idx >= 0:
			_trim_path_to_index(u, idx)
		_path_click_screen_accum = 0.0
		return
	
	if not is_dragging:
		return
	_finish_path_drag(world_pos)

func _start_new_path_drag(unit: Node, start_pos: Vector3) -> void:
	selected_unit = unit
	drag_start_position = start_pos
	drag_start_path_index = -1
	is_dragging = true
	_drag_screen_accum = 0.0
	current_drag_path = PackedVector3Array()
	# 路径属于单位：第一个点是当前「端点」（上一段终点或脚底）。
	current_drag_path.append(_endpoint_world(unit))
	var emit_pos: Vector3 = current_drag_path[current_drag_path.size() - 1]
	path_drawing_started.emit(unit, emit_pos)


func _update_drag_path(world_pos: Vector3) -> void:
	if not selected_unit or current_drag_path.is_empty():
		return
	var last_point: Vector3 = current_drag_path[current_drag_path.size() - 1]
	if last_point.distance_to(world_pos) < keypoint_min_distance:
		return
	current_drag_path.append(world_pos)
	path_drawing_updated.emit(selected_unit, current_drag_path)

func _finish_path_drag(world_pos: Vector3) -> void:
	if not is_dragging or not selected_unit:
		return
	if current_drag_path.is_empty():
		current_drag_path.append(_endpoint_world(selected_unit))
	if _drag_screen_accum <= ground_click_max_screen_drag_px and current_drag_path.size() == 1:
		await _merge_endpoint_via_planner(selected_unit, world_pos)
	else:
		var last_point: Vector3 = current_drag_path[current_drag_path.size() - 1]
		if last_point.distance_to(world_pos) > 0.08:
			current_drag_path.append(world_pos)
	path_drawing_finished.emit(selected_unit, current_drag_path)
	
	is_dragging = false
	drag_start_position = Vector3.ZERO
	drag_start_path_index = -1
	_drag_screen_accum = 0.0

func _select_unit(unit: Node) -> void:
	if selected_unit == unit:
		return
	
	selected_unit = unit
	unit_selected.emit(unit)


func _deselect_unit() -> void:
	if selected_unit == null:
		return
	_pending_path_trim.clear()
	_path_click_screen_accum = 0.0
	if is_dragging:
		_cancel_active_path_drag()
	var u := selected_unit
	selected_unit = null
	if path_visualizer and path_visualizer.has_method("clear_path"):
		path_visualizer.clear_path(u)
	unit_selected.emit(null)

func _raycast_unit(screen_pos: Vector2) -> Node:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null
	
	var ray := CameraScreenRay.world_ray_for_pick(camera, screen_pos)
	var from: Vector3 = ray["origin"]
	var dir: Vector3 = ray["dir"]
	var to := from + dir * 1000.0
	
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2  # 单位层
	
	var result = space_state.intersect_ray(query)
	if result && result.collider.has_method("is_unit"):
		return result.collider
	
	return null

func _check_path_click(unit: Node, screen_pos: Vector2) -> Dictionary:
	# 检查是否点击了路径（用于选择单位）
	if !path_visualizer || !path_visualizer.has_method("get_path_at_screen_position"):
		return {}
	
	var path_result = path_visualizer.get_path_at_screen_position(unit, screen_pos)
	if path_result && path_result.has("unit"):
		return {
			"unit": path_result.unit,
			"path_index": path_result.get("path_index", -1),
			"position": path_result.get("position", Vector3.ZERO)
		}
	
	return {}


func _trim_path_to_index(unit: Node, path_index: int) -> void:
	var cq: Variant = unit.get("command_queue")
	if cq == null:
		return
	var mc: Variant = cq.get_current_command()
	if mc == null or not (mc is MoveCommand):
		return
	var move: MoveCommand = mc as MoveCommand
	if path_index < 0 or path_index >= move.path.size():
		return
	var newp := PackedVector3Array()
	for i in range(path_index + 1):
		newp.append(move.path[i])
	move.set_path(newp)
	if path_visualizer and path_visualizer.has_method("visualize_path"):
		path_visualizer.visualize_path(unit, newp)


## 当前路径「端点」：有 MoveCommand 则取路径末点，否则取脚底（战术上近似 2D 落点）。
func _endpoint_world(unit: Node) -> Vector3:
	if unit == null:
		return Vector3.ZERO
	var cq: Variant = unit.get("command_queue")
	if cq:
		var mc: Variant = cq.get_current_command()
		if mc is MoveCommand:
			var pth: PackedVector3Array = (mc as MoveCommand).path
			if pth.size() > 0:
				return pth[pth.size() - 1]
	return _unit_feet_world(unit)


func _unit_feet_world(unit: Node) -> Vector3:
	var p: Vector3 = unit.global_position
	var h: Variant = unit.get("current_height")
	if typeof(h) == TYPE_FLOAT or typeof(h) == TYPE_INT:
		p.y -= float(h) * 0.5
	return p


func _merge_endpoint_via_planner(unit: Node, to_world: Vector3) -> void:
	var from: Vector3 = current_drag_path[0]
	var used_bridge := false
	var bridge := get_tree().get_first_node_in_group(&"stair_path_bridge")
	if bridge != null and bridge.has_method(&"plan_stair_path") and absf(from.y - to_world.y) > stair_height_threshold:
		var planned: Variant = bridge.call(&"plan_stair_path", from, to_world, unit)
		if planned is PackedVector3Array:
			var pp: PackedVector3Array = planned as PackedVector3Array
			if pp.size() >= 2:
				current_drag_path = pp
				used_bridge = true
	if used_bridge:
		return
	if unit.has_method("calculate_path_to"):
		var seg: PackedVector3Array = await unit.calculate_path_to(to_world)
		if not seg.is_empty():
			current_drag_path = seg
		else:
			current_drag_path = PackedVector3Array([from, to_world])
	else:
		current_drag_path = PackedVector3Array([from, to_world])


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var hit := _raycast_ground(screen_pos)
	if hit.is_empty():
		return Vector3.ZERO
	return hit["position"]


func _clamp_ground_pick_xz(p: Vector3, plane_y: float) -> Vector3:
	var h := ground_pick_clamp_half_extent
	p.x = clampf(p.x, -h, h)
	p.z = clampf(p.z, -h, h)
	p.y = plane_y
	return p


func _resolve_ground_plane_y() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return ground_plane_y
	var n: Node = cam
	for _i in 8:
		if n != null && (n as Object).has_method(&"get_tactical_click_plane_y"):
			var y: Variant = (n as Object).call(&"get_tactical_click_plane_y")
			if typeof(y) == TYPE_FLOAT:
				return y
		n = n.get_parent()
	return ground_plane_y


func _raycast_ground(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var ray := CameraScreenRay.world_ray_for_pick(camera, screen_pos)
	var from: Vector3 = ray["origin"]
	var dir: Vector3 = ray["dir"]
	if dir.length_squared() < 1e-24:
		return {}
	dir = dir.normalized()
	var space_state := get_viewport().get_world_3d().direct_space_state
	var plane_y := _resolve_ground_plane_y()

	var forward_hit := _raycast_ground_physics_forward(from, dir, space_state)
	if not forward_hit.is_empty():
		var p: Vector3 = forward_hit["position"]
		p = _clamp_ground_pick_xz(p, plane_y)
		return {
			"position": p,
			"collider": forward_hit.get("collider"),
			"normal": forward_hit.get("normal", Vector3.UP),
		}

	if screen_to_ground_use_plane_projection:
		var plane_hit_dict := CameraScreenRay.intersect_horizontal_plane(camera, screen_pos, plane_y)
		if not plane_hit_dict.is_empty():
			var plane_hit: Vector3 = plane_hit_dict["position"]
			var snapped := _clamp_ground_pick_xz(plane_hit, plane_y)
			var probe_from := Vector3(snapped.x, snapped.y + _VERT_PROBE_UP, snapped.z)
			var probe_to := Vector3(snapped.x, snapped.y - _VERT_PROBE_DOWN, snapped.z)
			var pq := PhysicsRayQueryParameters3D.create(probe_from, probe_to)
			pq.collision_mask = 1
			var probe := space_state.intersect_ray(pq)
			if not probe.is_empty():
				return {
					"position": snapped,
					"collider": probe["collider"],
					"normal": probe.get("normal", Vector3.UP),
				}

	return {}


func _raycast_ground_physics_forward(from: Vector3, dir: Vector3, space_state: PhysicsDirectSpaceState3D) -> Dictionary:
	var to := from + dir * _GROUND_FORWARD_LEN
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	return space_state.intersect_ray(query)

func _handle_executing_input(event: InputEvent) -> void:
	if event.is_action_pressed(player_keybind.TOGGLE_EXECUTION_KEY):
		GameStateManager.pause_execution()

func _handle_debrief_input(event: InputEvent) -> void:
	if event.is_action_pressed(player_keybind.REWIND_KEY):
		_handle_rewind_input(event)
	
	if event.is_action_pressed(player_keybind.RESET_GAME_KEY):
		GameStateManager.reset_gamestate()

func _handle_rewind_input(event: InputEvent) -> void:
	var target_time = 120.0
	GameStateManager.backlog_from_debrief(target_time)

func get_selected_unit() -> Node:
	return selected_unit

func clear_selection() -> void:
	_deselect_unit()
