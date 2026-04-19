# res://Gameplay/Input/camera_screen_ray.gd
## Viewport 鼠标 → 相机世界射线 → 与水平面相交（与 NAD-LAB `threedobjectfollowmouse` 同款思路）。
## 参考: https://github.com/aimforbigfoot/NAD-LAB-Godot-Projects-4.0/tree/main/threedobjectfollowmouse
class_name CameraScreenRay


## 将坐标限制在相机所属 Viewport 的 `get_visible_rect()` 内；**不**再减去 `rect.position`（与 `get_viewport().get_mouse_position()` 同一坐标系，避免整屏偏移）。
static func viewport_pixel_for_pick(camera: Camera3D, screen_px: Vector2) -> Vector2:
	var vp := camera.get_viewport()
	if vp == null:
		return screen_px
	var rect := vp.get_visible_rect()
	var x1 := rect.position.x
	var y1 := rect.position.y
	var x2 := rect.position.x + maxf(rect.size.x - 0.001, 0.0)
	var y2 := rect.position.y + maxf(rect.size.y - 0.001, 0.0)
	return Vector2(clampf(screen_px.x, x1, maxf(x2, x1)), clampf(screen_px.y, y1, maxf(y2, y1)))


## 引擎标准世界射线：原点在 `project_ray_origin`（透视下即相机世界位置 + 投影），方向 `project_ray_normal`。
static func world_ray_for_pick(camera: Camera3D, screen_px: Vector2) -> Dictionary:
	var pt := viewport_pixel_for_pick(camera, screen_px)
	var from := camera.project_ray_origin(pt)
	var dir := camera.project_ray_normal(pt)
	if dir.length_squared() < 1e-28:
		return {"origin": from, "dir": Vector3(0, 0, -1)}
	return {"origin": from, "dir": dir.normalized()}


## `Plane(Vector3.UP, plane_y).intersects_ray(...)`，等价于 y = plane_y 的解析求交；与示例中 `Plane(Vector3.UP)` 仅差在可设楼层高度。
static func intersect_horizontal_plane(camera: Camera3D, screen_px: Vector2, plane_y: float) -> Dictionary:
	var ray := world_ray_for_pick(camera, screen_px)
	var from: Vector3 = ray["origin"]
	var dir: Vector3 = ray["dir"]
	var pl := Plane(Vector3.UP, plane_y)
	var isect: Variant = pl.intersects_ray(from, dir)
	if isect is Vector3:
		return {"position": isect as Vector3}
	return {}
