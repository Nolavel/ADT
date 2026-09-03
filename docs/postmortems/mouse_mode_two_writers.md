# Two writers to Input.mouse_mode, and a camera that stopped at the screen edge

**Invariant this belongs to:** `CLAUDE.md`, Architecture rules — "Only
`InputSystems.gd` reads `Input` directly, and only it WRITES
`Input.mouse_mode`."

`MouseCursorUI` also set `Input.mouse_mode`, to `MOUSE_MODE_HIDDEN` while on
foot. `InputSystems` set `MOUSE_MODE_CAPTURED`. The two raced every frame, and
HIDDEN keeps the pointer inside the window — so the pointer hit the window edge
and the camera stopped turning. Stan reported it as "I can't rotate the
character past a certain point, left or right".

Measured 2026-09-02: `mouse_mode` reading **0** where `InputSystems` had asked
for **2**.

## The part worth remembering

I had seen `mouse_mode=1` in an earlier render probe and dismissed it as an Xvfb
artifact — a headless X server not granting pointer capture. It was the bug,
printing itself, one session early. Contrary evidence that is inconvenient is
not automatically environmental noise.
