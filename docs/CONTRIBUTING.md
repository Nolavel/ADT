# Contributing

Solo project with occasional short-term collaborators. This page tells you
what you can pick up, what you must not touch, and how work gets accepted.

## Before anything

1. Godot **4.7**, Forward+ renderer. Open the project, run `world/world.tscn`.
2. Read `../CLAUDE.md` — architecture, autoloads, and the contracts that must
   not be broken.
3. Read `GDSCRIPT_STYLE.md` — code conventions.
4. There is **no test framework**. "Tested" means: you ran the project and
   read Godot's output for `push_error` / `push_warning`.

## Language

Identifiers, file names, commit messages, documentation and **all new
comments** are in English. Existing comments are largely in Russian; they
are being translated header by header. Do not add new Russian comments.

If you cannot read a Russian header in a file you need to change, **ask
instead of guessing**. Those headers document invariants, not trivia.

## Open areas

Safe to pick up without deep context:

- **Block and ground-tile content.** Assemble scenes against the existing
  data contract (see below). Verified by running the game. Fully parallel.
- **Audio.** No audio system exists yet — a clean, self-contained seam.
- **UI widgets** under `ui/widgets/` — self-contained.
- **English editing** of comments and docs.
- **3D props** to written spec, outside the codebase.

Ask first — these need a spec from the owner:

- Hover camera tuning (`camera/camera_component/hover_camera_component.gd`)
- TPS combat camera occlusion — blocked on a raycast service that does not
  exist yet

Not open: anything listed in `planned_scope.md`. That page is a record of
intent, not a task list.

## Do not touch without asking

`core/world/streaming_systems.gd`, `core/world/world_systems.gd`,
`core/player_state/player_state.gd`, `world/world.gd`, `core/map_source/`.

These are load-bearing. Their invariants are documented in file headers,
and breaking them fails silently, not loudly.

## Contracts you must respect

- **`PlayerState.mode`** is only changed through its own API. `MENU` is
  entered and left via `open_menu()` / `close_menu()` — never by assignment.
- **`InputSystems` is the only place that calls `Input.*`.** Everything else
  subscribes to its signals or calls its query methods. Exceptions:
  `core/map_source/`, `map_camera/` (editor tooling).
- **`StreamingSystems` is the only owner of streamed content.** Do not
  instantiate world content anywhere else.
- **Strata layer naming.** A block content scene must contain
  `InstancePlaceholder` nodes named exactly `LayerDoggerland`,
  `LayerManifold`, `LayerGlare`. This is a name contract; violating it
  produces a warning and a missing layer, not a crash.
- **`GBX_` marker prefix.** Markers with that prefix are owned by the block
  generator and will be deleted on its next run. Drop the prefix to make a
  marker hand-owned.
- **`../input_map.md`** must be updated in the same commit as any input
  action added, removed or rebound.
- **No new autoloads.**
- **Attribute everything borrowed** — assets, references, code — in
  `CREDITS.md`, in the same commit that adds it.

## A note on Claude Code

CLAUDE.md isn't just documentation — it's a working brief for Claude Code, the AI tool the owner uses in the editor. If the tool pushes back on something from "Hard constraints" (renderer, autoloads, naming contracts), that's not the tool having an opinion — it's a decision the owner already made, just enforced automatically.
If a constraint seems wrong or outdated, raise it with the owner directly rather than arguing with the tool or working around it. The tool executes decisions, it doesn't make them.

## Scope rules

The project deliberately keeps the number of simultaneously live systems
small. Before proposing a new system, check that it serves at least two
existing ones. A mechanic that exists only for itself is not built.

Do not add placeholder scripts or empty directories for work that has not
started. Planned scope belongs in `planned_scope.md`. An empty file in the
tree reads as a promise.

Rejected ideas are recorded with a reason rather than discarded.

## Workflow

- Branch off `main`, one topic per branch.
- Commit messages: imperative, English, scope-first —
  `camera: clamp pitch in cockpit view`.
- Keep diffs small enough to read in one sitting.
- Open a PR describing **what you ran to verify it**, not just what you
  changed.
- If you had to leave a temporary solution: say so in the PR, with the
  reason and the condition for removing it. Undocumented workarounds are the
  only kind that are refused.

## Contributions and rights

This is a proprietary project (see [`../LICENSE.md`](../LICENSE.md))
intended for eventual commercial release.

By submitting a contribution you confirm that it is your own work, and you
grant the project owner a perpetual, worldwide, irrevocable, royalty-free
licence to use, modify, sublicense and distribute it as part of this
project, including commercially. You keep your own copyright and remain
free to use your work elsewhere.

Contributors are credited in `CREDITS.md`. If you would rather not be
credited, say so.

If you cannot agree to this, say so before starting — it is a fair position,
and it is better raised early than after the work exists.
