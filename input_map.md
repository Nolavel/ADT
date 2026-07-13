# Vertical Trespass — InputMap / Карта управления

> Актуально на: 2026-07-07
> Engine: Godot 4.6+ / GDScript
> Источник истины по режимам: `PlayerState.mode` (`ON_FOOT`, `VEHICLE_HOVER`, `TUBE_TRANSIT`, `MENU`),
> `PlayerState.view_mode` (`TPS`, `ISOMETRIC`, `TOPDOWN`)
>
> This document is the single source of truth for input bindings. Update it
> whenever an action is added, removed, or rebound in Project Settings → Input Map.
> Этот документ — единственный источник истины по биндингам ввода. Обновляйте
> его при любом добавлении/удалении/перепривязке action'а в Project Settings → Input Map.

---

## 1. Глобальные действия / Global actions

Работают вне зависимости от `PlayerState.mode`.
Work regardless of current `PlayerState.mode`.

| Action (Godot) | Клавиша / Key | RU описание | EN description |
|---|---|---|---|
| `pause` | Esc | Открыть/закрыть меню паузы | Open/close pause menu |

---

## 2. ON_FOOT — общие для ISOMETRIC и TOPDOWN / shared for ISOMETRIC & TOPDOWN

| Action (Godot) | Клавиша / Key | RU описание | EN description |
|---|---|---|---|
| `Mouse_Left_Button` | ЛКМ / LMB | Остановить движение / отменить цель | Stop movement / cancel move target |
| `Mouse_Right_Button` | ПКМ (клик) / RMB (click) | Идти в точку клика | Move to clicked point |
| `Mouse_Right_Button` (удержание / hold) | ПКМ, удержание >0.5с / RMB hold >0.5s | Перейти на бег к точке | Switch to running toward target |
| `Interact` | **F** | Подобрать/бросить предмет, активировать объект | Pick up/drop item, activate object |
| `lean_left` | Q | Орбитальная камера — шаг влево (дискретно) | Orbital camera — step left (discrete) |
| `lean_right` | E | Орбитальная камера — шаг вправо (дискретно) | Orbital camera — step right (discrete) |
| `zoom_in` | Колесо вниз / Wheel down | Приблизить камеру | Zoom camera in |
| `zoom_out` | Колесо вверх / Wheel up | Отдалить камеру | Zoom camera out |
| `toggle_view` | V | Переключить ISOMETRIC ↔ TOPDOWN | Toggle ISOMETRIC ↔ TOPDOWN |
| `toggle_follow` | P | Вкл/выкл слежение камеры за поворотом игрока | Toggle camera-follows-player-rotation |
| `toggle_tabs` | Tab (тап / hold) | Тап — уведомление; холд — статус-камера | Tap — notifier; hold — status camera |
| `Status` | X | UI-хоткей (потребитель ещё не реализован) | UI hotkey (consumer not implemented yet) |
| `Inventory` | I | UI-хоткей (потребитель ещё не реализован) | UI hotkey (consumer not implemented yet) |
| `Crafting` | G | UI-хоткей (потребитель ещё не реализован) | UI hotkey (consumer not implemented yet) |
| `Map` | M | UI-хоткей (потребитель ещё не реализован) | UI hotkey (consumer not implemented yet) |

**Примечание / Note:** click-to-move и орбиталка/зум/toggle_view — активны ТОЛЬКО в
`PlayerState.mode == ON_FOOT` и `view_mode in [ISOMETRIC, TOPDOWN]`.
Click-to-move and orbital/zoom/toggle_view are active ONLY when
`PlayerState.mode == ON_FOOT` and `view_mode in [ISOMETRIC, TOPDOWN]`.

---

## 3. ON_FOOT + TPS (отложено, не реализовано / deferred, not implemented)

WASD-движение вместо click-to-move. Переключение вида (`toggle_view`) сейчас
работает только между ISOMETRIC/TOPDOWN — включение TPS как отдельного
view_mode будет отдельной задачей.

WASD movement instead of click-to-move. `toggle_view` currently only toggles
between ISOMETRIC/TOPDOWN — wiring TPS in as a selectable view_mode is a
separate future task.

| Action (Godot) | Клавиша / Key | RU описание | EN description |
|---|---|---|---|
| `move_forward` | W | Движение вперёд | Move forward |
| `move_backward` | S | Движение назад | Move backward |
| `move_left` | A | Движение влево | Strafe left |
| `move_right` | D | Движение вправо | Strafe right |
| `jump` | Space | Прыжок | Jump |
| `sprint` | Shift | Бег | Sprint |
| `crouch` | C / Ctrl | Присед | Crouch |
| `Interact` | F | Тот же action, что в ISO/TOPDOWN — семантика не зависит от вида камеры | Same action as ISO/TOPDOWN — semantics don't depend on camera view |

---

## 4. VEHICLE_HOVER (контроллеры-заглушки, интерфейс зафиксирован заранее / stub controllers, interface reserved ahead of time)

Решение: клавиатурное управление (не мышь), заглушки-контроллеры уже есть в
`core/controllers/transport/base/hover_vehicle_base.gd` и подтипах
(car/van/bus/truck).

Decision: keyboard-only control (not mouse). Stub controllers already exist
under `core/controllers/transport/base/hover_vehicle_base.gd` and its
subtypes (car/van/bus/truck).

| Action (Godot) | Клавиша / Key | RU описание | EN description |
|---|---|---|---|
| `move_forward` | W | Тяга вперёд (переиспользуем action, режимы взаимоисключающие) | Throttle forward (action reused — modes are mutually exclusive) |
| `move_backward` | S | Тормоз/реверс (переиспользуем) | Brake/reverse (reused) |
| `move_left` | A | Руль влево (переиспользуем) | Steer left (reused) |
| `move_right` | D | Руль вправо (переиспользуем) | Steer right (reused) |
| `sprint` | Shift | Буст (переиспользуем) | Boost (reused) |
| `Interact` | F | Выйти из транспорта (переиспользуем — не заводим отдельный action) | Exit vehicle (reused — no separate action) |

**Примечание / Note:** `move_*`/`sprint`/`Interact` — те же Godot-action'ы, что
и в ON_FOOT. Конфликта нет: `PlayerState.mode` в любой момент времени только
один, и каждый контроллер сам решает, слушать ли сигнал/action, основываясь
на текущем режиме.

Same Godot actions as ON_FOOT. No conflict: `PlayerState.mode` is exclusive
at any given time, and each controller decides for itself whether to react,
based on the current mode.

---

## 5. TUBE_TRANSIT (низкий приоритет / low priority)

Единственное, что нужно на этом этапе — фрилук камеры. Никакого другого
взаимодействия.

The only thing needed at this stage is camera freelook. No other interaction.

| Action (Godot) | Клавиша / Key | RU описание | EN description |
|---|---|---|---|
| `Mouse_Right_Button` (удержание / hold) | ПКМ, удержание / RMB hold | Свободный обзор камерой | Camera freelook |

---

## 6. MENU (`PlayerState.Mode.MENU`)

| Action (Godot) | Клавиша / Key | RU описание | EN description |
|---|---|---|---|
| `pause` | Esc | Закрыть меню (Continue) | Close menu (Continue) |
| — | ЛКМ по кнопкам UI / LMB on UI buttons | Continue / Quit — обрабатывается кнопками, отдельных хоткеев нет | Continue / Quit — handled via buttons, no dedicated hotkeys |

---

## 7. Существующие конфликты и мусорные action'ы / Known conflicts & stale actions

| Action | Статус | Комментарий |
|---|---|---|
| `weapon_reload` | Висит на R (physical keycode 82) — раньше конфликтовал с `Interact`, конфликт снят переносом `Interact` на F. Оружия в игре пока нет — action держим про запас. |
| `debug_info` | Оставляем / kept | Служебный дебаг-хоткей, не относится к геймплейному InputMap. |
