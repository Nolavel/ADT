# =============================================================================
# aim_reticle.gd — AimReticle.
#
# Placeholder for the ADS reticle: a plain cross at screen centre, visible
# only while PlayerState.is_aiming. Debug-grade on purpose — a marker to
# confirm ADS reads as "aiming" on screen, not the final aiming interface.
# =============================================================================
extends Control

const RETICLE_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const ARM_LENGTH: float = 6.0
const LINE_WIDTH: float = 1.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = PlayerState.is_aiming
	PlayerState.aiming_changed.connect(_on_aiming_changed)


func _on_aiming_changed(is_aiming: bool) -> void:
	visible = is_aiming
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_line(
		center - Vector2(ARM_LENGTH, 0.0), center + Vector2(ARM_LENGTH, 0.0), RETICLE_COLOR, LINE_WIDTH
	)
	draw_line(
		center - Vector2(0.0, ARM_LENGTH), center + Vector2(0.0, ARM_LENGTH), RETICLE_COLOR, LINE_WIDTH
	)
