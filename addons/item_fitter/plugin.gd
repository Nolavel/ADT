# =============================================================================
# plugin.gd — Item Fitter, an EditorPlugin.
#
# The thing this exists to solve: a held item's mesh is built at RUNTIME by
# EquipmentVisualsComponent, so in the editor there is nothing in the hand to
# look at. Tuning HeldFit meant editing three numbers in a .tres, launching
# the game, drawing the weapon, squinting, and starting again — which is how
# the carbine ended up wearing the pistol's offsets for a whole build.
#
# WHY AN ADDON AND NOT tools/. Everything else in this project's tooling is
# one of two shapes, and neither fits: an EditorScript (File → Run) is a
# one-shot with no UI and no gizmo, and a debug panel instanced into
# world.tscn does not exist at edit time at all. Fitting an object to a hand
# needs a dock, the editor's own 3D gizmo on a live node, and to survive a
# scene switch — and only an EditorPlugin gets those three.
#
# WHAT IT WRITES: HeldFit on the ItemResource, and nothing else. It reads
# item.held_mesh and knows no item by name, so the next weapon, tool or torch
# works without a line changed here. Where a STOWED item sits is the intended
# next use — a second HeldFit field on the item, and one more picker here.
# =============================================================================
@tool
extends EditorPlugin

const DOCK_SCENE: PackedScene = preload("res://addons/item_fitter/item_fitter_dock.tscn")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = DOCK_SCENE.instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if _dock == null:
		return
	## The dock clears its own preview node first. Leaving one behind would
	## put a stray MeshInstance3D in whatever scene was open — harmless to
	## the file (the preview is spawned with owner = null and cannot be
	## serialised) but confusing to look at.
	_dock.clear_preview()
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
