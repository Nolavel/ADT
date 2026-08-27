# =============================================================================
# equipment_visuals_component.gd — makes EquipmentComponent visible.
#
# Reflects state, never owns it. Every decision about what is worn, stowed or
# drawn was already made and saved by EquipmentComponent; this component
# subscribes and moves meshes. Deleting it must change nothing except what is
# on screen — which is also the fastest way to prove a bug is not the
# visuals'.
#
# Two mechanisms, deliberately not interchangeable:
#
#   CLOTHING     a skinned MeshInstance3D already in the rig, found by the
#                name GarmentData.mesh_node_name gives, toggled visible.
#   HELD ITEM    a MeshInstance3D built under a BoneAttachment3D on the hand.
#                Rigid, which is exactly right for something that does not
#                bend. Placement comes from ItemResource.pose (ItemPose).
#
# EQUIPMENT IS AUTHORITATIVE over the visibility the scene authored.
#
# 2026-08-27 — held item placement prefers ItemResource.pose.
#              Supports single-hand and two-hand poses.
#              Old global held_offset / held_rotation_deg remain as fallback
#              for items that have not been authored yet.
# =============================================================================
extends Node
class_name EquipmentVisualsComponent


## The skeleton every visible mesh is actually skinned to. NOT GeneralSkeleton
## — that one drives the animation and indexes its bones differently
## (Head is 6 there and 5 here). Getting this wrong is the easiest mistake.
@export var skeleton_path: NodePath = ^"../player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton"

## The equipment this reflects. Sibling by default.
@export var equipment_path: NodePath = ^"../EquipmentComponent"

## Default right-hand BoneAttachment3D. Used when the pose names RightHand
## or when the item has no pose.
@export var hand_attachment_path: NodePath = ^"../player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/RightHandAttachment"

## Optional left-hand BoneAttachment3D. Created on demand if missing when a
## two-hand pose is applied.
@export var left_hand_attachment_path: NodePath = ^"../player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/LeftHandAttachment"

## Fallback when ItemResource.pose is null. Migration path only.
@export var held_offset: Vector3 = Vector3.ZERO
@export var held_rotation_deg: Vector3 = Vector3.ZERO

## Seconds between draw start and the mesh appearing (sync with draw anim).
@export var draw_attach_delay: float = 0.22

@export var debug_log: bool = false


var _skeleton: Node = null
var _equipment: EquipmentComponent = null
var _slot_meshes: Dictionary = {}
var _garment_mesh_names: Array[StringName] = []
var _hand_attachment: Node3D = null
var _left_hand_attachment: Node3D = null
## Primary (right) held mesh.
var _held_instance: MeshInstance3D = null
## Secondary (left) held mesh — only for two-hand poses.
var _held_instance_left: MeshInstance3D = null
## BoneAttachment3D nodes created on demand for non-default bones.
var _extra_attachments: Dictionary = {}


func _ready() -> void:
	_skeleton = get_node_or_null(skeleton_path)
	_equipment = get_node_or_null(equipment_path) as EquipmentComponent
	if _skeleton == null:
		push_warning("[EquipmentVisuals] no skeleton at %s — clothing will not update" % skeleton_path)
	if _equipment == null:
		push_warning("[EquipmentVisuals] no EquipmentComponent at %s — inert" % equipment_path)
		return

	_hand_attachment = get_node_or_null(hand_attachment_path) as Node3D
	if _hand_attachment == null:
		push_warning("[EquipmentVisuals] no hand attachment at %s — held items stay invisible" % hand_attachment_path)

	_left_hand_attachment = get_node_or_null(left_hand_attachment_path) as Node3D
	# Left is optional until a two-hand pose needs it; we create it later if missing.

	_collect_garment_mesh_names()
	_equipment.slot_changed.connect(_on_slot_changed)
	_equipment.drawn_changed.connect(_on_drawn_changed)
	refresh_all()
	_on_drawn_changed(_equipment.get_drawn())


func refresh_all() -> void:
	if _equipment == null or _skeleton == null:
		return
	if _equipment.layout == null:
		return
	_hide_all_garment_meshes()
	for body_slot in _equipment.layout.body_slots:
		if body_slot != null:
			_apply_body_slot(body_slot.id)


func _on_drawn_changed(item_id: StringName) -> void:
	_clear_held()
	if item_id == &"" or _skeleton == null:
		return

	if draw_attach_delay > 0.0:
		await get_tree().create_timer(draw_attach_delay).timeout
		if not is_instance_valid(self) or _equipment == null:
			return
		if _equipment.get_drawn() != item_id:
			return

	var item := ItemCatalog.get_item(item_id)
	if item == null or item.held_mesh == null:
		return

	_spawn_held(item)


func _clear_held() -> void:
	if _held_instance != null:
		_held_instance.queue_free()
		_held_instance = null
	if _held_instance_left != null:
		_held_instance_left.queue_free()
		_held_instance_left = null


func _spawn_held(item: ItemResource) -> void:
	var pose: ItemPose = item.pose

	# --- Primary (right) hand ---
	var right_attach := _resolve_attachment(
		pose.right_hand_bone if pose else &"RightHand",
		_hand_attachment
	)
	if right_attach == null:
		return

	_held_instance = MeshInstance3D.new()
	_held_instance.name = "HeldItem"
	_held_instance.mesh = item.held_mesh

	if pose != null:
		_held_instance.transform = pose.primary_transform()
		if debug_log:
			print("[EquipmentVisuals] holding %s via ItemPose (R:%s)" % [item.id, pose.right_hand_bone])
	else:
		_held_instance.position = held_offset
		_held_instance.rotation_degrees = held_rotation_deg
		if debug_log:
			print("[EquipmentVisuals] holding %s via fallback offsets" % item.id)

	right_attach.add_child(_held_instance)

	# --- Secondary (left) hand — only for two-hand poses ---
	if pose != null and pose.is_two_hand():
		var left_attach := _resolve_attachment(pose.left_hand_bone, _left_hand_attachment)
		if left_attach == null:
			# Try to create LeftHandAttachment on the fly.
			left_attach = _ensure_bone_attachment(pose.left_hand_bone)
		if left_attach != null:
			_held_instance_left = MeshInstance3D.new()
			_held_instance_left.name = "HeldItemLeft"
			_held_instance_left.mesh = item.held_mesh
			_held_instance_left.transform = pose.secondary_transform()
			left_attach.add_child(_held_instance_left)
			if debug_log:
				print("[EquipmentVisuals] two-hand secondary on %s" % pose.left_hand_bone)


## Returns an existing attachment for the bone, or creates one under the skeleton.
func _resolve_attachment(bone_name: StringName, preferred: Node3D) -> Node3D:
	if bone_name == &"" or bone_name == &"RightHand":
		return preferred
	if preferred != null and preferred is BoneAttachment3D:
		var ba := preferred as BoneAttachment3D
		if ba.bone_name == String(bone_name):
			return preferred
	return _ensure_bone_attachment(bone_name)


func _ensure_bone_attachment(bone_name: StringName) -> Node3D:
	if _extra_attachments.has(bone_name):
		return _extra_attachments[bone_name] as Node3D
	if _skeleton == null or bone_name == &"":
		return null
	var attach := BoneAttachment3D.new()
	attach.name = "%sAttachment" % bone_name
	attach.bone_name = String(bone_name)
	_skeleton.add_child(attach)
	_extra_attachments[bone_name] = attach
	if debug_log:
		print("[EquipmentVisuals] created BoneAttachment3D for %s" % bone_name)
	return attach


func _on_slot_changed(slot_path: StringName, _item_id: StringName) -> void:
	if String(slot_path).contains(EquipmentComponent.POCKET_SEPARATOR):
		return
	_apply_body_slot(slot_path)


func _apply_body_slot(slot_id: StringName) -> void:
	var previous := _mesh_for_slot(slot_id)
	if previous != null:
		previous.visible = false

	var item_id := _equipment.get_equipped(slot_id)
	if item_id == &"":
		return
	var item := ItemCatalog.get_item(item_id)
	if item == null or item.garment == null:
		return
	var mesh := _find_mesh(item.garment.mesh_node_name)
	if mesh == null:
		return
	mesh.visible = true
	_slot_meshes[slot_id] = mesh
	if debug_log:
		print("[EquipmentVisuals] %s -> %s visible" % [slot_id, item.garment.mesh_node_name])


func _hide_all_garment_meshes() -> void:
	for mesh_name in _garment_mesh_names:
		var mesh := _skeleton.get_node_or_null(NodePath(String(mesh_name))) as MeshInstance3D
		if mesh != null:
			mesh.visible = false


func _collect_garment_mesh_names() -> void:
	_garment_mesh_names.clear()
	var catalog := ItemCatalog.shared()
	if catalog == null:
		return
	for item in catalog.items:
		if item == null or item.garment == null:
			continue
		var mesh_name := item.garment.mesh_node_name
		if mesh_name != &"" and not _garment_mesh_names.has(mesh_name):
			_garment_mesh_names.append(mesh_name)


func _mesh_for_slot(slot_id: StringName) -> MeshInstance3D:
	return _slot_meshes.get(slot_id) as MeshInstance3D


func _find_mesh(mesh_name: StringName) -> MeshInstance3D:
	if _skeleton == null or mesh_name == &"":
		return null
	var found := _skeleton.get_node_or_null(NodePath(String(mesh_name)))
	if found == null:
		push_warning("[EquipmentVisuals] no mesh named '%s' under the skeleton" % mesh_name)
		return null
	return found as MeshInstance3D
