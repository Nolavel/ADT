# Visual language

How the game **looks and states things**, as opposed to how it works. This
document is for whoever draws, animates or art-directs Blackrock; the
implementation of everything described here lives in `CLAUDE.md` and in the
file headers, and is deliberately not repeated.

> Как игра выглядит и как она проговаривает события. Документ для художника
> и аниматора, а не для программиста.

---

## 1. The frame: comic, and noir, at once

Blackrock is presented as an **80s–90s comic book**. That is a frame around
the noir, not a replacement for it. The two agree more than they differ, and
where they touch, the comic sharpens what noir already wanted:

| | Noir asks for | The comic frame gives it |
|---|---|---|
| Light | High contrast, few sources | Flat blacks, hard edges, no soft midtones |
| Shadow | Hard, directional, dramatic | Shadow as shape, readable as silhouette |
| Explanation | None — the city does not explain itself | One large detail instead of a paragraph |
| Emphasis | Withheld, then sudden | The panel gets loud exactly once, then quiet |

The shared method is the important one: **a big detail instead of an
explanation.** A comic panel does not tell you a man is frightened; it draws
his hands. Blackrock does the same, and the onomatopoeia below is the one
place where the panel is allowed to make a sound about it.

This is not a pastiche of superhero comics. The register is closer to crime
and European album work of the period: heavy ink, restrained palette, and a
page that is legible at a glance.

---

## 2. Onomatopoeia is the voice of the panel, not the voice of the author

A floating word — `THUD`, `RUN`, `CALL` — is the frame registering that
something happened. It is not narration, not a hint, and not a feeling
handed to the player.

**It names the event. It never advises.**

| Allowed | Not allowed |
|---|---|
| `THUD` — a body hit the ground | `HE'S DOWN` — narrating for the player |
| `CALL` — someone is reporting | `RUN NOW` — instructing the player |
| `?` — an NPC did not understand | `SUSPICIOUS` — labelling a state |
| `…` — nothing was said | `TENSE` — assigning an emotion |

This is what keeps the device consistent with `core_loop.md`'s standing
rule that **the city does not explain itself**. A word that registers an
event adds no information the player could not have seen; a word that
interprets one is a HUD in disguise.

Tone: short, capitalised, no exclamation marks. English, like everything
else written in this repository.

---

## 3. The rule: a word marks an EVENT, never a STATE

This is a rule, not a preference.

**Events** — the word is allowed:
a punch lands, a body falls, someone dies, a witness starts reporting, a
report goes out, the player is hurt, the player runs out of breath, the
player raises his fists.

**States** — the word is forbidden:
walking, standing, watching, patrolling, being alert, being wounded, being
in COMBAT.

The reason is arithmetic, not taste. States are true for seconds or minutes
and would re-fire for as long as they hold; a screen that always has words
on it has no emphasis left to spend, and the device dies. The comic frame
gets loud once and then shuts up — that is exactly what makes the loud
moment mean something.

The practical consequence for anyone adding an effect: hook the **edge**,
the frame the thing changed, never a per-frame reading. A state that has
just been entered is an event; the same state, still holding, is not.

---

## 4. The gates are part of the language, not just optimisation

Two limits look like performance work and are actually art direction:

- **Distance gate** — an event further than its own radius from the player
  produces no word at all. A brawl fifty metres down the street is not this
  panel's subject. It happened; the frame simply is not about it.
- **Ceiling on simultaneous words** — a fixed maximum of words alive at
  once. A page with eight sound effects on it is a page with none.

Both exist so the frame keeps a subject. Raising them "because the system
can handle it" is a change to the visual language and needs the same
argument any other art-direction change would.

---

## 5. Sound is a separate layer

The comic word is **visual**. A future audio pass may key off the same event
identifiers — that is a convenience, not a coupling — but the effect
definition stays visual and must never grow a sound field.

A drawn `THUD` and a heard thud are two different statements about the same
event, and the game may well want one without the other.

---

## 6. The words are data

Every event's word pool, colour, size, duration and radius is a resource
under `data/comic_effects/`, one file per event, gathered by a catalog.

This is deliberate and load-bearing for this document's purpose: **the
vocabulary is expected to grow, and growing it is not a programming task.**
Editing a word list, retuning a colour, adding an event — all of it is done
in the inspector.

Current events, and the character each pool is written to:

| Event | Character |
|---|---|
| `npc_knockdown` | Dull, heavy — weight arriving |
| `npc_hit` | Short, an exhalation |
| `npc_death` | Quiet, nearly empty. **Kept deliberately small** — the silence works by scarcity |
| `npc_freeze` | Confusion, a look that stopped |
| `npc_flee` | Panic, but brief |
| `npc_call` | A message going to the city |
| `npc_transmit` | The signal itself, leaving |
| `player_hurt` | The player's own breath, through teeth |
| `player_death` | Quiet, like the crowd's |
| `player_winded` | Out of wind, not out of fight |
| `player_spent` | Nothing left to spend |
| `player_combat` | Fists up. The statement, not the fight |

---

## 7. Where this sits in the rest of the look

The comic layer is one device among several, and it should read as part of
the same design rather than an effect bolted on:

- **BlackRock**, the project's custom display typeface (`docs/CREDITS.md`),
  is the poster-weight voice of the game's identity. The comic word belongs
  to that same voice — heavy, flat, legible at a glance — not to the HUD's
  functional type.
- **The Votive projection** is the other thing in the build that speaks
  without a UI: a lit plane at an NPC's head that says *this one is
  transmitting*, readable across a street, turning with the body. Same
  principle as a floating word — a visible fact, not an explanation.
- **Archetype readability** (`docs/npc_archetypes.md` §3) — silhouette,
  gait, attention, and population mix — is the primary channel by which the
  crowd is legible. Note carefully that the **flat placeholder colours are
  scaffolding, not the design** (§4 of that document is explicit about it):
  they are a legend the player memorises, which is the very thing §3 exists
  to avoid, and they are to be replaced by cut, pace and alertness. Do not
  build new visual decisions on top of them.
- **Comic words and archetype channels answer different questions.** The
  channels say *who this is*, continuously and without a word. The comic
  layer says *what just happened*, once. Neither should start doing the
  other's job.

---

## 8. This grows

The event set and the word pools are both expected to expand as the core
loop does — reactions to intent, surveillance, advertising, strata-specific
behaviour all have moments that a panel might reasonably make a sound about.

What must not drift is section 3. Every new effect earns its place by
naming an event; the day the screen carries a running commentary, the device
is finished, and no amount of good words will bring it back.
