# =============================================================================
# item_pose.gd — how an item sits in the hands.
#
# One ItemPose = one .tres under data/item_poses/.
# The editor plugin authors these resources by placing the item in a live
# player scene (idle pose, viewport gizmos, Save button).
# Runtime only reads them. Nothing in the game path ever writes an ItemPose.
#
# Why this exists
# ---------------
# EquipmentVisualsComponent used to carry a single global held_offset /
# held_rotation_deg. That worked for the first drawable. The moment a second
# item needs a different grip, or a two-hand tool appears, those globals
# become a special-case list that belongs to the character instead of the
# item — the opposite of how every other piece of equipment data is already
# modelled (GarmentData lives on the item, EquipmentLayout describes the
# body, ItemCatalog is the lookup).
#
# ItemPose moves the numbers onto the item itself. The character only knows
# "which bone" and "apply the transform the pose gives me".
#
# Single source of truth
# ----------------------
# The same Resource the author saved in the editor is the one
# EquipmentVisualsComponent applies at runtime. There is no second
# "runtime offset" table and no conversion step. If the visual is wrong
# in game, the Resource is wrong — fix it once in the authoring scene.
#
# Single-hand vs two-hand
# -----------------------
# left_hand_bone empty  →  single-hand (only right_hand is used)
# left_hand_bone set    →  two-hand (both attachments are driven)
#
# The authoring scene shows both preview meshes when two-hand is active.
# The user moves them independently; Save writes both transforms.
# =============================================================================

extends Resource
class_name ItemPose


@export_group("Bones")
## Primary (usually right) hand bone. Must exist on OriginalSkeleton.
## Default matches the RightHandAttachment already present in player.tscn.
@export var right_hand_bone: StringName = &"RightHand"

## Secondary (usually left) hand bone.
## Empty = single-hand pose. When set, EquipmentVisualsComponent also
## drives a LeftHandAttachment and applies the secondary transform.
@export var left_hand_bone: StringName = &""


@export_group("Primary (right hand)")
## Local position of the item relative to the right-hand BoneAttachment3D.
@export var position: Vector3 = Vector3.ZERO
## Local rotation in degrees relative to the right-hand attachment.
@export var rotation_deg: Vector3 = Vector3.ZERO
## Scale. Almost always (1,1,1); present for unit-scale corrections.
@export var scale: Vector3 = Vector3.ONE


@export_group("Secondary (left hand) — only when left_hand_bone is set")
## Local position of the secondary grip relative to the left-hand attachment.
@export var secondary_position: Vector3 = Vector3.ZERO
## Local rotation in degrees relative to the left-hand attachment.
@export var secondary_rotation_deg: Vector3 = Vector3.ZERO
## Secondary scale (usually left at 1,1,1).
@export var secondary_scale: Vector3 = Vector3.ONE


@export_group("Grip markers on the item (optional, future-proof)")
## NodePath relative to the item root pointing at a GripPrimary Marker3D.
## Empty = the item root itself is the grip point.
## When set, the runtime can parent so this marker lands exactly on the bone;
## the position/rotation fields then become the fine offset from that marker.
@export var primary_grip_path: NodePath = NodePath("")
## Same for the secondary grip. Only meaningful for two-hand poses.
@export var secondary_grip_path: NodePath = NodePath("")


## True when both hands are used.
func is_two_hand() -> bool:
	return left_hand_bone != &""


## Transform applied to the primary (right-hand) mesh / item root.
func primary_transform() -> Transform3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rotation_deg.x),
		deg_to_rad(rotation_deg.y),
		deg_to_rad(rotation_deg.z)
	)).scaled(scale)
	return Transform3D(basis, position)


## Transform applied to the secondary (left-hand) mesh when is_two_hand().
func secondary_transform() -> Transform3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(secondary_rotation_deg.x),
		deg_to_rad(secondary_rotation_deg.y),
		deg_to_rad(secondary_rotation_deg.z)
	)).scaled(secondary_scale)
	return Transform3D(basis, secondary_position)
