# =============================================================================
# isometric_camera_debug_overlay.gd
#
# Debug overlay for IsometricCameraState. Draws the three zones, the follow
# point and the character, so the constants in IsometricCameraState can be
# tuned by watching rather than by guessing.
#
# Responsibilities
# - Draws dead / soft / hard zone rectangles around the follow point
# - Draws the follow point, the character and the error between them
#
# Architecture
# Camera / Debug
#
# Dependencies
# - IsometricCameraState
#
# Used By
# - OnFootCameraComponent
#
# Notes
# A debug tool, and one that may be deleted once the constants are settled.
# (This line used to draw the contrast against tools/checker_indicators;
# those were two orphan scripts with no scene and no instance anywhere, and
# they were deleted on 2026-08-27.)
#
# Add as a child of a CanvasLayer and give it full-rect anchors. Toggle
# through visible; when hidden it does no work at all.
#
# The overlay is fed by the host rather than reading the state itself, so
# it draws the numbers the state actually used this frame instead of
# recomputing them and possibly disagreeing.
# =============================================================================

extends Control
class_name IsometricCameraDebugOverlay


const COLOR_DEAD := Color(0.2, 0.9, 0.4, 0.9)
const COLOR_SOFT := Color(0.95, 0.75, 0.2, 0.7)
const COLOR_HARD := Color(0.95, 0.25, 0.25, 0.8)
const COLOR_HARD_ACTIVE := Color(1.0, 0.1, 0.1, 1.0)
const COLOR_ERROR := Color(0.4, 0.8, 1.0, 0.9)
const COLOR_TEXT := Color(1.0, 1.0, 1.0, 0.9)

const MARKER_RADIUS: float = 5.0
const LINE_WIDTH: float = 1.5


## Screen position of the follow point — the centre every zone is drawn
## around. Assigned by the host each frame.
var follow_screen: Vector2 = Vector2.ZERO

## Screen position of the character.
var target_screen: Vector2 = Vector2.ZERO

## Half-extents of each zone in pixels, straight from the state.
var zone_px: Vector2 = Vector2.ZERO
var soft_px: Vector2 = Vector2.ZERO
var hard_px: Vector2 = Vector2.ZERO

## True while the state is using the settling follow rate rather than the
## moving one.
var settling: bool = false

## True on any frame the hard limit had to take over from damping.
var hard_clamped: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Called by the host once per frame with the values the state just used.
## Requests a redraw only while visible, so a hidden overlay costs nothing.
func push(p_follow_screen: Vector2, p_target_screen: Vector2, state: IsometricCameraState) -> void:
	if not visible:
		return

	follow_screen = p_follow_screen
	target_screen = p_target_screen
	zone_px = state.debug_zone_px
	soft_px = state.debug_soft_px
	hard_px = state.debug_hard_px
	settling = state.debug_settling
	hard_clamped = state.debug_hard_clamped

	queue_redraw()


func _draw() -> void:
	_draw_zone(hard_px, COLOR_HARD_ACTIVE if hard_clamped else COLOR_HARD)
	_draw_zone(soft_px, COLOR_SOFT)
	_draw_zone(zone_px, COLOR_DEAD)

	# Error between where the camera is looking and where the character is.
	# While this line has length and the character is still inside the green
	# rectangle, the dead zone is doing its job.
	draw_line(follow_screen, target_screen, COLOR_ERROR, LINE_WIDTH)

	draw_circle(follow_screen, MARKER_RADIUS, COLOR_DEAD)
	draw_circle(target_screen, MARKER_RADIUS, COLOR_ERROR)

	var error := target_screen - follow_screen
	var label := "err %d,%d px   %s%s" % [
		int(error.x),
		int(error.y),
		"settling" if settling else "moving",
		"   HARD" if hard_clamped else ""
	]
	draw_string(
		ThemeDB.fallback_font,
		follow_screen + Vector2(hard_px.x + 12.0, -hard_px.y),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		COLOR_TEXT
	)


## Draws one axis-aligned rectangle centred on the follow point.
func _draw_zone(half_extents: Vector2, color: Color) -> void:
	if half_extents == Vector2.ZERO:
		return

	var rect := Rect2(follow_screen - half_extents, half_extents * 2.0)
	draw_rect(rect, color, false, LINE_WIDTH)
