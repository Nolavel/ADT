# =============================================================================
# votive_projector.gd — VotiveProjector, the visible half of the Votive
# (docs/attribution.md §6): a terminal worn at the right temple, projecting
# a hologram in front of the face. State and a visual representation of that
# state — nothing else.
#
# Shared between the player and NPCs, same reasoning as HealthComponent
# (core/components/health_component/): both player.tscn and npc.tscn carry
# one, and neither owner needs to know it's a shared node type.
#
# Deliberately NOT VotiveProjectorComponent — GDSCRIPT_STYLE.md's "Component"
# suffix convention is a default, not a law, and docs/attribution.md §6/§8
# names this class VotiveProjector explicitly. Kept as the design names it
# rather than renamed to fit the convention.
#
# No communication_state, no current_call, no identity binding — the Votive
# is a terminal that shows things, never a credential (attribution.md §6's
# own "game code must not let these two touch"). This node does not know who
# it belongs to, does not know what a "call" is, and does not decide when to
# transmit — it is told, by whichever controller drives the owning body
# (IdleNPCController for NPCs; nothing drives the player's, see below).
#
# GEOMETRY (revised from the first pass, which used a point OmniLight3D at
# the temple — read as "this NPC is lit," not "this NPC is transmitting", no
# sense of direction). Now a small self-lit quad, floating in front of the
# face rather than a point at the side of the head: attribution.md §6 says
# the terminal PROJECTS a hologram in front of the face, and that is what a
# player needs to actually see — a flat plane that turns with the NPC's own
# facing, not a bare bulb. This is also the first thing in the build that
# shows a crowd member's facing at a glance from a distance; that side
# effect is worth as much as the Votive readability itself.
#
# The quad's material is SHADING_MODE_UNSHADED with cull_mode DISABLED and no
# glow dependency: EnvironmentLightingSystem's runtime Environment
# (core/world/world_environment_systems/) does not enable glow_enabled today
# (only an unrelated dev tool, tools/tests/noir_room/, does) — enabling glow
# project-wide is a renderer/perf decision outside this component's scope, so
# visibility here does not depend on it. Unshaded + a saturated albedo reads
# at full brightness regardless of scene lighting or time of day; emission is
# still set (emission_energy, tuned comfortably above the noir_room test
# tool's own glow_hdr_threshold of 1.1) so the projection blooms for free the
# day glow is turned on, without needing a second pass here.
#
# flip_facing exists because the quad's own default front-face direction
# relative to this project's +Z-forward convention could not be verified
# without running the editor (see the task's own "не запускай сам") — cheaper
# for Stan to flip one bool after a look than to round-trip a code change.
#
# update_projection(delta) is driven by the owning body's own
# _physics_process (NPCBase, player.gd) every frame, the same "dumb
# component, driven by its owner" convention NPCAnimationComponent's
# update_animation_blend()/update_head_look() already use — this node never
# runs its own _process(). It is a no-op outside TRANSMITTING: IDLE/DARK are
# static, applied once at the moment they're entered, nothing to animate
# per frame.
#
# Positioning is computed once in _ready() from the owner's own
# get_eye_height() (duck-typed, same pattern PerceptionComponent's
# _target_chest_height() uses) rather than authored per scene instance — one
# formula for player and NPC alike, correct regardless of body_height. The
# quad itself is built in code (a MeshInstance3D child), not hand-placed in
# the .tscn, so this stays a single new top-level node in npc.tscn/
# player.tscn rather than a skeleton/bone edit to those large generated
# scenes.
# =============================================================================
extends Node3D
class_name VotiveProjector

enum State { IDLE, TRANSMITTING, DARK }

@export_group("Placement")
## Used only if the parent has no get_eye_height() (duck-typed, not a type
## check) — an order-of-magnitude fallback, not a real body measurement.
@export var mount_height_fallback: float = 1.6
## The projection sits slightly below eye level, not at it.
@export var eye_height_offset: float = 0.05
## How far in front of the face the projection floats — attribution.md §6's
## "in front of the face", not at the temple itself (the temple is where the
## terminal is WORN; the projection is what it shows). Stan tunes by eye,
## hence @export, not a constant — 0.2-0.3 is the expected range.
@export var projection_forward_offset: float = 0.25

@export_group("Projection")
## Side length of the square. Deliberately larger than a realistic HUD
## element — this is a prototype legibility pass, not final art. Stan tunes
## by eye; 0.2-0.3 is the expected range.
@export var projection_size: float = 0.25
## Flips the quad 180° around its own vertical axis. See the file header on
## why this exists instead of a hardcoded assumption about QuadMesh's
## default front-face direction.
@export var flip_facing: bool = false

@export_group("Transmission")
## Total blue/off-flicker + solid-red window. The owning controller decides
## WHEN transmission starts and how long PENDING actually lasts
## (IdleNPCController.call_report_duration) — this is only told to animate
## for however long it's given, via start_transmitting(duration); the two
## are expected to be passed the same number, not independently tuned.
@export var flash_count: int = 3
## Fraction of the transmission window spent solid red at the end, after the
## flicker — attribution.md §6's "RED · off · RED · off · RED · SOLID".
@export_range(0.05, 0.9) var solid_hold_ratio: float = 0.25

@export_group("Visual")
@export var idle_color: Color = Color(0.25, 0.55, 1.0)
@export var alert_color: Color = Color(1.0, 0.15, 0.1)
## Feeds StandardMaterial3D.emission_energy_multiplier — kept comfortably
## above tools/tests/noir_room's own glow_hdr_threshold (1.1), the only glow
## threshold anywhere in this project today, so the projection blooms for
## free if glow is ever turned on for the real game environment. Visibility
## itself does not depend on this — see the file header.
@export var emission_energy: float = 4.0

var _state: State = State.IDLE
var _transmit_duration: float = 3.0
var _transmit_timer: float = 0.0
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	_position_in_front_of_face()

	var quad := QuadMesh.new()
	quad.size = Vector2(projection_size, projection_size)

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	## Both sides visible: a wrong assumption about QuadMesh's default
	## front-face direction (see flip_facing's own comment) would otherwise
	## make the whole projection invisible rather than merely backwards.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.emission_enabled = true
	_material.emission_energy_multiplier = emission_energy
	## A screen, not a lit surface — see the file header.
	_material.disable_receive_shadows = true

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = _material
	_mesh_instance.rotation_degrees.y = 180.0 if flip_facing else 0.0
	add_child(_mesh_instance)

	_apply_idle_visual()


## Called once per physics frame by the owning body — see the file header.
## No-op outside TRANSMITTING: IDLE/DARK apply their visual once, at the
## moment go_idle()/go_dark() is called, not every frame.
func update_projection(delta: float) -> void:
	if _state != State.TRANSMITTING:
		return
	_transmit_timer = minf(_transmit_timer + delta, _transmit_duration)
	_update_transmit_visual()


## Starts (or restarts) the transmission animation over duration seconds —
## the controller's own call_report_duration, passed in rather than owned
## here, so the visual countdown and the actual PENDING window can never
## drift apart into two different "how long is this" numbers.
func start_transmitting(duration: float) -> void:
	_state = State.TRANSMITTING
	_transmit_duration = maxf(duration, 0.01)
	_transmit_timer = 0.0


## Baseline, on everyone, always (attribution.md §6) — also what interrupts
## a TRANSMITTING animation: update_projection() only advances/animates
## while _state == TRANSMITTING, so calling this (or go_dark()) mid-flicker
## simply stops the countdown where it stands.
func go_idle() -> void:
	_state = State.IDLE
	_transmit_timer = 0.0
	_apply_idle_visual()


## Terminal blacks out — see the file header on DARK's own meaning.
func go_dark() -> void:
	_state = State.DARK
	_transmit_timer = 0.0
	_apply_dark_visual()


func get_state() -> State:
	return _state


## Centred in front of the face, not offset to either side — the temple is
## where the terminal is WORN, but what a viewer needs to read is the
## projection, floating in front of the face like the design describes.
func _position_in_front_of_face() -> void:
	var owner_body := get_parent()
	var mount_height := mount_height_fallback
	if owner_body and owner_body.has_method(&"get_eye_height"):
		mount_height = float(owner_body.call(&"get_eye_height")) - eye_height_offset
	position = Vector3(0.0, mount_height, projection_forward_offset)


func _apply_idle_visual() -> void:
	if not _mesh_instance:
		return
	_mesh_instance.visible = true
	_set_color(idle_color)


func _apply_dark_visual() -> void:
	if not _mesh_instance:
		return
	_mesh_instance.visible = false


## blue -> flash_count red/off flashes -> solid red for the final
## solid_hold_ratio share of the window — attribution.md §6's pattern,
## timed against _transmit_duration (whatever start_transmitting() was
## given), not a fixed constant.
func _update_transmit_visual() -> void:
	if not _mesh_instance:
		return
	var solid_start := _transmit_duration * (1.0 - solid_hold_ratio)
	if _transmit_timer >= solid_start:
		_mesh_instance.visible = true
		_set_color(alert_color)
		return
	var blink_period := solid_start / maxf(float(flash_count), 1.0)
	var phase := fmod(_transmit_timer, blink_period)
	_mesh_instance.visible = phase < blink_period * 0.5
	_set_color(alert_color)


func _set_color(color: Color) -> void:
	if not _material:
		return
	_material.albedo_color = color
	_material.emission = color
