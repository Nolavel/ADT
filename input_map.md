# InputMap

> Verified against `project.godot` on **2026-08-12** · Godot 4.7 · GDScript

**This document is the single source of truth for input bindings.** Update it
in the same commit as any action added, removed or rebound in
Project Settings → Input Map.

Mode is owned by `PlayerState.mode` (`ON_FOOT`, `HOVER`, `TUBE_TRANSIT`,
`MENU`) and `PlayerState.view_mode` (`TPS`, `TPS_WIDE` — both third person,
differing only in framing).
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

`draw_holster` moved from `B` to `Tab` on 2026-08-26, and became a **cycle**
rather than "draw the first drawable". Both changes have the same cause: the
starter scrap pipe occupied an earlier pocket than the picked-up pistol, so the
key produced the pipe every time and the pistol was unreachable. The pipe is
gone and the key now steps through whatever is on the body. The cycle walks
pockets **and** the back body slots, since the carbine that replaced the pistol
is too large to pocket and lives on the back.

`weapon_reload` (`R`) got its first consumer on 2026-08-27, having been bound
and unread since the map was written: it refills the drawn weapon's magazine
(`player.gd._on_weapon_reload_pressed()`). Refused, with no gesture, when
nothing is drawn, when what is drawn does not feed from a magazine, or when
that magazine is already full.

**`toggle_tabs` was retired to free `Tab`.** It was documented here as "tap —
notifier; hold — status camera", but nothing in the project ever subscribed to
`tabs_key_tapped` or `tabs_key_held` and neither feature was built — the action
relayed a press to no one for its whole life. **The notifier and the status
camera now have no key**; they need one assigned when either is actually built,
and this paragraph is the reminder. The tap/hold timer pattern itself is in git
history (`InputSystems._handle_tabs_key`) if the notifier wants it.

`debug_save`/`debug_load` were originally bound to `F5`/`F9` (2026-08-12) and rebound
to `K`/`L` the same day: `F5` collides with the Godot editor's own "Run Project"
shortcut, which intercepts the key before it reaches the running game when the game
view is embedded in the editor.

---

## 2. ON_FOOT

| Action | Key | Description | RU |
|---|---|---|---|
| `interact` | `F` | Pick up / drop item, activate object; **hold** to board a hover | Взаимодействие |
| `toggle_view` | `V` | Toggle framing `TPS` ⇄ `TPS_WIDE` | Смена кадра |
| `inventory` | `I` | Inventory | Инвентарь |
| `map` | `M` | Map | Карта |
| `status` | `X` | Status | Статус |
| `toggle_stance` | `T` | Toggle `PlayerState.Stance` PEACE ⇄ COMBAT | Смена стойки |
| `draw_holster` | `Tab` | Draw / holster — **cycles** through the drawable items on the body (`EquipmentComponent`) | Достать / убрать — перебор по предметам |
| `weapon_reload` | `R` | Refill the drawn weapon's magazine (`WeaponComponent`) | Перезарядка магазина |

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

These were deliberately separate actions from `zoom_in`/`zoom_out`, which sat
on the same physical wheel until camera zoom was removed with the isometric
camera (2026-09-02). The wheel is the picker's alone now; the separation is
kept because it was right for a reason that outlives the clash — a "camera
zoom" action reused for an unrelated "adjust a number" UI would overload its
meaning everywhere else it is read.

---

## 3. ON_FOOT — camera lean

| Action | Key | Description | RU |
|---|---|---|---|
| `lean_left` | `Q` **hold** | Lean out to the left — the camera slides sideways, springs back on release | Выглянуть влево (удержание) |
| `lean_right` | `E` **hold** | Lean out to the right — same, mirrored | Выглянуть вправо (удержание) |

Held, never tapped, and level reads rather than edges (`InputSystems`
exposes only `is_lean_*_pressed()`). These keys have had three meanings: a
four-position camera orbit, then the isometric camera's bounded glance, and
now a third-person lean. The first two went with the isometric camera on
2026-09-02.

**The camera always leans; the body only leans in COMBAT.** The pose comes
from `new4/aim-lean-l` / `new4/aim-lean-r`, which are static held poses
(measured — every rotation track is constant across the clip, which is why a
plain `AnimationNodeBlend2` is the whole implementation). They are *aiming*
leans: rendered with empty hands in `PEACE` the character reads as miming a
rifle, so out of `COMBAT` the lean is the camera sliding sideways and nothing
else.

---

## 4. ON_FOOT — movement and combat

Direct movement, in both framings. `TPSMovementSystem` feeds `player.gd`
every physics frame and also drives `PlayerState.is_aiming` from the aim hold
below. It used to be gated on `view_mode == TPS`; with one camera there is
nothing left to gate on and `ON_FOOT` is the whole condition.

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

`mouse_left_button`/`mouse_right_button` are unclaimed by anything else on
foot. They used to carry a second, isometric meaning (click-to-move and
stop/cancel) read by a self-gated system; that system was removed with the
isometric camera on 2026-09-02, so each button now has one meaning.

`lock_on` searches the `lockable` group. Occlusion-aware target selection is
a known TODO, blocked on a raycast service that does not exist yet.

---

## 5. HOVER

Entered through `HoverEntryTrigger` (**hold** `interact` near a hover — see
`interact_hold_time` on the trigger). `Space` and
`Ctrl` are shared with `jump` / `crouch` by design — the modes are mutually
exclusive, so the bindings do not conflict at runtime.

| Action | Key | Description | RU |
|---|---|---|---|
| `move_forward` / `move_backward` | `W` / `S` | Thrust forward / reverse | Тяга |
| `move_left` / `move_right` | `A` / `D` | Strafe / yaw | Стрейф |
| `hover_up` | `Space` | Ascend; release engages altitude hold | Набор высоты |
| `hover_down` | `Ctrl` | Descend; release engages altitude hold | Сброс высоты |
| `toggle_view` | `V` | Camera `CHASE` ⇄ `COCKPIT` | Смена камеры |
| `interact` | `F` | **Hold** to exit — near-zero speed only | Выход |

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
| `debug_info` | `Enter` | Superseded by `toggle_stream_debug` |
| `crafting` | *(unbound)* | No binding and no reader |

---

## Notes

- `status` is bound with `device: 0` while every other action uses `-1`
  (any device). Harmless for keyboard, but inconsistent — worth normalising.
- Deadzone is `0.2` on every action.
