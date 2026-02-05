# ~/Scenes/test_scene.gd
extends Node

var tests_passed: int = 0
var tests_failed: int = 0

func _ready() -> void:
	print("=".repeat(60))
	print("=== GameStateManager & TimeSimulator Test Suite ===")
	print("=".repeat(60))
	
	# 等待一帧确保 Autoload 已初始化
	await get_tree().process_frame
	
	# 运行所有测试
	await _run_all_tests()
	
	# 打印总结
	_print_summary()

func _run_all_tests() -> void:
	_test_phase_transitions()
	await get_tree().process_frame
	
	# 等待 Time Simulation 测试完全完成
	await _test_time_simulation()
	await get_tree().process_frame
	
	# 等待 Rewind 测试完全完成
	await _test_rewind()
	await get_tree().process_frame
	
	# 等待 Reset 测试完全完成
	await _test_reset()
	await get_tree().process_frame

func _test_phase_transitions() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: Phase Transitions")
	print("-".repeat(60))
	
	var passed = true
	var errors: Array[String] = []
	
	# 测试初始状态
	var initial_phase = GameStateManager.get_phase()
	print("✓ Initial Phase: ", GameStateManager._get_phase_name(initial_phase))
	if initial_phase != GameStateManager.GamePhase.BRIEFING:
		passed = false
		errors.append("Expected BRIEFING, got " + GameStateManager._get_phase_name(initial_phase))
	
	# BRIEFING → PLANNING
	var result = GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
	print("✓ BRIEFING → PLANNING: ", result)
	if not result:
		passed = false
		errors.append("Failed to transition to PLANNING")
	
	# PLANNING → EXECUTING
	result = GameStateManager.start_execution()
	print("✓ PLANNING → EXECUTING: ", result)
	if not result:
		passed = false
		errors.append("Failed to start execution")
	
	# 检查时间模拟器状态
	var current_time = TimeSimulator.get_current_time()
	print("✓ Current Time: ", TimeSimulator.format_time(current_time))
	if current_time != 180.0:
		passed = false
		errors.append("Expected 3:00, got " + TimeSimulator.format_time(current_time))
	
	# 检查模式
	var mode = TimeSimulator.mode
	print("✓ TimeSimulator mode: ", mode)
	if mode != "playing":
		passed = false
		errors.append("Expected 'playing', got '" + mode + "'")
	
	# EXECUTING → PLANNING (暂停)
	result = GameStateManager.pause_execution()
	print("✓ EXECUTING → PLANNING (pause): ", result)
	if not result:
		passed = false
		errors.append("Failed to pause execution")
	
	# 检查暂停后模式
	mode = TimeSimulator.mode
	print("✓ TimeSimulator mode after pause: ", mode)
	if mode != "paused":
		passed = false
		errors.append("Expected 'paused', got '" + mode + "'")
	
	# 记录结果
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
	
	# 确保在 PLANNING 阶段
	var current_phase = GameStateManager.get_phase()
	print("  Current phase before test: ", GameStateManager._get_phase_name(current_phase))
	
	# 如果不在 PLANNING，先转换到 PLANNING
	if current_phase != GameStateManager.GamePhase.PLANNING:
		if current_phase == GameStateManager.GamePhase.EXECUTING:
			GameStateManager.pause_execution()
		else:
			GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
		await get_tree().process_frame
	
	# 开始执行（这会重置时间到 180.0）
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
	
	# 等待一帧确保执行开始
	await get_tree().process_frame
	
	# 现在记录初始时间（在 start_execution 重置之后）
	var initial_time = TimeSimulator.get_current_time()
	print("  Initial time (after start_execution): ", TimeSimulator.format_time(initial_time))
	
	# 检查模式
	var mode = TimeSimulator.mode
	print("  TimeSimulator mode: ", mode)
	if mode != "playing":
		passed = false
		errors.append("Expected 'playing', got '" + mode + "'")
	
	# 等待 0.6 秒让时间推进
	await get_tree().create_timer(0.6).timeout
	
	# 再等待一帧确保所有更新完成
	await get_tree().process_frame
	
	# 记录推进后的时间
	var time_after = TimeSimulator.get_current_time()
	var min_time = TimeSimulator.get_min_executed_time()
	
	print("  Time after 0.6s wait: ", TimeSimulator.format_time(time_after))
	print("  Min executed time: ", TimeSimulator.format_time(min_time))
	
	# 验证时间应该减少（倒计时）
	if time_after >= initial_time:
		passed = false
		errors.append("Time should decrease (was " + TimeSimulator.format_time(time_after) + ", started at " + TimeSimulator.format_time(initial_time) + ")")
	
	# 验证时间应该减少了大约 0.6 秒（允许一些误差）
	var expected_reduction = 0.6
	var actual_reduction = initial_time - time_after
	var tolerance = 0.2  # 允许 0.2 秒误差
	
	print("  Expected reduction: ~", expected_reduction, "s")
	print("  Actual reduction: ", actual_reduction, "s")
	
	if actual_reduction < (expected_reduction - tolerance):
		passed = false
		errors.append("Time should reduce by ~" + str(expected_reduction) + "s, but reduced by " + str(actual_reduction) + "s")
	
	# 验证最小执行时间
	if min_time > time_after:
		passed = false
		errors.append("Min time (" + TimeSimulator.format_time(min_time) + ") should be <= current time (" + TimeSimulator.format_time(time_after) + ")")
	
	# 检查快照（在检查前不要暂停，因为快照可能在暂停时被清除）
	var snapshot_count = TimeSimulator.snapshots.size()
	print("  Snapshots created: ", snapshot_count)
	# 快照每 5 秒创建一次，0.6 秒内不应该有快照（除了初始快照）
	# 但初始快照应该在 start_execution() 时创建
	if snapshot_count < 1:
		passed = false
		errors.append("Should have at least 1 snapshot (initial)")
	
	# 验证时间只在执行阶段推进
	# 暂停执行
	GameStateManager.pause_execution()
	await get_tree().process_frame
	
	var time_before_pause = TimeSimulator.get_current_time()
	print("  Time before pause: ", TimeSimulator.format_time(time_before_pause))
	
	# 等待一段时间
	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame
	
	var time_after_pause = TimeSimulator.get_current_time()
	print("  Time after pause (0.2s later): ", TimeSimulator.format_time(time_after_pause))
	
	# 暂停后时间不应该变化（或变化很小，因为暂停时可能还有累积器残留）
	var time_change = abs(time_after_pause - time_before_pause)
	if time_change > 0.05:
		passed = false
		errors.append("Time should not advance when paused (changed by " + str(time_change) + ")")
	
	# 记录结果
	if passed:
		tests_passed += 1
		print("✓ Time simulation: PASSED")
	else:
		tests_failed += 1
		print("✗ Time simulation: FAILED")
		for error in errors:
			print("  ERROR: ", error)
	
	# 确保测试完成后，系统处于可预测状态（PLANNING 阶段）
	if GameStateManager.get_phase() != GameStateManager.GamePhase.PLANNING:
		GameStateManager.pause_execution()
		await get_tree().process_frame

func _test_rewind() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: Rewind System")
	print("-".repeat(60))
	
	var passed = true
	var errors: Array[String] = []
	
	# 确保在 PLANNING 阶段
	var current_phase = GameStateManager.get_phase()
	if current_phase != GameStateManager.GamePhase.PLANNING:
		if current_phase == GameStateManager.GamePhase.EXECUTING:
			GameStateManager.pause_execution()
		else:
			GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
		await get_tree().process_frame
	
	# 开始执行并让时间推进，创建一些快照
	GameStateManager.start_execution()
	await get_tree().process_frame
	
	# 等待足够的时间让快照创建（至少 5 秒，因为快照间隔是 5 秒）
	# 但为了测试速度，我们等待 6 秒，这样会有至少 1 个快照（初始 + 1 个间隔快照）
	await get_tree().create_timer(6.0).timeout
	await get_tree().process_frame
	
	var time_before_timeout = TimeSimulator.get_current_time()
	var snapshot_count = TimeSimulator.snapshots.size()
	print("  Time before timeout: ", TimeSimulator.format_time(time_before_timeout))
	print("  Snapshots available: ", snapshot_count)
	
	# 确保有快照
	if snapshot_count < 1:
		passed = false
		errors.append("Need at least 1 snapshot for rewind test")
		tests_failed += 1
		print("✗ Rewind system: FAILED - No snapshots available")
		for error in errors:
			print("  ERROR: ", error)
		GameStateManager.pause_execution()
		return
	
	# 现在手动触发时间耗尽（模拟到达 0:00）
	# 注意：我们需要在 EXECUTING 阶段调用 on_timeout
	TimeSimulator.simulation_time = 0.0
	TimeSimulator.min_executed_time = 0.0
	
	# 确保在 EXECUTING 阶段
	if GameStateManager.get_phase() != GameStateManager.GamePhase.EXECUTING:
		# 如果不在执行阶段，先进入
		GameStateManager.phase_enter(GameStateManager.GamePhase.PLANNING)
		GameStateManager.start_execution()
		await get_tree().process_frame
	
	# 现在调用 on_timeout
	GameStateManager.on_timeout()
	
	# 等待一帧让状态更新
	await get_tree().process_frame
	
	# 检查是否进入 DEBRIEFING
	var phase = GameStateManager.get_phase()
	print("  Phase after timeout: ", GameStateManager._get_phase_name(phase))
	print("  DEBUG: Objective completed: ", GameStateManager.objective_completed)
	print("  DEBUG: Objective failed: ", GameStateManager.objective_failed)
	
	if phase != GameStateManager.GamePhase.DEBRIEFING:
		passed = false
		errors.append("Expected DEBRIEFING, got " + GameStateManager._get_phase_name(phase))
	
	# 测试倒带 - 选择一个有快照的时间（比如 120.0，应该在快照范围内）
	# 但我们需要检查实际可用的快照时间
	var rewind_time = 120.0
	if snapshot_count > 0:
		# 使用第一个快照之后的时间
		var first_snapshot_time = TimeSimulator.snapshots[0].time
		if first_snapshot_time < 120.0:
			rewind_time = first_snapshot_time + 10.0  # 使用快照时间 + 10秒
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
		
		# 验证时间是否正确（允许 5 秒误差，因为快照间隔是 5 秒）
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
