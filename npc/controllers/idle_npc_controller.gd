# =============================================================================
# idle_npc_controller.gd — IdleNPCController: stands, follows the player
# with its gaze, and turns its body if the player lingers.
#
# Movement intent stays permanently zero — the NPC still doesn't walk
# anywhere, navigation is a later commit. Every frame it asks its sibling
# PerceptionComponent for a plain observation and decides what it means:
# the head always tracks a visible player, but the body only commits to
# turning once the player has stayed in view past BODY_TURN_DELAY and is
# far enough off-angle (BODY_TURN_ANGLE_DEG) that a head turn alone would
# no longer read as attention. That distinction — a glance versus a
# deliberate turn — is exactly the kind of interpretation that belongs
# here, in the controller, never in perception itself (see
# player_observation.gd).
# =============================================================================
extends NPCControllerBase
class_name IdleNPCController

## How long the player must stay visible before the body — not just the
## head — commits to turning. A glance is cheap; turning your shoulders is
## a statement, and it should not fire on someone walking past.
const BODY_TURN_DELAY: float = 0.5
## Yaw offset past which a head turn alone stops reading as attention.
const BODY_TURN_ANGLE_DEG: float = 40.0

## Resolved once in _ready(), alongside _npc — sibling node, child of the
## same NPC. Null if the NPC has no PerceptionComponent (not every NPC will
## necessarily have one forever, e.g. background crowd fillers later).
var _perception: PerceptionComponent = null

## Seconds the player has been continuously visible. Reset to 0 the instant
## the player is no longer seen — this is "how long has this sighting
## lasted," not a running total.
var _visible_time: float = 0.0


func _ready() -> void:
	super._ready()
	if not _npc:
		return
	for child in _npc.get_children():
		if child is PerceptionComponent:
			_perception = child
			break


func _decide(delta: float) -> void:
	_npc.set_move_intent(Vector3.ZERO, 0.0)

	if not _perception:
		return

	var observation := _perception.observe_player()
	if not observation.is_seen:
		_visible_time = 0.0
		_npc.clear_look_target()
		_npc.clear_facing_target()
		return

	_npc.set_look_target(observation.position)
	_visible_time += delta

	## Once the body starts turning, observation.angle_deg trends toward 0
	## as the NPC's facing catches up with the player — so this condition
	## naturally stops re-triggering mid-turn without needing a separate
	## "committed" flag. That is deliberate: it reads as finishing the turn
	## it already started, not as flickering at the threshold.
	if _visible_time >= BODY_TURN_DELAY and observation.angle_deg > BODY_TURN_ANGLE_DEG:
		_npc.set_facing_target(observation.position)


## Read by the perception debug panel — see _visible_time's own comment.
func get_visible_time() -> float:
	return _visible_time
