# =============================================================================
# npc_base.gd — NPCBase, physical body and metrics shared by every NPC.
#
# Same separation as HoverBase (core/controllers/transport/base/hover_base.gd):
# the body integrates a movement intent, it never decides what that intent
# should be. set_move_intent() is the only way in; a controller node
# (npc/controllers/*, a child of this node) is the only thing that calls it.
# Of everything that makes up an NPC, the decision layer is the one part
# expected to change (hand-written state machine now, behaviour tree later)
# — body, movement and perception are meant to outlive that switch, so
# nothing here knows or cares which controller is driving it.
#
# Extends ActorBase (core/characters/actor_base.gd), the contract
# NPCControllerBase and PerceptionComponent actually type-check against —
# DroneBase (world/police_drone/drone_base.gd) extends the same base and
# reuses both. get_facing_direction() is inherited unmodified: NPCBase's
# root really does turn to face (_face_move_direction() below), which is
# exactly what ActorBase's default assumes.
#
# Metric and facing getters (get_eye_height/get_shoulder_height/
# get_facing_direction) share names with player.gd's own: the TPS camera's
# target/lock-on code already reads these through duck typing, so any node
# carrying them is usable wherever the player is, without the reader needing
# to know it's an NPC. get_facing_direction() exists because this project's
# rotation convention (atan2(dir.x, dir.z), +Z forward) isn't Godot's usual
# -Z-forward — see ActorBase's own comment on that getter.
#
# Perception exists now (npc_components/perception_component/), and this
# body can aim its head at a world point via set_look_target()/
# clear_look_target() — but it still never decides WHAT to look at. That
# decision lives in the controller (idle_npc_controller.gd today), same as
# movement intent.
#
# set_look_target()/clear_look_target() are state only — NPCAnimationComponent
# (npc_components/animation_component/) is what actually turns the head, via
# a LookAtModifier3D on the skeleton, read through has_look_target()/
# get_look_target_point() below. This body used to rotate a placeholder Head
# node by hand; that node is gone along with the capsule mesh once the real
# rig landed (see the npc.tscn commit) — the public contract didn't change,
# only where the turning happens.
#
# take_hit()/is_knocked_down() are a new contract, NPCBase-only rather than
# on ActorBase: DroneBase has no animation component to play a fall/getup
# clip on, and a flying body being knocked to the ground is a bigger,
# separate feature (real falling physics, a "crashed" state) this doesn't
# build. A punch that reaches a drone in flight just doesn't connect — see
# player.gd's own hit-detection comment.
#
# The knockdown sequence is three fixed-duration phases (FALLING/LYING/
# GETTING_UP, see KnockdownPhase and _update_knockdown()) plus a fourth,
# terminal DOWN phase entered only at zero health (see HealthComponent) and
# never left — not two with a poll on animation completion — an earlier
# version fired the knockdown
# clip once and then just waited out knockdown_duration before firing
# getup, which glitched: AnimationNodeOneShot goes inactive — and the
# locomotion tree underneath shows straight through, an idle pop mid-fall —
# the instant its CURRENT clip finishes playing, regardless of how long the
# controller wants to hold the pose for. A non-looping clip finishes on its
# own schedule, not the controller's. The fix is the LYING phase playing a
# looping clip (new4/ko-idle-loop, not the non-looping "ko-idle" also in the
# library — see npc_animation_component.gd's own comment on ANIM_LIE): a
# loop never finishes on its own, so it holds exactly as long as
# knockdown_hold_time says. FALLING/GETTING_UP still use non-looping clips
# and are still nominally at risk of the same gap if their own exported
# durations are tuned LONGER than the real clip lengths — tune them at or
# under, never over, and the phase transition (which always fires an
# explicit re-request, cutting the old clip off) preempts the gap entirely.
# =============================================================================
extends ActorBase
class_name NPCBase

## Clearance above BodyMetrics' head-top landmark for DebugHealthLabel — an
## interface offset, not a body measurement, so it lives here rather than as
## another BodyMetrics ratio.
const DEBUG_LABEL_CLEARANCE: float = 0.25
## Additional clearance stacking DebugActionLabel above DebugHealthLabel's own
## position, not another independent offset from head-top — keeps the two
## labels from overlapping when both debug_show_health and debug_show_action
## are on at once, and DebugActionLabel is the one that can run to two lines
## (word + reason), so it gets the higher slot.
const DEBUG_ACTION_LABEL_CLEARANCE: float = 0.35

## Body meshes opt in through this group in npc.tscn. Placeholder archetype
## colour belongs to the body only: a Votive, future weapon, or other
## component-owned mesh must stay on its own material unless it is explicitly
## authored as part of the body.
const GROUP_ARCHETYPE_BODY_MESH: StringName = &"archetype_body_mesh"

## Total height of this character. Per-instance data, not a constant: NPCs
## will vary. Landmark heights come from BodyMetrics ratios.
@export var body_height: float = 1.8
@export var walk_speed: float = 3.0

@export_group("Turning")
## How fast this body turns to face its movement direction or a facing
## target, rad/s equivalent fed through Smoothing.damp_factor. A feel
## value, tuned by eye — exported for that reason, same as walk_speed.
@export var turn_smoothing: float = 10.0

@export_group("Gravity")
## Same value and formula as player.gd's _apply_gravity(): one physical
## world, one gravity convention — not a second source to keep in sync.
@export var gravity: float = 20.0

@export_group("Knockdown")
## Seconds the fall clip (new4/knockdown) plays before the lying phase takes
## over. Tune at or under the real clip's own length — see the file header
## on why longer reopens the gap this fix closes.
@export var knockdown_fall_time: float = 0.6
## Seconds the body holds the lying-idle loop (new4/ko-idle-loop) before
## getting up — the bulk of the sequence, and the one phase immune to being
## tuned "too long" (a looping clip never ends on its own). This is what
## reads as "down."
@export var knockdown_hold_time: float = 2.0
## Seconds the getup clip (new4/ko-getup) plays before control returns to
## the controller. Same tuning caveat as knockdown_fall_time — at or under
## the real clip length, not over.
@export var knockdown_getup_time: float = 1.0

@export_group("Archetype")
## docs/npc_archetypes.md data — see NPCArchetypeData's own header for what
## each field drives. Unset (null) is valid: an NPC without one keeps its
## own body_height/walk_speed/PerceptionComponent defaults untouched, same
## as before this field existed.
@export var archetype: NPCArchetypeData = null

@export_group("Debug")
## Shows a floating Label3D above the NPC with current/max health and the
## active knockdown phase — a quick way to see hit points land without
## attaching a debugger. Off by default; while false the label stays
## hidden and its text is not recomputed at all.
@export var debug_show_health: bool = false
## Shows a second floating Label3D, stacked above DebugHealthLabel, with a
## short word for what this NPC is doing right now (see
## _resolve_debug_action_text()'s own comment for the vocabulary) — the only
## way today to tell "the reaction didn't fire" apart from "it fired but has
## no visible effect yet". Independent @export from debug_show_health: the
## two get switched on at different times (verifying a reaction vs.
## verifying damage). Off by default; while false the label stays hidden and
## nothing is recomputed.
@export var debug_show_action: bool = false

## Movement intent for this frame, written by whatever controller drives
## this NPC. direction is expected normalised and horizontal (Y ignored);
## speed_ratio is 0..1, a fraction of walk_speed.
var _move_direction: Vector3 = Vector3.ZERO
var _move_speed_ratio: float = 0.0
## True while movement direction should also drive body rotation — the
## default, and every caller before the two-phase flee backpedal (NPC_
## REACTIONS.md §4) left it there. False is the backpedal case:
## set_move_intent()'s direction still has to move the body backward, but
## rotation must keep tracking a facing target (the player) instead — see
## set_move_intent()'s own comment and _face_move_direction() below, whose
## header already anticipated this exact override before anything used it.
var _move_faces_direction: bool = true

## FALLING plays the knockdown clip, LYING holds the looping idle clip,
## GETTING_UP plays the getup clip — see _update_knockdown() for the
## fixed-duration timing of each and the file header for why fixed
## durations, not animation-completion polling, is what fixed the pop.
## DOWN is terminal: entered only once HealthComponent reports zero health,
## holds the same looping lying clip as LYING, and never transitions out —
## see _update_knockdown().
enum KnockdownPhase { FALLING, LYING, GETTING_UP, DOWN }

## Knocked down by a hit — see take_hit()'s own comment. While true, this
## body ignores movement intent outright (_physics_process branches on it
## directly, not by refusing set_move_intent() calls) and the controller is
## expected to have stopped calling set_move_intent()/set_look_target() at
## all (see is_knocked_down()).
var _knocked_down: bool = false
## Which of the three phases is currently playing — see KnockdownPhase.
var _knockdown_phase: KnockdownPhase = KnockdownPhase.FALLING
## Seconds spent in the CURRENT phase — reset to 0 on every phase change,
## compared against that phase's own exported duration.
var _knockdown_phase_timer: float = 0.0


## World point the body turns toward when it isn't moving — set by
## set_facing_target()/clear_facing_target(), read only by
## _face_move_direction(). Movement always overrides this; see that
## method's comment.
var _has_facing_target: bool = false
var _facing_target_point: Vector3 = Vector3.ZERO

## Whether the head currently has somewhere to look, and where — set by
## set_look_target()/clear_look_target(), read by NPCAnimationComponent
## through the getters below (has_look_target()/get_look_target_point()).
var _has_look_target: bool = false
var _look_target_point: Vector3 = Vector3.ZERO

## Cached text from the last DebugActionLabel refresh, so
## _update_debug_action_label() only touches .text (and only recomputes the
## billboard-visible string) on an actual state change instead of every
## physics frame — unlike the health label, which is cheap to re-stringify
## every frame regardless. See that method's own comment.
var _debug_action_label_text: String = ""

## The first child (if any) that answers get_debug_action_text() — resolved
## once in _ready() by capability (has_method()), not by name or class, so
## NPCBase still never needs to know which controller class drives it (see
## the file header). Null is a valid, silent outcome: an NPC whose
## controller doesn't implement this optional debug method just shows
## nothing beyond DOWN/IDLE — same "unset is a no-op" contract archetype
## uses.
var _debug_action_source: Node = null

## ComicEffectSystem, resolved lazily by group the same way IdleNPCController
## resolves IncidentRegistry — this body is a static scene instance and never
## receives a WorldContext, and Godot's bottom-up _ready() ordering means the
## system may not exist yet the first time we look. Null is a silent no-op:
## a floating word is decoration, never a precondition for taking a hit.
var _comic_effects: ComicEffectSystem = null

## Resolved once via @onready. Null (and silently skipped by
## _physics_process()) if the scene has no AnimationComponent — same
## defensive pattern the old $Head lookup used to have.
@onready var _animation: NPCAnimationComponent = get_node_or_null("AnimationComponent")

## Resolved once via @onready, same defensive pattern as _animation. Null if
## the scene has no HealthComponent — take_hit() still knocks the body down
## in that case, it just never applies damage or reaches the terminal DOWN
## phase, so knockdowns loop forever (the pre-HealthComponent behaviour).
@onready var _health: HealthComponent = get_node_or_null("HealthComponent")

## Resolved once via @onready, same defensive pattern as _animation/_health.
## Null (and debug_show_health silently has no effect) if the scene has no
## DebugHealthLabel.
@onready var _debug_health_label: Label3D = get_node_or_null("DebugHealthLabel")

## Resolved once via @onready, same defensive pattern as _debug_health_label.
## Null (and debug_show_action silently has no effect) if the scene has no
## DebugActionLabel.
@onready var _debug_action_label: Label3D = get_node_or_null("DebugActionLabel")

## Resolved once via @onready, same defensive pattern as _animation/_health.
## Driven every physics frame below, same "dumb component, owner drives it"
## convention _animation already follows — see votive_projector.gd's own
## header. State changes (start_transmitting()/go_idle()/go_dark()) are the
## controller's call, not this body's; this only keeps its animation ticking.
## Looked up by scene-unique name (%), not a direct-child path, since it now
## sits under a BoneAttachment3D bound to the head bone rather than directly
## under this node — see votive_projector.gd's own header on why.
@onready var _votive: VotiveProjector = get_node_or_null("%VotiveProjector")


func _ready() -> void:
	super._ready()
	add_to_group("lockable")
	if _health == null:
		push_warning("[NPCBase] HealthComponent not found - knockdowns will loop forever, no terminal DOWN phase")
	if _debug_health_label:
		_debug_health_label.position.y = get_head_top_height() + DEBUG_LABEL_CLEARANCE
	if _debug_action_label:
		_debug_action_label.position.y = (
			get_head_top_height() + DEBUG_LABEL_CLEARANCE + DEBUG_ACTION_LABEL_CLEARANCE
		)
	for child in get_children():
		if child.has_method(&"get_debug_action_text"):
			_debug_action_source = child
			break
	_apply_archetype()


func _physics_process(delta: float) -> void:
	if _knocked_down:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		velocity.x = _move_direction.x * walk_speed * _move_speed_ratio
		velocity.z = _move_direction.z * walk_speed * _move_speed_ratio
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if _knocked_down:
		_update_knockdown(delta)
	else:
		_face_move_direction(delta)
	if _animation:
		_animation.update_animation_blend(delta)
		_animation.update_head_look(delta)
	if _votive:
		_votive.update_projection(delta)
	if _debug_health_label:
		_debug_health_label.visible = debug_show_health
		if debug_show_health:
			_update_debug_health_label()
	if _debug_action_label:
		_debug_action_label.visible = debug_show_action
		if debug_show_action:
			_update_debug_action_label()


## Movement intent for this frame, written by whatever controller drives this
## NPC. The body integrates it; it never decides what the intent should be.
## direction is expected normalised and horizontal; speed_ratio is 0..1.
## face_direction defaults to true (the only behaviour before the two-phase
## flee backpedal existed) — pass false to keep moving in `direction` while
## letting a facing target (set_facing_target()) drive rotation instead, see
## _face_move_direction()'s own comment.
func set_move_intent(direction: Vector3, speed_ratio: float, face_direction: bool = true) -> void:
	_move_direction = direction
	_move_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	_move_faces_direction = face_direction


## Read by NPCAnimationComponent to drive the idle<->walk blend — the same
## 0..1 fraction of walk_speed set_move_intent() was given.
func get_move_speed_ratio() -> float:
	return _move_speed_ratio


## Knocked down by a hit and, if a HealthComponent is attached, damaged by
## damage points — applied even to a body that is already down, so finishing
## off someone on the ground works. Only the fall itself is ignored while
## already knocked down (a second hit mid-fall doesn't restart the timer or
## replay the fall clip — there is no stacking/combo concept here). Clears
## any facing/look target and zeroes movement intent outright on the hit
## that starts the knockdown, since a knocked-down body no longer has a
## controller deciding either — see is_knocked_down(). Reaching zero health
## is handled by _update_knockdown(), which locks the body into the
## terminal DOWN phase instead of ever letting it get back up.
func take_hit(from_position: Vector3, damage: float = 25.0) -> void:
	if _health:
		_health.apply_damage(damage)

	if _knocked_down:
		# A hit landing on a body already down. It still damages (above) and
		# can still finish the NPC off, but it starts no new knockdown — so
		# it gets the lighter word instead. The early return is what keeps
		# one hit from ever producing both npc_hit and npc_knockdown.
		_try_spawn_comic_effect(&"npc_hit")
		return
	_knocked_down = true
	_knockdown_phase = KnockdownPhase.FALLING
	_knockdown_phase_timer = 0.0
	_move_direction = Vector3.ZERO
	_move_speed_ratio = 0.0
	clear_look_target()
	clear_facing_target()
	if _animation:
		_animation.play_knockdown()
	_try_spawn_comic_effect(&"npc_knockdown")


## Read by the controller (idle_npc_controller.gd's _decide()) to stop
## deciding outright while this body is down — the body itself already
## refuses to move regardless (see _physics_process()), this is what lets
## the controller stop calling set_move_intent()/set_look_target() at all
## rather than calling them into a body that's ignoring them.
func is_knocked_down() -> bool:
	return _knocked_down


## Advances the fixed-duration knockdown state machine.
##
## Every phase owns its own timer and animation:
##
## FALLING
##     Plays the non-looping fall animation. Transitions to LYING once
##     knockdown_fall_time elapses — or straight to DOWN instead, if health
##     already hit zero by then.
##
## LYING
##     Holds the looping lying animation for exactly
##     knockdown_hold_time seconds, unless health hits zero first, which
##     cuts the hold short and locks into DOWN immediately.
##
## GETTING_UP
##     Plays the non-looping getup animation before handing control back to
##     the controller, unless health hits zero first, which locks into DOWN
##     immediately instead of ever standing back up.
##
## DOWN
##     Terminal. Holds the same looping lying animation as LYING and never
##     transitions out — no timer runs in this phase.
func _update_knockdown(delta: float) -> void:
	if _knockdown_phase == KnockdownPhase.DOWN:
		return

	# A hit that drains the last hit point while already LYING/GETTING_UP
	# locks the body down right away, no timer — FALLING has its own check
	# below instead, so the fall clip gets to finish before locking in.
	if _knockdown_phase != KnockdownPhase.FALLING and _is_health_depleted():
		_enter_down_phase()
		return

	_knockdown_phase_timer += delta

	match _knockdown_phase:

		KnockdownPhase.FALLING:
			if _knockdown_phase_timer < knockdown_fall_time:
				return

			if _is_health_depleted():
				_enter_down_phase()
				return

			_knockdown_phase = KnockdownPhase.LYING
			_knockdown_phase_timer = 0.0

			if _animation:
				_animation.play_lying()

		KnockdownPhase.LYING:
			if _knockdown_phase_timer < knockdown_hold_time:
				return

			_knockdown_phase = KnockdownPhase.GETTING_UP
			_knockdown_phase_timer = 0.0

			if _animation:
				_animation.play_getup()

		KnockdownPhase.GETTING_UP:
			if _knockdown_phase_timer < knockdown_getup_time:
				return

			_knocked_down = false
			_knockdown_phase_timer = 0.0


func _is_health_depleted() -> bool:
	return _health != null and _health.is_dead()


## Locks the body into the terminal DOWN phase. Only (re-)fires the lying
## clip when it wasn't already playing (i.e. coming from FALLING or
## GETTING_UP) — coming from LYING the loop is already running and doesn't
## need restarting; the body is already on the ground either way.
func _enter_down_phase() -> void:
	var was_lying := _knockdown_phase == KnockdownPhase.LYING
	_knockdown_phase = KnockdownPhase.DOWN
	_knockdown_phase_timer = 0.0
	if _animation and not was_lying:
		_animation.play_lying()
	_try_spawn_comic_effect(&"npc_death")


## Resolves ComicEffectSystem on first use and asks it for one word above
## this body. The system owns the distance gate and the active-count cap, so
## there is nothing to check here beyond "does the system exist yet".
func _try_spawn_comic_effect(id: StringName) -> void:
	if _comic_effects == null:
		_comic_effects = get_tree().get_first_node_in_group(
				ComicEffectSystem.GROUP_COMIC_EFFECT_SYSTEM
		) as ComicEffectSystem
	if _comic_effects:
		_comic_effects.try_spawn(id, global_position, self)


## Refreshes DebugHealthLabel's text. Only called while debug_show_health is
## true (see _physics_process()) — the knockdown phase name is shown only
## while actually knocked down, since _knockdown_phase otherwise still holds
## a stale value from the last knockdown rather than a meaningful "current"
## one.
func _update_debug_health_label() -> void:
	var phase_text: String = KnockdownPhase.keys()[_knockdown_phase] if _knocked_down else "-"
	if _health:
		_debug_health_label.text = "%.0f/%.0f  %s" % [
			_health.current_health, _health.max_health, phase_text
		]
	else:
		_debug_health_label.text = "no HealthComponent  %s" % phase_text


## Refreshes DebugActionLabel's text — but only writes .text when the
## resolved string actually changed, unlike _update_debug_health_label()
## above, which re-stringifies unconditionally every frame it's shown (see
## debug_show_action's own comment on why this label is event-driven).
## Reads only state that already exists elsewhere: is_knocked_down() (this
## body's own knockdown flag) for DOWN, or the optional
## get_debug_action_text() a controller may implement for everything else
## (see _debug_action_source's own comment) — this never stores its own copy
## of "what is this NPC doing."
func _update_debug_action_label() -> void:
	var text := _resolve_debug_action_text()
	if text == _debug_action_label_text:
		return
	_debug_action_label_text = text
	_debug_action_label.text = text


func _resolve_debug_action_text() -> String:
	if is_knocked_down():
		return "DOWN"
	if _debug_action_source:
		return String(_debug_action_source.call(&"get_debug_action_text"))
	return "IDLE"


## Character metric getters — same names as player.gd, so callers that duck
## type against the player (camera lock-on) work on an NPC unmodified.
func get_eye_height() -> float:
	return BodyMetrics.eye_height(body_height)


func get_shoulder_height() -> float:
	return BodyMetrics.shoulder_height(body_height)


func get_head_top_height() -> float:
	return BodyMetrics.get_head_top_height(body_height)


func get_debug_type_label() -> String:
	return "NPC"


## Point this character's head turns toward, in world space. The body only
## aims the head; whether there is anything worth looking at is a decision,
## and decisions live in the controller.
func set_look_target(point: Vector3) -> void:
	_has_look_target = true
	_look_target_point = point


## Returns the head to neutral (facing the same way as the body).
func clear_look_target() -> void:
	_has_look_target = false


## Read by NPCAnimationComponent (and the perception debug panel) — same
## has_facing_target()-style pattern, a public getter instead of reaching
## into a private var across a node boundary.
func has_look_target() -> bool:
	return _has_look_target


func get_look_target_point() -> Vector3:
	return _look_target_point


## World point this character turns its body toward. Overrides
## face-move-direction while set. The body only turns; whether anything is
## worth turning toward is a decision, and decisions live in the controller.
func set_facing_target(point: Vector3) -> void:
	_has_facing_target = true
	_facing_target_point = point


## Returns to move-direction-only facing (the previous, only behaviour).
func clear_facing_target() -> void:
	_has_facing_target = false


## Whether the body currently has a facing target — read by the perception
## debug panel so "the body didn't turn" is distinguishable from "nothing
## asked it to."
func has_facing_target() -> bool:
	return _has_facing_target


## Turns the body to face _move_direction while moving; otherwise turns
## toward _facing_target_point if one is set (see set_facing_target()).
## Movement wins over a facing target by default: an NPC that is walking
## somewhere faces where it's walking, never a facing target — otherwise it
## would visibly walk sideways or backwards while "looking" elsewhere. The
## exception is _move_faces_direction == false (set_move_intent()'s
## face_direction param) — the flee backpedal case, where the body must
## move backward while still facing whatever set_facing_target() points at.
func _face_move_direction(delta: float) -> void:
	var target_angle: float
	if _move_direction.length() > 0.01 and _move_faces_direction:
		target_angle = atan2(_move_direction.x, _move_direction.z)
	elif _has_facing_target:
		var to_target := _facing_target_point - global_position
		var horizontal_to_target := Vector3(to_target.x, 0.0, to_target.z)
		if horizontal_to_target.length() < 0.01:
			return
		target_angle = atan2(horizontal_to_target.x, horizontal_to_target.z)
	else:
		return
	rotation.y = lerp_angle(rotation.y, target_angle, Smoothing.damp_factor(turn_smoothing, delta))


## Applies archetype's per-channel data (docs/npc_archetypes.md §3) as three
## independent steps — colour, gait, attention — so that replacing the
## colour step with a real mesh/material variant later touches only that
## step, not the other two or the archetype resource itself. No-op if
## archetype is unset.
func _apply_archetype() -> void:
	if not archetype:
		return

	# Silhouette & clothing (placeholder, §4): one flat material across the
	# authored body parts, so the whole rig reads as a single colour instead of
	# keeping its per-part textures. Component-owned geometry must not inherit
	# this prototype treatment by merely being a descendant of the NPC.
	var material := StandardMaterial3D.new()
	material.albedo_color = archetype.placeholder_color
	for mesh in _find_archetype_body_meshes(self):
		mesh.material_override = material

	# Gait: speed only. Posture/animation-set variation (also named by §3)
	# is future, delegated work (§6) — NPCAnimationComponent has one
	# idle<->walk blend and no per-archetype variants to select between.
	walk_speed *= archetype.walk_speed_multiplier

	# Attention: configures the sibling PerceptionComponent's own exports —
	# does not modify PerceptionComponent.gd itself.
	var perception := get_node_or_null("PerceptionComponent") as PerceptionComponent
	if perception:
		perception.vision_range = archetype.vision_range
		perception.vision_angle_deg = archetype.vision_angle_deg


## Recursively collects only body MeshInstance3Ds tagged with
## GROUP_ARCHETYPE_BODY_MESH. The rig nests those meshes several levels deep
## (player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/
## <part>), so hardcoding paths would break on a rig restructure. The opt-in
## is intentional: forgetting to tag a new body mesh leaves its native
## material visible, while a new non-body mesh is safe by default.
func _find_archetype_body_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D and child.is_in_group(GROUP_ARCHETYPE_BODY_MESH):
			found.append(child)
		found.append_array(_find_archetype_body_meshes(child))
	return found
