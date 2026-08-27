# =============================================================================
# item_pose_authoring.gd — the live authoring scene for ItemPose.
#
# How the user works
# ------------------
# 1. Open this scene (Project → Tools → Item Pose Authoring, or open the .tscn).
# 2. The player is already in the scene. Select an animation (idle by default)
#    and press Play — the skeleton settles into that pose.
# 3. Pick an ItemResource from the list. The plugin spawns its held_mesh under
#    the right-hand BoneAttachment3D (and under the left-hand one if
#    "Two-hand" is checked).
# 4. Move / rotate the preview mesh(es) with the normal Godot gizmos in the
#    3D viewport. What you see is what will be saved.
# 5. Press Save Pose. Current local transforms become an ItemPose Resource,
#    written to data/item_poses/<id>_pose.tres and assigned to ItemResource.pose.
#
# Left hand
# ---------
# Toggle "Two-hand" on the panel. A second preview appears under
# LeftHandAttachment. Move it independently. Save writes both transforms
# into the same ItemPose (left_hand_bone is filled automatically).
#
# This script is @tool so it runs inside the editor. It never runs at
# game runtime and never touches EquipmentComponent.
# =============================================================================

@tool
extends Node3D


## Path to the player instance inside this scene.
@export var player_path: NodePath = ^"Player"

## Path to OriginalSkeleton under the player.
@export var skeleton_path: NodePath = ^"Player/player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton"

## Existing or expected right-hand attachment.
@export var right_attachment_path: NodePath = ^"Player/player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/RightHandAttachment"

## Left-hand attachment (created on demand if missing).
@export var left_attachment_path: NodePath = ^"Player/player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/LeftHandAttachment"

## Where saved poses go.
const POSE_DIR := "res://data/item_poses/"


var _player: Node = null
var _skeleton: Node = null
var _right_attach: Node3D = null
var _left_attach: Node3D = null
var _anim_player: AnimationPlayer = null

var _current_item: ItemResource = null
var _preview_right: MeshInstance3D = null
var _preview_left: MeshInstance3D = null
var _two_hand: bool = false

# --- UI nodes (built in _ready if the scene has a CanvasLayer/UI root) ---
var _item_option: OptionButton = null
var _anim_option: OptionButton = null
var _two_hand_check: CheckBox = null
var _status_label: Label = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		# This scene is editor-only. If somehow run in game, do nothing.
		return

	_player = get_node_or_null(player_path)
	_skeleton = get_node_or_null(skeleton_path)
	_right_attach = get_node_or_null(right_attachment_path) as Node3D
	_left_attach = get_node_or_null(left_attachment_path) as Node3D

	if _skeleton == null:
		push_warning("[ItemPoseAuthoring] skeleton not found at %s" % skeleton_path)
	if _right_attach == null:
		push_warning("[ItemPoseAuthoring] RightHandAttachment not found — will try to create")

	_find_animation_player()
	_build_ui_if_needed()
	_populate_item_list()
	_populate_anim_list()


# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------

func _build_ui_if_needed() -> void:
	# Prefer an existing UI root if the .tscn already has one.
	var ui_root := get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		ui_root = CanvasLayer.new()
		ui_root.name = "UI"
		add_child(ui_root)

	var panel := ui_root.get_node_or_null("Panel") as PanelContainer
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "Panel"
		panel.position = Vector2(16, 16)
		panel.custom_minimum_size = Vector2(280, 0)
		ui_root.add_child(panel)

		var vbox := VBoxContainer.new()
		panel.add_child(vbox)

		var title := Label.new()
		title.text = "ITEM POSE"
		title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(title)

		vbox.add_child(_make_label("Item"))
		_item_option = OptionButton.new()
		_item_option.item_selected.connect(_on_item_selected)
		vbox.add_child(_item_option)

		vbox.add_child(_make_label("Animation"))
		_anim_option = OptionButton.new()
		vbox.add_child(_anim_option)

		var play_btn := Button.new()
		play_btn.text = "Play Animation"
		play_btn.pressed.connect(_on_play_animation)
		vbox.add_child(play_btn)

		_two_hand_check = CheckBox.new()
		_two_hand_check.text = "Two-hand (left hand)"
		_two_hand_check.toggled.connect(_on_two_hand_toggled)
		vbox.add_child(_two_hand_check)

		var save_btn := Button.new()
		save_btn.text = "Save Pose"
		save_btn.pressed.connect(_on_save_pose)
		vbox.add_child(save_btn)

		var clear_btn := Button.new()
		clear_btn.text = "Clear Preview"
		clear_btn.pressed.connect(_clear_preview)
		vbox.add_child(clear_btn)

		_status_label = Label.new()
		_status_label.text = "Select an item, pose it, Save."
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_status_label)
	else:
		# Scene already has a panel — try to find the controls by name.
		_item_option = panel.find_child("ItemOption", true, false) as OptionButton
		_anim_option = panel.find_child("AnimOption", true, false) as OptionButton
		_two_hand_check = panel.find_child("TwoHandCheck", true, false) as CheckBox
		_status_label = panel.find_child("StatusLabel", true, false) as Label


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
	print("[ItemPoseAuthoring] %s" % msg)


# -----------------------------------------------------------------------------
# Catalog / Animation
# -----------------------------------------------------------------------------

func _populate_item_list() -> void:
	if _item_option == null:
		return
	_item_option.clear()
	_item_option.add_item("— none —", 0)
	_item_option.set_item_metadata(0, null)

	var catalog := ItemCatalog.shared()
	if catalog == null:
		_set_status("ItemCatalog not found")
		return

	var idx := 1
	for item in catalog.items:
		if item == null or item.held_mesh == null:
			continue
		# Only items that can appear in hands matter here.
		if not item.can_use_in_hands:
			continue
		_item_option.add_item(String(item.id), idx)
		_item_option.set_item_metadata(idx, item)
		idx += 1


func _find_animation_player() -> void:
	if _player == null:
		return
	# Common places an AnimationPlayer lives on the player.
	var candidates: Array[String] = [
		"AnimationPlayer",
		"player_base_mesh/AnimationPlayer",
		"AnimationTree",
	]
	for path in candidates:
		var node := _player.get_node_or_null(path)
		if node is AnimationPlayer:
			_anim_player = node as AnimationPlayer
			break
	# Deep search as last resort.
	if _anim_player == null:
		_anim_player = _find_first_animation_player(_player)


func _find_first_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_first_animation_player(child)
		if found:
			return found
	return null


func _populate_anim_list() -> void:
	if _anim_option == null:
		return
	_anim_option.clear()
	if _anim_player == null:
		_anim_option.add_item("(no AnimationPlayer found)")
		return
	var names := _anim_player.get_animation_list()
	for n in names:
		_anim_option.add_item(n)
	# Prefer idle if present.
	for i in names.size():
		if String(names[i]).to_lower().contains("idle"):
			_anim_option.select(i)
			break


func _on_play_animation() -> void:
	if _anim_player == null or _anim_option == null:
		_set_status("No AnimationPlayer")
		return
	var anim_name := _anim_option.get_item_text(_anim_option.selected)
	if anim_name.is_empty() or anim_name.begins_with("("):
		return
	_anim_player.play(anim_name)
	_set_status("Playing: %s" % anim_name)


# -----------------------------------------------------------------------------
# Item preview
# -----------------------------------------------------------------------------

func _on_item_selected(index: int) -> void:
	var item: ItemResource = _item_option.get_item_metadata(index) as ItemResource
	_current_item = item
	_clear_preview()
	if item == null:
		_set_status("No item")
		return
	_spawn_preview(item)
	_set_status("Preview: %s — move it, then Save" % item.id)


func _on_two_hand_toggled(pressed: bool) -> void:
	_two_hand = pressed
	if _current_item != null:
		_clear_preview()
		_spawn_preview(_current_item)


func _spawn_preview(item: ItemResource) -> void:
	if item.held_mesh == null:
		_set_status("Item has no held_mesh")
		return

	# Ensure right attachment exists.
	if _right_attach == null and _skeleton != null:
		_right_attach = _ensure_attachment(&"RightHand")
	if _right_attach == null:
		_set_status("No right-hand attachment")
		return

	_preview_right = MeshInstance3D.new()
	_preview_right.name = "PosePreview_Right"
	_preview_right.mesh = item.held_mesh
	# If the item already has a pose, start from it so the user can refine.
	if item.pose != null:
		_preview_right.transform = item.pose.primary_transform()
	_right_attach.add_child(_preview_right)

	if _two_hand:
		if _left_attach == null and _skeleton != null:
			_left_attach = _ensure_attachment(&"LeftHand")
		if _left_attach != null:
			_preview_left = MeshInstance3D.new()
			_preview_left.name = "PosePreview_Left"
			_preview_left.mesh = item.held_mesh
			if item.pose != null and item.pose.is_two_hand():
				_preview_left.transform = item.pose.secondary_transform()
			_left_attach.add_child(_preview_left)


func _ensure_attachment(bone_name: StringName) -> Node3D:
	if _skeleton == null:
		return null
	var existing := _skeleton.get_node_or_null("%sAttachment" % bone_name)
	if existing is BoneAttachment3D:
		return existing as Node3D
	var attach := BoneAttachment3D.new()
	attach.name = "%sAttachment" % bone_name
	attach.bone_name = String(bone_name)
	_skeleton.add_child(attach)
	# Make sure it is owned by the scene so it can be saved if desired.
	if Engine.is_editor_hint() and is_inside_tree():
		attach.owner = get_tree().edited_scene_root
	return attach


func _clear_preview() -> void:
	if _preview_right != null:
		_preview_right.queue_free()
		_preview_right = null
	if _preview_left != null:
		_preview_left.queue_free()
		_preview_left = null


# -----------------------------------------------------------------------------
# Save
# -----------------------------------------------------------------------------

func _on_save_pose() -> void:
	if _current_item == null:
		_set_status("No item selected")
		return
	if _preview_right == null:
		_set_status("No preview — select an item first")
		return

	var pose := ItemPose.new()
	pose.right_hand_bone = &"RightHand"
	pose.position = _preview_right.position
	pose.rotation_deg = _preview_right.rotation_degrees
	pose.scale = _preview_right.scale

	if _two_hand and _preview_left != null:
		pose.left_hand_bone = &"LeftHand"
		pose.secondary_position = _preview_left.position
		pose.secondary_rotation_deg = _preview_left.rotation_degrees
		pose.secondary_scale = _preview_left.scale
	else:
		pose.left_hand_bone = &""

	# Ensure directory exists.
	if not DirAccess.dir_exists_absolute(POSE_DIR):
		DirAccess.make_dir_recursive_absolute(POSE_DIR)

	var path := POSE_DIR + "%s_pose.tres" % String(_current_item.id)
	var err := ResourceSaver.save(pose, path)
	if err != OK:
		_set_status("Save failed: error %s" % err)
		return

	# Link the saved resource back onto the item so runtime finds it.
	_current_item.pose = load(path) as ItemPose
	if _current_item.resource_path != "":
		ResourceSaver.save(_current_item, _current_item.resource_path)

	var hand_info := "two-hand" if pose.is_two_hand() else "single-hand"
	_set_status("Saved %s (%s) → %s" % [_current_item.id, hand_info, path])
