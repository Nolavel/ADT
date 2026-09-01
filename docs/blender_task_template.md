# Blender MCP — Task Template
> Vertical Trespass / ADT. Use this template whenever asking Claude
> (Desktop or Code, via the Blender connector) to build or generate an
> asset in Blender. Pick ONE path below depending on the method.
> Style source of truth: docs/3D_ART_BIBLE.md — never freestyle style
> language, always point to it.

---

## Path 1 — Procedural / direct geometry (bpy Python via MCP)

Use when: building primitive-based meshes, kitbashing, batch operations,
modifiers, UV setup, materials, scene assembly — anything Claude builds
by running Python commands directly in Blender.

Style reference for THIS path: docs/3D_ART_BIBLE.md sections
**1 (Form Language), 3 (Environment), 4 (Vehicles), 5 (Props)**.
These are geometry rules, not prompt text — they describe hierarchy and
plane count, not a caption for an image model.

### Prompt skeleton

```
Read docs/3D_ART_BIBLE.md sections 1, 3, 4, 5 before building this —
they define the form hierarchy and plane logic for every object in the
project, not just this one.

Build in Blender via direct geometry (bpy):

OBJECT:            <name>
CATEGORY:           character | vehicle | building | prop
FUNCTION:            <what it does / why it exists in the world>
SILHOUETTE:          <one-line shape description>
PRIMARY FORMS:       <the 2-4 masses that carry 80% of the read>
SECONDARY FORMS:     <constructive elements — doors, vents, seams>
ACCENT DETAILS:       <3-5 max, per Art Bible discipline>
SURFACE DETAIL:      <only if truly necessary — justify>
POLY DENSITY TARGET:  middle-poly (see Art Bible §0 — not low, not photoreal)
MATERIAL NOTES:       <PBR base + painterly treatment, per §6>
REFERENCE STRATUM:    Doggerland | Manifold | Glare (if applicable)

Constraints:
- Geometry describes planes, not surfaces (Art Bible §1).
- No micro-detail carrying the style — silhouette + primary/secondary do.
- If this is a building: apply the layered hierarchy from §3 (main mass /
  infrastructure layer / upper volume).
- If this is a prop: object must read from silhouette + 3-4 forms alone
  (§5 — "visual icon" rule).
```

---

## Path 2 — AI generation (Hyper3D Rodin / text-to-3D via MCP)

Use when: generating a base mesh from a text description or reference
image through Blender MCP's Hyper3D integration, before manual cleanup.

Style reference for THIS path: docs/3D_ART_BIBLE.md section
**12 (formula for AI prompts)** — this is the actual prompt text,
copy near-verbatim as the Immutable Style block.

### Prompt skeleton

```
Read docs/3D_ART_BIBLE.md section 12 and use the Immutable Style block
verbatim as the base prompt. Do not paraphrase or shorten it.

STYLE IDENTITY
Stylized painterly middle-poly 3D. Graphic rather than photorealistic.
Anatomically believable but intentionally simplified. Strong readable
silhouettes. Large designed planes instead of micro-detail. Controlled
asymmetry. Muted industrial palette with selective saturated accents.
Character language inspired by Hanna Chie Stef: large facial planes,
graphic features, painterly skin treatment.

GEOMETRY
Medium polygon density. Primary forms must dominate. Secondary forms
explain construction. Avoid excessive bevels and micro-geometry.
No generic low-poly faceting.

MATERIALS
PBR-based but artistically simplified. Large color/value regions.
Controlled roughness. No photorealistic surface noise.

LIGHTING
Designed to reveal major planes. Soft cinematic light with controlled
contrast.

DESIGN
Dirty late-70s/80s science fiction. Industrial. Used. Functional.
Slightly grotesque. Cyberpunk without generic neon overload. Steampunk
influence without literal Victorian/steam machinery.

--- Asset Brief (fill in) ---
OBJECT:          <...>
FUNCTION:        <...>
ERA:             <...>
MATERIAL:        <...>
DAMAGE:          <...>
SILHOUETTE:      <...>
PRIMARY FORMS:   <...>
SECONDARY:       <...>
ACCENTS:         <...>
```

After generation: mesh MUST go through manual/Python cleanup pass
against Path 1's plane-hierarchy rules before it's considered final —
raw Hyper3D output is a starting point, not a finished asset.

---

## Never write (Art Bible §13 — forbidden phrasings)

Do not give Claude or Hyper3D any of these as a substitute for the
template above — they drift and lose the project's actual language:

- "Create a Disco Elysium cyberpunk character"
- "Make it like GTA Vice City"
- "Mid-poly cyberpunk"
- "Hanna Chie Stef style" (without unpacking the actual principles)

Always give the full hierarchy of constraints + a concrete Asset Brief.

---

## Quick decision: which path?

- Kitbashing from existing primitives / KayKit pieces / batch material
  work / UV or export automation → **Path 1**.
- Generating a brand-new base mesh from scratch with no starting
  geometry → **Path 2**, then Path 1 cleanup pass.
- Unsure → default to Path 1. It keeps full control over plane count
  and hierarchy, which is the actual style, not the prompt wording.
