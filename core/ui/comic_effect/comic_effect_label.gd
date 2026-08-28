# =============================================================================
# comic_effect_label.gd — pooled screen-space comic PANEL owned by
# ComicEffectSystem.
#
# Position is recomputed every frame from a world point (or a followed
# Node3D) via Camera3D.unproject_position. That is what makes the word orbit
# on screen when the player turns the camera — the world source stays fixed,
# the projection moves. Behind-camera sources die early rather than stick to
# the edge of the screen.
#
# WHY THIS IS A Control AND NOT A Label. The word used to be a Label with an
# outline override, which meant the only thing that could ever be authored
# was the type itself. Everything the comic frame is made of — the plate the
# word sits on, the print grid, the uneven inked edge — lives outside the
# glyphs, so the node draws itself: background, grid, border, outline, text,
# in that order. See docs/visual_language.md for what that frame is for.
#
# OUTLINE IS DRAWN BEFORE THE TEXT. Reversing those two hides the letters
# inside their own outline. It is an easy mistake to make and a slow one to
# see, because at small outline sizes it merely looks "muddy".
#
# THE PANEL IS DRAWN ONCE. Colours, corner jitter and geometry are all fixed
# at setup(), so _draw() runs on the first frame and then never again: the
# animation is transform and modulate, which the CanvasItem applies without
# redrawing. Sampling jitter inside _draw() would make a hanging panel
# quietly change shape whenever anything forced a redraw.
#
# Finished panels return to the pool; they are never freed mid-session.
# =============================================================================
class_name ComicEffectLabel
extends Control

signal finished(label: ComicEffectLabel)

## Scale the panel pops in from. Below ~0.5 the pop reads as a zoom rather
## than an impact.
const POP_FROM_SCALE: float = 0.55
## The pop is followed by a settle of the same length, so pop_time can never
## be allowed past a quarter of the life or the panel would still be
## overshooting when the fade starts.
const MAX_POP_FRACTION: float = 0.25

## One tiny texture per grid step, tiled across every panel that uses that
## step. Static because the steps come from a handful of profiles, not from
## the number of live panels: eight panels at 200x60 with a 5 px grid would
## otherwise be ~3800 draw_rect calls a frame.
static var _pattern_cache: Dictionary = {}

var _world_pos: Vector3 = Vector3.ZERO
var _follow: Node3D = null
var _offset: Vector3 = Vector3(0.0, 1.6, 0.0)
var _lifetime: float = 0.0
var _alive: bool = false
## False until the first layout pass has run and the panel has a size — see
## setup(). tick() does nothing before then, so a panel is never shown at the
## wrong size for a frame.
var _measured: bool = false

var _text: String = ""
var _profile: ComicVisualProfile = null
var _font: Font = null
var _font_size: int = 26

var _duration: float = 1.2
var _pop_time: float = 0.09
var _hold_ratio: float = 0.5
var _rise_px: float = 30.0
var _pop_overshoot: float = 1.1

## Corner displacement in the range [-1, 1] per axis, sampled once per spawn
## and multiplied by the profile's corner_jitter at draw time.
var _corner_offsets: PackedVector2Array = PackedVector2Array()
## Horizontal lean of the top edge, AGGRESSIVE only.
var _skew: float = 0.0
var _shape: PackedVector2Array = PackedVector2Array()
var _soft_box: StyleBoxFlat = null


## font_size arrives already resolved. ComicEffectDef.get_font_size() is the
## single place it is computed — recomputing emphasis here is how the panel
## and the text end up sized from two different numbers.
func setup(text: String, profile: ComicVisualProfile, font_size: int) -> void:
	_text = text
	_profile = profile
	_font_size = maxi(font_size, 1)
	_duration = maxf(profile.duration, 0.05)
	_pop_time = clampf(profile.pop_time, 0.01, _duration * MAX_POP_FRACTION)
	_hold_ratio = clampf(profile.hold_ratio, 0.0, 0.95)
	_rise_px = profile.rise_px
	_pop_overshoot = maxf(profile.pop_overshoot, 1.0)
	_lifetime = 0.0
	_alive = true
	_measured = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	scale = Vector2(POP_FROM_SCALE, POP_FROM_SCALE)
	# Grid tiling needs repeat on; Control inherits "disabled" by default.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	_corner_offsets = PackedVector2Array([
		Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
		Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
		Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
		Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
	])
	_skew = randf_range(-1.0, 1.0) * profile.corner_jitter

	# Stays hidden through the wait: the pool is attached with call_deferred,
	# and the theme font only resolves once the node is actually in the tree,
	# so measuring any earlier would size the panel from the fallback font.
	visible = false
	await get_tree().process_frame
	if not is_instance_valid(self) or not _alive:
		return
	_measure()
	_measured = true
	visible = true


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
	if not _alive or not _measured or camera == null:
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

	# ease-out rise, unchanged from the Label era — the panel drifts up and
	# decelerates, it does not float away.
	var rise: float = _rise_px * (1.0 - (1.0 - t) * (1.0 - t))
	position = screen - size * 0.5 + Vector2(0.0, -rise)
	scale = Vector2.ONE * _scale_at(_lifetime)
	modulate.a = _alpha_at(_lifetime, t)

	if t >= 1.0:
		_kill()


## pop (overshoot) -> settle (back to 1.0) -> steady.
func _scale_at(life: float) -> float:
	if life < _pop_time:
		var p: float = life / _pop_time
		# ease-out so the arrival is fast and the stop is soft
		return lerpf(POP_FROM_SCALE, _pop_overshoot, 1.0 - (1.0 - p) * (1.0 - p))
	if life < _pop_time * 2.0:
		return lerpf(_pop_overshoot, 1.0, (life - _pop_time) / _pop_time)
	return 1.0


## Rises over the pop, holds flat for hold_ratio of the life, then falls.
## Deliberately not the old monotonic 1.0 - t: a word that starts fading the
## instant it appears is never at full contrast while it is being read.
func _alpha_at(life: float, t: float) -> float:
	if life < _pop_time:
		return clampf(life / _pop_time, 0.0, 1.0)
	if t <= _hold_ratio:
		return 1.0
	return clampf(1.0 - (t - _hold_ratio) / maxf(1.0 - _hold_ratio, 0.001), 0.0, 1.0)


func _measure() -> void:
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	var text_size: Vector2 = _font.get_string_size(
		_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size
	)
	var pad: Vector2 = _profile.padding
	size = Vector2(
		ceilf(text_size.x + pad.x * 2.0),
		ceilf(maxf(text_size.y, float(_font_size)) + pad.y * 2.0)
	)
	pivot_offset = size * 0.5
	_build_shape()
	queue_redraw()


func _build_shape() -> void:
	var j: float = _profile.corner_jitter
	var pts := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(size.x, 0.0),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y),
	])
	for i in 4:
		pts[i] += _corner_offsets[i] * j
	if _profile.border_style == ComicVisualProfile.BorderStyle.AGGRESSIVE:
		# top edge leans; the panel reads as struck rather than placed
		pts[0].x += _skew
		pts[1].x += _skew
	_shape = pts

	_soft_box = null
	if _profile.border_style == ComicVisualProfile.BorderStyle.SOFT:
		var box := StyleBoxFlat.new()
		box.bg_color = _profile.background_color
		box.border_color = _profile.border_color
		var w: int = maxi(1, roundi(_profile.border_thickness))
		box.set_border_width_all(w)
		box.set_corner_radius_all(maxi(3, roundi(size.y * 0.28)))
		_soft_box = box


func _draw() -> void:
	if _profile == null or _shape.size() != 4:
		return

	var rect := Rect2(Vector2.ZERO, size)
	if _soft_box != null:
		draw_style_box(_soft_box, rect)
	else:
		draw_colored_polygon(_shape, _profile.background_color)

	_draw_pattern(rect)

	if _soft_box == null:
		var outline := _shape.duplicate()
		outline.append(_shape[0])
		draw_polyline(
			outline, _profile.border_color, _profile.border_thickness, true
		)

	# outline first, then the glyphs on top of it
	var pad: Vector2 = _profile.padding
	var baseline := Vector2(0.0, pad.y + _font.get_ascent(_font_size))
	if _profile.outline_size > 0:
		draw_string_outline(
			_font,
			baseline,
			_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x,
			_font_size,
			_profile.outline_size,
			_profile.outline_color
		)
	draw_string(
		_font,
		baseline,
		_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		_font_size,
		_profile.primary_color
	)


## One tiled draw, not a grid of draw_rect calls. Strength is entirely
## pattern_color.a — there is no second opacity factor anywhere, so what the
## inspector shows is what lands on screen.
func _draw_pattern(rect: Rect2) -> void:
	if _profile.pattern_color.a <= 0.0:
		return
	var tex: Texture2D = _get_pattern_texture(_profile.pattern_step)
	if tex == null:
		return
	var inset: float = _profile.border_thickness + _profile.corner_jitter
	var inner: Rect2 = rect.grow(-inset)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	draw_texture_rect(tex, inner, true, _profile.pattern_color)


static func _get_pattern_texture(step: float) -> Texture2D:
	var s: int = clampi(roundi(step), 2, 32)
	if _pattern_cache.has(s):
		return _pattern_cache[s]
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	# single lit texel per cell — modulated to pattern_color when drawn
	img.set_pixel(0, 0, Color(1.0, 1.0, 1.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_pattern_cache[s] = tex
	return tex


func _kill() -> void:
	if not _alive:
		return
	_alive = false
	_measured = false
	visible = false
	_follow = null
	finished.emit(self)
