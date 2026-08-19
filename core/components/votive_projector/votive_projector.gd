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
# PLACEMENT (revised — this node is now mounted on the head bone, not
# offset from the body root). The projection used to be positioned in
# _ready() from the owner's own duck-typed get_eye_height(), which meant the
# quad tracked the ROOT's facing, not the HEAD's — wrong once head-look
# (NPCAnimationComponent's LookAtModifier3D) turns the head independently of
# the body, since attribution.md §6's Votive is supposed to read as "this
# NPC is looking at you," and a body-relative offset cannot show that. This
# node is now parented under a BoneAttachment3D bound to the "Head" bone
# (both npc.tscn and player.tscn), so its position/rotation are already
# relative to the live head pose — get_eye_height()/mount_height_fallback/
# eye_height_offset/projection_forward_offset (the old duck-typed-owner
# math) are gone; there is no owner to duck-type against once the parent is
# a BoneAttachment3D.
#
# WHICH SKELETON. Both rigs retarget through two nested Skeleton3Ds:
# GeneralSkeleton (the one AnimationPlayer/AnimationTree actually drives)
# feeds a child RetargetModifier3D, which writes the retargeted pose onto
# OriginalSkeleton — and OriginalSkeleton is the one every visible
# MeshInstance3D is skinned to. The existing LookAtModifier3D that actually
# turns the head (npc_animation_component.gd's _setup_head_look(),
# player_animation_component.gd's own equivalent) is already bound to
# OriginalSkeleton's "Head" bone (bone index 5 in both rigs) for exactly
# that reason — it is the skeleton whose pose is what the player actually
# sees. The BoneAttachment3D this node hangs from is bound to the same bone
# on the same skeleton. player.tscn already carried an orphaned
# BoneAttachment3D at that exact path/bone (bone_idx 5, "Head") with nothing
# parented under it — leftover scaffolding from the earlier, interrupted
# pass at this same task; reused here rather than adding a second one.
#
# BONE AXES. A bone's local frame does not generally line up with this
# node's own -Z-forward assumption (typically a bone's local +Y runs along
# its own length, toward its child, not toward the character's forward) —
# a property of how this rig's bones are authored, not a defect, and one
# that (like flip_facing) could not be verified without running the editor.
# bone_local_offset/bone_rotation_compensation_deg are both @export for that
# reason — tuned by eye once attached, not derived here.
# =============================================================================
extends Node3D
class_name VotiveProjector

enum State { IDLE, TRANSMITTING, DARK }

@export_group("Placement")
## Local offset from the head bone's own origin (this node's parent is a
## BoneAttachment3D bound to "Head" — see the file header), in the bone's
## own local axes. Attribution.md §6's "in front of the face", not at the
## temple itself (the temple is where the terminal is WORN; the projection
## is what it shows) — but "in front" is only meaningful once
## bone_rotation_compensation_deg has straightened this node's local axes
## out to match the character's own forward/up, so the two are tuned
## together, by eye. Replaces the old owner-eye-height math (mount_height_
## fallback/eye_height_offset/projection_forward_offset), which assumed a
## body-root parent this node no longer has.
@export var bone_local_offset: Vector3 = Vector3(0.0, 0.0, 0.25)
## Compensates for the head bone's own local axis convention not matching
## this node's local -Z-forward assumption — see the file header's "bone
## axes" note. A property of this rig's bones, not a defect; tuned by eye
## once attached.
@export var bone_rotation_compensation_deg: Vector3 = Vector3.ZERO

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
	position = bone_local_offset
	rotation_degrees = bone_rotation_compensation_deg

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
