# Changelog

Chronological work log for this repository. **This file records *when* things changed
and what is currently in flight.** For *how the project works right now*, `CLAUDE.md`
is authoritative — do not reconstruct current state by replaying this log.

Newest entries first. Each entry: what changed in substance, which systems/files it
touched, and — where relevant — which parallel track it came from.

> Хронологический журнал работ. Здесь — *когда* и *что* менялось; актуальное
> состояние проекта описано в `CLAUDE.md`, а не выводится из этого журнала.

---

## 2026-08-13 — Drone periodic scan, search behaviour, LodgingRoom scene, sleep-hour picker

**Drone periodic PATROL scan; `alert_incident_radius` back to 60m.** Diagnosed from a
real playtest: raising `alert_incident_radius` to 600m had made drones react correctly
after a load, which looked like confirmation the `incidents_restored` fix (2026-08-12)
worked — but the real cause was distance, not the signal. `PatrolDroneController` only
ever checked `IncidentRegistry` at two fixed MOMENTS (resolving the registry, a load) —
never as it moved — so a drone patrolling directly over a fresh incident, at the
intended 60m radius, noticed nothing unless it happened to be within that radius at one
of those two instants. 600m was a diagnostic workaround, not a fix, and wrong for the
game: one incident would light up half the district in a city meant to react locally
and lazily, not as one mass.
*Периодическое сканирование реестра дроном в PATROL: реальная причина того, что 600 м
«помогало», была не в сигнале, а в том, что дрон проверял реестр только в двух
фиксированных случаях и никогда — на ходу. Радиус возвращён к 60.*

- New `PatrolDroneController._update_patrol_scan()` — every `patrol_scan_interval`
  (`1.0`s real time, PATROL only), re-runs the existing `_check_existing_incidents()`
  query against the drone's CURRENT position, not its position at some past moment.
  Documented as the third of three distinct hooks into that query (resolve-time
  catch-up, load-time catch-up, periodic scan) — each closes a different gap, none
  redundant with the others; the method's own header spells out which is which so a
  future reader doesn't mistake one for dead weight.
- `alert_incident_radius`: `600.0` → `60.0` (back to its pre-diagnosis value).
- `CLAUDE.md`'s `IncidentRegistry` paragraph updated: three ALERT-entry paths become
  four, with the periodic scan's own reasoning and the radius detour's story attached.
- `world/police_drone/controllers/patrol_drone_controller.gd`, `CLAUDE.md`.

## 2026-08-12 — Scope horizon document; doc cross-links; renderer constraint corrected

Added `docs/scope_horizon.md`: what is actively being built and in what order
(H1 dependency rules + save contract → H2 key-hints HUD → H3 EquipmentComponent
→ H4 pistol chain). Split of responsibility between the three tracking documents
stated explicitly: `planned_scope.md` = not started, `scope_horizon.md` = in
progress, `CHANGELOG.md` = done. Cross-linked from `CLAUDE.md`, `CONTRIBUTING.md`,
`planned_scope.md` and `readme.md`.

`CLAUDE.md`: renderer constraint corrected from Forward Mobile to Forward+ —
the file contradicted both `project.godot` and its own header. Shadow setting
renamed to `directional_shadow/size`, which is what is actually overridden.

> Добавлен документ активного горизонта работ; исправлено расхождение по
> рендереру в CLAUDE.md.

**H1 (part 1 of 2): save contract generalised, `SaveSystem` added, `IncidentRegistry`
made saveable.** `GameClockSystem.get_save_data()`/`load_save_data()` already existed
(predates H1) — this generalises that shape into an optional contract any
`WORLD_SYSTEM_SCRIPTS` entry can opt into (`get_save_key()` + `get_save_data()` +
`load_save_data()`, checked with `has_method()`, same idiom as the existing
`on_world_ready(context)` opt-in), and gives it a second, harder implementer.
*Контракт сохранения (get_save_data/load_save_data) обобщён из GameClockSystem в
опциональный интерфейс для любой системы; добавлен SaveSystem; IncidentRegistry
теперь тоже сохраняется.*

- New `core/world/save_system/save_system.gd` (`SaveSystem`, `WORLD_SYSTEM_SCRIPTS`
  entry, added last). Walks `WorldContext.systems`, collects `get_save_data()` under
  each system's own `get_save_key()`, writes `user://saves/slot_<n>.json` with a
  top-level `"version"` field present from this first write. `save_to_slot(slot)` /
  `load_from_slot(slot)` both return `bool` and `push_error`/`push_warning` with a
  specific reason on failure — a version mismatch refuses the whole file rather than
  half-loading it. Knows nothing about lodging, sleeping, or any in-fiction save
  point; something else decides *when* to call it.
- `InputSystems`: two new signals, `debug_save_pressed`/`debug_load_pressed`, bound to
  new actions `debug_save` (`F5`) / `debug_load` (`F9`) — a permanent developer tool,
  not the in-fiction save mechanism (sleeping). `project.godot`, `input_map.md` updated
  (action count 31 → 33).
- `core/world/game_clock/game_clock_system.gd`: added `get_save_key() -> "game_clock"`
  next to its existing `get_save_data()`/`load_save_data()` — no other change.
- `core/world/incident_registry/incident_registry.gd` and `incident.gd`: `Incident.
  perpetrator` (`Node3D`) → `perpetrator_id` (`StringName`) — a node reference is
  meaningless after a reload or once the reporting actor's block has streamed out.
  `report(perpetrator, kind, position)` → `report(perpetrator_id, kind, position)`;
  `has_recent_incident_by(perpetrator, within_seconds)` →
  `has_recent_incident_by(perpetrator_id, within_hours)`. Timestamps switched from
  `Time.get_ticks_msec()` (real seconds, reset on launch) to
  `GameClockSystem.total_game_hours` (game hours, itself saved/restored) — `_now()`
  resolves `GameClockSystem` via `on_world_ready(context)`. `max_incident_age`'s
  default changed from `30.0` (real seconds) to `0.25` (game hours ≈ 30 real seconds
  at default `time_scale`/`REAL_MINUTES_PER_GAME_DAY`) — a converted default, not the
  old number reinterpreted in a new unit. Implements `get_save_key()` →
  `"incident_registry"`, `get_save_data()`/`load_save_data()` (position flattened to a
  3-float array, `perpetrator_id`/`kind` to `String`/`int` — JSON has none of those
  types natively).
- `core/characters/actor_base.gd`: new `@export var actor_id: StringName` +
  `get_actor_id()`, authored per-instance the same convention as `BlockBase.id` /
  `LodgingRoom.room_id` — deliberately not derived from `get_path()`/
  `get_instance_id()`, both of which change across a streaming reload. Warns once in
  `_ready()` if left unset. The player is not an `ActorBase`; `player.gd` carries the
  same contract independently (`const ACTOR_ID := &"player"` + its own
  `get_actor_id()`), so `IncidentRegistry` resolves both through one duck-typed call.
- **Call site:** `IncidentRegistry._on_punch_landed()` is the only place that resolved
  a `Node3D` perpetrator before this change — it now calls `_player.get_actor_id()`
  before `report()`, with a `push_warning` (no report sent) if the player somehow has
  no such method. No other call site existed to update; `has_recent_incident_by()` has
  no callers yet either.
- `CLAUDE.md` updated: `WORLD_SYSTEM_SCRIPTS` list, the `IncidentRegistry` paragraph
  (id/timestamp change), and three new paragraphs (save contract, `ActorBase.actor_id`,
  `LodgingSystem`). `docs/scope_horizon.md` H1: corrected — the save contract already
  existed (`GameClockSystem`), so the task was generalising and documenting it, not
  defining a new one; checkboxes updated.

**H1 (part 2 of 2): `LodgingSystem`.** Durable per-room record — same "survives block
unloading" reasoning as `IncidentRegistry`. `docs/scope_horizon.md` itself scopes
sleep-as-save-point as *a separate item that does not block H1*; it landed here anyway
because the brief for this session bundled it into H1 explicitly. Flagged, not silently
reconciled — see this session's own report for detail.
*LodgingSystem — устойчивая запись по комнатам, добавлена в рамках этой сессии, хотя
scope_horizon.md изначально выносил её отдельным пунктом.*

- New `core/world/lodging/lodging_system.gd` (`LodgingSystem`, `WORLD_SYSTEM_SCRIPTS`
  entry). `_rooms: Dictionary` keyed by `room_id: StringName` →
  `{"last_slept_game_hours": float, "storage": Array}` (`storage` unused, present so
  the shape doesn't change later). `get_room_record(room_id)` creates a default record
  on first access; `notify_slept(room_id, slept_at_game_hours)` records that absolute
  reading. Implements `get_save_key()` → `"lodging"`, `get_save_data()`/
  `load_save_data()`. Does not import or call `SaveSystem` — the one-way dependency
  (room asks for sleep → sleep advances the clock → caller asks `SaveSystem` to write)
  is enforced by this file simply never mentioning it.
- Not yet built: the `LodgingRoom` scene that actually calls this system (step 4 of
  this session's brief) — stopped for review before that step, per the brief's own
  instruction.

**Review fixes on the above, same day.** Three corrections from a review pass before
step 4 started — two flagged in the original report and fixed cheaply as a result, one
found only by re-reading a file the report hadn't touched.
*Три правки по итогам ревью того же дня: две — по пунктам, отмеченным в отчёте, третья
найдена заново при чтении файла, которого отчёт не касался.*

- **`LodgingSystem.notify_slept()` stored the wrong quantity.** It wrote
  `hours_advanced` (a duration — how long the sleep took) into a field named
  `last_slept_game_hours`, which is supposed to answer "how long ago did the player
  sleep here" — a question a duration cannot answer, only an absolute clock reading
  can. Fixed: `notify_slept(room_id, slept_at_game_hours)` now takes the ABSOLUTE
  `GameClockSystem.total_game_hours` reading, taken by the caller after advancing the
  clock, not a duration taken during it. `LodgingSystem` still does not resolve
  `GameClockSystem` itself — the one caller this method exists for (`LodgingRoom`,
  not yet built) already has to hold that reference to advance the clock in the first
  place, so having `LodgingSystem` reach for `WorldContext` too would be a second copy
  of a lookup this file otherwise has no use for. New `LodgingSystem.NEVER_SLEPT`
  (`-1.0`) sentinel distinguishes "never slept here" from "slept during game hour 0" —
  `0.0` was ambiguous between the two, and `total_game_hours` only ever counts up from
  `GameClockSystem.START_HOUR` (`16.0`), so `-1.0` is unreachable by construction.
  `core/world/lodging/lodging_system.gd`.
- **`perception_debug_panel.gd`'s "last incident" line was reading the wrong clock —
  found during this fix, not flagged in the original report.** It still computed
  incident age as `Time.get_ticks_msec() / 1000.0 - incident.timestamp`, left over from
  before `Incident.timestamp` became game hours; after that change this was comparing
  an engine-uptime real-seconds value against a game-hours one, which would have shown
  a nonsense age (tens of thousands of "seconds") the moment anyone opened the panel.
  The original stale-reference sweep only grepped for `.perpetrator` and
  `has_recent_incident_by(` — it missed `.timestamp` itself. Fixed: the panel now
  resolves `GameClockSystem` via `on_world_ready()`, same as `IncidentRegistry` does,
  and reports age in game hours. `ui/debug/perception_debug_panel.gd`.
- **`docs/scope_horizon.md` H1 contradicted the brief that built it.** Lines 85–86 said
  sleep-as-save-point "is a separate item and does not block this one" — true when
  originally written, false since the brief for this session deliberately pulled
  sleeping-in-a-room into H1 as its actual payload: a debug keybind proves `SaveSystem`
  is wired correctly, but only a real save point (sleep) proves the contract is worth
  having, because nothing in the fiction produces a save any other way. The doc was not
  updated when that call was made. Corrected today, 2026-08-12 — the old line was not
  silently deleted; the replacement text says in-place that it held until this date and
  points here for why. Scope still excludes room availability/gating, any cost to
  sleeping, and item loss — only the act of sleeping-as-save-point moved into H1, not
  everything around it.

**The pruning-on-load incident.** DoD playtest (punch, run >0.35 game hours, save, quit,
relaunch, load) came back with the incident missing. Diagnosed against the actual save
file on disk, not just the code: `slot_0.json` held `game_clock.total_game_hours:
16.7704177555556` and `incident_registry.incidents[0].timestamp: 16.2768720055556` — a
gap of `0.4935` game hours between the punch and the save. The file was correct; nothing
pruned before writing it (`get_save_data()` doesn't prune, and nothing else calls
`_prune()` between a punch and a save unless a second punch happens). The eviction
happened inside `IncidentRegistry.load_save_data()`'s own trailing `_prune()` call,
which is correct given `max_incident_age` was `0.25`: `WORLD_SYSTEM_SCRIPTS` order
(`world/world.gd`) restores `GameClockSystem` before `IncidentRegistry`, so by the time
that `_prune()` ran, "now" was already the restored `16.7704...`, correctly computing the
incident as `0.4935` game hours old — which exceeds `0.25`. Root cause: `max_incident_age`
was inherited from a real-seconds drone-reaction timer and never re-examined as a
city-record retention window once it became one.
*Инцидент с прунингом при загрузке: диагностирован по реальному файлу сохранения, а не
только по коду — запись была корректно сохранена, но выброшена при загрузке
собственным вызовом _prune() внутри load_save_data(), потому что max_incident_age
(0.25 игрового часа) был перенесён из таймера реакции дрона и никогда не пересмотрен
как окно хранения записи городом.*

Four fixes from this diagnosis, three requested, one found while implementing the third:

- **`IncidentRegistry.max_incident_age`: `0.25` → `24.0` game hours (one in-game day).**
  Header now states explicitly that this is a retention window ("how long the city keeps
  a fact on record"), not a reaction timer, and that it is NOT the same value as
  `PatrolDroneController.alert_memory_time` (real seconds, unrelated, unchanged) despite
  once sharing a rough magnitude by accident of history. `max_incidents` (unchanged, the
  count-based cap) remains the actual safety valve against unbounded growth, so raising
  the age doesn't trade that away. Not addressed: whether retention should differ by
  `Incident.Kind` (e.g. evidence vs. ambient noise) — moot today since `Kind` has exactly
  one value; flagged in this session's own report as a call for Stan if/when a second
  `Kind` exists, not implemented. `core/world/incident_registry/incident_registry.gd`.
- **`SaveSystem` debug save/load now logs payload composition.** `_on_debug_save_pressed()`/
  `_on_debug_load_pressed()` each print one line per system (`get_save_key()`: size of
  every array/dict field, e.g. `incident_registry: incidents: 0`) via a new
  `_print_payload_summary()`/`_summarize_payload()` pair, safe to call immediately after
  save/load since `get_save_data()` is a pure read (re-invoking it cannot change what was
  written or loaded) and reports actual post-load state, including anything
  `load_save_data()` itself pruned — this is what would have shown the incident count
  dropping to `0` in the log instead of costing a manual save-file inspection.
  `save_to_slot()`/`load_from_slot()` themselves remain silent when called from game
  logic — only the debug handlers print. `core/world/save_system/save_system.gd`.
- **`PatrolDroneController` now catches up on incidents already on record, not only ones
  reported live.** New `IncidentRegistry.get_incidents_near(point, radius, max_age) ->
  Array[Incident]` (read-only, doesn't prune, same convention as
  `has_recent_incident_by()`). New `PatrolDroneController._check_existing_incidents()`,
  called exactly once — from `_try_resolve_incident_registry()`, the moment resolution
  succeeds, never polled — queries `alert_incident_radius` around the drone using
  `IncidentRegistry`'s own `max_incident_age` as the recency bound (no second threshold
  invented). Both this path and the existing live `incident_reported` path now funnel
  through one new `_trigger_alert()` instead of duplicating the "reset memory timer,
  enter ALERT" logic twice. Closes the same gap for the CONSUMER that H1 closed for the
  fact itself: a record surviving reload/streaming is wasted if nothing that appears
  afterward can read it, only hear about it happening live. `core/world/incident_registry/
  incident_registry.gd`, `world/police_drone/controllers/patrol_drone_controller.gd`.
  **Correction, same day, below:** this bullet's closing claim was wrong for the
  save/load case specifically — see "The incidents_restored gap" entry further down.
  This one-shot, resolve-time query alone does not cover a load happening later, on a
  player keypress, after a drone has already resolved the registry.
- **`debug_save`/`debug_load` rebound `F5`/`F9` → `K`/`L`.** `F5` collides with the Godot
  editor's own "Run Project" shortcut, which intercepts the key before it reaches the
  running game when the game view is embedded — exactly why the DoD playtest above had to
  fall back on quitting to desktop rather than a quick in-editor round-trip.
  `project.godot`, `input_map.md`.

**The `incidents_restored` gap.** Points 1/2/4 of the previous fix round verified clean
in Stan's log (`incidents: 2 entries` matched before and after a save/load, times
matched) — point 3 did not: drones stayed `PATROL` after a load even though the panel
and the log both showed the incident restored. Diagnosed by reading
`_try_resolve_incident_registry()`/`_check_existing_incidents()` again against the
actual sequence of events, not just re-reading the method in isolation:
`_try_resolve_incident_registry()` runs once, early — a few frames into a fresh
session, before anything has happened, so `_check_existing_incidents()`'s one query
reliably finds nothing. Its own `if _incident_registry: return` guard means it never
runs again. A load triggered later, on a player keypress, long after that one query
already ran and found nothing, was consequently invisible to this drone — not a
timing race, a hook that had already permanently fired and closed.
*Пробел с incidents_restored: резолв реестра дроном происходит один раз, рано, пока
реестр ещё пуст — последующая загрузка сохранения этому единственному запросу уже не
видна, и запрос больше никогда не повторяется.*

The original framing of H1's drone-catch-up task ("разовая синхронизация при
появлении в мире") was correct for a drone streaming back into the world, and wrong
for a load: a load is not the drone appearing, it is the registry's own content being
replaced out from under a drone that is already there. The fix adds a second, distinct
hook for that:

- New `IncidentRegistry.incidents_restored()` signal, no payload, emitted at the end of
  `load_save_data()` after `_incidents` is rebuilt and pruned. Deliberately NOT a
  replay of `incident_reported` once per restored entry — considered and rejected:
  `incident_reported` means "this just happened", which a consumer could reasonably
  treat as license to act as though it were fresh (extend a live reaction, stamp a
  fresh detection time); a restored incident is pre-existing state a consumer merely
  missed, and replaying the live signal would make that distinction permanently
  unrecoverable for any future consumer that needs it. The cost paid for that honesty:
  a second signal every future `incident_reported` consumer has to separately decide
  whether it also needs. `core/world/incident_registry/incident_registry.gd`.
- New `PatrolDroneController._on_incidents_restored()`, connected alongside
  `incident_reported` in `_try_resolve_incident_registry()`. Re-runs the existing
  `_check_existing_incidents()` query rather than a parallel code path.
  `_check_existing_incidents()` is now explicitly documented as serving TWO distinct
  callers/cases — resolve-time (streaming re-entry, effectively inert today) and
  load-time (the path that actually matters today) — with a comment spelling out which
  is which, so the two don't read as redundant to the next person who touches this
  file. `world/police_drone/controllers/patrol_drone_controller.gd`.
- `_check_existing_incidents()` now no-ops while the drone is already `ALERT`. Checked
  specifically because a load can now trigger a second catch-up call against a drone
  that's already `ALERT` from an earlier live report or an earlier catch-up, and
  `_trigger_alert()` unconditionally resets `_alert_memory_timer` — harmless today only
  because ALERT's own decay is commented out (`_update_state()`'s "Temporary
  behaviour" note: ALERT currently persists indefinitely regardless of the timer), but
  would become a live bug — a permanently-refreshed timer that never lets ALERT lapse —
  the moment that decay is re-enabled. `_on_incident_reported()` (the live path)
  deliberately keeps no equivalent guard: a genuinely new live report while already
  `ALERT` is a real, fresh provocation and should extend the hold; a catch-up finding
  what the drone already knows about is not.
- Investigated, not changed: whether a single punch could call `report()` twice,
  explaining Stan's `incidents: 2 entries` after what he described as one beating.
  `player.gd`'s punch path guards against it three separate ways —
  `_punch_hit_resolved` gates `_resolve_punch_hit()` to at most once per
  `_start_punch()`, `_is_punching` blocks a second punch from starting while one is in
  flight, and `_find_punch_target()` returns at most one `NPCBase` — and
  `IncidentRegistry.on_world_ready()` connects `punch_landed` exactly once. No path
  found for one punch to produce two reports; `2 entries` most plausibly reflects two
  real punches across a multi-round test session, not a duplicate-report defect. No
  code change from this finding.

## 2026-08-11 — HealthComponent wired to player and NPCs; NPCs take damage and stay down

Seven commits connecting `HealthComponent` (built earlier but never attached to either
actor) to the player and to NPCs, and giving `NPCBase.take_hit()` real damage with a
terminal knocked-down state instead of the old infinite three-phase knockdown loop.
*Семь коммитов: HealthComponent подключён к игроку и NPC, take_hit() теперь наносит
урон и держит терминальный нокдаун вместо бесконечного цикла из трёх фаз.*

**`HealthComponent` node type: `Node3D` → `Node` in `player.tscn`.** Health has no
position in space — `PerceptionComponent` is `Node3D` because it needs a vantage point,
`AnimationComponent` is a plain `Node`; `HealthComponent` belongs with the latter. Name,
node path and the attached script are unchanged.
*HealthComponent — Node, а не Node3D: у здоровья нет точки в пространстве.*
- `player/player.tscn`

**`HealthComponent` moved to `core/components/health_component/`.** It is shared by the
player and NPCs, so it does not belong under `player/`. `health_component.gd` and its
`.uid` moved via `git mv`; `player.tscn`'s `ext_resource` path updated to match. The
leftover empty `player/player_components/health_component/` and
`npc/npc_components/health_component/` placeholder directories are removed —
`class_name HealthComponent` is global, so no by-type reference needed touching.
*HealthComponent переехал в core/components/ — компонент общий для игрока и NPC, папке
игрока он не принадлежит.*
- `core/components/health_component/health_component.gd`,
  `core/components/health_component/health_component.gd.uid`, `player/player.tscn`

**`world.gd` now calls `player.on_world_ready(context)`.** The player scene was the one
thing `World._init_world()` spawned without ever offering it the same optional
`on_world_ready(context: WorldContext)` hook systems/3D-entities/UI scenes already get —
needed so the player's `HealthComponent` can reach `GameClockSystem`. Called right after
`context` is fully populated (`context.systems` included), same requirement
`WorldContext.get_system()` already has for every other caller.
*world.gd теперь зовёт player.on_world_ready(context) — раньше игрок был единственным,
кто не получал контекст мира.*
- `world/world.gd`

**Player `HealthComponent` wired to `GameClockSystem`.** New `_health` `@onready` ref
and `on_world_ready(context: WorldContext)`, which resolves `GameClockSystem` via
`context.get_system()` and passes it to `HealthComponent.setup()`. `died` is subscribed
in `_ready()` to a `_on_died()` stub — `TODO(health)`, only a `push_warning()` for now:
the death clip exists somewhere in the animation libraries but which one is unconfirmed,
so it is not wired up yet. Stamina's `band_changed` hookup is explicitly out of scope
for this change.
*HealthComponent игрока подключён к GameClockSystem; died пока только push_warning —
анимация смерти не подключена, клип не подтверждён.*
- `player/player.gd`

**`HealthComponent` added to `npc.tscn`.** Plain `Node`, `max_health = 100.0`,
`enable_conditions = false` (NPCs take plain hit-point damage — no bleeding, no
fractures), `debug_log = true` for the duration of the debug pass below. `setup()` is
not called: NPCs are streamed in/out by `StreamingSystems` and never see a
`WorldContext`, and with `enable_conditions` off the component has nothing that needs
`GameClockSystem` anyway.
*HealthComponent добавлен в npc.tscn — только очки здоровья, без кровотечений/переломов
и без setup(), NPC не видят WorldContext.*
- `npc/npc.tscn`

**NPCs take damage and stay down at zero health.** `take_hit()`'s signature grows a
`damage: float = 12.0` parameter (default ≈ nine hits to empty a 100 HP bar) and applies
it to `HealthComponent` — every hit, even to a body that's already down, so a downed NPC
can be finished off. Only the fall itself still no-ops while already knocked down (no
retriggering the fall clip mid-knockdown — unchanged). `HealthComponent` is resolved the
same optional `get_node_or_null()` way `_animation` already is: without one, an NPC
keeps the old infinite three-phase loop and a single `push_warning()` in `_ready()`.
New terminal `KnockdownPhase.DOWN`: entered from `FALLING` once the fall clip finishes
if health is already zero, or immediately (no timer) from `LYING`/`GETTING_UP` the
moment health hits zero — holds the same looping lying clip as `LYING` and never
transitions out, so `is_knocked_down()` stays `true` forever and movement/perception
stay gated exactly as they already were for the other three phases (no code changed
there — both already key off `is_knocked_down()`). The one real caller
(`player/player.gd`'s `_resolve_punch_hit()`) needed no change — the new `damage`
parameter's default covers it. The file header's now-false "not damage, this project
has no health yet" claim on `take_hit()` is corrected.
*NPC теперь получают урон и остаются лежать при нуле здоровья — новая терминальная фаза
DOWN, из которой нет выхода; повторные удары по лежащему теперь засчитываются.*
- `npc/npc_base.gd`

**Optional debug health label above NPCs.** New `DebugHealthLabel` (`Label3D`,
`billboard` enabled, hidden by default) in `npc.tscn`, driven by a new
`@export var debug_show_health: bool = false` on `NPCBase`. While on, shows
current/max health and the knockdown phase name (only while actually knocked down —
`_knockdown_phase` otherwise holds a stale value from the last knockdown, not a
meaningful "current" one); while off the label is hidden and its text is never
recomputed. Placement height comes from `get_eye_height()`
(`BodyMetrics.eye_height()`) — `BodyMetrics` has no dedicated "above the head" ratio,
only eye/shoulder/chest, so this is the closest existing landmark rather than an
invented offset; see the `TODO(health)` left in `_ready()`.
*Отладочная подпись здоровья над NPC — Label3D, скрыт по умолчанию, включается
per-instance через debug_show_health.*
- `npc/npc.tscn`, `npc/npc_base.gd`

**`BodyMetrics` gains a head-top landmark.** New `HEAD_TOP_RATIO` (1.0) and
`get_head_top_height()`, same shape as `EYE_RATIO`/`eye_height()`. A character's origin
sits at the feet, so the top of the head is the full `body_height`, not a fraction of
it — the constant exists for uniformity with the other landmarks, not because 1.0 is a
number anyone could get wrong. Closes the `TODO(health)` left on the NPC debug label,
which had been using `eye_height()` as a stand-in for lack of a dedicated ratio.
*BodyMetrics получил ориентир «макушка» — HEAD_TOP_RATIO = 1.0, начало координат в
ступнях, поэтому это весь рост целиком.*
- `core/characters/body_metrics.gd`

**NPC debug health label moved to the head-top landmark.** `DebugHealthLabel`'s
placement now uses a new `get_head_top_height()` wrapper (mirroring `get_eye_height()`/
`get_shoulder_height()`) plus a new local `DEBUG_LABEL_CLEARANCE` (0.25) on top — an
interface offset, not a body measurement, so it stays in `npc_base.gd` rather than
becoming another `BodyMetrics` ratio. Was sitting at eye level as a stand-in; closes the
`TODO(health)` left there.
*Отладочная подпись NPC теперь над макушкой, а не на уровне глаз — TODO(health) закрыт.*
- `npc/npc_base.gd`

**Stale-comment pass: `on_world_ready`, `take_hit()`, `PlayerState` enums.** Comment
text only, no code changes. `player.gd`'s `_click_to_move_system` comment claimed
player.gd wasn't part of `world.gd`'s `on_world_ready()` sweep — it has been since the
previous session; rewritten to explain why the separate `ClickToMoveSystem` injection
still exists instead (that `WorldContext` has no dedicated `ClickToMoveSystem` field,
and the injection predates it). `CLAUDE.md`'s `take_hit()` paragraph didn't mention
`HealthComponent`, damage, or the terminal `KnockdownPhase.DOWN` phase — updated to
match the current contract. Checked `CLAUDE.md`'s `PlayerState` paragraph for the
`VEHICLE_HOVER`/`TOPDOWN` staleness this task also flagged: it already reads `HOVER`
and already documents `TOPDOWN` as removed, matching `player_state.gd`'s actual enum —
no change needed there.
*Правка устаревших комментариев (без изменения кода): on_world_ready в player.gd,
контракт take_hit() в CLAUDE.md; перечисление PlayerState в CLAUDE.md уже верно.*
- `player/player.gd`, `CLAUDE.md`

**New `StatusBarWidget`: a reusable three-segment status gauge.** Draws one ratio as
three separate bars in a shared frame via `_draw()` (same reason `aim_reticle.gd` does:
exact pixel control, zero art assets), draining right to left, no numbers on screen —
colour and remaining fill are the whole readout. Knows nothing about health: takes a
ratio and a list of cause labels through `set_ratio()`/`set_labels()`, so hunger and
rest (data not wired up yet) are meant to be further instances of the same scene,
stacked underneath with their own colours — why thresholds/colours are exported rather
than hard-coded. `status_bar_widget.tscn` is a single `Control` root with the script
attached, all exports left at their defaults.
*Новый переиспользуемый виджет статус-бара — три сегмента одной полосы, ничего не знает
про здоровье конкретно, только ratio и подписи.*
- `ui/hud/status_bar/status_bar_widget.gd`, `ui/hud/status_bar/status_bar_widget.tscn`

**Player health now shows on the HUD.** New `PlayerHUD` (`ui/hud/player_hud/`), a
top-left `StatusStack` (`VBoxContainer`) holding one `StatusBarWidget` instance
(`HealthBar`) today, with hunger/rest meant to stack in the same way once those systems
exist. `PlayerHUD` is the only place `HealthComponent` and `StatusBarWidget` meet —
neither knows about the other — resolving the player's `HealthComponent` in
`on_world_ready(context)` (same `WorldContext` hook `aim_reticle.tscn` already uses,
registered in `world.gd`'s `WORLD_UI_SCENES` right next to it) and subscribing to
`health_changed`/`condition_changed`. Hunger/rest and stamina's `band_changed` are
explicitly not wired up yet — the widget is shaped for them, the data isn't there.
*Здоровье игрока теперь на HUD — PlayerHUD сводит HealthComponent и StatusBarWidget,
подписка на world.gd's WorldContext, как у aim_reticle.*
- `ui/hud/player_hud/player_hud.gd`, `ui/hud/player_hud/player_hud.tscn`, `world/world.gd`

**Fix: `PlayerHUD.on_world_ready()` crashed on spawn.** `world.gd` adds `WORLD_UI_SCENES`
instances via `call_deferred("add_child", ...)`, so a UI scene's own `_ready()` — and
therefore any `@onready` var — hasn't necessarily run yet by the time `on_world_ready()`
fires; `perception_debug_panel.gd` never hit this because its `on_world_ready()` only
stores a reference, but `player_hud.gd`'s calls straight into `_health_bar.set_ratio()`.
Runtime error: `Invalid call. Nonexistent function 'set_ratio' in base 'Nil'`.
`on_world_ready()` now does `if not is_node_ready(): await ready` before touching
`_health_bar` — a no-op for every other `on_world_ready()` caller (systems, 3D
entities), which are already fully ready by the time it's called.
*Фикс: PlayerHUD падал при спавне — on_world_ready() вызывался до собственного _ready()
у UI-сцен (world.gd добавляет их через call_deferred), _health_bar был ещё null.*
- `ui/hud/player_hud/player_hud.gd`

**Fix: `HealthComponent`'s `extends` line never matched its node type.** An earlier
commit changed `player.tscn`'s `HealthComponent` node type from `Node3D` to `Node`, but
never updated the script's own `extends Node3D` to match — a load-breaking mismatch that
sat committed until a local, uncommitted editor fix surfaced it. Now `extends Node`,
matching both `player.tscn`'s and `npc.tscn`'s already-correct node types. Also folds in
a harmless leftover `npc.tscn` diff: `max_health`/`enable_conditions` dropped from the
`HealthComponent` node (Godot's editor strips exported values equal to the script's own
defaults on save — same 100.0/false either way).
*Фикс: extends-строка HealthComponent не совпадала с типом узла в сценах — исправлено на
extends Node.*
- `core/components/health_component/health_component.gd`, `npc/npc.tscn`

**Fall damage on hard landings.** New `player.gd` export group `fall_damage_min_speed`
(8.0), `fall_damage_lethal_speed` (20.0), `fall_fracture_damage` (20.0). Landing is
detected by the not-on-floor → on-floor transition (`is_on_floor()` before/after
`move_and_slide()`), not a height threshold — a height check breaks on slopes, ledges
and moving platforms, but the vertical speed at the instant of impact does not.
`velocity.y` has to be cached immediately before `move_and_slide()` each frame, since
`is_on_floor()` only reflects the current frame's real collision result *after*
`move_and_slide()` resolves it, by which point the actual impact speed is already gone
from `velocity.y` itself. Damage grows quadratically between the two thresholds (a
normalised ratio, squared, times `HealthComponent.max_health`), so an eight-metre fall
barely registers while the last few metres before the lethal threshold read as
dramatically worse. A landing that deals at least `fall_fracture_damage` also calls
`add_condition(HealthComponent.Condition.FRACTURE)`. Verified analytically (not by
running the editor) that an ordinary jump can't hurt itself: `jump_force` (6.0) and
`gravity` (20.0) mean a standing jump lands at exactly `jump_force` = 6 m/s by energy
conservation, safely under `fall_damage_min_speed` (8.0) — no constants needed tuning to
make that hold.
*Урон от падения по скорости приземления, не по высоте; квадратичная кривая между двумя
порогами; перелом при достаточно тяжёлом ударе. Обычный прыжок проверен аналитически —
не ранит.*
- `player/player.gd`

**Permanent death branch in the player animation tree.** New `ANIM_DEATH`
(`new4/die2`) and public `play_death()`/`is_dead()` on `PlayerAnimationComponent`.
Deliberately NOT another `AnimationNodeOneShot` layered over locomotion the way the
punch is — the same trap `npc_base.gd`'s own header describes for its knockdown clips:
a `OneShot`'s non-looping clip snaps back to whatever is underneath the instant it
finishes, which is exactly wrong for a pose that has to hold forever. Instead, a new
`AnimationNodeTransition` (`death_transition`) sits at the tree's root with two named
inputs — `alive` (the entire tree built so far, previously wired straight to `output`)
and `death` (a single non-looping `AnimationNodeAnimation`, which holds its last frame
once it finishes — exactly the permanent pose needed). The switch only ever runs one
way: nothing in the file ever requests `alive` again, and `play_death()` is idempotent
via `is_dead()`'s own latch. New `@export var death_transition_time: float = 0.2`
(crossfade duration), same role as the existing `stance_transition_time`. Internal tree
parameter names (`death_transition`, its `transition_request`) do not leak past
`play_death()`/`is_dead()`, same contract `play_punch()`/`is_punch_active()` already
keep.
*Постоянная ветка смерти в дереве анимаций — AnimationNodeTransition, а не OneShot:
поза должна держаться вечно, а не соскакивать после окончания незацикленного клипа.*
- `player/player_components/animation_component/player_animation_component.gd`

**Player locked out of control on death.** `_on_died()` now calls
`_animation_component.play_death()`, `set_movement_enabled(false)`, and sets a new
permanent `_is_dead` flag. `movement_enabled` alone already stops `_handle_jump()` and
`_on_primary_click_pressed()` (both only reachable from inside its gate), but not
`_update_punch()`, which `_physics_process()` deliberately runs regardless of
`movement_enabled` so an in-progress punch can still unlock itself — `_is_dead` is
checked first, ahead of that unconditional call, so a corpse can never land the last hit
of a punch already in flight. One deliberate exception to the lock: gravity (and
`move_and_slide()`) keep running while dead, so a body that died mid-air still falls to
the ground — everything else stays frozen. No revive in this task; a `TODO(save)` marks
where `_is_dead` gets cleared once respawn/load exists.
*Игрок теряет управление насовсем при смерти — гравитация продолжает работать
(труп должен долетать до земли), всё остальное блокируется через _is_dead.*
- `player/player.gd`

**Hotfix: T-pose after the death branch landed.** `death_transition`'s inputs were built
with `add_input()`, which `AnimationNode` inherits but which does nothing useful on an
`AnimationNodeTransition` — that node sizes its inputs from `input_count` instead, so the
transition ended up with zero real inputs. `connect_node()` succeeded silently (no
console error), the node passed nothing through to `output`, and the skeleton fell back
to its rest pose for every animation, not just death. Fixed by setting
`input_count = 2` and naming the inputs via `set_input_name(0, "alive")` /
`set_input_name(1, "death")`. Second half of the same gap: `AnimationNodeTransition` has
no meaningful default state, so `_setup_animation_tree()` now explicitly requests
`"alive"` right after activating the tree (the same reason `stance_blend`'s init already
existed there — a `Blend2`'s default `blend_amount` of `0.0` needed no equivalent nudge).
`play_death()` was already requesting the transition by input name (`"death"`), so it
needed no change. Closes the `TODO(health)` about the unverified `AnimationNodeTransition`
API; the `new4/die2` loop-flag `TODO(health)` stays open — still unconfirmed without the
editor.
*Хотфикс: T-поза после ветки смерти — входы AnimationNodeTransition задаются через
input_count/set_input_name, а не add_input(); плюс явный старт в "alive".*
- `player/player_components/animation_component/player_animation_component.gd`

**`StaminaComponent` gains an external capacity ceiling and a sprint block.** New
`@export var critical_capacity_ratio: float = 0.25` (a tuning value, not written to from
code), `set_capacity_ratio(ratio: float)`, internal `get_effective_max_stamina()`
(`max_stamina * _capacity_ratio`), and `set_sprint_blocked(blocked: bool)`, independent
of the ratio — sprinting and the ceiling are two separate decisions on purpose, so
either can be tuned without dragging the other along. Every `max_stamina` reference in
the file was checked individually: recovery (`_update_stamina()`), `get_stamina_ratio()`
(now guarded against a zero ceiling), `restore_stamina()`, `is_recovering()`, and the
initial `_ready()` fill now target the effective ceiling; `stamina_changed`'s emitted
max, `get_max_stamina()`, `try_jump()`'s cost and the debug label stay against the
nominal `max_stamina` on purpose (UI-facing, or a fixed-quantity cost) — each with a
comment explaining the choice. Lowering the ceiling clamps `current_stamina` down
immediately, with its own `stamina_changed` emit, rather than waiting for the next
`_process()` to drain it down. `set_stamina_parameters()`'s own internal rescale
(previously double-counting through the now-ceiling-relative `get_stamina_ratio()`) was
corrected to keep working against the nominal max, still clamped to the current ceiling
afterward — a direct, necessary consequence of `get_stamina_ratio()`'s new meaning, not
a separate change. The component still knows nothing about health; `player.gd` (next
commit) is the only thing that knows why the ceiling ever moves.
*StaminaComponent получил внешний потолок и отдельный флаг запрета спринта — компонент
не знает, откуда взялся коэффициент, это дело player.gd.*
- `player/player_components/stamina_component/stamina_component.gd`

**`player.gd` ties health to the stamina ceiling.** New `_on_health_band_changed(band)`,
subscribed to `HealthComponent.band_changed` in `on_world_ready()` — the same place
`HealthComponent.setup()` already runs, since `player.gd` is the only thing that owns
both `HealthComponent` and `StaminaComponent`; neither component knows the other
exists. In `CRITICAL`: `stamina_manager.set_capacity_ratio(stamina_manager.
critical_capacity_ratio)` and `set_sprint_blocked(true)`; every other band: ratio back
to `1.0`, sprint block lifted. Fired once immediately after subscribing, with the
current band — same reason `player_hud.gd` already fires its own initial paint:
`HealthComponent` reaches full health in its own `_ready()`, before any subscription
exists, so the first signal would otherwise only arrive on the first point of damage.
The ceiling, not an outright block, is the deliberate choice: a player who can't run at
all is caught in a spiral — weakened, unable to get away, weakened further. A quarter
of the tank is enough for a short burst, not enough to sprint away clean; sprinting
itself is still refused separately, since the lowered ceiling alone doesn't stop
`is_running_mode` from reading as a sprint.
*player.gd связывает здоровье и стамину — в CRITICAL режется потолок (не отключается
бег целиком, чтобы не запустить спираль ослабления), спринт запрещается отдельно.*
- `player/player.gd`

**`StaminaComponent` brought in line with project conventions (partial).** The file
predated the project's style rules: `extends Node3D` with no spatial meaning, Russian
comments, no `##` docs on the class or its exports. Fixed `extends Node` to match
(`player.tscn`'s `StaminaComponent` node changed from `Node3D` to `Node` in the same
commit — the two must move together or the script fails to attach, the exact mismatch
`HealthComponent` shipped with earlier), translated every comment to English, added a
banner header and `##` docs on the class's public members and `@export` vars (including
translating the two `@export_group` labels, which are inspector-facing strings, not
lexical comments, but the same inconsistency otherwise). All value defaults and logic
are unchanged — diffed line by line to confirm. Left out on purpose: moving stamina's
update from `_process()` to `_physics_process()` changes behaviour on an unstable frame
rate (a fixed-step drain/recovery rate reads differently against real time than against
physics ticks), so per the task's own fallback it stays a question instead of a change —
see the closing list.
*StaminaComponent частично приведён к конвенциям — extends Node, английские комментарии
и `##`-документация, без изменения поведения. Перенос в _physics_process оставлен как
открытый вопрос.*
- `player/player_components/stamina_component/stamina_component.gd`, `player/player.tscn`

**Police drones stop oscillating when several converge on the player.** `_decide_hold_and_watch()`
(`patrol_drone_controller.gd`, shared by OBSERVE and ALERT) previously blended a
separation push into the movement DIRECTION alongside the approach direction. That
blend degenerates to pure separation drift at nonzero speed the instant a drone
reaches the hover ring — no combination of the two directions is ever exactly zero —
so a drone pushed off the ring by a neighbour immediately regained a full "return to
the ring" pull the moment it crossed `hover_approach_margin`, flew back in at speed,
got pushed out again: a stable limit cycle, not a resting state, visible as dithering
and circling with two or more drones (invisible with one, since separation is zero
then). Fixed by making separation offset the GOAL POINT instead — metres of
displacement on where the drone is flying TO (the nearest point on the hover ring to
its own current bearing from the player, so drones starting on different sides stay on
different sides), not degrees blended into a velocity that never actually reaches
zero. New `@export var hold_deadband: float = 0.5` — arriving within this distance of
the goal point now actually stops the drone, a state the old direction-blend could
never reach at all. `separation_weight`'s meaning changed accordingly (now a
metres-per-unit-offset multiplier, not a direction-blend weight) and its doc comment
was rewritten; its value (1.5), `separation_radius` (12.0), `observe_hover_distance`
(10.0) and `alert_hover_distance` (6.0) were left untouched for the project author to
retune by eye if needed.

Bundled into the same commit — earlier uncommitted local tuning that led here: mutual
separation between drones in the first place (so multiple police drones converging on
the player spread across different hover positions instead of stacking on one point,
`_raw_separation_offset()`/`_update_separation_offset()`, `separation_radius`/
`separation_smoothing`), and a deliberately visible tracking lag
(`_tracked_player_position`/`player_tracking_lag`, `_update_tracked_player_position()`)
so the drone's body and spotlight beam trail the player's actual motion rather than
snapping onto their live position every frame — now also driving the movement goal
itself, not just `set_look_target()`, which is what made the lag actually show up in
how the drone flies.
*Дроны больше не колеблются при нескольких вокруг игрока — сепарация теперь смещает
целевую точку полёта, а не подмешивается в направление скорости, что раньше давало
устойчивый предельный цикл. Плюс задержка слежения теперь влияет и на полёт, не только
на взгляд.*
- `world/police_drone/controllers/patrol_drone_controller.gd`

---

## 2026-08-10 — Punch works in ISOMETRIC, standing still, without blocking movement

Four commits fixing the defect recorded in `docs/NPC_REACTIONS.md` (the punch
only fired in TPS view) and then correcting an overreach made while fixing
it. Stance is a `PlayerState` axis and should not depend on which camera the
player is using — the original gate was checking the wrong thing.

**Punch fires on `mouse_left_button` in COMBAT, in both view modes.**
`player.gd`'s punch handler drops its `view_mode != TPS` check — the same
`Stance.COMBAT` check now applies regardless of view.
*Удар теперь срабатывает в COMBAT в обоих видах, не только в TPS.*
- `player/player.gd`

**Face the punch target by click point in ISOMETRIC.** TPS's body already
faces the camera every frame, so the punch lands where the player is
looking; ISOMETRIC has no equivalent, so a punch would otherwise fire in
whatever direction the character happened to be standing. Turns the body
toward the clicked ground point before starting the punch (instant, not
smoothed — `punch_hit_delay` already buffers the swing before the hit check
reads facing). The ground point comes from a new
`ClickToMoveSystem.raycast_ground_point()`, factored out of the existing
move-order raycast, rather than a second raycast from the camera —
`ClickToMoveSystem` hands `player.gd` a reference to itself in
`register_player()`, since the player scene isn't part of `world.gd`'s
`on_world_ready()` sweep.
*Разворот к точке клика перед ударом в изометрии — иначе удар летел туда,
куда персонаж случайно стоял.*
- `core/movement/click_to_move_system.gd`, `player/player.gd`

**Revert: `ClickToMoveSystem` gating off for all of `Stance.COMBAT`.** The
initial fix, worried about `mouse_left_button` contention between the punch
and click-to-move's stop/cancel handler, self-gated the whole system off for
`Stance.COMBAT` — but `mouse_left_button` and `mouse_right_button` are
different buttons, so there was never a conflict to guard against. The
actual effect was disabling `mouse_right_button` move-to-point too, leaving
the player unable to move at all while COMBAT was raised — worse than the
original defect. `ClickToMoveSystem` gates on `mode` + `view_mode` only
again; the `stance_changed` subscription and its handler (which existed only
to stop an in-progress path on entering `COMBAT`) are gone with it.
`raycast_ground_point()`/`_cast_ground_ray()` and the `player.gd` injection
via `register_player()` were correct additions and stay.
*Откат: гейтинг ClickToMoveSystem по стойке отключал и движение — конфликта
кнопок не было, ЛКМ и ПКМ разные.*
- `core/movement/click_to_move_system.gd`

**Punch requires standing still.** A punch played over locomotion has
nothing to blend with — this project has no layered upper-body animation
mixing, so `AnimationNodeOneShot` replaces locomotion outright while the
punch plays, reading as sliding on a moving body. New `punch_max_speed`
export (0.5), checked against `player.gd`'s actual `speed`, not movement
input intent, in both view modes. A click while moving is silently ignored
— no feedback system exists in this project to explain the miss.
*Удар теперь только с места — на ходу нечем показать удар, анимация просто
наложилась бы на бег.*
- `player/player.gd`

---

## 2026-08-06 — First full incident chain: player hits, NPC falls, city records, drone responds

Nine commits closing the loop the drone/NPC work left open: the drone reacted to a
raised stance, which meant the player could summon a patrol on an empty street by
posing. Now the drone reacts to a fixed fact — a punch that actually landed — and
stance goes back to being what it was designed as: a declared intent the city can
choose not to answer.

**`IncidentRegistry`** (`core/world/incident_registry/`), a new `WORLD_SYSTEM_SCRIPTS`
entry. What the city has on record — actors report, they do not remember, so a
reaction can outlive the block being unloaded around the actor that caused it. Two
calls: `report(perpetrator, kind, position)`, `has_recent_incident_by(perpetrator,
within_seconds)`. `Incident` is a `RefCounted`, not a `Dictionary` (warnings-as-errors).
Timestamps are real seconds (`Time.get_ticks_msec()`), not `GameClockSystem`'s
game-hours — see that file's own header for why the two don't compose safely. First
slice of the roadmap's `WitnessSystem`: `Kind` has one value (`ASSAULT`) because
nothing produces a second yet.
*IncidentRegistry — реестр зафиксированных фактов, а не памяти конкретного актора:
это то, что позволяет реакции пережить выгрузку квартала.*
- `core/world/incident_registry/incident.gd`, `core/world/incident_registry/incident_registry.gd`, `world/world.gd`

**Player punch, `COMBAT`-only, on `mouse_left_button`.** That button was free in TPS —
`ClickToMoveSystem` has always self-gated to `ON_FOOT` + `ISOMETRIC`. Animation is
`new4/punch1` (ShooterLib), not MeleeLib — MeleeLib turned out to have no unarmed
punch clip at all (it's a sword/shield kit). Layered over whichever stance branch is
mixed in via `AnimationNodeOneShot` (no upper-body-only blending exists yet), for the
same span `set_movement_enabled(false)` already locks movement. Hit detection is a
cone check against `ActorBase.GROUP_PERCEIVED_ACTOR` filtered to `NPCBase` — not a
reused `PlayerFocusCast`, which is scoped to the Interactables physics layer for
`InteractComponent`'s own purpose. A landed punch calls `take_hit()` on the target and
emits `punch_landed`, which `IncidentRegistry` listens for via its own
`on_world_ready()` — `player.gd` never learns the registry exists.
*Удар игрока в стойке COMBAT — ЛКМ была свободна в TPS. Анимация оказалась не там, где
предполагалось (ShooterLib, не MeleeLib).*
- `player/player.gd`, `player/player_components/animation_component/player_animation_component.gd`

**NPC knockdown/getup, `take_hit()` on `NPCBase`, not `ActorBase`.** Knocks the body
down, plays `new4/knockdown`, then after `knockdown_duration` (export, 1s) plays
`new4/ko-getup` and waits for that clip to actually finish (polled — no animation-event
system exists to hook "clip finished" to) before returning control.
`idle_npc_controller.gd` stops deciding outright while its NPC is down. `DroneBase` has
no equivalent — no animation component for a fall/getup clip, and a flying body
knocked from the sky is a separate, unbuilt feature — so a punch that reaches a drone
just doesn't connect.
*NPC падает и встаёт по take_hit() — контракт добавлен на NPCBase, не на ActorBase:
у дрона нет анимации для этого и падение с неба — отдельная нерешённая задача.*
- `npc/npc_base.gd`, `npc/npc_components/animation_component/npc_animation_component.gd`, `npc/controllers/idle_npc_controller.gd`

**`PatrolDroneController`'s ALERT: incident, not stance.** Subscribes to
`IncidentRegistry.incident_reported`, goes ALERT when the incident falls within
`alert_incident_radius` of the drone's current position. `alert_memory_time` still
holds the state afterward, same as before, just driven by the last provoking report.
The drone is a static test instance placed directly in `world.tscn` and never receives
a `WorldContext`, so it resolves the registry via a group lookup
(`IncidentRegistry.GROUP_INCIDENT_REGISTRY`) — the same pattern `PerceptionComponent`
already uses to find the player. Documents, without building, the next rung: a drawn
weapon in `COMBAT` as a weaker trigger, once the player has something to hold.
*ALERT дрона теперь по зафиксированному инциденту, а не по стойке — стойка осталась
поводом присмотреться (idle_npc_controller.gd), но не поводом вызвать патруль.*
- `world/police_drone/controllers/patrol_drone_controller.gd`, `core/world/incident_registry/incident_registry.gd`

**Drone light reaction: `SpotLight3D` addressed at the player, plus a blinking light
bar.** The old `StatusLight` (a single `OmniLight3D` lerping color) was a sphere,
addressed to no one, and barely legible in the greybox. `Spotlight` (child of
`DroneMesh`) switches on only while ALERT and the player is actually seen, and tracks
automatically — it's a plain child at `DroneMesh`'s identity transform, so it rides
along with the mesh's own existing `looking_at()` turn, no second aim mechanism.
`StatusLight` itself is replaced by `LightBarBlue`/`LightBarRed`, two small
`OmniLight3D`s blinking in antiphase off one shared timer (not two, which could drift
into both being on, or off, at once) — the ambient "a drone nearby is in ALERT" signal
`StatusLight` used to carry.
*Прожектор — адресный сигнал (дрон смотрит именно на игрока); мигалка (синий/красный
OmniLight3D в противофазе) — амбиентный сигнал, что дрон вообще в ALERT.*
- `world/police_drone/PoliceDrone.tscn`, `world/police_drone/controllers/patrol_drone_controller.gd`

**Perception debug panel: incidents, knockdown, drone alert reason.** Reports the last
`IncidentRegistry` entry (type, age), each `NPCBase`'s knocked-down state, and per
drone, that ALERT is held by incident memory plus whether the spotlight is lit.
Resolves `IncidentRegistry` via `on_world_ready()` — this panel is a `WORLD_UI_SCENES`
entry and gets one, unlike the drone controller.
*Панель отладки восприятия: последний инцидент, состояние падения NPC, причина ALERT
у дрона.*
- `ui/debug/perception_debug_panel.gd`

---

## 2026-08-04 — Police drone moved onto the NPC/AI architecture; NPCs get the player's rig

`world/police_drone/police_drone.gd` was a working concept written before `npc/`'s
NPCBase/NPCControllerBase/PerceptionComponent split existed — a `RigidBody3D` fighting
its own physics engine, an `Area3D` proximity trigger duplicating `PerceptionComponent`,
and a dead `is_in_group("Player")` check (capitalized group, removed from the project).
Rebuilt onto the same architecture NPCs already use, plus NPCs themselves finally got a
real mesh, skeleton and animation instead of a capsule and a cube head. Ten commits;
grouped here by theme, not by commit.

**`ActorBase` (`core/characters/actor_base.gd`), extracted first.**
`NPCControllerBase`/`PerceptionComponent` both hard-checked `parent is NPCBase`, which
would have blocked the drone from reusing either — a non-humanoid flying body is not an
`NPCBase`. Extracted the slice both actually need (`set_move_intent()`,
`set_look_target()`/`clear_look_target()`, `get_eye_height()`, `get_facing_direction()`,
every method a stub) into `ActorBase extends CharacterBody3D`; `NPCBase` now extends it
instead of `CharacterBody3D` directly. Added a `perceived_actor` group for debug-tooling
enumeration, deliberately separate from `NPCBase`'s own `lockable` (the TPS combat
camera's lock-on pool, `tps_combat_camera_state.gd`) — a drone is not a lock-on target,
and widening `lockable` would have made it one by accident.
*ActorBase — общий контракт для NPCControllerBase/PerceptionComponent, чтобы дрон мог
их переиспользовать без ручной проверки типа. Группа perceived_actor отдельно от
lockable (цели захвата боевой камеры) — дрон не должен становиться целью захвата.*
- `core/characters/actor_base.gd`, `npc/npc_base.gd`, `npc/controllers/npc_controller_base.gd`, `npc/controllers/idle_npc_controller.gd`, `npc/npc_components/perception_component/perception_component.gd`

**`DroneBase`, `CharacterBody3D` pseudo-physics instead of a fought `RigidBody3D`.**
Ground-following altitude hold via `HeightRayCast` (re-sampled every frame, unlike
`HoverBase`'s fixed held-Y — this drone patrols over uneven terrain) and horizontal
inertia both reuse `HoverBase`'s approach: one `Smoothing.damp_factor()` rate chosen by
whether there's movement intent this frame, not a per-frame current/target speed
comparison (see `hover_base.gd`'s own note on the bang-bang jitter that comparison
produces at top speed). The body's own `rotation.y` never turns — only `DroneMesh`
does, toward `set_look_target()`, same `Transform3D.interpolate_with()` technique the
old script used — so `get_facing_direction()` is overridden rather than inherited from
`ActorBase`'s atan2-on-rotation.y default.
*DroneBase на CharacterBody3D: удержание высоты рейкастом и горизонтальная инерция
переиспользуют подход HoverBase. Корпус не поворачивается, только меш — через
set_look_target().*
- `world/police_drone/drone_base.gd`

**`PatrolDroneController` (extends `NPCControllerBase`) — PATROL/ALERT, not PATROL/CHASE.**
Patrol logic (random point in a local square rotated to start yaw, same square the old
script used) ported as-is. ALERT triggers on a visible player in
`PlayerState.Stance.COMBAT` — the same declared-intent read `idle_npc_controller.gd`
already used to skip its own glance/turn gate — replacing the old `Area3D`
"anyone who walked in" trigger. `alert_memory_time` (3s default) holds ALERT for a few
seconds after the player leaves COMBAT or sight. In ALERT the drone closes to
`alert_hover_distance` and holds — observation, not pursuit; vertical separation isn't
computed separately, `DroneBase`'s own ground-following hold already puts it
`hover_height` above whatever ground the player is standing on. A `StatusLight`
(`OmniLight3D`) eases red in ALERT via `Smoothing.damp_factor()`, not an instant switch.
`PerceptionComponent` itself needed no changes — the drone's instance just sets a wider
`vision_range`/`vision_angle_deg` than the pedestrian NPC default.
*PatrolDroneController: ALERT реагирует на боевую стойку игрока (не на присутствие),
с задержкой памяти 3с. В ALERT дрон держит дистанцию и высоту, а не таранит игрока.
Статус-light плавно краснеет.*
- `world/police_drone/controllers/patrol_drone_controller.gd`, `world/police_drone/PoliceDrone.tscn`

`police_drone.gd` deleted — fully migrated. `PoliceDrone.tscn`'s root is now
`CharacterBody3D` running `drone_base.gd`; `DetectionZone` (`Area3D`) and its signal
connections are gone along with the 100m `SphereShape3D` only it referenced.

**NPCs get the player's mesh, skeleton and animation.** `player.tscn` bakes its mesh and
skeleton (`player_base_mesh` → `GeneralSkeleton` → `RetargetModifier3D` →
`OriginalSkeleton`, five `MeshInstance3D`s) as inline sub-resources, not an instanceable
`PackedScene` — reuse from `npc.tscn` meant a literal copy (every `ArrayMesh`/`Skin`
sub-resource transitively, cross-checked against dangling/orphaned references), not a
shared file; `player.tscn` itself is untouched. Grey dummy, not reskinned: each
`MeshInstance3D`'s texture-heavy `material_override` (and the ~18 texture
`ExtResource`s behind it) was dropped in favour of the flat, textureless material
already baked into each mesh's own surface data. `BoneAttachment3D`/
`ModifierBoneTarget3D` (weapon-hand IK, a head attachment point) were left out — player-
only plumbing with no NPC consumer. `NPCAnimationComponent` (new,
`npc_components/animation_component/`) drives a single `AnimationNodeBlendSpace1D`
(idle to walk, no run tier — NPCs have no speed tier past `walk_speed`) from
`NPCBase.get_move_speed_ratio()` (new getter), plus a `LookAtModifier3D` head look —
the same technique `player_animation_component.gd` uses, called explicitly from
`npc_base.gd._physics_process()`. Replaces `NPCBase`'s old hand-rotated `Head` node
entirely; `set_look_target()`/`clear_look_target()` are unchanged as the public
contract, only the implementation moved (two new getters,
`has_look_target()`/`get_look_target_point()`, let the component read that state
without reaching across the node boundary).
*NPC получили копию меша/скелета/AnimationPlayer игрока (без текстур — серая болванка),
т.к. они вшиты в player.tscn как суб-ресурсы, а не отдельная сцена. Анимация —
BlendSpace1D idle/walk + LookAtModifier3D для поворота головы вместо ручного
поворота узла Head.*
- `npc/npc.tscn`, `npc/npc_base.gd`, `npc/npc_components/animation_component/npc_animation_component.gd`

**Idle NPCs wander instead of standing still.** `IdleNPCController` now picks a random
point within `wander_radius` of where it started (a disk, not the drone's rotated
square — nothing here needs an orientation to preserve), walks to it at
`wander_speed_ratio`, pauses `wander_pause_time`, picks another. No navigation: a
`RayCast3D` created in code (parented to the NPC body, not a scene edit) retargets
immediately on an obstacle, the same immediate-retarget response the drone's patrol
uses on arrival — no pause, that's reserved for reaching an actual destination. The
existing gaze/body-turn logic is unchanged in substance, just no longer gated behind a
permanently-zero move intent: seeing the player now freezes movement outright instead
of it always having been zero.
*IdleNPCController теперь бродит: случайная точка в радиусе, пауза между переходами,
рейкаст вперёд вместо навигации. При виде игрока движение останавливается.*
- `npc/controllers/idle_npc_controller.gd`

**Perception debug panel lists drones alongside NPCs.** One shared list
(`ActorBase.GROUP_PERCEIVED_ACTOR`), each row tagged by `get_debug_type_label()`
("NPC"/"Drone") rather than a second panel — they share the same perception. Added: a
`PlayerState.stance` header line (the reason anything reacts now), and a per-
controller-type state line (`IdleNPCController`'s existing visible-time/facing-target/
body-angle description, or `PatrolDroneController`'s PATROL/ALERT state plus seconds
left before ALERT lapses from memory).
*Дебаг-панель восприятия: дроны и NPC в одном списке с пометкой типа, стойка игрока в
заголовке, состояние контроллера и обратный отсчёт ALERT для дрона.*
- `ui/debug/perception_debug_panel.gd`

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

**Aim-down-sights, as a COMBAT modifier, not a third stance.** `PlayerState.is_aiming`
deepens a commitment already declared by COMBAT rather than declaring a new one —
`set_aiming()` silently clamps to `false` outside `Stance.COMBAT`/`Mode.ON_FOOT` (a
held aim button crossing a stance change mid-press is ordinary input, not a caller
mistake), mirroring `set_stance()`'s own never-assign-directly rule.
`InputSystems.is_aim_pressed()` reads `mouse_right_button` as a raw held query, not a
signal — the same reasoning `is_sprint_held()` uses, the caller decides what the hold
means. `player.gd`'s `aim_speed_multiplier` stacks on top of the COMBAT speed
multiplier inside `get_speed_multiplier()`, so every `target_speed` computation
already reads the aim slowdown from one place. `on_foot_camera_component.gd` dollies
TPS distance to `TPS_AIM_DISTANCE` (closer than `TPS_DISTANCE`, framing the shot) and
widens the shoulder offset by `aim_shoulder_offset_multiplier` — AIM wins the distance
priority even over an active lock-on. `AimReticle` (`ui/hud/aim_reticle/`) is a
debug-grade screen-centre cross visible only while `PlayerState.is_aiming`, confirming
ADS reads on screen — not the final aiming interface.
*ADS как модификатор COMBAT, а не третья стойка — is_aiming усиливает уже объявленное
намерение. Скорость замедляется множителем поверх COMBAT, камера приближается и
смещает плечо, крестик-заглушка подтверждает состояние на экране.*
- `core/player_state/player_state.gd`, `core/input/input_systems.gd`
- `player/player.gd`
- `camera/camera_component/on_foot_camera_component.gd`
- `ui/hud/aim_reticle/`

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
