# InputMap

> Verified against `project.godot` on **2026-07-29** · Godot 4.7 · GDScript

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

Action count: **29** — 25 live, 4 reserved and unread.

---

## 1. Global

Active regardless of `PlayerState.mode`.

| Action | Key | Description | RU |
|---|---|---|---|
| `pause` | `Esc` | Open / close pause menu; owns `get_tree().paused` via `PlayerState` | Меню паузы |
| `toggle_stream_debug` | `\` | Toggle the streaming debug panel (observer only) | Панель отладки стриминга |

---

## 2. ON_FOOT — shared across ISOMETRIC and TPS

| Action | Key | Description | RU |
|---|---|---|---|
| `mouse_left_button` | LMB | Stop movement / cancel move target | Отменить цель движения |
| `mouse_right_button` | RMB click | Move to clicked point | Идти в точку |
| `mouse_right_button` | RMB hold > 0.5 s | Switch to running toward target | Бег к цели |
| `interact` | `F` | Pick up / drop item, activate object, board a hover | Взаимодействие |
| `zoom_in` | Wheel down | Zoom camera in | Приблизить |
| `zoom_out` | Wheel up | Zoom camera out | Отдалить |
| `toggle_view` | `V` | Toggle `ISOMETRIC` ⇄ `TPS` | Смена вида |
| `toggle_follow` | `P` | Toggle camera-follows-player-rotation | Слежение камеры |
| `inventory` | `I` | Inventory | Инвентарь |
| `map` | `M` | Map | Карта |
| `status` | `X` | Status | Статус |
| `toggle_tabs` | `Tab` | Tap — notifier; hold — status camera | Тап/холд — уведомление/статус-камера |

> ⚠ **`toggle_tabs` and `lock_on` are both bound to `Tab`** and both are
> on-foot actions. Unresolved collision — see `docs/planned_scope.md`.

---

## 3. ON_FOOT — ISOMETRIC only

Click-to-move navigation. Handled by `NavigationComponent` and
`ClickToMoveSystem`.

| Action | Key | Description | RU |
|---|---|---|---|
| `lean_left` | `Q` | Orbital camera — discrete step left | Шаг камеры влево |
| `lean_right` | `E` | Orbital camera — discrete step right | Шаг камеры вправо |

---

## 4. ON_FOOT — TPS only

Direct movement. `TPSMovementSystem` feeds `player.gd` every physics frame.

| Action | Key | Description | RU |
|---|---|---|---|
| `move_forward` | `W` | Forward | Вперёд |
| `move_backward` | `S` | Backward | Назад |
| `move_left` | `A` | Strafe left | Влево |
| `move_right` | `D` | Strafe right | Вправо |
| `jump` | `Space` | Jump | Прыжок |
| `sprint` | `Shift` | Sprint; consumes stamina | Бег |
| `switch_shoulder` | `Z` | Swap camera shoulder (`TpsShoulderCameraState`) | Смена плеча камеры |
| `lock_on` | `Tab` | Toggle Explore ⇄ Locked (`TpsCombatCameraState`) | Захват цели |

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
