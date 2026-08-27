# Item Pose — authoring scene workflow

**Status:** full skeleton, ready to port (2026-08-27)  
**Files under** `artifacts/Prok/`

---

## What the user does

```
1. Project → Tools → Item Pose Authoring
   (or open addons/item_pose_editor/item_pose_authoring.tscn)

2. Instance your real player.tscn into the scene as child "Player"
   (or set player_path / skeleton_path exports)

3. Select Animation → idle → Play Animation
   Player stands in idle.

4. Select Item (only items with held_mesh + can_use_in_hands)

5. Preview mesh appears under RightHandAttachment.
   Move / rotate it with normal viewport gizmos.

6. (Optional) Check "Two-hand (left hand)"
   Second preview appears under LeftHandAttachment.
   Move it independently.

7. Press Save Pose
   → data/item_poses/<id>_pose.tres
   → ItemResource.pose is set to that resource

8. Done. Runtime uses exactly what you saw.
```

---

## Data flow

```
Authoring scene (editor only)
        │  user moves MeshInstance3D with gizmos
        ▼
ItemPose Resource          ← written by Save
        │
        ▼
ItemResource.pose          ← linked on save
        │
        ▼
EquipmentVisualsComponent  ← reads on draw
        │
        ├── RightHandAttachment → primary mesh
        └── LeftHandAttachment  → secondary mesh (if two-hand)
```

---

## Files

| Path | Role |
|------|------|
| `core/items/item_pose.gd` | Resource. Primary + secondary transforms, bones. |
| `core/items/item_resource.gd` | `@export var pose: ItemPose` |
| `player/.../equipment_visuals_component.gd` | Applies pose (single or two-hand). Fallback to old offsets if pose null. |
| `addons/item_pose_editor/plugin.gd` | EditorPlugin. Menu item → open authoring scene. |
| `addons/item_pose_editor/plugin.cfg` | Plugin descriptor. |
| `addons/item_pose_editor/item_pose_authoring.gd` | Authoring logic: spawn preview, play anim, Save. |
| `addons/item_pose_editor/item_pose_authoring.tscn` | Minimal scene (Camera + Light + UI root). Drop player in. |
| `data/item_poses/*.tres` | Saved poses. |

---

## Single-hand vs two-hand

| | Single-hand | Two-hand |
|---|-------------|----------|
| UI | Two-hand checkbox off | checkbox on |
| Preview | only right | right + left |
| ItemPose.left_hand_bone | `&""` | `&"LeftHand"` |
| Runtime | one MeshInstance3D | two MeshInstance3Ds |

Both transforms are local to their BoneAttachment3D.  
What you see in the authoring viewport is exactly what the game applies.

---

## Why this design

- **Authoring is visual.** No guessing Vector3. Idle (or any anim) is live.
- **One source of truth.** The Resource written by Save is the one runtime reads. No second table.
- **Left hand is first-class.** Same Resource, same Save button, same runtime path.
- **Plugin is editor-only.** Zero runtime cost. Zero coupling to EquipmentComponent / stance / save.
- **Backward compatible.** Items without a pose still use the old global offsets until authored.

---

## Porting to main

1. Copy `core/items/item_pose.gd`.
2. Ensure `ItemResource` has the `pose` field.
3. Replace `equipment_visuals_component.gd` (or merge the pose + left-hand paths).
4. Copy the whole `addons/item_pose_editor/` folder.
5. Enable the plugin in Project Settings → Plugins.
6. Open the authoring scene, instance your real `player.tscn` as child named `Player`.
7. Adjust `skeleton_path` / attachment paths if your hierarchy differs.
8. Author the first real pose for the current drawable (carbine / pistol).
9. Assign it (Save does this automatically).
10. Run the game — the item should sit exactly where you placed it.

When every drawable has a pose, the fallback `@export held_offset / held_rotation_deg` and the corresponding branch can be deleted.
