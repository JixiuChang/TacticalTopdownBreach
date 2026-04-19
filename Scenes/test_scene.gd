# ~/Scenes/test_scene.gd
extends Node3D

## Run console automation (GameState / time). When false, play Test Level with briefing HUD.
@export var run_automated_tests: bool = false

## Per-level briefing (English for localization pipeline). Override per scene instance in editor.
@export var briefing_title: String = "Test Level"
@export_multiline var briefing_body: String = "This is a sandbox test map.\nYou can try UI flow, planning, and execution timing."

const GROUP_BRIEFING_BLOCKS_INPUT: String = "briefing_blocks_input"
const DEBUG_GROUND_GROUP: StringName = &"debug_ground_click"

var tests_passed: int = 0
var tests_failed: int = 0

var _briefing_layer: CanvasLayer = null
var _briefing_panel: Control = null
@onready var _click_indicator: ClickIndicatorFX = $ClickIndicator

func _ready() -> void:
	if run_automated_tests:
		await _run_automated_suite()
		return
	
	GameStateManager.reset_gamestate()
	await get_tree().process_frame
	_build_briefing_ui()
	if not run_automated_tests:
		_connect_ground_click_indicator()


func _connect_ground_click_indicator() -> void:
	var router := get_node_or_null("/root/InputRouter")
	if router == null:
		return
	if router.planning_ground_pick.is_connected(_on_router_planning_ground_pick):
		return
	router.planning_ground_pick.connect(_on_router_planning_ground_pick)


func _on_router_planning_ground_pick(hit_position: Vector3, collider: Object) -> void:
	if run_automated_tests:
		return
	if get_tree().get_first_node_in_group(GROUP_BRIEFING_BLOCKS_INPUT) != null:
		return
	if GameStateManager.get_phase() != GameStateManager.GamePhase.PLANNING:
		return
	if collider is Node and not _node_or_ancestor_in_ground_group(collider as Node):
		return
	if _click_indicator != null:
		_click_indicator.play_at(hit_position)


func _node_or_ancestor_in_ground_group(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_in_group(DEBUG_GROUND_GROUP):
			return true
		p = p.get_parent()
	return false


func _unhandled_input(event: InputEvent) -> void:
	if run_automated_tests:
		return
	if !_is_briefing_visible():
		return
	if event.is_echo():
		return
	if !event.is_pressed():
		return
	if event is InputEventMouseButton && _is_continue_mouse_button(event.button_index):
		_dismiss_briefing()
		get_viewport().set_input_as_handled()


func _is_briefing_visible() -> bool:
	return _briefing_panel != null && _briefing_panel.visible


func _is_continue_mouse_button(button: int) -> bool:
	return (
		button == MOUSE_BUTTON_LEFT
		|| button == MOUSE_BUTTON_RIGHT
		|| button == MOUSE_BUTTON_MIDDLE
	)


func _on_briefing_gui_input(event: InputEvent) -> void:
	if !_is_briefing_visible():
		return
	if event is InputEventMouseButton && event.pressed && _is_continue_mouse_button(event.button_index):
		_dismiss_briefing()
		_briefing_panel.accept_event()


func _build_briefing_ui() -> void:
	_briefing_layer = CanvasLayer.new()
	_briefing_layer.layer = 100
	_briefing_layer.name = "BriefingLayer"
	add_child(_briefing_layer)
	
	var root := Control.new()
	root.name = "BriefingRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_to_group(GROUP_BRIEFING_BLOCKS_INPUT)
	_briefing_layer.add_child(root)
	_briefing_panel = root
	
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.06, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	
	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 96)
	root.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)
	
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = briefing_title
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var sep := HSeparator.new()
	vbox.add_child(sep)
	
	var body := RichTextLabel.new()
	body.name = "Body"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "[center]" + briefing_body.replace("\n", "\n") + "[/center]"
	vbox.add_child(body)
	
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "Click to continue."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 20)
	footer.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(footer)
	
	var click_catcher := Control.new()
	click_catcher.name = "ClickCatcher"
	click_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	click_catcher.gui_input.connect(_on_briefing_gui_input)
	root.add_child(click_catcher)


func _dismiss_briefing() -> void:
	if _briefing_panel:
		_briefing_panel.visible = false
		_briefing_panel.remove_from_group(GROUP_BRIEFING_BLOCKS_INPUT)
	GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)


func _run_automated_suite() -> void:
	GameStateManager.reset_gamestate()
	print("=".repeat(60))
	print("=== GameStateManager & TimeSimulator Test Suite ===")
	print("=".repeat(60))
	await get_tree().process_frame
	await _run_all_tests()
	_print_summary()


func _run_all_tests() -> void:
	_test_phase_transitions()
	await get_tree().process_frame
	await _test_time_simulation()
	await get_tree().process_frame
	await _test_rewind()
	await get_tree().process_frame
	await _test_reset()
	await get_tree().process_frame


func _test_phase_transitions() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: Phase Transitions")
	print("-".repeat(60))
	var passed = true
	var errors: Array[String] = []
	var initial_phase = GameStateManager.get_phase()
	print("✓ Initial Phase: ", GameStateManager._get_phase_name(initial_phase))
	if initial_phase != GameStateManager.GamePhase.BRIEFING:
		passed = false
		errors.append("Expected BRIEFING, got " + GameStateManager._get_phase_name(initial_phase))
	var result = GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
	print("✓ BRIEFING → PLANNING: ", result)
	if not result:
		passed = false
		errors.append("Failed to transition to PLANNING")
	result = GameStateManager.start_execution()
	print("✓ PLANNING → EXECUTING: ", result)
	if not result:
		passed = false
		errors.append("Failed to start execution")
	var current_time = TimeSimulator.get_current_time()
	print("✓ Current Time: ", TimeSimulator.format_time(current_time))
	if current_time != 180.0:
		passed = false
		errors.append("Expected 3:00, got " + TimeSimulator.format_time(current_time))
	var mode = TimeSimulator.mode
	print("✓ TimeSimulator mode: ", mode)
	if mode != "playing":
		passed = false
		errors.append("Expected 'playing', got '" + mode + "'")
	result = GameStateManager.pause_execution()
	print("✓ EXECUTING → PLANNING (pause): ", result)
	if not result:
		passed = false
		errors.append("Failed to pause execution")
	mode = TimeSimulator.mode
	print("✓ TimeSimulator mode after pause: ", mode)
	if mode != "paused":
		passed = false
		errors.append("Expected 'paused', got '" + mode + "'")
	if passed:
		tests_passed += 1
		print("✓ Phase transitions: PASSED")
	else:
		tests_failed += 1
		print("✗ Phase transitions: FAILED")
		for error in errors:
			print("  ERROR: ", error)


func _test_time_simulation() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: Time Simulation")
	print("-".repeat(60))
	var passed = true
	var errors: Array[String] = []
	var current_phase = GameStateManager.get_phase()
	print("  Current phase before test: ", GameStateManager._get_phase_name(current_phase))
	if current_phase != GameStateManager.GamePhase.PLANNING:
		if current_phase == GameStateManager.GamePhase.EXECUTING:
			GameStateManager.pause_execution()
		else:
			GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
		await get_tree().process_frame
	var start_result = GameStateManager.start_execution()
	print("  Start execution result: ", start_result)
	if not start_result:
		passed = false
		errors.append("Failed to start execution")
		tests_failed += 1
		print("✗ Time simulation: FAILED - Cannot start execution")
		for error in errors:
			print("  ERROR: ", error)
		return
	await get_tree().process_frame
	var initial_time = TimeSimulator.get_current_time()
	print("  Initial time (after start_execution): ", TimeSimulator.format_time(initial_time))
	var mode = TimeSimulator.mode
	print("  TimeSimulator mode: ", mode)
	if mode != "playing":
		passed = false
		errors.append("Expected 'playing', got '" + mode + "'")
	await get_tree().create_timer(0.6).timeout
	await get_tree().process_frame
	var time_after = TimeSimulator.get_current_time()
	var min_time = TimeSimulator.get_min_executed_time()
	print("  Time after 0.6s wait: ", TimeSimulator.format_time(time_after))
	print("  Min executed time: ", TimeSimulator.format_time(min_time))
	if time_after >= initial_time:
		passed = false
		errors.append("Time should decrease (was " + TimeSimulator.format_time(time_after) + ", started at " + TimeSimulator.format_time(initial_time) + ")")
	var expected_reduction = 0.6
	var actual_reduction = initial_time - time_after
	var tolerance = 0.2
	print("  Expected reduction: ~", expected_reduction, "s")
	print("  Actual reduction: ", actual_reduction, "s")
	if actual_reduction < (expected_reduction - tolerance):
		passed = false
		errors.append("Time should reduce by ~" + str(expected_reduction) + "s, but reduced by " + str(actual_reduction) + "s")
	if min_time > time_after:
		passed = false
		errors.append("Min time (" + TimeSimulator.format_time(min_time) + ") should be <= current time (" + TimeSimulator.format_time(time_after) + ")")
	var snapshot_count = TimeSimulator.snapshots.size()
	print("  Snapshots created: ", snapshot_count)
	if snapshot_count < 1:
		passed = false
		errors.append("Should have at least 1 snapshot (initial)")
	GameStateManager.pause_execution()
	await get_tree().process_frame
	var time_before_pause = TimeSimulator.get_current_time()
	print("  Time before pause: ", TimeSimulator.format_time(time_before_pause))
	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame
	var time_after_pause = TimeSimulator.get_current_time()
	print("  Time after pause (0.2s later): ", TimeSimulator.format_time(time_after_pause))
	var time_change = abs(time_after_pause - time_before_pause)
	if time_change > 0.05:
		passed = false
		errors.append("Time should not advance when paused (changed by " + str(time_change) + ")")
	if passed:
		tests_passed += 1
		print("✓ Time simulation: PASSED")
	else:
		tests_failed += 1
		print("✗ Time simulation: FAILED")
		for error in errors:
			print("  ERROR: ", error)
	if GameStateManager.get_phase() != GameStateManager.GamePhase.PLANNING:
		GameStateManager.pause_execution()
		await get_tree().process_frame


func _test_rewind() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: Rewind System")
	print("-".repeat(60))
	var passed = true
	var errors: Array[String] = []
	var current_phase = GameStateManager.get_phase()
	if current_phase != GameStateManager.GamePhase.PLANNING:
		if current_phase == GameStateManager.GamePhase.EXECUTING:
			GameStateManager.pause_execution()
		else:
			GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
		await get_tree().process_frame
	GameStateManager.start_execution()
	await get_tree().process_frame
	await get_tree().create_timer(6.0).timeout
	await get_tree().process_frame
	var time_before_timeout = TimeSimulator.get_current_time()
	var snapshot_count = TimeSimulator.snapshots.size()
	print("  Time before timeout: ", TimeSimulator.format_time(time_before_timeout))
	print("  Snapshots available: ", snapshot_count)
	if snapshot_count < 1:
		passed = false
		errors.append("Need at least 1 snapshot for rewind test")
		tests_failed += 1
		print("✗ Rewind system: FAILED - No snapshots available")
		for error in errors:
			print("  ERROR: ", error)
		GameStateManager.pause_execution()
		return
	TimeSimulator.simulation_time = 0.0
	TimeSimulator.min_executed_time = 0.0
	if GameStateManager.get_phase() != GameStateManager.GamePhase.EXECUTING:
		GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
		GameStateManager.start_execution()
		await get_tree().process_frame
	GameStateManager.on_timeout()
	await get_tree().process_frame
	var phase = GameStateManager.get_phase()
	print("  Phase after timeout: ", GameStateManager._get_phase_name(phase))
	print("  DEBUG: Objective completed: ", GameStateManager.objective_completed)
	print("  DEBUG: Objective failed: ", GameStateManager.objective_failed)
	if phase != GameStateManager.GamePhase.DEBRIEFING:
		passed = false
		errors.append("Expected DEBRIEFING, got " + GameStateManager._get_phase_name(phase))
	var rewind_time = 120.0
	if snapshot_count > 0:
		var first_snapshot_time = TimeSimulator.snapshots[0].time
		if first_snapshot_time < 120.0:
			rewind_time = first_snapshot_time + 10.0
		else:
			rewind_time = first_snapshot_time
	print("  Attempting rewind to: ", TimeSimulator.format_time(rewind_time))
	var result = GameStateManager.backlog_from_debrief(rewind_time)
	print("  Rewind result: ", result)
	if result:
		var new_time = TimeSimulator.get_current_time()
		var new_phase = GameStateManager.get_phase()
		print("  Time after rewind: ", TimeSimulator.format_time(new_time))
		print("  Phase after rewind: ", GameStateManager._get_phase_name(new_phase))
		if new_phase != GameStateManager.GamePhase.PLANNING:
			passed = false
			errors.append("Expected PLANNING after rewind, got " + GameStateManager._get_phase_name(new_phase))
		if abs(new_time - rewind_time) > 5.0:
			passed = false
			errors.append("Rewind time should be ~" + TimeSimulator.format_time(rewind_time) + ", got " + TimeSimulator.format_time(new_time))
	else:
		passed = false
		errors.append("Rewind failed")
	if passed:
		tests_passed += 1
		print("✓ Rewind system: PASSED")
	else:
		tests_failed += 1
		print("✗ Rewind system: FAILED")
		for error in errors:
			print("  ERROR: ", error)


func _test_reset() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: Reset")
	print("-".repeat(60))
	var passed = true
	var errors: Array[String] = []
	GameStateManager.reset_gamestate()
	var phase = GameStateManager.get_phase()
	var time = TimeSimulator.get_current_time()
	print("  Phase after reset: ", GameStateManager._get_phase_name(phase))
	print("  Time after reset: ", TimeSimulator.format_time(time))
	if phase != GameStateManager.GamePhase.BRIEFING:
		passed = false
		errors.append("Expected BRIEFING, got " + GameStateManager._get_phase_name(phase))
	if time != 180.0:
		passed = false
		errors.append("Expected 3:00, got " + TimeSimulator.format_time(time))
	if passed:
		tests_passed += 1
		print("✓ Reset: PASSED")
	else:
		tests_failed += 1
		print("✗ Reset: FAILED")
		for error in errors:
			print("  ERROR: ", error)


func _print_summary() -> void:
	print("\n" + "=".repeat(60))
	print("=== Test Summary ===")
	print("=".repeat(60))
	print("Tests Passed: ", tests_passed)
	print("Tests Failed: ", tests_failed)
	print("Total Tests: ", tests_passed + tests_failed)
	if tests_failed == 0:
		print("\n✓ ALL TESTS PASSED!")
	else:
		print("\n✗ SOME TESTS FAILED")
	print("=".repeat(60))
