# Morph icons — what they are and how to attach one

A **morph** is a small spring-driven glyph parented under a Button, saying what
that widget is doing right now: at rest, noticed, or held. Three dots is the
first one — idle is a horizontal line, hover an async wave, drag or pull a
clockwise circle.

The code is in the repository already. This document is for attaching a morph
to a widget in the editor, and for writing the next morph.

---

## 1. What is where

```
ui/widgets/morphs/
├── morph_icon.gd        # MorphIcon — the base class controllers type against
├── spring_point.gd      # SpringPoint — shared spring solver (RefCounted)
└── three_dots_morph.gd  # ThreeDotsMorph — first concrete morph, pure _draw()
```

`MorphIcon` owns the vocabulary (`Mode { LINE, WAVE, CIRCLE }`), the three
named shortcuts (`to_line()` / `to_wave()` / `to_circle()`), `get_mode()`, and
the static `MorphIcon.find_in(host)` lookup. A concrete morph overrides exactly
one method, `set_mode()`.

Controllers hold a `MorphIcon`, never a concrete type. That is the point of the
base class: a second morph is a new script in this folder and nothing else.

---

## 2. Which widgets can carry one

Any widget whose controller passes a morph into `setup()`. Today:

| Host | Controller | Wired |
|---|---|---|
| `btn_drag_handle` in `ui/ingame_menu/in_game_menu.tscn` | `DragHandleController` via `MenuController` | yes, node attached |
| `%Hammer` in `ui/main_menu/revolver_menu.tscn` | `RevolverHammerController` via `revolver_menu.gd` | yes, node attached |
| `btn_drag_handle` in `ui/settings/settings.tscn` | `DragHandleController` via `setting.gd` | not yet — the third argument is simply not passed |

**A morph is optional everywhere.** `find_in()` returning null is the ordinary
case, not a warning: the gesture has to work identically with no glyph
attached, and it does.

### What the controllers gained

Both `DragHandleController` and `RevolverHammerController` route every phase
change through `_set_phase()`, which emits a `phase_changed` signal and calls
`_sync_morph()`. Mapping is in §5. `get_phase()` is public for anything else
that wants to read it. No new autoloads, no changes to `PlayerState`,
`InputSystems`, or the scene bootstrap lists.

---

## 3. Scene wiring — pause menu (`ui/ingame_menu/in_game_menu.tscn`)

> Already done in the scene. Kept as the recipe for the next host, and for
> the one trap it contains — step 2.


1. Select `btn_drag_handle` (the centre handle, text was `"( )"`).
2. Clear its text — **and give the button a `custom_minimum_size`.** This is
   the trap: the handle's own anchors describe an 8x8 rect, and everything
   larger than that came from the text. Clear the text with nothing standing
   in for it and the button collapses to a nearly unclickable target. It is
   set to `Vector2(36, 36)` here, matching the morph.
3. Optionally make the button flat / transparent so only the morph shows:
   - Theme overrides or `flat = true`, modulate as needed.
4. Add a child **Control** node:
   - Name: `Morph` (the name is for humans; `find_in()` matches on type)
   - Attach script: `res://ui/widgets/morphs/three_dots_morph.gd`
   - Layout: full-rect of the parent (anchors 0–1, or centre with a fixed size e.g. 36×36).
   - Recommended exports for a small handle:
     - `spacing` = 8–10
     - `dot_radius` = 2.5–3.5
     - `circle_radius` = 8–10
     - `wave_amp` = 4–6
     - `auto_hover_wave` = **false** (controller owns modes)
5. Save. On open, `MenuController` finds the morph and hands it to `DragHandleController`.

Resulting tree (relevant part):

```
InGameMenu
├── btn_continue
├── btn_out
├── btn_settings
├── btn_last_save
└── btn_drag_handle          (Button, text empty)
    └── Morph                 (ThreeDotsMorph, a MorphIcon)
```

---

## 4. Scene wiring — main menu (`ui/main_menu/revolver_menu.tscn`)

> Already done in the scene. The hammer's `text = "PULL"` was cleared, which
> removes the only words that told a first-time player what to do with it —
> the morph is now the whole affordance. Worth a look in play.

The hammer is `%Hammer` (Button), 64x64 by its own offsets, so unlike the
pause handle it needs no minimum size. Same pattern:

1. Select `%Hammer`.
2. Clear text if any.
3. Add child Control `Morph` with `three_dots_morph.gd`.
4. Size ~36–48 px, centred on the hammer.
5. `auto_hover_wave = false`.

`revolver_menu.gd` is already wired — its `_ready()` calls
`MorphIcon.find_in(_hammer)` and passes the result through. Attaching the node
is the whole job; no script change is needed.

---

## 5. Behaviour map

| Gesture | Pause handle | Revolver hammer | Morph mode |
|---|---|---|---|
| Rest | IDLE | IDLE | LINE |
| Grab / pull | DRAGGING | PULLED | CIRCLE |
| Flight / strike | FLYING | STRIKING | CIRCLE |
| Return / land | IDLE | RETURNING → IDLE | LINE |

Hover-wave is available via `auto_hover_wave = true` on the morph itself, but leave it **off** when a controller owns the morph so the two never fight.

---

## 6. Writing the next morph

Extend `MorphIcon` and override one method:

```gdscript
class_name HamburgerMorph
extends MorphIcon

func set_mode(new_mode: Mode) -> void:
    if new_mode == mode:
        return
    mode = new_mode
    _apply_mode_targets(false)
```

`to_line()` / `to_wave()` / `to_circle()` / `get_mode()` come from the base and
route through your `set_mode()`, so there is nothing else to implement and no
way to reach a mode your override has not seen. Drop the new node under any
supported Button; **no controller changes** — that is what the base class is
for, and it is why the controllers do not name `ThreeDotsMorph`.

A morph that cannot express one of the three modes should still accept it and
pick its nearest reading rather than refuse — a controller must not have to
know which glyph it got.

`SpringPoint` stays shared. Do not reimplement spring maths per morph, and do
not add per-morph stiffness knobs: the whole family is meant to feel like one
thing (see that file's own header).

---

## 7. Style / project rules compliance

- Static typing, tabs, banner headers, English comments.
- No new autoload.
- No `Input.*` outside `InputSystems` (morph and controllers use GUI signals only).
- UI widget under `ui/widgets/` — self-contained, listed as safe work in `CONTRIBUTING.md`.
- Empty placeholder files not created.
- `CHANGELOG.md` and `CLAUDE.md` updated in the same commit, per this repo's
  own rule.

---

## 8. Quick verify

1. Open project, run `world/world.tscn` (or open pause menu / main menu stand).
2. Pause menu: handle shows three dots in a line; grab → dots spin on a circle; release → line again after flight.
3. Main menu: hammer same behaviour while pulling / striking.
4. No `push_error` / `push_warning` about missing morph (morph is optional; if absent, controllers behave as before).

---

## 9. Tuning knobs

On the Morph node in the inspector:

| Export | Pause handle (small) | Main hammer (larger) |
|---|---|---|
| spacing | 8–10 | 10–14 |
| dot_radius | 2.5–3.5 | 3.5–4.5 |
| circle_radius | 8–10 | 10–14 |
| wave_amp | 4–6 | 5–8 |
| wave_speed / circle_speed | leave defaults | leave defaults |
| color | `#e8edf2` or project accent | same |

Spring stiffness/damping live in `SpringPoint` constants — change only if the whole family of morphs should feel different. `SpringPoint.MAX_STEP` clamps the integrator's step; leave it alone unless you know why it is there (that file's header explains).
