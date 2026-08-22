# =============================================================================
# three_dots_morph.gd
# ## ENG: Three-dot morph icon for menu handles.
#         Idle   → horizontal line
#         Hover  → async wave (±amp)
#         Drag / pull / throw → continuous clockwise circle
#
#         Pure _draw(), no child nodes. Spring physics via SpringPoint,
#         carried over unchanged from the HTML motion study.
#
#         First concrete MorphIcon. Everything a controller talks to —
#         Mode, to_line()/to_wave()/to_circle(), get_mode() — belongs to
#         that base class; the only method overridden here is set_mode(),
#         because the only thing specific to three dots is where the dots
#         are asked to go. Parent it under any Button and let whoever owns
#         the gesture drive it; the morph never reads input itself.
# =============================================================================
class_name ThreeDotsMorph
extends MorphIcon

@export_group("Geometry")
@export var spacing: float = 14.0
@export var dot_radius: float = 3.5
@export var circle_radius: float = 11.0

@export_group("Motion")
@export var wave_speed: float = 5.8
@export var wave_amp: float = 6.0
@export var circle_speed: float = 1.2
## Phase offsets so the three dots never sit on one straight line while waving.
@export var wave_phases: Array[float] = [0.0, 2.1, 4.2]

@export_group("Look")
@export var color: Color = Color(0.91, 0.93, 0.95, 1.0)  ## #e8edf2, matches concept

## When true, mouse_entered → WAVE, mouse_exited → LINE (only while idle).
## Controllers that own drag/pull should leave this false and drive modes
## themselves so hover does not fight the active gesture.
@export var auto_hover_wave: bool = false

var _dots: Array[SpringPoint] = []
var _time: float = 0.0
var _cx: float = 0.0
var _cy: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild_dots()
	resized.connect(_on_resized)
	if auto_hover_wave:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
	set_process(true)


func _on_resized() -> void:
	_rebuild_dots()


func _rebuild_dots() -> void:
	_cx = size.x * 0.5
	_cy = size.y * 0.5
	_dots.clear()
	_dots.append(SpringPoint.new(_cx - spacing, _cy))
	_dots.append(SpringPoint.new(_cx, _cy))
	_dots.append(SpringPoint.new(_cx + spacing, _cy))
	# Re-apply current mode targets so a resize does not leave dots stranded.
	_apply_mode_targets(true)


# -----------------------------------------------------------------------------
# ## ENG: The one MorphIcon override
# -----------------------------------------------------------------------------

## MorphIcon's to_line()/to_wave()/to_circle() all route here, so this is the
## single place three dots decide what a mode looks like.
func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	_apply_mode_targets(false)


# -----------------------------------------------------------------------------
# ## ENG: Targets + spring step
# -----------------------------------------------------------------------------

func _apply_mode_targets(instant: bool) -> void:
	match mode:
		Mode.LINE:
			_dots[0].set_target(_cx - spacing, _cy)
			_dots[1].set_target(_cx, _cy)
			_dots[2].set_target(_cx + spacing, _cy)
		Mode.WAVE, Mode.CIRCLE:
			# Continuous modes refresh every frame in _update_targets().
			pass
	if instant:
		for d in _dots:
			d.snap()


func _update_targets() -> void:
	if mode == Mode.WAVE:
		for i in 3:
			var phase: float = wave_phases[i] if i < wave_phases.size() else float(i) * 2.1
			var y: float = _cy + sin(_time * wave_speed + phase) * wave_amp
			_dots[i].set_target(_cx + float(i - 1) * spacing, y)

	elif mode == Mode.CIRCLE:
		# Positive angle in Godot 2D = clockwise (canvas Y down).
		var base: float = _time * circle_speed
		for i in 3:
			var a: float = base + (float(i) * TAU) / 3.0 - PI * 0.5
			var x: float = _cx + cos(a) * circle_radius
			var y: float = _cy + sin(a) * circle_radius
			_dots[i].set_target(x, y)


func _process(delta: float) -> void:
	_time += delta
	_update_targets()
	for d in _dots:
		d.update(delta)
	queue_redraw()


func _draw() -> void:
	for d in _dots:
		draw_circle(Vector2(d.x, d.y), dot_radius, color)


# -----------------------------------------------------------------------------
# ## ENG: Optional auto-hover (off by default when a controller owns the morph)
# -----------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	if mode == Mode.LINE:
		to_wave()


func _on_mouse_exited() -> void:
	if mode == Mode.WAVE:
		to_line()
