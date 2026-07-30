# =============================================================================
# idle_npc_controller.gd — IdleNPCController: stands still.
#
# First and, for now, only decision strategy: writes a permanently-zero
# intent every frame. The point of this step is proving the
# NPCControllerBase -> NPCBase.set_move_intent() contract closes end to end,
# not that the NPC does anything yet — perception, navigation and reactions
# are later commits.
# =============================================================================
extends NPCControllerBase
class_name IdleNPCController


func _decide(_delta: float) -> void:
	_npc.set_move_intent(Vector3.ZERO, 0.0)
