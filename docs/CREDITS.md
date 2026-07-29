# Credits and third-party licences

Everything borrowed is listed here with its author, source and licence.
This file is updated in the same commit that adds an asset — not later.

The project's own licence is in `LICENSE`. Nothing on this page is covered
by it; each item below is governed by its own terms.

> **Anything on this page marked "must ship with builds" has to appear in the
> released game as well, not only in this repository.** See the last section.

---

## Engine

**Godot Engine** — <https://godotengine.org>
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
Licensed under the MIT License — <https://godotengine.org/license>

Godot also bundles third-party components under their own licences. The
complete, authoritative list is produced by the engine itself:
`Engine.get_license_text()` and `Engine.get_copyright_info()`.
**Must ship with builds** — the MIT notice accompanies the distributed
engine binary.

---

## Editor plugins

| Component | Author | Licence |
|---|---|---|
| Godot AI (`addons/godot_ai/`) | Godot AI contributors | MIT |

Editor-only. Not part of released builds.

---

## Fonts

| Font | Author | Licence |
|---|---|---|
| Averia Libre | © 2011 Dan Sayers | SIL Open Font License 1.1 |
| IM Fell English SC | © 2010 Igino Marini | SIL Open Font License 1.1 |
| Special Elite | © 2011 Astigmatic (AOETI) | Apache License 2.0 |
| CGF Locust Resistance | Chris Garrett | Free for personal and commercial use |
| BlackRock | Nolavel | Project asset — not for redistribution |

OFL: <https://openfontlicense.org> · Apache 2.0:
<https://www.apache.org/licenses/LICENSE-2.0>

**BlackRock** is a custom display typeface made for this project's visual
identity. It is covered by `LICENSE`, not by any open font licence, and is
not a general-purpose font.

**Must ship with builds** — OFL and Apache-2.0 both require their notices to
accompany distribution.

---

## 3D assets

| Asset | Author | Source | Licence |
|---|---|---|---|
| JUMPSUIT Low Poly | DanlyVostok | <https://skfb.ly/p8VJx> | CC BY 4.0 |

CC BY 4.0: <https://creativecommons.org/licenses/by/4.0/>
**Must ship with builds** — CC BY requires attribution wherever the work is
distributed, including inside the game.

---

## Textures

| Asset | Author | Source | Licence |
|---|---|---|---|
| Prototype Textures 1.0 | Kenney | <https://kenney.nl> | CC0 1.0 |

CC0 imposes no obligation; credited because Kenney asks and it costs nothing.

---

## Shipping these credits

CC BY, OFL, Apache-2.0 and the Godot MIT notice all attach to the
**distributed build**, not to this repository. Putting them only here does
not satisfy them.

Planned: an in-game credits screen fed from this file, plus Godot's own
licence text pulled at runtime via `Engine.get_license_text()`. Until that
screen exists, ship a `CREDITS.txt` alongside the executable containing this
file's contents.

Not yet done. Recorded in `docs/planned_scope.md`.
