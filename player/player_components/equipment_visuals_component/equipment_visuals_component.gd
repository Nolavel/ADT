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
#                name GarmentData.mesh_node_name gives, toggled visible. It
#                deforms with the body because it is skinned to the whole
#                skeleton — a bone attachment would follow one bone rigidly
#                and trousers would not bend at the knee.
#   HELD ITEM    a MeshInstance3D built under a BoneAttachment3D on the hand.
#                Rigid, which is exactly right for something that does not
#                bend.
#
# EQUIPMENT IS AUTHORITATIVE over the visibility the scene authored. A garment
# mesh is hidden unless something worn actually names it — refresh_all() sweeps
# every mesh the catalog knows about before showing anything. Without that
# sweep the scene's own `visible = true` would survive an empty equipment
# component, and the two would only agree by coincidence.
# =============================================================================
extends Node
class_name EquipmentVisualsComponent

## The skeleton every visible mesh is actually skinned to. NOT GeneralSkeleton
## — that one drives the animation and indexes its bones differently
## (Head is 6 there and 5 here). Getting this wrong is the easiest mistake in
## this file.
@export var skeleton_path: NodePath = ^"../player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton"

## The equipment this reflects. Sibling by default.
@export var equipment_path: NodePath = ^"../EquipmentComponent"

## Where a drawn item is parented. A BoneAttachment3D on the hand, NOT on
## the body root — the prop has to follow the hand through the animation.
@export var hand_attachment_path: NodePath = ^"../player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton/RightHandAttachment"

## Position and rotation of a held item inside the hand, in the attachment's
## local space.
##
## Exported rather than baked into the scene node's transform for the same
## reason VotiveProjector exports bone_local_offset: a bone's local axes
## rarely match anything's forward assumption, and the right values can only
## be found by looking at it. These are meant to be dragged in the inspector
## until the thing sits in the fist — they are not defaults anybody computed.
@export var held_offset: Vector3 = Vector3.ZERO
@export var held_rotation_deg: Vector3 = Vector3.ZERO

@export var debug_log: bool = false

var _skeleton: Node = null
var _equipment: EquipmentComponent = null
## Which mesh a body slot last showed, so it can be hidden again without
## asking the item that is no longer there. Overwritten, never cleared.
var _slot_meshes: Dictionary = {}
## Every mesh name any garment in the catalog claims, collected once. The
## catalog is immutable, so this cannot go stale; it exists so the sweep in
## refresh_all() does not walk every item on every call.
var _garment_mesh_names: Array[StringName] = []
var _hand_attachment: Node3D = null
## The MeshInstance3D currently in the hand, built on draw and freed on
## holster. Built rather than pre-made and hidden: an item's mesh is per-item
## data, so there is nothing to pre-make.
var _held_instance: MeshInstance3D = null


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

	_collect_garment_mesh_names()
	_equipment.slot_changed.connect(_on_slot_changed)
	_equipment.drawn_changed.connect(_on_drawn_changed)
	## Applied once at start rather than waiting for the next change: the
	## starter garments are equipped in EquipmentComponent._ready(), which
	## may already have run, and a load replaces everything wholesale without
	## emitting per-slot signals.
	refresh_all()
	_on_drawn_changed(_equipment.get_drawn())


## Brings every garment mesh into line with what is currently worn. Cheap and
## idempotent — call it after anything that changes equipment in bulk.
func refresh_all() -> void:
	if _equipment == null or _skeleton == null:
		return
	if _equipment.layout == null:
		return
	_hide_all_garment_meshes()
	for body_slot in _equipment.layout.body_slots:
		if body_slot != null:
			_apply_body_slot(body_slot.id)


## Builds the held mesh on draw, frees it on holster. Freed rather than
## hidden: the next drawn item is a different mesh, so a kept instance would
## only have to be rebuilt anyway.
func _on_drawn_changed(item_id: StringName) -> void:
	if _held_instance != null:
		_held_instance.queue_free()
		_held_instance = null
	if item_id == &"" or _hand_attachment == null:
		return

	var item := ItemCatalog.get_item(item_id)
	if item == null or item.held_mesh == null:
		## The drawn state is still correct — this item simply has no mesh
		## yet. Silent on purpose: most items will be in this position for a
		## long time, and a warning per draw would be noise.
		return

	_held_instance = MeshInstance3D.new()
	_held_instance.mesh = item.held_mesh
	_held_instance.position = held_offset
	_held_instance.rotation_degrees = held_rotation_deg
	_hand_attachment.add_child(_held_instance)
	if debug_log:
		print("[EquipmentVisuals] holding %s" % item_id)


func _on_slot_changed(slot_path: StringName, _item_id: StringName) -> void:
	## Pockets have no visual — their whole point is that the contents are
	## out of sight. Only body slots carry a garment mesh.
	if String(slot_path).contains(EquipmentComponent.POCKET_SEPARATOR):
		return
	_apply_body_slot(slot_path)


## One body slot's mesh follows what is in it. The mesh is hidden first and
## shown only if something worn actually names it, so unequipping and
## swapping both land in the same place without a separate "hide the old one"
## path.
func _apply_body_slot(slot_id: StringName) -> void:
	var previous := _mesh_for_slot(slot_id)
	if previous != null:
		previous.visible = false

	## An empty slot is answered before the catalog is asked. refresh_all()
	## walks every body slot, and three of the player's five are empty, so
	## without this guard get_item() warns "unknown item id ''" three times on
	## every refresh for a question whose answer is "nothing is worn there".
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


## Hides every mesh any garment could show, so what stays visible afterwards is
## only what is actually worn. Only meshes NAMED BY AN ITEM are touched — the
## body, the headset and the unassigned details mesh are named by nothing and
## are never hidden by this.
func _hide_all_garment_meshes() -> void:
	for mesh_name in _garment_mesh_names:
		## Resolved directly rather than through _find_mesh(): a garment whose
		## mesh does not exist in this rig is a normal state (an NPC rig, a
		## garment authored ahead of its art), and warning about it once per
		## sweep would bury the warning that matters — the one _find_mesh()
		## raises when something is actually being shown.
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


## Direct children of the skeleton only — every skinned garment mesh sits
## there, and searching the whole subtree would reach attachments and props
## that are not clothing.
func _find_mesh(mesh_name: StringName) -> MeshInstance3D:
	if _skeleton == null or mesh_name == &"":
		return null
	var found := _skeleton.get_node_or_null(NodePath(String(mesh_name)))
	if found == null:
		push_warning("[EquipmentVisuals] no mesh named '%s' under the skeleton" % mesh_name)
		return null
	return found as MeshInstance3D
