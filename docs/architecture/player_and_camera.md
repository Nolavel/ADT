# Player, camera and stance

The player node's two movement modes, the per-mode camera components, transport,
and the stance/aiming state the rest of the game reads.

Split out of `CLAUDE.md` on 2026-08-25 — it had grown to 94 KB with single
paragraphs over 4000 characters, which is a document nobody edits: agents append
to the end instead of correcting the middle, and that is where the repeated drift
came from. The text here is the same text, moved, not rewritten.

`CLAUDE.md` remains authoritative for the rules; this file is authoritative for
the contracts it describes.

---

### Player (`player/player.gd` + `player/player_components/`)

`player.gd` (on `CharacterBody3D`) owns physics, animation state machine, and rotation directly (not delegated to components) for both movement modes it supports:
- **Direct WASD movement** — `TPSMovementSystem` (a `WORLD_SYSTEM_SCRIPTS` entry) feeds `set_direct_move_input()` every physics frame; `player.gd` does the actual velocity/rotation/animation work in `_apply_direct_movement()`. This is the default and, since the isometric removal, the only player-driven path.
- **Scripted navigation** — driven by `NavigationComponent`, path following in `_handle_navigation()`. It runs only while a path set through `move_to_position()` is in flight; today the one caller is `InteractComponent`'s auto-approach to something `F` was pressed on.
- **One question decides which**, in `_physics_process()`: is a scripted path active? The other half of that decision used to be `PlayerState.view_mode`, and it went with click-to-move and the isometric camera on 2026-09-02. Two consequences remain and are load-bearing: `_update_direct_move_target_speed()` is **skipped** while a scripted path runs (it zeroes `target_speed` whenever there is no WASD input, which would drain the approach's speed before it moved a metre), and a non-zero `_direct_move_direction` **cancels** the path on the spot — the player's own input always wins, and the `movement_stopped` that follows is how `InteractComponent` learns the approach is over.

**Discontinuous placement goes through `teleport_to()`, never through a bare `global_position` write.** Physics interpolation is on project-wide (`project.godot`, `common/physics_interpolation`), so a body that is placed rather than moved has a stale previous transform to be blended from — the origin, on the first frame after `add_child()`. `teleport_to()` sets the position, zeroes `velocity` and calls `reset_physics_interpolation()`; its two callers are the spawn in `world.gd` and stepping out of a hover in `hover_entry_trigger.gd`. Motion that is genuinely continuous — the boarding tween, navigation, WASD — must NOT come through it, because interpolation is exactly what that motion wants.

`player_components/` contains three implemented components: `nav_component`, `stamina_component`, `interact_component`. Empty placeholder directories for unstarted components (health, hunger, sleep, wallet, progression, crafting, save) were removed on 2026-07-29; that scope is recorded in `docs/planned_scope.md`. `equipment_component` and `equipment_visuals_component` were implemented later as H5 (2026-08-23).

### Camera (`camera/`)

`camera_follow.gd` is the host; per-mode behaviour lives in `camera_component/`: `on_foot_camera_component`, `hover_camera_component`, `tube_transit_camera_component`, plus `camera_shake_component` layered additively on top of whichever is active. `PlayerState.mode` picks the component; the host never writes the transform itself outside the MENU pause animation.

**There is ONE on-foot camera.** The isometric orbit was removed on 2026-09-02 — `IsometricCameraState`, its debug overlay, the zoom slider that chained the two views into one continuum, `ClickToMoveSystem`, `ZoomRulerSystem` and the long-dead Q/E orbit and P follow-rotation layer all went in the same commit. `docs/postmortems/tps_camera_single_mode_audit.md` is the survey that made it safe; read it before reviving any of it from git.

**`PlayerState.ViewMode` is now a FRAMING choice, not a camera.** `TPS` centres the character behind the shoulder; `TPS_WIDE` shifts the lens (`Camera3D.h_offset`/`v_offset`) so they sit low and to one side, and pulls in to `wide_distance` (1.30 m against TPS's 2.2). Same pitch, same yaw, same occlusion, same follow rates. **The distance started out fixed** — the constraint was *"только смещение, дистанция та же"* — and became a knob when the reference frame the view is meant to match was measured against a render: the character sits 6.8% in from the left edge at ~29% of the frame's width there, against 20% and ~14% from a lens shift alone. A lens shift moves the subject across the frame; it cannot make them bigger, so the two requirements could not both hold. Setting `wide_distance` back to `TPS_DISTANCE` restores the original behaviour exactly — the term it feeds is written as a difference for that reason. A second finding from the same measurement, and the counter-intuitive one: **moving in means a SMALLER `h_offset`**, since the same shift throws a bigger subject further off-frame (at 1.2 m with `h` 0.90 only a shoulder was left in shot). The blend between them is one eased scalar (`_framing_blend`), which is what let the old view-transition machinery — a zoom animation, a pitch retarget and a `view_mode_animating` gate the whole position pass had to know about — be deleted rather than ported. **Only `OnFootCameraComponent` reads `view_mode`**; every other consumer (movement, mouse capture, head-look, the cursor, the HUD decals) lost its branch in the same commit rather than keeping a distinction that no longer exists.

**Occlusion is a sphere cast, and that is inherited on purpose.** TPS used `intersect_ray()` while the isometric camera used a sphere `cast_motion()`; `CHANGELOG.md` records that the sphere replaced a ray precisely *because* a ray asks whether the camera's mathematical centre has crossed the wall — answered late and discontinuously, with the frustum's near face already inside — while a sphere reports the surface a whole radius early and its distance then falls continuously. Carrying the ray into the single remaining camera would have been an unrecorded rollback of a decision already made, so `_apply_wall_clamp()` → `_update_collision_distance()` → `_probe_camera_distance()` is the isometric method, moved over. **Retract is immediate, restore is eased** (`CAMERA_COLLISION_RESTORE_RATE` 2.5): being inside a wall is a correctness failure, being further out than necessary costs nothing. The clamp runs **after** the follow filter, on `camera_current_pos`, so the retraction is actually immediate and the filter cannot hold a position inside the wall to snap back out of.

**The two occlusion LENGTHS could not be inherited and were re-derived.** The isometric numbers were sized for a 10–17.5 m orbit: `ISO_COLLISION_MIN_DISTANCE` 3.0 and a 0.45 m probe. On a 2.2 m boom the minimum alone would have disabled occlusion outright, since `_probe_camera_distance()` returns early whenever the desired distance is already at or under it. `CAMERA_COLLISION_MIN_DISTANCE` is 0.70 and `CAMERA_COLLISION_RADIUS` 0.30, stated against this camera's 1.5–2.6 m working range. These two are the part of the migration most in need of eyes on a real corridor.

**Q/E are a lean, and the camera leans further than the body.** `_handle_lean()` accumulates a held axis at `LEAN_RATE` and springs back at the faster `LEAN_RETURN_RATE` (effort to hold, none to abandon — the asymmetry is inherited from the isometric glance these keys used to carry). The camera slides along the same `right` vector the shoulder offset uses, added to it, so leaning while switched to the left shoulder moves further left instead of fighting it. The pose comes from `new4/aim-lean-l` / `new4/aim-lean-r`, wired as two chained `AnimationNodeBlend2` in `PlayerAnimationComponent` — chained Blend2 rather than a `BlendSpace1D` because a blend space needs a clip at its neutral centre and the centre here is *whatever locomotion is doing*, which is an input, not a clip. Both clips were measured before being wired: every rotation track is constant across their 2.083 s, so they are held poses and the blend amount *is* the lean. **The body only leans in `COMBAT`**: they are aiming leans, and rendered with empty hands in `PEACE` the character reads as miming a rifle, so out of combat the lean is the camera alone.

**Engine physics interpolation is OFF on the camera node** (`camera_follow.tscn`, `physics_interpolation_mode = 2`) and must stay off: this camera already smooths itself exponentially in `_physics_process` and then writes its own `global_transform` in `_process`, with the additive shake applied on top there. Engine interpolation would be a second smoother blending from a transform this file has already blended. Measured with the render probe 2026-09-03: turning it off is the whole of the visible change — the first frames after boot differ by 15% of the picture (the character is framed instead of sliding half out of shot at the right edge), converging to ~0.2% by frame 20.

**Steady-state follow rates**: position at `TPS_FOLLOW_SPEED` (16), rotation much faster at `TPS_LOOK_SMOOTHING` (30). If rotation lagged as much as position, the target would visibly leave frame on a quick mouse turn — position lag reads as a spring, rotation lag reads as input lag.

**Stamina is drawn in the HUD, the cursor only aims.** `StaminaGauge` (`ui/hud/stamina_gauge/`) renders the stamina ring as the first cell of `PlayerHUD`'s `StatusStack/HealthRow`, left of the health bar — four quarter arcs whose length is the remaining ratio and whose colour walks full → yellow → orange → red, the two chasing recovery sweeps with their pulse and inner glow, the jump-charge arc, and the walk/sprint/no-stamina icon **inside** the ring. It owns **no arithmetic**: `StaminaComponent` keeps all of it and this widget subscribes, bound by `PlayerHUD.on_world_ready()` through `bind(player)` rather than by hunting for the player through a group. Every radius and thickness is still expressed in the original cursor's pixels around an 8 px centre and multiplied by `gauge_scale`, so the proportions cannot drift from what they were. **It has been in three places, and the middle one is why the rule matters.** It started on `MouseCursorUI`, moved to the ground as `StaminaIndicator3D` (2026-08-28) to stop the cursor saying two things at once, and moved into the HUD on 2026-09-02 because the ground version needed `depth_test_disabled` to stay visible at all and therefore drew straight **through the character it was under** — a trade dressed as a fix. On a flat canvas there is no depth to test and nothing to draw over, so that failure is structurally absent rather than tuned away. The move-target group `TargetIndicator.GROUP_MOVE_TARGET` lost its only reader with that deletion and is kept only until click-to-move goes with the isometric removal. `MouseCursorUI` was where all of this lived until 2026-08-28 and now holds no reference to `StaminaComponent` at all: it says one thing, which is what the player is pointing at — dim grey, brighter over an NPC or item, and `[ ✛ ]` brackets while a firearm is drawn, opening and settling on a spring driven by the **continuous** speed rather than by `is_running`. **In TPS it is pinned to screen centre**, since the mouse is captured there and the camera is what aims. **What is under it is decided by TYPE, not by mask**: the island terrain carries `collision_layer = 3` and so sits on `CHARACTERS` alongside real characters, which no mask can separate — the cursor therefore accepts only `NPCBase`, `InteractableObject` or an interactable's `Area`, which also gives honest occlusion for free, since the ray returns the nearest hit. That terrain layer is still wrong and is not fixed by this.

`TpsShoulderCameraState` (left/right shoulder) and `TpsCombatCameraState` (Explore ⇄ Locked, lock-on) are unchanged by the migration; the audit confirmed neither ever touched the isometric state. `CONFLICT-1` — `TpsCombatCameraState`'s blended yaw being computed during `TRANSITION` but applied only while `LOCKED` — was **deliberately left as it is** and is tracked separately, so that this migration neither silently fixes nor silently loses it.

### Transport (`core/controllers/transport/`)

+`base/hover_base.gd` is the shared hover behaviour (CharacterBody3D pseudo-physics, inertia, yaw smoothing, semi-automatic altitude hold). Control is fed in every frame through `set_move_intent(move, vertical)` — `base/input_hover_controller.gd` (`InputHoverController`) is the player-side implementation and reads exclusively through `InputSystems`. An AI-side controller will use the same interface. Boarding is handled by `hover_entry_trigger.gd` (FSM: `IDLE → BOARDING → SEATED → EXITING`), not by `InteractComponent`. **Both boarding and exiting are hold-to-confirm since 2026-08-28** (`interact_hold_time`, 0.7 s): a press only starts the hold, and the transition runs once at the threshold — `_hold_committed` is what stops a still-held key from firing it again. Getting into a vehicle is the one mis-press in this build that is expensive to undo, and this trigger is the project's only interact claimant, so the hold lives on the claim contract rather than being a general property of interaction.

- Metro, lifts, tube transit and additional hover types are **not implemented** — see `docs/planned_scope.md`. Their placeholder scripts were removed on 2026-07-29.


- **Character physical size** is per-character data (`player/player.gd`'s `body_height` export; `npc/npc_base.gd`'s own) with shared eye/shoulder/chest ratios in `core/characters/body_metrics.gd` (`BodyMetrics`), not duplicated per character. The `Player` `CharacterBody3D` origin sits at the feet. Any value that depends on the character's height (camera framing, raycast origins, attachment points) must go through the `get_eye_height()`/`get_shoulder_height()`/`get_chest_height()` getters — never hardcode a height or assume where origin sits.

- **Player stance** (`PlayerState.stance`, `Stance.PEACE`/`Stance.COMBAT`) is a declared intent, and since H5 equipment is one of the things that can declare it — drawing a weapon IS a declaration, and the point is that it cannot be made quietly. Raised fists are already a statement on their own, which is why the coupling is deliberately asymmetric: entering `COMBAT` never auto-draws, but drawing something whose `readability` is `THREATENING` sets `COMBAT`, and returning to `PEACE` by any route holsters. `player.gd` owns that wiring (`_on_drawn_changed()`/`_on_stance_changed_for_equipment()`) because `EquipmentComponent` knows nothing about stances and `InputSystems` knows nothing about equipment; it is the second-ever caller of `set_stance()`. No loop and no guard flag is needed — `set_stance()` returns early on an unchanged value and `holster()` returns early with empty hands. Mutated only through `PlayerState.set_stance()`, never assigned directly, same rule as `mode`/`view_mode`. Read by `player.gd` (movement speed, TPS body rotation, and — only in `COMBAT`, in both view modes — the punch action on `mouse_left_button`, see `_on_primary_click_pressed()`; ISOMETRIC additionally faces the body to the click point first, via `_face_punch_target()`, since it has no TPS-style camera-driven facing to fall back on. A punch also resolves an **intent target** once at button-accept time — `_acquire_punch_intent()`, a wider-cone/longer-reach reuse of the same `_find_punch_target(reach, angle_deg)` search the hit check runs, stored as an instance id, never a `Node` reference — and `_face_punch_intent()` turns the body toward it for the length of the wind-up, so an NPC that walks out of the cone during `punch_hit_delay` is still swung at. The hit check itself is unchanged, so this improves the odds of a fair punch landing and never guarantees one; the intent clears when the punch ends. A punch that resolves with no target emits `punch_missed(position)` — see the `IdleNPCController` bullet below for its one subscriber, and note it deliberately never reaches `IncidentRegistry`), `core/movement/click_to_move_system.gd` (self-gates off for the whole of `Stance.COMBAT`, on top of its existing `ON_FOOT` + `ISOMETRIC` gate, so click-to-move and the punch never both react to the same `mouse_left_button`/`mouse_right_button` click; stops an in-progress path rather than letting it finish on entering `COMBAT`, since `player.gd`'s navigation branch is keyed on `view_mode` alone and would otherwise keep advancing it), `camera/tps_combat_camera_state.gd` (lock-on gating), `player_animation_component.gd` (a stance-branched AnimationTree — two direction-blended `AnimationNodeBlendSpace2D` branches with identical geometry: a centre/idle point plus seven directional points, forward split into a walk point (`walk_blend_radius`) and a run point (outer edge) since the blend vector's length carries speed; every point is the same clip on both branches except idle, MeleeLib's `LightIdle` for PEACE vs ShooterLib's `sneak-idle` for COMBAT — plus a punch, layered over whichever branch is mixed in via `AnimationNodeOneShot`, ShooterLib's `punch1`), and — as of the drone/NPC work below — the AI decision layer: `idle_npc_controller.gd`'s glance/turn gate still reads `PlayerObservation.stance` (itself sourced from `PlayerState.stance` by `PerceptionComponent`, only when the player is actually seen), but `patrol_drone_controller.gd`'s ALERT no longer does — see the `IncidentRegistry` paragraph below for what replaced it. `ui/hud/stance_indicator/stance_indicator.gd` is the newest consumer — a HUD badge next to the health bar showing PEACE/COMBAT by both colour and text, self-contained like `KeyHintsPanel` (reads `PlayerState.stance`/`stance_changed` directly in `_ready()` rather than through a `WorldContext`). The evidence system still doesn't read stance. Not reset by `open_menu()`/`close_menu()`.
  - **`PlayerState.is_aiming`** is a COMBAT-only modifier, not a third stance (`set_aiming()` silently clamps to `false` outside `Stance.COMBAT`/`Mode.ON_FOOT` — a held aim button crossing a stance change mid-press is ordinary input, not an error). Read by `player.gd` (`aim_speed_multiplier`, stacked on top of the COMBAT speed multiplier), `on_foot_camera_component.gd` (dollies TPS camera distance to `TPS_AIM_DISTANCE`, widens shoulder offset by `aim_shoulder_offset_multiplier` — wins even over an active lock-on), and `ui/hud/aim_reticle/` (a debug-grade screen-centre cross, visible only while aiming — confirms ADS reads on screen, not the final aiming UI).
- **`KeyHintsPanel`** (`ui/hud/player_hud/key_hints_panel.gd`, instanced inside `player_hud.tscn`, H2 — `docs/scope_horizon.md`) shows the actions valid for the player's CURRENT `PlayerState` snapshot (`mode`/`view_mode`/`stance`/`is_aiming`), bottom-center, whenever `InputSystems.key_hints_enabled` is true, laid out as THREE COLUMNS — Movement / Action / System — not one horizontal ribbon: a flat row list only ever encoded meaning through `sort_order`, which the eye can't read at a glance, forcing a full scan every time. `KeyHintEntry.category` (`Category` enum: `MOVEMENT`, `ACTION`, `SYSTEM`) picks the column; column ORDER on screen is the enum's own declaration order (`KeyHintsPanel._build_columns()` iterates `Category.values()`, no case statement choosing order in the panel itself), and within a column rows still sort by `sort_order`. Three, not four: a dedicated camera/view column would only ever hold one or two rows, so those entries live in `ACTION`. A column with zero active rows hides itself (header included), never leaving an empty slot in the `HBoxContainer` of columns. Data-driven from `KeyHintEntry`/`KeyHintsCatalog` (`ui/hud/player_hud/`, populated in `res://data/key_hints.tres` — see the entry below for what's in it) rather than a hardcoded per-state switch — an entry's `modes`/`view_modes`/`stances` arrays are empty for "any", so an action valid everywhere doesn't have to enumerate every enum member. An entry can describe a GROUP of actions that share one meaning (`KeyHintEntry.action_names`, e.g. WASD → one "Move" row) instead of one action each — `get_action_names()` returns `action_names` if set, else the single `action_name`, so an ungrouped entry is unaffected; `get_row_key()` (the joined action names) is what the diffed rebuild tracks a row by, not `action_name` directly, precisely so a group gets one stable row identity. Key labels are resolved live from `InputMap`, never authored by hand, so a rebind cannot make the panel lie: keyboard wins when an action has more than one bound event (none do today), otherwise the first event of whatever else it's bound to; a keyboard event's `as_text()` has any trailing parenthetical stripped, a mouse button becomes LMB/RMB/MMB/MB4/MB5/`MB<n>`, and a wheel tick becomes `Wheel Up`/`Wheel Dn`/`Wheel Left`/`Wheel Right` — spelled out in ASCII rather than drawn with `↑`/`↓`/`←`/`→`, since the key label's font is a bare `SystemFont` request (`_build_mono_font()`) with no guarantee the resolved font actually carries the Arrows Unicode block; unverified hypothesis, not something checked by running the game. A group's per-action labels are joined by `group_key_separator` (one exported value, not repeated per call site). Rebuilds only on `PlayerState`'s four signals, diffed PER COLUMN against the rows already on screen in that column (keyed by `get_row_key()`) rather than cleared and rebuilt wholesale, so an unrelated stance flip doesn't flash rows that are still valid — same diffing shape as before columns existed, just scoped per column's own row list instead of one shared one (`_rebuild_column()`). Self-contained relative to the rest of `player_hud.gd`: reads `PlayerState`/`InputSystems` directly in `_ready()` instead of waiting on `on_world_ready(context)`, since both are autoloads and nothing here needs the player/camera a `WorldContext` would hand over.
  - **`res://data/key_hints.tres`** was trimmed from 39 rows to 22 `KeyHintEntry` resources, and to 20 on 2026-09-02 when the isometric-only rows (click-to-move, its stop/cancel, the duplicate ISO punch), the zoom pair and the ISO camera-step went with the camera itself; the `view_modes` filter on the remaining rows was dropped in the same pass, since both surviving view modes are the same camera and a filter that always matches is noise (movement/camera-pair actions collapsed into grouped rows; `inventory`/`map`/`status` removed outright — those systems don't exist, and a hint promising them is a lie; `toggle_stream_debug`/`toggle_perception_debug` removed as observer-only debug overlays, out of scope for "can a reviewer operate the build"; `toggle_follow`/`toggle_tabs`/`switch_shoulder` removed as low-value secondary camera preferences) so a state shows roughly ten rows instead of forty — the original per-action population proved unreadable on screen. `debug_save`/`debug_load` were briefly one grouped `K / L` row (`"Debug save / load"`) and were split back into two: the paired key label and the paired description didn't unambiguously say which key was which action, and the one row saved wasn't worth that ambiguity. Every entry carries a `category` (`MOVEMENT`/`ACTION`/`SYSTEM`) for its column; `lock_on` was the one genuinely debatable case — filed under `ACTION` (closer to targeting/combat than to `MOVEMENT`) rather than invented a fourth column for it. Actual per-state row counts (three-column layout): ISOMETRIC+PEACE 11, ISOMETRIC+COMBAT 10, TPS+PEACE 11, TPS+COMBAT 12, HOVER 8.

---

## The aim chain — one point, and where the pitch comes from

**Added 2026-09-04.** The camera decides intent; the muzzle fires. Keeping those
two separate is what stops a round landing on someone the barrel is visibly not
pointing at.

### The defect this replaced, stated so it is not reintroduced

Aiming was a horizontal cone off `get_facing_direction()`, which returns
`Vector3(sin(rotation.y), 0.0, cos(rotation.y))` — **Y is structurally zero** —
against `_find_punch_target()`, which additionally flattens the target with
`to_target.y = 0.0`. **There was no pitch anywhere.** The camera tilts and the
character cannot, which is why the barrel never met the screen centre however the
muzzle marker was placed.

The horizontal half was never as broken as it looked: `_face_camera()` runs at
`combat_face_camera_smoothing` (20.0) in COMBAT, so the body already tracked
camera yaw within a smoothing lag. Only the vertical half was missing outright.

### The chain

- **`get_aim_point()`** wraps `TPSAimComponent.get_aim_target(shot_range, [get_rid()])`
  — the camera's own ray through the screen centre. `get_rid()` is not optional:
  the ray starts at the CAMERA, which in third person sits behind the character,
  so without it every shot aims at the player's own back. `Vector3.ZERO` means the
  component found no camera, and is treated as no answer rather than as the world
  origin.
- **`_shot_origin()`** is the muzzle when a weapon is in the hand, the shoulder
  otherwise — `draw_attach_delay` leaves ~0.22 s where the weapon is out and the
  mesh is not built.
- **`_shot_direction(origin)`** is the full-3D direction from origin to the aim
  point, with **three refusals that all fall back to `get_facing_direction()`**,
  which is exactly the pre-existing behaviour: no component; a ZERO answer; and a
  direction pointing behind the character, which in a TPS means the ray caught
  geometry between camera and player rather than an intention.
- **`_find_shot_target()`** is a cone around that line, from the muzzle, measured
  in 3D and aimed at the target's SHOULDER — against the feet, a target on a slope
  would fall out of the cone for being the wrong height rather than the wrong
  direction. Deliberately **not** a third mode on `_find_punch_target()`: a punch
  measures a horizontal cone from the body, a shot a 3D cone from the muzzle, and
  keeping them apart is what guarantees the punch is untouched.
- **`_has_clear_shot(origin, target)`** now casts from the same muzzle. It ran
  shoulder-to-shoulder before, which made the hit check and the tracer two lines
  free to disagree at a grazing angle; one origin removes that rather than
  documenting it. Measured before moving it: the muzzle is at 1.33 m against a
  1.476 m shoulder, so the kerbs the check was raised off the origin to clear are
  still well below it.

Target selection is a cone search and not a ray because **NPC bodies carry no
collision layer a ray could select on** without inventing one. That is unchanged.

### Measured: the weapon does not tilt at all

The angle between the barrel (the held instance's local **+X**) and the aim line
(muzzle to aim point), sampled in the running world:

| camera pitch | barrel vs aim line | barrel.y |
|---|---|---|
| 0 deg | **13.31 deg** | +0.157 |
| +30 deg | **23.74 deg** | +0.159 |
| -30 deg | **42.92 deg** | +0.158 |

**`barrel.y` does not move.** The aim line swings +-0.51 in Y across that sweep
and the barrel stays locked about 9 degrees above horizontal, because the pose
comes from the animation and nothing corrects it. The gameplay shot is now
correct; the visual is not, and this table is the size of what is left.

**What it implies for the next step, rather than a guess.** A spine-only
`LookAtModifier3D` would have to carry 13 to 43 degrees. The head look already
runs at 70/45 degree limits so a spine layer *could* physically reach it, but
40-odd degrees of spine bend reads as the character folding rather than aiming.
The 13.31 degrees at LEVEL aim is a separate, cheaper problem: it is a static
offset in the rest pose, so `HeldFit.rotation_deg` may absorb most of it before
any IK exists. `TwoBoneIK3D` ships with Godot 4.7 (verified in the binary) if the
arms are needed after that.

Every modifier that ever gets added must sit on **`OriginalSkeleton`**, after
`RetargetModifier3D`, where the existing `LookAt` already is — `Head` is bone 5
there and 6 in `GeneralSkeleton`, and a modifier on the wrong one is silently
overwritten by the retarget every frame.

