# Vertical Trespass (Prok)

Noir open-world action prototype set in the vertical city of Blackrock.
Нуарный опенворлд-прототип в вертикальном городе Блэкрок.

**Engine:** Godot 4.7 (Forward Mobile) · GDScript
**Target:** playable demo — October 2026

---

## Запуск / Run

Основная сцена: **`world.tscn`** — игрок, камера, системы и стриминговый
конвейер города поднимаются автоматически (см. `world/world.gd`).

Main scene: **`world.tscn`** — player, camera, systems and the city
streaming pipeline are brought up automatically.

## Управление / Controls

Единственный источник истины по биндингам: **`input_map.md`**.
Кратко / summary:

**Пешком / On foot (ISOMETRIC ⇄ TPS — `V`)**
- ПКМ / RMB — идти к точке; удержание — бег (hold — run)
- `F` — взаимодействие: предметы, кнопки, посадка в ховер
- `Q` / `E` — шаг орбитальной камеры; `P` — следящая камера; колесо — зум

**Ховер / Hover**
- `W A S D` — тяга и стрейф (thrust / strafe)
- `Space` / `Ctrl` — набор и сброс высоты; отпустить — автоудержание
  (ascend / descend; release — altitude hold)
- `V` — камера CHASE ⇄ COCKPIT
- `F` — выход (только при остановке / near-zero speed only)

**Глобально / Global:** `Esc` — меню паузы.

## Структура / Layout

| Путь | Назначение / Purpose |
|---|---|
| `core/` | Автолоады и системы: PlayerState, InputSystems, стриминг, транспорт |
| `player/` | Сцена игрока и компоненты (интеракт, инвентарь, стамина) |
| `camera/` | Камера-хост + покомпонентные режимы (on foot / hover / transit) |
| `world/` | world.tscn, контент и силуэты кварталов и плит земли |
| `tools/` | Редакторские инструменты, в т.ч. генератор greybox-кварталов |
| `data/` | Ресурсы данных: `world_data.tres`, предметы (`data/items/`) |

## Редактирование мира / World editing

Источник данных мира — сцена **`map_source.tscn`** (маркеры кварталов,
точка спавна). При её запуске `world_data.tres` экспортируется заново.
Массовая генерация greybox-застройки: `tools/block_generator/`
(шаг A — библиотека блоков, шаг B — расстановка маркеров).

World data source — **`map_source.tscn`** (block markers, spawn point);
running it re-exports `world_data.tres`. Greybox mass generation lives in
`tools/block_generator/`.

## Для коллаборантов / For collaborators

Контекст проекта и соглашения по коду: **`CLAUDE.md`**, `input_map.md`.
Project context and code conventions: **`CLAUDE.md`**, `input_map.md`.
