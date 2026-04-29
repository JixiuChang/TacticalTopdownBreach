# ~/Scenes/test_wall_destruction.gd
extends Node3D

# 测试可破坏墙壁系统的脚本
# 使用方法：将此脚本附加到测试场景的根节点

var test_wall: StaticBody3D = null
var explosion_position: Vector3 = Vector3.ZERO
var test_passed: int = 0
var test_failed: int = 0

func _ready() -> void:
	print("=".repeat(60))
	print("=== 可破坏墙壁系统测试 ===")
	print("=".repeat(60))
	
	# 等待系统初始化
	await get_tree().process_frame
	
	# 运行测试
	await _run_all_tests()
	
	# 打印总结
	_print_summary()

func _run_all_tests() -> void:
	await _test_wall_structure()
	await get_tree().process_frame
	
	await _test_explosion()
	await get_tree().process_frame
	
	await _test_debris_generation()
	await get_tree().process_frame
	
	await _test_snapshot_system()
	await get_tree().process_frame

func _test_wall_structure() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: 墙壁结构检查")
	print("-".repeat(60))
	
	var passed = true
	var errors: Array[String] = []
	
	# 查找测试墙壁
	test_wall = get_node_or_null("TestWall")
	if !test_wall:
		# 尝试创建测试墙壁
		test_wall = _create_test_wall()
	
	if !test_wall:
		passed = false
		errors.append("无法找到或创建测试墙壁")
		test_failed += 1
		print("✗ 墙壁结构检查: FAILED")
		for error in errors:
			print("  ERROR: ", error)
		return
	
	# 检查节点结构
	var mesh = test_wall.get_node_or_null("MeshInstance3D")
	var collision = test_wall.get_node_or_null("CollisionShape3D")
	var container = test_wall.get_node_or_null("DebrisContainer")
	
	if !mesh:
		passed = false
		errors.append("缺少 MeshInstance3D 节点")
	
	if !collision:
		passed = false
		errors.append("缺少 CollisionShape3D 节点")
	
	if !container:
		passed = false
		errors.append("缺少 DebrisContainer 节点")
	
	# 检查脚本
	if !test_wall.has_method("handle_explosion"):
		passed = false
		errors.append("墙壁脚本未正确附加或缺少 handle_explosion 方法")
	
	# 检查快照组
	if !test_wall.is_in_group("snapshotable"):
		passed = false
		errors.append("墙壁未加入 snapshotable 组")
	
	# 检查导出的属性
	if not ("debris_scene" in test_wall):
		passed = false
		errors.append("缺少 debris_scene 导出属性")
	
	if not ("debris_count" in test_wall):
		passed = false
		errors.append("缺少 debris_count 导出属性")
	
	# 检查碎片场景是否设置
	var debris_scene = test_wall.get("debris_scene")
	if !debris_scene:
		passed = false
		errors.append("Debris Scene 未设置（需要在 Inspector 中设置）")
		print("  WARNING: 请在 Inspector 中设置 Debris Scene 为 Prefabs/wall_debris.tscn")
	
	if passed:
		test_passed += 1
		print("✓ 墙壁结构检查: PASSED")
		print("  - MeshInstance3D: ✓")
		print("  - CollisionShape3D: ✓")
		print("  - DebrisContainer: ✓")
		print("  - Script: ✓")
		print("  - Snapshotable group: ✓")
	else:
		test_failed += 1
		print("✗ 墙壁结构检查: FAILED")
		for error in errors:
			print("  ERROR: ", error)

func _test_explosion() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: 爆炸功能测试")
	print("-".repeat(60))
	
	if !test_wall:
		print("✗ 爆炸功能测试: SKIPPED (无测试墙壁)")
		return
	
	var passed = true
	var errors: Array[String] = []
	
	# 检查墙壁初始状态
	if test_wall.has_method("is_destroyed"):
		var is_destroyed = test_wall.is_destroyed()
		if is_destroyed:
			passed = false
			errors.append("墙壁初始状态应该是未破坏的")
	
	# 设置爆炸位置（在墙壁中心附近）
	explosion_position = test_wall.global_position + Vector3(0, 0, 0.5)
	
	# 检查是否有 handle_explosion 方法
	if !test_wall.has_method("handle_explosion"):
		passed = false
		errors.append("缺少 handle_explosion 方法")
		test_failed += 1
		print("✗ 爆炸功能测试: FAILED")
		for error in errors:
			print("  ERROR: ", error)
		return
	
	# 调用爆炸（但不实际执行，只检查方法存在）
	print("  - handle_explosion 方法: ✓")
	print("  - 爆炸位置: ", explosion_position)
	
	if passed:
		test_passed += 1
		print("✓ 爆炸功能测试: PASSED")
	else:
		test_failed += 1
		print("✗ 爆炸功能测试: FAILED")
		for error in errors:
			print("  ERROR: ", error)

func _test_debris_generation() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: 碎片生成测试")
	print("-".repeat(60))
	
	if !test_wall:
		print("✗ 碎片生成测试: SKIPPED (无测试墙壁)")
		return
	
	var passed = true
	var errors: Array[String] = []
	
	# 检查碎片场景
	var debris_scene = test_wall.get("debris_scene")
	if !debris_scene:
		passed = false
		errors.append("Debris Scene 未设置")
		test_failed += 1
		print("✗ 碎片生成测试: FAILED")
		print("  ERROR: 请在 Inspector 中设置 Debris Scene")
		return
	
	# 检查碎片数量设置
	var debris_count = test_wall.get("debris_count")
	print("  - Debris Count 设置: ", debris_count)
	
	# 实际触发爆炸（如果可能）
	if test_wall.has_method("handle_explosion") && explosion_position != Vector3.ZERO:
		print("  - 触发测试爆炸...")
		test_wall.handle_explosion(explosion_position, 1.0)
		
		# 等待一帧让碎片生成
		await get_tree().process_frame
		await get_tree().process_frame
		
		# 检查碎片是否生成
		var container = test_wall.get_node_or_null("DebrisContainer")
		if container:
			var debris_count_actual = container.get_child_count()
			print("  - 生成的碎片数量: ", debris_count_actual)
			
			if debris_count_actual > 0:
				print("  - 碎片生成: ✓")
				
				# 检查碎片是否有快照功能
				var first_debris = container.get_child(0)
				if first_debris.is_in_group("snapshotable"):
					print("  - 碎片快照组: ✓")
				else:
					passed = false
					errors.append("碎片未加入 snapshotable 组")
			else:
				passed = false
				errors.append("未生成碎片")
		else:
			passed = false
			errors.append("找不到 DebrisContainer")
	
	if passed:
		test_passed += 1
		print("✓ 碎片生成测试: PASSED")
	else:
		test_failed += 1
		print("✗ 碎片生成测试: FAILED")
		for error in errors:
			print("  ERROR: ", error)

func _test_snapshot_system() -> void:
	print("\n" + "-".repeat(60))
	print("TEST: 快照系统测试")
	print("-".repeat(60))
	
	if !test_wall:
		print("✗ 快照系统测试: SKIPPED (无测试墙壁)")
		return
	
	var passed = true
	var errors: Array[String] = []
	
	# 检查墙壁是否有快照方法
	if !test_wall.has_method("capture_state"):
		passed = false
		errors.append("墙壁缺少 capture_state 方法")
	
	if !test_wall.has_method("restore_state"):
		passed = false
		errors.append("墙壁缺少 restore_state 方法")
	
	# 测试快照功能
	if test_wall.has_method("capture_state"):
		var state = test_wall.capture_state()
		print("  - capture_state 方法: ✓")
		print("  - 保存的状态键: ", state.keys())
		
		# 检查关键状态
		if state.has("is_destroyed"):
			print("  - is_destroyed 状态: ✓")
		else:
			passed = false
			errors.append("状态中缺少 is_destroyed")
		
		if state.has("wall_state"):
			print("  - wall_state 状态: ✓")
		else:
			passed = false
			errors.append("状态中缺少 wall_state")
		
		# 测试恢复功能
		if test_wall.has_method("restore_state"):
			test_wall.restore_state(state)
			print("  - restore_state 方法: ✓")
	
	# 检查碎片快照
	var container = test_wall.get_node_or_null("DebrisContainer")
	if container && container.get_child_count() > 0:
		var debris = container.get_child(0)
		if debris.has_method("capture_state"):
			var debris_state = debris.capture_state()
			print("  - 碎片 capture_state: ✓")
			print("  - 碎片状态键: ", debris_state.keys())
		else:
			passed = false
			errors.append("碎片缺少 capture_state 方法")
	
	if passed:
		test_passed += 1
		print("✓ 快照系统测试: PASSED")
	else:
		test_failed += 1
		print("✗ 快照系统测试: FAILED")
		for error in errors:
			print("  ERROR: ", error)

func _create_test_wall() -> StaticBody3D:
	# 尝试从预制体创建测试墙壁
	var wall_scene = load("res://Prefabs/wall_destructable.tscn") as PackedScene
	if !wall_scene:
		return null
	
	var wall = wall_scene.instantiate() as StaticBody3D
	if wall:
		wall.name = "TestWall"
		wall.global_position = Vector3(0, 1, 0)
		add_child(wall)
		print("  - 创建测试墙壁: ✓")
	
	return wall

func _print_summary() -> void:
	print("\n" + "=".repeat(60))
	print("=== 测试总结 ===")
	print("=".repeat(60))
	print("测试通过: ", test_passed)
	print("测试失败: ", test_failed)
	print("总测试数: ", test_passed + test_failed)
	
	if test_failed == 0:
		print("\n✓ 所有测试通过！")
	else:
		print("\n✗ 部分测试失败")
	print("=".repeat(60))
