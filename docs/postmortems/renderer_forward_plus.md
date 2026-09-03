# The renderer constraint that contradicted itself for three weeks

**Invariant this belongs to:** `CLAUDE.md`, Hard constraints — "Renderer:
Forward+."

`CLAUDE.md`'s Hard-constraints section claimed the project ran **Forward
Mobile** and forbade Forward+ features outright. It had said so for roughly
three weeks while `project.godot` set no `renderer/rendering_method` override at
all — which means the Forward+ default applied — and while the header of the
same file said "Godot 4.7 (Forward+ renderer) project" four screens above.

The switch itself happened on **2026-07-21**: away from Forward Mobile,
accepting a ~20–25% FPS cost on the development machine in exchange for the full
lighting and post stack (volumetric fog, SSIL, SSR, `AreaLight3D`) that the
game's noir look depends on. The performance target is low-end integrated
graphics at ~55 FPS, so the budget stays tight and every effect is a real cost —
but Forward+ features are not off-limits, which is exactly what the stale
paragraph had been telling agents for three weeks.

Third recorded drift of this kind — see `documentation_drift.md`.
