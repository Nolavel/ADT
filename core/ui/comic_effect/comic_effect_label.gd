# =============================================================================
# comic_effect_label.gd — pooled screen-space word owned by ComicEffectSystem.
#
# Position is recomputed every frame from a world point (or a followed
# Node3D) via Camera3D.unproject_position. That is what makes the word orbit
# on screen when the player turns the camera — the world source stays fixed,
# the projection moves. Behind-camera sources die early rather than stick to
# the edge of the screen.
#
# Finished labels return to the pool; they are never freed mid-session.
# =============================================================================
class_name ComicEffectLabel
extends Label

signal finished(label: ComicEffectLabel)

var _world_pos: Vector3 = Vector3.ZERO
var _follow: Node3D = null
var _offset: Vector3 = Vector3(0.0, 1.6, 0.0)
var _lifetime: float = 0.0
var _duration: float = 0.9
var _rise_px: float = 32.0
var _alive: bool = false


func setup(
		text: String,
		color: Color,
		font_size: int,
		duration: float,
		rise_px: float
	) -> void:
	self.text = text
	modulate = color
	add_theme_font_size_override("font_size", font_size)
	_duration = maxf(duration, 0.05)
	_rise_px = rise_px
	_lifetime = 0.0
	_alive = true
	visible = true
	# size is reliable after the first layout; pivot centres the word on the
	# unprojected point so it doesn't sit offset to the bottom-right.
	await get_tree().process_frame
	if is_instance_valid(self):
		pivot_offset = size * 0.5


func set_world_source(pos: Vector3, offset: Vector3 = Vector3(0.0, 1.6, 0.0)) -> void:
	_world_pos = pos
	_offset = offset
	_follow = null


func set_follow(node: Node3D, offset: Vector3 = Vector3(0.0, 1.6, 0.0)) -> void:
	_follow = node
	_offset = offset
	if is_instance_valid(node):
		_world_pos = node.global_position


func is_alive() -> bool:
	return _alive


func tick(delta: float, camera: Camera3D) -> void:
	if not _alive or camera == null:
		return

	if is_instance_valid(_follow):
		_world_pos = _follow.global_position
	elif _follow != null:
		# follow was freed (stream unload, queue_free) — end cleanly
		_kill()
		return

	var world: Vector3 = _world_pos + _offset
	if camera.is_position_behind(world):
		_kill()
		return

	var screen: Vector2 = camera.unproject_position(world)
	_lifetime += delta
	var t: float = clampf(_lifetime / _duration, 0.0, 1.0)
	# ease-out rise
	var rise: float = _rise_px * (1.0 - (1.0 - t) * (1.0 - t))
	position = screen - size * 0.5 + Vector2(0.0, -rise)
	modulate.a = 1.0 - t
	if t >= 1.0:
		_kill()


func _kill() -> void:
	if not _alive:
		return
	_alive = false
	visible = false
	_follow = null
	finished.emit(self)
