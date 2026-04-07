# ~/Prefabs/wall_destructable.gd
extends StaticBody3D

enum WallState { INTACT, DESTROYED }

@export var debris_scene: PackedScene = null
@export var debris_count: int = 8
@export var explosion_force_multiplier: float = 10.0

var wall_state: WallState = WallState.INTACT
var destroyed: bool = false
var destruction_time: float = -1.0

# 节点引用
var intact_mesh: MeshInstance3D = null
var collision_shape: CollisionShape3D = null
var debris_container: Node3D = null

# 碎片追踪（用于防止重复生成）
var debris_instances: Array[RigidBody3D] = []

signal wall_destroyed(wall: StaticBody3D, explosion_position: Vector3)

func _ready() -> void:
	# 加入快照组
	add_to_group("snapshotable")
	
	# 获取节点引用
	intact_mesh = get_node_or_null("MeshInstance3D")
	collision_shape = get_node_or_null("CollisionShape3D")
	
	# 创建碎片容器
	debris_container = get_node_or_null("DebrisContainer")
	if !debris_container:
		debris_container = Node3D.new()
		debris_container.name = "DebrisContainer"
		add_child(debris_container)
	
	# 如果没有指定碎片场景，尝试加载默认的
	if !debris_scene:
		debris_scene = load("res://Prefabs/wall_debris.tscn") as PackedScene
	
	# 收集现有的碎片（如果从快照恢复）
	_collect_existing_debris()

func _collect_existing_debris() -> void:
	# 收集已经存在的碎片（从快照恢复时）
	if debris_container:
		for child in debris_container.get_children():
			if child is RigidBody3D:
				var debris = child as RigidBody3D
				if !debris_instances.has(debris):
					debris_instances.append(debris)
					# 设置父墙壁引用
					if debris.has_method("set_parent_wall"):
						debris.set_parent_wall(self)

func handle_explosion(explosion_position: Vector3, explosion_radius: float = 1.0, explosion_time: float = -1.0) -> void:
	if destroyed:
		return
	
	# 检查是否已经有碎片（防止重复生成）
	if debris_instances.size() > 0:
		print("Wall already destroyed, skipping debris generation")
		return
	
	# 记录破坏时间
	if explosion_time < 0:
		var time_sim = get_node_or_null("/root/TimeSimulator")
		explosion_time = time_sim.get_current_time() if time_sim else 0.0
	destruction_time = explosion_time
	
	# 检查爆炸点是否在墙壁范围内
	if !_is_explosion_in_range(explosion_position, explosion_radius):
		return
	
	# 执行射线检测破坏
	_destroy_with_raycast(explosion_position, explosion_radius)
	
	# 标记为已破坏
	destroyed = true
	wall_state = WallState.DESTROYED
	
	# 禁用碰撞
	if collision_shape:
		collision_shape.disabled = true
	
	# 隐藏原始网格
	if intact_mesh:
		intact_mesh.visible = false
	
	# 发射信号
	wall_destroyed.emit(self, explosion_position)
	
	# 更新导航
	_update_navigation()

func _destroy_with_raycast(explosion_position: Vector3, radius: float) -> void:
	var hit_points = _get_explosion_hit_points(explosion_position, radius)
	
	for hit_point in hit_points:
		_generate_debris_at_point(hit_point, explosion_position)

func _get_explosion_hit_points(explosion_position: Vector3, radius: float) -> Array[Vector3]:
	var hit_points: Array[Vector3] = []
	var bounds = _get_wall_bounds()
	var ray_count = 32
	var space_state = get_world_3d().direct_space_state
	
	for i in range(ray_count):
		var angle = (TAU / ray_count) * i
		var elevation = (PI / 2.0) * (randf() - 0.5)
		
		var direction = Vector3(
			cos(elevation) * cos(angle),
			sin(elevation),
			cos(elevation) * sin(angle)
		)
		
		var ray_end = explosion_position + direction * (radius * 2.0)
		var query = PhysicsRayQueryParameters3D.create(explosion_position, ray_end)
		query.exclude = [self]
		query.collision_mask = 1
		
		var result = space_state.intersect_ray(query)
		
		if result && result.collider == self:
			var hit_point = result.position
			if _is_point_in_bounds(hit_point, bounds):
				hit_points.append(hit_point)
	
	if hit_points.size() < 4:
		hit_points = _sample_wall_surface(explosion_position, radius)
	
	return hit_points

func _sample_wall_surface(explosion_position: Vector3, radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var bounds = _get_wall_bounds()
	var wall_center = (bounds.min + bounds.max) / 2.0
	var to_explosion = (explosion_position - wall_center).normalized()
	
	var abs_to = Vector3(abs(to_explosion.x), abs(to_explosion.y), abs(to_explosion.z))
	var main_axis = 0
	if abs_to.y > abs_to.x && abs_to.y > abs_to.z:
		main_axis = 1
	elif abs_to.z > abs_to.x:
		main_axis = 2
	
	var sample_count = debris_count
	for i in range(sample_count):
		var offset = Vector3.ZERO
		
		match main_axis:
			0:
				offset.x = sign(to_explosion.x) * (bounds.max.x - bounds.min.x) / 2.0
				offset.y = randf_range(bounds.min.y, bounds.max.y) - wall_center.y
				offset.z = randf_range(bounds.min.z, bounds.max.z) - wall_center.z
			1:
				offset.x = randf_range(bounds.min.x, bounds.max.x) - wall_center.x
				offset.y = sign(to_explosion.y) * (bounds.max.y - bounds.min.y) / 2.0
				offset.z = randf_range(bounds.min.z, bounds.max.z) - wall_center.z
			2:
				offset.x = randf_range(bounds.min.x, bounds.max.x) - wall_center.x
				offset.y = randf_range(bounds.min.y, bounds.max.y) - wall_center.y
				offset.z = sign(to_explosion.z) * (bounds.max.z - bounds.min.z) / 2.0
		
		var sample_point = wall_center + offset
		if sample_point.distance_to(explosion_position) <= radius * 1.5:
			points.append(sample_point)
	
	return points

func _generate_debris_at_point(hit_point: Vector3, explosion_position: Vector3) -> void:
	if !debris_scene:
		return
	
	# 检查是否已经存在碎片（防止重复生成）
	if debris_instances.size() >= debris_count:
		return
	
	var debris = debris_scene.instantiate() as RigidBody3D
	if !debris:
		return
	
	# 设置碎片位置
	debris.global_position = hit_point
	
	# 设置父墙壁引用
	if debris.has_method("set_parent_wall"):
		debris.set_parent_wall(self)
	
	# 添加到碎片容器（作为墙壁的子节点）
	debris_container.add_child(debris)
	
	# 追踪碎片
	debris_instances.append(debris)
	
	# 计算爆炸力
	var force_direction = (hit_point - explosion_position).normalized()
	var distance = hit_point.distance_to(explosion_position)
	var force_magnitude = explosion_force_multiplier / (distance + 0.1)
	
	# 应用爆炸力
	var force = force_direction * force_magnitude
	debris.apply_central_impulse(force)
	
	# 添加旋转力
	var torque = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * force_magnitude * 0.1
	debris.apply_torque_impulse(torque)

func _is_explosion_in_range(explosion_position: Vector3, radius: float) -> bool:
	if !collision_shape:
		return false
	
	var wall_bounds = _get_wall_bounds()
	var expanded_min = wall_bounds.min - Vector3(radius, radius, radius)
	var expanded_max = wall_bounds.max + Vector3(radius, radius, radius)
	
	return (
		explosion_position.x >= expanded_min.x && explosion_position.x <= expanded_max.x &&
		explosion_position.y >= expanded_min.y && explosion_position.y <= expanded_max.y &&
		explosion_position.z >= expanded_min.z && explosion_position.z <= expanded_max.z
	)

func _get_wall_bounds() -> Dictionary:
	if !collision_shape || !collision_shape.shape:
		return { "min": Vector3.ZERO, "max": Vector3.ZERO }
	
	var shape = collision_shape.shape as BoxShape3D
	if !shape:
		return { "min": Vector3.ZERO, "max": Vector3.ZERO }
	
	var size = shape.size
	var center = global_position
	var half_size = size / 2.0
	
	return {
		"min": center - half_size,
		"max": center + half_size
	}

func _is_point_in_bounds(point: Vector3, bounds: Dictionary) -> bool:
	return (
		point.x >= bounds.min.x && point.x <= bounds.max.x &&
		point.y >= bounds.min.y && point.y <= bounds.max.y &&
		point.z >= bounds.min.z && point.z <= bounds.max.z
	)

# ============================================
# 时间模拟器集成：快照系统
# ============================================

func capture_state() -> Dictionary:
	var state = {
		"destroyed": destroyed,
		"wall_state": wall_state,
		"destruction_time": destruction_time,
		"debris_count": debris_instances.size()
	}
	
	# 注意：碎片的状态由碎片自己保存（因为它们也在 snapshotable 组中）
	# 这里只保存墙壁的状态和碎片数量（用于验证）
	
	return state

func restore_state(state: Dictionary) -> void:
	# 恢复墙壁状态
	destroyed = state.get("destroyed", false)
	wall_state = state.get("wall_state", WallState.INTACT)
	destruction_time = state.get("destruction_time", -1.0)
	
	# 恢复墙壁外观
	if destroyed:
		if collision_shape:
			collision_shape.disabled = true
		if intact_mesh:
			intact_mesh.visible = false
	else:
		if collision_shape:
			collision_shape.disabled = false
		if intact_mesh:
			intact_mesh.visible = true
	
	# 注意：碎片的状态由时间模拟器自动恢复（因为它们也在 snapshotable 组中）
	# 我们只需要重新收集碎片引用
	call_deferred("_collect_existing_debris")
	
	# 更新导航
	_update_navigation()

func _update_navigation() -> void:
	var nav_region = get_tree().get_first_node_in_group("navigation_region")
	if nav_region && nav_region is NavigationRegion3D:
		call_deferred("_rebake_navigation", nav_region)

func _rebake_navigation(nav_region: NavigationRegion3D) -> void:
	if nav_region:
		nav_region.bake_navigation_mesh()

func is_destroyed() -> bool:
	return destroyed

func get_debris_count() -> int:
	return debris_instances.size()
