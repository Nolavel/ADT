# =============================================================================
# npc_controller_base.gd — NPCControllerBase, the seam between decision
# approach and everything else an actor is.
#
# Despite the name (kept for the NPC controllers already built on it),
# drives any ActorBase (core/characters/actor_base.gd), not only NPCBase —
# PatrolDroneController (world/police_drone/controllers/) extends this same
# base to drive DroneBase. A child of the actor node it drives (same shape
# as input_hover_controller.gd feeding HoverBase). Fetches its ActorBase
# parent once in _ready() and calls _decide(delta) every physics frame —
# nothing else. A subclass overrides _decide() and nothing else needs to
# change when the decision approach changes: body, movement and perception
# all sit on the other side of this one method and don't know it happened.
# =============================================================================
extends Node
class_name NPCControllerBase

## Parent actor body this controller drives. Set once in _ready().
var _actor: ActorBase = null


func _ready() -> void:
	var parent := get_parent()
	if not (parent is ActorBase):
		push_error("NPCControllerBase: parent '%s' is not an ActorBase — controller disabled" % parent.name)
		set_physics_process(false)
		return
	_actor = parent


func _physics_process(delta: float) -> void:
	_decide(delta)


## The only layer that changes when the AI approach changes. Everything else
## — body, movement, perception — survives a switch from a hand-written state
## machine to a behaviour tree. Keep decisions here and nothing else.
func _decide(_delta: float) -> void:
	pass
