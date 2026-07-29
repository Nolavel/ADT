# GDScript style

Follows the official Godot GDScript style guide. This file records only the
points where the project is stricter, or where the guide leaves a choice.

Source: <https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html>

## Formatting

- `.gd`: **tabs**, width 4. `.cs`: spaces, width 4. Enforced by `.editorconfig`.
- LF line endings, UTF-8, final newline, no trailing whitespace
  (`.md` files excluded from whitespace trimming).
- Two blank lines between top-level definitions, one between methods.
- Max line length 100 characters, soft.

## Naming

| Thing | Case | Example |
|---|---|---|
| File names | `snake_case` | `hover_entry_trigger.gd` |
| `class_name` | `PascalCase` | `InputHoverController` |
| Node names in scenes | `PascalCase` | `StreamContainer` |
| Functions, variables | `snake_case` | `set_move_intent()` |
| Private members | `_snake_case` | `_controller` |
| Constants | `SCREAMING_SNAKE_CASE` | `STREAM_CHECK_DISTANCE` |
| Enums | type `PascalCase`, members `SCREAMING_SNAKE_CASE` | `Mode.ON_FOOT` |
| Signals | `snake_case`, past tense | `interact_pressed` |
| Input actions | `snake_case` | `switch_shoulder` |

A file's name matches its `class_name` in snake_case. If it does not, one of
the two is wrong.

## Types

- **Static typing everywhere.** `var speed: float = 0.0`, `func f() -> void:`.
  Untyped declarations are not accepted in new code.
- Prefer `:=` inference when the right-hand type is obvious.
- Annotate exported variables explicitly:
  `@export var stream_radius: float = 1000.0`.

## Declaration order

1. `@tool` / `class_name` / `extends`
2. File header comment (see below)
3. Signals
4. Enums
5. Constants
6. `@export` variables
7. Public variables
8. Private variables
9. `@onready` variables
10. `_init`, `_ready`, `_process`, `_physics_process`, other engine callbacks
11. Public methods
12. Private methods

## Comments

Comments are written for a collaborator who has never seen the file, not for
the person who wrote it yesterday. **English only in new code.**

- **Every autoload, system and non-trivial component** starts with a banner
  header explaining *why the file exists* and *what contracts and invariants
  it relies on*. This is the project's most important convention — the
  streaming and world-geometry systems are unusable without theirs.
  Small helpers do not need one.
- Use `##` doc comments on public API — Godot surfaces them in the editor.
- Comment the *reason*, not the mechanics. `# clamp to avoid gimbal flip at
  the poles` is useful; `# clamp pitch` is not.
- `TODO(scope):` with a scope tag, never a bare `TODO`. A `TODO` that is not
  actionable belongs in `docs/planned_scope.md`, not in code.

## Scenes and nodes

- One responsibility per node. Components live under a `*_component/`
  directory and are named `*Component`.
- Do not use `get_node("../../Something")`. Use exported `NodePath`s,
  groups, or a signal.
- Do not add empty directories or `extends Node` placeholder scripts for
  work that has not started. Planned work belongs in
  `docs/planned_scope.md`. An empty file in the tree reads as a promise.

## Rules specific to this project

- No new autoloads.
- `Input.*` is called only inside `core/input/input_systems.gd`
  (exceptions: `core/map_source/`, `map_camera/`).
- Content is instantiated only by `StreamingSystems`.
- `PlayerState.mode` is never assigned directly from outside.
- Any change to input actions updates `input_map.md` in the same commit.
