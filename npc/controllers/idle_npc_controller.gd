# =============================================================================
# idle_npc_controller.gd — IdleNPCController: wanders near its spawn point,
# freezes and follows the player with its gaze on noticing one, turns its body
# if the player lingers, and reacts to a nearby incident (NPC_REACTIONS.md §4:
# Flee, Freeze, Call, or — Patrolman only — Respond).
#
# WANDER IS DELIBERATELY DUMB: a random point in wander_radius, walk, pause,
# repeat, with a forward RayCast3D standing in for navigation. That ray is
# parented with call_deferred("add_child", ...) — a direct call fails here.
#
# GLANCE VERSUS TURN: the head always tracks a visible player; the body commits
# only past body_turn_delay AND body_turn_angle_deg. That interpretation
# belongs here, never in perception itself (see player_observation.gd).
#
# ALL REACTIONS LIVE IN THIS ONE CONTROLLER because only one decision-maker can
# own set_move_intent()/set_look_target() per frame. ReactionState pre-empts
# everything else in _decide(). Reactions are PROBABILISTIC, biased by
# NPCArchetypeData.flee_probability, never a per-archetype rule. The registry
# resolves lazily by group; there is deliberately NO catch-up replay of
# incidents predating this NPC noticing them.
#
# WITNESS CALL needs is_witness_caller, a human-owned Votive, and having
# actually seen the incident; the report is held PENDING for
# call_report_duration and can still be stopped by a knockdown or by the player
# closing in — which hands off into the SAME flee machine. The sibling
# VotiveProjector is driven from here and owns no timing of its own.
#
# TWO-PHASE FLEE: BACKING_AWAY is a fixed duration; RUNNING fixes its direction
# once and is gated by flee_far_distance, not by a clock.
#
# A MISSED SWING is the one stimulus that does NOT come through
# IncidentRegistry (player.gd's punch_missed): a visible act, not a fact about
# the city, so no Incident and no memory — one "?" or a reduced-probability
# roll into the same flee machine.
#
# WITNESS MEMORY: written on ANY sighting during an incident and on being
# knocked down, and held in ActorMemoryRegistry rather than on this node, so
# it outlives the NPC's own block streaming out. Still what one passer-by
# remembers, not what the city has on record. It ages out on a schedule set by
# how well this NPC saw — docs/architecture/npc_and_incidents.md.
#
# History: docs/postmortems/idle_npc_controller_history.md
# =============================================================================
extends NPCControllerBase
class_name IdleNPCController

enum State { IDLE, WALKING }

## NONE = ordinary wander/observe-player behaviour applies. The other four
## pre-empt it entirely for as long as they're active — see the file header.
## CALLING (docs/attribution.md section 7) replaces what used to be an
## instant, fully-attributed report on the spot: a caller now resolves an
## observation quality and holds a WitnessReport PENDING for
## call_report_duration before it actually commits — see _step_calling().
enum ReactionState { NONE, FLEEING, FROZEN, RESPONDING, CALLING }

## FLEEING's own two sub-phases (NPC_REACTIONS.md §4 extension). BACKING_AWAY
## is the witness realising the aggressor knows it saw something — it backs
## away while still watching the player; RUNNING is giving up on watching
## and just getting away. See _start_flee()/_step_flee_backing_away()/
## _step_flee_running().
enum FleePhase { BACKING_AWAY, RUNNING }


class IncidentVision:
	var distance: float = INF
	var angle_deg: float = 180.0
	var is_seen: bool = false
	var rejection: String = "no-perception"


class IncidentTelemetryEntry:
	var incident_id: int = 0
	var sequence: int = 0
	var in_hearing_range: int = 0
	var transmitting: int = 0
	## Reason label ("already-reacting", "knocked-down", "no-archetype") ->
	## how many NPCs were skipped for it — see _log_incident_rejection()'s
	## own comment on why these are counted, not printed by name.
	var skip_counts: Dictionary = {}
	var skip_total: int = 0

## Distance to the wander target that counts as "arrived."
const WANDER_ARRIVAL_RADIUS: float = 0.5
## How far ahead the obstacle raycast checks, metres.
const OBSTACLE_CHECK_DISTANCE: float = 1.5
## Height above the NPC's own origin the obstacle raycast casts from —
## roughly chest height, high enough to clear kerbs, low enough to catch
## most walls. Not derived from BodyMetrics: a single fixed offset is
## enough for a straight-ahead bump check, not worth a new getter.
const OBSTACLE_RAY_HEIGHT: float = 1.0
## CollisionLayers.OBSTACLE (wall only) — floor is what an NPC walks on,
## not an obstacle to walking.
const OBSTACLE_MASK: int = CollisionLayers.OBSTACLE
## _obstacle_ray's rest target_position — local +Z, the same "check what's
## ahead of the body's own facing" sense every other user of the ray relies
## on (wander, respond, the RUNNING flee phase).
const OBSTACLE_RAY_FORWARD: Vector3 = Vector3(0.0, 0.0, OBSTACLE_CHECK_DISTANCE)
## _obstacle_ray's target_position while BACKING_AWAY. The ray is fixed to
## the NPC's own local space, and during a backpedal the body's local +Z
## points AT the player (set_facing_target(), not the movement direction —
## see _face_move_direction()'s own comment on why), so the ordinary forward
## ray would be checking toward the threat instead of toward the ground the
## NPC is actually about to step onto. Local -Z is "behind the body," which
## during a backpedal is exactly the direction of travel.
const OBSTACLE_RAY_BACKWARD: Vector3 = Vector3(0.0, 0.0, -OBSTACLE_CHECK_DISTANCE)
const INCIDENT_TELEMETRY_PREFIX: String = "[WitnessTelemetry]"
const PATROL_PAIR_SLOT_ARRIVAL_DISTANCE: float = 0.4
const PATROL_PAIR_NOTICE_HOLD: float = 0.15

static var _next_telemetry_sequence: int = 1
static var _telemetry_entries: Array[IncidentTelemetryEntry] = []

@export_group("Wander")
## Radius of the random-point area around where this NPC started.
@export var wander_radius: float = 8.0
## Wander pace as a fraction of NPCBase.walk_speed — a stroll, not a
## commute. A feel value, tuned by eye.
@export var wander_speed_ratio: float = 0.6
## Seconds paused after reaching a wander point before picking the next
## one. A feel value, tuned by eye.
@export var wander_pause_time: float = 2.0

@export_group("Body Turn")
## How long the player must stay visible before the body — not just the
## head — commits to turning. A glance is cheap; turning your shoulders is
## a statement, and it should not fire on someone walking past. A feel
## value, tuned by eye.
@export var body_turn_delay: float = 0.5
## Yaw offset past which a head turn alone stops reading as attention. A
## feel value, tuned by eye.
@export var body_turn_angle_deg: float = 40.0

@export_group("Incident Reaction")
## Metres from an incident this NPC still reacts to it — "earshot," not
## sight: the reaction fires whether or not this NPC can currently see the
## player. A feel value, not per-archetype — NPC_REACTIONS.md ties reaction
## BIAS to archetype (§4, via flee_probability) but never hearing range.
@export var earshot_radius: float = 25.0
## Safety cap on the RUNNING phase alone (seconds), not the whole reaction
## any more — geometry can trap an NPC close to the threat with nowhere
## straight to run, so this guarantees RUNNING still ends eventually even if
## flee_far_distance is never actually covered. Generous on purpose: at
## flee_speed_ratio 1.0 and a typical walk_speed, covering flee_far_distance
## (default 80m) takes on the order of 8-15s in the open, so this stays a
## cap on a trapped NPC rather than the thing that normally ends RUNNING.
@export var flee_duration: float = 20.0
## Speed ratio during the RUNNING phase (phase 2) — faster than an ordinary
## wander pace on purpose; running away from a fight should read as more
## urgent than a stroll. Also the fastest of the two flee phases, on
## purpose — see backpedal_speed_ratio's own comment for why that has to be
## slower, not just different.
@export var flee_speed_ratio: float = 1.0
## Seconds spent frozen (staring at the incident) before returning to
## ordinary wander.
@export var freeze_duration: float = 4.0

@export_group("Missed Swing (visible act, not an incident)")
## Scale applied to the archetype's own flee_probability when this NPC sees
## the player throw a punch that connects with nobody. Below 1.0 because a
## miss is a weaker provocation than an incident: someone swung at the air,
## nobody went down, and the city has no record of it. The BIAS still comes
## from the archetype table (NPCArchetypeData.flee_probability), not from
## here — this file only says how much less a whiff is worth than the real
## thing, so retuning who is skittish stays a data edit.
@export_range(0.0, 1.0) var swing_flee_probability_scale: float = 0.5

@export_group("Flee — two phases (NPC_REACTIONS.md §4 extension)")
## Speed ratio during the BACKING_AWAY phase (phase 1) — deliberately slower
## than flee_speed_ratio: a witness backing away while still watching the
## threat is cautious, not yet sprinting. NPCAnimationComponent's locomotion
## blend is signed and widened to ANIM_BACKWARD/ANIM_RUN (see that file's own
## header), so the gap between this and flee_speed_ratio now also reads as a
## real clip change, not just a speed change: BACKING_AWAY's negative blend
## position plays the backward clip, RUNNING's speed_ratio at the outer
## positive edge plays the run clip. NPCBase itself has no speed tier above
## walk_speed either, so both phases still top out there.
@export var backpedal_speed_ratio: float = 0.45
## Fixed duration of the BACKING_AWAY phase — this task's own "фиксированная
## длительность... не по дистанции — по времени" requirement: unlike an
## earlier version, nothing here shortens it if the player closes distance
## or stops approaching mid-backpedal. The only early exits left are losing
## track of the player node entirely or backing into solid geometry — see
## _step_flee_backing_away().
@export var backpedal_duration: float = 2.0
## How far RUNNING must put this NPC from _flee_threat_position before the
## reaction ends — "far", this task's own words, "tens of metres, not five".
## Distance-gated on purpose, not duration-gated (see flee_duration's own
## comment on why that field is now a safety cap, not the primary limit).
##
## Raised 40 -> 80 after the H3/H4 playtest: at 40m a fleeing NPC was still
## comfortably on screen when it stopped and went back to wandering, which
## read as the panic wearing off rather than as escape. Someone running for
## their life leaves.
@export var flee_far_distance: float = 80.0
## Cosine threshold for "is the player's movement aimed at me" — the player
## walking somewhere else nearby must not read as approaching every witness
## in earshot (see the file's own "стоящий на месте игрок" requirement,
## extended here to "moving elsewhere" too). ~0.3 is roughly a 70-degree
## cone centred on the direction from the player to this NPC. A feel value.
## Also the gate _step_calling() uses to decide whether a mid-transmission
## witness abandons the report and flees — see _abort_call_for_flee().
@export var approach_alignment_threshold: float = 0.3

@export_group("Respond (Patrolman, NPC_REACTIONS.md §4)")
## A dispatched Patrolman RUNS — someone was assaulted and the city was
## told, which is not an occasion for a brisk walk. 1.0 is the run point of
## NPCAnimationComponent's own blend space and the same value
## flee_speed_ratio uses, so the clip matches the intent rather than
## playing a fast walk. Still a fraction of walk_speed like every other
## speed knob here: NPCBase has no second base speed tier above walk_speed
## (unlike the player's own walk/run split), so walk_speed*1.0 is the
## ceiling wander/flee already live under.
@export var respond_speed_ratio: float = 1.0
## Distance from the target at which a responding Patrolman stops, instead
## of closing all the way to WANDER_ARRIVAL_RADIUS (0.5m) — investigating a
## scene reads as holding back a couple of metres, not walking up nose to
## nose with whoever/whatever is there. A feel value.
@export var respond_arrival_distance: float = 2.0

@export_group("Patrol Pair")
## Robot's lateral offset from its human leader.
@export var patrol_pair_spacing: float = 1.5
## Gap at which the human leader stops and waits for its partner.
@export var patrol_pair_wait_distance: float = 4.0
## Gap at which a waiting leader resumes, providing distance hysteresis.
@export var patrol_pair_resume_distance: float = 2.5
## Robot catch-up pace as a fraction of NPCBase.walk_speed.
@export var patrol_pair_catchup_speed_ratio: float = 1.0
## Delay before one unresolved authored partner produces a single warning.
@export var patrol_pair_search_timeout: float = 3.0

@export_group("Incident Registry")
## Seconds to keep retrying the group lookup before giving up and warning
## once — same idiom and same default as
## PatrolDroneController.incident_registry_search_timeout.
@export var incident_registry_search_timeout: float = 5.0

@export_group("Debug")
## Event-only trace for the witness decision path. On by default while the
## vertical slice is being judged; disable only when ordinary playtest output
## needs to be quiet. This does not alter any reaction probabilities.
@export var incident_telemetry_enabled: bool = true

@export_group("Witness Observation Quality (attribution.md §2)")
## Beyond this distance the ceiling is SILHOUETTE — the maximum achievable
## once a witness is confirmed to have actually seen the incident at all
## (see _is_incident_in_vision_cone()). Thresholds are @export, not
## constants, per attribution.md §7's own instruction: they are feel/scale
## values, not derived numbers.
##
## ALL THREE MUST FIT INSIDE THE WITNESS ENVELOPE, and that is what set the
## current values. The only calling archetype is Clerk, whose
## PerceptionComponent.vision_range is 16 m, so nothing beyond 16 m ever
## reaches this ladder at all. The old thresholds (30 / 10 / 5) put SILHOUETTE
## past 30 m and made the top rung unreachable by construction — measured, and
## the reason attribution.md §7's case C failed from the day it was written.
## Retuned 2026-09-04 (Stan: lower the ceilings rather than raise the vision)
## so every rung has a band for a mechanical observer: IRIS <= 3, FACE 3-6,
## EQUIPMENT 6-11, SILHOUETTE 11-16. Humans share the same distances but cap
## at FACE. Raising Clerk's vision_range means retuning these too.
@export var witness_ceiling_equipment_distance: float = 11.0
## Beyond this distance (and within witness_ceiling_equipment_distance) the
## ceiling is EQUIPMENT.
@export var witness_ceiling_face_distance: float = 6.0
## Beyond this distance (and within witness_ceiling_face_distance) the
## ceiling is FACE; within it, IRIS for mechanical actors and FACE for humans.
@export var witness_ceiling_iris_distance: float = 3.0

@export_group("Witness Report (attribution.md §6/§7)")
## Seconds until a PENDING WitnessReport commits — "time until transmission
## completes", not "time to kill the witness" (attribution.md §6's own
## distinction: interrupting is one way to spend this window, not the only
## one). Not tuned per stratum in this slice, per this task's own scope.
@export var call_report_duration: float = 3.0

## NPCControllerBase resolves _actor as ActorBase (shared with
## PatrolDroneController/DroneBase); this controller only ever drives an
## NPCBase and uses NPC-only facing-target methods ActorBase doesn't
## declare, hence its own narrower reference, cast once in _ready().
var _npc: NPCBase = null

## Resolved once in _ready(), alongside _npc — sibling node, child of the
## same NPC. Null if the NPC has no PerceptionComponent (not every NPC will
## necessarily have one forever, e.g. background crowd fillers later).
var _perception: PerceptionComponent = null

## Resolved once in _ready(), same sibling-lookup pattern as _perception.
## Drives the visible half of a CALLING reaction (_start_calling()/
## _commit_witness_report()) and blacks out while knocked down (_decide()'s
## own guard) — see votive_projector.gd's own header for why this node owns
## no timing or decision logic of its own.
var _votive: VotiveProjector = null

## ComicEffectSystem, resolved lazily by group — the same scheme this file
## already uses for IncidentRegistry, and for the same reason: a static
## scene instance never receives a WorldContext. Null is a silent no-op;
## the floating word is decoration on top of a reaction, never its trigger.
var _comic_effects: ComicEffectSystem = null

## True for as long as this NPC has been continuously knocked down — set the
## instant _decide() sees is_knocked_down(), cleared (once) the frame it
## first sees the opposite. Exists purely so _votive.go_idle() fires exactly
## once on getting up, not every frame afterward — calling go_idle() every
## frame while NOT knocked down would stomp a legitimately TRANSMITTING
## state the instant a later CALLING reaction started.
var _was_knocked_down: bool = false

## Seconds the player has been continuously visible. Reset to 0 the instant
## the player is no longer seen — this is "how long has this sighting
## lasted," not a running total.
var _visible_time: float = 0.0

## ActorMemoryRegistry, resolved lazily by group — the same "a static scene
## instance never receives a WorldContext" situation _incident_registry is in,
## and the same fix. Where this NPC's memory of the player actually lives.
##
## It used to be a bool on this controller, and that bool was gone the instant
## the NPC was: "увидел — запомнил" only held until the block streamed out.
## The behaviour it drives is unchanged (see _decide()) — only the storage
## moved. Still NOT IncidentRegistry: that registry is what the CITY has on
## record, this is what one passer-by personally remembers, and the two have
## different lifetimes and no derivation between them.
var _memory_registry: ActorMemoryRegistry = null

## The player node this controller is subscribed to punch_missed on,
## resolved lazily by group in _try_connect_player_swing() — the same
## "a static scene instance never receives a WorldContext" situation
## _incident_registry is in, and the same fix. Held only to keep the
## connection check cheap; nothing reads it otherwise.
var _swing_source: Node = null

var _wander_state: State = State.IDLE
## Centre of the wander area — captured once in _ready(), same "anchored to
## where it started" convention as PatrolDroneController's patrol square.
var _wander_origin: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _pause_timer: float = 0.0
## Created in code, parented to the NPC body (not this controller — a
## RayCast3D needs a Node3D ancestor for its transform to mean anything).
## Not a scene node: keeps this commit to a script change, no npc.tscn edit.
var _obstacle_ray: RayCast3D = null

## Current incident reaction, if any — see ReactionState's own comment.
var _reaction_state: ReactionState = ReactionState.NONE
## Seconds spent in the current reaction state — reset to 0 whenever a new
## reaction starts, compared against flee_duration/freeze_duration.
var _reaction_timer: float = 0.0
## The fixed point this FLEEING reaction is running from — an incident's
## position (_start_flee() from _on_incident_reported()/
## _abort_call_for_flee()) or the player's own position at the moment
## memory-triggered flight starts (_decide()'s _remembers_player() branch).
## Set once, at _start_flee(), and never moved afterward — see
## _set_flee_direction_from_threat()'s own comment.
var _flee_threat_position: Vector3 = Vector3.ZERO
## Away-from-_flee_threat_position direction driving RUNNING's movement —
## recomputed once whenever _enter_flee_phase() actually turns into RUNNING
## (NPC_REACTIONS.md §4 extension: "направление берётся один раз при
## развороте", never per frame). BACKING_AWAY instead recomputes this every
## frame toward the player's own live position — see
## _step_flee_backing_away() — since backing away has to actually track a
## moving threat; only the final RUNNING direction is fixed.
var _flee_direction: Vector3 = Vector3.ZERO
## Which of FleePhase this FLEEING reaction is currently in — see
## _start_flee()/_enter_flee_phase().
var _flee_phase: FleePhase = FleePhase.RUNNING
## Seconds spent in the CURRENT flee phase — reset on every phase change,
## compared against backpedal_duration (BACKING_AWAY) or flee_duration, now
## a per-phase safety cap rather than the whole reaction's own timer
## (RUNNING — see _step_flee_running()).
var _flee_phase_timer: float = 0.0
## Where a RESPONDING (Patrolman-only) NPC is walking to.
var _respond_target: Vector3 = Vector3.ZERO
## True once a RESPONDING Patrolman has closed to respond_arrival_distance
## and stopped — see _step_respond(). Distinguishes "still walking there"
## from "arrived and holding" for get_debug_action_text() and gates the
## arrival hold's own timer.
var _respond_arrived: bool = false

## Authored partner resolved lazily from ActorBase's existing discovery group.
## No new registry owns patrol formation.
var _patrol_partner: NPCBase = null
var _patrol_partner_controller: IdleNPCController = null
var _patrol_partner_search_time: float = 0.0
var _warned_missing_patrol_partner: bool = false
var _patrol_pair_invalid: bool = false
var _leader_waiting_for_partner: bool = false
## Brief notification from the partner that it currently sees the player.
## It synchronizes stopping without borrowing the partner's observation data.
var _patrol_pair_notice_timer: float = 0.0

## Resolved lazily via a group lookup, retried from _decide() until it
## succeeds — same reasoning and same pattern as
## PatrolDroneController._incident_registry; see that file's header for why
## a single _ready() call isn't enough for a static scene instance.
var _incident_registry: IncidentRegistry = null
## Seconds spent so far retrying the lookup — compared against
## incident_registry_search_timeout to decide when to warn.
var _incident_registry_search_time: float = 0.0
## Set once the timeout warning has fired, so it fires exactly once per
## instance instead of every frame the registry stays unresolved.
var _warned_missing_incident_registry: bool = false

## The report currently being transmitted (ReactionState.CALLING), or null
## outside that state — see _start_calling()/_commit_witness_report()/
## _cancel_active_witness_report(). Cleared the instant it leaves PENDING.
var _current_witness_report: WitnessReport = null
## The incident _current_witness_report is about — kept alongside it purely
## so _commit_witness_report() has a position to hand _call_it_in(), which
## takes an Incident, not a WitnessReport (see that method's own header on
## why it still reports fully attributed).
var _pending_incident: Incident = null

## Mirrors the inputs _resolve_observation_level() used for the current/last
## report — debug-only, read by the perception debug panel so it can show
## why a witness got the level it got (attribution.md §7's debug panel
## requirement) without WitnessReport itself carrying scaffolding fields the
## design doesn't call for.
var _debug_witness_distance: float = -1.0
## Always true by the time a report is actually built — see
## _is_incident_in_vision_cone(), which gates entry into CALLING before
## _build_witness_report() ever runs. Kept as its own field (rather than
## assumed) so the debug panel states the fact plainly instead of implying
## it, matching attribution.md §7's own panel format ("in FOV").
var _debug_witness_in_cone: bool = false
## Distance-ceiling result — see _distance_ceiling(). Currently always equal
## to the report's own observation_level: attention (attribution.md §2) is
## not applied this iteration, since this build has no mechanic for either
## of its real triggers (talking, looking into one's own Votive) — see
## _resolve_observation_level()'s own comment. Kept as a separate field
## anyway, matching the design's panel format, so it starts differing again
## the moment a real attention trigger lands, with no panel change needed.
var _debug_witness_ceiling: WitnessReport.ObservationLevel = WitnessReport.ObservationLevel.NONE


func _ready() -> void:
	super._ready()
	_npc = _actor as NPCBase
	if not _npc:
		return
	for child in _npc.get_children():
		if child is PerceptionComponent:
			_perception = child

	## Not the get_children() scan above: VotiveProjector now sits under a
	## BoneAttachment3D bound to the head bone (votive_projector.gd's own
	## header), not directly under _npc, so it is no longer a direct child to
	## scan for by type. Scene-unique name (%) lookup finds it regardless of
	## nesting depth — same fix npc_base.gd's/player.gd's own _votive
	## resolution needed for the same reason.
	_votive = _npc.get_node_or_null("%VotiveProjector") as VotiveProjector

	_wander_origin = _npc.global_position
	_obstacle_ray = RayCast3D.new()
	_obstacle_ray.position = Vector3(0.0, 0.9, 0.0)
	_obstacle_ray.target_position = OBSTACLE_RAY_FORWARD
	_obstacle_ray.collision_mask = OBSTACLE_MASK
	_npc.call_deferred("add_child", _obstacle_ray)

	_wander_state = State.IDLE
	_pause_timer = wander_pause_time

	## Very likely to fail here (see the file header on why) — kept anyway,
	## harmless, and resolves immediately in the rare case ordering ever
	## does favour this instance. _decide() is what actually guarantees
	## resolution, same split PatrolDroneController uses.
	_try_resolve_incident_registry()


func _decide(delta: float) -> void:
	if not _npc:
		return
	_patrol_pair_notice_timer = maxf(_patrol_pair_notice_timer - delta, 0.0)
	_try_resolve_patrol_partner(delta)

	## A knocked-down body isn't deciding anything — it can't move, and
	## NPCBase already ignores movement intent while down (see its own
	## _physics_process()). Calling into set_move_intent()/set_look_target()
	## regardless would just be noise; skipping outright is what "the
	## controller stops deciding" (npc_base.gd's take_hit() comment) means.
	if _npc.is_knocked_down():
		## Suppressing a witness is itself an incident (attribution.md §6) —
		## nothing special needed for THAT, the punch that knocked this NPC
		## down already reported through player.gd's own punch_landed path.
		## What this guard covers is the OTHER half: a report already in
		## flight when the suppression lands must not silently keep counting
		## down toward COMMITTED while the witness is on the ground.
		_was_knocked_down = true
		## Being put on the ground is first-hand knowledge and must not be
		## lost to _on_incident_reported()'s own knocked-down guard, which
		## returns BEFORE the memory is ever written — the victim is
		## down in the same frame its own assault is reported, so every
		## bystander used to remember the player while the one NPC with the
		## best reason to ran got up and stared. Set here rather than
		## there: this needs no cone maths and no incident at all, and it
		## also covers a punch from a player this NPC never saw coming.
		_record_memory(WitnessReport.ObservationLevel.FACE)
		_cancel_active_witness_report()
		if _votive:
			_votive.go_dark()
		return

	if _was_knocked_down:
		## Just got up — one-shot transition back to the visible baseline.
		## See _was_knocked_down's own comment for why this can't just be
		## "call go_idle() every frame we're not knocked down".
		_was_knocked_down = false
		if _votive:
			_votive.go_idle()

	_try_join_partner_response()

	_try_connect_player_swing()

	if not _incident_registry:
		_try_resolve_incident_registry()
	if not _incident_registry:
		_incident_registry_search_time += delta
		if not _warned_missing_incident_registry \
				and _incident_registry_search_time >= incident_registry_search_timeout:
			_warned_missing_incident_registry = true
			push_warning(
				"[IdleNPCController] %s: IncidentRegistry not found after %.1fs — "
				% [_npc.name, _incident_registry_search_time]
				+ "this NPC will never react to an incident"
			)

	if _reaction_state != ReactionState.NONE:
		_step_reaction(delta)
		return

	if not _perception:
		_decide_wander(delta)
		return

	var observation := _perception.observe_player()
	if not observation.is_seen:
		_visible_time = 0.0
		_npc.clear_look_target()
		_npc.clear_facing_target()
		if _patrol_pair_notice_timer > 0.0 and _is_patrol_pair_operational():
			_npc.set_move_intent(Vector3.ZERO, 0.0)
			return
		_decide_wander(delta)
		return

	if _remembers_player():
		## This NPC witnessed an incident and still remembers — no fresh
		## incident needed, just seeing the player again is enough (this
		## task's own "сразу бежит, без всякого инцидента" requirement).
		## allow_backpedal=false: this isn't a fresh startle that might still
		## be worth watching first, it's recognition — straight to RUNNING.
		_start_flee(observation.position, false)
		return

	## Stops in place the instant it notices someone — see the file header.
	_npc.set_move_intent(Vector3.ZERO, 0.0)
	_notify_patrol_partner_player_seen()
	_npc.set_look_target(observation.position)
	_visible_time += delta

	## COMBAT is already a statement (see PlayerState.Stance's own comment)
	## — a raised weapon doesn't earn the same benefit of the doubt as
	## someone walking past, so it skips the glance/turn gate entirely and
	## commits the body immediately. PEACE keeps the original behaviour:
	## once the body starts turning, observation.angle_deg trends toward 0
	## as the NPC's facing catches up with the player — so that condition
	## naturally stops re-triggering mid-turn without needing a separate
	## "committed" flag. That is deliberate: it reads as finishing the turn
	## it already started, not as flickering at the threshold.
	if observation.stance == PlayerState.Stance.COMBAT:
		_npc.set_facing_target(observation.position)
	elif _visible_time >= body_turn_delay and observation.angle_deg > body_turn_angle_deg:
		_npc.set_facing_target(observation.position)


## Read by the perception debug panel — see _visible_time's own comment.
func get_visible_time() -> float:
	return _visible_time


## Debug-only: a short word plus an optional one-line reason, joined by
## "\n" — read by NPCBase's DebugActionLabel (debug_show_action), duck-typed
## via has_method() so NPCBase never depends on this controller by name or
## class (see NPCBase._debug_action_source's own comment). Reads only state
## this controller already computes for its own decisions (_reaction_state,
## _wander_state, _visible_time); nothing here exists solely to answer this
## question.
##
## Vocabulary: WALK, IDLE, LOOK, FLEE, CALL — DOWN is NPCBase's own
## knockdown flag and is resolved there without ever reaching this method.
## FROZEN and RESPONDING deliberately share a word with the ordinary
## "looking at the player" / "wandering" cases they look identical to from
## outside (a stare, a walk toward a point) — the reason line is what tells
## them apart, not a seventh/eighth word; the label is meant to be read at a
## glance, not parsed like a sentence.
func get_debug_action_text() -> String:
	match _reaction_state:
		ReactionState.FLEEING:
			return "FLEE\nbackpedal" if _flee_phase == FleePhase.BACKING_AWAY else "FLEE"
		ReactionState.FROZEN:
			return "LOOK\nincident"
		ReactionState.RESPONDING:
			return "LOOK\nresponding" if _respond_arrived else "WALK\nresponding"
		ReactionState.CALLING:
			return "CALL\nwitness"

	if _visible_time > 0.0:
		return "LOOK\nsaw"

	return "WALK" if _wander_state == State.WALKING else "IDLE"


## Human-readable state for debug tooling (perception_debug_panel.gd), same
## convention as PatrolDroneController.get_state_name().
func get_state_name() -> String:
	return State.keys()[_wander_state]


## Human-readable incident-reaction state for debug tooling — "NONE" outside
## a reaction, same convention as get_state_name() above.
func get_reaction_state_name() -> String:
	return ReactionState.keys()[_reaction_state]


# ── Witness/report debug getters (attribution.md §7's debug panel) ─────────
# Read by perception_debug_panel.gd. Small single-purpose getters, same
# encapsulation convention get_alert_memory_remaining()/is_spotlight_active()
# use on PatrolDroneController, rather than exposing _current_witness_report
# or the private _debug_witness_* fields directly.

func has_active_witness_report() -> bool:
	return _current_witness_report != null


func get_witness_report_status_name() -> String:
	return WitnessReport.Status.keys()[_current_witness_report.status] \
			if _current_witness_report else "n/a"


## Seconds left before a PENDING report commits, or -1.0 outside CALLING —
## same "-1.0 means n/a" convention get_alert_memory_remaining() uses.
func get_witness_report_remaining() -> float:
	if _reaction_state != ReactionState.CALLING:
		return -1.0
	return maxf(0.0, call_report_duration - _reaction_timer)


## Distance the CURRENT/LAST report's observation quality was resolved
## against — see _debug_witness_distance's own comment.
func get_witness_distance() -> float:
	return _debug_witness_distance


## "true"/"false" (attribution.md §7's own panel format uses "in FOV",
## lowercase true/false, not this panel's usual YES/no convention) — see
## _debug_witness_in_cone's own comment on why this is always true by the
## time there's a report to describe at all.
func get_witness_in_cone_text() -> String:
	return "true" if _debug_witness_in_cone else "false"


## Distance-ceiling result — see _debug_witness_ceiling's own comment on why
## this currently always matches get_witness_observation_level_name().
func get_witness_ceiling_name() -> String:
	return WitnessReport.ObservationLevel.keys()[_debug_witness_ceiling]


func get_witness_observation_level_name() -> String:
	return WitnessReport.ObservationLevel.keys()[_current_witness_report.observation_level] \
			if _current_witness_report else "n/a"


func _decide_wander(delta: float) -> void:
	if _is_patrol_pair_operational():
		if _is_patrol_pair_follower():
			_step_patrol_pair_follower(patrol_pair_catchup_speed_ratio)
			return
		if _should_patrol_leader_wait():
			_npc.set_move_intent(Vector3.ZERO, 0.0)
			_wander_state = State.IDLE
			return
	else:
		_leader_waiting_for_partner = false

	match _wander_state:
		State.IDLE:
			_npc.set_move_intent(Vector3.ZERO, 0.0)
			_pause_timer -= delta
			if _pause_timer <= 0.0:
				_pick_new_wander_point()
				_wander_state = State.WALKING
		State.WALKING:
			_step_wander()


func _step_wander() -> void:
	var to_target := _wander_target - _npc.global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < WANDER_ARRIVAL_RADIUS:
		_start_pause()
		return

	if _obstacle_ray and _obstacle_ray.is_colliding():
		## Blocked ahead, no navigation to route around it — retarget
		## immediately and keep going next frame, same as
		## PatrolDroneController's patrol does on arrival. No pause: that's
		## reserved for reaching an actual destination, not bouncing off a
		## wall.
		_pick_new_wander_point()
		return

	_npc.set_move_intent(to_target.normalized(), wander_speed_ratio)


func _start_pause() -> void:
	_npc.set_move_intent(Vector3.ZERO, 0.0)
	_wander_state = State.IDLE
	_pause_timer = wander_pause_time


## Random point in a radius around a captured origin — a disk, not a
## square: unlike PatrolDroneController's local patrol square (rotated to
## a start yaw, which a circular area has no equivalent of), the spec here
## says "radius," so sqrt(randf()) keeps the distribution uniform over the
## disk's area instead of bunching toward the centre.
func _pick_new_wander_point() -> void:
	var angle := randf_range(0.0, TAU)
	var r := wander_radius * sqrt(randf())
	var offset := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	_wander_target = _wander_origin + offset


## Resolves the authored reciprocal Patrolman pair through ActorBase's existing
## discovery group. Missing actors keep retrying for future streaming; malformed
## authored relationships warn once and stay solo.
func _try_resolve_patrol_partner(delta: float) -> void:
	if _npc.patrol_partner_id == &"" or _patrol_pair_invalid:
		return
	if is_instance_valid(_patrol_partner) and is_instance_valid(_patrol_partner_controller):
		return
	_patrol_partner = null
	_patrol_partner_controller = null
	for node in get_tree().get_nodes_in_group(ActorBase.GROUP_PERCEIVED_ACTOR):
		var candidate := node as NPCBase
		if candidate == null or candidate == _npc:
			continue
		if candidate.get_actor_id() != _npc.patrol_partner_id:
			continue
		if not _is_valid_patrol_partner(candidate):
			_patrol_pair_invalid = true
			push_warning(
				"[IdleNPCController] %s: invalid patrol pair with '%s'" % [
					_npc.name, candidate.name,
				]
			)
			return
		var candidate_controller := _find_idle_controller(candidate)
		if candidate_controller == null:
			_patrol_pair_invalid = true
			push_warning(
				"[IdleNPCController] %s: partner '%s' has no IdleNPCController" % [
					_npc.name, candidate.name,
				]
			)
			return
		_patrol_partner = candidate
		_patrol_partner_controller = candidate_controller
		return

	_patrol_partner_search_time += delta
	if not _warned_missing_patrol_partner \
			and _patrol_partner_search_time >= patrol_pair_search_timeout:
		_warned_missing_patrol_partner = true
		push_warning(
			"[IdleNPCController] %s: patrol partner '%s' not found after %.1fs" % [
				_npc.name, _npc.patrol_partner_id, _patrol_partner_search_time,
			]
		)


func _is_valid_patrol_partner(candidate: NPCBase) -> bool:
	if candidate.patrol_partner_id != _npc.get_actor_id():
		return false
	if _npc.archetype == null or candidate.archetype == null:
		return false
	if candidate.archetype != _npc.archetype or not _npc.archetype.responds_by_approaching:
		return false
	return (
		_npc.nature == ActorBase.Nature.HUMAN
		and candidate.nature == ActorBase.Nature.ROBOT
	) or (
		_npc.nature == ActorBase.Nature.ROBOT
		and candidate.nature == ActorBase.Nature.HUMAN
	)


func _find_idle_controller(actor: NPCBase) -> IdleNPCController:
	for child in actor.get_children():
		if child is IdleNPCController:
			return child as IdleNPCController
	return null


func _is_patrol_pair_operational() -> bool:
	return is_instance_valid(_patrol_partner) \
			and is_instance_valid(_patrol_partner_controller) \
			and not _npc.is_knocked_down() \
			and not _patrol_partner.is_knocked_down()


func _is_patrol_pair_follower() -> bool:
	return _npc.nature == ActorBase.Nature.ROBOT


func _should_patrol_leader_wait() -> bool:
	var gap := _npc.global_position.distance_to(_patrol_partner.global_position)
	if _leader_waiting_for_partner:
		if gap <= patrol_pair_resume_distance:
			_leader_waiting_for_partner = false
	else:
		_leader_waiting_for_partner = gap > patrol_pair_wait_distance
	return _leader_waiting_for_partner


## Moves the robot toward a lateral slot based on the human leader's current
## facing. The slot is recomputed continuously, so turns remain a formation
## rather than two independent destinations.
func _step_patrol_pair_follower(speed_ratio: float) -> void:
	var slot := _get_patrol_pair_slot()
	var to_slot := slot - _npc.global_position
	to_slot.y = 0.0
	if to_slot.length() <= PATROL_PAIR_SLOT_ARRIVAL_DISTANCE:
		_npc.set_move_intent(Vector3.ZERO, 0.0)
		_wander_state = State.IDLE
		return
	if _obstacle_ray and _obstacle_ray.is_colliding():
		_npc.set_move_intent(Vector3.ZERO, 0.0)
		_wander_state = State.IDLE
		return
	_npc.set_move_intent(to_slot.normalized(), speed_ratio)
	_wander_state = State.WALKING


func _get_patrol_pair_slot() -> Vector3:
	var forward := _patrol_partner.get_facing_direction()
	var right := Vector3(forward.z, 0.0, -forward.x).normalized()
	return _patrol_partner.global_position + right * patrol_pair_spacing


func _notify_patrol_partner_player_seen() -> void:
	if not _is_patrol_pair_operational():
		return
	_patrol_partner_controller._receive_patrol_partner_player_seen()


func _receive_patrol_partner_player_seen() -> void:
	_patrol_pair_notice_timer = PATROL_PAIR_NOTICE_HOLD
	if _reaction_state == ReactionState.NONE and not _npc.is_knocked_down():
		_npc.set_move_intent(Vector3.ZERO, 0.0)


## Rejoins an active response after an ordinary get-up or late pair resolve.
## The partner shares only the destination/state; observation quality remains
## local to each controller.
func _try_join_partner_response() -> void:
	if _reaction_state != ReactionState.NONE or not _is_patrol_pair_operational():
		return
	if _patrol_partner_controller._reaction_state != ReactionState.RESPONDING:
		return
	_start_responding(_patrol_partner_controller._respond_target, false)


# ── Incident reaction (NPC_REACTIONS.md §4) ─────────────────────────────────

## Retried from _decide() until it succeeds — see the file header on why a
## single _ready() call isn't enough for a static scene instance. Idempotent
## past the first success. No catch-up query on resolve, deliberately unlike
## PatrolDroneController's _check_existing_incidents() — see the file header
## on why a stale incident shouldn't make an NPC flinch now.
func _try_resolve_incident_registry() -> void:
	_try_resolve_memory_registry()
	if _incident_registry:
		return
	var found := get_tree().get_first_node_in_group(
		IncidentRegistry.GROUP_INCIDENT_REGISTRY
	) as IncidentRegistry
	if not found:
		return
	_incident_registry = found
	_incident_registry.incident_reported.connect(_on_incident_reported)


## Same lazy-by-group resolution, called from the same place, and nothing
## subscribes: this registry is asked questions, it does not announce.
func _try_resolve_memory_registry() -> void:
	if _memory_registry:
		return
	_memory_registry = get_tree().get_first_node_in_group(
		ActorMemoryRegistry.GROUP_ACTOR_MEMORY_REGISTRY
	) as ActorMemoryRegistry


## Whether this NPC still remembers the player. A question now rather than a
## field: the answer ages out on its own schedule inside the registry, so a
## caller never has to know a memory can expire.
##
## False when the registry has not resolved yet, which is the honest reading —
## an NPC that cannot reach its own memory has none to act on, and _decide()
## falls through to ordinary observation exactly as it did before any of this.
func _remembers_player() -> bool:
	if _memory_registry == null or _npc == null:
		return false
	var player_id := _player_actor_id()
	if player_id == &"":
		return false
	return _memory_registry.remembers(_npc.get_actor_id(), player_id)


## Files what this NPC just learned about the player. Silent no-op when the
## registry is not up yet or the player carries no id — the same "unset is a
## no-op" shape the rest of this controller uses, and a dropped memory is a
## better failure than a crash in a bystander's decision layer.
func _record_memory(level: WitnessReport.ObservationLevel) -> void:
	if _memory_registry == null or _npc == null:
		return
	var player_id := _player_actor_id()
	if player_id == &"":
		return
	_memory_registry.remember(_npc.get_actor_id(), player_id, level)


## The player's stable id, resolved by group at the call site — the same
## lookup _call_it_in() already does, and for the same reason: this
## controller never receives a WorldContext.
func _player_actor_id() -> StringName:
	var player_node := get_tree().get_first_node_in_group("player")
	if not (player_node and player_node.has_method(&"get_actor_id")):
		return &""
	return StringName(player_node.call(&"get_actor_id"))


## Subscribes to the player's punch_missed once the player node exists —
## same lazy-by-group scheme as _try_resolve_incident_registry() above, for
## the same bootstrap-ordering reason. Deliberately NOT routed through
## IncidentRegistry: a swing that hit nothing is not a fact the city holds,
## so it has no business travelling on the channel that survives saves and
## streaming. The player is found by the "player" group, the same lookup
## _call_it_in() and _is_player_approaching() already use.
func _try_connect_player_swing() -> void:
	## is_instance_valid(), not a plain null check: this covers both "never
	## resolved" and "the node it was connected to has since been freed",
	## which a stored reference alone cannot tell apart.
	if is_instance_valid(_swing_source):
		return
	var player_node := get_tree().get_first_node_in_group("player")
	if not (player_node and player_node.has_signal(&"punch_missed")):
		return
	_swing_source = player_node
	player_node.connect(&"punch_missed", _on_player_punch_missed)


## The one entry point for "the player swung at nothing while I was looking."
## A local observable event, gone the moment it is handled: no Incident, no
## WitnessReport, no memory — witnessing an assault is what earns
## a permanent grudge, and nobody was assaulted here.
##
## Gated on this NPC actually seeing the player RIGHT NOW, through the
## ordinary PerceptionComponent observation (range + cone + line of sight) —
## no separate geometry, so an NPC facing away or round a corner saw nothing
## and reacts to nothing. A reaction already in progress, or a body on the
## ground, wins outright: a whiff is the weakest stimulus in the file and
## must never interrupt a transmission, a flee or a knockdown.
##
## Exactly one word per noticed swing, never both: a rolled Flee already
## spawns npc_flee from _start_flee(), and stacking "?" on top of "RUN" over
## one head in one frame is the same double-word mistake npc_transmit's
## placement exists to avoid (see CLAUDE.md's ComicEffectSystem entry). "?"
## is what "noticed it and stayed put" looks like; RUN says more, and says
## it instead.
func _on_player_punch_missed(swing_position: Vector3) -> void:
	if not _npc or not _perception:
		return
	if _npc.is_knocked_down():
		return
	if _reaction_state != ReactionState.NONE:
		return

	var observation := _perception.observe_player()
	if not observation.is_seen:
		return

	if _npc.archetype \
			and randf() < _npc.archetype.flee_probability * swing_flee_probability_scale:
		## allow_backpedal left at its default rather than forced either
		## way: _start_flee()'s own _is_player_approaching() gate is the
		## right judge here and, since punching requires standing still
		## (player.gd's punch_max_speed), it will normally answer "not
		## approaching" and send this straight to RUNNING. Left to that gate
		## anyway, so a swing thrown mid-slide (should punch_max_speed ever
		## be relaxed) gets the backpedal without this line changing.
		_start_flee(swing_position)
		return

	_try_spawn_comic_effect(&"npc_swing_noticed")


## Resolves ComicEffectSystem on first use and asks it for one word above
## this NPC. Deliberately not routed through NPCBase: the body spawns the
## words it owns (knockdown, death), the decision layer spawns the ones it
## owns (flee, freeze, call), and neither learns about the other's. The
## system owns the distance gate and the active-count cap, so there is
## nothing to check here beyond "does the system exist yet".
func _try_spawn_comic_effect(id: StringName) -> void:
	if _comic_effects == null:
		_comic_effects = get_tree().get_first_node_in_group(
			ComicEffectSystem.GROUP_COMIC_EFFECT_SYSTEM
		) as ComicEffectSystem
	if _comic_effects and _npc:
		_comic_effects.try_spawn(id, _npc.global_position, _npc)


## Rolls this NPC's reaction to a live incident report — see the file header
## for the priority/pre-emption rules and why this is probabilistic rather
## than a fixed per-archetype rule.
func _on_incident_reported(incident: Incident) -> void:
	if not _npc:
		return
	var telemetry := _begin_incident_telemetry(incident)
	if _npc.is_knocked_down():
		_log_incident_rejection(telemetry, "SKIP knocked-down")
		return
	if _reaction_state != ReactionState.NONE:
		## Already reacting to something — a second, unrelated incident
		## doesn't interrupt or restart the current one. Keeps the state
		## machine simple; nothing in NPC_REACTIONS.md §4 asks for
		## interruption.
		_log_incident_rejection(telemetry, "SKIP already-reacting")
		return
	if not _npc.archetype:
		## No archetype, no reaction bias to roll against — same "unset is a
		## no-op" contract NPCBase._apply_archetype() already uses.
		_log_incident_rejection(telemetry, "SKIP no-archetype")
		return

	var vision := _evaluate_incident_vision(incident)
	## Two separate channels, NPC_REACTIONS.md §4 / Incident.Source.
	##
	## earshot_radius is this NPC's OWN noticing range and gates the whole
	## ordinary crowd reaction — a bystander does not learn about a mugging
	## across town, and that stays exactly as it was.
	##
	## A committed Votive report is the other channel: it reached the city,
	## so a responding archetype (Patrolman) is dispatched to it from any
	## distance. This is the ONLY bypass — a dispatched Patrolman still runs
	## the same _start_responding() path below, and no ordinary archetype
	## gets one, so Flee/Freeze/Call remain hearing-bound.
	var dispatched: bool = incident.source == Incident.Source.WITNESS_REPORT \
			and _npc.archetype.responds_by_approaching
	if vision.distance > earshot_radius and not dispatched:
		return
	telemetry.in_hearing_range += 1

	if vision.is_seen:
		## NPC_REACTIONS.md §4 extension: witnessing an incident at all is
		## remembered forever, regardless of archetype or what this NPC does
		## about it next (Call/Flee/Freeze/Respond) — "увидел — запомнил",
		## this task's own words. See _record_memory()'s own comment.
		##
		## _distance_ceiling() and not _resolve_observation_level(): the
		## distance is already in `vision`, and that wrapper additionally
		## writes the debug-panel fields, which belong to the report about to
		## be resolved and not to this. Same number, no side effect.
		_record_memory(_distance_ceiling(vision.distance))

	if _npc.archetype.responds_by_approaching:
		_log_incident_candidate(telemetry, vision, "RESPOND patrolman")
		## Always the incident position, never the player, even when a
		## witness's report would put the player at FACE/IRIS quality:
		## Incident (incident_registry/incident.gd) carries no observation
		## level at all, and WitnessReport — the one class that resolves
		## one — is never attached to the Incident or the registry (see
		## witness_report.gd's own header: "written and read by nothing
		## else in this build"). A responding Patrolman has no channel to
		## learn a report's quality without a new one being added — an
		## open contract question, not something to wire around here.
		_start_responding(incident.position)
		return

	## Witness/Call check happens before the ordinary Flee/Freeze roll, not
	## alongside it — an NPC that calls still visibly stares at the incident
	## (CALLING sets the same facing/look target FROZEN does); an NPC whose
	## archetype doesn't call falls through to the same probabilistic
	## Flee/Freeze roll every other NPC uses. Reporting is no longer instant
	## — see _start_calling() and docs/attribution.md §7.
	##
	## Whether an NPC calls at all is a deterministic archetype trait
	## (NPCArchetypeData.is_witness_caller, true only for Clerk today), not a
	## population-wide density/probability roll — see that field's own
	## comment for why. _evaluate_incident_vision() is still a hard gate, not
	## a modifier: an NPC whose back is turned did not see anything and does
	## not become a caller over it, whatever its archetype — see that
	## method's own header and attribution.md §2 on why "didn't see" and
	## "saw, but worse" are not the same case. earshot_radius above still
	## gates whether this NPC reacts AT ALL (Flee/Freeze/Call) — that stays
	## hearing-based, unchanged; only Call additionally requires having
	## actually seen it.
	if not vision.is_seen:
		_log_incident_candidate(
			telemetry, vision, "REJECT %s" % vision.rejection
		)
	elif not _npc.archetype.is_witness_caller:
		_log_incident_candidate(telemetry, vision, "SEES  REJECT archetype")
	elif not _npc.has_votive():
		_log_incident_candidate(telemetry, vision, "SEES  REJECT no-votive")
	else:
		_log_incident_candidate(
			telemetry, vision,
			"SEES  ceiling %s  CALL" % [
				WitnessReport.ObservationLevel.keys()[_distance_ceiling(vision.distance)],
			]
		)
		telemetry.transmitting += 1
		_start_calling(incident)
		return

	if randf() < _npc.archetype.flee_probability:
		_start_flee(incident.position)
		_log_incident_outcome(telemetry, "FLEE")
	else:
		_start_freeze(incident.position)
		_log_incident_outcome(telemetry, "FROZEN")


## Witness Call — NPC_REACTIONS.md §4: "reports the incident." Reuses
## IncidentRegistry.report() exactly as player.gd's own punch handler
## already does (see incident_registry.gd's own header: "a future witness
## reports through the same call" was the design from the start, not a
## retrofit). Attribution (does this report name a perpetrator, or only
## that something happened) is docs/attribution.md §5's job, not scheduled —
## this still reports fully attributed, same as every producer today, until
## that lands. Only ever called once a WitnessReport has actually COMMITTED
## (_commit_witness_report()) — see that method and docs/attribution.md §7
## for why this no longer fires the instant a witness decides to call.
func _call_it_in(incident: Incident) -> void:
	if not _incident_registry:
		return
	var player_node := get_tree().get_first_node_in_group("player")
	if not (player_node and player_node.has_method(&"get_actor_id")):
		return
	## Source.WITNESS_REPORT, not the default DIRECT: this is a Votive
	## transmission that ran its full duration and committed, and it is the
	## channel the city dispatches on from any distance. The punch that
	## started all this already entered the record as DIRECT through
	## player.gd's own path — the two are deliberately separate facts, not
	## one fact reported twice. See Incident.Source's own comment.
	_incident_registry.report(
		StringName(player_node.call(&"get_actor_id")),
		Incident.Kind.ASSAULT,
		incident.position,
		Incident.Source.WITNESS_REPORT
	)


## Phase 1 (BACKING_AWAY) only opens if allow_backpedal is true AND the
## player is approaching RIGHT NOW — a player merely standing nearby must
## not summon a backing-away crowd (this task's own requirement). A witness
## that flees while the player isn't approaching, or with allow_backpedal
## false (memory-triggered flight — see _decide()'s _remembers_player()
## branch, which isn't a fresh startle and skips the theatrics outright),
## goes straight to RUNNING. threat_position is fixed for the whole
## reaction (see _set_flee_direction_from_threat()), so RUNNING always ends
## up heading away from it, not from wherever the player happened to be
## standing when the backpedal ended.
func _start_flee(threat_position: Vector3, allow_backpedal: bool = true) -> void:
	_flee_threat_position = threat_position
	_set_flee_direction_from_threat()
	_reaction_state = ReactionState.FLEEING
	_reaction_timer = 0.0
	var start_backing_away := allow_backpedal and _is_player_approaching()
	_enter_flee_phase(FleePhase.BACKING_AWAY if start_backing_away else FleePhase.RUNNING)
	_try_spawn_comic_effect(&"npc_flee")


## _flee_direction, away from _flee_threat_position — the fixed point this
## flee reaction is running from. Called once by _start_flee() and again,
## once, whenever _enter_flee_phase() actually turns into RUNNING (whether
## that happens immediately or after a BACKING_AWAY that spent its own
## duration tracking the player's live position instead — see that phase's
## own comment). Never called per frame during RUNNING itself: this task's
## own "убегает от места инцидента, а не от игрока... направление берётся
## один раз при развороте" requirement.
func _set_flee_direction_from_threat() -> void:
	var away := _npc.global_position - _flee_threat_position
	away.y = 0.0
	_flee_direction = away.normalized() if away.length() > 0.01 else Vector3.FORWARD


## Switches FLEEING's active sub-phase and does the one-time setup each side
## needs — RUNNING clears the stare (facing/look target), points
## _obstacle_ray back at the body's own forward, and recomputes
## _flee_direction once from _flee_threat_position (overwriting whatever
## BACKING_AWAY may have left it as); BACKING_AWAY points the ray backward
## instead, since during a backpedal local +Z faces the player, not the
## direction of travel (see OBSTACLE_RAY_BACKWARD's own comment).
func _enter_flee_phase(phase: FleePhase) -> void:
	_flee_phase = phase
	_flee_phase_timer = 0.0
	if phase == FleePhase.RUNNING:
		_set_flee_direction_from_threat()
	if not _obstacle_ray:
		return
	if phase == FleePhase.BACKING_AWAY:
		_obstacle_ray.target_position = OBSTACLE_RAY_BACKWARD
	else:
		_obstacle_ray.target_position = OBSTACLE_RAY_FORWARD
		_npc.clear_facing_target()
		_npc.clear_look_target()


## Whether the player's own movement is currently aimed at this NPC — the
## gate for BOTH opening BACKING_AWAY (_start_flee()) and staying in it
## (_step_flee_backing_away()). Reads player.gd's CharacterBody3D.velocity
## directly rather than sampling this NPC's distance to the player across
## frames: velocity answers "is it approaching me" from the very first
## frame of a reaction, with no one-frame warm-up a distance-delta approach
## would need. Standing still (near-zero velocity) is never approaching,
## matching this task's own "стоящий на месте игрок" requirement.
func _is_player_approaching() -> bool:
	var player_node := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not player_node:
		return false
	var to_npc := _npc.global_position - player_node.global_position
	to_npc.y = 0.0
	if to_npc.length() < 0.01:
		return true
	var player_velocity := player_node.velocity
	player_velocity.y = 0.0
	if player_velocity.length() < 0.01:
		return false
	return player_velocity.normalized().dot(to_npc.normalized()) > approach_alignment_threshold


func _start_freeze(incident_position: Vector3) -> void:
	_reaction_state = ReactionState.FROZEN
	_reaction_timer = 0.0
	_npc.set_move_intent(Vector3.ZERO, 0.0)
	## "Stare" — the body turns toward the incident, not just the head, same
	## set_facing_target()/set_look_target() pair _decide()'s own COMBAT
	## branch already uses for a deliberate turn rather than a glance.
	_npc.set_facing_target(incident_position)
	_npc.set_look_target(incident_position)
	_try_spawn_comic_effect(&"npc_freeze")


func _start_responding(incident_position: Vector3, sync_partner: bool = true) -> void:
	_reaction_state = ReactionState.RESPONDING
	_reaction_timer = 0.0
	_respond_target = incident_position
	_respond_arrived = false
	if not sync_partner or not _is_patrol_pair_operational():
		return
	## Defer the pair sync until IncidentRegistry finishes notifying every
	## listener. The partner must evaluate the incident with its own perception
	## before formation state can make it look already occupied.
	_patrol_partner_controller.call_deferred(
		&"_start_responding_from_partner", incident_position
	)


func _start_responding_from_partner(incident_position: Vector3) -> void:
	if _reaction_state != ReactionState.NONE or not _is_patrol_pair_operational():
		return
	_start_responding(incident_position, false)


## Witness decided to call (docs/attribution.md §7) — stares at the incident
## the same way _start_freeze() does (reused, not a new visual behaviour;
## the Votive is what actually distinguishes CALLING from FROZEN — see the
## chain-wiring commit) and builds a WitnessReport that sits PENDING until
## _step_calling() commits or _cancel_active_witness_report() cancels it.
func _start_calling(incident: Incident) -> void:
	_reaction_state = ReactionState.CALLING
	_reaction_timer = 0.0
	_npc.set_move_intent(Vector3.ZERO, 0.0)
	_npc.set_facing_target(incident.position)
	_npc.set_look_target(incident.position)
	_pending_incident = incident
	_current_witness_report = _build_witness_report(incident)
	if _votive:
		_votive.start_transmitting(call_report_duration)
	_try_spawn_comic_effect(&"npc_call")
	if incident_telemetry_enabled:
		print(
			"%s transmission start: %s, %.1fs expected" % [
				INCIDENT_TELEMETRY_PREFIX, _npc.name, call_report_duration,
			]
		)


## Resolves this witness's observation quality for incident (docs/
## attribution.md §2) and returns a PENDING WitnessReport — never a
## suspect, see that file's own header.
func _build_witness_report(incident: Incident) -> WitnessReport:
	var report := WitnessReport.new()
	report.witness_id = _npc.get_actor_id()
	report.observed_at = Time.get_ticks_msec() / 1000.0
	report.observed_from = _npc.global_position
	report.observation_level = _resolve_observation_level(incident)
	report.status = WitnessReport.Status.PENDING
	return report


## Distance ceiling only (attribution.md §2's table) — attention is NOT
## applied this iteration. It used to lower the ceiling by one step for a
## witness facing away, which was wrong in kind, not just in tuning: facing
## away means the witness did not see the incident at all, not that they saw
## it worse (attribution.md §2's own corrected split — "didn't see" vs. "saw,
## but worse" are different cases, and this build only has a mechanic for the
## first). _evaluate_incident_vision() is that gate now, checked in
## _on_incident_reported() before this is ever called — a report is only
## ever built for a witness already confirmed to have seen the incident, so
## there is nothing left here to lower. Real REDUCED triggers (talking,
## looking into one's own Votive) have no mechanic to derive them from yet;
## add attention back here, not as a vision-cone workaround, once one does.
## Also stashes the intermediate values on _debug_witness_* for the
## perception debug panel — see those vars' own comment.
func _resolve_observation_level(incident: Incident) -> WitnessReport.ObservationLevel:
	var distance := _npc.global_position.distance_to(incident.position)
	var ceiling := _distance_ceiling(distance)

	_debug_witness_distance = distance
	_debug_witness_in_cone = true
	_debug_witness_ceiling = ceiling

	return ceiling


func _distance_ceiling(distance: float) -> WitnessReport.ObservationLevel:
	if distance > witness_ceiling_equipment_distance:
		return WitnessReport.ObservationLevel.SILHOUETTE
	if distance > witness_ceiling_face_distance:
		return WitnessReport.ObservationLevel.EQUIPMENT
	if distance > witness_ceiling_iris_distance:
		return WitnessReport.ObservationLevel.FACE
	if not _npc.can_read_iris():
		return WitnessReport.ObservationLevel.FACE
	return WitnessReport.ObservationLevel.IRIS


## Whether this NPC actually saw incident — range + cone only, same check
## PerceptionComponent.observe_player() runs for the player (distance versus
## vision_range, angle versus half of vision_angle_deg), retargeted at the
## incident's own position instead of the player's live one (they are not
## always the same point — the victim may have moved since). Reads
## PerceptionComponent's public vision_range/vision_angle_deg exports rather
## than calling into it: that component's own API only ever answers "can
## this actor see the PLAYER right now," which isn't the question here.
## Deliberately no line-of-sight raycast — this gate only ever asked for
## range + cone (attribution.md §2 doesn't call for occlusion here), not a
## stand-in fix for one. PerceptionComponent's own LINE_OF_SIGHT_MASK used
## to include the floor layer (an open, undiagnosed defect — since fixed,
## see CollisionLayers.SIGHT), which was the original reason to avoid
## reusing its mask here; that reason is gone, but nothing in the design
## calls for occlusion in this check either way, so it still doesn't have
## one.
func _evaluate_incident_vision(incident: Incident) -> IncidentVision:
	var result := IncidentVision.new()
	if not _perception:
		return result

	var eye_pos := _npc.global_position + Vector3(0.0, _npc.get_eye_height(), 0.0)
	result.distance = eye_pos.distance_to(incident.position)
	var vision_range := _perception.vision_range
	if result.distance > vision_range:
		result.rejection = "range (max %.1f)" % vision_range
		return result

	var horizontal_to_incident := incident.position - eye_pos
	horizontal_to_incident.y = 0.0
	if horizontal_to_incident.length() < 0.001:
		result.is_seen = true
		result.angle_deg = 0.0
		result.rejection = ""
		return result

	var facing := _npc.get_facing_direction()
	result.angle_deg = rad_to_deg(facing.angle_to(horizontal_to_incident.normalized()))
	if result.angle_deg > _perception.vision_angle_deg * 0.5:
		result.rejection = "cone (max %.0f)" % (_perception.vision_angle_deg * 0.5)
		return result

	result.is_seen = true
	result.rejection = ""
	return result


## Dispatches the active reaction — called from _decide() instead of the
## ordinary wander/observe-player branch for as long as a reaction is live.
func _step_reaction(delta: float) -> void:
	match _reaction_state:
		ReactionState.FLEEING:
			_step_flee(delta)
		ReactionState.FROZEN:
			_step_freeze(delta)
		ReactionState.RESPONDING:
			_step_respond(delta)
		ReactionState.CALLING:
			_step_calling(delta)


func _step_flee(delta: float) -> void:
	_reaction_timer += delta
	match _flee_phase:
		FleePhase.BACKING_AWAY:
			_step_flee_backing_away(delta)
		FleePhase.RUNNING:
			_step_flee_running(delta)


## Phase 1: backs away from the player's own live position while facing it
## (set_facing_target(), with set_move_intent()'s face_direction=false so
## the body doesn't turn to face the way it's walking — see npc_base.gd's
## own comment on that override). A FIXED duration, not distance-gated (this
## task's own "не по дистанции — по времени" requirement) — the only early
## exits left are losing track of the player node entirely or backing into
## solid geometry; ends on backpedal_duration regardless of how close the
## player still is or whether it's still approaching.
func _step_flee_backing_away(delta: float) -> void:
	_flee_phase_timer += delta

	var player_node := get_tree().get_first_node_in_group("player") as Node3D
	if not player_node:
		_enter_flee_phase(FleePhase.RUNNING)
		return

	if _flee_phase_timer >= backpedal_duration:
		_enter_flee_phase(FleePhase.RUNNING)
		return

	var player_pos := player_node.global_position
	var away := _npc.global_position - player_pos
	away.y = 0.0
	if away.length() > 0.01:
		_flee_direction = away.normalized()

	_npc.set_facing_target(player_pos)
	_npc.set_look_target(player_pos)

	if _obstacle_ray and _obstacle_ray.is_colliding():
		## Backing into something — no navigation to route a backward step
		## around it (see the file header), so give up on the theatrics and
		## just run instead of pushing through a wall backward.
		_enter_flee_phase(FleePhase.RUNNING)
		return

	_npc.set_move_intent(_flee_direction, backpedal_speed_ratio, false)


## Phase 2: runs away from _flee_threat_position (not the player — see
## _set_flee_direction_from_threat()) until flee_far_distance is covered, or
## flee_duration elapses regardless — a per-phase safety cap now, not the
## whole reaction's own timer, since geometry can trap an NPC close to the
## threat with nowhere straight to run. Same obstacle check _step_wander()
## uses (see the file header on _obstacle_ray's deferred add_child()),
## retargeting off a wall by rotating _flee_direction rather than stopping.
func _step_flee_running(delta: float) -> void:
	_flee_phase_timer += delta
	if _npc.global_position.distance_to(_flee_threat_position) >= flee_far_distance:
		_end_reaction()
		return
	if _flee_phase_timer >= flee_duration:
		_end_reaction()
		return
	if _obstacle_ray and _obstacle_ray.is_colliding():
		_flee_direction = _flee_direction.rotated(Vector3.UP, randf_range(0.5, 1.5))
	_npc.set_move_intent(_flee_direction, flee_speed_ratio)


func _step_freeze(delta: float) -> void:
	_reaction_timer += delta
	if _reaction_timer >= freeze_duration:
		_end_reaction()


## Patrolman only (see _on_incident_reported()). Walks straight at the
## incident position, same "goal point, arrive" shape _step_wander() uses,
## at respond_speed_ratio (brisker than an ordinary wander) and stopping at
## respond_arrival_distance (further out than WANDER_ARRIVAL_RADIUS — an
## investigating Patrolman holds back, doesn't walk up nose to nose). On
## arrival this NPC just stops and stares at the target for freeze_duration
## — reusing that same hold length rather than a third near-identical
## export, since nothing about this task calls for combat behaviour on
## arrival, only visible acknowledgement that it got there.
func _step_respond(delta: float) -> void:
	if _is_patrol_pair_operational():
		if _is_patrol_pair_follower():
			_step_patrol_pair_respond_follower()
			return
		if _should_patrol_leader_wait():
			_npc.set_move_intent(Vector3.ZERO, 0.0)
			return
	else:
		_leader_waiting_for_partner = false

	if _respond_arrived:
		_reaction_timer += delta
		if _reaction_timer >= freeze_duration:
			_end_reaction()
		return

	var to_target := _respond_target - _npc.global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist <= respond_arrival_distance:
		_respond_arrived = true
		_reaction_timer = 0.0
		_npc.set_move_intent(Vector3.ZERO, 0.0)
		_npc.set_facing_target(_respond_target)
		_npc.set_look_target(_respond_target)
		return

	if _obstacle_ray and _obstacle_ray.is_colliding():
		## No navigation to route around it (see the file header) — give up
		## on reaching the exact point rather than push through a wall.
		_end_reaction()
		return

	_npc.set_move_intent(to_target.normalized(), respond_speed_ratio)


func _step_patrol_pair_respond_follower() -> void:
	if _patrol_partner_controller._reaction_state != ReactionState.RESPONDING:
		_end_reaction()
		return
	_step_patrol_pair_follower(patrol_pair_catchup_speed_ratio)
	if not _patrol_partner_controller._respond_arrived:
		_respond_arrived = false
		return
	var to_slot := _get_patrol_pair_slot() - _npc.global_position
	to_slot.y = 0.0
	if to_slot.length() > PATROL_PAIR_SLOT_ARRIVAL_DISTANCE:
		return
	_respond_arrived = true
	_npc.set_move_intent(Vector3.ZERO, 0.0)
	_npc.set_facing_target(_respond_target)
	_npc.set_look_target(_respond_target)


## PENDING -> COMMITTED once call_report_duration elapses without
## interruption (docs/attribution.md §6/§7's "time until transmission
## completes"). Two interruption paths: the knocked-down guard in _decide()
## (_cancel_active_witness_report(), unchanged), and — this task's own
## "клерк начинает звонок и дистанция до игрока уменьшается" trigger —
## the player closing in on a still-transmitting witness, checked here every
## frame via _is_player_approaching() (the same helper/threshold the
## generic Flee reaction's own backpedal gate uses).
func _step_calling(delta: float) -> void:
	if _is_player_approaching():
		_abort_call_for_flee()
		return
	_reaction_timer += delta
	if _reaction_timer >= call_report_duration:
		_commit_witness_report()


## The report survived its full transmission window uninterrupted — mark it
## COMMITTED and only NOW call _call_it_in(), the same attributed
## IncidentRegistry report every producer in this build makes (see that
## method's own header on why attribution itself isn't built yet).
func _commit_witness_report() -> void:
	if _current_witness_report:
		_current_witness_report.status = WitnessReport.Status.COMMITTED
		if _pending_incident:
			_call_it_in(_pending_incident)
			_try_spawn_comic_effect(&"npc_transmit")
		if incident_telemetry_enabled:
			print(
				"%s transmission committed: %s, observation %s, registry ASSAULT" % [
					INCIDENT_TELEMETRY_PREFIX, _npc.name,
					WitnessReport.ObservationLevel.keys()[_current_witness_report.observation_level],
				]
			)
	_current_witness_report = null
	_pending_incident = null
	if _votive:
		_votive.go_idle()
	_end_reaction()


## Interrupted before commit (docs/attribution.md §7, test case E: "CANCELLED,
## nothing in registry") — _call_it_in() is simply never called, so nothing
## reaches IncidentRegistry. Only acts on a report still PENDING: called
## every frame this NPC is knocked down (see _decide()'s own guard) and once
## from _abort_call_for_flee(), so it must be a safe no-op once already
## cancelled or committed. Does not touch _reaction_state itself past
## clearing the report — every caller sets its own state right afterward
## (the knocked-down guard doesn't change it at all; _abort_call_for_flee()
## moves straight to FLEEING via _start_flee()).
func _cancel_active_witness_report(reason: String = "knocked down") -> void:
	if not _current_witness_report or _current_witness_report.status != WitnessReport.Status.PENDING:
		return
	_current_witness_report.status = WitnessReport.Status.CANCELLED
	if incident_telemetry_enabled:
		print(
			"%s transmission cancelled: %s, %s, %.1fs remaining" % [
				INCIDENT_TELEMETRY_PREFIX, _npc.name, reason,
				maxf(call_report_duration - _reaction_timer, 0.0),
			]
		)
	_current_witness_report = null
	_pending_incident = null
	_reaction_state = ReactionState.NONE


## The player is closing in on a witness mid-transmission — abandons the
## report (same CANCELLED path a knockdown already gives) and flees, reusing
## the ordinary FLEEING state machine so the backpedal-then-run shape is the
## same for every trigger, not a second implementation (this file's own
## precedent: don't invent a second solution to an already-solved shape).
## go_idle(), not go_dark(): the terminal isn't suppressed, it just isn't
## transmitting any more — go_dark() stays reserved for the knocked-down
## case (_decide()'s own guard). Always opens with BACKING_AWAY: this is
## only ever called because the player IS approaching (the caller already
## checked), so _start_flee()'s own "skip the backpedal if not approaching"
## branch never actually applies here.
func _abort_call_for_flee() -> void:
	var threat_position := _pending_incident.position if _pending_incident else _npc.global_position
	_cancel_active_witness_report("player approaching")
	if _votive:
		_votive.go_idle()
	_start_flee(threat_position)


## Returns to ordinary behaviour via a paused idle, not mid-stride — same
## entry state _start_pause() already gives the wander cycle after arriving
## somewhere, so a reaction ending doesn't visibly snap the NPC into a new
## walk direction on the very next frame.
func _end_reaction() -> void:
	_reaction_state = ReactionState.NONE
	_npc.clear_facing_target()
	_npc.clear_look_target()
	## Defensive, not load-bearing on the happy path: every
	## _enter_flee_phase(RUNNING) call already restores this before RUNNING
	## can ever end the reaction, but a safety net in case some future path
	## ever calls _end_reaction() while still BACKING_AWAY — which would
	## otherwise leave the ray pointed backward for whatever ordinary
	## wander/respond/run behaviour picks this NPC up next.
	if _obstacle_ray:
		_obstacle_ray.target_position = OBSTACLE_RAY_FORWARD
	_start_pause()


func _begin_incident_telemetry(incident: Incident) -> IncidentTelemetryEntry:
	var incident_id := incident.get_instance_id()
	var existing := _find_incident_telemetry(incident_id)
	if existing:
		return existing

	var entry := IncidentTelemetryEntry.new()
	entry.incident_id = incident_id
	entry.sequence = _next_telemetry_sequence
	_next_telemetry_sequence += 1
	_telemetry_entries.append(entry)
	if incident_telemetry_enabled:
		print(
			"%s INCIDENT #%d  %s  pos(%.1f, %.1f, %.1f)  t=%.2fh" % [
				INCIDENT_TELEMETRY_PREFIX, entry.sequence, Incident.Kind.keys()[incident.kind],
				incident.position.x, incident.position.y, incident.position.z, incident.timestamp,
			]
		)
		call_deferred("_finish_incident_telemetry", incident_id)
	return entry


func _finish_incident_telemetry(incident_id: int) -> void:
	var entry := _find_incident_telemetry(incident_id)
	if not entry:
		return
	if incident_telemetry_enabled:
		if entry.skip_total > 0:
			print("%s   skipped: %d (%s)" % [
				INCIDENT_TELEMETRY_PREFIX, entry.skip_total, _format_skip_counts(entry.skip_counts)
			])
		print("%s   in hearing range: %d" % [INCIDENT_TELEMETRY_PREFIX, entry.in_hearing_range])
		print("%s -> transmitting: %d" % [INCIDENT_TELEMETRY_PREFIX, entry.transmitting])
	_telemetry_entries.erase(entry)


## "already-reacting 13, knocked-down 1" — Dictionary insertion order is the
## order reasons were first seen for this incident, which in practice is
## also NPC iteration order; stable enough for a debug trace, no explicit
## sort needed.
func _format_skip_counts(skip_counts: Dictionary) -> String:
	var parts: Array[String] = []
	for reason: String in skip_counts:
		parts.append("%s %d" % [reason, skip_counts[reason]])
	return ", ".join(parts)


func _find_incident_telemetry(incident_id: int) -> IncidentTelemetryEntry:
	for entry in _telemetry_entries:
		if entry.incident_id == incident_id:
			return entry
	return null


## outcome is one of "SKIP knocked-down" / "SKIP already-reacting" / "SKIP
## no-archetype" — an NPC that never reached the earshot gate at all, so the
## range/cone verdict the rest of this trace exists to show does not apply
## to it (per this task's own instruction: print by name only NPCs that were
## actually evaluated). Counted into entry.skip_counts instead of printed
## per NPC — _finish_incident_telemetry() prints the one summary line once
## the incident is done being evaluated.
func _log_incident_rejection(entry: IncidentTelemetryEntry, outcome: String) -> void:
	if not incident_telemetry_enabled:
		return
	var reason := outcome.trim_prefix("SKIP ")
	entry.skip_counts[reason] = int(entry.skip_counts.get(reason, 0)) + 1
	entry.skip_total += 1


func _log_incident_candidate(
	_entry: IncidentTelemetryEntry, vision: IncidentVision, outcome: String
) -> void:
	if incident_telemetry_enabled:
		print(
			"%s   %s  d=%.1f  ang=%.0f  %s" % [
				INCIDENT_TELEMETRY_PREFIX, _npc.name,
				vision.distance, vision.angle_deg, outcome,
			]
		)


## What a candidate that fell through to the ordinary Flee/Freeze roll
## actually ended up doing — printed as its own line right after whichever
## REJECT/SEES line _log_incident_candidate() already produced, since that
## line is written before the roll happens and can't be appended to after
## the fact. Every candidate that reaches this point (in earshot, not
## knocked down, not already reacting, has an archetype) always resolves to
## one of these two — there is no silent "no reaction" among logged
## candidates once _on_incident_reported() gets this far.
func _log_incident_outcome(_entry: IncidentTelemetryEntry, outcome: String) -> void:
	if incident_telemetry_enabled:
		print("%s   %s  -> %s" % [INCIDENT_TELEMETRY_PREFIX, _npc.name, outcome])
