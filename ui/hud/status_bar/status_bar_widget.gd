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
@export var frame_line_width: float = 2.0

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

@export_group("Juice")
@export var ghost_duration_damage: float = 0.38
@export var ghost_duration_heal: float = 0.28
@export var crt_burst_strength: float = 1.0
@export var damage_flash_duration: float = 0.16
@export var heal_flash_duration: float = 0.22
@export var segment_nudge: float = 1.2

@export_group("ECG")
@export var ecg_enabled: bool = true
## Seconds for the damage irregularity to die out.
@export var ecg_spike_duration: float = 0.45
## Base scroll speed (cycles-ish per second).
@export var ecg_scroll_speed: float = 0.6
## Vertical scale relative to segment_height.
@export var ecg_amplitude: float = 0.42

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

## ── Juice (Hybrid) ──────────────────────────────────────────────────────────
var _ghost_from: float = 1.0
var _ghost_t: float = 0.0
var _ghost_is_damage: bool = true

var _damage_flash: float = 0.0
var _heal_flash: float = 0.0
var _crt_burst: float = 0.0

var _segment_offsets: Array[float] = [0.0, 0.0, 0.0]

## ── ECG ─────────────────────────────────────────────────────────────────────
var _ecg_phase: float = 0.0
var _ecg_spike: float = 0.0
## Master switch; can later be driven by settings or band.
var _ecg_enabled: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_color = _target_color_for(_ratio)
	_is_pulsing = _ratio <= terminal_ratio
	_ecg_enabled = ecg_enabled
	set_process(_is_pulsing or _ecg_enabled)
	_update_minimum_size()


func _process(delta: float) -> void:
	var need_redraw: bool = _is_pulsing or _ecg_enabled

	if _ghost_t > 0.0:
		var dur: float = ghost_duration_damage if _ghost_is_damage else ghost_duration_heal
		_ghost_t = maxf(0.0, _ghost_t - delta / dur)
		need_redraw = true

	if _damage_flash > 0.0:
		_damage_flash = maxf(0.0, _damage_flash - delta / damage_flash_duration)
		need_redraw = true
	if _heal_flash > 0.0:
		_heal_flash = maxf(0.0, _heal_flash - delta / heal_flash_duration)
		need_redraw = true
	if _crt_burst > 0.0:
		_crt_burst = maxf(0.0, _crt_burst - delta / 0.28)
		need_redraw = true
	if _ecg_spike > 0.0:
		_ecg_spike = maxf(0.0, _ecg_spike - delta / ecg_spike_duration)
		need_redraw = true

	for i in SEGMENT_COUNT:
		if _segment_offsets[i] > 0.0:
			_segment_offsets[i] = maxf(0.0, _segment_offsets[i] - delta * 3.4)
			need_redraw = true

	if _ecg_enabled:
		_ecg_phase += delta
		need_redraw = true

	if need_redraw:
		queue_redraw()

	# ECG keeps process alive at all times while enabled (constant per-frame
	# cost — see docs note this widget used to be zero-cost when healthy).
	if not _is_pulsing and _ghost_t <= 0.0 and _damage_flash <= 0.0 \
			and _heal_flash <= 0.0 and _crt_burst <= 0.0 and _ecg_spike <= 0.0 \
			and not _ecg_enabled:
		var any_offset := false
		for o in _segment_offsets:
			if o > 0.0:
				any_offset = true
				break
		if not any_offset:
			set_process(false)

# ── Public API ───────────────────────────────────────────────────────────────

## Feeds the gauge. Takes a ratio, not current/maximum, so the widget stays
## reusable for values that have no notion of "hit points".
func set_ratio(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _ratio):
		return

	var previous: float = _ratio
	var delta: float = clamped - previous

	# Juice: exact delta that is about to change.
	if absf(delta) > 0.001:
		_ghost_from = previous
		_ghost_t = 1.0
		_ghost_is_damage = delta < 0.0
		if _ghost_is_damage:
			_damage_flash = 1.0
			_crt_burst = crt_burst_strength
			_ecg_spike = 1.0
			_segment_offsets = [0.55, 0.85, 1.15]
		else:
			_heal_flash = 1.0
			_segment_offsets = [0.35, 0.5, 0.65]
		set_process(true)

	_ratio = clamped

	var previous_target: Color = _target_color_for(previous)
	var new_target: Color = _target_color_for(_ratio)
	if new_target != previous_target:
		_start_color_fade(new_target)

	var should_pulse: bool = _ratio <= terminal_ratio
	if should_pulse != _is_pulsing:
		_is_pulsing = should_pulse

	# Keep process alive while any juice/ECG animation runs.
	if _is_pulsing or _ghost_t > 0.0 or _damage_flash > 0.0 \
			or _heal_flash > 0.0 or _ecg_spike > 0.0 or _ecg_enabled:
		set_process(true)

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

	# Terminal pulse. Alpha only: the hue stays critical, so the pulse cannot
	# be mistaken for another threshold crossing.
	if _is_pulsing:
		var wave: float = 0.5 + 0.5 * sin(
			Time.get_ticks_msec() / 1000.0 * pulse_speed * TAU
		)
		fill_color.a *= lerpf(0.35, 1.0, wave)

	# Damage / heal flash on the remaining fill.
	if _damage_flash > 0.01:
		var boost: float = _damage_flash * 0.45
		fill_color = Color(
			minf(1.0, fill_color.r + 0.28 * boost),
			minf(1.0, fill_color.g + 0.20 * boost),
			minf(1.0, fill_color.b + 0.14 * boost),
			minf(1.0, fill_color.a + 0.25 * boost)
		)
	if _heal_flash > 0.01:
		var boost: float = _heal_flash * 0.35
		fill_color = Color(
			minf(1.0, fill_color.r + 0.12 * boost),
			minf(1.0, fill_color.g + 0.16 * boost),
			minf(1.0, fill_color.b + 0.22 * boost),
			minf(1.0, fill_color.a + 0.20 * boost)
		)

	for i in SEGMENT_COUNT:
		var ox: float = origin.x + i * (segment_width + segment_gap)
		var oy: float = origin.y

		if _segment_offsets[i] > 0.01:
			oy += sin(_segment_offsets[i] * 9.0) * segment_nudge * _segment_offsets[i]

		draw_rect(Rect2(ox, oy, segment_width, segment_height), empty_color, true)

		# Right-to-left depletion: the leftmost segment is the last to empty,
		# so segment i covers the ratio band [i/3, (i+1)/3] and its own fill
		# grows from its LEFT edge.
		var segment_fill: float = clampf(
			_ratio * SEGMENT_COUNT - float(i), 0.0, 1.0
		)
		if segment_fill > 0.0:
			var fw: float = segment_width * segment_fill
			if _damage_flash > 0.25 and i == mini(SEGMENT_COUNT - 1, int(_ratio * SEGMENT_COUNT)):
				fw *= 1.0 + _damage_flash * 0.05
			draw_rect(Rect2(ox, oy, fw, segment_height), fill_color, true)

			if _segment_offsets[i] > 0.05:
				draw_rect(
					Rect2(ox + fw - 2.0, oy, 2.0, segment_height),
					Color(1, 1, 1, 0.14 * _segment_offsets[i]), true
				)

		# Ghost of the exact delta that is about to disappear (damage) or
		# that just appeared (heal).
		if _ghost_t > 0.02:
			var from_fill: float = clampf(_ghost_from * SEGMENT_COUNT - float(i), 0.0, 1.0)
			var to_fill: float = clampf(_ratio * SEGMENT_COUNT - float(i), 0.0, 1.0)

			if _ghost_is_damage and from_fill > to_fill:
				var lost_start: float = to_fill
				var lost_w: float = (from_fill - to_fill) * segment_width
				if lost_w > 0.5:
					var gx: float = ox + lost_start * segment_width
					var intensity: float = _ghost_t * (0.55 + _crt_burst * 0.45)
					var t: float = Time.get_ticks_msec() / 1000.0

					# Base ghost.
					draw_rect(
						Rect2(gx, oy, lost_w, segment_height),
						Color(0.63, 0.16, 0.12, 0.55 * intensity), true
					)

					# Horizontal tears.
					var y: float = oy
					while y < oy + segment_height:
						var jitter: float = (sin(t * 12.0 + y * 0.7) * 3.0 \
								+ sin(t * 5.0) * 2.0) * _crt_burst
						draw_line(
							Vector2(gx + jitter, y),
							Vector2(gx + lost_w + jitter * 0.6, y),
							Color(0.86, 0.71, 0.63, 0.35 * intensity), 1.0
						)
						y += 2.0

					# Vertical glitch bars.
					var glitch_count: int = 2 + int(_crt_burst * 4.0)
					for g in glitch_count:
						var gx2: float = gx + lost_w * (0.15 + g * 0.22) \
								+ sin(t * 8.0 + g) * 4.0
						var gw: float = 1.5 + _crt_burst * 2.5
						var ga: float = 0.4 * intensity * (0.6 + 0.4 * sin(t * 15.0 + g))
						draw_rect(
							Rect2(gx2, oy, gw, segment_height),
							Color(0.94, 0.86, 0.78, ga), true
						)

					# Bright cut edge.
					draw_rect(
						Rect2(gx - 1.0, oy, 2.0, segment_height),
						Color(1.0, 0.78, 0.63, 0.5 * intensity), true
					)

			elif not _ghost_is_damage and to_fill > from_fill:
				var gain_start: float = from_fill
				var gain_w: float = (to_fill - from_fill) * segment_width
				if gain_w > 0.5:
					var gx: float = ox + gain_start * segment_width
					var intensity: float = _ghost_t * 0.7
					draw_rect(
						Rect2(gx, oy, gain_w, segment_height),
						Color(0.71, 0.78, 0.86, 0.25 * intensity), true
					)
					draw_rect(
						Rect2(gx + gain_w - 2.0, oy, 2.0, segment_height),
						Color(0.86, 0.92, 1.0, 0.55 * intensity), true
					)

	# ECG on top of fills, broken at gaps.
	if _ecg_enabled and ecg_enabled:
		_draw_ecg(origin, bars_width)

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


## One cycle of a simplified ECG: P → QRS → T + mild noise.
## t — continuous time in "beat" units; irreg 0..1 adds damage chaos.
func _ecg_sample(t: float, irreg: float) -> float:
	var x: float = fposmod(t, 1.0)
	var y: float = 0.0

	# P wave
	if x > 0.08 and x < 0.18:
		var u: float = (x - 0.08) / 0.10
		y = 0.22 * sin(u * PI)
	# QRS
	elif x >= 0.22 and x < 0.28:
		var u: float = (x - 0.22) / 0.06
		if u < 0.25:
			y = -0.15 * (u / 0.25)
		elif u < 0.45:
			y = -0.15 + 1.15 * ((u - 0.25) / 0.20)
		elif u < 0.60:
			y = 1.0 - 1.35 * ((u - 0.45) / 0.15)
		else:
			y = -0.35 * (1.0 - (u - 0.60) / 0.40)
	# T wave
	elif x > 0.38 and x < 0.55:
		var u: float = (x - 0.38) / 0.17
		y = 0.32 * sin(u * PI)

	y += (sin(t * 17.3) * 0.03 + sin(t * 41.1) * 0.02) * (0.4 + irreg)
	if irreg > 0.15 and x > 0.22 and x < 0.30:
		y += irreg * 0.55 * sin((x - 0.22) / 0.08 * PI)
	return y


func _draw_ecg(origin: Vector2, bars_width: float) -> void:
	var base_alpha: float = 0.22
	if _ratio <= critical_ratio:
		base_alpha = 0.58
	elif _ratio <= impaired_ratio:
		base_alpha = 0.42
	else:
		base_alpha = 0.20 + (1.0 - _ratio) * 0.06

	base_alpha = minf(0.85, base_alpha + _ecg_spike * 0.35 + _damage_flash * 0.12)
	if base_alpha < 0.03:
		return

	var amp: float = (0.35 + (1.0 - _ratio) * 0.55) * segment_height * ecg_amplitude
	if _ratio <= terminal_ratio:
		amp *= 1.15

	var scroll: float = _ecg_phase * (ecg_scroll_speed + (1.0 - _ratio) * 0.7 \
			+ _ecg_spike * 0.8)

	# Contrast vs fill.
	var col: Color
	if _ratio <= critical_ratio:
		col = Color(1.0, 0.82, 0.75, minf(0.95, base_alpha + 0.15))
	elif _ratio <= impaired_ratio:
		col = Color(0.03, 0.03, 0.04, minf(0.92, base_alpha + 0.28))
	else:
		col = Color(0.92, 0.92, 0.94, minf(0.88, base_alpha + 0.22))

	var mid_y: float = origin.y + segment_height * 0.55
	var total_fill_units: float = _ratio * float(SEGMENT_COUNT)

	for i in SEGMENT_COUNT:
		var seg_fill: float = clampf(total_fill_units - float(i), 0.0, 1.0)
		if seg_fill < 0.02:
			continue

		var seg_x: float = origin.x + float(i) * (segment_width + segment_gap)
		var seg_fill_w: float = segment_width * seg_fill
		var steps: int = maxi(12, int(seg_fill_w / 1.5))

		# Polyline only inside this segment's filled rect — gap stays empty.
		var points: PackedVector2Array = PackedVector2Array()
		points.resize(steps + 1)
		for s in steps + 1:
			var u: float = float(s) / float(steps)
			var x: float = seg_x + u * seg_fill_w
			var t: float = scroll - (float(i) + u) * 0.85
			var y: float = mid_y - _ecg_sample(t, _ecg_spike) * amp
			points[s] = Vector2(x, y)

		draw_polyline(points, col, 1.2, true)

		# Soft second pass on dark / red.
		if _ratio > impaired_ratio or _ratio <= critical_ratio or _ecg_spike > 0.2:
			var glow_a: float = (0.28 if _ratio <= critical_ratio else 0.18) \
					* minf(1.0, base_alpha + 0.3)
			var glow := Color(col.r, col.g, col.b, glow_a)
			draw_polyline(points, glow, 2.1, true)

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
