# =============================================================================
# aim_reticle.gd — AimReticle.
#
# Placeholder for the ADS reticle: a plain cross at screen centre, visible
# while PlayerState.is_aiming AND nothing better is already aiming.
#
# THE SECOND CONDITION IS THE POINT. MouseCursorUI turns into aim brackets
# the moment a firearm is drawn, so aiming a drawn weapon used to put TWO
# aiming marks on screen at once — brackets around the target and a cross at
# the centre, disagreeing whenever the two were not in the same place.
# Reported by Stan 2026-08-28 as "the aim sometimes doesn't work, a cursor
# shows up instead — inconsistent". One aim at a time: when the cursor is
# doing it, this stands down.
#
# Debug-grade on purpose — a marker to confirm ADS reads as "aiming" on
# screen, not the final aiming interface.
# =============================================================================
extends Control

const RETICLE_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const ARM_LENGTH: float = 6.0
const LINE_WIDTH: float = 1.5

var _cursor: MouseCursorUI = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	PlayerState.aiming_changed.connect(_on_aiming_changed)
	_refresh()


func _on_aiming_changed(_is_aiming: bool) -> void:
	_refresh()


## Asked every frame rather than only on the aiming edge: whether the cursor
## is drawing brackets changes with what is in the hands, which is not this
## widget's signal to watch.
func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var should_show: bool = PlayerState.is_aiming and not _cursor_is_aiming()
	if should_show == visible:
		return
	visible = should_show
	queue_redraw()


## MouseCursorUI is found by group rather than by path: it lives inside
## player.tscn and this widget is instanced into the UI canvas by world.gd,
## so neither can name the other.
func _cursor_is_aiming() -> bool:
	if not is_instance_valid(_cursor):
		_cursor = get_tree().get_first_node_in_group(
			MouseCursorUI.GROUP_MOUSE_CURSOR
		) as MouseCursorUI
	return is_instance_valid(_cursor) and _cursor.has_firearm


func _draw() -> void:
	var center := size * 0.5
	draw_line(
		center - Vector2(ARM_LENGTH, 0.0), center + Vector2(ARM_LENGTH, 0.0), RETICLE_COLOR, LINE_WIDTH
	)
	draw_line(
		center - Vector2(0.0, ARM_LENGTH), center + Vector2(0.0, ARM_LENGTH), RETICLE_COLOR, LINE_WIDTH
	)
