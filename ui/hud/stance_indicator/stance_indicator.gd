# =============================================================================
# stance_indicator.gd — StanceIndicator.
#
# Small HUD badge next to the health bar showing PlayerState.stance
# (PEACE/COMBAT) at a glance — without it an outside viewer has no way to
# tell why a punch does or doesn't land.
#
# Not a StatusBarWidget instance: that widget is a ratio gauge (thirds,
# drain animation, threshold colours) built for a continuous value like
# health. Stance is a two-state switch with no ratio to show, so reusing it
# would mean feeding it a fake 0.0/1.0 ratio just to borrow its frame — more
# indirection than a short _draw() costs here. Colour alone would make a
# newcomer learn the game's colour language before it means anything, so
# this carries both colour and a text label, same as this HUD's condition
# labels (FRACTURE, etc.) already do.
#
# Self-contained like KeyHintsPanel: reads PlayerState directly in _ready()
# rather than waiting on on_world_ready(context) — PlayerState is an
# autoload, so there is nothing a WorldContext would hand over that this
# doesn't already have.
#
# Dependencies: PlayerState (stance_changed).
# =============================================================================
class_name StanceIndicator
extends Control

@export_group("Layout")
@export var badge_width: float = 84.0
@export var badge_height: float = 27.0
@export var frame_line_width: float = 2.0

@export_group("Colours")
@export var frame_color: Color = Color(0.45, 0.45, 0.45, 0.9)
## Deliberately not green/red-as-traffic-light — PEACE is a cool, calm fill,
## COMBAT reuses StatusBarWidget's own critical_color so "red" reads the
## same danger meaning everywhere in this HUD.
@export var peace_color: Color = Color(0.16, 0.30, 0.36, 0.95)
@export var combat_color: Color = Color(0.68, 0.10, 0.08, 0.95)
@export var text_color: Color = Color(0.92, 0.92, 0.92, 0.95)
@export var font_size: int = 12

var _stance: PlayerState.Stance = PlayerState.Stance.PEACE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(badge_width, badge_height)
	_stance = PlayerState.stance
	PlayerState.stance_changed.connect(_on_stance_changed)


func _on_stance_changed(_old_stance: PlayerState.Stance, new_stance: PlayerState.Stance) -> void:
	_stance = new_stance
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(
		Vector2(frame_line_width * 0.5, frame_line_width * 0.5),
		Vector2(badge_width - frame_line_width, badge_height - frame_line_width)
	)
	var fill := combat_color if _stance == PlayerState.Stance.COMBAT else peace_color
	draw_rect(rect, fill, true)
	draw_rect(rect, frame_color, false, frame_line_width)

	var label := "COMBAT" if _stance == PlayerState.Stance.COMBAT else "PEACE"
	var font: Font = get_theme_default_font()
	if font == null:
		return

	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var pos := Vector2(
		(badge_width - text_size.x) * 0.5,
		(badge_height + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
