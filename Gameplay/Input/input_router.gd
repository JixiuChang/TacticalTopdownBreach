# ~/Gameplay/Input/input_router.gd
extends Node

signal ground_selected(position: Vector3)
signal unit_selected(unit: Node)

var player_keybind: Node = null

func _ready() -> void:
	# 获取 PlayerKeybind（Autoload 或场景节点）
	if has_node("/root/PlayerKeybind"):
		player_keybind = get_node("/root/PlayerKeybind")
	else:
		player_keybind = get_node_or_null("../PlayerKeybind")

func _input(event: InputEvent) -> void:
	if not player_keybind: return
	
	var current_phase = GameStateManager.get_phase()
	
	match current_phase:
		GameStateManager.GamePhase.PLANNING:
			_handle_planning_input(event)
		GameStateManager.GamePhase.EXECUTING:
			_handle_executing_input(event)
		GameStateManager.GamePhase.DEBRIEFING:
			_handle_debrief_input(event)

func _handle_planning_input(event: InputEvent) -> void:
	# 使用 player_keybind 的变量
	if event.is_action_pressed(player_keybind.TOGGLE_EXECUTION_KEY):
		GameStateManager.start_execution()
	
	if event.is_action_pressed(player_keybind.SELECT_GROUND_KEY):
		_handle_ground_selection(event)
	
	if event.is_action_pressed(player_keybind.SELECT_UNIT_KEY):
		_handle_unit_selection(event)

func _handle_executing_input(event: InputEvent) -> void:
	if event.is_action_pressed(player_keybind.TOGGLE_EXECUTION_KEY):
		GameStateManager.pause_execution()

func _handle_debrief_input(event: InputEvent) -> void:
	if event.is_action_pressed(player_keybind.REWIND_KEY):
		_handle_rewind_input(event)
	
	if event.is_action_pressed(player_keybind.RESET_GAME_KEY):
		GameStateManager.reset_gamestate()

func _handle_ground_selection(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	
	var mouse_event = event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed: return
	
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var from = camera.project_ray_origin(mouse_event.position)
	var to = from + camera.project_ray_normal(mouse_event.position) * 1000.0
	
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # 地面层
	
	var result = space_state.intersect_ray(query)
	if result:
		ground_selected.emit(result.position)

func _handle_unit_selection(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	
	var mouse_event = event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed: return
	
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var from = camera.project_ray_origin(mouse_event.position)
	var to = from + camera.project_ray_normal(mouse_event.position) * 1000.0
	
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2  # 单位层
	
	var result = space_state.intersect_ray(query)
	if result and result.collider.has_method("is_unit"):
		unit_selected.emit(result.collider)

func _handle_rewind_input(event: InputEvent) -> void:
	# 暂时使用示例值，后续可以通过 UI 选择时间戳
	var target_time = 120.0
	GameStateManager.backlog_from_debrief(target_time)
