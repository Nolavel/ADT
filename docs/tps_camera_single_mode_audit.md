Same HEAD as before — good, snapshot is stable. Now let's gather project configuration.Main scene = `world/world.tscn`. Now let's find all camera-related files comprehensively.Confirmed: reticle is purely visual (screen-center cross), no raycast, no weapon direction logic. Now the weapon component:Now let's check `CLAUDE.md` for the documented verification ladder and any stated camera contract, plus scan git log stats specifically for camera-related files count.Теперь у меня достаточно материала для полного отчёта. Формирую итоговый документ.Достаточно. Пишу итоговый отчёт.

---

# ADT — Single TPS Camera Migration Audit

## Краткий вывод

**Факты:** Две отдельные, ортогональные по объектной модели, но частично переплетённые по данным camera-системы (`OnFootCameraComponent` как единый хост-диспетчер, `IsometricCameraState` и TPS-подсистемы как разные ветки внутри него). Владение `Camera3D.global_position/global_rotation` — единолично у `OnFootCameraComponent._update_camera_position()`, дублирования нет. `PlayerState.view_mode` — единственный переключатель между режимами, потребители найдены и перечислены. Aim-пайплайн НЕ является screen-center-raycast системой — это angle-cone поиск от `rotation.y` (общий с punch). Vehicle-камеры (`Hover`, `TubeTransit`) полностью независимы от ISO/TPS. `NavigationComponent` — общая инфраструктура (используется и ISO-кликом, и TPS-scripted-подходом), `ClickToMoveSystem` (input-обработчик клика) — ISO-only.

**Проблема:** Перед удалением ISO нужно (а) явно определить судьбу 6 живых зависимостей от `view_mode` вне camera/-папки (animation head-look, zoom ruler UI, debug overlay, InputSystems mouse-mode, key hints, click-to-move gating), (б) не потерять уже задокументированный в CHANGELOG факт, что TPS-occlusion (raycast) — заведомо худший, более ранний подход, чем ISO-occlusion (spherecast), принятый проектом сознательно позже.

**Проверенные файлы:** ~45 файлов прочитаны полностью или прицельно (см. §2–§17 ниже), плюс `project.godot`, 2 `.tscn`, `.github/workflows/godot.yml`, `CLAUDE.md`, `docs/scope_horizon.md`, `CHANGELOG.md`, git log/show.

**Архитектурное решение:** Не предлагается на этом этапе — только Target Architecture как гипотеза (§25) и Migration Plan как проект (§26), оба требуют отдельного согласования.

**Изменения:** NONE — audit only.

**Проверка:** Существующий CI (`godot --headless --editor` x2 + `godot --headless` boot + `render_probe.sh`) — реальный, работающий инструмент верификации, найден в `.github/workflows/godot.yml`, задокументирован в `CLAUDE.md`. Использовать как базовую линию до/после миграции.

**Риски/вопросы:** См. §20 и §29.

---

## 1. Repository snapshot

```
HEAD:            0d6f6160cdbc8e221289a9aef7b9d5b599472694 — "tps_camera_first"
HEAD date:       2026-08-30 23:03:19 +0800
Branch:          main
Working tree:    clean, up to date with origin/main
Remote:          https://github.com/Nolavel/ADT.git
Godot (pinned):  4.7.2  [CONFIRMED — .claude/hooks/ensure_godot.sh, VERSION="4.7.2"]
Godot (project.godot): config/features=["4.7"] — feature-compat tag, не точный патч [CONFIRMED]
Main scene:      world/world.tscn  (resolved from run/main_scene UID bftcnbrfar8om)  [CONFIRMED]
Autoloads:       StreamingSystems, WorldSystems, InputSystems, PlayerState, _mcp_game_helper (editor MCP tool)  [CONFIRMED — project.godot [autoload]]
Editor plugins:  addons/godot_ai (MCP dev tool), addons/item_fitter (EditorPlugin dock)  [CONFIRMED — не связаны с ISO/TPS]
Camera-related InputMap: 36 actions всего (input_map.md), из которых прямо к камере относятся:
    toggle_view (V), zoom_in/zoom_out (Wheel), lean_left/lean_right (Q/E),
    switch_shoulder (Z), lock_on (G), toggle_follow (P, задокументирован как unread)
    [CONFIRMED — project.godot [input] содержит все перечисленные ключи буквально]
Test/check commands: 
    godot --headless --editor --quit-after 2000   (import, x2 — первый прогон "врёт")
    godot --headless --quit-after 400              (boot world.tscn, физика/автозагрузки живые)
    sh tools/render_probe/render_probe.sh 120 <out> (софтверный рендер, единственная проверка "рисуется ли")
    [CONFIRMED — .github/workflows/godot.yml, воспроизведено дословно из CLAUDE.md]
export_presets.cfg: НЕ НАЙДЕН в репозитории  [CONFIRMED отсутствие — вероятно .gitignore'ится либо экспорт не настроен в VCS] → build/export конфигурация [UNKNOWN — requires verification вне репозитория]
```

Замечание [CONFIRMED]: HEAD-коммит `tps_camera_first` по `git show --stat` реально меняет только `core/player_state/player_state.gd` (4 строки) и `data/items/carbine.tres` (9 строк) — TPS-камера-код в этом коммите не менялся. Название коммита не отражает его diff.

---

## 2. Current camera architecture

```
Camera architecture
├── camera/camera_follow.gd                              — host Camera3D, dispatcher по PlayerState.mode
│   └── camera/camera_follow.tscn                          (сцена: Camera3D + debug Labels + IsoCameraDebug Control)
├── camera/camera_component/
│   ├── on_foot_camera_component.gd (2023 строки)         — единственный writer camera transform в ON_FOOT
│   ├── hover_camera_component.gd  (186)                  — независим от ISO/TPS [CONFIRMED — grep пуст]
│   ├── tube_transit_camera_component.gd (49)             — независим от ISO/TPS [CONFIRMED — grep пуст]
│   └── camera_shake_component.gd (131)                   — аддитивный поверх любого режима, независим
├── camera/isometric_camera_state.gd (1278)                — ISO-only состояние, инстанцируется внутри OnFootCameraComponent
├── camera/isometric_camera_debug_overlay.gd (129)         — ISO-only, узел в camera_follow.tscn (IsoCameraDebug)
├── camera/tps_shoulder_camera_state.gd (172)               — TPS-only, чистый offset generator
├── camera/tps_combat_camera_state.gd (322)                 — TPS-only, Explore/Locked/Transition
└── core/movement/tps_movement_system.gd (109)              — TPS-only, движение camera-relative
    core/movement/click_to_move_system.gd                   — ISO-only input handler (НЕ camera, но camera-mode-gated)
    core/ui/zoom_ruler_system.gd + vfx/hud_component/zoom_ruler/zoom_ruler_hud.gd — UI, охватывает ОБА режима одним слайдером
```

### Таблица по файлам

| Path | Class | Owner | State | Inputs | Outputs | Readers | Writers | Dependencies | Survives without ISO? | Survives without TPS? |
|---|---|---|---|---|---|---|---|---|---|---|
| `camera_follow.gd` | `CameraFollow extends Camera3D` | себя (Camera3D transform) | `CameraState.GAME/MENU_PAUSE` | `PlayerState.mode_changed` | `global_transform`, вызывает `_active_component.update()` | — | сам себе | `OnFootCameraComponent`, `HoverCameraComponent`, `TubeTransitCameraComponent`, `CameraShakeComponent` | ДА, после удаления `IsoCameraDebug`-узла и `iso_debug_enabled` export'а | ДА, если вместо `OnFootCameraComponent` подставить чисто-TPS хост (гипотетически) |
| `on_foot_camera_component.gd` | `OnFootCameraComponent extends Node` | `camera_target/current_yaw/pitch`, `camera_target_pos/current_pos` | нет отдельного enum-состояния файла — делегирует `PlayerState.view_mode` | mouse (`InputSystems.get_look_delta`), `PlayerState.is_aiming`, `_tps_combat`, `_shoulder`, `_iso` | `camera.global_position/rotation`, `camera.h_offset` | — | сам единолично | `TpsShoulderCameraState`, `TpsCombatCameraState`, `IsometricCameraState`, `InputSystems`, `PlayerState` | НЕТ без правок — `update()`, `_update_camera_position()`, `_transition_to_view()` содержат ISO-ветки, требующие удаления/упрощения | ДА — TPS-ветка самодостаточна |
| `isometric_camera_state.gd` | `IsometricCameraState extends RefCounted` | `current_angle` (свой), follow point, occlusion distance | внутренний | `Frame` (собран хостом) | follow point, yaw, occlusion distance | `on_foot_camera_component.gd` (единственный) | сам | нет внешних | Не применимо — сам есть ISO | ДА тривиально — не используется TPS-веткой вообще |
| `tps_shoulder_camera_state.gd` | `TpsShoulderCameraState extends RefCounted` | `state` (LEFT/RIGHT/TRANSITION), offset | внутренний enum | `toggle()/set_left()/set_right()` | `float` offset | `on_foot_camera_component.gd` | сам | нет | ДА — не знает про ISO вообще [CONFIRMED — grep по файлу] | НЕТ — существует только для TPS |
| `tps_combat_camera_state.gd` | `TpsCombatCameraState extends RefCounted` | `state`, `locked_target` | `EXPLORE/LOCKED/TRANSITION` | `try_toggle_lock()`, `player`, `current_yaw` | `Dictionary{yaw, pitch_offset_deg, distance_override}` | `on_foot_camera_component.gd` | сам | `PlayerState.stance_changed`, duck-typed `get_facing_direction()` на игроке/NPC | ДА — не знает про ISO | НЕТ — TPS-only по построению |
| `tps_movement_system.gd` | `TPSMovementSystem extends Node` | нет своего состояния — читает camera basis каждый тик | активен только `mode==ON_FOOT && view_mode==TPS` | `InputSystems.get_move_axis/is_sprint_held/is_aim_pressed`, `camera.global_transform.basis` | `player.set_direct_move_input()`, `player.set_camera_yaw()`, `PlayerState.set_aiming()` | — | сам | `camera` (ссылка), `player_node` (ссылка) | ДА — self-gating на `view_mode==TPS` уже исключает ISO-контекст | НЕТ — TPS-only по построению |
| `click_to_move_system.gd` | `ClickToMoveSystem extends Node` | нет своего yaw/pos состояния | активен только `mode==ON_FOOT && view_mode==ISOMETRIC` [CONFIRMED] | `InputSystems.primary_click_pressed/secondary_click_pressed/held` | `player.move_to_position()` → `NavigationComponent.set_target_position()` | — | сам | `player.set_click_to_move_system()` | Не применимо — сам ISO-only | ДА — при удалении ISO вся нода становится dead, НО лежащий под ней `NavigationComponent`/`_handle_navigation` **используется и TPS** через `InteractComponent` [CONFIRMED — `interact_component.gd:483 player.move_to_position(stop_point)`] |
| `zoom_ruler_system.gd` + `zoom_ruler_hud.gd` | системный узел + `Control` | нет | нет | `on_foot.get_current_zoom_range()` | UI-слайдер | — | UI-виджет | `OnFootCameraComponent.get_current_zoom_range()` | НЕТ — весь смысл виджета "континуум ISO↔TPS через V" [CONFIRMED — комментарий в `zoom_ruler_hud.gd:5` буквально описывает переход через V] | НЕТ — TPS вообще не зумируется (`_start_zoom` возвращает рано для TPS, "zoom disabled in TPS — distance is fixed", подтверждено в предыдущем аудите) |
| `isometric_camera_debug_overlay.gd` | `Control` | нет | нет | `IsometricCameraState`/`Frame` | рисует dead-zone прямоугольники | — | себя | Узел `IsoCameraDebug` в `camera_follow.tscn`, гейтится `iso_debug_enabled && view_mode==ISOMETRIC` в `camera_follow.gd::_update_iso_debug_visibility()` | Не применимо — сам ISO-only | ДА — TPS никогда его не видит |

---

## 3. Dependency graph

```
InputSystems (autoload, ЕДИНСТВЕННЫЙ физический читатель Input.*)
    │
    ├── _frame_look_delta ──────────────────────────────────┐
    │                                                        │
    ▼                                                        ▼
PlayerState (autoload, source of truth mode/view_mode/stance/is_aiming)
    │
    ├── view_mode ──► ClickToMoveSystem (self-gate: ISO)      [ISO-only input path]
    ├── view_mode ──► TPSMovementSystem (self-gate: TPS)      [TPS-only input path]
    ├── view_mode ──► OnFootCameraComponent.update() (branch) [ОБА пути внутри одного файла]
    ├── view_mode ──► PlayerAnimationComponent.update_head_look() (branch) [ОБА пути]
    ├── view_mode ──► InputSystems._apply_mouse_mode() (курсор capture only in TPS)
    └── view_mode ──► camera_follow._update_iso_debug_visibility() [ISO-only]

TPSMovementSystem ──(camera.global_transform.basis, 1-тик задержка, см. §13)──► player.set_direct_move_input()
                  ──(camera.global_rotation.y)───────────────────────────────► player.set_camera_yaw() → _camera_yaw

player.gd
    │
    ├── _apply_direct_movement() ──► rotation.y = lerp(rotation.y, _camera_yaw+PI, ...)   [ЕДИНСТВЕННЫЙ writer rotation.y в TPS]
    ├── get_facing_direction() ──► _find_punch_target()/_resolve_shot() [aim = angle-cone от rotation.y, НЕ raycast от камеры]
    ├── get_movement_vector_relative_to_facing() ──► PlayerAnimationComponent (blend space) [camera-независимо]
    └── move_to_position() ──► NavigationComponent.set_target_position() [ОБЩИЙ путь: ISO click ИЛИ TPS InteractComponent]

OnFootCameraComponent
    ├── TPS-ветка: mouse → camera_target_yaw → (TpsCombatCameraState при LOCKED) → camera_current_yaw → camera.global_rotation
    ├── ISO-ветка: IsometricCameraState.update_orientation() → current_angle → camera_target_yaw (только в ISO)
    ├── _update_iso_head_look() ──► player.set_head_look_point() ──► PlayerAnimationComponent._look_point  [ISO-only цепочка, 3 файла]
    └── get_on_foot_component() ──► ZoomRulerSystem, stream_debug_panel.gd  [читатели снаружи camera/]

NPC / World / Vehicle — [CONFIRMED, grep по всем NPC/drone/perception-файлам]:
    НЕ содержат ни одного обращения к PlayerState.view_mode, PlayerState.mode или camera.*.
    Единственная связь — PlayerState.stance (COMBAT/PEACE), которая view_mode-независима.
```

**ISO-only nodes:** `IsometricCameraState`, `isometric_camera_debug_overlay.gd` (+ scene node `IsoCameraDebug`), `ClickToMoveSystem` (input-часть; `NavigationComponent` под ним — общий).

**TPS-only nodes:** `TpsShoulderCameraState`, `TpsCombatCameraState`, `TPSMovementSystem`.

**Shared nodes:** `OnFootCameraComponent` (хост-диспетчер, оба branch внутри одного файла), `PlayerState` (все 4 поля читаются камерой и не-камерой), `InputSystems`, `NavigationComponent`, `player.gd` (единый источник facing независимо от режима), `PlayerAnimationComponent` (частично — см. hidden dependency ниже), `zoom_ruler` UI (буквально построен НА границе ISO/TPS, требует переосмысления, не механического удаления).

**Hidden dependencies (не видны по имени файла):**
1. `PlayerAnimationComponent.update_head_look()` — `match PlayerState.view_mode` внутри анимационного компонента, который по названию не выглядит camera-related. [CONFIRMED]
2. `InputSystems._apply_mouse_mode()` — курсор скрывается/захватывается в зависимости от `view_mode` (не проверено дословно в этом сеансе, но задокументировано в `input_map.md`: "InputSystems captures the cursor only in TPS ... because ISOMETRIC needs a visible cursor for click-to-move"). [CONFIRMED — цитата из input_map.md, строки 128-133]
3. `zoom_ruler_hud.gd` — UI-виджет, чья семантика ЦЕЛИКОМ построена на переходе через V между двумя зумовыми диапазонами. [CONFIRMED]
4. `KeyHintsPanel`/`key_hints.tres` — читает `view_mode` для показа релевантных подсказок (établи в предыдущем аудите как `entry.view_modes` массив; не пере-верифицировано построчно в этом сеансе — [INFERENCE] на основе `docs/architecture/player_and_camera.md` описания системы).

**Dangerous dependency (не hidden, но легко пропустить):** `player.move_to_position()`/`NavigationComponent` — выглядит как "явно ISO", но реально общий с TPS через `InteractComponent`. Удаление `ClickToMoveSystem` без сохранения `NavigationComponent` сломает TPS-подход к предметам.

---

## 4. Camera state ownership

| State | Owner | Writer(s) | Reader(s) | Init | Reset | Transition | Persistence |
|---|---|---|---|---|---|---|---|
| `camera.global_position/global_rotation` | `OnFootCameraComponent` | ровно 1 — конец `_update_camera_position()` [CONFIRMED, см. предыдущий аудит §4] | движок (рендер), `CameraShakeComponent` (аддитивно поверх) | `setup()` | нет явного reset, только `enter()`/`exit()` при смене `PlayerState.mode` | `_transition_to_view()` | не персистится |
| `camera_target_yaw` | `OnFootCameraComponent` | 3: mouse (TPS, безусловно), `TpsCombatCameraState.LOCKED` (условно), `current_angle` (ISO, безусловно в ISO) — **TRANSITION CONTRACT REQUIRED, уже нарушен см. предыдущий CONFLICT-1** | `_update_camera_position` | `setup()` | нет | неявный, через порядок веток `if view==TPS / else` | нет |
| `camera_current_yaw` | `OnFootCameraComponent` | 1 (lerp) | `camera.global_rotation` | `setup()` | нет | нет | нет |
| `player.rotation.y` | `player.gd` | 1 в TPS (`_face_camera`), 3 всего в файле включая punch (`_face_punch_target`, `_face_punch_intent`) и navigation (`_handle_navigation`) — гейтятся взаимоисключающе через `movement_enabled`/`view_mode`, но НЕ верифицировано построчно на 100% (см. §10) | `get_facing_direction()`, punch/shot target search, NPC perception (дуплицирующий `get_facing_direction` контракт) | нет явного | нет | нет | нет |
| `player._camera_yaw` | `player.gd` | 1 — `TPSMovementSystem` каждый TPS-тик | `_face_camera`, `PlayerAnimationComponent.update_head_look()` (TPS-ветка) | `= 0.0` | нет | **задокументированное известное ограничение**: "in ISOMETRIC it holds whatever TPS left behind" (`docs/architecture/player_and_camera.md`) [CONFIRMED цитата] | нет |
| Shoulder state | `TpsShoulderCameraState` | 1 (`toggle`) | offset consumer в `_update_camera_position` | `RIGHT` | нет | внутренний `TRANSITION` enum | нет |
| Lock-on target | `TpsCombatCameraState` | `try_toggle_lock`/`_clear_lock`/`_on_stance_changed` | debug overlay, `_locked_result` | `null` | `_clear_lock()` | внутренний enum | нет |
| `PlayerState.view_mode` | `PlayerState` | 1 — `set_view_mode()` | ≥6 потребителей (см. §3 hidden deps) | `TPS` (default, `player_state.gd:16`) [CONFIRMED] | нет | сигнал `view_mode_changed` | нет |

**Вывод по FAIL/TRANSITION CONTRACT REQUIRED:** `camera_target_yaw` — единственное значение с реальным конфликтом (уже задокументированным в предыдущем аудите как CONFLICT-1: TRANSITION-ветка `TpsCombatCameraState` считает blended yaw, но он не применяется). Остальные состояния — один владелец, без гонки.

---

## 5. ISO-only systems

[CONFIRMED, если не помечено иначе]

- `camera/isometric_camera_state.gd` (целиком, 1278 строк)
- `camera/isometric_camera_debug_overlay.gd` + узел `IsoCameraDebug` в `camera_follow.tscn`
- `core/movement/click_to_move_system.gd` (input-обработка; НЕ путать с `NavigationComponent`, который общий)
- В `on_foot_camera_component.gd`: ISO-ветки внутри `update()`, `_update_camera_position()`, ISO-часть `_transition_to_view()`, `_handle_isometric_look_input()`, `_update_iso_head_look()`, `_build_iso_frame()`, `_cursor_edge_weight()`, `_apply_iso_wall_clamp()` и все `ISO_*`/`_iso_*` константы/поля (обширный список, ≈40% файла по объёму — не подсчитано точно, [INFERENCE] по пропорции найденных `_iso`-префиксных символов)
- `_handle_rotation_input()`, `_rotate_camera_left/right()`, `_handle_follow_toggle()`, `_handle_follow_rotation()` — **мёртвый код УЖЕ СЕЙЧАС**, ISO стала directional и они не вызываются (задокументировано в самом файле, строки 690-696 предыдущего аудита: "nothing reaches them")
- Экспорт-параметры: `orbit_distance`, `orbit_height`, `camera_angle`, `iso_look_yaw_limit_deg`, `iso_look_rate_deg`, `iso_look_return_rate`, `iso_head_look_limit_deg`, `iso_head_look_cursor_limit_deg`, весь `ISOMETRIC WALL SAFETY`/`SCREEN-EDGE FRAMING`/`LOOK-AHEAD` блок констант
- `player.gd::set_head_look_point()`/`clear_head_look_point()` + `PlayerAnimationComponent`'s `_look_point`/`_look_point_valid` + ISO-ветка `update_head_look()`'s `match` — **вся цепочка**, единственный писатель — `_update_iso_head_look()` [CONFIRMED — grep не нашёл других вызывающих]
- `zoom_ruler_system.gd` + `zoom_ruler_hud.gd` — формально не "ISO-only" по имени, но семантически неотделим от ISO↔TPS континуума (см. §3) — **классифицирую как ISO-coupled, не чисто ISO-only**

---

## 6. TPS systems

[CONFIRMED]

- `camera/tps_shoulder_camera_state.gd` (целиком)
- `camera/tps_combat_camera_state.gd` (целиком)
- `core/movement/tps_movement_system.gd` (целиком)
- В `on_foot_camera_component.gd`: `_handle_tps_follow()`, TPS-часть `_update_camera_position()`, `_select_tps_distance_source()`, `_decay_tps_state()`, `_handle_shoulder_toggle()`, TPS-часть `_transition_to_view()`, все `TPS_*`/`_tps_*` константы/поля
- `player.gd::_face_camera()`, `_apply_direct_movement()` (TPS-путь через `PlayerState.view_mode==TPS` в `_physics_process`)
- `PlayerAnimationComponent.update_head_look()`'s TPS-ветка

---

## 7. Shared systems

[CONFIRMED]

- `PlayerState` (все 4 поля)
- `InputSystems` (весь файл — единственный физический читатель `Input.*`, обслуживает оба режима)
- `player.gd` — facing/rotation.y владение НЕ разделено по режиму как отдельные функции (кроме `_face_camera` vs `_handle_navigation`, которые сами взаимоисключающе гейтятся `view_mode`) — **но** `get_facing_direction()`, punch/shot-логика, NPC perception-контракт полностью camera-mode-независимы
- `NavigationComponent`/`_handle_navigation`/`move_to_position()` — **важная находка**: изначально ISO-only, но CHANGELOG (строки 756-757) документирует дату, когда это стало общим ("Navigation is no longer ISOMETRIC-only... TPS now runs the [navigation]")
- `CameraFollow` (диспетчер по `PlayerState.mode`, не по `view_mode`) — общий для `ON_FOOT`/`HOVER`/`TUBE_TRANSIT`
- `HoverCameraComponent`, `TubeTransitCameraComponent`, `CameraShakeComponent` — вообще не знают о существовании ISO/TPS
- Вся NPC/AI/perception/drone-подсистема — camera-mode-независима (см. §15)
- `get_head_yaw_relative_deg()` в `PlayerAnimationComponent` — по коду общая утилита, хотя реально осмысленное значение получает только в TPS-idle и ISO ветках `update_head_look()`

---

## 8. Hidden dependencies

Уже перечислены в §3 отдельным блоком. Дублирую здесь кратко со ссылкой на evidence:

1. `PlayerAnimationComponent.update_head_look()` — `match PlayerState.view_mode`, строка 295 файла. [CONFIRMED]
2. `InputSystems` mouse-capture режим зависит от `view_mode` (курсор виден в ISO для клика, скрыт в TPS). [CONFIRMED — цитата input_map.md]
3. `zoom_ruler_hud.gd` — весь UI построен на континууме, теряет смысл без ISO. [CONFIRMED]
4. `KeyHintsPanel` — предположительно фильтрует подсказки по `view_mode` через `KeyHintEntry.view_modes`. [INFERENCE — не перепрочитано построчно в этом сеансе, ссылка на предыдущий аудит документации]
5. `docs/scope_horizon.md` / `CHANGELOG.md` — не код, но фиксируют, что ISO-камера **официально помечена "Out of plan"** и **"Not finished — collision response and a refactoring pass remain"** по состоянию на 2026-08-27. [CONFIRMED — прямая цитата]

---

## 9. Player dependencies

[CONFIRMED, если не помечено]

`player.gd` зависит от camera/view_mode в следующих точках:
- `_physics_process()`: `if PlayerState.view_mode == PlayerState.ViewMode.TPS: ... else: _handle_navigation()` — единственная развилка верхнего уровня
- `_camera_yaw` (пишется только `TPSMovementSystem`, читается `_face_camera` и `PlayerAnimationComponent`)
- `set_head_look_point()`/`clear_head_look_point()` — ISO-only, см. §5
- `get_facing_direction()`, `get_movement_vector_relative_to_facing()`, `get_horizontal_direction()` — camera-mode-независимые геттеры, используются и TPS (движение), и animation, и combat/punch/shot

**Не зависят от camera/view_mode:** `_apply_gravity`, `_handle_jump`, весь punch/shot/reload pipeline (кроме факта, что `_face_camera` в TPS держит `rotation.y` синхронизированным с камерой — но сам punch/shot код читает только `rotation.y`, не `view_mode` и не камеру напрямую).

---

## 10. Movement dependencies

Цепочка (TPS, подтверждено кодом):

```
Input (WASD)
    ↓ InputSystems.get_move_axis()
TPSMovementSystem._physics_process()
    ↓ camera.global_transform.basis  ← ЕДИНСТВЕННОЕ место, где движение читает камеру напрямую
    ↓ (forward = -cam_basis.z, right = cam_basis.x, оба flattened по Y)
direction (camera-relative, Y-flattened)
    ↓ player.set_direct_move_input(direction, want_run)
player.gd._apply_direct_movement()
    ↓ velocity = direction * speed
    ↓ rotation.y = lerp_angle(rotation.y, _camera_yaw + PI, smoothing)   ← facing НЕ зависит от direction вообще
```

**Критическая проверка "не появился ли скрытый feedback loop TPS camera → movement → rotation → camera":**
[CONFIRMED — не появился]. `camera_target_pos`/`camera_target_pos` пивот строится из `target.global_position` (позиция), а НЕ из `target.rotation.y`. Значит `rotation.y` персонажа нигде не используется как вход для вычисления позиции или yaw камеры В TPS-режиме. Единственное место, где `player.rotation.y` читается камерой — `TpsCombatCameraState._explore_result()` (`target_yaw := player.rotation.y + PI`), но это значение **не применяется** к `camera_target_yaw` пока `state != LOCKED` (см. предыдущий аудит, CONFLICT-1/CONFLICT-4). В `LOCKED`-состоянии yaw строится из `player.global_position`/`locked_target.global_position` (геометрия), тоже не из `rotation.y`. **Значит формального алгебраического feedback loop нет и в TPS не появится дополнительно после удаления ISO** — эта часть архитектуры уже безопасна.

Единственная реальная зависимость движения от камеры-с-задержкой — уже описанная в предыдущем аудите ORD-1 (1-тиковая задержка через `camera.global_transform.basis`, читаемое `TPSMovementSystem` ДО того, как камера в этот тик обновилась) — она не связана с ISO и переживёт миграцию без изменений, если её не исправить отдельно.

---

## 11. Input dependencies

| Action | Consumer(s) | ISO only | TPS only | Both | Unused |
|---|---|---|---|---|---|
| `toggle_view` (V) | `_handle_view_toggle()` в `OnFootCameraComponent` | — | — | ДА (это и есть переключатель) | — |
| `zoom_in`/`zoom_out` (Wheel) | `_handle_zoom_input()`/`_start_zoom()` | — | Формально общий метод, но TPS-ветка `_start_zoom` возвращает рано ("zoom disabled in TPS") | Технически ДА (input читается всегда), функционально ISO-only | — |
| `lean_left`/`lean_right` (Q/E) | `is_lean_left/right_pressed()` в ISO bounded look; `is_lean_left/right_just_pressed()` в мёртвом orbit-коде | ДА (held-версия активна только в ISO) | — | — | just_pressed-версия мертва в обоих режимах (см. §5) |
| `switch_shoulder` (Z) | `_handle_shoulder_toggle()` | — | ДА | — | — |
| `lock_on` (G) | `_tps_combat.try_toggle_lock()` | — | ДА | — | — |
| `toggle_follow` (P) | `is_toggle_follow_just_pressed()` | Формально читается, но `_handle_follow_toggle()` возвращает рано в TPS И задокументирован как "no effect since ISOMETRIC became directional" | — | Технически связан с обоими, функционально мёртв в обоих | По факту да, мёртв |
| `mouse_left_button`/`mouse_right_button` | Разные consumers по `view_mode`+`stance` (click-to-move/stop в ISO, punch/aim в TPS) | Частично | Частично | ДА, ветвится и по view_mode, и по stance | — |

**REMOVE-кандидаты (только после подтверждения нулевых consumers):** `zoom_in`/`zoom_out` — если TPS никогда не зумируется, а ISO удаляется, эти actions теряют функционального потребителя (`_start_zoom` для TPS всегда `return` рано). Требуется явное решение: либо TPS получает zoom, либо actions удаляются вместе с `ZoomRulerSystem`/`zoom_ruler_hud.gd`.
**KEEP:** `switch_shoulder`, `lock_on` — чисто TPS, не затронуты.
**UNKNOWN до решения продукта:** `lean_left`/`lean_right` — их held-форма (bounded glance) чисто ISO; их just-pressed форма уже мертва. Нужно решение: переносить ли "bounded glance" в TPS или удалять оба action.
**KEEP (не трогать):** `toggle_view` — становится unbound/удаляется ТОЛЬКО вместе с `PlayerState.view_mode` целиком, это решение более высокого порядка, не input-level.

---

## 12. InputSystems audit

`_mouse_look_delta`/`_frame_look_delta`/`get_look_delta()`:
- Пишется в `_input()` (event-driven, накопление за кадр)
- Переносится в `_frame_look_delta` в `_physics_process()`, обнуляется каждый тик — **используется ТОЛЬКО TPS-веткой** (`_handle_tps_follow()` в `OnFootCameraComponent`) [CONFIRMED — grep на `get_look_delta` в предыдущем аудите нашёл единственный call site]
- ISO НЕ использует `get_look_delta()` вообще — mouse-look в ISO отключён по дизайну (input_map.md, строки 128-133): "Mouse-X drives the look in TPS but deliberately not here"
- **Вывод:** `_mouse_look_delta`/`_frame_look_delta`/`get_look_delta()` — де-факто уже TPS-only инфраструктура, ISO её не трогает вообще. Удаление ISO НЕ требует изменений здесь.

`_apply_mouse_mode()` — единственное место в `InputSystems`, реально зависящее от `view_mode` (курсор capture). [CONFIRMED по цитате из документации; сам метод не был построчно перечитан в этом сеансе — код существует по адресу `input_systems.gd:189` (обрезанный диапазон в предыдущем чтении файла), требуется точечное дочтение перед миграцией — [REQUIRES RUNTIME/дочтение, не критично для архитектурного решения].

---

## 13. Physics process order

Полностью подтверждено в предыдущем аудите (ORD-1, CONFLICT-3), повторяю ключевой факт:

- `InputSystems` — autoload, гарантированно первый каждый тик [CONFIRMED — свойство движка Godot]
- `TPSMovementSystem`, `player`, `camera` (через `camera_follow.tscn`) — добавляются в дерево в `world.gd` в порядке: `WORLD_SYSTEM_SCRIPTS` (включает `ClickToMoveSystem` ДО `TPSMovementSystem`, затем остальные системы) → `player` → `camera`
- Ни `process_priority`, ни `process_physics_priority` НЕ используются нигде в проекте [CONFIRMED — `grep` пуст]
- **ARCHITECTURAL RISK** [как и было классифицировано ранее]: порядок держится исключительно на порядке `add_child()`. Удаление ISO НЕ устраняет и НЕ усугубляет этот риск — `ClickToMoveSystem` тоже висит в этом же списке `WORLD_SYSTEM_SCRIPTS`, его удаление сдвинет индексы, но не меняет структурную проблему.
- Минимальный способ сделать порядок явным (не применять сейчас): выставить `process_physics_priority` на 4 узлах согласно требуемому порядку (уже предложено в предыдущем аудите как P0 Diff 1) — актуально независимо от судьбы ISO.

---

## 14. CameraFollow audit

`CameraFollow` — **dispatcher, не state owner**. [CONFIRMED]. Его собственное состояние — только `CameraState.GAME/MENU_PAUSE` (пауза-анимация) и `_active_component` (переключение по `PlayerState.mode`, НЕ `view_mode`). Он хостит `OnFootCameraComponent`, `HoverCameraComponent`, `TubeTransitCameraComponent`, `CameraShakeComponent` как children/поля.

ISO-only ветки внутри `camera_follow.gd`:
- `_update_iso_debug_visibility()` — единственная ISO-специфичная логика во всём файле
- Поле `iso_debug_enabled` (export) и `iso_camera_debug` (`@onready`)

Всё остальное — общее (MENU_PAUSE анимация, shake, диспетчеризация по `mode`).

**Можно ли оставить `CameraFollow`?** Да — он уже структурно является тем самым "dispatcher по `PlayerState.mode`", который нужен и для vehicle-камер, и для будущей единственной TPS on-foot камеры. Удаление ISO требует убрать только 2 маленьких фрагмента (метод + 2 поля + сцен-узел `IsoCameraDebug`), не переписывания файла.

---

## 15. OnFootCameraComponent audit

Классификация методов (по чтению всего файла в предыдущем аудите + доп. проверка в этом):

| Категория | Методы |
|---|---|
| **COMMON** | `setup()`, `enter()`, `exit()`, `update()` (диспетчер верхнего уровня), `_handle_zoom_input()`/`_start_zoom()` (общий код, TPS-ветка внутри рано выходит), `_handle_view_toggle()`, `_transition_to_view()` (общий метод с TPS/ISO ветками внутри), `_update_labels()`, `get_current_mode()`, `get_combat_state()`, `get_current_zoom_range()`, `_target_metric_height()`, `_target_speed_ratio()`, `_target_horizontal_direction()`, `_target_facing_direction()`, `_yaw_facing()` |
| **TPS** | `_handle_tps_follow()`, `_select_tps_distance_source()`, `_decay_tps_state()`, `_handle_shoulder_toggle()`, TPS-ветка `_update_camera_position()` |
| **ISO** | `_handle_isometric_look_input()`, `_update_iso_head_look()`, `_clear_iso_head_look()`, `_build_iso_frame()`, `_cursor_edge_weight()`, `_cursor_ground_point()`, `_apply_iso_wall_clamp()`, `_update_iso_look_ahead()`, `_push_iso_debug()`, ISO-ветка `_update_camera_position()`, ISO-ветка `_transition_to_view()` |
| **TRANSITION** | `_update_zoom_animation()`, `_update_view_mode_animation()` — общие для перехода в обе стороны |
| **LEGACY/DEAD** | `_handle_rotation_input()`, `_rotate_camera_left()`, `_rotate_camera_right()`, `_handle_follow_toggle()`, `_handle_follow_rotation()`, `_update_orbit_rotation_animation()`, `_update_follow_rotation_animation()` — уже задокументированы в самом файле как недостижимые ("nothing reaches them"), НЕ вызваны ISO/TPS различием, а более ранним переходом ISO на directional-модель |
| **UNKNOWN** | нет — весь файл прочитан и классифицирован |

**Цель после удаления ISO:** файл должен потерять всю строку ISO + LEGACY/DEAD (обе категории уже мёртвые по отношению к текущему рантайму или станут мёртвыми при удалении ISO) — реалистичная оценка сокращения объёма файла [INFERENCE] — 45-55% строк, т.к. большая часть из 2023 строк — комментарии к ISO-подсистемам (occlusion, look-ahead, screen-edge framing — очень подробно закомментированные блоки констант).

---

## 16. IsometricCameraState audit

- **Who instantiates:** `OnFootCameraComponent` (`var _iso := IsometricCameraState.new()`, поле, не автозагрузка) [CONFIRMED]
- **Who references:** только `OnFootCameraComponent` [CONFIRMED — не найдено других мест инстанцирования/использования класса `IsometricCameraState` вне `camera/` в широком поиске §2 этого отчёта]
- **Who calls update:** `on_foot_camera_component.gd::_update_camera_position()`, ISO-ветка
- **What data does it own:** `current_angle` (собственный yaw), follow point, occlusion distance, position spring state
- **External consumers of its outputs:** только `on_foot_camera_component.gd` (копирует `current_angle`/`get_current_yaw()` обратно в свои поля для дебаг-лейблов и следующего view-transition)

**Per-result decision (предварительно, не окончательно — требует product-level согласования):**
- `current_angle`/orientation — **удалить** вместе с классом, TPS его не использует
- occlusion (sphere-cast) — **перенести/заменить**: единственный кандидат на улучшение TPS-occlusion (см. §17), т.к. CHANGELOG прямо документирует, что sphere-подход был осознанно принят как решение проблемы raycast-а
- zoom/position/pitch логика — **удалить**, специфична для orbit-камеры сверху, не применима к TPS shoulder-камере
- player facing (`_iso_manual_look_yaw_deg`, head-look офсет) — **удалить** вместе со всей ISO head-look цепочкой (§5, §8)
- Generic utility кандидаты — **не найдено** ни одной функции внутри `IsometricCameraState`, которая была бы полезна как domain-independent utility (весь класс написан специально под orbit-camera-over-character модель, не переиспользуемую для shoulder-камеры)

---

## 17. Occlusion / collision audit

| | ISO | TPS |
|---|---|---|
| Метод | `intersect_shape` (sphere), `cast_motion()` | `intersect_ray` |
| Радиус/форма | `ISO_COLLISION_RADIUS = 0.45` | точечный луч |
| Min distance | `ISO_COLLISION_MIN_DISTANCE = 3.0` | нет явного min (кроме `TPS_ZOOM_MIN=3.0`, применяется до occlusion, не как отдельный этап) |
| Restore rate | `ISO_COLLISION_RESTORE_RATE = 2.5` (асимметрично — retract мгновенный, restore медленный) | нет отдельной ставки — occlusion применяется напрямую к `camera_target_pos`, который затем идёт через общий position-lerp `TPS_FOLLOW_SPEED` |
| Surface margin | `0.25` | `0.25` (совпадает) |
| Layers | `CollisionLayers.CAMERA_OCCLUSION = FLOOR | WALL` (общая константа) | та же константа |
| Character self-collision | UNKNOWN — не найдено явной проверки, что маска исключает/включает тело игрока | то же UNKNOWN |
| Floor vs wall различение | Общий маск, оба слоя вместе | тот же |

**Историческая, задокументированная (не предполагаемая) причина разницы** [CONFIRMED, CHANGELOG строки 1550-1557]: "ISOMETRIC had no collision check at all; only TPS did" (первичное состояние), затем "A sphere `cast_motion()` now runs... A sphere rather than a ray because a ray asks whether the camera's mathematical centre has crossed the wall — answered late... while a sphere reports the surface a radius early". Это прямая проектная документация, объясняющая, ПОЧЕМУ raycast (TPS, более старый) хуже sphere-cast (ISO, более новый, целенаправленное решение именно этой проблемы).

**Вывод — не копировать ISO вслепую, но использовать её КАК ЭТАЛОН намеренно, а не случайно:** [INFERENCE, подкреплён CONFIRMED историческим фактом] единственная TPS-камера должна унаследовать sphere-based occlusion contract, потому что проект уже один раз прошёл путь "raycast → обнаружена проблема → sphere" и повторное протаскивание raycast в финальную архитектуру означало бы сознательный откат уже принятого и задокументированного решения.

---

## 18. TPSCombatCameraState audit

Полностью повторяет находки предыдущего forensic-аудита (CONFLICT-1, CONFLICT-2, CONFLICT-4), кратко:

- **EXPLORE:** spring-damper к `player.rotation.y + PI`, считается, но **не применяется к `camera_target_yaw`** (используется только `pitch_offset_deg`) [CONFIRMED]
- **LOCKED:** полностью перезаписывает `camera_target_yaw` из геометрии (`player.global_position`↔`locked_target.global_position`), mouse-look молча отбрасывается [CONFIRMED]
- **TRANSITION:** blended yaw считается (`_blend_result`), но условие в вызывающем коде (`if state == LOCKED`) НЕ включает `TRANSITION` — **этот найденный ранее behavior должен быть либо явно исправлен, либо явно перенесён как есть (с багом) в новую единственную-TPS архитектуру**, если исправление выходит за рамки текущей миграции. **Важно: миграция ISO→TPS НЕ должна случайно "починить" или "потерять" это поведение неявно** — если исправление CONFLICT-1 не входит в согласованный scope этой миграции, поведение переносится as-is, с явной пометкой в migration plan, что это известный, отдельно тикетированный баг.
- Hysteresis, occlusion для lock-on — отсутствуют, задокументированы в самом файле как TODO (не относится к ISO/TPS миграции, независимая функциональная недостача)

---

## 19. Shoulder camera audit

[CONFIRMED, полностью соответствует предыдущему аудиту] `TpsShoulderCameraState` не пишет yaw ни при каких обстоятельствах — офсет применяется как боковой перенос пивота (`right * shoulder_offset`) и как `camera.h_offset` (lens shift). Не взаимодействует с `IsometricCameraState` вообще (не импортируется, не читается оттуда). Полностью безопасен для переноса as-is в single-TPS архитектуру.

---

## 20. Aim pipeline audit

**Реально существующий pipeline** [CONFIRMED, новая находка этого сеанса, отсутствовавшая в предыдущем аудите]:

```
Body facing (player.rotation.y, лагово следует за camera_yaw через _face_camera)
    ↓
_find_punch_target(reach, angle_deg) — cone-поиск ближайшего NPC в узком угле от facing
    ↓ (для стрельбы: shot_range=40.0, shot_angle_deg=6.0° — очень узкий конус = soft-lock)
target
    ↓
_has_clear_shot() — line-of-sight raycast shoulder-to-shoulder (только occlusion-проверка, НЕ direction-проверка)
    ↓
target.take_hit()
```

**НЕТ:** screen-center → camera forward → world-ray → hit-point pipeline. `aim_reticle.gd` — чисто визуальный крест в центре экрана, не связан ни с каким raycast'ом [CONFIRMED, файл прочитан полностью]. `WeaponComponent` — чистая бухгалтерия магазина/патронов, ноль direction-логики [CONFIRMED].

**Ответ на прямой вопрос "может ли камера смотреть в одну сторону, персонаж — в другую, а оружие — в третью?":**
[CONFIRMED] Формально "оружие" не имеет собственного направления вообще — целевой поиск идёт от `rotation.y` тела. Камера и тело МОГУТ временно разойтись (лаг `_face_camera`'s `lerp_angle` при резком повороте мыши), и в этот промежуток аим-конус будет смотреть туда, куда смотрит ТЕЛО (отстающее), а не туда, куда уже смотрит камера. Три раздельных направления (камера/тело/оружие) физически не существуют — оружие всегда равно телу.

**Удаление ISO не ломает aim** [CONFIRMED] — вся цепочка `_find_punch_target`/`_resolve_shot`/`_has_clear_shot` не читает `view_mode` и не читает камеру напрямую вообще.

---

## 21. Animation dependencies

- `update_animation_blend()` — camera-независим полностью, читает только `get_movement_vector_relative_to_facing()` (velocity относительно `rotation.y`) [CONFIRMED]
- `update_head_look()` — **единственная реальная ISO/TPS-зависимость в анимационном слое**, `match PlayerState.view_mode`:
  - TPS-ветка: `_player.get_camera_yaw() + PI` → голова смотрит по направлению камеры в TPS-idle
  - ISO-ветка (`_:`): `_look_point`/`_look_point_valid`, пишется извне только `OnFootCameraComponent._update_iso_head_look()`
  - Fallback (ни то ни другое, или движение): `get_facing_direction()` — camera-независим
- `get_head_yaw_relative_deg()` — общая утилита,UNKNOWN точный текущий потребитель (задокументирована как "not consumed inside player.gd yet — added ahead of need")

**Классификация:**
- camera-independent: `update_animation_blend()`, `update_sprint_blend()`, весь punch/death/stance-blend
- camera-dependent (TPS): `update_head_look()` TPS-ветка
- ISO-only: `update_head_look()` ISO-ветка + вся `_look_point` инфраструктура (`set_head_look_point`/`clear_head_look_point`)
- TPS-only: нет отдельной TPS-only анимационной системы кроме указанной ветки head-look

**Left-turn bug и animation layer** — в этом сеансе `player_animation_component.gd` прочитан прицельно (head-look и blend-space секции). **Не найдено** clamp'ов или условной логики в `update_animation_blend()`, которая могла бы асимметрично блокировать поворот влево — blend-space строится из `Vector2` без directional clamp'ов на уровне этого файла. [REQUIRES RUNTIME для окончательного снятия гипотезы — статический анализ AnimationTree-ресурса (`.tres`) не проводился, blend-space geometry сама по себе не прочитана как ресурс].

---

## 22. UI dependencies

| System | ISO reference | Action |
|---|---|---|
| `aim_reticle.gd` | нет | KEEP AS IS |
| `zoom_ruler_hud.gd` + `zoom_ruler_system.gd` | Прямая, в самом смысле виджета | REWRITE (переосмыслить: либо TPS получает zoom и виджет адаптируется, либо виджет и вся система удаляются) |
| `isometric_camera_debug_overlay.gd` | Полностью ISO | REMOVE |
| `stream_debug_panel.gd` | Читает `get_combat_state()` (TPS lock-on diagnostic) — НЕ ISO-специфичен, несмотря на соседство в debug-папке | KEEP |
| `key_hints_panel.gd`/`key_hints.tres` | [INFERENCE, не пере-верифицировано] предположительно фильтрует по `view_mode` через `KeyHintEntry.view_modes` | REWRITE (убрать `view_modes` фильтрацию, оставить только `TPS`-релевантные подсказки) — [требует точечного дочтения перед реализацией] |
| Debug-лейблы в `camera_follow.tscn` (`CurrentMode`, `Orbital`, `Follow`) | `_update_labels()` формирует ISO-специфичный текст ("Осмотреться: удерживай Q или E", и т.д.) | MODIFY (упростить текст, убрать ISO-ветки внутри `_update_labels()`) |

---

## 23. World / NPC / AI dependencies

[CONFIRMED — полный grep по `npc/`, `world/police_drone/` на `view_mode|camera|ISOMETRIC|PlayerState.` дал только обращения к `PlayerState.stance`]

**Нет ни одной системы, предполагающей существование ISO.** Perception, witness system, target selection, navigation (NPC-side, отдельная от игрока) — все camera-mode-независимы. Единственная NPC-side зависимость от camera-related контракта — `npc_base.gd`'s `get_facing_direction()` метод, названный так же, как у игрока, чтобы TPS lock-on (`_get_facing_direction()` в `TpsCombatCameraState`, duck-typed) мог работать одинаково на игроке и NPC — это **TPS-специфичная, а не ISO-специфичная** межфайловая договорённость, не пострадает от удаления ISO.

---

## 24. Vehicle dependencies

[CONFIRMED] `HoverCameraComponent`, `TubeTransitCameraComponent`, `hover_base.gd`, `input_hover_controller.gd` — **ноль** обращений к `camera`, `view_mode`, `ISOMETRIC`, `OnFootCameraComponent`, `IsometricCameraState` (широкий grep пуст). Диспетчеризация между on-foot и vehicle камерами идёт через `PlayerState.mode` (ON_FOOT/HOVER/TUBE_TRANSIT), полностью ортогонально `view_mode` (TPS/ISOMETRIC), который существует только внутри `Mode.ON_FOOT`. **Vehicle-инфраструктура не требует никаких изменений при удалении ISO.**

---

## 25. Scene/resource dependencies

- `camera/camera_follow.tscn` — единственная сцена с прямой ISO-ссылкой (`IsoCameraDebug` node + script). [CONFIRMED, полный текст сцены прочитан]
- `world/world.tscn` (main scene) — НЕ содержит прямых узлов `OnFootCameraComponent`/`IsometricCameraState` (они инстанцируются в коде через `.new()`), т.е. сцена САМА по себе не хранит ISO-зависимости на уровне NodePath. [CONFIRMED по чтению `world.gd` и `camera_follow.gd::_ready()`]
- `.tres`-ресурсы: не найдено отдельных `.tres` конфигов, специфичных для ISO-камеры (все настройки — `@export`-поля в `.gd`-файлах, не вынесены в ресурсы) — **orphaned resources после удаления ISO: НЕ ОЖИДАЕТСЯ** [INFERENCE, основана на отсутствии найденных `.tres` с "iso"/"isometric" в имени или содержимом — точечный поиск не проводился по содержимому всех `.tres`, только по имени пути в широком grep §2, который не выявил `.tres`-файлов вообще].

**UNKNOWN — requires verification:** точный список `.tres`, ссылающихся на удаляемые скрипты (Godot хранит `script` ссылки по UID, полный обратный поиск по UID `isometric_camera_state.gd`/`isometric_camera_debug_overlay.gd` не проводился в этом сеансе).

---

## 26. Build/export dependencies

- `export_presets.cfg` — **отсутствует в репозитории** [CONFIRMED отсутствие файла]. Экспорт-конфигурация — либо не версионируется (обычная практика для Godot, т.к. содержит абсолютные локальные пути), либо не настроена. → **UNKNOWN — requires verification** вне репозитория (у разработчика локально).
- `addons/godot_ai`, `addons/item_fitter` — оба плагина не содержат ни одной ссылки на `isometric`/`ISOMETRIC`/`view_mode` (широкий grep §2 захватил только `camera_handler.gd` — это EDITOR-камера MCP-инструмента, полностью не связанная с gameplay `Camera3D`/`OnFootCameraComponent`). [CONFIRMED]
- CI (`.github/workflows/godot.yml`) не содержит явных camera/ISO-специфичных шагов — верифицирует только "проект парсится" и "world.tscn грузится/бутится" в целом, что автоматически покроет и удаление ISO без отдельной настройки CI. [CONFIRMED]

---

## 27. Git-history findings

[CONFIRMED, все цитаты — дословные из git log/show]

- ISO-камера построена в 8 фазах между 2026-08-26 и 2026-08-27 (`35056f2` "Phase 1" → `ecae9c4` "Phase 5A"/`92dff18` "Phase 5B"), под отдельным брифом, ПАРАЛЛЕЛЬНО основному "island horizon", **никогда не попадая на roadmap-страницу до отдельного ретроактивного commit**.
- Коммит `1c3ffd2` ("Scope review...") **прямым текстом** документирует: *"The ISOMETRIC camera work is recorded under a new 'Out of plan' heading... it is not finished — collision response and a refactoring pass remain."*
- `docs/scope_horizon.md`, секция "Out of plan" → "ISOMETRIC camera feel (Phases 1 → 5B)" → **"Not finished. Collision response and a refactoring pass remain."** — это последнее известное официальное состояние ISO-камеры в проектной документации, датированное 2026-08-27, и НЕ обновлённое после этого (HEAD — 2026-08-30, 3 дня спустя, без дальнейших правок этого файла по ISO).
- `scope_horizon.md` **не содержит ни одного упоминания TPS** — TPS-работа не отслеживается через тот же roadmap-механизм, что усиливает [INFERENCE]: TPS появился как параллельный, более новый и, судя по HEAD-коммиту "tps_camera_first" (30 августа, спустя 3 дня после scope review), — вероятно, задуманный как замена уже помеченной "не закончена, вне плана" ISO-камеры.
- CHANGELOG прямо документирует историю occlusion (raycast → признана хуже → sphere-cast как осознанное решение), см. §17.
- CHANGELOG документирует дату, когда `NavigationComponent` перестал быть ISO-only и стал общим с TPS (см. §7).

**Не делаю вывод "старый код = плохой код".** История здесь скорее говорит обратное: ISO — не "плохой", а осознанно недоделанный побочный эксперимент, который так и не получил финальной проходки (что подтверждает, а не противоречит, идее его удаления, но НЕ является технической причиной удаления самой по себе — только организационным контекстом).

---

## 28. Risks

1. **[HIGH]** `zoom_ruler_hud.gd`/`ZoomRulerSystem` — семантически неотделимы от ISO↔TPS континуума; удаление ISO без явного решения о судьбе TPS-зума оставит систему в неопределённом состоянии (см. §11, §22).
2. **[MEDIUM]** `PlayerAnimationComponent.update_head_look()` — ISO-ветка удаляется вместе с `_look_point` инфраструктурой в 3 файлах одновременно (`OnFootCameraComponent`, `player.gd`, `PlayerAnimationComponent`) — пропуск одного из трёх мест оставит мёртвый, но потенциально ошибочно вызываемый код.
3. **[MEDIUM]** `ClickToMoveSystem` vs `NavigationComponent` — лёгкая ошибка: удалить `NavigationComponent`/`_handle_navigation` вслед за `ClickToMoveSystem`, ошибочно посчитав их одной системой — сломает TPS-подход через `InteractComponent`.
4. **[HIGH, унаследован из предыдущего аудита, НЕ новый]** Порядок `_physics_process` (ORD-1) — не устраняется и не усугубляется этой миграцией, но остаётся системным риском независимо от неё.
5. **[MEDIUM]** CONFLICT-1 (TRANSITION blended yaw не применяется в lock-on) — риск, что при рефакторинге `OnFootCameraComponent` (удаление ISO-веток) это поведение будет случайно "исправлено" неявно (например, если кто-то одновременно упростит условие `if state == LOCKED`) без отдельного решения продукта — нужно явно зафиксировать в migration plan, трогается это поведение или нет.
6. **[LOW]** `export_presets.cfg` отсутствует в репозитории — build/export последствия миграции не могут быть проверены статически, только через CI (которое покрывает только headless import/boot, не полный export).
7. **[UNKNOWN]** `KeyHintsPanel`/`key_hints.tres` фильтрация по `view_modes` — не пере-верифицирована в этом сеансе, требует точечного чтения перед миграцией UI.

---

## 29. Unknowns requiring confirmation

- [UNKNOWN] Точное содержимое `InputSystems._apply_mouse_mode()` (строки 189-278, не дочитаны построчно в этом сеансе, хотя цитата из `input_map.md` косвенно подтверждает поведение).
- [UNKNOWN] `KeyHintEntry.view_modes` — точный механизм фильтрации подсказок по `view_mode`, не перепрочитан в этом сеансе.
- [UNKNOWN] Есть ли `.tres`-ресурсы, ссылающиеся на `isometric_camera_state.gd`/`isometric_camera_debug_overlay.gd` по UID — обратный поиск по UID не проводился.
- [UNKNOWN] `export_presets.cfg` / реальная export-конфигурация — отсутствует в репозитории, состояние не может быть подтверждено из VCS.
- [REQUIRES RUNTIME] Left-turn bug (см. предыдущий аудит §7) — причина не подтверждена статическим анализом ни в прошлом, ни в этом сеансе; дополнительно проверено, что `player_animation_component.gd` не содержит очевидного directional-clamp'а, но полный AnimationTree/BlendSpace2D ресурс не инспектирован как данные.
- [REQUIRES RUNTIME] Character self-collision в occlusion (и ISO sphere-cast, и TPS raycast) — не подтверждено, что маска `CAMERA_OCCLUSION` исключает/учитывает тело самого игрока корректно при экстремальных углах питча.
- [INFERENCE, требует product-decision, не кода] Судьба TPS-зума (см. риск №1) — это не технический факт, а продуктовое решение, которое должно быть принято ДО составления финального migration order.

---

## 30. Final recommendation

**Аудит НЕ считаю завершённым для перехода к Act-фазе** (§42 критерий готовности из исходного задания) по следующим конкретно оставшимся пунктам:

1. ✅ Владелец финального `Camera3D` transform — определён (`OnFootCameraComponent`, единолично).
2. ✅ Владелец camera yaw — определён (с одной известной, задокументированной аномалией — CONFLICT-1 в TRANSITION lock-on).
3. ✅ Владелец camera pitch — определён (та же логика, отдельные поля, тот же owner).
4. ✅ Владелец player facing — определён (`player.gd::_face_camera()`, единственный writer в TPS).
5. ✅ Владелец movement basis — определён (`TPSMovementSystem`, читает `camera.global_transform.basis` напрямую).
6. ⚠️ Судьба `PlayerState.view_mode` — **не решена**: технически можно удалить (единственный оставшийся режим — TPS, enum станет вырожденным), но >6 живых потребителей (§3) требуют явного per-consumer решения REMOVE/MODIFY, не единого флага.
7. ⚠️ Судьба ISO↔TPS transition-кода — **не решена окончательно**: `_transition_to_view()` физически исчезнет как развилка, но нужно решить, остаётся ли сам механизм (view_mode_animating и т.п.) для потенциального будущего режима (vehicle-камера уже использует другую диспетчеризацию — `PlayerState.mode`, так что вероятно НЕ нужен) или удаляется целиком.
8. ⚠️ Input actions к удалению — **не решены до конца** (`zoom_in`/`zoom_out`, `lean_left`/`lean_right` — см. §11, риск №1).
9. ✅ Scene nodes к удалению — определены (`IsoCameraDebug` — единственный).
10. ⚠️ Resources к удалению — **не подтверждены полностью** (§25, №29 — обратный UID-поиск не проведён).
11. ⚠️ Animation dependencies — определены, но требуют скоординированного удаления в 3 файлах одновременно (риск №2).
12. ✅ Aim/combat dependencies — определены, изменений не требуют (aim не зависит от ISO вообще).
13. ⚠️ UI dependencies — частично определены, `KeyHintsPanel`/`key_hints.tres` требует дочтения (риск №7), `zoom_ruler` требует продуктового решения (риск №1).
14. ✅ World/NPC dependencies — определены как нулевые.
15. ✅ Vehicle dependencies — определены как нулевые, сохраняются без изменений.
16. ⚠️ Build/export dependencies — не могут быть подтверждены (файл конфигурации отсутствует в VCS).
17. ❌ Точный порядок удаления — **не составлен на этом этапе намеренно** (согласно постановке задачи: только Observe+Orient+Decide, Act отдельно).
18. ❌ Доказательство отсутствия регрессий — **не может быть дано без runtime**, только через существующий CI + ручной regression-сценарий из §36 исходного задания (left/right/strafe/backpedal/aim/shoulder/lock-on цикл).

**Рекомендация:** Прежде чем переходить к составлению детального Ordered Migration Plan (пункты 33-34 исходного задания) и тем более к Act-фазе, нужно закрыть три открытых продуктовых (не технических) вопроса: (а) судьба TPS-зума и, соответственно, `zoom_ruler`-системы; (б) судьба `lean_left/right` bounded-glance функциональности; (в) явное решение — трогается ли CONFLICT-1 (TRANSITION blended yaw) в рамках этой миграции или переносится как известный отдельный баг. Технической причины откладывать удаление `IsometricCameraState`/`isometric_camera_debug_overlay.gd`/ISO-веток `OnFootCameraComponent` нет — они логически изолированы и уже официально помечены проектом как "not finished, out of plan". Риск исходит не из сложности самого удаления, а из недосмотренных периферийных потребителей (animation head-look, UI zoom ruler, key hints), которые находятся в других файлах и легко пропускаются при поверхностном рефакторинге "просто удалить папку camera/iso*".

Изменения в код не вносились. Аудит соответствует запрошенному объёму Observe+Orient+Decide; Act — по отдельному согласованию.
