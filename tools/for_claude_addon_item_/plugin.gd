# =============================================================================
# plugin.gd — Item Pose Editor (EditorPlugin).
#
# Pure authoring tool. Never runs in an exported build.
# Never touches EquipmentComponent or runtime state.
#
# Workflow this plugin supports:
#
#   1. User opens the authoring scene (or clicks "Open Pose Authoring").
#   2. Player stands in idle (or any chosen animation).
#   3. User picks an ItemResource → plugin spawns held_mesh under the hand(s).
#   4. User moves / rotates the preview mesh(es) with normal viewport gizmos.
#   5. User presses Save → current transform(s) become an ItemPose Resource.
#   6. Resource is written to data/item_poses/ and linked on ItemResource.pose.
#
# The only contract with the rest of the project is the shape of ItemPose
# and the optional ItemResource.pose field.
# =============================================================================

@tool
extends EditorPlugin


const AUTHORING_SCENE_PATH := "res://addons/item_pose_editor/item_pose_authoring.tscn"
const MENU_LABEL := "Item Pose Authoring"


func _enter_tree() -> void:
	add_tool_menu_item(MENU_LABEL, _on_open_authoring)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_LABEL)


func _on_open_authoring() -> void:
	var editor := get_editor_interface()
	if not ResourceLoader.exists(AUTHORING_SCENE_PATH):
		push_error("[ItemPoseEditor] authoring scene missing: %s" % AUTHORING_SCENE_PATH)
		return
	editor.open_scene_from_path(AUTHORING_SCENE_PATH)
	print("[ItemPoseEditor] opened authoring scene")
