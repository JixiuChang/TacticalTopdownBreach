# ~/Scenes/level_house_01.gd
extends Node3D

@export var tactical_unit_scene: PackedScene = null
@export var destructible_wall_scene: PackedScene = null

var player_spawns: Array[Marker3D] = []
var enemy_spawns: Array[Marker3D] = []
var objective_location: Marker3D = null

func _ready() -> void:
	await get_tree().process_frame
	
	_collect_spawn_points()
	
	_spawn_player_units()
	
	if GameStateManager.get_phase() == GameStateManager.GamePhase.BRIEFING:
		pass

func _collect_spawn_points() -> void:
	var spawns_node = get_node_or_null("Spawns/PlayerSpawns")
	if spawns_node:
		for child in spawns_node.get_children():
			if child is Marker3D:
				player_spawns.append(child)
	
	var enemy_spawns_node = get_node_or_null("Spawns/EnemySpawns")
	if enemy_spawns_node:
		for child in enemy_spawns_node.get_children():
			if child is Marker3D:
				enemy_spawns.append(child)
	
	var objective_node = get_node_or_null("Objective")
	if objective_node:
		objective_location = objective_node.get_node_or_null("ObjectiveLocation")

func _spawn_player_units() -> void:
	if !tactical_unit_scene:
		return
	
	var units_node = get_node_or_null("Units")
	if !units_node:
		units_node = Node3D.new()
		units_node.name = "Units"
		add_child(units_node)
	
	if units_node.get_child_count() == 0:
		for i in range(min(4, player_spawns.size())):
			var unit = tactical_unit_scene.instantiate()
			unit.global_position = player_spawns[i].global_position
			unit.unit_id = i
			unit.unit_name = "Unit " + str(i + 1)
			units_node.add_child(unit)

func get_player_spawns() -> Array[Marker3D]:
	return player_spawns

func get_enemy_spawns() -> Array[Marker3D]:
	return enemy_spawns

func get_objective_location() -> Marker3D:
	return objective_location
