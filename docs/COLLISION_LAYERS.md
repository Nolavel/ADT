# Collision layers

Single source of truth for 3D physics layers and the query masks built from
them. `core/physics/collision_layers.gd` (`CollisionLayers`) is the code
counterpart — its constants must match this file exactly; a layer is never
introduced in one without the other.

Verified against `project.godot` and the scenes/scripts below on
**2026-08-18**. Six physical query sites exist in code today (perception
line-of-sight, camera occlusion, NPC obstacle avoidance, the dropped-item
ground-detection raycast, the interactable `RigidBody3D`'s own physical
mask, and the player's interactable focus `ShapeCast3D`), plus one more
found while writing this table (the 3D-UI cursor hover raycast) — see
`docs/planned_scope.md`'s "Not started, not stubbed" entry on
`RaycastService` for why that count does not yet justify a facade over them.

## Layers

| # | Value | Name | Who's on it | Who queries it |
|---|---|---|---|---|
| 1 | 1 | `Characters` | `player.gd`'s `CharacterBody3D` and `npc/npc_base.gd`'s `NPCBase` — both leave `collision_layer` unset, so they sit here by Godot's own default. **Also** present, seemingly by accident, on nearly every static "floor" body in the project — `map_source.tscn`'s `CityZone`/`WorldZone`, every ground-tile silhouette/content scene, every block content layer (`layer_doggerland`/`layer_manifold`/`layer_glare`), `LodgingRoom`'s `Floor` and all four walls — all authored as `collision_layer = 3` (this layer **and** `floor`). Nothing in the code reads that combination as meaningful; it reads like Godot's new-`CollisionObject3D` default (layer 1) never got cleared when the `floor` bit was added by hand. See the report note below — this makes the name a half-truth for floor geometry, but renaming what player/NPC bodies sit on wasn't this task's call to make unilaterally. | `core/map_source/map_cursor.gd`'s info raycast (`RAY_COLLISION_MASK = 1`, editor tool — its own header calls this "static geometry", which is exactly the floor bodies above, not player/NPC), `PoliceDrone.tscn` body (`collision_mask = 7`), its `HeightRayCast` (`collision_mask = 3`). |
| 2 | 2 | `floor` | Every "floor"-group `StaticBody3D`: `map_source.tscn`'s `CityZone`/`WorldZone`, all ground-tile silhouette/content scenes, all block content layers, `LodgingRoom.Floor`. | `PerceptionComponent.LINE_OF_SIGHT_MASK`, `OnFootCameraComponent`'s occlusion raycast, `ClickToMoveSystem._cast_ground_ray()` (`GROUND_LAYER`), `InteractiveVisualIndicator`'s ground-detection raycasts (intended target — see Bug 5.2), `InteractableObject.collision_mask`, `PoliceDrone` body and `HeightRayCast`, `HoverTest` body. |
| 3 | 4 | `wall` | Every block/tower silhouette under `world/silhouettes/blocks/**` — the Ring 0 permanent-collision silhouettes `StreamingSystems` spawns once for every block (see `CLAUDE.md`'s `StreamingSystems` paragraph). | `LINE_OF_SIGHT_MASK`, camera occlusion, `IdleNPCController`'s obstacle-avoidance ray (once actually wired into the tree — Bug 5.1), `PoliceDrone` body, `HoverTest` body. |
| 4 | 8 | `PhysicsObjects` | `InteractableObject` (`RigidBody3D`) — `collision_layer = 8`, set in `_ready()` and restored to the same value in `InteractComponent._drop_item()` after being zeroed out while carried. | `InteractableObject.collision_mask` (10 — itself plus `floor`; this is the `RigidBody3D`'s own physical collision mask, not a raycast query). |
| 9 | 256 | `Drones` | `PoliceDrone.tscn` root `CharacterBody3D` (`collision_layer = 256`) — the only occupant found anywhere in the project. | Nothing found. `PatrolDroneController`'s player-visibility checks go through the shared `PerceptionComponent` (`LINE_OF_SIGHT_MASK`), which never references this layer. |
| 10 | 512 | `Interactables` | `InteractableObject.interaction_area` (`Area3D`, `collision_layer = 512`, set in `_ready()`). | `InteractComponent.PlayerFocusCast` (`ShapeCast3D`, `collision_mask = 512`). |
| 11 | 1024 | `TransportTriggers` | `HoverEntryTrigger` (`Area3D`, `hover_test.tscn`, `collision_layer = 1024`). | Nothing by mask — `hover_entry_trigger.gd` detects the player through `Area3D.body_entered`, not a raycast/shapecast against this layer. |
| 20 | 524288 | `3D_GUI` | **Nothing currently.** No scene in the project assigns this layer to any node — grepped for both the raw value and anything resembling a 3D UI button body. | `MouseCursorUI._update_3d_ui_state()` (`dynamic_cursor_ui.gd`, `collision_mask = 1 << 19`) — a raycast against a layer nothing occupies, so it can never hit today. Worth confirming by running the game rather than assuming; see the report's "check by running" note. |

Layers 5–8, 12–19 are unused — no script or scene references them.

## Query profiles (`CollisionLayers`)

A profile is named for **what the query is asking**, not just which bits
happen to be set — the same bit pattern can mean different things in
different places, and a name that only restates the bits (`FLOOR_AND_WALL`)
would tell a reader nothing they couldn't get from the mask itself.

- **`SIGHT = WALL`** — What blocks one character's view of another. Walls
  only: a floor between two actors means they are on different decks, and
  the geometry of the city already makes that unreachable — including the
  floor here made the perception ray fail on slopes and stairs for no gain.
  Used by `PerceptionComponent.observe_player()`'s line-of-sight raycast.
  **This drops `floor` from what `LINE_OF_SIGHT_MASK` used to include** —
  see "Behaviour change to verify by running" below.

- **`CAMERA_OCCLUSION = FLOOR | WALL`** — What the camera must not pass
  through. Floor as well as walls, unlike `SIGHT`: the camera is not an eye
  at head height, it swings low behind the character and would sink through
  the deck without this. Used by `OnFootCameraComponent`'s TPS occlusion
  raycast.

- **`OBSTACLE = WALL`** — What a straight-ahead wander/flee/respond bump
  check treats as blocking. Wall only, not floor — floor is what an NPC
  walks on, not an obstacle to walking. Used by `IdleNPCController`'s
  forward obstacle ray (see Bug 5.1 for why this wasn't actually taking
  effect until now).

- **`GROUND = FLOOR`** — What a dropped/thrown interactable's six-direction
  "which way is down" raycast should hit. The object needs to find the
  floor it's meant to land on after a throw may have tumbled it into any
  orientation — a wall in the way is not the floor. Used by
  `InteractiveVisualIndicator`'s ground-detection raycasts (see Bug 5.2 —
  this replaces a mask that was actually `wall`, contradicting its own
  comment).

- **`INTERACTION = FLOOR | PHYSICS_OBJECTS`** — What an `InteractableObject`
  physically rests against and bumps into: the floor it needs to land on,
  and other physics objects it can collide with. This is a `RigidBody3D`'s
  own `collision_mask`, not a raycast query — grouped here anyway since it's
  one more site that was a bare literal. **Wall is deliberately absent**,
  which means a thrown item does not stop at a wall — that gap was already
  there before this pass (`Interactables.gd:49`'s own literal `10` predates
  this file) and is left as found; naming it does not mean endorsing it. See
  the report's open questions.

- **`CURSOR_UI = GUI_3D`** — What the screen-space cursor's 3D-UI hover
  raycast should hit: the dedicated 3D-UI layer, nothing else. Used by
  `MouseCursorUI._update_3d_ui_state()`. Currently untested in practice — see
  the layer table above, layer 20 has no occupant in any scene today.

## Rule

**Masks and layers are set through `CollisionLayers`, never as a bare
integer literal**, in both code and scenes. A `.tscn` still stores the raw
number (Godot has no way to reference a script constant from scene data),
so a scene-level assignment is documented here, in the table above, instead.
A new layer is added to `project.godot`'s `[layer_names]`, named in
`CollisionLayers`, and given a row in this file's table in the same commit —
never one without the other two.

## Open questions / not verified by running

- **`SIGHT` dropping `floor` is a behaviour change**, not just a rename.
  `LINE_OF_SIGHT_MASK` previously included `floor` — code already flagged
  that as an "open, undiagnosed defect" (`idle_npc_controller.gd`, around
  the `_is_incident_in_vision_cone()` comment). Removing it should make NPC
  sight work correctly on slopes/stairs where it used to fail; confirm by
  running the game and checking an NPC's sight line across a sloped tile or
  a staircase, separately from the rest of this change.
- **`CURSOR_UI`/layer 20 has no occupant anywhere in the project.** The
  raycast that reads it (`dynamic_cursor_ui.gd`) is consequently inert today
  — this was true before this pass and is not something it changes, but is
  worth confirming by running the game with the 3D cursor active rather than
  assuming from the grep above.
- **`INTERACTION`'s missing `wall` bit** (`Interactables.gd:49`, originally
  a bare `10`) was left as found — its intent (why an interactable doesn't
  stop against a wall) isn't recoverable from the code, and this pass didn't
  invent a reason. Flagged for the project owner, not fixed.
