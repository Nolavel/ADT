extends Node
class_name TPSAimComponent

# Возвращает точку в мире, куда смотрит центр камеры.
func get_aim_target(max_range: float, exclude_rids: Array[RID] = []) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO # Фоллбэк, если камеры нет

	# Берем центр экрана
	var viewport_size = get_viewport().get_visible_rect().size
	var screen_center = viewport_size / 2.0

	var from = camera.project_ray_origin(screen_center)
	var to = from + camera.project_ray_normal(screen_center) * max_range

	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude_rids
	
	# Здесь можно настроить collision_mask, чтобы луч игнорировал прозрачные триггеры
	# query.collision_mask = ... 

	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position
	return to
