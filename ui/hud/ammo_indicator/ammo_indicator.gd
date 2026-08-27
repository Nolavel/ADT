# =============================================================================
# ammo_indicator.gd — AmmoIndicator.
#
# The magazine, on the HUD, directly under the health row: how many rounds
# are in it, how many it holds, and how many are left behind it. Drawn as
# pips plus the numbers, because a magazine is a small discrete count and
# both readings are useful at different distances — the pips answer "am I
# nearly out" without being read, the numbers answer "how many exactly".
#
# The reserve is a number only, never pips: eighty pips is not a thing anyone
# reads, and the reserve is the figure you check between fights rather than
# during one.
#
# Not a StatusBarWidget instance, for the reason StanceIndicator already
# records for itself: that widget is a ratio gauge with thirds, a drain
# animation and threshold colours, all built for a continuous value like
# health. A ratio here would round 1-of-8 and 0-of-8 to nearly the same bar,
# and those are the two states that matter most.
#
# UNLIKE StanceIndicator this is NOT self-contained. Stance is on PlayerState,
# an autoload the widget can just read; the magazine is on WeaponComponent, a
# child of the player, so PlayerHUD resolves it and wires this in
# on_world_ready() — that node is the documented place where a component and
# a widget meet.
#
# Hidden whenever no magazine weapon is in the hands. Empty hands show
# nothing rather than a stale count from the last weapon held.
#
# Dependencies: none directly — PlayerHUD calls set_ammo()/clear().
# =============================================================================
class_name AmmoIndicator
extends Control

@export_group("Layout")
@export var badge_height: float = 27.0
@export var pip_width: float = 5.0
@export var pip_height: float = 14.0
@export var pip_spacing: float = 3.0
## Gap between the last pip and the "3 / 8" text.
@export var text_gap: float = 10.0

@export_group("Colours")
## A round still in the magazine.
@export var loaded_color: Color = Color(0.86, 0.78, 0.42, 0.95)
## A round already spent — drawn rather than omitted, so the row's width
## does not change as it empties and the eye has a total to compare against.
@export var spent_color: Color = Color(0.30, 0.30, 0.30, 0.75)
## The whole row once the magazine is empty. Reuses StatusBarWidget's own
## critical colour so "red" means the same thing everywhere in this HUD —
## the same reasoning StanceIndicator records for COMBAT.
@export var empty_color: Color = Color(0.68, 0.10, 0.08, 0.95)
@export var text_color: Color = Color(0.92, 0.92, 0.92, 0.95)
## The reserve figure, dimmer than the magazine's — it is the secondary
## reading, and giving both the same weight makes neither stand out.
@export var reserve_color: Color = Color(0.62, 0.62, 0.62, 0.9)
@export var font_size: int = 12

var _rounds: int = 0
var _capacity: int = 0
var _reserve: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_apply_minimum_size()


## Show a weapon's magazine. A capacity of zero is treated as "nothing to
## show" rather than an error: it is the same answer for a torch, for empty
## hands, and for a firearm that does not feed from a magazine.
func set_ammo(rounds: int, capacity: int, reserve: int) -> void:
	if capacity <= 0:
		clear()
		return
	_rounds = clampi(rounds, 0, capacity)
	_capacity = capacity
	_reserve = maxi(reserve, 0)
	_apply_minimum_size()
	visible = true
	queue_redraw()


func clear() -> void:
	_rounds = 0
	_capacity = 0
	_reserve = 0
	visible = false
	queue_redraw()


## Width follows the capacity — an eight-round magazine and a thirty-round
## one are not the same size on screen, and a VBoxContainer needs to be told
## so rather than discovering it in _draw().
func _apply_minimum_size() -> void:
	var pips_width: float = 0.0
	if _capacity > 0:
		pips_width = _capacity * pip_width + maxf(_capacity - 1, 0) * pip_spacing
	var text_width: float = 0.0
	var font: Font = get_theme_default_font()
	if font != null:
		text_width = font.get_string_size(
			_label_text() + _reserve_text(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
		).x
	custom_minimum_size = Vector2(pips_width + text_gap + text_width, badge_height)


func _label_text() -> String:
	return "%d / %d" % [_rounds, _capacity]


## Empty string for a weapon with no reserve at all — the separator would
## otherwise dangle after the magazine and read as a missing number.
func _reserve_text() -> String:
	if _reserve <= 0 and _capacity > 0 and _rounds >= _capacity:
		## Full magazine, nothing behind it: worth saying, since that is the
		## last magazine in the game for this weapon.
		return "  ·  0"
	if _reserve <= 0:
		return ""
	return "  ·  %d" % _reserve


func _draw() -> void:
	if _capacity <= 0:
		return

	var is_empty := _rounds <= 0
	var top := (badge_height - pip_height) * 0.5
	var x := 0.0
	for i in _capacity:
		var filled := i < _rounds
		var fill := loaded_color if filled else spent_color
		if is_empty:
			## Every pip red, not just an absence of yellow ones: an empty
			## magazine is a state to notice, and "nothing lit" reads the
			## same as the widget having failed to update.
			fill = empty_color
		draw_rect(Rect2(Vector2(x, top), Vector2(pip_width, pip_height)), fill, true)
		x += pip_width + pip_spacing

	var font: Font = get_theme_default_font()
	if font == null:
		return
	var baseline := (badge_height + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var text_x := x - pip_spacing + text_gap
	var magazine_text := _label_text()
	draw_string(
		font,
		Vector2(text_x, baseline),
		magazine_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		empty_color if is_empty else text_color
	)

	var reserve_text := _reserve_text()
	if reserve_text == "":
		return
	## Drawn as a second string rather than one concatenated label so the two
	## numbers can carry different colours — the reserve is the quieter of
	## the two until it reaches zero, and then it is the loudest thing here.
	text_x += font.get_string_size(
		magazine_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	).x
	draw_string(
		font,
		Vector2(text_x, baseline),
		reserve_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		empty_color if _reserve <= 0 else reserve_color
	)
