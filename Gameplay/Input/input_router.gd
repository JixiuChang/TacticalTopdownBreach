# ~/Gameplay/Input/input_router.gd
extends Node

## Emitted with the selected unit, or `null` when selection is cleared.
signal unit_selected(unit: Node)
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
				_handle_mouse_motion(event)
				if is_dragging:
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
	
	var mouse_pos = event.position
	var world_position = _screen_to_world(mouse_pos)
	
	if event.pressed:
		# 鼠标按下
		_on_mouse_press(world_position, mouse_pos)
	else:
		# 鼠标释放
		_on_mouse_release(world_position, mouse_pos)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if !is_dragging:
		return
	
	var mouse_pos = event.position
	var world_position = _screen_to_world(mouse_pos)
	
	if world_position == Vector3.ZERO:
		return
	
	# 更新拖拽路径
	_update_drag_path(world_position)

func _on_mouse_press(world_pos: Vector3, screen_pos: Vector2) -> void:
	# 1. 检查是否点击了单位
	var clicked_unit = _raycast_unit(screen_pos)
	if clicked_unit:
		if selected_unit == clicked_unit:
			_deselect_unit()
		else:
			_select_unit(clicked_unit)
		return
	
	# 2. 检查是否点击了路径
	if selected_unit:
		var path_click_result = _check_path_click(selected_unit, screen_pos)
		if path_click_result:
			# 点击了路径，选择单位（如果还没选中）
			if selected_unit != path_click_result.unit:
				_select_unit(path_click_result.unit)
			
			# 从路径点开始拖拽
			_start_path_drag(path_click_result.unit, path_click_result.path_index, path_click_result.position)
			return
	
	# 3. 检查是否从已有路径开始拖拽
	if selected_unit:
		var path_drag_result = _check_path_drag_start(selected_unit, screen_pos)
		if path_drag_result:
			# 从路径上开始拖拽，不选择单位
			_start_path_drag(path_drag_result.unit, path_drag_result.path_index, path_drag_result.position)
			return
	
	# 4. 如果有选中单位，开始新的路径绘制
	if selected_unit:
		_start_new_path_drag(selected_unit, world_pos)

func _on_mouse_release(world_pos: Vector3, screen_pos: Vector2) -> void:
	if !is_dragging:
		return
	
	# 完成路径绘制
	_finish_path_drag(world_pos)

func _start_new_path_drag(unit: Node, start_pos: Vector3) -> void:
	selected_unit = unit
	drag_start_position = start_pos
	drag_start_path_index = -1
	is_dragging = true
	current_drag_path = PackedVector3Array()
	current_drag_path.append(start_pos)
	
	path_drawing_started.emit(unit, start_pos)

func _start_path_drag(unit: Node, path_index: int, start_pos: Vector3) -> void:
	selected_unit = unit
	drag_start_position = start_pos
	drag_start_path_index = path_index
	is_dragging = true
	
	# 获取当前路径，保留 path_index 之前的部分
	var command_queue = unit.get("command_queue")
	if command_queue:
		var current_command = command_queue.get_current_command()
		if current_command && current_command is MoveCommand:
			var existing_path = current_command.path
			current_drag_path = PackedVector3Array()
			
			# 保留 path_index 之前的所有点
			for i in range(min(path_index + 1, existing_path.size())):
				current_drag_path.append(existing_path[i])
			
			# 添加新的起始点
			current_drag_path.append(start_pos)
		else:
			current_drag_path = PackedVector3Array()
			current_drag_path.append(start_pos)
	else:
		current_drag_path = PackedVector3Array()
		current_drag_path.append(start_pos)
	
	path_drawing_started.emit(unit, start_pos)

func _update_drag_path(world_pos: Vector3) -> void:
	if !selected_unit || current_drag_path.is_empty():
		return
	
	# 使用 NavigationAgent3D 计算到新位置的路径
	var last_point = current_drag_path[current_drag_path.size() - 1]
	
	# 如果距离太近，不添加新点
	if last_point.distance_to(world_pos) < 0.5:
		return
	
	# 计算路径段（使用 NavigationAgent3D）
	if selected_unit.has_method("calculate_path_to"):
		var segment_path = await selected_unit.calculate_path_to(world_pos)
		
		if !segment_path.is_empty():
			# 合并路径（移除第一个点，因为它是 last_point）
			var merged_path = PackedVector3Array()
			merged_path.append_array(current_drag_path)
			
			# 添加新路径段（跳过第一个点）
			for i in range(1, segment_path.size()):
				merged_path.append(segment_path[i])
			
			current_drag_path = merged_path
			path_drawing_updated.emit(selected_unit, current_drag_path)

func _finish_path_drag(world_pos: Vector3) -> void:
	if !is_dragging || !selected_unit:
		return
	
	# 确保路径以最终位置结束
	if current_drag_path.is_empty():
		current_drag_path.append(world_pos)
	else:
		var last_point = current_drag_path[current_drag_path.size() - 1]
		if last_point.distance_to(world_pos) > 0.1:
			# 计算到最终位置的路径
			if selected_unit.has_method("calculate_path_to"):
				var final_segment = await selected_unit.calculate_path_to(world_pos)
				if !final_segment.is_empty():
					var merged_path = PackedVector3Array()
					merged_path.append_array(current_drag_path)
					for i in range(1, final_segment.size()):
						merged_path.append(final_segment[i])
					current_drag_path = merged_path
	
	# 完成路径绘制
	path_drawing_finished.emit(selected_unit, current_drag_path)
	
	# 重置拖拽状态
	is_dragging = false
	drag_start_position = Vector3.ZERO
	drag_start_path_index = -1

func _select_unit(unit: Node) -> void:
	if selected_unit == unit:
		return
	
	selected_unit = unit
	unit_selected.emit(unit)


func _deselect_unit() -> void:
	if selected_unit == null:
		return
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
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0
	
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

func _check_path_drag_start(unit: Node, screen_pos: Vector2) -> Dictionary:
	# 检查是否从已有路径开始拖拽
	if !path_visualizer || !path_visualizer.has_method("get_path_at_screen_position"):
		return {}
	
	var path_result = path_visualizer.get_path_at_screen_position(unit, screen_pos)
	if path_result && path_result.has("unit"):
		# 从路径上开始拖拽，不选择单位
		return {
			"unit": path_result.unit,
			"path_index": path_result.get("path_index", -1),
			"position": path_result.get("position", Vector3.ZERO)
		}
	
	return {}

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0
	
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # 地面层
	
	var result = space_state.intersect_ray(query)
	if result:
		return result.position
	
	return Vector3.ZERO

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
