# InputMap

> Verified against `project.godot` on **2026-08-12** · Godot 4.7 · GDScript

**This document is the single source of truth for input bindings.** Update it
in the same commit as any action added, removed or rebound in
Project Settings → Input Map.

Mode is owned by `PlayerState.mode` (`ON_FOOT`, `HOVER`, `TUBE_TRANSIT`,
`MENU`) and `PlayerState.view_mode` (`TPS`, `ISOMETRIC`).
`TOPDOWN` was removed from the project — do not reintroduce it.

`InputSystems` (`core/input/input_systems.gd`) is the only script that calls
`Input.*`. Everything else subscribes to its signals or calls its query
methods. Exceptions: `core/map_source/`, `map_camera/` — editor tooling that
reads raw `KEY_*` deliberately.

Action count: **36** — 32 live, 4 reserved and unread.

---

## 1. Global

Active regardless of `PlayerState.mode`.

| Action | Key | Description | RU |
|---|---|---|---|
| `pause` | `Esc` | Open / close pause menu; owns `get_tree().paused` via `PlayerState` | Меню паузы |
| `toggle_stream_debug` | `\` | Toggle the streaming debug panel (observer only) | Панель отладки стриминга |
| `toggle_perception_debug` | `]` | Toggle the NPC perception debug panel (observer only) | Панель отладки восприятия NPC |
| `debug_save` | `K` | Debug save to slot 0 (`SaveSystem`) — permanent developer tool, not the in-fiction save mechanism | Отладочное сохранение |
| `debug_load` | `L` | Debug load from slot 0 (`SaveSystem`) | Отладочная загрузка |
| `toggle_key_hints` | `H` | Show/hide the key-hints HUD panel (`InputSystems.key_hints_enabled`) | Показать/скрыть панель подсказок |

`draw_holster` is its own action rather than a side effect of `toggle_stance`:
hanging the draw off the stance key would mean entering COMBAT auto-draws, and
raised fists are already a statement on their own. The two are coupled the
other way instead — drawing something that reads as a threat sets COMBAT, and
standing down to PEACE holsters (H5, `player.gd`).

`B` is arbitrary and provisional. `X` would be the conventional holster key but
is taken by `status`, one of the actions defined here and never implemented
(see `docs/planned_scope.md`); repurposing a reserved binding is Stan's call,
not a side effect of this feature.

`debug_save`/`debug_load` were originally bound to `F5`/`F9` (2026-08-12) and rebound
to `K`/`L` the same day: `F5` collides with the Godot editor's own "Run Project"
shortcut, which intercepts the key before it reaches the running game when the game
view is embedded in the editor.

---

## 2. ON_FOOT — shared across ISOMETRIC and TPS

| Action | Key | Description | RU |
|---|---|---|---|
| `interact` | `F` | Pick up / drop item, activate object, board a hover | Взаимодействие |
| `zoom_in` | Wheel down | Zoom camera in | Приблизить |
| `zoom_out` | Wheel up | Zoom camera out | Отдалить |
| `toggle_view` | `V` | Toggle `ISOMETRIC` ⇄ `TPS` | Смена вида |
| `toggle_follow` | `P` | Toggle camera-follows-player-rotation — **no effect since the ISOMETRIC camera became directional** (§3); binding kept, unread | Слежение камеры (не действует) |
| `inventory` | `I` | Inventory | Инвентарь |
| `map` | `M` | Map | Карта |
| `status` | `X` | Status | Статус |
| `toggle_tabs` | `Tab` | Tap — notifier; hold — status camera | Тап/холд — уведомление/статус-камера |
| `toggle_stance` | `T` | Toggle `PlayerState.Stance` PEACE ⇄ COMBAT | Смена стойки |
| `draw_holster` | `B` | Draw the first drawable item on the body, or holster what is in hand (`EquipmentComponent`) | Достать / убрать |

---

## 2a. ON_FOOT — LodgingRoom sleep-hour picker (only while open)

Relayed unconditionally like every other action in this file; `LodgingRoom`
(`world/lodging/`) decides whether a picker is actually open, same "signal
fires always, subscriber decides relevance" convention as everything else.
`interact` (above) is reused, not rebound — first press opens the picker,
second confirms it; no new action needed for that part.

| Action | Key | Description | RU |
|---|---|---|---|
| `lodging_hours_up` | Wheel up | +1 hour, clamped to 8 | +1 час, максимум 8 |
| `lodging_hours_down` | Wheel down | −1 hour, clamped to 1 | −1 час, минимум 1 |
| `pause` | `Esc` | Cancels the picker (also opens the pause menu, unchanged) | Отмена выбора (плюс меню паузы, как обычно) |

Deliberately separate actions from `zoom_in`/`zoom_out` (same physical wheel,
§2 above) — reusing the camera-zoom actions for an unrelated "adjust a
number" UI would overload their meaning everywhere else they're read.

---

## 3. ON_FOOT — ISOMETRIC only

Click-to-move navigation. Handled by `NavigationComponent` and
`ClickToMoveSystem`.

| Action | Key | Description | RU |
|---|---|---|---|
| `mouse_left_button` | LMB | `PEACE`: stop movement / cancel move target. `COMBAT`: punch instead — see §4, same action as TPS, standing still only | `PEACE`: отменить цель движения. `COMBAT`: удар (только с места) |
| `mouse_right_button` | RMB click | Move to clicked point — regardless of `Stance` | Идти в точку |
| `mouse_right_button` | RMB hold > 0.5 s | Switch to running toward target | Бег к цели |
| `lean_left` | `Q` **hold** | Look left — temporary, bounded to ±35° from the character's own direction, springs back on release | Осмотреться влево (удержание) |
| `lean_right` | `E` **hold** | Look right — same bound and spring-back | Осмотреться вправо (удержание) |

`lean_left`/`lean_right` were discrete orbital steps until the ISOMETRIC camera
became directional: yaw now follows the character's movement direction while
moving and their facing once stopped, so there is no orbit left to step. The
two keys carry the bounded temporary look instead — held, not tapped. The
bound (`OnFootCameraComponent.iso_look_yaw_limit_deg`) is what keeps this a
glance rather than a free orbit by another name.

Mouse-X drives the look in TPS but deliberately not here: `InputSystems`
captures the cursor only in TPS (`_apply_mouse_mode()`), because ISOMETRIC
needs a visible cursor for click-to-move. Mouse look in this view would fire
on every ordinary movement toward a click target and stall at the screen
edge. `toggle_follow` (`P`, §2) likewise no longer affects ISOMETRIC — the
camera follows direction unconditionally now.

`mouse_right_button` moved here from "shared" (2026-08-03): `ClickToMoveSystem`
has always self-gated to ON_FOOT + ISOMETRIC, so the click-to-move meaning
never actually applied in TPS — it just had no reader there before this
table said otherwise. See §4 for what the same physical button now does
in TPS.

`mouse_left_button` moved here from "shared" (2026-08-06), same reason:
`ClickToMoveSystem`'s stop-movement handler is gated the same way as its
move-to-point one, so it never actually fired in TPS either. See §4 for
what the same physical button does there now.

`mouse_left_button` splits by `Stance` within ISOMETRIC (2026-08-10):
`ClickToMoveSystem`'s own handler for it (stop/cancel) is unconditional on
`Stance` — it is `player.gd`'s punch handler that only acts in `COMBAT`, on
the same signal. The two never conflict: click-to-move itself, including
`mouse_right_button`, is unaffected by `Stance` and keeps working the same
in `COMBAT` as in `PEACE`.

---

## 4. ON_FOOT — TPS only

Direct movement. `TPSMovementSystem` feeds `player.gd` every physics frame,
and also drives `PlayerState.is_aiming` from the aim hold below.

| Action | Key | Description | RU |
|---|---|---|---|
| `move_forward` | `W` | Forward | Вперёд |
| `move_backward` | `S` | Backward | Назад |
| `move_left` | `A` | Strafe left | Влево |
| `move_right` | `D` | Strafe right | Вправо |
| `jump` | `Space` | Jump | Прыжок |
| `sprint` | `Shift` | Sprint; consumes stamina | Бег |
| `mouse_left_button` | LMB | Punch — only takes effect in `Stance.COMBAT`, standing still (`player.gd`, `punch_max_speed`) | Удар — только в стойке COMBAT и с места |
| `mouse_right_button` | RMB hold | Aim down sights — only takes effect in `Stance.COMBAT` | Прицеливание — только в стойке COMBAT |
| `switch_shoulder` | `Z` | Swap camera shoulder (`TpsShoulderCameraState`) | Смена плеча камеры |
| `lock_on` | `G` | Toggle Explore ⇄ Locked (`TpsCombatCameraState`) | Захват цели |

`mouse_left_button`/`mouse_right_button` are otherwise unclaimed here — their
ISOMETRIC meanings (§3) are read by a different, self-gated system, so each
physical button carries two unrelated meanings depending on `view_mode`.

`lock_on` searches the `lockable` group. Occlusion-aware target selection is
a known TODO, blocked on a raycast service that does not exist yet.

---

## 5. HOVER

Entered through `HoverEntryTrigger` (`interact` near a hover). `Space` and
`Ctrl` are shared with `jump` / `crouch` by design — the modes are mutually
exclusive, so the bindings do not conflict at runtime.

| Action | Key | Description | RU |
|---|---|---|---|
| `move_forward` / `move_backward` | `W` / `S` | Thrust forward / reverse | Тяга |
| `move_left` / `move_right` | `A` / `D` | Strafe / yaw | Стрейф |
| `hover_up` | `Space` | Ascend; release engages altitude hold | Набор высоты |
| `hover_down` | `Ctrl` | Descend; release engages altitude hold | Сброс высоты |
| `toggle_view` | `V` | Camera `CHASE` ⇄ `COCKPIT` | Смена камеры |
| `interact` | `F` | Exit — near-zero speed only | Выход |

Input reaches the vehicle through `InputHoverController`
(`core/controllers/transport/base/input_hover_controller.gd`), which calls
`HoverBase.set_move_intent()` and does no physics of its own.

---

## 6. TUBE_TRANSIT

Camera freelook only. No dedicated actions. Low priority.

---

## 7. MENU

`pause` only. All other input is suppressed while `get_tree().paused` is
true.

---

## 8. Reserved — defined but unread

Present in `project.godot`, consumed by no script. Kept to avoid churning
the input map; removed at the next review if still unread.

| Action | Key | Note |
|---|---|---|
| `crouch` | `C`, `Ctrl` | No crouch state on the player |
| `weapon_reload` | `R` | No weapons |
| `debug_info` | `Enter` | Superseded by `toggle_stream_debug` |
| `crafting` | *(unbound)* | No binding and no reader |

---

## Notes

- `status` is bound with `device: 0` while every other action uses `-1`
  (any device). Harmless for keyboard, but inconsistent — worth normalising.
- Deadzone is `0.2` on every action.
