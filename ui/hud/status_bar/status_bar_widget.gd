# =============================================================================
# status_bar_widget.gd — StatusBarWidget.
#
# Top-left HUD gauge: one value drawn as THREE separate bars in a shared grey
# frame, draining right to left. No numbers on screen — the colour and how much
# is left are the whole readout.
#
# Built with _draw() rather than TextureProgressBar for the same reason
# aim_reticle.gd is: exact pixel control over the gap and the frame, and zero
# art assets. Reworking this into textures later touches only _draw().
#
# REUSE: this widget knows nothing about health. It takes a ratio and a list of
# labels. Hunger and rest are meant to be further instances of this same scene
# stacked underneath, with their own colours — that is why the thresholds and
# colours are exported instead of hard-coded.
#
# WHY THE COLOUR IS GLOBAL, NOT PER BAR: all three bars change colour together.
# A per-bar colour would read as "this bar is the yellow one" instead of "the
# body is failing", which is the opposite of what the three thirds mean.
#
# Dependencies: none. The owner feeds it through set_ratio()/set_labels().
# =============================================================================
class_name StatusBarWidget
extends Control

## Number of segments the gauge is split into. Three by design — the health
## bands (HealthComponent.Band) are thirds, and the segment boundaries have to
## sit exactly on the band boundaries or the colour change lands off-edge.
const SEGMENT_COUNT: int = 3

@export_group("Layout")
## Width of a single segment, in pixels.
@export var segment_width: float = 92.0
@export var segment_height: float = 13.0
## Gap between segments. A couple of pixels: enough to read as three bars,
## small enough to still read as one gauge.
@export var segment_gap: float = 4.0
## Distance from the frame to the segments inside it.
@export var frame_padding: float = 5.0
@export var frame_line_width: float = 1.0

@export_group("Colours")
@export var frame_color: Color = Color(0.45, 0.45, 0.45, 0.9)
## Empty part of a segment. Near-transparent rather than a solid backing —
## an empty bar should read as absence, not as a filled dark bar.
@export var empty_color: Color = Color(0.12, 0.12, 0.12, 0.35)
## Fill above the impaired threshold. Deliberately not the usual green.
@export var nominal_color: Color = Color(0.04, 0.04, 0.04, 0.95)
@export var impaired_color: Color = Color(0.85, 0.72, 0.15, 0.95)
@export var critical_color: Color = Color(0.68, 0.10, 0.08, 0.95)

@export_group("Thresholds")
## Ratio at or below which the fill turns impaired-coloured.
@export var impaired_ratio: float = 2.0 / 3.0
## Ratio at or below which the fill turns critical-coloured.
@export var critical_ratio: float = 1.0 / 3.0
## Below this the fill pulses. Terminal zone — the player must not be able to
## mistake it for "just low".
@export var terminal_ratio: float = 0.1

@export_group("Behaviour")
## Seconds the colour takes to cross a threshold. An instant repaint at the
## boundary reads as a glitch, especially when the value hovers on the edge.
@export var color_fade_time: float = 0.15
## Full pulse cycles per second in the terminal zone.
@export var pulse_speed: float = 2.0

@export_group("Labels")
## Cause lines under the bars (bleeding, fracture). Empty draws nothing and
## the widget's height shrinks accordingly.
@export var label_color: Color = Color(0.75, 0.13, 0.13, 0.95)
@export var label_font_size: int = 11
## Gap between the frame and the first cause line.
@export var label_top_margin: float = 4.0
@export var label_line_spacing: float = 2.0

var _ratio: float = 1.0
var _labels: PackedStringArray = PackedStringArray()

## Displayed fill colour. Tweened, so it lags _ratio's threshold crossings by
## color_fade_time — this is the value _draw() actually uses.
var _fill_color: Color = nominal_color
var _color_tween: Tween = null

## Set while the value is in the terminal zone; drives the pulse in _process.
var _is_pulsing: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_color = _target_color_for(_ratio)
	_is_pulsing = _ratio <= terminal_ratio
	set_process(_is_pulsing)
	_update_minimum_size()


func _process(_delta: float) -> void:
	# Only ever runs in the terminal zone — set_process() is toggled with the
	# pulse, so a healthy player costs nothing per frame.
	queue_redraw()

# ── Public API ───────────────────────────────────────────────────────────────

## Feeds the gauge. Takes a ratio, not current/maximum, so the widget stays
## reusable for values that have no notion of "hit points".
func set_ratio(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _ratio):
		return

	var previous_target: Color = _target_color_for(_ratio)
	_ratio = clamped

	var new_target: Color = _target_color_for(_ratio)
	if new_target != previous_target:
		_start_color_fade(new_target)

	var should_pulse: bool = _ratio <= terminal_ratio
	if should_pulse != _is_pulsing:
		_is_pulsing = should_pulse
		set_process(_is_pulsing)

	queue_redraw()


## Cause lines under the bars. Order is the caller's — HealthComponent returns
## them in a fixed order so the lines never jump around.
func set_labels(labels: PackedStringArray) -> void:
	_labels = labels
	_update_minimum_size()
	queue_redraw()

# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var bars_width: float = SEGMENT_COUNT * segment_width \
			+ (SEGMENT_COUNT - 1) * segment_gap
	var origin := Vector2(frame_padding + frame_line_width,
			frame_padding + frame_line_width)

	# Frame around all three segments, drawn once.
	var frame_rect := Rect2(
		Vector2(frame_line_width * 0.5, frame_line_width * 0.5),
		Vector2(
			bars_width + frame_padding * 2.0 + frame_line_width,
			segment_height + frame_padding * 2.0 + frame_line_width
		)
	)
	draw_rect(frame_rect, frame_color, false, frame_line_width)

	var fill_color: Color = _fill_color
	if _is_pulsing:
		# Alpha only: the hue stays critical, so the pulse cannot be mistaken
		# for another threshold crossing.
		var wave: float = 0.5 + 0.5 * sin(
			Time.get_ticks_msec() / 1000.0 * pulse_speed * TAU
		)
		fill_color.a *= lerpf(0.35, 1.0, wave)

	for i in SEGMENT_COUNT:
		var segment_origin := origin + Vector2(
			i * (segment_width + segment_gap), 0.0
		)
		draw_rect(
			Rect2(segment_origin, Vector2(segment_width, segment_height)),
			empty_color, true
		)

		# Right-to-left depletion: the leftmost segment is the last to empty,
		# so segment i covers the ratio band [i/3, (i+1)/3] and its own fill
		# grows from its LEFT edge.
		var segment_fill: float = clampf(
			_ratio * SEGMENT_COUNT - float(i), 0.0, 1.0
		)
		if segment_fill > 0.0:
			draw_rect(
				Rect2(segment_origin,
						Vector2(segment_width * segment_fill, segment_height)),
				fill_color, true
			)

	_draw_labels(frame_rect.size.y)


func _draw_labels(frame_height: float) -> void:
	if _labels.is_empty():
		return

	var font: Font = get_theme_default_font()
	if font == null:
		return

	var line_height: float = font.get_height(label_font_size)
	var y: float = frame_height + label_top_margin + line_height
	for label in _labels:
		draw_string(
			font, Vector2(frame_line_width, y), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size, label_color
		)
		y += line_height + label_line_spacing

# ── Internals ────────────────────────────────────────────────────────────────

func _target_color_for(ratio: float) -> Color:
	if ratio <= critical_ratio:
		return critical_color
	if ratio <= impaired_ratio:
		return impaired_color
	return nominal_color


func _start_color_fade(target: Color) -> void:
	if _color_tween != null and _color_tween.is_valid():
		_color_tween.kill()
	## tween_method rather than tween_property: _draw() only runs on
	## queue_redraw(), so a property tween would update the colour silently
	## and never reach the screen — the bar would keep the pre-threshold
	## colour until something else forced a redraw.
	_color_tween = create_tween()
	_color_tween.tween_method(_set_fill_color, _fill_color, target, color_fade_time)


func _set_fill_color(color: Color) -> void:
	_fill_color = color
	queue_redraw()


## Keeps the Control's own size honest so a VBoxContainer of these stacks
## without overlapping once hunger and rest are added.
func _update_minimum_size() -> void:
	var bars_width: float = SEGMENT_COUNT * segment_width \
			+ (SEGMENT_COUNT - 1) * segment_gap
	var width: float = bars_width + frame_padding * 2.0 + frame_line_width * 2.0
	var height: float = segment_height + frame_padding * 2.0 \
			+ frame_line_width * 2.0

	if not _labels.is_empty():
		var font: Font = get_theme_default_font()
		if font != null:
			var line_height: float = font.get_height(label_font_size)
			height += label_top_margin \
					+ _labels.size() * (line_height + label_line_spacing)

	custom_minimum_size = Vector2(width, height)
