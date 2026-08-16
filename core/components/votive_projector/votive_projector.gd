# =============================================================================
# votive_projector.gd — VotiveProjector, the visible half of the Votive
# (docs/attribution.md §6): a terminal worn at the right temple, projecting
# a hologram. State and a visual representation of that state — nothing else.
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
# Three states, nothing more:
#   IDLE          steady blue — the default, on everyone, always. This
#                  baseline is what makes TRANSMITTING legible: if only
#                  witnesses lit up, any light at all would mean trouble.
#   TRANSMITTING  the ~3s blue-was-here -> red/off flicker -> solid red
#                  escalation, attribution.md §6's countdown a player can
#                  literally count with no UI.
#   DARK          off. Used for a knocked-down NPC's terminal blacking out —
#                  not part of attribution.md §7's chain itself, but the
#                  natural reading of "unconscious" for a device that is
#                  otherwise always lit.
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
# light itself is built in code (an OmniLight3D child), not hand-placed in
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
@export var temple_side_offset: float = 0.12
@export var temple_forward_offset: float = 0.06
## Temple sits slightly below eye level.
@export var eye_height_offset: float = 0.05

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
@export var light_energy: float = 1.2
@export var light_range: float = 0.5

var _state: State = State.IDLE
var _transmit_duration: float = 3.0
var _transmit_timer: float = 0.0
var _light: OmniLight3D = null


func _ready() -> void:
	_position_at_temple()
	_light = OmniLight3D.new()
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.shadow_enabled = false
	add_child(_light)
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


func _position_at_temple() -> void:
	var owner_body := get_parent()
	var mount_height := mount_height_fallback
	if owner_body and owner_body.has_method(&"get_eye_height"):
		mount_height = float(owner_body.call(&"get_eye_height")) - eye_height_offset
	position = Vector3(temple_side_offset, mount_height, temple_forward_offset)


func _apply_idle_visual() -> void:
	if not _light:
		return
	_light.visible = true
	_light.light_color = idle_color


func _apply_dark_visual() -> void:
	if not _light:
		return
	_light.visible = false


## blue -> flash_count red/off flashes -> solid red for the final
## solid_hold_ratio share of the window — attribution.md §6's pattern,
## timed against _transmit_duration (whatever start_transmitting() was
## given), not a fixed constant.
func _update_transmit_visual() -> void:
	if not _light:
		return
	var solid_start := _transmit_duration * (1.0 - solid_hold_ratio)
	if _transmit_timer >= solid_start:
		_light.visible = true
		_light.light_color = alert_color
		return
	var blink_period := solid_start / maxf(float(flash_count), 1.0)
	var phase := fmod(_transmit_timer, blink_period)
	_light.visible = phase < blink_period * 0.5
	_light.light_color = alert_color
