class_name PathIndicatorFX
extends Node3D

@export var line_width: float = 0.12
@export var y_lift: float = 0.03

var _surface_color: Color = Color.WHITE
var _path: PackedVector3Array = PackedVector3Array()
var _line: Line3D = null


func _ready() -> void:
	_line = Line3D.new()
	_line.name = "PathLine3D"
	_line.width = line_width
	_line.default_color = _surface_color
	_line.visible = false
	add_child(_line)


func set_surface_color(c: Color) -> void:
	_surface_color = c
	if _line != null:
		_line.default_color = _surface_color


func play_path(path: PackedVector3Array) -> void:
	_path = path
	_update_remaining(path)


func update_progress(current_position: Vector3, current_index: int) -> void:
	if _path.size() < 2 or _line == null:
		stop()
		return
	var idx := clampi(current_index, 0, _path.size() - 1)
	var pts := PackedVector3Array()
	pts.append(current_position)
	for i in range(idx, _path.size()):
		var p := _path[i]
		pts.append(p)
	_update_remaining(pts)


func stop() -> void:
	if _line == null:
		return
	_line.points = PackedVector3Array()
	_line.visible = false


func _update_remaining(path_like: PackedVector3Array) -> void:
	if _line == null:
		return
	if path_like.size() < 2:
		_line.points = PackedVector3Array()
		_line.visible = false
		return
	var lifted := PackedVector3Array()
	for p in path_like:
		lifted.append(Vector3(p.x, p.y + y_lift, p.z))
	_line.points = lifted
	_line.visible = true
