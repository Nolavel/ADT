# =============================================================================
# idle_npc_controller.gd — IdleNPCController: wanders near its spawn point,
# freezes and follows the player with its gaze the moment it notices one,
# turns its body if the player lingers, and reacts to a nearby incident
# (NPC_REACTIONS.md §4: Flee, Freeze and stare, or — Patrolman only — walk
# toward it).
#
# Wandering is deliberately dumb: a random point inside wander_radius of
# where this NPC started, walk to it, pause, pick another — a forward
# RayCast3D substitutes for navigation (there is none yet): on an obstacle,
# retarget immediately and keep going, the same immediate pick-a-new-point
# response PatrolDroneController's patrol uses on arrival. A pause
# (wander_pause_time) only happens on reaching an actual destination, not
# on bouncing off a wall. NOTE: _obstacle_ray is built in _ready() but never
# actually parented into the tree (see that line's own comment) — a
# RayCast3D outside the tree never updates, so is_colliding() always reads
# false today. This was already true of wander before this file grew an
# incident reaction that reuses the same check; flagged here rather than
# fixed, since fixing it is a navigation change this task's own brief rules
# out ("не берись чинить навигацию попутно").
#
# Every frame it also asks its sibling PerceptionComponent for a plain
# observation and decides what it means: the moment the player is seen,
# movement freezes outright (wandering is not worth continuing mid-glance),
# the head always tracks a visible player, and the body only commits to
# turning once the player has stayed in view past body_turn_delay and is
# far enough off-angle (body_turn_angle_deg) that a head turn alone would
# no longer read as attention. That distinction — a glance versus a
# deliberate turn — is exactly the kind of interpretation that belongs
# here, in the controller, never in perception itself (see
# player_observation.gd).
#
# INCIDENT REACTION (NPC_REACTIONS.md §4) lives in this same controller
# rather than a separate component, on purpose: only one decision-maker can
# own set_move_intent()/set_look_target() on a given frame without the two
# fighting each other, and PatrolDroneController already bundles three
# fairly different behaviours (PATROL/OBSERVE/ALERT) into one controller
# for the same reason — this follows that precedent rather than starting a
# new one. Subscribes to IncidentRegistry.incident_reported using the exact
# lazy-resolve scheme PatrolDroneController uses (see
# _try_resolve_incident_registry()) — an ambient NPC is just as likely to be
# sitting statically in world.tscn ahead of World's own _ready() pass as a
# drone is, so the same bootstrap-ordering problem applies. Deliberately
# does NOT replay catch-up for incidents that predate this NPC noticing
# them (PatrolDroneController's _check_existing_incidents() has no
# equivalent here): a durable ALERT genuinely means "the city still
# suspects something," but a crowd flinch is a momentary startle response —
# an NPC freezing or fleeing NOW over a punch thrown minutes ago, possibly
# somewhere it has since wandered away from, would read as a bug, not
# memory.
#
# ReactionState pre-empts everything else in _decide() while active
# (checked right after the knocked-down guard, before wander/observe-player)
# — an NPC mid-flee or mid-freeze does not also pause to notice the player
# strolling by; the incident is the stronger stimulus. Reactions are
# deliberately probabilistic, not per-archetype rules: NPC_REACTIONS.md §4
# says the crowd reacts BY CHANCE, and a fixed "this archetype always
# flees" would turn the crowd into a lookup table — exactly what §2's
# "street literacy, learned by observation" is arguing against. The bias
# lives on the archetype (NPCArchetypeData.flee_probability), not as a
# constant here, so retuning it never means touching this file.
#
# WITNESS CALL (docs/attribution.md §7) no longer reports the instant a
# witness rolls Call. ReactionState.CALLING resolves an observation quality
# (distance ceiling + facing-based attention, docs/attribution.md §2) into a
# WitnessReport, then holds it PENDING for call_report_duration seconds
# before _commit_witness_report() actually calls IncidentRegistry — see that
# method, _step_calling() and _cancel_active_witness_report(). Attribution
# itself (docs/attribution.md §5) is not built: _call_it_in() still reports
# fully attributed once a report commits, same as every producer today.
# =============================================================================
extends NPCControllerBase
class_name IdleNPCController

enum State { IDLE, WALKING }

## NONE = ordinary wander/observe-player behaviour applies. The other four
## pre-empt it entirely for as long as they're active — see the file header.
## CALLING (docs/attribution.md section 7) replaces what used to be an
## instant, fully-attributed report on the spot: a witness that rolls Call
## now resolves an observation quality and holds a WitnessReport PENDING for
## call_report_duration before it actually commits — see _step_calling().
enum ReactionState { NONE, FLEEING, FROZEN, RESPONDING, CALLING }

## docs/attribution.md section 2's binary attention modifier. Only the
## "facing away from the incident" trigger is implemented — "talking to
## another NPC" and "looking into their own Votive projection" both name
## behaviour this build has no mechanic for (no NPC-to-NPC conversation state,
## and NPCs never look at their own Votive), so this deliberately covers the
## one trigger that's actually derivable from what an NPC already knows about
## itself: its own facing versus the incident's position.
enum Attention { NORMAL, REDUCED }

## Distance to the wander target that counts as "arrived."
const WANDER_ARRIVAL_RADIUS: float = 0.5
## How far ahead the obstacle raycast checks, metres.
const OBSTACLE_CHECK_DISTANCE: float = 1.5
## Height above the NPC's own origin the obstacle raycast casts from —
## roughly chest height, high enough to clear kerbs, low enough to catch
## most walls. Not derived from BodyMetrics: a single fixed offset is
## enough for a straight-ahead bump check, not worth a new getter.
const OBSTACLE_RAY_HEIGHT: float = 1.0
## Wall only (not floor) — same layer PerceptionComponent's own
## LINE_OF_SIGHT_MASK calls "wall (3)"; floor is what an NPC walks on, not
## an obstacle to walking.
const OBSTACLE_MASK: int = 1 << 2

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
## Seconds spent fleeing before returning to ordinary wander.
@export var flee_duration: float = 4.0
## Speed ratio while fleeing — faster than an ordinary wander pace on
## purpose; a walk away from a fight should read as more urgent than a
## stroll.
@export var flee_speed_ratio: float = 1.0
## Seconds spent frozen (staring at the incident) before returning to
## ordinary wander.
@export var freeze_duration: float = 4.0

@export_group("Incident Registry")
## Seconds to keep retrying the group lookup before giving up and warning
## once — same idiom and same default as
## PatrolDroneController.incident_registry_search_timeout.
@export var incident_registry_search_timeout: float = 5.0

@export_group("Witness (NPC_REACTIONS.md §4)")
## Fraction of the population that gets the witness flag — rolled once per
## NPC in _ready(), not re-rolled per incident (see _is_witness's own
## comment for why). ONE number for the whole population on purpose: §4
## gives the flag a density, not a per-archetype rate, and
## npc_archetypes.md §5 already treats population composition as scene
## data, not an archetype property — this follows that same split. Retune
## density by changing this default; do not add a per-archetype override.
@export_range(0.0, 1.0) var witness_density: float = 0.15
## Given a witness NPC reacts to an incident at all, the chance it calls
## rather than just fleeing/freezing like everyone else — a witness doesn't
## always report, same "bias, not a rule" principle flee_probability
## already applies to Flee vs. Freeze.
@export_range(0.0, 1.0) var call_probability: float = 0.6

@export_group("Witness Observation Quality (attribution.md §2)")
## Beyond this distance the ceiling is SILHOUETTE — nothing more is
## achievable regardless of attention. Thresholds are @export, not
## constants, per attribution.md §7's own instruction: they are feel/scale
## values, not derived numbers.
@export var witness_ceiling_equipment_distance: float = 30.0
## Beyond this distance (and within witness_ceiling_equipment_distance) the
## ceiling is EQUIPMENT.
@export var witness_ceiling_face_distance: float = 10.0
## Beyond this distance (and within witness_ceiling_face_distance) the
## ceiling is FACE; within it, IRIS.
@export var witness_ceiling_iris_distance: float = 5.0
## Degrees off this NPC's own facing, toward the incident's position, past
## which attention counts as REDUCED rather than NORMAL — see Attention's own
## comment on why "facing away" is the one trigger this build can derive.
@export var witness_attention_angle_deg: float = 90.0

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

## Seconds the player has been continuously visible. Reset to 0 the instant
## the player is no longer seen — this is "how long has this sighting
## lasted," not a running total.
var _visible_time: float = 0.0

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
## Fixed at the moment FLEEING starts (away from the incident position) —
## not re-derived every frame, since the incident itself doesn't move.
var _flee_direction: Vector3 = Vector3.ZERO
## Where a RESPONDING (Patrolman-only) NPC is walking to.
var _respond_target: Vector3 = Vector3.ZERO

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

## Rolled once in _ready() against witness_density — NOT re-rolled per
## incident (NPC_REACTIONS.md §4 is explicit: static on the NPC, not thrown
## fresh each time, so a save survives it and "the same passer-by" stays
## meaningful if anything later needs that). No visual tell by design (§2):
## nothing here reads this to change appearance, only whether _on_incident_
## reported() offers this NPC the Call branch at all.
var _is_witness: bool = false

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
var _debug_witness_attention: Attention = Attention.NORMAL
var _debug_witness_ceiling: WitnessReport.ObservationLevel = WitnessReport.ObservationLevel.NONE


func _ready() -> void:
	super._ready()
	_npc = _actor as NPCBase
	if not _npc:
		return
	for child in _npc.get_children():
		if child is PerceptionComponent:
			_perception = child
			break

	_wander_origin = _npc.global_position
	_obstacle_ray = RayCast3D.new()
	_obstacle_ray.position = Vector3(0.0, 0.9, 0.0)
	_obstacle_ray.target_position = Vector3(0.0, 0.0, 1.5)
	_obstacle_ray.collision_mask = 3
	#_npc.add_child(_obstacle_ray)

	_wander_state = State.IDLE
	_pause_timer = wander_pause_time

	## Once per instance, at spawn — see _is_witness's own comment on why
	## not per incident.
	_is_witness = randf() < witness_density

	## Very likely to fail here (see the file header on why) — kept anyway,
	## harmless, and resolves immediately in the rare case ordering ever
	## does favour this instance. _decide() is what actually guarantees
	## resolution, same split PatrolDroneController uses.
	_try_resolve_incident_registry()


func _decide(delta: float) -> void:
	if not _npc:
		return

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
		_cancel_active_witness_report()
		return

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
		_decide_wander(delta)
		return

	## Stops in place the instant it notices someone — see the file header.
	_npc.set_move_intent(Vector3.ZERO, 0.0)
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


## Human-readable state for debug tooling (perception_debug_panel.gd), same
## convention as PatrolDroneController.get_state_name().
func get_state_name() -> String:
	return State.keys()[_wander_state]


## Human-readable incident-reaction state for debug tooling — "NONE" outside
## a reaction, same convention as get_state_name() above.
func get_reaction_state_name() -> String:
	return ReactionState.keys()[_reaction_state]


func _decide_wander(delta: float) -> void:
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


# ── Incident reaction (NPC_REACTIONS.md §4) ─────────────────────────────────

## Retried from _decide() until it succeeds — see the file header on why a
## single _ready() call isn't enough for a static scene instance. Idempotent
## past the first success. No catch-up query on resolve, deliberately unlike
## PatrolDroneController's _check_existing_incidents() — see the file header
## on why a stale incident shouldn't make an NPC flinch now.
func _try_resolve_incident_registry() -> void:
	if _incident_registry:
		return
	var found := get_tree().get_first_node_in_group(
		IncidentRegistry.GROUP_INCIDENT_REGISTRY
	) as IncidentRegistry
	if not found:
		return
	_incident_registry = found
	_incident_registry.incident_reported.connect(_on_incident_reported)


## Rolls this NPC's reaction to a live incident report — see the file header
## for the priority/pre-emption rules and why this is probabilistic rather
## than a fixed per-archetype rule.
func _on_incident_reported(incident: Incident) -> void:
	if not _npc or _npc.is_knocked_down():
		return
	if _reaction_state != ReactionState.NONE:
		## Already reacting to something — a second, unrelated incident
		## doesn't interrupt or restart the current one. Keeps the state
		## machine simple; nothing in NPC_REACTIONS.md §4 asks for
		## interruption.
		return
	if not _npc.archetype:
		## No archetype, no reaction bias to roll against — same "unset is a
		## no-op" contract NPCBase._apply_archetype() already uses.
		return

	if _npc.global_position.distance_to(incident.position) > earshot_radius:
		return

	if _npc.archetype.responds_by_approaching:
		_start_responding(incident.position)
		return

	## Witness/Call check happens before the ordinary Flee/Freeze roll, not
	## alongside it — a witness who calls still visibly stares at the
	## incident (CALLING sets the same facing/look target FROZEN does); a
	## witness who doesn't call this time falls through to the same
	## probabilistic roll every other NPC uses. Reporting is no longer
	## instant — see _start_calling() and docs/attribution.md §7.
	if _is_witness and randf() < call_probability:
		_start_calling(incident)
		return

	if randf() < _npc.archetype.flee_probability:
		_start_flee(incident.position)
	else:
		_start_freeze(incident.position)


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
	_incident_registry.report(
		StringName(player_node.call(&"get_actor_id")), Incident.Kind.ASSAULT, incident.position
	)


func _start_flee(incident_position: Vector3) -> void:
	var away := _npc.global_position - incident_position
	away.y = 0.0
	_flee_direction = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	_reaction_state = ReactionState.FLEEING
	_reaction_timer = 0.0
	_npc.clear_look_target()
	_npc.clear_facing_target()


func _start_freeze(incident_position: Vector3) -> void:
	_reaction_state = ReactionState.FROZEN
	_reaction_timer = 0.0
	_npc.set_move_intent(Vector3.ZERO, 0.0)
	## "Stare" — the body turns toward the incident, not just the head, same
	## set_facing_target()/set_look_target() pair _decide()'s own COMBAT
	## branch already uses for a deliberate turn rather than a glance.
	_npc.set_facing_target(incident_position)
	_npc.set_look_target(incident_position)


func _start_responding(incident_position: Vector3) -> void:
	_reaction_state = ReactionState.RESPONDING
	_respond_target = incident_position


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


## Distance ceiling (attribution.md §2's table), then attention (facing away
## only, see Attention's own comment) lowers it by exactly one step — never
## raises it, a hard rule per that section, not a tuning choice. Also stashes
## the intermediate values on _debug_witness_* for the perception debug
## panel — see those vars' own comment.
func _resolve_observation_level(incident: Incident) -> WitnessReport.ObservationLevel:
	var distance := _npc.global_position.distance_to(incident.position)
	var ceiling := _distance_ceiling(distance)
	var attention := _resolve_attention(incident)

	_debug_witness_distance = distance
	_debug_witness_attention = attention
	_debug_witness_ceiling = ceiling

	if attention == Attention.REDUCED:
		return _lower_one_step(ceiling)
	return ceiling


func _distance_ceiling(distance: float) -> WitnessReport.ObservationLevel:
	if distance > witness_ceiling_equipment_distance:
		return WitnessReport.ObservationLevel.SILHOUETTE
	if distance > witness_ceiling_face_distance:
		return WitnessReport.ObservationLevel.EQUIPMENT
	if distance > witness_ceiling_iris_distance:
		return WitnessReport.ObservationLevel.FACE
	return WitnessReport.ObservationLevel.IRIS


## Facing away from the incident is the one REDUCED trigger this build can
## derive — see Attention's own comment. Uses this NPC's own facing versus
## the incident's position directly (NPCBase.get_facing_direction()), not
## PerceptionComponent: that component only ever measures facing relative to
## the PLAYER, and the incident's position is not always the player's
## current position (the victim may have moved since).
func _resolve_attention(incident: Incident) -> Attention:
	var to_incident := incident.position - _npc.global_position
	to_incident.y = 0.0
	if to_incident.length() < 0.01:
		return Attention.NORMAL
	var facing := _npc.get_facing_direction()
	var angle := rad_to_deg(facing.angle_to(to_incident.normalized()))
	return Attention.REDUCED if angle > witness_attention_angle_deg else Attention.NORMAL


## One step down the ObservationLevel ladder, floored at NONE — attention
## never pushes a report below the ladder's own bottom. In practice the
## floor is never reached here: a witness only ever reaches this path
## already within earshot_radius, which is well under
## witness_ceiling_equipment_distance by default, so the ceiling is always
## at least SILHOUETTE before attention is applied.
func _lower_one_step(level: WitnessReport.ObservationLevel) -> WitnessReport.ObservationLevel:
	match level:
		WitnessReport.ObservationLevel.IRIS:
			return WitnessReport.ObservationLevel.FACE
		WitnessReport.ObservationLevel.FACE:
			return WitnessReport.ObservationLevel.EQUIPMENT
		WitnessReport.ObservationLevel.EQUIPMENT:
			return WitnessReport.ObservationLevel.SILHOUETTE
		_:
			return WitnessReport.ObservationLevel.NONE


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
	if _reaction_timer >= flee_duration:
		_end_reaction()
		return
	## Same obstacle check _step_wander() uses, and just as inert today —
	## see the file header on _obstacle_ray never actually being parented
	## into the tree. Written for when that's fixed, not pretending it
	## works now.
	if _obstacle_ray and _obstacle_ray.is_colliding():
		_flee_direction = _flee_direction.rotated(Vector3.UP, randf_range(0.5, 1.5))
	_npc.set_move_intent(_flee_direction, flee_speed_ratio)


func _step_freeze(delta: float) -> void:
	_reaction_timer += delta
	if _reaction_timer >= freeze_duration:
		_end_reaction()


## Patrolman only (see _on_incident_reported()). Walks straight at the
## incident position, same "goal point, arrive" shape _step_wander() uses,
## reusing WANDER_ARRIVAL_RADIUS rather than a second near-identical
## constant that would mean the same thing.
func _step_respond(_delta: float) -> void:
	var to_target := _respond_target - _npc.global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < WANDER_ARRIVAL_RADIUS:
		_end_reaction()
		return

	if _obstacle_ray and _obstacle_ray.is_colliding():
		## No navigation to route around it (see the file header) — give up
		## on reaching the exact point rather than push through a wall.
		_end_reaction()
		return

	_npc.set_move_intent(to_target.normalized(), wander_speed_ratio)


## PENDING -> COMMITTED once call_report_duration elapses without
## interruption (docs/attribution.md §6/§7's "time until transmission
## completes"). Interruption is handled elsewhere — see
## _cancel_active_witness_report(), reached through the knocked-down guard
## in _decide(), not through this timer.
func _step_calling(delta: float) -> void:
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
	_current_witness_report = null
	_pending_incident = null
	_end_reaction()


## Interrupted before commit (docs/attribution.md §7, test case E: "CANCELLED,
## nothing in registry") — _call_it_in() is simply never called, so nothing
## reaches IncidentRegistry. Only acts on a report still PENDING: called
## every frame this NPC is knocked down (see _decide()'s own guard), so it
## must be a safe no-op once already cancelled or committed. Does not touch
## _reaction_state itself past clearing the report — the knocked-down guard
## that calls this returns immediately afterward regardless of what state was
## active (CALLING or otherwise), same as before this method existed.
func _cancel_active_witness_report() -> void:
	if not _current_witness_report or _current_witness_report.status != WitnessReport.Status.PENDING:
		return
	_current_witness_report.status = WitnessReport.Status.CANCELLED
	_current_witness_report = null
	_pending_incident = null
	_reaction_state = ReactionState.NONE


## Returns to ordinary behaviour via a paused idle, not mid-stride — same
## entry state _start_pause() already gives the wander cycle after arriving
## somewhere, so a reaction ending doesn't visibly snap the NPC into a new
## walk direction on the very next frame.
func _end_reaction() -> void:
	_reaction_state = ReactionState.NONE
	_npc.clear_facing_target()
	_npc.clear_look_target()
	_start_pause()
