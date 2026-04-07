# ~/UI/Path/line_3d.gd
class_name Line3D
extends MeshInstance3D

var _points: PackedVector3Array = PackedVector3Array()
var width: float = 0.1
var default_color: Color = Color.WHITE

func _ready() -> void:
	_update_mesh()

func set_points(new_points: PackedVector3Array) -> void:
	_points = new_points
	_update_mesh()

func get_points() -> PackedVector3Array:
	return _points

var points: PackedVector3Array:
	get:
		return _points
	set(value):
		_points = value
		_update_mesh()

func _update_mesh() -> void:
	if _points.size() < 2:
		mesh = null
		return
	
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for i in range(_points.size() - 1):
		var p1 = _points[i]
		var p2 = _points[i + 1]
		var direction = (p2 - p1).normalized()
		
		if direction.length() < 0.001:
			direction = Vector3.FORWARD
		
		var right = Vector3.UP.cross(direction).normalized()
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right * width
		
		var v1 = p1 - right
		var v2 = p1 + right
		var v3 = p2 + right
		var v4 = p2 - right
		
		surface_tool.add_vertex(v1)
		surface_tool.add_vertex(v2)
		surface_tool.add_vertex(v3)
		
		surface_tool.add_vertex(v1)
		surface_tool.add_vertex(v3)
		surface_tool.add_vertex(v4)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = default_color
	surface_tool.set_material(material)
	
	mesh = surface_tool.commit()
