# =============================================================================
# item_fitter_dock.gd — the Item Fitter's panel.
#
# Five controls and two buttons, in the order the job is actually done: pick
# the item, pick the hand, pick and scrub an animation, drag the mesh in the
# viewport with the ordinary gizmo, save.
#
# THE PREVIEW IS A REAL NODE, parented to the same GripPivot the game uses at
# runtime. That is the whole trick — the editor's own move/rotate gizmo works
# on it for free, and because the pivot cancels the rig's 0.38763407 scale,
# the numbers under the gizmo are in metres and mean exactly what HeldFit
# stores. Nothing here re-implements a transform editor.
#
# It is spawned with `owner = null`, which is what keeps it out of the saved
# scene: Godot serialises a node only if it is owned by the scene root. So
# the preview can never be committed into player.tscn by someone pressing
# Ctrl+S with the dock open — worth stating, because that is the failure this
# kind of tool usually ships with.
#
# ItemCatalog is not used. It resolves ids through a statically loaded .tres,
# which would work here, but the dock has no id to resolve — the picker hands
# over the ItemResource itself, which is both simpler and what an editor user
# expects to drag in.
# =============================================================================
@tool
extends Control

## Where the preview goes, by node name inside the edited scene. Looked up
## rather than exported so the dock works on any character scene that follows
## the same convention, and fails with a readable message on one that does
## not.
const RIGHT_GRIP_HINT: String = "RightHandAttachment/GripPivot"
const LEFT_GRIP_HINT: String = "LeftHandAttachment/GripPivot"

var _item: ItemResource = null
var _preview: MeshInstance3D = null
var _animation_player: AnimationPlayer = null

@onready var _item_picker: EditorResourcePicker = $Layout/ItemPicker
@onready var _hand_button: OptionButton = $Layout/HandRow/HandButton
@onready var _animation_button: OptionButton = $Layout/AnimationRow/AnimationButton
@onready var _time_slider: HSlider = $Layout/TimeSlider
@onready var _status: Label = $Layout/Status
@onready var _save_button: Button = $Layout/Buttons/SaveButton
@onready var _revert_button: Button = $Layout/Buttons/RevertButton


func _ready() -> void:
	name = "Item Fit"
	_item_picker.base_type = "ItemResource"
	_item_picker.resource_changed.connect(_on_item_changed)

	_hand_button.clear()
	_hand_button.add_item("Right hand", HeldFit.Hand.RIGHT)
	_hand_button.add_item("Left hand", HeldFit.Hand.LEFT)
	_hand_button.item_selected.connect(_on_hand_selected)

	_animation_button.item_selected.connect(_on_animation_selected)
	_time_slider.value_changed.connect(_on_time_changed)
	_save_button.pressed.connect(_on_save_pressed)
	_revert_button.pressed.connect(_on_revert_pressed)

	_set_status("Open a character scene and pick an item.")


# -----------------------------------------------------------------------------
# ## ENG: The preview node
# -----------------------------------------------------------------------------

## Removes the preview and forgets it. Safe to call at any time, including
## when there is none — plugin.gd calls it unconditionally on unload.
func clear_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.get_parent().remove_child(_preview)
		_preview.queue_free()
	_preview = null


## Builds the preview under the grip pivot for the chosen hand, applying
## whatever fit the item already carries — so opening the dock on a fitted
## item shows the fit rather than resetting it.
func _rebuild_preview() -> void:
	clear_preview()
	if _item == null:
		_set_status("Pick an item.")
		return
	if _item.held_mesh == null:
		_set_status("'%s' has no held_mesh — nothing to fit." % _item.id)
		return

	var grip := _find_grip(_hand_button.get_selected_id())
	if grip == null:
		_set_status("No %s in the open scene. Open the character scene first."
				% _grip_hint(_hand_button.get_selected_id()))
		return

	_preview = MeshInstance3D.new()
	_preview.name = "ItemFitPreview"
	_preview.mesh = _item.held_mesh
	grip.add_child(_preview)
	## Deliberately NOT set to the scene root. An unowned node is not
	## serialised, so this cannot end up saved into the character scene.
	_preview.owner = null
	_apply_fit_to_preview()

	## Selected so the move/rotate gizmo is already on it — the whole point
	## of the preview being a real node rather than three spinboxes here.
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(_preview)
	_set_status("Drag it into the hand, then Save to item. Values are in metres.")


func _apply_fit_to_preview() -> void:
	if _preview == null:
		return
	var fit: HeldFit = _item.held_fit if _item != null else null
	if fit == null:
		_preview.transform = Transform3D.IDENTITY
		return
	_preview.position = fit.offset
	_preview.rotation_degrees = fit.rotation_deg
	_preview.scale = fit.scale


## The GripPivot for a hand, searched by path suffix rather than an absolute
## path: the attachments sit deep under a retarget skeleton whose path is
## long and rig-specific, and a suffix match keeps this working on a rig
## whose intermediate nodes are named differently.
func _find_grip(hand: int) -> Node3D:
	var root := _edited_root()
	if root == null:
		return null
	var hint := _grip_hint(hand)
	for node in _all_descendants(root):
		if node is Node3D and String(root.get_path_to(node)).ends_with(hint):
			return node
	return null


func _grip_hint(hand: int) -> String:
	return LEFT_GRIP_HINT if hand == HeldFit.Hand.LEFT else RIGHT_GRIP_HINT


func _all_descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_all_descendants(child))
	return found


## EditorInterface is used as the 4.2+ singleton rather than through
## EditorPlugin.get_editor_interface(), which is deprecated. Safe in this
## file specifically: the dock is @tool and is only ever instantiated by the
## plugin, inside the editor.
func _edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()


# -----------------------------------------------------------------------------
# ## ENG: Animation
# -----------------------------------------------------------------------------

## Fills the clip list from the edited scene's AnimationPlayer. Rebuilt on
## every item change rather than cached: the open scene can change underneath
## the dock, and a stale clip list is a list of names that no longer resolve.
func _refresh_animations() -> void:
	_animation_button.clear()
	_animation_player = null
	var root := _edited_root()
	if root == null:
		return
	for node in _all_descendants(root):
		if node is AnimationPlayer:
			_animation_player = node
			break
	if _animation_player == null:
		return

	_animation_button.add_item("(rest pose)", 0)
	var index := 1
	for clip in _animation_player.get_animation_list():
		_animation_button.add_item(String(clip), index)
		index += 1


func _on_animation_selected(index: int) -> void:
	if _animation_player == null:
		return
	if index <= 0:
		_animation_player.stop()
		_time_slider.max_value = 1.0
		_time_slider.value = 0.0
		return
	var clip := _animation_button.get_item_text(index)
	var animation := _animation_player.get_animation(clip)
	if animation == null:
		return
	_time_slider.max_value = animation.length
	_time_slider.value = 0.0
	## Played and immediately paused, then driven by the slider. A running
	## clip is no use for judging a grip — the pose has to hold still while
	## the mesh is dragged, and the interesting frames are the extremes
	## rather than whatever the playhead happens to be on.
	_animation_player.play(clip)
	_animation_player.pause()
	_animation_player.seek(0.0, true)


func _on_time_changed(value: float) -> void:
	if _animation_player == null or not _animation_player.is_playing():
		return
	_animation_player.seek(value, true)


# -----------------------------------------------------------------------------
# ## ENG: Saving
# -----------------------------------------------------------------------------

## Writes the preview's local transform into the item's HeldFit and saves the
## .tres. The transform is read from the node rather than from fields in this
## dock, so whatever was done in the viewport — gizmo, inspector, snapping —
## is what gets stored.
func _on_save_pressed() -> void:
	if _item == null or _preview == null:
		_set_status("Nothing to save.")
		return

	var fit := _item.held_fit
	if fit == null:
		fit = HeldFit.new()
		_item.held_fit = fit
	fit.hand = _hand_button.get_selected_id() as HeldFit.Hand
	fit.offset = _preview.position
	fit.rotation_deg = _preview.rotation_degrees
	fit.scale = _preview.scale

	var path := _item.resource_path
	if path.is_empty():
		_set_status("This item has no file on disk — save it as a .tres first.")
		return
	var err := ResourceSaver.save(_item, path)
	if err != OK:
		_set_status("Save failed (%d): %s" % [err, path])
		return
	_set_status("Saved to %s" % path.get_file())


func _on_revert_pressed() -> void:
	_apply_fit_to_preview()
	_set_status("Reverted to the fit stored on the item.")


# -----------------------------------------------------------------------------
# ## ENG: Internals
# -----------------------------------------------------------------------------

func _on_item_changed(resource: Resource) -> void:
	_item = resource as ItemResource
	if _item != null and _item.held_fit != null:
		_hand_button.select(_hand_button.get_item_index(_item.held_fit.hand))
	_refresh_animations()
	_rebuild_preview()


func _on_hand_selected(_index: int) -> void:
	_rebuild_preview()


func _set_status(text: String) -> void:
	_status.text = text
