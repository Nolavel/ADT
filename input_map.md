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

Action count: **33** — 29 live, 4 reserved and unread.

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
| `toggle_follow` | `P` | Toggle camera-follows-player-rotation | Слежение камеры |
| `inventory` | `I` | Inventory | Инвентарь |
| `map` | `M` | Map | Карта |
| `status` | `X` | Status | Статус |
| `toggle_tabs` | `Tab` | Tap — notifier; hold — status camera | Тап/холд — уведомление/статус-камера |
| `toggle_stance` | `T` | Toggle `PlayerState.Stance` PEACE ⇄ COMBAT | Смена стойки |

---

## 3. ON_FOOT — ISOMETRIC only

Click-to-move navigation. Handled by `NavigationComponent` and
`ClickToMoveSystem`.

| Action | Key | Description | RU |
|---|---|---|---|
| `mouse_left_button` | LMB | `PEACE`: stop movement / cancel move target. `COMBAT`: punch instead — see §4, same action as TPS, standing still only | `PEACE`: отменить цель движения. `COMBAT`: удар (только с места) |
| `mouse_right_button` | RMB click | Move to clicked point — regardless of `Stance` | Идти в точку |
| `mouse_right_button` | RMB hold > 0.5 s | Switch to running toward target | Бег к цели |
| `lean_left` | `Q` | Orbital camera — discrete step left | Шаг камеры влево |
| `lean_right` | `E` | Orbital camera — discrete step right | Шаг камеры вправо |

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
