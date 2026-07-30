# =============================================================================
# idle_npc_controller.gd — IdleNPCController: stands and follows the player
# with its gaze.
#
# Movement intent stays permanently zero — the NPC still doesn't walk
# anywhere, navigation is a later commit. What's new: every frame it asks
# its sibling PerceptionComponent for a plain observation and decides what
# it means (look at the player, or don't) — that decision belongs here, in
# the controller, never in perception itself (see player_observation.gd).
# =============================================================================
extends NPCControllerBase
class_name IdleNPCController

## Resolved once in _ready(), alongside _npc — sibling node, child of the
## same NPC. Null if the NPC has no PerceptionComponent (not every NPC will
## necessarily have one forever, e.g. background crowd fillers later).
var _perception: PerceptionComponent = null


func _ready() -> void:
	super._ready()
	if not _npc:
		return
	for child in _npc.get_children():
		if child is PerceptionComponent:
			_perception = child
			break


func _decide(_delta: float) -> void:
	_npc.set_move_intent(Vector3.ZERO, 0.0)

	if not _perception:
		return

	var observation := _perception.observe_player()
	if observation.is_seen:
		_npc.set_look_target(observation.position)
	else:
		_npc.clear_look_target()
