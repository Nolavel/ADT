# Changelog

Chronological work log for this repository. **This file records *when* things changed
and what is currently in flight.** For *how the project works right now*, `CLAUDE.md`
is authoritative — do not reconstruct current state by replaying this log.

Newest entries first. Each entry: what changed in substance, which systems/files it
touched, and — where relevant — which parallel track it came from.

> Хронологический журнал работ. Здесь — *когда* и *что* менялось; актуальное
> состояние проекта описано в `CLAUDE.md`, а не выводится из этого журнала.

---

## 2026-08-03 — Animation blending concept
Early concept work on animation blending, then two follow-up fixes once the tree
was actually exercised.
*Концепт блендинга анимаций и два последующих исправления после первых прогонов.*
- `player/player_components/` (animation)

**PEACE always faces the camera; strafe restored.** `_apply_direct_movement()` gave
PEACE a forward/backward hemisphere check that faced movement direction while walking
forward — so a pure-strafe input (e.g. the D key) just turned the body toward it and
walked forward; lateral movement never happened. Dropped the hemisphere branch: both
stances now always face the camera while moving, differing only in turn rate. PEACE's
animation branch was rebuilt to match — an `AnimationNodeBlendSpace2D` with the same
seven-point geometry COMBAT already had (only the center/idle clip differs), replacing
the old `Blend2(idle, BlendSpace1D(walk, run))` shape, which could only ever play
forward locomotion regardless of strafe input. `get_speed_multiplier()` (was
`_current_speed_multiplier()`, made public for the animation component) and a
stance-ceiling normalisation fix landed alongside it.
*PEACE теперь всегда разворачивается к камере, как COMBAT — раньше страйф не работал
физически. Ветка анимации PEACE перестроена в BlendSpace2D по образцу COMBAT.*
- `player/player.gd`, `player/player_components/animation_component/player_animation_component.gd`

**Run clip wired into both branches.** Both PEACE and COMBAT's forward point played
`new4/sneak-walk` at every speed from `walk_speed` to `run_speed` — the character
visibly walked while covering ground up to `run_speed / walk_speed` times faster than
the clip implies. Pre-dated the rebuild above; `ANIM_COMBAT_RUN` had been flagged
unwired twice. Split the forward axis into two points (walk at the new
`walk_blend_radius` export, run at the outer edge) instead of nesting a second blend
space, since the blend vector's length already carries speed. Left a comment flagging
that idle/walk/run now sit exactly collinear on the blend space's x=0 axis — an
unverified `auto_triangles` risk that needs checking the next time this runs in the
editor.
*Бег наконец подключён в обеих ветках — раньше при любой скорости играл клип шага.
Дистанция ходьбы разнесена по радиусу, а не вложенным блендспейсом.*
- `player/player_components/animation_component/player_animation_component.gd`

**Isometric camera follow state wired into `OnFootCameraComponent`.** The
ISOMETRIC arm used to orbit the character's raw position; it now orbits a new
`IsometricCameraState` follow point instead — a dead zone (the character can
drift inside a screen-space rectangle before the camera reacts at all, tighter
in COMBAT), lead toward the click-to-move destination rather than extrapolated
velocity, a vertical channel that tracks ground height instead of body height
(holds still on a jump, chases once a fall outlasts a grace period), and
asymmetric damping (slow catch-up while moving, fast settle once stopped).
`IsometricCameraDebugOverlay` draws the three zones plus the follow/character
markers when attached, fed by the host so it never recomputes what the state
already decided. Every ISOMETRIC-only value decays back to rest while TPS is
active (`_iso.decay(delta)`, called from the TPS arm) — the mirror image of
`_decay_tps_state()`, so neither view can hand the other a stale offset across
a `V` switch. Two small getters back this: `player.gd`'s `get_move_target()`
and `NavigationComponent`'s `get_final_target()`, both reading the current
click-to-move destination rather than reconstructing it from velocity.
*Состояние следования камеры в ISOMETRIC вынесено в `IsometricCameraState`:
мёртвая зона, упреждение к цели клика, отдельный вертикальный канал,
асимметричное демпфирование. Дебаг-оверлей рисует зоны. Состояние затухает
в TPS зеркально `_decay_tps_state()`.*
- `camera/camera_component/on_foot_camera_component.gd`, `camera/isometric_camera_state.gd`, `camera/isometric_camera_debug_overlay.gd`
- `player/player.gd`, `player/player_components/nav_component/navigation_component.gd`

**Isometric debug overlay wired up; dead-zone math made projection-aware.**
`OnFootCameraComponent.iso_debug_overlay` was declared and read from
`_push_iso_debug()` but nothing ever created or assigned it, so it could never
turn on. Added an `IsoCameraDebug` node (the overlay script, hidden by
default) to `camera_follow.tscn`, and a `camera_follow.gd` export
(`iso_debug_enabled`, own "Debug" group) that gates its visibility every
physics frame — on only while `PlayerState.mode == ON_FOOT` and
`view_mode == ISOMETRIC`, so it is structurally impossible for the overlay to
show during TPS. No key toggle: the earlier attempt at one read `Input`
directly outside `InputSystems`, which this project does not allow outside
`map_source/`/`map_camera/`; no such handler was present in this checkout, so
there was nothing to remove, but the export replaces that approach on
principle. Also fixed `_build_iso_frame()`'s `world_per_pixel`: it assumed a
perspective camera, but `camera_follow.tscn` stores an orthogonal camera
(`projection = 1`, `size = 20.0`) that `camera_follow.gd` currently overrides
to perspective at `_ready()` — correct today only because the code wins over
the scene. Branched on `camera.projection` so the dead zone stays correct if
that override is ever removed.
*Дебаг-оверлей мёртвой зоны наконец подключён — раньше он существовал, но
никто его не создавал и не назначал. Показывается только в ON_FOOT +
ISOMETRIC, управляется экспортом, а не клавишей (чтение Input вне
InputSystems здесь запрещено). world_per_pixel теперь учитывает тип проекции
камеры, а не только перспективную.*
- `camera/camera_follow.tscn`, `camera/camera_follow.gd`
- `camera/camera_component/on_foot_camera_component.gd`

---

## 2026-08-02 — Stance system, NPC body language, animation component
The densest day so far; three separate threads landed.

**`Stance` (PEACE / COMBAT) as declared intent.**
Added to `PlayerState` alongside `Mode`/`ViewMode`, changed only through
`set_stance()`. Bound to `T` via `InputSystems`. COMBAT slows movement, makes the
player face the camera and strafe unconditionally, and is now a precondition for
lock-on (previously lock-on was available in any stance).
*Стойка PEACE/COMBAT как явное намерение игрока — третий enum в PlayerState,
клавиша T. В COMBAT: медленнее, всегда лицом к камере, strafe, разрешён lock-on.*
- `core/player_state/player_state.gd` (`enum Stance`, `set_stance()`)
- `core/input/input_systems.gd` (`toggle_stance`)
- `player/player.gd`, `camera/camera_component/on_foot_camera_component.gd`

**`PlayerAnimationComponent` + stance-branched AnimationTree.**
Animation clip names extracted to constants; `get_movement_vector_relative_to_facing()`
added so the animation layer reads movement in the frame the body actually faces.
*Компонент анимаций игрока, дерево ветвится по стойке; вектор движения считается
относительно направления корпуса.*
- `player/player_components/` (new `PlayerAnimationComponent`)

**NPC body language.**
The body (not just the head) now turns toward a facing target when standing still,
and *commits* to the turn once the player has lingered off-angle — so the NPC does
not twitch back and forth at the threshold. Feel constants exported for by-eye tuning.
*NPC разворачивается корпусом, а не только головой; разворот «фиксируется» после
того, как игрок задержался вне угла — иначе NPC дёргался бы на пороге.*
- `npc/npc_base.gd`, `npc/controllers/`, perception debug panel

**Hygiene.** Bilingual RU/EN comment pairs dropped in favour of English only;
`get_move_axis()`/`get_move_vector()` unified into one method; dead `"Player"` group
and `get_state_name()` removed; stale doc-comments fixed in `TpsCombatCameraState`
and `CLAUDE.md`.

---

## 2026-07-31 — Documentation English pass, head look-at concept
English pass finished on `on_foot_camera_component.gd` and `player.gd`; stale NPC
scope note corrected in `planned_scope.md`. Started `head_lookat` concepting with
`LookAtModifier3D`.
*Английский пасс по документации; начат концепт поворота головы через LookAtModifier3D.*
- `camera/camera_component/on_foot_camera_component.gd`, `player/player.gd`
- `docs/planned_scope.md`, `CONTRIBUTING.md`

---

## 2026-07-30 — Camera overhaul, BodyMetrics, NPC perception foundation
**Camera.** Naive exponential smoothing replaced with frame-rate-independent damping.
Look sensitivity split per axis with invert options; horizontal look inversion fixed;
a radians/degrees mismatch that broke vertical look fixed. Position-follow rate
decoupled from both rotation-follow rate and view-transition speed. Camera now leads
in the movement direction. Sprint pull-back made explicit rather than accidental, and
decays in ISOMETRIC. `V` made symmetric — zoom drives to the edge before switching to TPS.
*Камера: framerate-независимое демпфирование, раздельная чувствительность по осям,
lead в направлении движения, симметричный V.*

**`BodyMetrics`.** Shared anatomical landmark ratios extracted as the single source of
body-size truth; camera reads TPS pivot/occlusion height from the target's own metrics
rather than hard-coded numbers.
*Единый источник истины по размерам тела; камера берёт высоту пивота оттуда.*

**NPC — first vertical slice of perception.** `NPCBase` body and placeholder scene,
a decision layer with one manual test instance, `PlayerObservation` as a plain
perception fact, `PerceptionComponent` (vision only), head turning toward a look
target decided by the controller, and a dedicated NPC perception debug panel.
Lock-on moved off `Tab` onto `G`; facing-direction convention mismatch fixed.
*NPC: база, слой решений, восприятие (только зрение), поворот головы, дебаг-панель.*
- `npc/npc_base.gd`, `npc/controllers/`, `npc/npc_components/`
- `core/body_metrics.gd`, `core/smoothing.gd`

---

## 2026-07-29 — Repository goes collaborator-ready; player rescaled
**Documentation/licensing infrastructure.** GDScript style guide, `docs/planned_scope.md`,
`CONTRIBUTING.md`, `CREDITS.md`, `LICENSE` added; README revised. Project renamed
`Prok` → `ADT` → back to `Vertical Trespass`. Empty placeholder component directories
(health, hunger, sleep, wallet, progression, equipment, crafting, save) removed —
that scope now lives in `planned_scope.md` instead of as empty folders.
*Инфраструктура для коллаборантов: style guide, scope, CONTRIBUTING, лицензия.
Пустые папки-заглушки удалены — их роль перешла к planned_scope.md.*

**Player body.** Capsule rescaled to 1.8 m with the origin moved to the feet; character
metrics introduced as the single source of body-size truth; `PlayerFocusCast` shrunk
from a room-sized volume to an actual reach volume.
*Капсула 1.8м, начало координат в ступнях.*

**Camera fixes.** TPS combat camera no longer updates only on the lock-on press frame;
TPS pitch no longer stomps the combat camera offset; pivot height split from occlusion
ray height; shoulder offset split between `h_offset` and translation.

**Ownership.** `mouse_mode` ownership moved from `PlayerState` to `InputSystems`.

---

## 2026-07-27 → 07-28 — Main menu stand
Four iterations of the main menu concept stand (`v0.1` → `v0.4`).
*Концепт-стенд главного меню, четыре итерации.*

---

## 2026-07-24 — Deck floor concept, tower demo
*Концепт палубного этажа, демо башни.*

---

## 2026-07-22 — Strata geometry, hover horizontal model
Horizontal hover motion switched from `move_toward` with a rate flipped by comparing
target/current speed, to exponential smoothing `velocity.lerp(target, 1 - exp(-k*delta))`.
The old form was bang-bang control without hysteresis: near `max_speed` the current
speed oscillates around the target within float error, flipping the rate between
accel and braking every frame — visible judder. Consequence: `acceleration`/`braking`
are now exponential coefficients (1/s), **not** m/s². Also fixed camera `_process`.
*Горизонталь ховера переведена на экспоненциальное сглаживание — move_toward с
переключаемым rate давал дрожь на максимальной скорости. Коэффициенты сменили смысл.*
- `core/controllers/transport/base/hover_base.gd`, `camera/camera_follow.gd`

---

## 2026-07-21 — Strata transitions made non-abrupt; world border
**Streaming.** Strata switching became hysteresis-gated (`STRATA_HYSTERESIS = 50 m`) so
the player must clear a boundary by a margin before the change commits. Within
`STRATA_PRELOAD_MARGIN = 100 m` of a boundary, the neighbouring `Layer<Strata>` is
background-loaded into `_packed_cache` — cache only, no early visual swap.
*Гистерезис страт + упреждающий прогрев соседнего слоя.*

**World border.** `WorldBorderGuardSystem` turns the controlled entity back toward the
centre near the World Zone edge (GTA-style), using the same anchor pattern as
`StreamingSystems` (on foot → player, in a hover → the hover). It never writes
`velocity` directly — it calls `HoverBase.set_border_steering_bias()`, which blends
into `wish_dir` before inertia. An earlier version wrote `velocity` from outside and
fought `_process_horizontal` every tick, producing jitter at the boundary.
`WorldBorderDebugSystem` draws the World Zone wireframe (`debug_visible` export).
*Разворот у границы мира через намерение, а не через прямую запись velocity.*
- `core/world/world_systems.gd`, `core/world/streaming_systems.gd`
- `core/world/world_border_guard.gd`, `core/world/world_border_debug.gd`

---

## 2026-07-20 — Segmented block silhouettes
Block silhouettes stopped being one solid mesh: the generator now emits three named
per-stratum segments (`MeshDoggerland`/`MeshManifold`/`MeshGlare`), and streaming hides
only the segment whose content layer is actually materialized. A stratum with no loaded
content shows its silhouette instead of empty space. Collision stays unsegmented.
*Силуэт блока разбит на три сегмента по стратам, скрываются независимо.*
- `tools/block_generator/block_library_generator.gd`, `core/world/streaming_systems.gd`

---

## Before 2026-07-20 — condensed

- **`2026-07-19`** — `InputHoverController`, `hover_camera_component`, `PlayerState.Mode.HOVER` (renamed from `VEHICLE_HOVER`), Blackrock font.
- **`2026-07-16`** — `block_generator`, `block_placer`, hover entry trigger, `hover_test` scene, inventory store.
- **`2026-07-15`** — stream debug panel (observer-only), ring metric for ground tiles, TPS combat/shoulder camera state concepts, stamina + movement blend demo, TOPDOWN camera position removed.
- **`2026-07-14`** — godot-ai MCP addon and first `CLAUDE.md`; dead `menu_pause.gd` dropped.
- **`2026-07-13`** — streaming cell conveyor (states, threaded loads, frame budget, strata layers); world Y=0 migration and ground-tile grid math; silhouette/content paths split; `CityZoneData` monolith dropped.
- **`2026-07-11`** — silhouette experiments.
- **`2026-07-06 → 07-09`** — controllers, in-game menu, `InputSystems` as sole `Input` reader, `MenuSystem`, zoom ruler, `WorldContext`, folder restructure, environment set concept.
- **`2026-07-01`** — migration to Godot 4.7, repo cleaning, editorconfig.
- **`2026-06-24 → 06-30`** — `map_source` level-design tool, versions 0.2 → 0.4.
- **`2026-06-12`** — **Vertical Trespass starts here.** The repository was repurposed from an earlier project; everything before this date belongs to that one.
- **`2025-11-25 → 2026-01-26`** — *predecessor project* (cryo silo, x-ray shader, display terminals, `InteractManager`). Not Vertical Trespass; same repository.

---

## Parallel tracks currently in flight

- **NPC perception & body language** — `npc/`, perception debug panel, head/body turning.
- **Player animation** — `PlayerAnimationComponent`, stance-branched AnimationTree, blending.

*Параллельные треки: NPC (восприятие, язык тела) и анимации игрока.*
