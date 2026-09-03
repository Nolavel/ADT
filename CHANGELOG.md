# Changelog

Chronological work log for this repository. **This file records *when* things changed
and what is currently in flight.** For *how the project works right now*, `CLAUDE.md`
is authoritative — do not reconstruct current state by replaying this log.

Newest entries first. Each entry: what changed in substance, which systems/files it
touched, and — where relevant — which parallel track it came from.

> Хронологический журнал работ. Здесь — *когда* и *что* менялось; актуальное
> состояние проекта описано в `CLAUDE.md`, а не выводится из этого журнала.

---

## 2026-09-03 - CLAUDE.md carries invariants only; nine post-mortems (Task 4)

Every "this line previously claimed", every drift count, every dated measurement
left `CLAUDE.md` for a named file in `docs/postmortems/`, with one link back from
the rule it belongs to. 27 019 → 17 059 bytes. **All 53 invariants verified
present after the cut**, one at a time; two pre-existing broken links fixed on
the way (`INPUT_MAP.md` vs the real `input_map.md`). The plan's 8–10 KB target is
NOT met — what is left is rules, and going further means relocating them, not
deleting history.

> *`CLAUDE.md` теперь только инварианты; вся археология — в `docs/postmortems/`.*

---

## 2026-09-03 - CHANGELOG split: everything before 2026-08-15 into an archive (Task 4)

405 KB across 111 entries is a document nobody reads. Entries dated before
2026-08-15 move to `CHANGELOG_2026-07..08.md` (129 KB, 17 entries plus the
condensed pre-07-20 list); the main file keeps six weeks and a link. Cut by
section boundary, not line number: "Parallel tracks currently in flight" is live
state, not a dated entry, and stays. Verified by reconstruction — the two files
concatenate back to the original byte for byte.

> *Записи до 2026-08-15 вынесены в архив; сверено побайтово.*

---

## 2026-09-03 - docs/postmortems/ exists, and the camera audit moves into it (Task 4)

The third documentation genre finally has a place. `tps_camera_single_mode_audit.md`
— 74 KB about a migration finished on 2026-09-02 — is a record of a decision, not
a description of a live system, so it moves with no content edits. The three
documents that linked to it are updated in the same commit, and
`docs/postmortems/README.md` states the three-genre split the rest of Task 4
acts on.

> *Заведён `docs/postmortems/`; аудит камеры переехал туда без правок текста.*

---

## 2026-09-03 - Correction: 20 untyped returns in game code, not 35

The count in the Task 3b entry below was wrong, and wrong in my own favour: the
grep behind it read only the FIRST line of each signature, and 15 functions
carry their `-> Type:` on the closing line of a multi-line declaration. Real
figure is 20, in three files — `target_indicator.gd` 15, `camera_follow.gd` 4,
`navigation_component.gd` 1. The work plan's "15 in target_indicator.gd" was
exact all along; its "38 outside tools/" is the one that does not reproduce.

> *Число было завышено почти вдвое: grep смотрел только первую строку сигнатуры.*

---

## 2026-09-03 - Typing warnings on, and what they do NOT do (work plan Task 3b)

`project.godot` had no `[debug]` section at all; `untyped_declaration` and
`unsafe_method_access` are now warnings (not errors — that flip is Stan's call).
Measured, not assumed: a deliberately untyped function in an AUTOLOAD produced
**zero** lines on both `--headless --editor` and `--headless`, so these are the
editor's Script panel only and CI cannot see them. Untyped returns: **20** in
game code (15 of them in `target_indicator.gd`) — see the correction below.

> *Предупреждения о типизации включены, но видны только в редакторе — в CI их
> нет. 35 мест в игровом коде.*

---

## 2026-09-03 - The tick and the F badge are a sequence now, not a pile

The F badge came up on "a target exists" with no distance test, so from
`intent_radius` 2.5 m it and the floating tick were up together and overlapped —
measured on a render frame at 2.00 m, the tick sits inside the plate. Gated on
`is_target_in_reach()`, plus the event that was missing:
`InteractableObject.on_reach_changed()` — detected/lost only fire on a change of
TARGET. Fixed the tick's shared-tween race, which this makes frequent.

> *Галка и F больше не висят вместе: далеко — галка, вплотную — F вместо неё.*

---

## 2026-09-03 - The orphan grain effect, wired up and renamed (work plan Task 3a)

`ui/hud/fade_by_distance/` → `vfx/grain_effect/`, and it draws now: a scene, a
`ShaderMaterial` on the same-named shader that was already sitting unused in
`vfx/shaders/`, and one line at the TOP of `WORLD_UI_SCENES` so its
`SCREEN_TEXTURE` is the 3D world and the HUD stays crisp above it. Player comes
through `on_world_ready()`; the pause hookup that waited on a `fog_effect_toggled`
nobody emits is now `PlayerState.mode_changed`. Author's numbers untouched.

> *Сирота `fade_by_distance` переименована в `grain_effect`, переехала в `vfx/`
> и наконец подключена к миру. Числа автора не тронуты.*

---

## 2026-09-03 - Physics interpolation, and which half of it was actually visible (work plan Task 2)

`reset_physics_interpolation()` now runs on both streaming paths and in the
player's new `teleport_to()` — the single funnel for the two discontinuous
position writes (spawn, hover exit). Interpolation is OFF on the camera, which
already smooths itself. Render probe before/after: the camera override is the
whole visible change (15% of frame 1), the resets moved 0.02% — insurance, not
a measured fix. `HoverTest`'s override was `= 1` (ON, not OFF): a no-op, removed.

> *Сброс интерполяции в стриминге и в телепортах игрока; на камере выключена.
> Замер показал: видимую разницу дала только камера.*

---

## 2026-09-03 - docs/NOW.md, the chat/code handoff (work plan Task 0)

`CHANGELOG.md` stopped being the sync point at 396 KB across 106 entries — two
external reviewers both called `PlayerPersistenceSystem` missing while it sits
in `world.gd:64`. `docs/NOW.md` replaces it for that job: four sections, 80-line
ceiling, read first and written last. `CLAUDE.md` gains two lines pointing at it
and capping entries here at 3–6 lines.

> *Файл передачи между чатом и кодом; записи в этом журнале — не длиннее 6 строк.*

---

## 2026-09-02 - Three playtest regressions, and the one I had reasoned about instead of measuring

Stan reported three things after playing. Two were mine and both came from
assumptions I never checked; the third turned out not to be the bug he
described, and the real one underneath it was worse.

**V did nothing, and so did jump, stance, lock-on and shoulder swap.** The
edge latch introduced with the event-driven input rewrite stored
`Engine.get_physics_frames()` and expired an entry once the counter moved past
it. That depends on knowing exactly when Godot ticks that counter relative to
input flushing — which I reasoned about rather than measured, and got
backwards. Measured: **six synthetic `toggle_view` taps produced six latches
and zero reads.** Every polled edge in the project was dead. Replaced with a
latch that carries no arithmetic at all: an event files the action as `false`,
the top of the next physics frame promotes it to `true`, the frame after drops
it. Costs one frame of latency and has nothing left to be wrong about. Now
5 taps → 5 latches → 5 `view_mode_changed`.

**The camera stopped turning at the screen edge**, because `MouseCursorUI` was
a SECOND writer of `Input.mouse_mode` — `MOUSE_MODE_HIDDEN` on foot, left over
from the isometric era. HIDDEN keeps the pointer inside the window, so
relative motion stops with it. Measured on the running build as `mouse_mode`
0 where `InputSystems` had asked for 2. The widget now decides only its own
`visible`; `CLAUDE.md`'s "only InputSystems touches Input" rule gained the word
WRITES. **I had this evidence a day earlier** — a probe printed `mouse_mode=1`
and I wrote it off as an Xvfb artifact instead of following it.

**Reload: the reported symptom was real, the cause was not what it looked
like.** Through the real key path, standing / after a shot / while walking, a
single press reloaded correctly every time — so the bug was not in the input
or the request buffer. Under the render probe's single-digit frame rate it
failed exactly as described, and that is the actual fault: `AnimationTree`
updates on the IDLE frame while the punch/shot/reload machines run in
`_physics_process`, so "the one-shot is not active" and "it has not started
yet" read identically. The one-frame grace guarding that was enough at a
comfortable frame rate and is a coin toss at 55 FPS against 60 Hz physics.
Measured: one physics frame after a reload started, `_is_reloading` was true
and `is_weapon_gesture_active()` false — so the next frame ended the reload
before its refill landed. All three machines now latch a `*_gesture_seen` flag
before they are allowed to test for the end, with `GESTURE_START_GRACE` as the
backstop. Backward control in the same low-frame-rate environment: `3/8,
reserve 80` before (never applied), `8/8, reserve 75` after.

**Two smaller reload fixes on top.** A second press while a reload is already
running is no longer buffered — it used to queue a second full reload, running
the gesture twice and spending the reserve twice for one intent, which is why
the second press appeared to be the one that worked. Proven by the reserve
delta: pressing twice now costs **−2**, not −4. And the row shows the magazine
filling while it fills (`AmmoIndicator.begin_reload()`, a third colour that
never lets a filling magazine look like a full one) — the refill lands 1.2 s
into a 1.875 s gesture and nothing on screen moved before it, which is what
made a working reload feel broken.

Touched: `core/input/input_systems.gd`, `player/player.gd`,
`ui/hud/ammo_indicator/ammo_indicator.gd`, `ui/hud/player_hud/player_hud.gd`,
`ui/widgets/dynamic_cursor/dynamic_cursor_ui.gd`, `CLAUDE.md`,
`docs/architecture/autoloads_and_bootstrap.md`.

> *Три регрессии с плейтеста. V не работала — и вместе с ней прыжок, стойка,
> захват цели и смена плеча: защёлка ребра считала кадры физики, а я эту
> арифметику придумал, а не замерил. Замер: шесть нажатий — шесть защёлок, ноль
> чтений. Камера упиралась в край экрана, потому что курсор оказался вторым
> писателем `mouse_mode` и ставил HIDDEN — улику я видел днём раньше и списал
> на Xvfb. Перезарядка с одного нажатия работала везде, где я мерил, и ломалась
> на низком FPS: AnimationTree считается в idle, а машина состояний в физике,
> поэтому «не активен» и «ещё не начался» — одно и то же чтение. Теперь все три
> жеста ждут подтверждения старта. Плюс второе нажатие больше не заказывает
> вторую перезарядку, и обойма видимо заполняется, пока заполняется.*

---

## 2026-09-02 - Interact affordance: the hover door speaks, both halves are asserted the same way, the press has a payoff

**The hover door said nothing, and it was measured before it was fixed.** A
probe standing the player in each interaction zone reported: hover door — key
claimed, no F panel, no decal; lodging bed and carbine — both fine. So the
lodging room was never broken, and the hover was broken in two independent
ways at once:

1. `HoverEntryTrigger` only raised the panel inside `on_interact_claimed()`,
   i.e. after the player had already pressed F. It now goes up on ARRIVAL and
   comes down on leaving; releasing the key early rolls the ring back without
   taking the door's label away.
2. `InteractComponent` called `hide_prompt()` on every frame the key was
   claimed, stomping whatever the claimant had just raised. "Silent while
   claimed" now means silent — neither shows nor hides.

**The two halves of one affordance were driven differently, and that was a
bug.** The decal came from an EDGE (`interact_target_changed`), the panel from
a per-frame call. Anything that hid the decal therefore won permanently, with
no edge left to raise it again — reproduced as the F panel over the lodging
bed with no decal under it after walking past a hover door. Both halves are
now re-asserted every physics frame. `HUDComponent` READS `InteractComponent`
rather than being pushed by it, so the dependency still points the way it
always did: what finds things does not know who draws them. A key claimant
overrides through `show_candidate_at()` while it owns the key.

**A latent teardown cycle surfaced on the way and is worth recording.**
Removing `HUDComponent`'s reference to `InteractComponent` — dead once the
signal path went — turned the headless boot from silent into `27 resources
still in use at exit` plus 61 leaked `GDScript`/`GDScriptNativeClass`
instances, reproducibly, with no callers involved. Restoring the reference
(now genuinely used, for the read) makes it silent again. The cycle was not
created by this change, only exposed by it; it is not chased down here.

**`TargetIndicator` transitions are idempotent now**, which the class already
claimed in its own comment. `_disappear()` used to `await tween.finished`
before clearing `is_visible_indicator`, so during the 0.15 s fade every call
started another tween. Harmless while the decal was hidden once per edge;
per-frame assertion turned it into a tween per frame. The intent flips
immediately and an in-flight transition is killed rather than raced.

**The press has a payoff.** The morph existed but nothing announced the press
itself: a tap ran F → circle → dot in idle white with the glyph not turning,
because `_holding` was only ever set by the hold path. A press now punches the
plate inward, flips the register to active, spins the glyph while the morph
runs, and the finished dot throws a ring that expands and fades. Rendered and
looked at as four frames — nothing / candidate / press / burst.

**The F prompt moved into the world.** It was a `Control` on the UI canvas
unprojecting its anchor every frame, which drew it at a constant pixel size
however far away the object was — a label pinned to the glass rather than a
sign standing next to the thing. The same Control and the same `_draw()` now
render into a `SubViewport` carried by a billboarded `Sprite3D` at the anchor,
so nothing about the picture was rewritten and perspective scale, real
placement and depth ordering come for free. Rendered at 1.3 m and 2.3 m to
confirm it actually scales. **Always on top** (`no_depth_test`) — Stan's call:
the prompt is a statement the game is making, not an object in the scene, and
a depth-tested badge at chest height is lost behind the player's own shoulder
constantly.

**The entrance is travel, not a fade**, and that is the "галка плавно меняется
на F" part: the badge rises out of the ground decal and sinks back into it,
growing from `seated_scale` on the way, so the marker and the letter read as
one affordance with two stages rather than two notifications. `HoldPrompt`
moved from `WORLD_UI_SCENES` to `WORLD_3D_ENTITY_SCENES` with it.

**Stamina keeps a floor under its opacity** (`arc_min_alpha`, 0.35). The
ported rule was alpha = the remaining ratio, so the ring faded toward
invisible exactly as it ran out. Raised on the six-state render rather than
changed silently, because it was the original's behaviour; Stan's call was the
floor. Arc length still reaches zero and the ramp still runs to red, so
"almost nothing left" reads the same — it just stays legible while saying it.

Touched: `core/controllers/transport/hover_entry_trigger.gd`,
`core/ui/target_indicator/target_indicator.gd`,
`player/player_components/interact_component/interact_component.gd`,
`ui/hud/stamina_gauge/stamina_gauge.gd`, `ui/widgets/hold_prompt/hold_prompt.gd`,
`vfx/hud_component/hud_component.gd`.

> *У двери ховера не было ни F, ни декали — замерено пробой, а не на глаз:
> подсказка поднималась только ПОСЛЕ нажатия, а InteractComponent каждый кадр
> её гасил, пока клавиша захвачена. Комната, вопреки жалобе, работала. Обе
> половины подсказки теперь утверждаются одинаково — каждый физический кадр, и
> HUD читает InteractComponent, а не наоборот. По дороге вылез скрытый цикл в
> графе скриптов (27 ресурсов на выходе) — записан, но не выкорчёван. Нажатие
> получило отдачу: просадка таблички, жёлтый регистр, поворот и всплеск кольца.
> У стамины появился порог прозрачности 0.35.*

---

## 2026-09-02 - The isometric camera is gone; one TPS with two framings, Q/E lean

**The migration the 2026-08-30 audit was written for, carried out.** Removed:
`IsometricCameraState` (1278 lines), `isometric_camera_debug_overlay.gd` and
the `IsoCameraDebug` node, every ISO branch inside `OnFootCameraComponent`
(2023 lines → 637, taking the orbit and follow-rotation code the audit had
already found unreachable), `ClickToMoveSystem`, `ZoomRulerSystem` and
`vfx/hud_component/zoom_ruler/`, the `zoom_in` / `zoom_out` / `toggle_follow`
actions, and the move-destination indicator.

**Deliberately NOT removed**, exactly as the audit warned: `NavigationComponent`
and `player.move_to_position()`. `InteractComponent`'s auto-approach walks on
them; only the click handler died. The candidate decal stays too — it is about
interaction, not about clicks.

**`ViewMode` survives as a FRAMING, not as a camera.** `TPS` / `TPS_WIDE`:
one camera, same distance, same pitch, same occlusion, differing by a lens
shift (`h_offset`/`v_offset`) that puts the character low and to one side.
Stan's constraint verbatim — *"только смещение, дистанция та же"*. One eased
scalar replaced the whole view-transition machinery (zoom animation, pitch
retarget, the `view_mode_animating` gate the position pass had to know about).
**Only the camera reads `view_mode` now**: movement, mouse capture, head-look,
the cursor and the HUD decals all lost their branch in the same commit rather
than keeping a distinction that no longer exists.

**Occlusion inherited the sphere cast, its two lengths could not come with
it.** `cast_motion()` replaced a ray once already, for a recorded reason, so
carrying the ray into the last camera would have been an unrecorded rollback.
But `ISO_COLLISION_MIN_DISTANCE` 3.0 was sized for a 10–17.5 m orbit, and on a
2.2 m boom it would have disabled occlusion outright through the probe's own
early-out. Re-derived to 0.70 with a 0.30 radius, and flagged as the part most
in need of eyes on a real corridor.

**Q/E are a lean, measured before it was written.** `new4/aim-lean-l` /
`new4/aim-lean-r` exist and every rotation track in them is CONSTANT across
2.083 s — held poses, not lean-in/lean-out, which is what makes two chained
`AnimationNodeBlend2` the whole implementation. Rendered and looked at: they
are *aiming* leans, and with empty hands the character reads as miming a
rifle, so the body leans only in `COMBAT` while the camera leans always.

**The wide framing's distance stopped being fixed, and that was measured too.**
It shipped as "offset only, same distance" per the decision, then Stan sent the
reference frame it is meant to match. Measured against a render at the
reference's own 2:1: the character sits **6.8%** in from the left edge at
**~29%** of frame width there, against **20%** and **~14%** from a lens shift
alone. A lens shift moves a subject across the frame; it cannot make them
bigger, so the two requirements could not both hold and the distance became an
export. Counter-intuitive finding from the same pass: moving in needs a
*smaller* `h_offset`, since the same shift throws a bigger subject further off
frame — at 1.2 m with `h` 0.90 only a shoulder was left in shot. Defaults are
Stan's pick of three rendered candidates: **1.30 m / h 0.40 / v 0.20**,
deliberately short of the reference's exact scale, because at 1.1–1.2 m the
figure fills a quarter of the frame permanently and the near plane starts
clipping the shoulder. `wide_distance = TPS_DISTANCE` restores the original
behaviour exactly — the term is written as a difference for that reason.

Touched: `camera/` (three files deleted, `on_foot_camera_component.gd`
rewritten), `core/movement/`, `core/ui/`, `core/input/input_systems.gd`,
`core/player_state/player_state.gd`, `player/player.gd` and its animation
component, `vfx/hud_component/`, `world/world.gd`, `project.godot`,
`data/key_hints.tres`, `input_map.md`, `readme.md`, `ARCHITECTURE.md`,
`CLAUDE.md`, `docs/architecture/*`, `docs/scope_horizon.md`,
`docs/planned_scope.md`, `docs/core_loop.md`, `docs/NPC_REACTIONS.md`.

Verified: import ×2 clean, `world.tscn` boot clean (one long-standing warning
left, one fewer than before — the anchors warning came from the deleted
overlay); framing, both leans and the wide view rendered under Xvfb and looked
at; mouse capture confirmed on a real display (not visible on foot, visible in
menu). The auto-approach probe walks 0 m headless — **and so does the same
probe on pre-migration `main`**, because navigation is disabled without a
`NavigationRegion3D`, so that is the environment and not a regression; what it
does prove is that `move_to_position()` still sets an active path, identically
on both sides.

> *Изо-камера удалена целиком вместе с click-to-move, зумом и линейкой;
> `OnFootCameraComponent` ужался с 2023 строк до 637. Второй режим остался, но
> это тот же TPS со сдвигом линзы — герой уходит в нижний левый угол, дистанция
> та же. Окклюзия унаследовала сферу из изо, но её длины пришлось пересчитать:
> изометрический минимум 3 м на плече 2.2 м просто отключил бы проверку. Q/E —
> наклон: клипы замерены (это статические позы), тело наклоняется только в
> COMBAT, потому что клипы прицельные и с пустыми руками выглядят как имитация
> винтовки. Дистанция wide перестала быть фиксированной: замер по референсу
> показал, что сдвиг линзы двигает героя по кадру, но не делает его крупнее —
> 6.8% от края и 29% ширины в референсе против 20% и 14% при одном сдвиге.
> Дефолт 1.30 м / h 0.40 / v 0.20, сознательно не доведён до масштаба
> референса.*

---

## 2026-09-02 - Reload measured instead of guessed; stamina leaves the world for the HUD; input reads edges from events

**The reload bug was mine, and it was arithmetic.** "R only loads on the third
or fourth press" survived two previous attempts because both of them fixed
something else. This time the clips were measured: `new3/rifle_shot` is
**1.167 s** and `new3/rifle_reload_2` is **1.875 s**, plus the
`weapon_oneshot`'s 0.1 s fadeout — while the reload request buffer added on
2026-08-28 was a flat **0.6 s** countdown. A reload asked for right after a
shot therefore expired about half a second before the hands were free, every
single time. The buffer is now bounded by the BLOCK rather than by a clock:
`player.gd` holds the request while something is genuinely in the way and
retries on the first free frame, with `RELOAD_REQUEST_MAX_WAIT` (4 s) as a
ceiling against a gesture that never reports finished, not as a tuning knob.
Proven end to end by a probe that fires a shot, presses R 0.2 s in, and
measures the wait: **0.990 s — dropped by the old window, kept by the new
one**, magazine 6 → 8, reserve 80 → 77.

**Input now reads edges from events.** `InputSystems` polled
`Input.is_action_just_pressed()` 21 times inside `_physics_process()`. Measured
honestly, that is **not** what broke reload — at the project's 60 Hz physics
the poll path loses nothing — but it is lossy the moment the idle and physics
rates diverge (120 synthetic taps arrive as **42** at 5 Hz physics, and as
**120** through the event path at every rate tested). Keyboard actions moved to
`_unhandled_input()` (GUI keeps first refusal, where `pause` already lived),
mouse buttons to `_input()` (polling ignored GUI consumption, and moving them
behind it would change which clicks reach gameplay), matched with separate
`if`s because wheel up drives both `zoom_out` and `lodging_hours_up`. Query
methods that must stay polls are answered from an edge latch expired at the
top of the physics frame — autoloads run before scene nodes, so clearing at the
bottom would erase it before `camera_follow.gd` looked.
`is_zoom_*_just_released()` became `is_zoom_*_tick()`.

**Stamina moved from the ground into the HUD.** The ring drew over the player,
and that was a direct consequence of the `depth_test_disabled` added to keep it
from sinking into the terrain — a trade, not a fix. `StaminaIndicator3D` is
deleted; `ui/hud/stamina_gauge/` draws the same effect set as the first cell of
`PlayerHUD`'s health row, restored from commit `e40eab4`: four quarter arcs
that close into a ring at full stamina, the cool → yellow → orange → red ramp,
both recovery sweeps with pulse and inner glow, the jump-charge arc, and the
walk/sprint icon **inside** the ring. On a flat canvas there is nothing to draw
over, so the defect is absent rather than tuned away. Six states were rendered
and looked at under Xvfb before this was called done.

Touched: `core/input/input_systems.gd`, `player/player.gd`,
`player/player.tscn`, `camera/camera_component/on_foot_camera_component.gd`,
`ui/hud/stamina_gauge/` (new), `ui/hud/player_hud/`,
`core/ui/target_indicator/target_indicator.gd`, `ui/widgets/`, `CLAUDE.md`,
`docs/architecture/autoloads_and_bootstrap.md`,
`docs/architecture/player_and_camera.md`.

> *Перезарядка: причина найдена измерением — клип выстрела 1.167 с, а окно
> буфера было 0.6 с, поэтому запрос истекал раньше, чем освобождались руки;
> теперь ожидание ограничено самой блокировкой, а не таймером. Ввод читает
> дискретные нажатия из события, а не опросом (замер: 120 нажатий → 42 при
> опросе на 5 Гц физики, 120 через события на любой частоте) — но честно: не
> это ломало R. Стамина ушла с земли в HUD рядом с health, эффекты подняты из
> коммита `e40eab4`, иконки — внутри кольца; рисование поверх игрока исчезло
> вместе с плоскостью в мире.*

---

## 2026-08-29 - The stamina ring, looked at properly; H6 measured against its own Definition of Done

**Two real defects in the ring, both found by rendering it rather than by
reading it.** The previous round restored the arc geometry and the alpha, but
nobody had actually looked at the result:

- **`band()` had no flat part.** It was
  `1.0 - smoothstep(0.0, width, abs(d - target))` — a gradient spanning the
  whole width, so at any thickness worth seeing it drew a blurred donut
  rather than an arc. Widening `arc_thickness` in the last round therefore
  made it *worse*, not better. It is now a real band: flat across its
  thickness with a small feather at each edge, and the thickness came back
  down to 0.13 m.
- **`ring_glow` at 2.2 saturated the colour away.** The ring blends additive,
  so 2.2× drove every hue to white and the full → yellow → orange → red ramp
  simply did not survive. 1.5.

**All five states verified on screen**, each forced in a probe and rendered:
full and moving (closed cool ring), draining (arcs opening, ramping yellow),
low (four short red arcs), recovering (two chasing green sweeps plus the
restored inner glow), and jump charge. The recovery inner glow — the piece
the original port dropped — is visibly there.

The probe itself had to be corrected twice, and both were the same kind of
mistake: forcing `_stamina_ratio` while the indicator's own `_process` was
still recomputing it from `StaminaComponent` every frame, and rendering onto
a WHITE floor, where an additive ring saturates to white and a red ring looks
grey. A test scene that does not resemble the real one answers a different
question.

**H6 measured.** Six of the seven Definition-of-Done clauses were driven in a
probe rather than judged by eye, and all six pass: found on the island,
picked up, kept across a save/load (slot *and* spent magazine), drawn and
holstered, fired at an NPC with damage through `HealthComponent` (100 → 0),
and entered in `IncidentRegistry`. The seventh — **carried while moving** —
is the one clause headless cannot answer, and it is now stated as the only
thing H6 is held for. The horizon is renamed **"Carbine chain"**.

Three probe bugs worth naming, because all three are language traps rather
than typos: a lambda capturing a local **by value** (so `shot_landed` read as
a miss while the target took 100 damage), `HealthComponent` exposing
`current_health` as a property and not a getter (both readings came back
`-1`), and `IncidentRegistry` only wiring itself to `shot_landed` inside
`on_world_ready()` — present but deaf until called, which read as an unmet
requirement.

*Две настоящие ошибки в кольце, обе найдены рендером, а не чтением: `band()`
не имел плоской части и давал размытый бублик вместо дуги, а `ring_glow` 2.2
при аддитивном смешивании выжигал цвет в белый. Все пять состояний проверены
картинкой, включая вернувшееся внутреннее свечение восстановления. H6 измерен
по своему же определению готовности: шесть пунктов из семи проходят пробой,
седьмой — «носится в движении» — headless проверить не может, и теперь именно
он назван единственным, ради чего H6 держат открытым. Горизонт переименован в
«Carbine chain».*

- `player/player_components/stamina_indicator/stamina_indicator_3d.gd`,
  `docs/scope_horizon.md`

---

## 2026-08-28 - Playtest round 3: arcs for brackets, the stamina ring put back, a buffered reload

**The stamina ring is restored from the ORIGINAL, not re-invented.** Stan said
it still is not the effect it was and that reading how it used to be would
make it clear. It did — `git log -S"_draw_sprint_arcs"` produces the 2D
version, and three of the differences were mine:

- **The four arcs were never meant to stay separate.** The original drew
  `quarter_length = PI * 0.5 * ratio` from each quarter's start, so they MEET
  into a closed ring at full stamina and open into four arcs as it drains.
  The `arc_gap` added a day earlier kept a permanent wedge empty so "four
  arcs read as four" — a change to the design dressed up as a fix. Removed.
- **The alpha was decided twice.** The original set it once
  (`ratio` moving, `ratio * 0.5` at rest). The shader was multiplying it
  again. That second factor is gone, and the rest value is back to the
  original 0.5 — which now actually means half.
- **`arc_thickness` was declared and never used**, with 0.10 hard-coded in
  the shader. The 2D version drew 6 px arcs on a 12 px radius — half the
  radius. Wired up and widened to 0.22 m, which is most of what "not the
  effect it was" meant: it was a hairline.

  Also restored: the recovery **inner glow**, a soft disc breathing with the
  same pulse, which the port dropped entirely and without which recovery is
  two thin sweeps that read as noise.

**The ring can no longer be hidden by the ground it lies on.**
`depth_test_disabled` plus `ground_clearance` 0.18 → 0.30. On a slope it was
disappearing into the terrain — "sometimes it is not visible".

**The aim brackets are arcs.** Segments of a circle centred on the cursor, so
both bow away from the target with their tips pointing at it. Three straight
lines read as a UI frame; an arc reads as something closing on a thing. The
`bracket_height` / `bracket_width` exports keep their meaning — height sets
how much of the circle is covered, width the stroke.

**A reload asked for a fraction of a second early is no longer thrown away.**
"Reload works, but sometimes R has to be pressed twice" was the press landing
inside another gesture — mid-punch, mid-shot, or with movement locked — where
it was silently discarded. It is now buffered for `RELOAD_BUFFER_TIME`
(0.6 s) and retried the moment the hands are free. A window rather than a
queue: a reload wanted a second ago is intent, one wanted five seconds ago is
a stale keystroke firing by itself. The gate itself moved into `_begin_reload()`
so the key press and the buffered retry run the same path rather than two
copies that drift.

**Packaging.** `main` had taken the NaN fix and batch 2 but not batch 1, whose
PR had gone conflicted against them. Batch 1 is carried onto this branch,
conflict resolved — the resolution dropped two `CHANGELOG.md` entries that
were already on `main` and they were restored before committing.

*Кольцо стамины восстановлено по исходному коду из истории, а не переделано
заново: зазор между дугами убран (в оригинале они смыкаются при полной
стамине), второй множитель альфы в шейдере убран, неиспользуемый
`arc_thickness` наконец подключён и расширен, вернулось внутреннее свечение
восстановления. Кольцо больше не прячется в землю. Скобки прицела стали
дугами. Запрос перезарядки буферизуется, поэтому R больше не надо жать
дважды. Первая четвёрка перенесена сюда с разрешением конфликта.*

- `player/player_components/stamina_indicator/stamina_indicator_3d.gd`,
  `ui/widgets/dynamic_cursor/dynamic_cursor_ui.gd`, `player/player.gd`,
  `CHANGELOG.md`

---

## 2026-08-28 - Playtest batch 1: fitter docs, walk icons, the stamina ring, the F panel

Four of Stan's eight findings from a live session, in the order he numbered
them.

**1. `item_fitter` had no instructions.** The plugin is enabled and the files
are all there, but nothing anywhere said which scene has to be open or what
the dock actually writes, so it read as broken. `docs/ITEM_FITTER.md` now
covers it end to end: `player/player.tscn` (or any scene carrying
`…HandAttachment/GripPivot`) must be open, pick the `ItemResource`, pick the
hand, **pick an animation and scrub the time slider** so the fit is made
against the pose the item is really seen in, move the preview with the
ordinary gizmo, Save. It writes `HeldFit` on the item and nothing else, and
the preview is spawned with `owner = null` so it can never be serialised into
the character scene. Both silent-failure modes are named, and so is the rule
that a size problem belongs to the grip pivot rather than to `HeldFit`.

**2. The walk/sprint icons rode the player's head.** They now ride the
MOVE-DESTINATION marker — where the character is going, which is what a
"walking / running" statement is about. `TargetIndicator` grew a lookup group
(`GROUP_MOVE_TARGET`) that `HUDComponent` puts only its `target_indicator`
in, deliberately not the candidate decal; `StaminaIndicator3D` resolves it the
same way it would resolve any node it cannot be handed a reference to.
**Consequence worth knowing:** with no destination marker — TPS, or ISOMETRIC
before the first click — there is now no icon at all. It does not fall back
over the head, because that is the placement being moved away from and a
symbol that jumps between two unrelated places depending on how you steer is
worse than one that waits.

**3. The stamina ring had lost its animation and read as cold grey.** Three
separate defects in the port, all now fixed:
- the shader is `render_mode … unshaded`, where **`EMISSION` is ignored
  outright** — the port set `EMISSION = col * 2.0` and the glow it was meant
  to have simply never arrived. Brightness is in `ALBEDO` now, through a
  `ring_glow` knob.
- the drawn length of each arc was the stamina ratio alone, so a **full bar
  drew a solid ring**: the four arcs were only ever visible while stamina was
  running out. A new `arc_gap` keeps a wedge empty at every quarter boundary,
  so four arcs read as four at any level.
- standing still halved the alpha, and the shader halved it again — a full
  ring at rest came out around a quarter opacity. 0.5 → 0.75 there, 0.55 →
  0.95 in the shader.

  `ground_clearance` 0.05 → 0.18, as asked.

**4. The F panel appeared once and then stopped.** It captured
`context.camera` at world-ready and unprojected through that reference
forever. A camera that is no longer the current one puts the panel at
coordinates unrelated to what is on screen, and `is_position_behind()` then
hides it outright — which is exactly "it showed at startup and then not at
the hover door, and seemingly not over the rifle". It now asks
`get_viewport().get_camera_3d()` every frame, which is how `MouseCursorUI`
and `FadeByDistance` already did it; this widget was the odd one out. The
context camera stays as the fallback for the frame before a viewport camera
exists.

**Verified by looking**, which is the part that was missing before: a render
under Xvfb shows the ring as four separated arcs, visibly brighter, where the
same frame before the change showed one thin continuous circle. Zero errors
in the render log and no new warnings. Import passes and a `world.tscn` boot
are clean.

One bug caught in my own change before it shipped: `_resolve_icon_anchor()`
was first written to fill an out-parameter, which does nothing in GDScript —
`Vector3` is a value type, so every icon would have been pinned to the world
origin.

*Первая четвёрка замечаний Стэна. Написана инструкция к item_fitter. Иконки
ходьбы переехали с головы игрока на маркер цели хода (следствие: без маркера
иконки нет вовсе). Кольцу стамины вернули анимацию — `unshaded` глушил
`EMISSION`, при полной стамине четыре дуги схлопывались в сплошное кольцо, и
альфа резалась дважды; кольцо поднято выше над полом. Панель F брала камеру
один раз при старте и переставала попадать в экран — теперь берёт живую
камеру каждый кадр.*

- `docs/ITEM_FITTER.md` (new), `CLAUDE.md`,
  `core/ui/target_indicator/target_indicator.gd`,
  `vfx/hud_component/hud_component.gd`,
  `player/player_components/stamina_indicator/stamina_indicator_3d.gd`,
  `ui/widgets/hold_prompt/hold_prompt.gd`

---

## 2026-08-28 - Playtest batch 2: comic placement, the carbine's grip, one aim, a refusal with a voice

The second four of Stan's findings.

**5. Comic words sat on top of what they were about.** A word is a remark
about an event, not a label stuck to it, and dead centre above the head hid
the face or the item that was the subject. Words now spawn to one SIDE
(`LATERAL_OFFSET`), at a random angle within an arc so two on one head do not
overlap, and they hold longer — every profile's `duration` and `hold_ratio`
went up (npc 1.2 → 1.75 s, player 1.1 → 1.65, hurt 1.0 → 1.5, environment
1.3 → 1.9). `ComicEffectSystem` also had the **same captured-camera bug** the
F panel had and now asks the viewport for the live camera each frame.

**6. The carbine lay across the hands, and the cause was that no fit had ever
been authored.** `data/items/carbine.tres` had **no `held_fit` at all**, so
`EquipmentVisualsComponent` fell back to `transform = IDENTITY` and the mesh
hung in whatever orientation it was modelled in. The same story as finding 1:
the tool for this existed and had no instructions.

  Measured rather than eyeballed. The mesh's long axis is local Z (0.734 m —
  a 73 cm carbine, origin at the grip). The grip pivot's own axes were read
  **on a settled pose**, and the barrel aimed along the forearm
  (`RightLowerArm` → `RightHand`) with the gun's up as close to world up as
  that allows; the Euler triple came out of `Basis.get_euler()` and was
  round-tripped before use. First attempt read the grip basis two physics
  frames in, before the animation tree had blended into idle, and produced a
  fit for a pose that never appears on screen — the render showed the rifle
  standing vertically, which is how that was caught.

  Honest limit: this puts the weapon along the forearm with its top up. The
  last centimetres — seating it in the palm — are exactly what the Item Fitter
  dock is for, with a gizmo, the real renderer and an eye.

**6 (second). Two aims on screen at once.** `MouseCursorUI` becomes aim
brackets whenever a firearm is drawn, and `AimReticle` draws a cross at screen
centre whenever `PlayerState.is_aiming` — so aiming a drawn weapon showed
both, disagreeing whenever they were not in the same place. `AimReticle` now
stands down while the cursor is doing the aiming. Separately, `has_firearm` is
**held through a weapon gesture**: draw, holster and the Tab cycle each pass
through a frame or two with nothing drawn, and flipping brackets to a circle
and back inside a quarter second reads as a glitch. The hands being busy is
not the hands being empty.

**7. "The weapon does not reload" — it does, and that is the finding.**
Driven through the real key with `Input.action_press("weapon_reload")`: the
magazine refills at 1.2 s (5 → 8), the reserve pays for it (80 → 77), the
state clears and movement comes back when the 1.875 s clip ends. What does
**not** happen is any answer at all when the reload is refused — a full
magazine or an empty reserve returned silently, with no gesture, no message
and no sound, which from outside is identical to a dead key. That is now a
`reload_refused` signal on the player, and `AmmoIndicator` flashes the row
that shows why.

  I got this wrong once mid-investigation and said the character was left
  frozen. That was my own probe breaking out of its wait loop the moment the
  magazine refilled and then asserting the state was clear while the clip was
  still legitimately playing. Corrected by running the loop to the end.

**Verified**: import and boot clean, a render under Xvfb with zero errors and
no new warnings, plus before/after renders of the weapon in the hand.

*Вторая четвёрка. Комикс-слова встают сбоку от источника, а не поверх него, и
держатся дольше; у системы был тот же баг с захваченной камерой, что у панели
F. У карабина вообще не было `held_fit` — отсюда «поперёк рук»; поворот
посчитан по устоявшейся позе и направлению предплечья, а не подобран на глаз.
Прицелов на экране было два одновременно — крест уступает скобкам; скобки
больше не мигают во время жеста. Перезарядка, измеренная через настоящую
клавишу, работает — молчал именно отказ, теперь он мигает строкой боезапаса.*

- `core/ui/comic_effect/comic_effect_system.gd`,
  `data/comic_effects/profiles/*.tres`, `data/items/carbine.tres`,
  `ui/hud/aim_reticle/aim_reticle.gd`,
  `ui/widgets/dynamic_cursor/dynamic_cursor_ui.gd`, `player/player.gd`,
  `ui/hud/ammo_indicator/ammo_indicator.gd`, `ui/hud/player_hud/player_hud.gd`

---

## 2026-08-28 - The cursor spring diverged to NaN; and a way to actually look

Stan reported 7714 errors in one editor session. The stack trace named the
file: `dynamic_cursor_ui.gd:338 @ _draw_bracket_left()` —
`Vector2 cannot be normalized, the elements must be finite`.

**Root cause.** The aim-bracket spring integrates with semi-implicit Euler and
is stable only while the step stays under roughly `2 / damping` — about
0.14 s at damping 14. One frame longer than that (a streaming hitch, a
breakpoint, the editor stealing focus) makes it diverge; the offset runs away
and never comes back, because every later frame feeds the poisoned value into
itself. Each frame then drew six antialiased lines at a non-finite position,
and every one called `Vector2.normalize()` and warned. Not a burst — a
permanent flood.

**The project already had the answer.** `SpringPoint.MAX_STEP`
(`ui/widgets/morphs/`) clamps exactly this, and its header already said why:
"a hitch past that bound does not degrade gracefully: it diverges". Three
springs were written without it — the cursor's, and both of
`hold_prompt.gd`'s, which are a day old. All three now clamp against that
constant **by name** rather than copying the number, and `spring_point.gd`'s
header no longer claims it is a morph-family value.
`tps_combat_camera_state.gd` gets the same one-line clamp: it is far less
exposed (damping 6 puts the bound at 0.33 s) but a diverged yaw is a NaN
camera basis, which takes the whole view with it.

**A second, smaller bug, found by the probe rather than by reading.** The
first version of the draw guard tested the floats with `is_finite()` and let
the offending value straight through: GDScript floats are 64-bit, so a
diverged spring is still "finite" there — measured, 1e150 — while `Vector2`
stores 32-bit components and the same number is already `inf` by the time
`draw_line()` sees it. The guard now tests the `Vector2`.

**Why none of this was caught here.** Headless is the dummy driver: it never
compiles a shader and never calls `_draw()`. Every check in this repository
was silent and green while the game printed six warnings a frame. That is not
a gap in attention, it is a gap in method, and it is why this entry also adds
a way to see.

`tools/render_probe/render_probe.sh` runs the game under Xvfb on software
OpenGL and writes a PNG sequence with Godot's own `--write-movie` — no
ffmpeg, xwd or ImageMagick, none of which exist in the container. The
capability was there the whole time and had never been tried. Its limits are
stated in its own header and in `CLAUDE.md`: it is the **Compatibility**
renderer against a **Forward+** project, so geometry, placement, orientation
and UI layout are trustworthy and lighting is not.

**CI corrected, twice over.** The warning summary ended in `sort -u`, so one
warning and seven thousand identical ones rendered as the same tidy line —
a real defect in what I built four days ago. Warnings now report with counts,
and any single warning repeating more than 50 times fails the run. A second
job, `Render`, runs the probe, gates its log, and uploads the last frame on
every run so the build can be looked at without checking it out.

**Verified.** A probe reproduced the divergence directly (run, read, deleted):
at 60 fps clamped and unclamped agree exactly, so the fix changes nothing in
normal play; at a 0.2 s step the unclamped integrator passes 1e30 while the
clamped one settles on the target; the draw guard refuses the diverged value
and a zero-height bracket, and still allows a healthy one. Nine assertions,
all passing. The render probe produced 60 frames with zero errors, and the
frame is legible.

*Пружина прицельных скобок расходилась в NaN на одном длинном кадре и дальше
печатала по шесть предупреждений в кадр — отсюда 7714 у Стэна. В проекте уже
была константа `SpringPoint.MAX_STEP` ровно от этого, с объяснением; три
пружины были написаны мимо неё. Теперь все клампятся по имени этой константы.
Отдельно: headless не рисует вообще, поэтому ни одна моя проверка этого
увидеть не могла — добавлен `tools/render_probe/`, запуск игры под Xvfb с
сохранением кадров, и второй job в CI, который прикладывает кадр к каждому
прогону. CI больше не сворачивает одинаковые предупреждения в одну строку.*

- `ui/widgets/dynamic_cursor/dynamic_cursor_ui.gd`,
  `ui/widgets/hold_prompt/hold_prompt.gd`,
  `camera/tps_combat_camera_state.gd`, `ui/widgets/morphs/spring_point.gd`,
  `tools/render_probe/render_probe.sh` (new),
  `.github/workflows/godot.yml`, `CLAUDE.md`

---

## 2026-08-28 - CI: the verification ladder runs by itself

There was no `.github/` directory in this repository at all. Every claim that
"the import is clean and the world boots" rested on someone having run the
ladder by hand and reported it accurately — which is exactly how
`tools/for_claude_addon_item_/` reached `main` and broke it.

`.github/workflows/godot.yml` now runs that ladder on every pull request and
on a push to `main`: import twice, then boot `world.tscn`. It **reuses**
`.claude/hooks/ensure_godot.sh` rather than restating the download, so the
engine version stays pinned in exactly one place and bumping it there busts
the CI cache automatically. One correction on top of the reuse: the hook is
deliberately fail-soft (`|| exit 0`, so it can never block a session from
starting), so the workflow asserts `godot --version` afterwards — otherwise a
failed download would look like a pass.

**Everything about the design was measured on a genuinely cold cache, not
assumed.** Import pass one takes 36 s and prints **17 `ERROR` lines that are
all false** — four `Cannot infer the type of X`, a failure to load the
project font, a missing albedo texture — every one of which is gone by pass
two (31 s, completely silent). That is why only the second pass is gated, and
`CLAUDE.md` now carries the numbers instead of just the rule. The boot takes
12 s and prints exactly the two warnings already standing on `main`.

**The gate is the log, never the exit code:** Godot exits 0 with a script
that does not parse — confirmed directly. Warnings do not fail a run, but
every unique one is written into the run summary, so a new warning is visible
without making the known pair permanently red. Logs upload as an artifact on
failure.

**Verified in both directions.** Forward: the gate is silent on a clean tree
(import pass two and boot, zero matches). Backward — the one that makes green
mean something: a deliberate syntax error in `core/input/input_systems.gd`
produced 14 gated lines on the import pass and 18 on the boot, and the file
was restored. The version-extraction `sed`, the grep gate and the warning
summary were each run against the real captured logs, and the YAML was
parsed.

**A real limitation, found by the first attempt at that backward test and
written down rather than hidden:** a `.gd` file that no scene, autoload or
other script references is never compiled by the import pass, so a syntax
error in an orphan file passes CI green. There is no cheap fix —
`--check-only --script` is the trap `CLAUDE.md` already describes. Recorded
in the workflow header, in `CLAUDE.md` and in `docs/scope_horizon.md`.

Deliberately **not** included: no test suite (the accepted trade in
`scope_horizon.md` is unchanged — this asserts nothing about behaviour), no
`CHANGELOG`/contract gate (considered, dropped as more likely to be worked
around than obeyed), no PR template. The push trigger is restricted to `main`
and must not be widened to `**`: `entire/checkpoints/v1` is Entire's own
branch and nothing in CI should ever check it out.

*Появился `.github/workflows/godot.yml` — лестница проверки из `CLAUDE.md`
(двойной импорт + загрузка мира) теперь гоняется репозиторием на каждый PR и
на push в `main`, а не с моих слов. Переиспользует `ensure_godot.sh`, так что
версия движка закреплена в одном месте. Гейт — по логу, не по коду выхода:
Godot возвращает 0 даже при ошибке парсинга. Первый холодный проход даёт 17
ложных ошибок и поэтому не проверяется — это измерено. Тестов не добавлено,
принятый компромисс из scope_horizon не тронут.*

- `.github/workflows/godot.yml` (new), `CLAUDE.md`, `docs/scope_horizon.md`

---

## 2026-08-28 - Hold Prompt: F → ○ → ●, and boarding becomes hold-to-confirm

Interaction had no on-screen feedback at all: `InteractComponent` found a
candidate, `HUDComponent` put a decal under it, and nothing said which key
took it. New **`HoldPrompt`** (`ui/widgets/hold_prompt/`, a `WORLD_UI_SCENES`
entry) draws a tapered plate with the letter `F` over the candidate —
entrance with a shake and a smear that resolves into a hard edge, a slow
pulse at rest; holding the key turns it yellow, spins the `F` out and morphs
it into a circle and then a filled dot. Ported from a canvas study, with its
spring and morph constants carried over unchanged.

**The widget decides nothing.** No inventory, no `store_item()`, no
threshold. `set_progress()` is a **target** it eases toward: rising fast, so
a commit never lands before the dot is drawn, and falling slowly, so a
cancelled hold rolls back without the caller animating anything — truth
belongs to the caller, feel belongs to the widget. Found by group, the way
`ComicEffectSystem` is, because `HoverEntryTrigger` never receives a
`WorldContext`. Delete the node and every interaction still works.

**`InputSystems` gets its interact hold timer back**, in the shape the
removed prototype got wrong: not a separate action on another key, but three
edges on the same one — `interact_pressed`, `interact_held(duration)`,
`interact_released(duration)` — measured exactly the way
`_handle_secondary_click()` already measures the right mouse button. It
reports how long and never "that was a tap". The claim contract mirrors the
three (`on_interact_claimed()` required, the other two duck-typed) and is
**corrected rather than doubled**: there is one claimant in the project, so
no legacy path was kept beside it. Plus `is_interact_claimed()`, a state
read of the same category as `is_jump_just_pressed()`.

**Boarding and exiting a hover are now hold-to-confirm** (0.7 s,
`HoverEntryTrigger.interact_hold_time`). The threshold lives with the thing
that decides, not in the relay. Getting into a vehicle is the one mis-press
here that is expensive to undo, and this trigger is the only claimant, so the
hold sits on the claim contract instead of becoming a general property of
interaction. **Pickup is deliberately unchanged** — F still commits on the
press, because an auto-approach commits on arrival seconds later and a
tap-vs-hold arbitration at release has nothing to attach to there. The tap
gets the same morph through `instant_complete()`, which holds the panel up
for ~0.24 s: a pickup frees the world object, so the panel would otherwise be
told to leave one frame after the morph began.

**Verified** by a throwaway probe (run, read, deleted — 49 assertions, all
passing) driving **real input** via `Input.action_press("interact")`, so the
relay itself is under test rather than a stand-in. Negative control ran
first, with no `HoldPrompt` anywhere in the tree: boarding and pickup behaved
exactly as before. Then: one `pressed` and one `released` per press with a
monotonic duration that resets between presses; no signal escapes while
claimed and the claimant gets all three; a hold under the threshold does not
board, crossing it boards once, and a still-held key does not board twice;
the bottom edge is narrower than the top by `2 * bottom_taper`; a cancelled
hold eases back instead of snapping; `instant_complete()` reaches the dot in
0.120 s; an anchor behind the camera hides the panel. Import passes and a
`world.tscn` boot are clean — the two warnings present are the two already on
`main`.

Two bugs the probe caught, both mine: the freed-Object-equals-null trap again
(`_follow != null` reads false for a freed anchor, so the panel hung on a
dead reference — `is_instance_valid()` alone is the fix), and a taper
assertion that was measuring a sampled polyline to exact equality.

**Not verified:** headless has no picture. Whether the taper reads as a
shield pointing down rather than a clipped rectangle, whether the entrance
shake fights the candidate decal that appears on the same frame, and whether
0.7 s to board is right all need eyes.

*Появился экранный prompt взаимодействия: рамка с буквой F над кандидатом,
при удержании — жёлтый цвет и морф F → круг → точка. Виджет ничего не решает,
прогресс приходит снаружи как цель. В `InputSystems` вернулось удержание
interact тремя рёбрами; контракт claim'а зеркалит их. Посадка и высадка из
ховера теперь через удержание 0.7 с; подбор намеренно остался мгновенным.*

- `ui/widgets/hold_prompt/hold_prompt.gd` + `.tscn` (new), `world/world.gd`,
  `core/input/input_systems.gd`,
  `player/player_components/interact_component/interact_component.gd`,
  `core/controllers/transport/hover_entry_trigger.gd`,
  `docs/architecture/autoloads_and_bootstrap.md`,
  `docs/architecture/player_and_camera.md`,
  `docs/architecture/items_and_equipment.md`, `input_map.md`

---

## 2026-08-28 - The comic word gets a panel

The floating reaction word was a `Label` with an outline: the only thing
anyone could ever author was the type itself. It now arrives on a drawn
**panel** — near-black plate, very faint print grid, inked border that is not
quite straight — with the whole frame built procedurally from data.

**`ComicVisualProfile`** (new, `core/ui/comic_effect/`) owns how a panel is
drawn: colours, type, border style/thickness/corner jitter, padding, grid
step, and the pop/hold/fade timings. It is shared by a **class** of events,
not owned by one: four profiles in `data/comic_effects/profiles/` — `npc`,
`player`, `player_hurt`, `environment` — replace thirteen per-event colours.
That reduction is the argued part of this change: thirteen hues are a legend
the player memorises, which `docs/visual_language.md` warns against; four
registers say *whose noise is this*. The cost is named in
`docs/architecture/npc_and_incidents.md` — `player_combat` no longer borrows
`StanceIndicator.combat_color`, and that tie is now carried by the stance
badge alone.

**`ComicEffectLabel` is a `Control` that draws itself** — background, grid,
border, text outline, text, in that order. Outline strictly before the text
(reversed, it hides the glyphs inside their own outline and merely looks
muddy). Corner jitter is sampled once at `setup()`, never inside `_draw()`, so
a hanging panel cannot change shape when something forces a redraw. The grid
is one tiled `draw_texture_rect` off a static per-step `ImageTexture` cache —
a loop of `draw_rect` would be thousands of calls a frame at eight live
panels. Alpha now rises, **holds at full while the word is being read**, then
fades; the old curve started fading on frame one.

**Nothing renders differently by accident.** `ComicEffectDef.resolve_profile()`
synthesises a profile from the legacy `color`/`font_size`/`duration`/`rise_px`
fields when none is set, so a def with no profile still draws — migration is
per-def and optional. `ComicEffectDef.get_font_size()` is the single place the
drawn size is decided; the label does not recompute it.

**Untouched on purpose:** the vocabulary, the distance gate, `MAX_ACTIVE` (8)
and `POOL_SIZE` (12), the anti-repeat and the catalog. `docs/visual_language.md`
§4 makes those art direction, and this change had no art-direction argument
for moving them. `ComicEffectSystem` changed in two places only.

**Verified** by a throwaway probe scene (run, read, deleted — 40 assertions,
all passing): a profile-less def still spawns a sized, visible panel; the
catalog still loads 13 defs with their texts intact; no vocabulary entry
contains `!` and every entry is capitalised, which is `visual_language.md` §2
checked literally; the distance gate still blocks; panel width is exactly text
+ padding × 2; the profile's duration wins over the legacy field; alpha rises,
holds 25 samples at full, ends at zero; all four border styles draw without
error; after every panel dies `_active` is empty, the pool is intact and
nothing was freed. Import passes and a `world.tscn` boot are clean — the two
warnings present are the two already on `main`.

**Not verified, and honestly so:** headless has no picture. Whether the panel
reads as a comic panel rather than a UI tooltip, whether the grid fights the
letters, and whether eight at once clutter the screen all need eyes.

**Out of plan, deliberately** — recorded as such in `docs/scope_horizon.md`
under *Out of plan*, with the trade against H6 stated rather than hidden.

*Комикс-слово теперь рисуется как панель: подложка, слабая печатная сетка,
неровная рамка. Новый ресурс `ComicVisualProfile` описывает вид целого класса
событий — четыре регистра вместо тринадцати цветов. Альфа теперь нарастает,
держится и только потом гаснет. Словарь, дистанционный гейт и лимит
одновременных слов не тронуты. Работа вне плана, отмечено в scope_horizon.*

- `core/ui/comic_effect/comic_visual_profile.gd` (new),
  `core/ui/comic_effect/comic_effect_def.gd`,
  `core/ui/comic_effect/comic_effect_label.gd`,
  `core/ui/comic_effect/comic_effect_system.gd`,
  `data/comic_effects/profiles/*.tres` (new, 4),
  `data/comic_effects/*.tres` (13), `docs/visual_language.md`,
  `docs/architecture/npc_and_incidents.md`, `docs/scope_horizon.md`

---

## 2026-08-28 - Stamina moves to the feet; the cursor becomes an aim

`MouseCursorUI` was doing two unrelated jobs on the same few pixels: saying
how much wind the character has left, and saying what they are aiming at.
Aiming is a fast, precise read; stamina is a slow, ambient one, and stacked
together the aiming half loses.

**Stamina moved into the world.** New `StaminaIndicator3D`
(`player/player_components/stamina_indicator/`) draws it as a ring on the
ground around the character's feet. It owns no arithmetic — `StaminaComponent`
still does all of it, and this node subscribes and renders, the same contract
`EquipmentVisualsComponent` already states for itself. The visual is a **port,
not a rewrite**: the four arcs and their full → yellow → orange → red ramp, the
two chasing recovery rings with their pulse, the jump-charge arc and the
walk/sprint/no-stamina icons all keep their original formulas and timings —
only the surface changed, from a 2D canvas to a shader on a ground quad, the
same approach `TargetIndicator` already uses. Two details that are easy to
lose in a port and were kept deliberately: the ring dims by half while
standing still, and the arcs spin faster in proportion to the sprint blend.

**`top_level = true`, position copied each frame.** The node is a child of the
player but must not inherit their rotation: in COMBAT the body turns to face
the camera constantly, and a ground ring welded to that yaw would swing on
every turn. Verified — turn the player 90°, the ring stays at 0°.

**The icons became billboarded `Sprite3D`s** above the ring rather than lying
flat on it: flat, they read only from directly overhead, which is the one
angle TPS never gives.

**The cursor now says one thing.** Dim grey when nothing is under it, brighter
when an NPC or an item is, and **brackets instead of a ring while a firearm is
in hand** — `player.gd._drawn_firearm()` became public `get_drawn_firearm()`
so that question has one asker and one answer instead of the UI re-deriving it
from the catalog. The brackets breathe off the **continuous** speed rather than
off `is_running`, through a spring rather than a lerp, so they open as the
character moves and settle as they stop. Their shape is unchanged: `[ ✛ ]`,
spine outwards, tips toward the target.

**In TPS the cursor is pinned to screen centre.** The mouse is captured there,
so it cannot be moved and the camera is what aims; the ray is cast from the
same point, which makes it an honest sight down the camera's own direction.

**Found while testing, not fixed here:** the island terrain carries
`collision_layer = 3`, so it sits on `CHARACTERS` alongside actual characters.
Nothing separates them by mask, and the first version of the cursor lit up
from a plain look at the ground. Rather than change that layer — which would
touch physics across the project — the cursor checks the *type* of what the
ray hit (`NPCBase`, `InteractableObject`, or an `InteractableObject`'s `Area`).
That also buys honest occlusion for free: the ray returns the nearest hit, so
an NPC behind a hill is rejected along with the hill. **The layer itself is
still wrong and worth a look on its own.**

24 assertions in `world.tscn`, all green, including that the cursor no longer
holds a `StaminaComponent` reference at all and is not subscribed to any of
its signals.

*Стамина уехала из курсора в мир — кольцо на земле вокруг ног, вся анимация
перенесена дословно, считает по-прежнему `StaminaComponent`. Кольцо не
наследует поворот тела. Курсор теперь говорит одно: серый / белый по наведению
и скобки при огнестреле, живущие от непрерывной скорости через пружину. В TPS
курсор прибит к центру экрана. Попутно найдено: терраин острова стоит на слое
CHARACTERS — здесь не чиню, но это стоит посмотреть.*

---

## 2026-08-28 - The candidate decal: "I will walk there" vs "I can reach it"

PR #40 gave `InteractComponent` an intent tier, so the game already knew what
the player was aimed at and already walked the character over on F. What was
missing was any quiet way of saying so. Now a ground decal sits under the
targeted object and changes colour: **dim** while pressing F would walk the
character over, **bright** once it is within arm's reach.

**The two states are not read from which tier found the object.** That would
lie: `PlayerFocusCast` reaches about 1.8 m forward while `pickup_distance` is
0.9 m, so a focus-cast hit can still need an approach. `in_reach` is computed
with the same `_flat_distance_to(object) <= pickup_distance` that
`try_interact()` uses to decide, so the colour cannot drift from the
behaviour by construction rather than by luck.

`InteractComponent` gained one signal — `interact_target_changed(object,
in_reach)` — and still knows nothing about widgets. `TargetIndicator` gained a
`decal_only` mode (ring and arrow are not created at all), two colours and
`show_candidate()`, and still knows nothing about items, equipment or pickup;
it is told "appear here, this colour". `HUDComponent` connects the two, which
is where it belongs — it already owns the indicator and already receives the
world context.

**A second node of the same class, not a second mode on the existing one.** In
ISOMETRIC "where I am walking" and "what I am reaching for" can be on screen
at once, so one node would have had to choose. The move marker is unchanged in
every respect: ring, arrow, walk/run/invalid palette, and its ON_FOOT +
ISOMETRIC gate. The candidate decal deliberately drops the ISOMETRIC half of
that gate — interacting works the same in both views.

**A real bug, older than this change, found by the probe.** In Godot a freed
Object compares **equal to null**. `detect_interactable()` gates its whole
update on `new_interactable != current_interactable`, so after a pickup —
`new` is null, `current` is freed — that reads as *no change*: the branch is
skipped and `current_interactable` keeps pointing at a dead object **forever**,
while also answering `== null` truthfully to anyone who asks. It had no
visible symptom before there was a widget following that value; the decal
made it visible by staying on an empty patch of ground.

Fixed at the source: `detect_interactable()` normalises an invalid target to
null before anything else looks at it, so `on_lost_by_player()` and every
consumer see an honest null. The new edge test compares instance ids for the
same reason, and `HUDComponent` asks `is_instance_valid()` rather than
`== null`, since those two questions look identical here and only one of them
is unambiguous.

24 assertions in `world.tscn`, all green, negative control first: with
`intent_radius = 0` the decal never appears. Colours are read back out of the
live shader parameter rather than from the exports, so the test proves what is
actually on screen, and two assertions pin Godot's freed-equals-null behaviour
directly so the reasoning above is not folklore.

*Под предметом, на который нацелен игрок, появляется декаль: тусклая — «дойду»,
яркая — «дотянусь». Граница берётся тем же выражением, которое потом и решает,
идти или брать, поэтому цвет не может разойтись с поведением.
`InteractComponent` отдаёт один сигнал и ничего не знает про виджеты;
`TargetIndicator` получил режим «только декаль» и ничего не знает про предметы.
Пойман баг старше этой правки: освобождённый объект в Godot равен null, из-за
чего `current_interactable` после подбора навсегда залипал на мёртвой ссылке —
симптома не было, пока за этим значением не начал следить виджет.*

---

## 2026-08-27 - F means "pick that up", not "you are standing correctly"

Picking something up made the player position the character for the UI rather
than for the fiction. `PlayerFocusCast` is a capsule reaching ~1.8 m forward
with radius 0.4, and it has to physically overlap the object's own `Area3D` —
a window roughly ±0.9 m wide that you had to thread while facing the thing.
Then `try_interact()` acted only if `current_interactable` was already set,
and nothing ever moved toward anything.

**Detection got a second tier, on the player rather than on the items.** When
the focus cast finds nothing, one shape query per physics frame asks the wider
question: anything within `intent_radius` (2.5 m) inside a 240° forward cone,
nearest wins. It reads the same `Area3D`s on the same layer the focus cast
already reads, so no object needs anything new — and the winner goes into the
same `current_interactable`, so the tick indicator, the debug label and
`try_interact()` all work unchanged, just earlier. Growing every item's own
`Area` instead would have been the per-item spelling of a rule that belongs on
the character once.

**F now states an intent.** Further than `pickup_distance` (0.9 m) and the
character walks over first, then interacts on arrival; already in range and it
acts immediately, exactly as before. The walk reuses the click-to-move
contract as-is (`set_movement_speed` + `move_to_position`) rather than driving
the body from the component, and since `_handle_navigation()` already turns
toward the point it is walking to, the character arrives facing the target
with nothing extra to do — measured 2.1° off. All five interaction types go
through it, via a `_perform_interaction()` extracted from `try_interact()` so
the immediate path and the on-arrival path run the same code instead of two
copies of the same `match`.

**Navigation is no longer ISOMETRIC-only.** `move_to_position()` in TPS used to
set a path nothing consumed, so an approach there did nothing. TPS now runs the
navigation branch whenever a scripted path is in flight — and, less obviously,
must also **skip `_update_direct_move_target_speed()`**, which zeroes
`target_speed` on every frame without WASD input and would have drained the
approach's speed before it moved a metre. Player input cancels the path on the
spot; `InteractComponent` hears that through the existing `movement_stopped`.

**One bug found by re-reading rather than by running:** a path that ends
normally emits the same `movement_stopped` as the player interrupting, so the
first version silently cancelled any pickup whose walk finished a few
centimetres outside the arrival radius. The handler now only records that the
body stopped; the distance test rules first, and the stop point is aimed at
75% of `pickup_distance` so the walk ends comfortably inside.

`approach_timeout` (4 s) is not padding: this project has no
`NavigationRegion3D` (`NavigationComponent` says so at every boot and falls
back to a straight line), so a walk into geometry never arrives and never ends.
The probe confirms both halves — an approach across open ground succeeds, and
one starting behind `LodgingRoom`'s walls gives up and hands control back.

25 assertions in `world.tscn` through the real `interact_pressed` signal, all
green, starting with a negative control: with `intent_radius = 0` the same
carbine at 2.2 m and 55° off is **not** detected and F does nothing.

Player speed is untouched — 5.0 / 15.5 were never the cause of this.

*F теперь означает намерение: увидел — нажал — персонаж сам подошёл и подобрал.
Второй ярус обнаружения (2.5 м, конус 240°) живёт на игроке, а не на предметах.
Навигация заработала и в TPS. Найден баг: нормально завершившийся путь шлёт тот
же сигнал, что и вмешательство игрока, — подбор молча терялся.*

---

## 2026-08-27 - tools/for_claude_addon_item_/ removed — it broke ItemResource

`main` did not compile its own item system. `tools/for_claude_addon_item_/`
held a staged concept for an item-pose addon, and two of its files declared
`class_name ItemResource` and `class_name EquipmentVisualsComponent` — names
the real `core/items/item_resource.gd` and
`player/.../equipment_visuals_component.gd` already own. Godot treats a
duplicate global class as a parse error, so on a cold import
`core/items/item_resource.gd` itself failed to load, and
`addons/item_fitter/item_fitter_dock.gd` failed with it ("Cannot infer the
type of 'fit'"). Measured before the deletion and after: three import passes
and a headless boot are clean now, and the fitter plugin loads again.

The folder was a drop-box, not a system: two edited copies of live scripts, a
competing `ItemPose` resource, an authoring scene, a plugin, a design note, a
`carbine_pose.tres` pointing at `res://core/items/item_pose.gd` — a path that
does not exist on `main` — and a half-finished browser download
(`Unconfirmed 300846.crdownload`, actually a `plugin.cfg`).

**Its design was not thrown away.** That prototype reached the same
conclusions the merged work did — the pose belongs on the item, authored
visually against a live animation, by an editor plugin — and went one step
further in one place: a **second mesh in the off hand with its own
transform**, so a long gun is posed at both grips. That is now
`TODO(equipment)` on `HeldFit.hand` and a line in the architecture contract,
to be taken if the carbine's left hand reads wrong by eye. Its other idea,
grip markers on the item, is already answered differently — the carbine mesh's
origin *is* its grip.

**Its numbers do not transfer.** `carbine_pose.tres` held
`position (0.03, -0.02, 0.08)`, `rotation (12, 94, -3)`, but it parented to
the `BoneAttachment3D` rather than to a `GripPivot`, so those are skeleton
units against the old mid-barrel mesh origin — the same 38.8% scale bug the
merged work fixed. Re-author with the fitter instead.

*`tools/for_claude_addon_item_/` удалена: два файла в ней объявляли
`class_name ItemResource` и `EquipmentVisualsComponent`, из-за чего настоящий
`item_resource.gd` не компилировался, а плагин `item_fitter` падал. Идея
второй руки из этого концепта сохранена как `TODO(equipment)` в `HeldFit`;
числа из `carbine_pose.tres` не переносятся — они в единицах скелета от
старого начала координат меша.*

---

## 2026-08-27 - An editor tool for fitting items to hands; tools/ audited

**`addons/item_fitter/`** — an `EditorPlugin` dock. Pick an `ItemResource`,
pick the hand, pick and scrub one of the character's animation clips, drag the
mesh with the ordinary 3D gizmo, Save. It writes `HeldFit` back onto the item
and knows no item by name, so the next weapon or tool works without a line
changed. The preview is a real node parented to the same `GripPivot` the game
uses at runtime — the editor's gizmo works on it for free, and the numbers
under it are metres because the pivot cancels the rig scale. Spawned with
`owner = null` so it can never be saved into the character scene.

Second addon after `godot_ai`, and the reason it is not in `tools/` is
recorded in `CLAUDE.md`: `tools/` holds one-shot `EditorScript`s and runtime
debug panels, and fitting an object to a hand needs a dock, a live gizmo and
to survive a scene switch — three things only an `EditorPlugin` provides.

**`tools/` audited**, folder by folder, by what actually references each.
Everything is live except one: `input_debugger`, `stats_display` and
`scan_folder_files` are instanced in `world.tscn`; `island_generator`,
`build_aogashima_terrain`, `city_generator` and `block_generator` are each the
only reproducible path to committed content; `tests/noir_room` is cited by
`votive_projector.gd`. **`tools/checker_indicators/` is deleted** — two orphan
scripts with no scene and no instance anywhere, `@onready`-ing children
(`$IncreaseHP`, `$DecreaseHP`) that exist in no file, and mentioned only by
two comments that both named the wrong path. Those two comments are fixed.

**`CLAUDE.md` named a file that has never existed.** Both the project header
and the hard-constraints list said the only C# in the repo was
`tools/scan_folder_files/project_scanner.cs`; that path holds
`project_scanner.gd`, and `git log --all --diff-filter=AD -- '*.cs'` finds
nothing — no C# file has ever been committed here. `project.godot` carries an
empty `[dotnet] assembly_name="ADT"` from someone opening the project once in
the .NET editor, with no `.csproj` and no `.sln`. So the "drop C# entirely"
backlog item was closed by never having started. Fourth recorded drift in
that file, corrected there the way the previous three are.

*Добавлен плагин редактора `addons/item_fitter/` — выбираешь предмет, руку и
анимацию, двигаешь меш обычным гизмо и сохраняешь посадку на сам предмет.
Папка `tools/` разобрана: всё живое, кроме `checker_indicators` — удалено.
В `CLAUDE.md` исправлено утверждение про единственный C#-файл: C# в этом
репозитории не было никогда.*

---

## 2026-08-27 - The carbine sits in the hand, the shot reads, and there is a reserve

Playing the carbine surfaced three complaints, and each had one measurable
cause rather than being a matter of taste.

**Every held item in the project was rendered at 38.8% of its real size.**
`player.tscn`'s `player_base_mesh` carries a uniform 0.38763407 scale and it
is the only scale between the player and the hand bones, and
`EquipmentVisualsComponent` parented the held mesh straight to
`RightHandAttachment` — so a 73 cm carbine appeared as 28 cm, and every offset
written for one was silently in skeleton units rather than metres (the
pistol's `held_offset` of 0.33 was 12.8 cm). Nothing warned; it looked like
the numbers needed tuning. A **`GripPivot` under each hand attachment** now
carries the reciprocal scale (2.5797526), so everything below it is metric,
and `_check_grip_scale()` warns if that ever stops being true. A
`LeftHandAttachment` was added alongside the right one.

**The pose moved off the component and onto the item.** New `HeldFit`
(`core/items/held_fit.gd`, optional `ItemResource.held_fit`) — hand, offset,
rotation, scale. `EquipmentVisualsComponent.held_offset`/`held_rotation_deg`
are gone: one pose shared by everything ever drawn is how a component ends up
holding a pose for geometry it knows nothing about. The carbine placeholder
was regenerated with its **origin in the grip** (all vertices shifted
`(0, +0.088, +0.088)`), so a zero fit already puts it in the fist instead of
holding it by the middle of the barrel; the world placement Y was re-measured
against the new AABB, 128.917 → **128.829**, by ground ray.

**The shot and the reload now come from the same pack as the locomotion.**
`new4/shoot-rifle-light` is 0.25 s and from ShooterLib while the idle and all
eight locomotion points are `new3/` — a quarter-second snap to a different
rifle pose and back, which is why it read as no animation at all.
`new4/reload-rifle` had the same mismatch, and that is the other half of
"after the reload it's as if there's nothing left": the magazine did refill,
it just did not look like a reload. Now **`new3/rifle_shot`** (1.17 s) and
**`new3/rifle_reload_2`** (1.88 s), both non-looping — which rules out every
shorter candidate, since a looping clip under a `OneShot` can fail to
terminate and would lock movement permanently. `weapon_oneshot`'s fade times
are set explicitly rather than left at a default.

**Reserve ammunition**, 80 rounds behind the magazine
(`ItemResource.reserve_capacity`, `WeaponComponent._reserves`). A reload moves
`min(missing, reserve)`; a partial reload is a success, since refusing one
would strand the last rounds. **`can_reload()` is asked before the gesture
starts** — caught by the probe suite: `player.gd` locks movement at the key
press and only reaches `reload()` a second into the clip, so the first version
played a full reload animation for a weapon with an empty reserve. The HUD row
reads `8 / 8 · 72`, the reserve dimmer than the magazine and red at zero.
The reserve is finite and nothing restores it; an ammunition pickup is the
follow-up, deliberately not built here.

39 assertions in `world.tscn` through the real input paths, all green —
including the two that would have caught the scale bug and did not exist
before (the held mesh's global scale is 1.0, its world length 0.734 m), the
gesture timings, the reserve draining to zero and refusing the eleventh
reload, and the HUD immediately after a reload rather than only at zero.

*Найдено: любой предмет в руке рендерился в 38.8% размера — у `player_base_mesh`
масштаб 0.38763, а меш вешался прямо на кость. Добавлены пивоты `GripPivot` с
обратным масштабом, посадка предмета переехала на сам предмет (`HeldFit`),
начало координат меша карабина перенесено в рукоять. Выстрел и перезарядка
переведены на тот же пак анимаций, что и локомоция, — отсюда «анимации нет».
Добавлен запас в 80 патронов.*

---

## 2026-08-27 - The pistol becomes a carbine, and gets ammunition

The pistol was the wrong weapon for this project's animation library. It has
four or five clips; the rifle set has an idle, an aim, three fires, two reloads,
turns — and a full **eight-direction locomotion pack** (`new3/rifle_locomotion_run_*`)
that maps one-to-one onto the eight outer points the existing `BlendSpace2D`
already uses. Carrying a weapon should change how the character moves, and only
the rifle set can show it.

**The carbine replaces the pistol.** `data/items/carbine.tres`,
`data/items/meshes/carbine_placeholder.res` (one `ArrayMesh`, three surfaces:
receiver/barrel, stock, grip) and `world/interactables/carbine/carbine.tscn`;
`pistol.tres`, `pistol_placeholder.res` and `world/interactables/pistol/` are
gone. The world placement was **re-measured, not carried over** — the new mesh's
AABB minimum is −0.1447 against the pistol's −0.118, which moved the authored Y
from 128.89 to 128.917 against a ground ray at 128.762.

**Carrying a weapon now changes the whole locomotion.** A third `BlendSpace2D`
(`weapon`) with the same eight-point geometry, filled from the rifle pack, chained
after `stance_blend` on a second `Blend2`. `set_drawn_idle(bool)` became
`set_weapon_locomotion(bool)` — the old one substituted a single clip at the combat
centre point and left the eight directional points empty-handed, so the character
sprinted with a weapon out as if nothing were in its hands. Two honest gaps left
in place and commented: the pack has one forward clip where the geometry wants a
walk and a run, and its rear diagonals have no point to go to.

**One shot kills**, and it is only the damage number: `ranged_damage = 150.0`
against a default `max_health` of 100. `NPCBase._update_knockdown()` already had a
terminal `DOWN` phase entered at zero health and never left, so "they get back up
after being shot" was never a missing state.

**Ammunition.** `ItemResource.magazine_size` on the item, and a new
`WeaponComponent` (a direct child of `Player`) holding `{item_id: rounds}` — not on
the item, which is shared, and not on `EquipmentComponent`, which stores ids and
knows nothing that differs between two identical items. Firing spends a round at
the trigger; an empty magazine refuses the whole shot, gesture included.
`weapon_reload` (`R`), bound and unread since the input map was written, gets its
first consumer. Reserve ammunition is deliberately absent. It saves through
`PlayerPersistenceSystem` with no further wiring.

**A carbine is `CARRIED`, so no pocket takes it** — which used to mean it had
nowhere to go, since body slots were garments-only. `EquipmentSlotDefinition`
gained `accepts_non_garment` (true on `back_pack` and `back_unique` only;
`max_size` cannot answer it, as legs/torso/feet are `CARRIED`-sized too),
`stow_anywhere()` gained a third pass over those slots **after** pockets, and the
draw cycle walks them too. `refuses_threatening` still keeps an automatic stow off
`back_unique`, so the display slot stays a deliberate act. Draw and holster pick
the shoulder clips (`new4/equip-shoulder-r`, `WeaponChange_back`) from that slot.

**Pickup is animated, and the clip is chosen by height** — `new4/pickup_item` below
0.6 m, `new4/interact-button` at or above. Height rather than `interaction_type`,
because the question is where the hands have to go and a can on a table is not a
button. Movement is deliberately not locked for it.

**HUD:** a new `AmmoIndicator` (pips plus "3 / 8") directly under the health row,
wired by `PlayerHUD` in `on_world_ready()` — it needs `WeaponComponent` and
`EquipmentComponent`, neither an autoload. Visible only while a magazine weapon is
in the hands.

Verified through the real paths in `world.tscn` — 32 assertions, all green: pickup
detection and both gesture branches, draw from the back, the weapon blend reaching
1.0 and returning to 0.0, eight shots emptying the magazine with no incident from
any of them, the shot at zero starting nothing, the reload refilling and releasing
movement, a save/load round-trip of the count, one shot taking an NPC to zero
health and leaving it in the terminal phase six seconds later, and the HUD row
appearing, tracking and hiding. Import pass and headless boot clean.

**Left for eyes:** whether the carbine reads as two-handed in the hands (the held
mesh attaches to `RightHand` only — the left hand is placed by the clips and the
mesh will not track it), whether the rifle locomotion blends cleanly, whether the
walk-uses-the-run-clip gap matters, and whether the ammo row sits right.
H6 is **not** closed in `docs/scope_horizon.md` — that waits on a clean playtest.

*Пистолет заменён на двуручный карабин: под него в проекте есть полный набор
анимаций, включая восьминаправленную локомоцию, чего у пистолета нет. Выстрел
убивает с одного раза (урон 150 против 100 здоровья). Добавлены магазин
(`WeaponComponent`, перезарядка на `R`) и строка патронов в HUD под здоровьем.
Анимация подбора выбирается по высоте предмета. Карабин не влезает в карман —
носится на спине, для чего слоты тела научились принимать не-одежду.*

---

## 2026-08-26 - Tab draws and holsters, the key cycles, the scrap pipe is gone

Picking the pistol up wasn't enough to hold it: the draw key produced a punch.

Three causes, all from the H6 work. `_on_draw_holster_pressed()` drew the
**first** item with `can_use_in_hands`, and the starter `scrap_pipe` sat in
`torso/chest_left`, ahead of the pistol in `chest_right` — so the key always
handed over the pipe, whose `ranged_damage` is 0, so the click fell through to
the punch. The function's own comment had admitted the shortcut: *"First is good
enough while there is one weapon — a real weapon-selection UI is H6's problem"*.
H6 was the job and this was left. And `starter_stowed_ids` carried its own
instruction — *"empty this once there is a weapon the player actually finds in
the world"* — which H6 also walked past.

**The key now cycles**: empty hands draw the first drawable, pressing again
holsters it and draws the next, the press after the last leaves the hands empty.
Deliberately no ranking — no "prefer a firearm" rule. Which of two things in your
pockets you want in your hand is a decision, and a hierarchy in code only has to
be renegotiated with every third item.

**`draw_holster` moved from `B` to `Tab`**, and `toggle_tabs` was retired to free
it. That action was documented as "tap — notifier; hold — status camera", but
nothing in the project ever subscribed to `tabs_key_tapped` or `tabs_key_held`
and neither feature exists — it relayed a press to no one for its whole life.
Two actions cannot share a key, and the choice was between one named for what it
does and one named after a key for features never built. `input_map.md` records
that the notifier and status camera now have **no** key and need one assigned
when either lands, so the idea does not vanish quietly.

**The scrap pipe is deleted** — `starter_stowed_ids` emptied, `scrap_pipe.tres`
and its catalog entry removed. Nothing in any scene referenced it.

**And the HUD now says the key exists.** `draw_holster` was missing from
`data/key_hints.tres` entirely, so the panel whose whole job is showing the
currently valid actions never mentioned it. That omission is what turned a wrong
binding into "how do I even get it out".

One bug the run caught in the new code before it shipped: the cycle checked "is
there anything to draw" before checking the hands, and a drawn item is in no
pocket — so with a single weapon the list was empty while it was held and the
key refused to holster. Hands first, then the list.

Verified in `world.tscn` through the real signals, not by calling `draw()`:
empty starter body → press is a no-op; walk up and `try_interact()` → pistol in a
pocket; `draw_holster_pressed` → `get_drawn() == "pistol"`; click → `_drawn_firearm()`
resolves and an NPC on a clear line goes 1.000 → 0.660; press again → hands empty
and the pistol back in the slot it came from; once more → drawn again. Second
import pass 0 errors / 0 warnings, boot 0 script errors, no `scrap_pipe` left
anywhere outside this log.

> *Пистолет подбирался, но в руки не шёл: клавиша доставала стартовую трубу из
> более раннего кармана, а у трубы нет `ranged_damage`, поэтому клик уходил в
> удар. Теперь клавиша перебирает предметы, а не берёт первый; переехала с `B`
> на `Tab`, ради чего снят `toggle_tabs` — его никто никогда не слушал, обе
> обещанные фичи не построены, и в `input_map.md` записано, что им нужна новая
> клавиша. Труба удалена совсем. И главное: `draw_holster` вообще не было в
> подсказках — панель молчала про клавишу. Прогон поймал ещё и мою свежую
> ошибку: проверка «есть ли что доставать» стояла до проверки рук, а вынутый
> предмет ни в одном кармане не лежит, поэтому убрать оружие было нельзя.*
- `project.godot`, `core/input/input_systems.gd`, `player/player.gd`, `equipment_component.gd`, `data/key_hints.tres`, `data/items/catalog.tres`, `input_map.md`, `docs/architecture/items_and_equipment.md`; deleted `data/items/scrap_pipe.tres`

---

## 2026-08-26 - The pistol was lying below the player's focus cast

No tick over it, and `F` did nothing — reported from playtest.

`PlayerFocusCast` is a capsule at y 1.3 with radius 0.4: it sees roughly 0.9 m to
1.7 m above the feet, and `player.tscn` marks that reach as a deliberate
gameplay choice. The pistol was placed on the terrain, 0.13 m above ground, so it
never entered the volume — `on_detected_by_player()` never fired, no tick,
`current_interactable` stayed null, and the interact key had nothing to act on.

Fixed on the object rather than the player: the pistol's detection `Area3D` grew
from a snug `0.5 × 0.5 × 0.6` to `0.7 × 2.4 × 0.7` centred a metre above its
origin. A small thing on the ground is entitled to a tall detection volume —
that is what the `Area` is for — and the player's tuned capsule stays untouched.

**The reporting failure behind this is the part worth keeping.** The S1–S2 probe
called `player.store_item()` and checked the save round-trip, and the entry
claimed pickup was verified. Those are the second half. The half that was broken
— `detect_interactable()` → `on_detected_by_player()` → tick → `try_interact()` —
had never been executed once. The replacement probe drives that path: it stands
the player in front of the pistol in `world.tscn` and asserts
`current_interactable`, then the indicator's own `is_sprite_visible`, and only
then storage. It was run against the unfixed scene first and failed at step one,
which is what makes the pass meaningful.

> *Пистолет лежал ниже зоны обнаружения игрока: капсула фокуса видит примерно
> 0.9–1.7 м над ступнями, а он был в 0.13 м. Увеличена зона самого объекта
> (0.7 × 2.4 × 0.7, центр на метр выше origin), капсула игрока не тронута.
> Важнее сам урок: прошлый зонд дёргал store_item() напрямую и объявил подбор
> проверенным, ни разу не пройдя путь обнаружения. Новый зонд идёт настоящим
> путём и сначала был прогнан на сломанной сцене.*
- `world/interactables/pistol/pistol.tscn`, `docs/architecture/items_and_equipment.md`

---

## 2026-08-26 - The camera never left ISOMETRIC: restoring a deleted else

Pressing `V` changed `PlayerState.view_mode` but left the camera sitting in its
isometric position — reported from playtest as "camera behaves oddly, doesn't
fully switch to TPS".

`dae379e` ("ISOMETRIC look-ahead, and the wall clamp moved after the spring")
removed two lines along with the exponential it replaced:

```gdscript
	else:
		camera_current_pos = camera_current_pos.lerp(camera_target_pos, …position_follow_speed…)
```

That `else` was the position filter for TPS **and for both directions of the view
transition**. Without it `camera_current_pos` was written nowhere except inside
`if view_mode == ISOMETRIC and not view_mode_animating` — so `V` set
`view_mode_animating`, skipped the block, and froze the camera body; when the
transition finished the mode was TPS and the block was skipped again. Rotation
kept lerping on its own line below, which is why it read as strange rather than
dead. The comment above the branch still described "the exponential everywhere
else" the whole time, so the code and its own documentation disagreed rather than
the design having changed.

Restored, with the history in a comment so it is not deleted a second time.
`position_follow_speed` was already computed immediately above and already
resolves correctly for both cases, so nothing else moved.

Measured, in `world.tscn`, driving the real transition: before, the camera
travelled **0.00 m** on the switch and stayed 10.06 m from the character; after,
7.29 m and 2.87 m. Toggling back returns it to 8.44 m. The check was run against
the unfixed file first — a test that has not failed on the bug is not evidence.

Not from the H6 pistol work, which touches no camera or `PlayerState` file; found
by `git log -S` on the deleted expression while checking that claim rather than
asserting it.

> *Камера не уходила в TPS: коммит `dae379e` вместе с заменённой экспонентой
> удалил ветку `else`, которая двигала камеру в TPS и во время самого перехода.
> Позиция обновлялась только в блоке «изо и переход не идёт», поэтому нажатие V
> её замораживало. Поворот продолжал работать отдельной строкой — отсюда
> «странно». Возвращено, с историей в комментарии. Проверено прогоном: было 0.00
> м смещения, стало 7.29 м; сначала прогнал на несломанном файле, чтобы тест
> точно ловил баг.*
- `camera/camera_component/on_foot_camera_component.gd`, `docs/architecture/player_and_camera.md`

---

## 2026-08-26 - Draw it, carry it, fire it (H6 S3-S5) — the slice closes

**One gesture node, three clips.** A second `AnimationNodeOneShot`
(`weapon_oneshot`) chained after the punch's and feeding `death_transition`,
with a single `weapon_clip` whose animation is rewritten immediately before
each request. Two one-shots rather than one, because `is_punch_active()` and
`is_weapon_gesture_active()` are what `player.gd` polls to know when to give
movement back and sharing a node would make the two questions
indistinguishable; but one clip node, because draw, holster and fire are
mutually exclusive uses of the same hands. Every clip was already in the
project — `new4/equip-hip-fast`, `new4/equip-thigh`, `WeaponChange_hip`,
`new4/shoot-pistol`. Nothing imported, nothing mounted.

**The draw follows the slot, not the other way round.** `EquipmentComponent`
gained `get_drawn_from()`, and `player.gd` picks `equip-thigh` or
`equip-hip-fast` from the slot id. `stow_anywhere()` keeps choosing the pocket
— per Stan, a firearm belongs in a future jacket's chest pocket, so forcing a
slot would have been backwards.

**Carrying** substitutes `new4/idle-pistol` into the COMBAT blend space's
centre point while something is drawn (`set_drawn_idle()`), leaving all eight
directional points alone. Verified that a live `AnimationNodeAnimation.animation`
write is picked up by a running `AnimationTree`.

**The held mesh now waits for the hand.** `draw_attach_delay` (0.22 s) on
`EquipmentVisualsComponent`, with a re-check after the wait so a quick
draw-then-holster cannot leave a pistol floating in an empty hand. The delay
lives with the mesh rather than on `player.gd`: "when does it appear" is a
presentation question, and a second copy of the number in another file is the
duplication this project keeps getting bitten by.

**Firing** mirrors the punch — same COMBAT/ON_FOOT/standing-still gates, a
one-shot, a timer for the impact frame — and differs in two places: the target
search runs at `shot_range` with a narrow `shot_angle_deg` instead of a fist's
cone, and a single ray against `CollisionLayers.SIGHT` refuses a shot through a
wall. Damage goes through the existing `take_hit()`, so knockdown, the witness
chain and the comic layer all follow unchanged. A blocked or missed shot emits
the existing `punch_missed`, so a shot at nothing is noticed exactly as a
whiffed swing is.

**One new field, and it earns its place.** `ItemResource.ranged_damage`
(0 = not a firearm). `readability` cannot separate a pistol from a scrap pipe —
both are THREATENING and `can_use_in_hands` — and the equipment contract's "no
invented is-a-weapon flag was needed" was about *drawing*, which genuinely
needed none. One field rather than a bool beside a number, because a flag can
disagree with the number. Range stays on `player.gd` next to `punch_reach`:
reach belongs to whoever is holding the thing.

`IncidentRegistry` subscribes to `shot_landed` alongside `punch_landed`, both
duck-typed, both `Kind.ASSAULT`.

**A bug only running could find.** `_has_clear_shot()` originally aimed
chest-to-chest — but `get_chest_height()` exists on the player and *not* on
`NPCBase`, which exposes only eye and shoulder. The call failed silently and
the check returned false for every shot, including across open sea. Now
shoulder-to-shoulder, which both carry and which the TPS camera already pivots
on.

Two things the probe taught about the world, worth writing down: tower
silhouettes sit on `CollisionLayers.WALL`, so a character standing inside a
generated block's footprint has no clear line to anything — correct behaviour
for the mask, surprising the first time it bites. And an occlusion test that
relies on a generated building standing in the right place is not a test; the
committed check authors its own wall.

Verified in `world.tscn` with the real player, a real NPC and the live
registry: draw sets COMBAT and fires the gesture; a shot at 2.5 m takes health
1.000 → 0.660 (34 of 100) and puts one ASSAULT incident in the registry under
`player`; the same shot through an authored wall does neither and reports a
miss; a shot at nothing reports a miss; holstering returns the pistol to
`torso/chest_right` and it survives in the save payload. Second import pass 0
errors / 0 warnings; boot 0 script errors and only the three pre-existing
warnings. Probes deleted, not committed.

**H6's Definition of Done is met** — found on the island, picked up, saved,
drawn, carried, fired, damage through the existing path, incident recorded.
Not seen by eye: whether the placeholder reads as a pistol, whether the draw
reads as a draw, whether `idle-pistol` blends cleanly, and whether the held
offsets sit right in the palm.

> *Слайс закрыт. Жест один узел на три клипа — все клипы уже были в проекте.
> Анимация доставания выбирается по слоту, а не слот под анимацию. Меш
> появляется в руке с задержкой и с перепроверкой, чтобы не повис в пустой
> ладони. Выстрел — копия удара, но луч вместо конуса плюс проверка стены;
> урон и инцидент идут по существующим путям. Новое поле ranged_damage: по
> readability пистолет от трубы не отличить. Найден настоящий баг: у NPC нет
> get_chest_height(), из-за чего проверка линии огня всегда возвращала «занято»
> — перешёл на плечи. Проверено в живом мире: 34 урона из 100, запись в
> реестре, за стеной — промах.*
- `player/player.gd`, `player_animation_component.gd`, `equipment_component.gd`, `equipment_visuals_component.gd`, `core/items/item_resource.gd`, `data/items/pistol.tres`, `core/world/incident_registry/incident_registry.gd`

---

## 2026-08-26 - Pistol as an item, and the first thing in the world you can pick up (H6 S1-S2)

**The pistol exists as data.** `data/items/pistol.tres` — `size_class = POCKET`
(the size model was written with "a pistol must fit a jacket pocket" as its
worked example), `readability = THREATENING`, `can_use_in_hands = true`,
`can_throw = false` — registered in `data/items/catalog.tres` and resolving
through `ItemCatalog.get_item(&"pistol")`.

**The placeholder mesh is one `ArrayMesh` with two surfaces**, grip and barrel,
generated once by a throwaway tool and committed as
`data/items/meshes/pistol_placeholder.res`. `ItemResource.held_mesh` takes a
single `Mesh` by deliberate contract; widening it to accept a scene for the sake
of temporary art would have spent a real design decision on a placeholder.
Barrel along +Z, matching the project's visual-forward convention.

**`world/interactables/pistol/pistol.tscn` is the first object in this project
that can actually be picked up.** `test_can` and `scrap_pipe` were item resources
with nothing in the world holding them, and the only `InteractableObject`
instance anywhere was `LodgingRoom`'s `BedPoint`. So this scene is the shape
later pickups copy, and its parts are not optional: the `Area3D` must be named
`Area` and the indicator must be a child named `InteractiveVisualIndicator`,
both being `@onready` path lookups that fail silently on a rename.
`interaction_type = INVENTORY_ONLY` routes it to the body through
`player.gd`'s `store_item()`.

**The tick over a spotted object needed a texture, not code.**
`InteractiveVisualIndicator._ready()` returns early unless
`indicator_sprite_texture` is set — which is why `BedPoint`'s indicator has
never shown anything. The pistol assigns `assets/icons/icon_interactive.png`.

**A placed pickup is frozen, and the reason was measured rather than assumed.**
A downward ray at the spawn area reports a **22 degree slope**, and a
box-shaped `RigidBody3D` there never sleeps: first placement drifted 2.15 m in
three seconds and was still moving. `freeze = true` is set on the instance in
`world.tscn`, not in `pistol.tscn`, so the scene stays physical for a future
dropped instance while the authored one holds position (re-measured: 0.0000 m
drift over five seconds). Height comes from the ground ray (Y 128.762) plus the
mesh AABB minimum, not from `world_data.tres`'s `spawn_point` — that value is Y
130.062, nearly two metres above the ground it names.

**Persistence needed no work, which is worth stating because it looks like it
should.** Verified by round-trip rather than by reading: storing the pistol puts
it in `torso/chest_right`, `EquipmentComponent.get_save_data()` carries
`{"pockets": {"torso/chest_right": "pistol"}, ...}`, and a fresh component fed
that payload has it back.

One finding that changes a plan decision: **`stow_anywhere()` picks the first
EMPTY pocket and takes no preference argument**, so the pistol lands in
`chest_right` (the starter `scrap_pipe` holds `chest_left`), not the thigh
pocket the plan named. Forcing a slot would need new API. The better shape, for
S3: choose the draw clip from `_drawn_from` at draw time —
`new4/equip-hip-fast` for a chest pocket, `new4/equip-thigh` for a thigh one.

Verified: second import pass 0 errors / 0 warnings; `world.tscn` boots headless
with 0 script errors and only the three pre-existing warnings (UI anchors,
`NavigationRegion3D`, ObjectDB at exit). Probes and the mesh generator were
deleted, not committed. Not seen by eye — whether the placeholder reads as a
pistol is Stan's call.

> *Пистолет появился как предмет и как первая подбираемая вещь в проекте.
> Плейсхолдер-меш — один `ArrayMesh` из двух поверхностей (рукоять и дуло),
> сгенерирован разово. Сцена подбора — образец для всех будущих: `Area` и
> индикатор ищутся по имени и молча ломаются при переименовании. Галочке нужна
> была текстура, а не код. Размещённый экземпляр заморожен: у спавна склон 22°,
> и коробка на нём не засыпает — уползала на 2 м за три секунды. Сохранение
> работало и так, проверено круговым тестом. Карман выбирает сам
> `stow_anywhere()` — не бедренный, а первый свободный; анимацию доставания на
> S3 надо брать от слота, а не наоборот.*
- `data/items/pistol.tres`, `data/items/meshes/pistol_placeholder.res`, `data/items/catalog.tres`, `world/interactables/pistol/pistol.tscn`, `world/world.tscn`, `docs/architecture/items_and_equipment.md`

---

## 2026-08-26 - Scope review: island and H3/H4 closed, H6 promoted, camera recorded as out of plan

Documents only. No engine code changed.

**The island horizon was done and the page did not know it.** `scope_horizon.md`
still had step 5 — the building generator — marked "Open. This is what *now*
means," last reviewed 2026-08-25. It is closed, and by evidence rather than
assertion: `tools/city_generator/` holds all four files, `map_source.tscn`
carries 151 `GBX_` markers (exactly the dry-run figure), and
`data/world_data.tres` holds 152 `BlockData` entries — `landmark`, `tower_001`
and `cty_001`–`cty_150`. So Export ran and the runtime streams the generated
city. The 2026-08-25 entry's own caveat, that markers actually appearing in
`BLOCKS` would be Stan's first run, is discharged.

**H3 and H4 closed as concepts**, by Stan's decision. Closing them means they
stop gating the next horizon, not that they are finished; refinement is
deliberately deferred past H6 and is now its own entry under Next.

**The §7 witness slice was measured before being called closed.** A throwaway
probe scene drove `IdleNPCController._on_incident_reported()` against a Clerk
and read the same getters the observation panel uses. A, B, D and E pass. C
does not, and the reason is arithmetic: SILHOUETTE needs distance > 30 m, but
`earshot_radius` (25 m) and Clerk's `vision_range` (16 m) both close first, so
the reachable witness envelope is 0–16 m and the top rung of the ceiling
ladder is unreachable by construction. Recorded in `attribution.md` §7 with the
boundary probes (12 m → EQUIPMENT, 20 m → no report) rather than fixed — it is
a tuning decision, not a defect in the chain.

Two smaller notes landed with it: `_cancel_active_witness_report()` nulls the
report after setting CANCELLED, so the panel reads `n/a` instead of the
terminal status — behaviour correct, observability thin; and case D's reaction
varies run to run, which is `flee_probability` working, not flakiness.

**H6 (pistol chain) promoted to Now.** Its only prerequisite, H5, closed
2026-08-23; the island reason to hold a weapon back is spent; H3/H4 no longer
gate it. Step 3 (draw/holster) is largely met by H5 S5 already, so the slice
starts nearer the middle than its own list suggests.

**The ISOMETRIC camera work is recorded under a new "Out of plan" heading.**
Phases 1 → 5B ran alongside the island horizon without ever appearing on the
page, and it is **not finished** — collision response and a refactoring pass
remain. It is tracked in its own session, not in the H-series order; the
section exists so the time budget this file governs does not look as though it
went entirely to plan.

Also corrected: `core_loop.md` §8 said "six archetypes" where the design and
the data have always had five, and its "one blocking gap" now carries a note
that the blocker is closed while the fidelity is not.

> *Ревизия скоупа, только документы. Островной горизонт был закрыт по факту, но
> страница об этом не знала — шаг 5 подтверждён данными: 151 маркер в сцене, 152
> блока в `world_data.tres`. H3 и H4 закрыты как концепты (доработка — сильно
> позже), но перед закрытием прогнаны тест-кейсы §7: A, B, D, E проходят, C не
> может пройти в принципе — SILHOUETTE требует >30 м, а слух 25 м и зрение
> клерка 16 м закрываются раньше. Пистолет поднят в Now. Фазы изо-камеры внесены
> отдельным разделом «вне плана» с пометкой, что работа не закончена.*
- `docs/scope_horizon.md`, `docs/attribution.md`, `docs/core_loop.md`

---

## 2026-08-27 - Front half of the turn circle softened; destination reversal (Phase 5B)

Splits the circle in two and lets each half behave the way it actually
wants to, which the single angle-keyed curve could not.

**Front half softened.** Phase 5A's easing-only pass lowered a small turn's
peak by a fifth and that was still not enough — a correction inside the
front half kept reading as the camera clicking round after the body. The
remaining lever is time, because at a fixed angle the average speed is
duration and nothing else, so `_turn_soften_for()` multiplies the duration
by `turn_soften_front` (1.25) across the front half, by nothing across the
back half, with one octant of blend so there is no cliff at the boundary.
Measured: 45° now 0.317 s at 212°/s (5A 265, originally 337), 90° 0.450 s
at 323°/s (5A 403, originally 477). 135° and 180° are **bit-identical to
5A** — a reversal is not a follow and must not become a slow pan across the
world. Duration is deliberately non-monotonic as a result: 90° takes longer
than 135°, because 135° covers over twice the angle at 536°/s against
323°/s.

**Destination reversal, now built.** `_try_destination_reversal()` reads
`Frame.move_target` and commits a reversal immediately when the click is
past `reversal_threshold_deg` (112.5°, `SNAP_STEP * 2.5` — the boundary
between the octants in front of the camera and those behind it). Two
witnesses on purpose: the body heading answers "where is this character
going", the destination answers "what did the player just decide", and with
click-to-move the second is known a whole turn-and-accelerate before the
first agrees with it. It is also the case the hysteresis and dwell gates
get wrong — a body swinging through 180° passes through every intermediate
octant, each a plausible candidate, so the gates either commit somewhere
nobody asked for or sit out the rotation and move afterwards. It bypasses
the standing-still gate too: that gate exists to ignore idle fidgeting, and
a move order is not fidgeting.

Verified: front/back durations and peaks as tabled; a click behind starts
the turn on the **next frame** with no dwell wait and lands on exactly π; a
click 40° or 90° ahead while standing still moves the camera not at all;
the body spun 180° on the spot with no click still rotates nothing, so the
model's headline property survives; a behind-destination held for six
seconds commits exactly one turn; a 180° click only 0.5 m away is ignored.

> *Фаза 5B. Круг разделён на половины. Передняя смягчена по времени
> (×1.25): 45° теперь 212 °/с вместо 337 исходных, 90° — 323 вместо 477.
> Задняя не тронута совсем — разворот назад должен приходить как решение, а
> не ехать со скоростью следования. Побочно длительность стала
> немонотонной, и это намеренно. Плюс внедрён триггер по destination: клик
> за спину распознаётся из move_target мгновенно, минуя гистерезис, выдержку
> и гейт неподвижности — намерение игрока известно задолго до того, как тело
> успеет повернуться.*

---

## 2026-08-27 - Adaptive turn character for small ISOMETRIC turns (Phase 5A)

Durations, octants, hysteresis, dwell, look-ahead, head-look, cursor edge
framing and the whole collision path are untouched. Only the *shape* of a
turn changed.

The complaint was that every octant turn had much the same character
whatever the angle, so a small correction read as the camera clicking round
after the body. There is a hard constraint underneath that worth stating:
at a fixed duration and angle the average angular speed is already decided,
and every curve's peak is at least the average — so "less aggressive" can
only mean **lower peak**, which means flatter, not rounder. A higher-order
ease has softer ends and a *higher* peak, the opposite of what a small turn
wants.

So the profile is now a trapezoid in angular velocity with smootherstep
corners (`_turn_ease()`): it ramps up over `ramp` of the duration, holds a
plateau, ramps down over the same fraction. The area is fixed — the turn
covers its angle in its time whatever shape it takes — so the plateau is
`1/(1-ramp)` times the average, and a smaller ramp flattens the peak.
`_turn_ramp_for()` interpolates `TURN_RAMP_SMALL` (0.32) at one octant to
`TURN_RAMP_LARGE` (0.467) at a reversal, that upper value being exactly
where the profile matches the plain smootherstep it replaces.

Measured peak angular speed at unchanged durations: 45° 265°/s (was 337,
**-21.5%**), 90° 403 (was 477, -15.5%), 135° 536 (was 584, -8.3%), 180°
675 (was 675, **+0.1%**). First- and last-frame speeds stay near zero at
every size, every turn still lands on exactly 1.000000, the ease is
strictly non-decreasing at every ramp, and the area check holds for ramps
from 0.05 to 0.5.

Not built, and named here so it is not lost: splitting `body_heading_delta`
from `destination_heading_delta`, so a click *behind* the character is read
as deliberate reversal while a small drift of body heading is only ever a
soft follow. `Frame.move_target` already carries the destination, so the
plumbing exists; the trigger does not. Held back on purpose until the
three-step dynamic above is judged in play.

> *Фаза 5A: изменён только характер доворота, тайминги не тронуты. Профиль
> угловой скорости стал трапецией со smootherstep-углами: площадь под ним
> фиксирована, поэтому «мягче» достижимо исключительно снижением пика, то
> есть уплощением, а не более гладкой кривой — кривая более высокого
> порядка даёт пик ВЫШЕ. Малый поворот стал мягче на 21.5%, разворот на
> 180° остался прежним с точностью до 0.1%.*

---

## 2026-08-27 - ISOMETRIC look-ahead, and wall clamp moved after the spring

Feel untouched again: octants, yaw rates, head-look and the position spring
are as they were.

**The camera now aims through the character rather than at them.** At full
strength the look target moves 2.0 m forward along the camera's horizontal
forward and 0.4 m up while the camera sinks 0.3 m; pitch is *derived* from
camera-to-target and yaw is left entirely to the octant. Strength is
`speed_ratio * 0.7 + cursor_edge_weight * 0.5`, clamped and eased.

This answers "the camera is still catching up with my body" without
touching yaw speed, and deliberately so: yaw speed trades smoothness
against responsiveness and no setting gives both, because they are the same
quantity. Look-ahead is a different quantity — the space the player is
running into is shown *before* the turn finishes, so the octant turn never
has to be hurried. **No yaw is produced, structurally rather than by
promise**: the offset runs along the camera's own horizontal forward, so
camera, follow point and look target stay in one vertical plane. Measured
deviation over 16 bearings x 11 strengths is 8.9e-8 rad — float epsilon.
Measured tilt at full strength: +6.05° at 15 m of zoom, +8.71° at the 10 m
near edge, +5.25° at 17.5 m.

**The wall clamp moved to after the position spring**, where the ordering
diagram in the brief already assumed it was. It was not: Phase 3 clamped
`camera_target_pos`, so the "immediate" retract was immediate only for the
target and the spring then took its own 0.08 s to carry the camera there —
longer, at `run_speed` 15.5, than the 0.7 m of sphere-plus-margin clearance
lasts. It now clamps `camera_current_pos` itself, so the retract is
immediate for the camera and the spring cannot hold a position inside the
wall to snap back out to. The look target is built before the clamp runs,
so a wall changes where the camera is and never where it aims.

Edge tuning as requested: `CURSOR_EDGE_DEAD_ZONE` 0.70 -> 0.65,
`CURSOR_BIAS_DISTANCE` 2.9 -> 3.4.

Verified by import pass, headless boot, a standalone solve of the framing
maths (yaw deviation at epsilon, pitch curve across strength and zoom), and
a live probe in which the idle look-ahead settled at exactly 0.375 — the
measured corner weight 0.750 times the cursor share 0.5, confirming the
edge ramp, corner softening and look-ahead share all agree end to end.
Behaviour against real walls and the feel of the tilt still need eyes.

> *Look-ahead: камера целится сквозь персонажа вперёд, а не в него. Питч
> выводится из точки взгляда, yaw остаётся за октантами — отклонение yaw
> 8.9e-8 рад, то есть ноль по построению. Это ответ на «камера догоняет
> тело» без ускорения поворота: скорость yaw меняет плавность на
> отзывчивость и обратно, а look-ahead показывает пространство раньше, чем
> поворот закончится. Плюс перенёс кламп стен за пружину — в фазе 3 он
> стоял до неё, и мгновенный отъезд был мгновенным только у цели.*

---

## 2026-08-27 - ISOMETRIC wall safety and screen-edge framing (Phases 3 and 4)

Camera feel deliberately left alone this pass — the brief was wall clipping
and cursor framing, and nothing in the octant model, follow point, position
spring or head-look limits was retuned.

**Phase 3 — wall safety.** ISOMETRIC had no collision check at all; only
TPS did. A **sphere** `cast_motion()` now runs from the pivot toward the
unobstructed camera position along `CollisionLayers.CAMERA_OCCLUSION`. A
sphere rather than a ray because a ray asks whether the camera's
mathematical *centre* has crossed the wall — answered late, and flipping
the frame the centre crosses a silhouette edge — while a sphere reports the
surface a radius early and its answer then varies continuously as the
player walks, so the retraction is a smooth ramp before any filtering.
Retract is immediate and restore is eased at `ISO_COLLISION_RESTORE_RATE`:
being inside a wall is a correctness failure, being further out than
necessary costs nothing. The probe starts at eye height, since the follow
point rides the tracked *ground* height and would report a hit on the
floor. `current_zoom_distance` is untouched — a wall must not rewrite the
player's zoom or the HUD ruler — and the retracted distance feeds
`_build_iso_frame()` so the dead zone keeps its apparent size while pulled
in.

**Phase 4 — screen-edge framing.** The cursor bias is now gated on distance
to the screen *edge* rather than distance from the character: nothing at
all through the neutral middle 70%, then a smootherstep ramp to full at the
edge, the two axes combined as a capped vector and softened where both are
engaged so a corner reads 0.75 against an edge midpoint's 1.0 instead of
the 1.41 naive axes would give. The mouse is also where the player's hand
rests while reading the screen, so a bias growing with plain distance moved
the frame for no expressed reason. **Deliberately weights a translation and
not a yaw** — an ever-present mouse signal driving rotation would reinstate
the self-moving yaw the octant model exists to remove.

**A discontinuity found while building Phase 4 and fixed at source.**
`_cursor_ground_point()` returned null for rays that never meet the ground,
and at a -35° pitch the top few percent of the screen is sky. The edge bias
ramps *up* toward the edges, so a cursor pushed to the top would lean the
frame nearly all the way and then have it vanish on crossing the horizon.
Such rays now yield a synthetic point along the ground direction at
`CURSOR_RAY_MAX_DISTANCE`; both consumers want a direction more than a
position.

Verified by import pass, headless boot, a live-scene probe (control casts
prove the sphere detects the floor at 3.00 m and clear sky at 20.00 m), a
cursor sweep down the screen confirming a valid ground point at every
height including the whole sky region, and a standalone check of the edge
ramp (zero everywhere inside the dead zone, corner 0.750 against edge
1.000). Wall behaviour in real geometry still needs eyes.

> *Фазы 3 и 4, feel камеры намеренно не трогал. Стены: сферический
> cast_motion от пивота к камере — сфера, а не луч, потому что луч отвечает
> поздно и разрывно на силуэтных кромках. Отъезд мгновенный, возврат
> плавный: быть внутри стены — ошибка корректности, стоять дальше нужного —
> бесплатно. Зум игрока и линейка HUD не переписываются. Курсор: смещение
> кадра теперь гейтится близостью к краю экрана, а не расстоянием до
> персонажа — в середине экрана ноль, у края плавный набор, углы слабее
> середины стороны. Это вес на смещении, а не на yaw. Попутно найден и
> починен разрыв: выше горизонта курсорная точка была null, и вес обрывался
> ровно в главном жесте.*

---

## 2026-08-26 - ISOMETRIC camera output: critically damped position, smootherstep turns

Playtest note from the author: the camera's idea of where to look is right,
it just arrives there too abruptly, and most visibly at sprint. Diagnosis
was position framing rather than yaw, with an explicit instruction not to
touch the octant model, follow-point logic, cursor-bias architecture or
head-look, and not to add a second independent follow state. That is what
this does and no more.

**The output filter's ORDER was the fault, not its rate.** An exponential
is first order: it smooths position and passes a step in the *target's*
velocity through in the same frame. `IsometricCameraState`'s follow point
is assembled from piecewise rules — the dead-zone kink, the moving/settling
rate switch at `SETTLING_SPEED_THRESHOLD`, a lead that collapses on
arrival, a cursor bias that drops out when the ray misses — each continuous
in position and discontinuous in rate of change. At `run_speed` 15.5 a rate
step is a metre of framing inside a fifth of a second. New
`Smoothing.smooth_damp_vector3()` (critically damped, Game Programming Gems
formulation) replaces the position half of the existing pass at
`ISO_POSITION_SMOOTH_TIME` 0.08. Not a second stage: there is still exactly
one filter between the state and the camera. Measured against a 50% step in
target velocity — exponential jerks by 3.05 m/s in one frame, spring by
0.52. The cost is real and budgeted: a spring trails a constant-speed
target by `speed * smooth_time`, 1.24 m at sprint against the exponential's
0.52 m, constant rather than varying, and `LEAD_DISTANCE` already absorbs
constant offsets.

**Rotation deliberately keeps the exponential.** `_current_yaw` leaves a
smootherstep turn already C1, so there is no velocity step to filter, and
springing it would blunt the arrival the octant model exists to produce.

**Turn easing is quintic smootherstep instead of ease-out cubic**, for the
velocity curve rather than the position curve. The cubic opened a 45° turn
at 505 °/s in its first frame — a dead stop to three times its own average
in 16 ms — and only the arrival was smooth. Smootherstep opens at 7 °/s,
peaks at 337 and returns to zero: a bump, not a step, and a lower peak
than the old curve's opening value.

`CURSOR_BIAS_DISTANCE` 2.5 → 2.9, a deliberate 16%. Head-look limits
(35°/25°) and `FOLLOW_RATE_MOVING` (6.0) untouched.

> *Правка по темпоральному отклику, без изменения идеи камеры. Дефектом был
> порядок выходного фильтра, а не его скорость: экспонента — фильтр первого
> порядка и пропускает скачок скорости цели в тот же кадр, а follow point
> собран из кусочных правил. Позиция теперь идёт через критически
> задемпфированную пружину (замена, не второй каскад): скачок скорости на
> разрыве 3.05 → 0.52 м/с ценой +0.7 м постоянного отставания на спринте.
> Поворот оставлен на экспоненте намеренно. Easing доворота переведён на
> smootherstep: старт 505 → 7 °/с, пик ниже на треть.*

---

## 2026-08-26 - Head-turn clamp and turn-size scaling (Phase 2 follow-up)

Two defects in the commit above, both found by the author on first look.

**The head could turn 360°.** The cursor branch handed the rig the cursor's
raw world point with nothing bounding the angle, so a cursor behind the
character asked for a look behind the character. A second, less visible
route made it worse: `PlayerAnimationComponent` lerps the look marker's
*world position*, so a target jumping front-to-back dragged the marker
along a straight line **through** the character, and the look direction
swept every angle as it passed the head. Every branch of
`_update_iso_head_look()` now yields an angle off the body's facing rather
than a point, with one construction at the bottom, so the clamp cannot be
bypassed: `iso_head_look_limit_deg` (35°, matching the glance) as the
backstop, `iso_head_look_cursor_limit_deg` (25°) tighter for the cursor —
a glance is asked for, a cursor is not. Verified across a full 360° cursor
sweep at two body orientations; worst magnitude 25.0°.

**A 180° reversal whip-panned.** A reversal is one turn, not four, and it
was taking the same 0.25 s as a 45° step — 720°/s. `_turn_duration_for()`
now scales the duration by `sqrt(step / 45°)`: 45° stays 0.25 s, 90° takes
0.367 s, 180° takes 0.5 s.

Also measured, against a concern raised on the octant model rather than a
defect: a heading wobbling ±8° across an octant boundary for 20 s commits
**zero** turns, so ping-ponging is impossible. A steady sweep is a
different matter — 180°/s of circling commits zero turns, 90°/s five, and
60°/s or slower the full eight. Eight is the model working, not failing:
any camera that follows heading must rotate 360° over a full circle, so a
gate can only trade turn count against turn size, and eight 45° steps is
the gentlest way to spend a rotation that has to happen. The comment
claiming the dwell reduced this to one turn was wrong and has been
replaced with the measurements.

> *Две правки к коммиту ниже. Голова могла провернуться на 360°: курсорная
> ветка отдавала ригу сырую мировую точку без ограничения угла, а маркер
> взгляда лерпается по мировой позиции — цель позади тянула его по прямой
> сквозь персонажа. Теперь все ветки дают угол от facing тела, а не точку,
> с единственным клампом (35° общий, 25° для курсора). Разворот на 180°
> проходил за те же 0.25 с, что и шаг в 45° — длительность отмасштабирована
> по корню из величины шага. Плюс измерено поведение при обегании объекта:
> дребезг на границе румба не даёт ни одного доворота, медленный круг даёт
> все восемь — и это геометрия, а не дефект.*

---

## 2026-08-26 - ISOMETRIC camera: octant yaw, cursor bias, head turn (Phase 2)

Playtest of Phase 1 reported three things: the world rotated too much, the camera
would not centre on the character during a run, and the directional framing was
not earning its cost. Two of the three turned out to be defects in the pipeline
rather than tuning.

**ISOMETRIC was smoothed twice.** `_update_camera_position()` raised its trailing
follow rates only for TPS; ISOMETRIC fell through to `view_transition_speed`
(4.0), putting a second time constant behind `IsometricCameraState` — whose dead,
soft and hard zones are all measured against the follow point it returns, on the
assumption that the camera sits there. At `run_speed` 15.5 the two stages trailed
by ~8.3 m against a 3.2 m lead, and the hard zone could not clamp anything,
because the point it clamped was not the point being drawn. Rotation had the
matching fault: position used this frame's yaw while `camera.rotation.y` used the
lagged copy, so every turn slid the character across the frame. New
`ISO_FOLLOW_SPEED`/`ISO_ROTATION_SPEED` (30.0) make that pass near-transparent;
`FOLLOW_RATE_MOVING` 3.5 → 6.0 now that it is the only rate that counts.

**The dead zone's vertical axis was measured in the wrong plane.** Forward error
was converted to pixels with the same scale as sideways error, but at a -35°
pitch a ground metre running away from the camera covers `sin(35°) ≈ 0.574` of
the screen a metre running across it does — so `dead_zone_y` behaved as ~0.079.
New `Frame.forward_screen_scale` corrects it; zones shrunk to 0.05/0.03 against
the corrected measurement.

**Yaw is now an octant snap, not a continuous follow.** Eight fixed headings; a
turn commits only after the heading clears the boundary by `snap_hysteresis_deg`
*and* holds for `snap_dwell`, and is then a fixed-duration ease
(`snap_turn_duration`), not exponential damping — damping never arrives, and its
tail is what read as "the world is rotating". Standing still no longer turns the
camera at all, so `recenter_yaw_rate` has no successor. Q/E stays a spring-return
glance, now leaning on a base that holds still.

**Cursor bias and head turn added.** The follow point leans a bounded amount
toward the ground point under the cursor (plane intersection, not a physics
raycast — a physics hit jumps at rooftop edges and would kick the camera), which
is how the praised click-to-move cameras answer "show me where I'm going" without
spending orientation on it. And the character's head now turns: the
`LookAtModifier3D` rig in `PlayerAnimationComponent` had been fully built with
zero callers project-wide, so this only supplies the point — the Q/E glance
first, the cursor while stopped.

Touched `camera/isometric_camera_state.gd`,
`camera/camera_component/on_foot_camera_component.gd`,
`docs/architecture/player_and_camera.md`. Verified by import pass, headless boot
and a throwaway harness over the octant gates (hysteresis, dwell, wrap, turn
arrival, still-body invariance); **feel is unverified — this needs a playtest.**

> *Изокамера, фаза 2. Найдено два дефекта тракта, а не тюнинга: в ISOMETRIC
> демпфирование стояло дважды (из-за чего камера отставала на ~8.3 м на беге и
> зоны меряли не ту точку), а вертикальная мёртвая зона считалась в неверной
> плоскости и была в 1.75 раза шире заявленной. Yaw переведён на снап по 8
> румбам с гистерезисом и выдержкой — поворот на месте больше не крутит мир.
> Добавлены смещение кадра к курсору и поворот головы персонажа (риг уже
> существовал и не имел ни одного вызывающего). Ощущение требует плейтеста.*

---

## 2026-08-26 - ISOMETRIC camera follows the character's direction (Phase 1)

The isometric camera had two sources of yaw racing each other: a four-position
orbit stepped with Q/E, and an optional follow-player-rotation toggle on P.
`IsometricCameraState` owned only the follow point and was handed a camera basis
the host derived from its own `current_angle`. The player had to aim the camera
by hand while moving.

**Yaw is now directional and lives in one place.** `IsometricCameraState` gained
`update_orientation()` and owns `_current_yaw` — the character's movement
direction while moving, their facing once stopped, chosen at the same speed
threshold the follow point already used for settling. `follow_yaw_rate` (4.0) and
`recenter_yaw_rate` (2.2) are the two rates; recentring is the slower of the two
on purpose, so an idle turn on the spot doesn't swing the view. The host's
`current_angle` is now written *from* the state each frame and read only by the
debug labels and the next view transition.

**Call order is load-bearing** and is spelled out in the state's own header:
`update_orientation()`, then the host reads `get_cam_forward()`/`get_cam_right()`
into the `Frame`, then `update()`. The dead zone is measured in the camera plane,
so advancing the follow point against the previous frame's basis while the yaw
moved this frame slides it sideways for no reason the player can see.

**Manual look is Q/E held**, bounded to ±35° and spring-returned
(`iso_look_yaw_limit_deg` / `iso_look_rate_deg` / `iso_look_return_rate`, all on
the host). Not mouse-X, which is what the incoming spec asked for: `InputSystems`
captures the cursor only in TPS, because ISOMETRIC needs it visible for
click-to-move — mouse look here would fire on every ordinary movement toward a
click target and stall at the screen edge. RMB is already the click-to-move
run-hold. Q/E were free precisely because this change retired the orbit they
stepped. The clamp lives on the host and nowhere else: the state receives an
already-bounded number of degrees and holds no input policy.

**Facing crosses the boundary as a vector, and the sign was corrected.** The
incoming spec replaced the transition seed's `target.rotation.y + PI` with a
formula built on Godot's standard −Z forward. This project uses +Z
(`player.gd`'s `get_facing_direction()`, which carries its own "or the sign will
be wrong" warning), so that would have placed the camera in front of the
character's face at every angle — the exact 180° flip the spec's own acceptance
test was written to catch. Kept the spec's intent (one shared conversion for the
seed and for `_reset_yaw()`, no hand-written `+ PI`) and fed it
`get_facing_direction()` instead; verified numerically that it reproduces
`r + PI` at every angle.

`enter()` now calls `request_reset()` rather than `reset()`: `reset()` clears the
flag `update_orientation()` reads, so resetting the follow point directly would
place it correctly and then let the yaw smooth out of a stale value.

Q/E and P labels in the debug panel were corrected in the same commit rather than
deferred — this change is what made them false. Files: `camera/isometric_camera_state.gd`,
`camera/camera_component/on_foot_camera_component.gd`, `core/input/input_systems.gd`
(held `is_lean_*_pressed()`), `input_map.md`, `ARCHITECTURE.md`.

**One reset flag per channel, found by running it.** `update_orientation()` and
`update()` reset different things — the yaw and the follow point — but cleared a
single shared `_needs_reset`, and only `reset()` (called from `update()`) cleared
it. Paired, as the host calls them, that works. Driven apart, `update_orientation()`
takes the reset path every frame: the yaw pins to the character's direction and the
manual look does nothing at all, silently. A harness that exercised orientation
without `update()` hit exactly that. Split into `_needs_reset` and
`_needs_yaw_reset`, each cleared by the method that owns it.

Phase 1 only. The dead orbit infrastructure (`OrbitalPosition`, `POSITION_ANGLES`,
`_handle_rotation_input`, `follow_player_rotation` and their animations) is left
unreached in place, to be deleted in its own commit once the feel is confirmed;
the debug overlay's direction lines are Phase 1B.

**Verified with the Godot CLI** (4.7.2, via `.claude/hooks/ensure_godot.sh`): second
import pass clean — 0 errors, 0 warnings; `world.tscn` boots headless with no script
errors and no `push_warning` from `_target_facing_direction()`, so the duck-typed
getter resolves and the camera is not running on its fallback. A temporary probe in
the running engine confirmed the sign at `rotation.y = 0`: facing `(0.00, 1.00)`
(+Z, as the project's convention says), yaw `180°`, `cam_forward` identical to
facing (`dot = +1.000`) and the camera offset opposite it (`dot = -1.000`) — behind
the character, which is acceptance test #1 passing in the engine rather than on
paper. A synthetic harness covered what a stationary boot cannot: reset-snap at four
angles, convergence while moving, the moving/stopped rate asymmetry (0.978 vs 0.866
after 0.5 s on a 90° turn), the ±35° bound, the look riding the base through a
character turn, and a degenerate direction not producing NaN. Probe and harness were
both reverted; neither is committed.

Still open for the playtest, because headless cannot answer them: whether Q pans
left and E right on screen (needs held input and a rendered frame — the maths is
verified, the screen-direction convention is not), and whether the feel is right.

> ИЗО-камера теперь смотрит туда, куда персонаж идёт (а стоя — куда смотрит);
> yaw живёт в `IsometricCameraState` в единственном экземпляре, `current_angle`
> стал приёмником, а не источником. Осмотр — удержание Q/E, ±35°, с возвратом
> пружиной; мышь не годится, потому что в ИЗО курсор видим для click-to-move.
> Знак facing исправлен относительно присланного ТЗ: в проекте forward = +Z, и
> вариант из ТЗ ставил камеру персонажу в лицо. Орбита и P оставлены в файле
> мёртвыми до подтверждения ощущений. В редакторе не проверялось.

---

## 2026-08-26 - Restore player.gd: the fall-damage commit truncated the file

`ca19b2f` ("Fix false fall damage on island slopes (min air time)") meant to add
three things — a `fall_damage_min_air_time` export, an `_air_time` counter, and a
`_check_fall_damage()` that requires a minimum airborne duration before a landing
can hurt. It did add them, and it also deleted the other 698 lines of
`player/player.gd`, ending the file at line 517 with a literal
`# --- rest of file unchanged ---`. They were not unchanged; they were gone.

The build could not run. `_physics_process()` still called `_handle_jump()`,
`_apply_gravity()`, `_update_speed()`, `_apply_direct_movement()`,
`_handle_navigation()`, `_apply_deceleration()`, `_update_punch()`,
`_handle_stamina_consumption()`, `_update_direct_move_target_speed()`,
`_apply_fall_damage()` and `get_current_max_speed()` — none of which existed any
more. The whole punch path, `_on_died()` and the player's comic-word wiring went
with them. So did three public getters other systems read through duck typing:
`get_facing_direction()` (`tps_combat_camera_state.gd`,
`player_animation_component.gd`), `get_horizontal_direction()` and
`get_move_target()` (`on_foot_camera_component.gd`) — those would have degraded to
a one-time `push_warning` and a dead camera lead rather than a crash, which is the
worse failure of the two: silent.

Restored from `586cd6e`, the last intact revision, with `ca19b2f`'s three intended
edits reapplied in place, so the fall-damage fix is kept in full and nothing else
is re-litigated. 46 functions come back; the only lines this removes relative to
the broken tip are the marker itself and a duplicate `get_speed_ratio()` that the
truncated file had re-pasted at the end. No contract changed, so `CLAUDE.md` is
untouched.

Not verified in the editor — no Godot binary in the session that produced this.
Worth an F5 before trusting it: the claim here is "the file is whole again and
every call target resolves", checked by diffing the function list against both
revisions, not "the game was run".

> `ca19b2f` обрезал `player/player.gd` c 1192 строк до 517, оставив в конце
> `# --- rest of file unchanged ---`. Задуманные три правки про урон от падения на
> месте, остальные 698 строк — удалены, игра не запускалась. Файл восстановлен из
> `586cd6e` с повторно применёнными правками `ca19b2f`. В редакторе не проверялось.

---

## 2026-08-25 - City generator, second attempt: a grid that reads

The first generator was run and rejected on sight — "влепил всё линейно,
выглядит генеративно, нет сетки, в центре нет ничего". All three were fair and
all three had one cause each.

**No grid.** The first version scattered a lattice over the whole island,
tested every intersection for slope and dropped the failures. The land here is
fragmented, so what survived was confetti: points on a pitch, but not one
continuous street. A grid reads from the **corridors between** buildings, not
from the spacing of the buildings.

Now the grid grows in **Chebyshev rings outward from the landmark**, and an
unbuildable cell is left **empty rather than replaced** by a distant buildable
one. The gap reads as a plaza; the row does not break, and the street runs
through. First run: 100 downtown towers over 8 rings with 188 empty cells —
those 188 gaps are the thing that was missing.

**Empty centre.** That was my own `MARUYAMA_RADIUS = 400`, honouring the
brief's "Маруяма остаётся незастроенной". A 400 m hole in the middle of the
island. Per Stan's decision the city now **climbs the volcano** and the brief
is amended in the same commit, struck through rather than quietly deleted. The
landmark stands on the summit at 220 m, so its 1000 m reaches 1220 against a
1250 m ceiling and is visible from everywhere — which is what the brief wanted
of it in the first place.

**Landmark with no retinue.** It used to hunt for the flattest ground and ended
up at (-247, -219), alone. It is now the anchor of the whole layout, and height
falls off by ring (`RING_FALLOFF` 0.88) around it — the retinue is geometry, not
chance.

**Everything goes through map_source now.** Writing `world_data.tres` directly
was my deviation from the brief and it is what left Stan unable to move
anything. The generator now writes `BlockBase` markers into the open scene's
`BLOCKS` node, each with a `SilhouettePreview` child so the towers are visible
and draggable, following `block_placer.gd`'s established `get_scene()` pattern.
`GBX_` prefixed markers are cleared on each run and authored ones are not
touched — the documented convention. `world_data.tres` is written by
map_source's own Export button, as the brief always specified.

`map_source.tscn` gains the island as a backdrop at the origin and loses
`CityZone`, the dead 6600 m city floor that would have covered it.
`map_source.gd` lost its `city_zone_body` reference, which nothing read.

**Three files, and this time for a verified reason.** `EditorScript` cannot be
instantiated outside the editor — Godot answers "Class EditorScript can only be
instantiated by editor". I had merged the logic into the EditorScript to stop
the two similarly-named files confusing which one to Run, and that merge broke
the headless path outright. The logic is back in `CityLayout` (a `RefCounted`),
with `generate_city.gd` and `generate_city_cli.gd` as thin entry points — and
`city_layout.gd` now says in its first line that it is not the file you run.

Also fixed here: reading the heightmap through `Texture2D.get_image()` +
`get_pixel()` is 4.2 million calls on a 2048² map and hung the tool past every
timeout. It now reads the PNG with `Image.load_from_file()` and walks the raw
`PackedByteArray`.

**Dry run:** summit (-2, 38) at 220 m; 100 downtown over 8 rings; 29 of 30 rim
sectors (one has no land); 20 outer belt; 1 top-up; **151 exactly**, heights
200-1000, a library of 32 tower pairs.

**Not verified, and Stan needs to know before running:** markers are written
through `get_scene()`, which is empty headless. The layout numbers above are
measured; *markers actually appearing in `BLOCKS`* is his first run.

*Генератор переделан. Сетка растёт кольцами от главной башни, непригодная
ячейка остаётся ПУСТОЙ, а не подменяется далёкой — из-за этой подмены ряды
съезжали и улиц не было вовсе. Город лезет на Маруяму, главная башня на
вершине окружена кольцами меньших; строку ТЗ про незастроенный конус
зачёркиваю явно. Всё уходит в map_source маркерами — двигать мышью, экспорт
кнопкой. Попутно: EditorScript нельзя создать вне редактора, поэтому логика
вернулась в отдельный класс, а чтение карты высот переехало на сырые байты —
через get_pixel() инструмент висел минутами.*
- `tools/city_generator/city_layout.gd` (new), `generate_city.gd`, `generate_city_cli.gd`, `core/map_source/map_source.tscn`, `core/map_source/map_source.gd`, `docs/island_rescope_brief.md`

---

## 2026-08-25 - City generator (island step 5)

The last open step of `docs/island_rescope_brief.md`. Reads the island's
terrain, lays a Manhattan grid on the buildable ground, hangs a ring of towers
outside it, and writes both the tower scenes and `data/world_data.tres`.

**Run it yourself:** open `tools/city_generator/generate_city.gd` in the script
editor and File -> Run. No scene needs to be open. Headless equivalent:
`godot --headless --script res://tools/city_generator/generate_city_cli.gd`.

**Why three files.** An EditorScript does not execute from `--script` on the
CLI (verified — it silently does nothing), so the logic lives in
`CityGenerator` (a `RefCounted`) with two thin entry points over it: one for a
person in the editor, one for a headless agent run. No duplicated logic.

**What makes the grid readable.** Avenues run N-S 85 m apart, streets E-W 46 m
apart, and the tower footprint is 64 x 30 with its narrow side facing along the
street. The asymmetry is the whole point: from any intersection it is obvious
which axis is the long one, so direction of travel reads without a minimap. A
square cell would be a chessboard with no north.

**Height profile.** 200-700 m, quantized to 25 m so the scene library stays
finite, tallest in the middle and falling off quadratically toward the edge —
a city with a downtown rather than a field of equal posts. Ring towers are
biased tall (70% draw the top of the range) per the brief. One landmark at
1000 m, placed on the flattest ground near the centre.

**Two traps this had to work around, both consequences of the 8-bit heightmap.**
Slope measured between neighbouring samples measures the quantization, not the
terrain — a 1.96 m step over a 6.84 m cell reads as 16 degrees, and a flat
caldera floor is rejected as a cliff. Slope is therefore taken over a five-cell
baseline. And the generator reads the heightmap PNG rather than the island
scene's `HeightMapShape3D`, which was the first choice because it is what the
player collides with — but it lives inside a 41 MB text scene that takes
minutes to parse, and a tool run by hand cannot open with a multi-minute stall.
The two were measured against each other and agree within half a metre.

**Verified by running it here**, not by reading it: 258 buildable intersections
found, 160 taken for the core within a 938 m radius, 40 ring towers on all 40
sectors, 1 landmark, 201 total from a library of 35 tower pairs. Booting the
result gives `Data: 201 blocks`, 37 of them active at the spawn radius, the
player still standing at `(220, 128.81, -140)`, and no new errors or warnings.
The generated output is deliberately **not** committed — it is Stan's run to
make.

Alongside it: `GAMEPLAY_HEIGHT` 1000 -> **1250**, so the 1000 m landmark
standing on a 110 m caldera floor does not have the ceiling resting on its
roof. And `WorldBorderGuardSystem.margin` 500 -> **120**: with a half-extent of
1750, a 500 m margin started turning the player back at 1250 from centre, which
is barely half the map and well inside the island's own shoreline.

*Генератор города — последний открытый шаг островного ТЗ. Манхэттенская сетка:
авеню через 85 м, улицы через 46, башня 64×30 узкой стороной вдоль улицы —
именно несовпадение осей делает направление читаемым. Высоты 200-700 с
профилем «выше к центру», кольцо преимущественно высокое, одна смысловая на
1000. Проверено прогоном: 201 башня, мир грузится, игрок на месте. Потолок
мира 1000 -> 1250, бордер 500 -> 120 (раньше отжимал от собственного берега).
Сгенерированное намеренно не коммичу — запуск ваш.*
- `tools/city_generator/` (new: `city_generator.gd`, `generate_city.gd`, `generate_city_cli.gd`), `core/world/world_systems.gd`, `core/world/world_border_guard.gd`

---

## 2026-08-25 - A clean run: 151 engine messages down to 4

First use of the CLI for what it is actually for. A headless boot printed
**151** errors and warnings; it now prints **4**, and the three that remain
are not defects.

**88 — unnamed animation blend points.** `add_blend_point()` gained a `name`
parameter and warns for every unnamed one, four per NPC and sixteen on the
player, every spawn. All twenty call sites now pass the name the point already
had as a variable.

**54 — stale asset UIDs, and a project font that never loaded.** Root cause:
`*.import` was gitignored. Godot 4 keeps an imported asset's UID inside its
`.import` file, so every clone minted its own while the `.tscn` files kept the
UIDs of whoever saved them. `project.godot` asked for the BlackRock font by a
UID no machine had, so the custom font silently failed to load — an ERROR, not
a warning. `.import` files are now committed (133 of them, Godot's own
recommended layout) and every stale reference rewritten to match; only the
`uid=` field changed, never a path or an id.

**22 — actors with no `actor_id`.** Every NPC and drone in `world.tscn` was
unnamed to `IncidentRegistry`, meaning none of them could be recorded as a
perpetrator or a witness. Each now carries its node name in snake_case, which
is unique in the scene and stable for the save contract.

**9 — `unknown item id ''`, and this one was mine.** `_garment_in()` and
`_apply_body_slot()` both walk every body slot on every call, three of the
player's five being empty, and asked the catalog to resolve `""` each time.
An empty slot is now answered before the catalog is consulted. A non-empty id
that fails to resolve still warns, because that is still a real failure.

The same pass caught a regression I introduced while writing it: the first fix
used `ItemCatalog.find()`, an instance method, on the class. That is a hard
parse error, it took `equipment_component.gd` and everything depending on it
down with it, and one headless run turned it into 177 cascading errors. It also
settles a question this session had only answered indirectly — `find()` is not
callable on the class, `get_item()` is the static form, and Stan had already
converted every call site.

**What is left, and why:** a UI scene with mismatched anchors (cosmetic, an
editor fix), `NavigationRegion3D not found` (true — the island has no navmesh
yet, the system is correctly reporting a missing feature), and two
leaked-at-exit lines that are Godot shutdown noise on `--quit-after`.

Verified after the fact: the player still spawns on the caldera floor at
`(220, 128.81, -140)` with `is_on_floor()` true.

*151 сообщение движка → 4. Безымянные точки блендспейсов (88), протухшие UID
ассетов из-за `*.import` в gitignore (54, включая шрифт проекта, который вообще
не грузился), акторы без `actor_id` (22) и мой собственный баг с пустым id
предмета (9). По ходу поймал собственную же регрессию: `ItemCatalog.find()` на
классе — жёсткая ошибка разбора, положившая пол-проекта; один headless-прогон
превратил её в 177 ошибок и показал сразу.*
- `npc/npc_components/animation_component/npc_animation_component.gd`, `player/player_components/animation_component/player_animation_component.gd`, `player/player_components/equipment_component/equipment_component.gd`, `player/player_components/equipment_visuals_component/equipment_visuals_component.gd`, `world/world.tscn`, `project.godot`, `.gitignore`, 133 `*.import` files (now tracked), 31 scenes/resources with rewritten UIDs, `CLAUDE.md`

---

## 2026-08-25 - Godot CLI in the agent container

Agent sessions run in a throwaway container with no Godot, which is why every
entry above ends with "verify by running it yourself". That is now fixed:
`.claude/hooks/ensure_godot.sh` fetches Godot 4.7.2 at session start — **4
seconds from cold**, the proxy caches it — and exits immediately when `godot`
is already on `PATH`, so it does nothing on a developer machine. The GitHub
Releases page is blocked by the agent proxy, but the redirect through
`downloads.godotengine.org` to the release-asset CDN is allowed; the hook uses
the official domain for that reason.

**What it proved on the first run**, on work that was until now unverified:

- The island commits hold up. `world.tscn` boots, `[World] ✅ Initialized`, 34
  cells built, streaming activates blocks with a 64 ms latency, no errors about
  `GroundTileData` or `strata_ids`.
- **The player stands on the ground.** A temporary probe (run, read, reverted)
  reported `spawn=(220, 130.062, -140)` settling to `(220, 128.81, -140)` with
  `is_on_floor() = true`. This was the risk recorded as unverifiable two
  commits ago — whether the image-row-to-world-Z mapping had the right sign. It
  did.
- H5 equipment works end to end at startup: jumpsuit and boots equipped, the
  pipe stowed in `torso/chest_left`, both garment meshes shown. Which also
  settles a question answered indirectly in the H5 session — `ItemCatalog.find()`
  called on the class is legal GDScript.

**Two things it found.** `_build_cells` still printed `Cells: %d (tiles +
blocks)` after the ground tiles were removed — fixed here. And with 33 blocks
replanted across the island, radius 400 activates only **2** of them at spawn;
the brief sizes that radius for ~25 live towers. The replanted layout is far
sparser than the island is meant to be, which is a fact about step 5's absence,
not about the radius.

**A trap worth recording:** `--check-only --script` compiles a file with no
autoloads registered and reports `Identifier not found: PlayerState` for 36 of
120 scripts, all false. The import pass is the real check, and it must be run
**twice** cold — the first pass compiles scripts before the autoloads they
reference exist and invents three `Cannot infer the type of X` errors that are
gone on the second.

Import touched no tracked files (`.godot/` and `*.import` are gitignored). The
invalid-UID warnings on player textures and the project font predate this and
are cosmetic — Godot falls back to the text path.

*Godot CLI теперь ставится в контейнер агента хуком на старте сессии — 4
секунды с холодного старта. Проверено сразу: мир грузится, стриминг работает,
экипировка надевается, **игрок стоит на земле** — знак Z в спавне был верный,
это был мой главный непроверяемый риск. Найдено две мелочи: устаревшая строка
про плиты и то, что при 33 башнях радиус 400 активирует всего 2 — редко для
острова, но это следствие отсутствия шага 5, а не радиуса.*
- `.claude/hooks/ensure_godot.sh` (new), `.claude/settings.json`, `core/world/streaming_systems.gd`, `CLAUDE.md`

---

## 2026-08-25 - Sea level is Y 45, and the documents say so

**The water plane and the terrain shader disagreed about where the sea is.**
`WaterSystem` sits at Y 45 in `aogashima_island.tscn`; the shader's
`sea_level` was 0, so it painted 45 m of submerged terrain as land instead of
coastal rock, and its `coast_mask` tinted a band nobody could see.

The water is right, and the heightmap settles it: measured off the baked
collision, the island above Y 45 is **2543 × 2570 m**; above Y 0 it is
**3192 × 3124 m**. The brief asks for 2500 on the short side. The water plane
is a deliberate choice that drowns the flat coastal shelf and leaves cliffs —
exactly what the brief describes. `shader_parameter/sea_level` is now 45.

**Documents caught up with the tile grid's removal**, in the same pass:
`docs/architecture/world_streaming.md` (the spawn paragraph still described
the `Y_CITY_ZONE_TOP` clamp that was removed two commits ago — it now says
spawn is a point on the terrain, and which of the two places that store it
wins), `ARCHITECTURE.md` (Ring 0 no longer holds nine tile silhouettes; one
distance metric instead of two), `docs/CONTRIBUTING.md`, `readme.md`,
`CLAUDE.md`'s index row.

`docs/scope_horizon.md` now marks the state of each of the brief's six steps
rather than just listing them: 1, 2, 4 and 6 done, 3 done differently by
decision, **5 open and outstanding** — the building generator is the only
thing left before the island transition can close.

*Вода в сцене стоит на Y 45, а шейдер считал море за 0 — 45 м затопленного
рельефа красились сушей. Права вода: при 45 остров 2543 × 2570 м, ровно то,
что просит ТЗ. Заодно документы догнали снятие сетки: абзац про зажим спавна
описывал зажим, снятый двумя коммитами раньше, а `scope_horizon` теперь
показывает состояние каждого шага ТЗ — открыт только генератор застройки.*
- `world/aogashima/aogashima_island.tscn`, `docs/architecture/world_streaming.md`, `ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `readme.md`, `docs/scope_horizon.md`, `docs/island_rescope_brief.md`, `CLAUDE.md`

---

## 2026-08-25 - The 3x3 ground-tile grid is gone; the island is the ground

Found by reviewing the merge, and bigger than it reads: **the nine ground tiles
were a walkable seabed under the whole ocean.** Each `gt_silhouette_*` is a
`BoxShape3D` 2200 x 10 x 2200 on `collision_layer = 3`, group `floor`, Ring 0 —
permanent, never unloaded — with its top face at Y 0. Nine of them make a solid
**6600 x 6600 m** slab, 1550 m wider than the island's own map on every side.
The island was standing on a concrete plate the size of the old city, and 40
greybox towers stood in the sea around it.

The brief's first decided line is *"one island instead of a 3x3 tile grid"*.

**Code.** `WorldSystems` lost `GROUND_TILE_SIZE`, `GROUND_GRID_SIZE`,
`CITY_ZONE_SIZE`, `get_tile_id/position/coords()`, `is_tile_inside_grid()`,
`current_tile`, `tile_changed`, and `update_player_position()` — which had
nothing left to do. `StreamingSystems` lost `CellType` entirely (one kind of
cell now), `TILE_LOAD_RING`/`TILE_UNLOAD_RING`, `_tile_ring()`, the `coords`
field, and the two-branch distance metric; `cell_state_changed` dropped its
`cell_type` argument. `WorldData.ground_tiles` and `GroundTileData` are
deleted, as is the 3x3 export loop in `map_source.gd` and the tile line in the
debug panel.

`WORLD_ZONE_SIZE` 9600 -> **3500**: the world boundary is now exactly the
terrain plane's extent, because past it there is no terrain and no collision,
only the ocean plane.

**Data.** The nine tile entries are gone. The 40 towers were **replanted**: the
whole layout is scaled 0.33 toward the origin, which maps the old 6600 m city
onto the island's ~2400 m of dry land and keeps the relative arrangement
recognisable. 33 survive; 7 landed on Maruyama's cone (the brief leaves it
unbuilt) and 1 was still at sea, and those are dropped. Y comes from the island
scene's own baked `HeightMapShape3D`, so collision and visual agree by
construction. Dead `strata_ids` dictionaries were cleared out of every block
while they were open. Provisional — step 5 replaces all of it.

**A spawn bug this uncovered, from my own earlier commit.** `world.gd` line 112
overwrites `WorldSystems.spawn_point` with `world_data.spawn_point` whenever
the latter is non-zero. It was `(250.8, 0, -277)`, so the spawn I placed on the
terrain two commits ago never took effect at runtime — the player would have
appeared at Y 0, inside the volcano. Both now read the same point on the caldera
floor, and the autoload's comment says which one actually wins. `featured_3tower`
had no `position` line at all (so, `Vector3.ZERO` — inside Maruyama's summit)
and was given one on the inner slope.

The nine tile scenes under `world/content/ground_tiles/` and
`world/silhouettes/ground_tiles/` are **left on disk**, orphaned: nothing loads
them, but editor scenes may still reference them and a blind `git rm` across
scenes is not something to do twice in one session.
`tools/block_generator/block_placer.gd` keeps its own copies of the grid
constants and now says in its header that running it is pointless — it would
place blocks in the sea at Y 0; step 5's generator replaces it.

*Сетка 3×3 снята. Девять плит были ходимым дном 6600 × 6600 под всем морем —
остров стоял на бетонной плите размером с прежний город. Ушли оба типа ячейки,
кольцевая метрика и вся тайловая математика; граница мира 9600 -> 3500 = край
карты. 40 башен пересажены на остров сжатием раскладки в 0.33, 33 выжили.
Попутно вскрылось: `world.gd` перезаписывал спавн значением из
`world_data.tres` с Y 0, то есть правка спавна из позавчерашнего коммита в игре
не работала.*
- `core/world/world_systems.gd`, `core/world/streaming_systems.gd`, `world/resources/world_data.gd`, `world/resources/ground_tile_data.gd` (deleted), `core/map_source/map_source.gd`, `ui/debug/stream_debug_panel.gd`, `core/world/world_border_guard.gd`, `tools/block_generator/block_placer.gd`, `world/world.gd`, `data/world_data.tres`

---

## 2026-08-25 - Documents catch up, and CLAUDE.md is cut into pieces (island step 6)

Out of the brief's order — step 6 comes after 3-5 — because 3-5 need an open
editor and this does not, and the brief asks for step 6 not to be postponed.

**`CLAUDE.md` split, 94 KB -> 15 KB.** It had single paragraphs over 4000
characters. A document that dense is not edited: agents append to the end
rather than correct the middle, which is exactly where the drift this file
keeps suffering comes from. The per-system contracts now live in
`docs/architecture/`: `autoloads_and_bootstrap`, `world_streaming`,
`player_and_camera`, `npc_and_incidents`, `items_and_equipment`,
`persistence`. `CLAUDE.md` keeps the rules, the constraints and an index.

The text was **moved, not rewritten** — a split that also revises is not
reviewable in one pass. Byte count across all seven files is 99 KB against
94 KB before, the difference being the six file headers and the index table.

**Vertical-city claims removed** from `ARCHITECTURE.md` (the strata layer name
contract is now marked removed rather than deleted, because those `Layer*`
nodes are still baked into generated block scenes and a reader needs to know
what they were), `docs/CONTRIBUTING.md` (the strata naming rule is simply
false now), `docs/core_loop.md` §10 (the surveillance gradient survives — it
is design, not implementation — but is now expressed as caldera floor / shelf /
outer rim, continuous through the terrain), `docs/visual_language.md`,
`docs/planned_scope.md`. The streaming radii in `ARCHITECTURE.md` were 1000/1200
and are now 400/500 with the reason attached.

Mentions left alone on purpose: `NPC_REACTIONS.md`, `attribution.md` and
`npc_archetypes.md` use Doggerland / Manifold / Glare as **place names**, which
is exactly what the brief preserves them for.

**`docs/COLLISION_LAYERS.md`** gained the island's `TerrainStaticBody`
(`collision_layer = 3`) on layers 1 and 2. The project rule is that a bare
integer in a scene is only allowed alongside a row in that file, and the row
was missing — the ground the whole game now stands on was undocumented.

**The brief itself amended** with the four decisions taken during these steps
(square map, procedural terrain and no `CREDITS.md` entry, island at the
origin, step 6 out of order), plus the one open question found by reading the
file: `aogashima_heightmap_16bit.png` is **8-bit RGB**, not 16-bit. Data sits
in R alone; the generator asks for `FORMAT_RH` but `save_png()` did not keep
it. Height quantizes at ~1.96 m per step instead of 0.008, so the caldera
floor will terrace visibly. The shader reads `.r` and works, which is what
makes it quiet.

*Разрезал `CLAUDE.md`: 94 КБ -> 15 КБ, контракты уехали в `docs/architecture/`
шестью файлами. Текст перенесён дословно, не переписан. Вычищено описание
вертикального города из остальных документов — кроме дизайнерских, где
Доггерленд/Манифолд/Глэйр остаются именами мест, как ТЗ и разрешает. В
`COLLISION_LAYERS.md` добавлена земля острова. В ТЗ внесены решения этой
сессии и записан найденный дефект: heightmap 8-битный, а не 16-битный.*
- `CLAUDE.md`, `docs/architecture/*.md` (new), `ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/core_loop.md`, `docs/visual_language.md`, `docs/planned_scope.md`, `docs/COLLISION_LAYERS.md`, `docs/island_rescope_brief.md`

---

## 2026-08-25 - Island moved to the origin, and everything standing on it moved with it

Stan's call: the island sits at the world origin. It was instanced in
`world.tscn` at `Z + 2200` — one old `GROUND_TILE_SIZE`, a leftover of the
3x3 grid.

**The offset was load-bearing and nobody noticed.** Every test object was
placed while the island was 2200 m away, i.e. over open ocean where the
terrain is 0 — so `Y 0..10` worked. Move the island under them and the whole
scene is inside the volcano: the crowd, the lodging room, the hover and the
four drones. The spawn point (`0, 2, 200`) lands 197 m below the surface of
Maruyama's cone.

So the move is three changes, not one:

- `world.tscn` — the island's transform is gone; it sits at the origin.
- All 24 `StreamContainer` objects lifted onto the terrain. **XZ is untouched**
  — the playtest layout Stan knows is preserved exactly — and each object keeps
  the clearance it already had, with the terrain height under it added.
  Heights were read out of the scene's own baked `HeightMapShape3D`, sampled at
  each object's XZ, so collision and visual agree by construction (they were
  cross-checked against the heightmap PNG and match within half a metre).
- `WorldSystems.spawn_point` -> `(220, 133, -140)`, three metres above ground
  next to the lodging room, so a run starts at the thing being tested instead
  of 500 m from it.

`map_source.gd` also stopped clamping spawn Y. `_commit_spawn_point()` wrote
`Y_CITY_ZONE_TOP` (0.0) instead of the marker's own height, and the marker
raycast clamped into `[0, 5]`. On a flat city that was invisible; on terrain it
guarantees a spawn underground. This is the clamp `CLAUDE.md` already blamed
for the spawn being ground-tile-only.

**Known and deliberately left:** the test cluster is on Maruyama's western
flank at 122-160 m, and the brief wants Maruyama unbuilt. Re-placing it is
editor work, by eye, and belongs with the building pass at step 5. The spawn
above is a debug spawn, not a design decision.

*Остров переехал в начало координат — и утащил за собой всё, что на нём
стояло. Смещение Z+2200 держало сцену: объекты ставились над океаном, где
рельеф 0, поэтому Y 0..10 работал. 24 объекта подняты по фактическому рельефу
(XZ не тронут, высоты взяты из запечённой коллизии сцены), спавн — рядом с
ночлежкой. Снят зажим Y при расстановке спавна: на плоском городе он был
незаметен, на рельефе всегда даёт точку под землёй. Кластер пока стоит на
склоне Маруямы — переставлять по месту в редакторе.*
- `world/world.tscn`, `core/world/world_systems.gd`, `core/map_source/map_source.gd`

---

## 2026-08-25 - Streaming radii 400/500, and what streaming is now for (island step 2)

`BLOCK_STREAM_RADIUS` 1000 -> **400**, `BLOCK_UNLOAD_RADIUS` 1200 -> **500**
(the same 25 % hysteresis gap). Both are eyeball numbers: if a silhouette
swaps to content in the player's face, the radius is too small.

The brief asks for one thing to be written down alongside them, and it matters
more than the numbers: **the pipeline's purpose changed.** It used to make a
9.6 km world manageable, which is exactly where 1000/1200 came from. A 3.5 km
island fits in memory whole, so streaming now governs the swap of silhouette
for live content, not world size — and 400/500 are derived from how many
towers should be live around the player (~25 at the caldera's ~100 m spacing),
not from how much world fits. Recorded in `streaming_systems.gd`'s own header
and in `CLAUDE.md`; without it the reason the pipeline is this complicated is
lost in a month.

Also: `aogashima_generator.gd`'s `OUTPUT_PATH` wrote to the repo root while the
file it produces lives in `world/aogashima/`. One line.

*Радиусы стриминга 400/500 вместо 1000/1200, и — что важнее — записано, зачем
конвейер теперь нужен: не «сделать огромный мир управляемым», а управлять
подменой пустышки на живой контент. Остров в 3,5 км помещается целиком.*
- `core/world/streaming_systems.gd`, `tools/island_generator/aogashima_generator.gd`, `CLAUDE.md`

---

## 2026-08-25 - Strata removed from the editor tools (island step 1, part 2)

The runtime lost strata in the previous commit; these are the tools that fed
it. Stan's call was to keep the interior builders and cut strata out of them
rather than delete them.

**Tiers, not strata.** All three builders needed the same three things from
`StrataGeometry`: where floors are allowed, how wide the dead band is, and
which deck profile to use. Without strata that collapses to *one tower, one
playable height*, split into tiers:

- `tower_builder.gd` — the three authored mesh pairs (350/300/250) were bound
  to Doggerland/Manifold/Glare and shipped as three scenes behind
  `InstancePlaceholder`. They are now three **tiers of one tower**, built
  straight into a single content scene. The authored taper is kept — it is
  good art and had nothing to do with strata. `TOWER_TOP` 3000 -> 1000, the
  island ceiling.
- `test_block_builder.gd` — same conversion, per tower: each tower's own
  playable height is split into `TIER_PROFILES.size()` tiers.
- `block_library_generator.gd` — had its own duplicated `STRATA_*_TOP`
  constants. A block is now one solid volume; the silhouette is one mesh
  instead of one `Mesh<StrataName>` segment per stratum. Height range
  3200-ish -> `HEIGHT_RANGE` 30..500 m, which is what the island actually
  holds.

`TECH_BAND` is 6 m, not the old 100 m. That number came from a stratum 1000 m
tall; island towers start at 30 m, where two 100 m dead bands would leave
nothing. Six metres is about one floor and is meant to be caught by eye.

`StrataDeckProfile` -> **`DeckProfile`** (`world/resources/deck_profile.gd`,
`data/deck_profiles/`). The A/B/C pattern names keep their meaning — warren,
utilitarian, atrium — but a profile is now named next to the tier it belongs
to instead of being derived from a stratum. Uids are unchanged, so the three
`.tres` keep their identity.

`map_source.gd`/`map_cursor.gd` lost `strata_ids`, the height->strata mapping,
the DG/MF/GL suffixes and the strata line in the cursor overlay; the three
`STRATA_*` `Area3D` nodes and their box shapes are gone from
`map_source.tscn`.

**Expected on the next run, and not a bug:** the 40 existing greybox blocks
still carry `Layer*` placeholders and `Mesh<StrataName>` segments in their
`.tscn` files. Nothing materializes those any more, so a block renders as its
thin `Shared` spine until the library is regenerated. Same for the 84 baked
`gbx_strata_top` metadata entries. All of it is generated data, regenerated at
step 5; the generators above already emit the new shape.

*Страты вырезаны из редакторных тулз. Три меша башни стали тремя ЯРУСАМИ
одной башни — авторская ступенчатость сохранена, она к стратам отношения не
имела. `TECH_BAND` 6 м вместо 100: сотня была рассчитана на страту в 1000 м, а
на острове башни от 30 м. `StrataDeckProfile` -> `DeckProfile`. Важно: старые
40 greybox-блоков до перегенерации будут выглядеть тонкими стержнями —
объём жил в слоях, которые больше никто не материализует.*
- `tools/block_generator/tower_builder.gd`, `test_block_builder.gd`, `block_library_generator.gd`, `core/map_source/map_source.gd`, `map_cursor.gd`, `map_source.tscn`, `world/resources/deck_profile.gd` (renamed), `data/deck_profiles/*.tres` (moved)

---

## 2026-08-25 - Strata removed from the runtime (island step 1)

`docs/island_rescope_brief.md` step 1. First because it is a deletion: the
longer strata live, the more gets built on top of them.

`WorldSystems` lost `STRATA_DOGGERLAND/MANIFOLD/GLARE`, `STRATA_HYSTERESIS`,
`current_strata`, `set_current_strata()`, `strata_changed`,
`get_strata_by_height()` and the hysteresis walk; `update_player_position()`
now only tracks the tile. `GAMEPLAY_HEIGHT` 3200 -> 1000, the island ceiling.

`StreamingSystems` lost the entire layer-materialization pipeline —
`STRATA_PRELOAD_MARGIN`, the four `StreamCell` layer fields, the
`layer_changed` signal, `_on_strata_changed`, `_prewarm_upcoming_layers`,
`_prewarm_layer`, `_request_layer`, `_pump_layers`, `_set_silhouette_segment`,
`_find_layer_placeholder`, and the `"Layer" + strata` naming contract (663 ->
497 lines). **Untouched:** the cell state machine, `_packed_cache`,
`MAX_CONCURRENT_LOADS`, `INSTANTIATION_BUDGET_PER_FRAME`, the silhouette and
content rings.

One deliberate behaviour change: a block's silhouette is now hidden wholesale
when its content goes ACTIVE, exactly as a ground tile's already was. Before,
a block hid its silhouette one `Mesh<StrataName>` segment at a time, per
materialized layer; with no layers there is nothing to hide per segment, and
leaving it alone would draw silhouette and content at once.

Also stripped: `BlockData.strata_ids`, the strata column and `layer_changed`
subscription in `stream_debug_panel.gd`, strata comments in
`environment_lighting_system.gd` and `isometric_camera_state.gd`. Deleted
`core/world/strata_geometry.gd` — its only consumers are the two editor
interior builders, handled in the next commit.

**Recorded in advance, per the brief's stop line:** removing
`BlockData.strata_ids` makes the existing `data/world_data.tres` not fully
readable — Godot will report an unknown property on every block. The data is
regenerated at step 5 anyway; the file was never wrong, the field is gone.

*Страты удалены из рантайма: ушёл весь конвейер материализации слоёв в
`StreamingSystems` и вся математика страт в `WorldSystems`, потолок 3200 ->
1000. Силуэт квартала теперь гасится целиком, как у плиты, — посегментно
гасить нечего. Заранее зафиксировано: старый `world_data.tres` будет ругаться
на `strata_ids`, это ожидаемо до перегенерации на шаге 5.*
- `core/world/world_systems.gd`, `core/world/streaming_systems.gd`, `core/world/strata_geometry.gd` (deleted), `world/resources/block_data.gd`, `ui/debug/stream_debug_panel.gd`, `camera/isometric_camera_state.gd`, `core/world/world_environment_systems/environment_lighting_system.gd`, `CLAUDE.md`

---

## 2026-08-25 - Doc sync after island rescope + H5 close

- `planned_scope.md`: removed false claim that EquipmentComponent does not exist; H5 moved out of planned scope
- `scope_horizon.md`: H5 closed; Island transition set as current Now
- `island_rescope_brief.md`: strict version (no author-addressing)
- `npc_archetypes.md`: corrected “None of this is implemented” header
- `CLAUDE.md`: Documents table + player components list brought in line with reality

*Синхронизация документов после закрытия H5 и утверждения перехода на остров.*

## 2026-08-23 - Equipment becomes visible (H5 S6 + S7)

Five steps of H5 were merged and none of them could be seen: the character
wore a jumpsuit, carried a pipe in a thigh pocket and drew it on `B`, all of it
true in the save file and invisible on screen. `EquipmentVisualsComponent`
connects the state to the rig, and reflects it rather than owning it —
deleting the component must change nothing except what is drawn.

**Clothing** is a skinned mesh already in the rig, named by
`GarmentData.mesh_node_name` and toggled visible. A name rather than a
`NodePath`: a path is scene-specific and would not survive an NPC reading it,
while the name is a convention both rigs already satisfy. One name, not a
list — nothing today needs two.

**A held item** is a `MeshInstance3D` built under a `BoneAttachment3D` on the
hand, from a new `ItemResource.held_mesh`. A `Mesh` rather than a scene, so
holding something costs one field instead of a `.tscn` per item; null means the
drawn state is still correct and nothing shows.

The trap worth recording: **the skeleton is `OriginalSkeleton`, not
`GeneralSkeleton`.** The former is the retarget target every visible mesh is
actually skinned to; it has 65 bones and indexes them differently — `Head` is 5
there and 6 in `GeneralSkeleton`, `RightHand` is **34** and 32. Both the index
and which skeleton it belongs to were read out of the scene and cross-checked
against the existing Votive attachment rather than assumed.

`held_offset`/`held_rotation_deg` are exported and deliberately left at zero:
they are meant to be dragged in the inspector until the thing sits in the fist,
the same reasoning `VotiveProjector.bone_local_offset` already carries. Nobody
computed a default and nobody could.

`scrap_pipe` got a `CylinderMesh` placeholder; it leaves with the fixture when
H6 lands. NPCs are untouched — their rig would work unchanged, but nothing
drives it there.

*Экипировка стала видимой: одежда — скиннингованный меш по имени, вещь в
руке — меш под BoneAttachment3D на кисти. Скелет именно OriginalSkeleton, у
него своя индексация костей (RightHand = 34, а не 32) — сверено по сцене.
Смещение в руке вынесено в экспорты, подгонять глазами.*
- `player/player_components/equipment_visuals_component/equipment_visuals_component.gd`, `core/items/garment_data.gd`, `core/items/item_resource.gd`, `player/player.tscn`, `data/items/starter_*.tres`, `data/items/scrap_pipe.tres`, `CLAUDE.md`

**Follow-up the same day — equipment is now authoritative over the visibility
the scene authored.** Stan asked whether the jumpsuit would still be visible at
startup and how we would tell the component apart from the scene doing nothing.
The first half was fine (`_ready()` order is safe both ways — the visuals
component calls `refresh_all()` and catches up if equipment went first), but the
question exposed a real hole: `_apply_body_slot()` only hid a mesh through
`_slot_meshes`, which starts empty, and an empty slot returned early before
hiding anything. So the component could never hide a mesh `player.tscn` had
authored `visible = true` — at frame 0 the source of truth was the scene, not
the equipment, and they agreed by coincidence. `refresh_all()` now sweeps every
mesh named by any garment in `ItemCatalog` before showing the worn ones. Only
meshes an item names are touched: the body, the headset and the unassigned
details mesh are named by nothing and are never hidden. This is also what makes
S6 observable — emptying `starter_garment_ids` in the inspector now actually
undresses the character, and dropping just `starter_boots` is a clean
discriminator since boots and jumpsuit are separate meshes even though the body
is one.

*Экипировка теперь главнее видимости, записанной в сцене: `refresh_all()`
сначала гасит все меши одежды из каталога и только потом показывает надетые.
Раньше компонент физически не мог погасить меш, у которого в `player.tscn`
стоял `visible = true`, — и именно поэтому S6 нечем было проверить.*
- `player/player_components/equipment_visuals_component/equipment_visuals_component.gd`, `CLAUDE.md`

---

## 2026-08-23 - Draw / holster, and stance as one state with it (H5 S5)

The third of H5's three states — what is held — and the one rule that reaches
outside equipment: **drawing a weapon and being in COMBAT are the same fact,
symmetric both ways.** You cannot hold a drawn weapon and claim to be
peaceful, and you cannot be at ease with one in your hand.

A drawn item is removed from its slot and remembers where it came from, so
holstering puts it back exactly there — that slot is guaranteed free, whereas
`stow_anywhere()` would drop it in a different pocket every time. Both halves
are saved; without `drawn_from`, holstering after a load would have nowhere to
put the thing back.

**No new item field was needed.** `can_use_in_hands` (already on
`ItemResource`) gates whether something can be drawn; `readability ==
THREATENING` (S2) gates whether drawing it means anything. They compose: a
torch is drawable and says nothing, a weapon is drawable and says everything —
so no "is a weapon" flag had to be guessed at ahead of the deferred item model.

The coupling lives in `player.gd`: equipment knows nothing about stances,
`InputSystems` knows nothing about equipment, and `PlayerState` is the only
thing allowed to change a stance. `set_stance()` gains its second-ever caller.
No loop and no guard flag — `set_stance()` returns early on an unchanged value
and `holster()` returns early with empty hands. **COMBAT deliberately does not
auto-draw:** raised fists are already a statement, and that asymmetry is the
point.

New `draw_holster` action on `B`, with `input_map.md` updated in the same
commit per the standing rule. Its own action rather than a side effect of
`toggle_stance`, precisely so COMBAT does not auto-draw. `B` is provisional —
`X` would be conventional but is taken by the never-implemented `status`.

`data/items/scrap_pipe.tres` is a fixture so this is testable before H6's
pistol exists. POCKET-sized and THREATENING on purpose: it hides in a thigh
pocket (pockets do not check readability — that IS the concealment mechanic)
and reads as a threat once drawn, and it is refused by `back_unique`, which
exercises `refuses_threatening` on a real item for the first time.
`starter_stowed_ids` puts it on the player at start; both it and the item
leave when H6 lands.

`CLAUDE.md`'s "stance is a declared intent, **not equipment**" line is refined
here and not earlier — only now does it describe code that exists.

*Достать/убрать и стойка — одно состояние, симметрично в обе стороны. Новых
полей у предмета не понадобилось: can_use_in_hands решает, можно ли взять,
readability — значит ли это что-нибудь. COMBAT сам не достаёт: кулаки уже
заявление. Обрезок трубы — фикстура, чтобы это было чем проверять до пистолета.*
- `player/player_components/equipment_component/equipment_component.gd`, `player/player.gd`, `core/input/input_systems.gd`, `project.godot`, `input_map.md`, `data/items/scrap_pipe.tres`, `data/items/catalog.tres`, `CLAUDE.md`

---

## 2026-08-23 - InteractComponent stops deciding where items go (H5 S4)

`InteractComponent` held an `@onready` reference to `InventoryComponent` and
decided an item's fate itself — `try_add()` then `queue_free()`. Its job ends
at "the player wants this thing"; where the thing ends up is not its business.

The policy moved to `player.gd`'s new `store_item()`: **equipment first,
inventory second**. It lives there rather than in either component because
`EquipmentComponent` deliberately knows nothing about inventory, and the
player is what owns both — so the order between them is its decision to make.
`InteractComponent` now calls it duck-typed through `has_method()`, the same
idiom `on_world_ready()` and the save contract already use, and frees the
world object only on success. A refusal leaves the item in the world
untouched.

`EquipmentComponent` gained `stow_anywhere()`: the garment's own body slot if
it is a garment, else the first empty pocket that takes it. Candidates are
tested with `can_stow()` and only the winner is actually stowed, so a full
jacket does not produce four refusal lines on the way to the fifth pocket.

**Visible behaviour change:** `test_can` is POCKET-sized by default and the
starter jumpsuit carries four pockets, so cans now fill pockets first and only
reach the inventory from the fifth onward. A pocket is a socket and holds
exactly one item whatever `max_stack` says — stacking stays inventory's
business.

Carrying in the hands (`CARRY_ONLY`, the PickupSlot path) is untouched. Hands
are not in the layout, and "what is held" is a later step.

*Interact перестал решать судьбу предмета: политика «сначала на тело, потом в
инвентарь» переехала в player.gd, который владеет обоими компонентами.
Заметное следствие — банки теперь сначала занимают карманы комбинезона.*
- `player/player_components/interact_component/interact_component.gd`, `player/player.gd`, `player/player_components/equipment_component/equipment_component.gd`, `CLAUDE.md`

---

## 2026-08-23 - EquipmentComponent: the rules, without the wiring (H5 S3)

Fourth step of H5, and the first that does something. Logic and persistence
only — no meshes, no bones, no stance; those are later steps and keeping them
out is what makes this one reviewable.

Two levels, matching S2's data. Body slots come from the `EquipmentLayout`
assigned in the inspector. Pockets are derived **live** from whatever garments
are worn — `_find_pocket()` re-derives every time rather than caching a table,
because what is worn changes and a stale pocket table is the kind of bug that
hides.

Two refusals carry the design, and both are refusals rather than conveniences:

**`equip()` into an occupied slot refuses and never swaps.** An implicit swap
has to put the old garment somewhere, and a component that knows nothing about
inventory could only drop it — silently destroying the player's clothes to
save the caller one line. The caller unequips first and deals with what comes
back. That is what "you cannot replace a thing until the old one has somewhere
to go" means in code.

**`unequip()` refuses while the garment's own pockets still hold something.**
Those pockets leave with the garment, so their contents would have nowhere to
be. Same rule as the body slot, one level down.

`Refusal` is an enum rather than a bool so a caller can tell the player
something true — TOO_LARGE and READS_AS_THREAT are different sentences.

Holds ids, never `ItemResource` references, which is what makes it saveable at
all. `load_save_data()` restores body slots **before** pockets — that order is
load-bearing, a pocket exists only while its garment is worn — and re-validates
every entry against the current layout and catalog rather than trusting the
file: a garment removed from the game must not resurrect as an entry nothing
can address.

The character starts dressed: `starter_garment_ids` puts the jumpsuit and boots
on in `_ready()`, and a restored save overwrites that wholesale, which is the
correct precedence.

*Компонент экипировки: два уровня, карманы выводятся из надетого вживую.
Занятый слот отказывает вместо подмены, а вещь не снимается, пока её карманы
не пусты — оба отказа и есть правило «нельзя заменить, пока старому не нашлось
места». Хранит id, поэтому сохраняем; при загрузке тело восстанавливается
раньше карманов.*
- `player/player_components/equipment_component/equipment_component.gd`, `player/player.tscn`, `CLAUDE.md`

---

## 2026-08-23 - Equipment slot data, no component yet (H5 S2)

Third step of H5. Data only — nothing reads any of it, and that is the point:
the shape has to be settled before a component is written against it.

`ItemTraits` holds the two enums an item and a slot both speak: `SizeClass`
(POCKET/CARRIED/BULKY) and `Readability`
(CONCEALABLE/ORDINARY/THREATENING). Its own script rather than fields on
`ItemResource`, for a concrete reason — `EquipmentSlotDefinition` names a size
class, `ItemResource` reaches `GarmentData`, `GarmentData` reaches slot
definitions; putting the enums on `ItemResource` closes that into a cycle
GDScript resolves badly.

`EquipmentSlotDefinition` describes one socket and serves as both a body slot
and a pocket, because they are the same thing: a place that holds exactly one
item with a limit on what may go there. `refuses_threatening` is true on
`back_unique` and nowhere else — a rifle across the back is a statement the
player should make deliberately, not a storage decision.

`EquipmentLayout` (`data/equipment/player_layout.tres`) closes the open
question of who registers slots: a Resource on the character, not constants in
a component. It describes the **body** only. Pockets are not in it — slot
count belongs to the garment, so `GarmentData` names its body slot by id and
carries its own pockets. That split is what makes clothing replaceable, and it
is why concealed carry is granted by the garment rather than by the character.

Two starter garments authored so the data is real rather than empty classes.
The jumpsuit occupies `torso` and carries all four pockets — it is one garment
covering torso and legs, which is also the honest reflection of the rig, where
no separate trouser and jacket meshes exist.

*Данные слотов H5: словарь размеров и читаемости отдельным скриптом (иначе
цикл в разрешении классов), одно определение сокета и для тела, и для
кармана, раскладка тела ресурсом на персонаже, а карманы — на самой одежде.
Компонента ещё нет.*
- `core/items/item_traits.gd`, `core/items/garment_data.gd`, `core/items/item_resource.gd`, `core/equipment/equipment_slot_definition.gd`, `core/equipment/equipment_layout.gd`, `data/equipment/player_layout.tres`, `data/items/starter_*.tres`, `data/items/catalog.tres`, `CLAUDE.md`

---

## 2026-08-23 - A missed swing is seen; a punch commits to who it was thrown at

Two combat/reaction gaps, closed surgically.

**Missed swings are now observable.** `_resolve_punch_hit()` emits a new
`punch_missed(position)` signal when the cone check finds nobody. It goes
nowhere near `IncidentRegistry` — a swing that hit nothing is a visible act,
not a fact the city holds, so nothing is recorded and nothing is attributed.
`IdleNPCController` subscribes lazily by group (`_try_connect_player_swing()`,
the same scheme it already uses for the registry) and handles it in one entry
point, `_on_player_punch_missed()`: gated on the ordinary
`PerceptionComponent.observe_player()` so an NPC facing away or behind a wall
reacts to nothing, refused outright while knocked down or mid-reaction, and
resolving to exactly one of two outcomes — a roll of
`archetype.flee_probability * swing_flee_probability_scale` (new export,
`0.5`) into the existing two-phase Flee, or one `npc_swing_noticed` word
("?", "HUH", "…"). Never both: `_start_flee()` already spawns `npc_flee`, and
two words over one head in one frame is the mistake `npc_transmit`'s
placement exists to avoid. Witness memory is deliberately not set — nobody
was assaulted. New def `data/comic_effects/npc_swing_noticed.tres`, registered
in the catalog.

**A punch now commits to its intended target.** `punch_hit_delay` (0.15s) is
long enough for a walking NPC to step out of a cone the player was correctly
aiming at when they clicked. `_start_punch()` resolves an intent target once,
up front (`_acquire_punch_intent()`, a wider-cone/longer-reach reuse of the
now-parameterised `_find_punch_target(reach, angle_deg)`), stored as an
instance id rather than a `Node` reference so a target streaming out
mid-swing is a checked lookup, not a dangling one. `_face_punch_intent()`
turns the body toward it for the length of the wind-up only, at
`punch_intent_turn_smoothing`. The hit check itself is untouched — this makes
a fair punch more likely to land, it does not guarantee one, and a target
that fully leaves the cone or reach still makes it a miss. Intent clears when
the punch ends.

Out of scope and untouched, as specified: `TpsCombatCameraState`'s
pivot/reticle drift, wiring punch to `locked_target`, `punch_max_speed`,
attribution/`WitnessReport`. Files: `player/player.gd`,
`npc/controllers/idle_npc_controller.gd`, `data/comic_effects/` (new def +
catalog), `CLAUDE.md`. Not run in the editor — no Godot binary in this
session; verify with `project_run`/`logs_read`.

> Промах теперь заметен: удар в воздух рассылает `punch_missed`, и любой NPC,
> который в этот момент реально видит игрока, отвечает одним словом "?" или
> (с пониженной вероятностью по архетипу) убегает — без инцидента, без отчёта
> свидетеля и без памяти о игроке. Удар же запоминает, в кого его бросили:
> цель определяется один раз в момент нажатия, и корпус доворачивается к ней
> во время замаха, так что шагнувший в сторону NPC всё ещё получает удар в
> свою сторону. Проверка попадания не изменена.

---

## 2026-08-23 - PlayerPersistenceSystem: the player's components reach a save (H5 S1)

`SaveSystem` walks `WorldContext.systems` and nothing else. That is correct —
it is a list of world systems, not a search of the scene tree — but it meant a
component hanging off the player had no route into a save at all, and
equipment was going to hit that wall the moment it needed to persist. Proven
now, on the component that already exists, rather than discovered later on the
one that doesn't.

`PlayerPersistenceSystem` (`core/world/player_persistence/`) is that route and
deliberately the only one: `SaveSystem`'s contract does not widen, a second
system implements it on the player's behalf. Keeping "the player has
components" out of `SaveSystem` is what lets it stay a thing that moves
dictionaries. Payload nests one level, each component stating its own key
under the same no-class-names rule as the top level.

`SaveSystem._implements_save_contract()` became the public static
`implements_save_contract()`. Two files now ask that question, and stating the
contract twice is how two definitions of it start to drift.

`InventoryComponent` is the first consumer and the proof: it writes
`{id, count}` pairs instead of the `ItemResource` the payload rule forbids, and
resolves them back through `ItemCatalog` — which is precisely why S0 came
first. Four decisions recorded in its own comments rather than left to be
rediscovered: a load replaces contents outright; `item_added` is deliberately
NOT emitted per restored stack, because nothing was added (the same
distinction `incidents_restored` draws); an unresolvable id is dropped rather
than stored as a null every reader would have to guard; and
`max_carry_weight` is not re-checked on load, since refusing to restore what
was carried because capacity has since been lowered would silently destroy the
player's belongings.

*Компоненты игрока получили маршрут в сейв: SaveSystem обходит только список
мировых систем и в дерево сцены не заглядывает. Отдельная система-мост, а не
расширение контракта. Проверено на инвентаре — он теперь пишет пары
{id, count} и разрешает их через ItemCatalog из S0.*
- `core/world/player_persistence/player_persistence_system.gd`, `core/world/save_system/save_system.gd`, `player/player_components/inventory_component/inventory_component.gd`, `world/world.gd`, `CLAUDE.md`

---

## 2026-08-23 - Correct the slot model: garments carry the pockets

Two things this page said earlier today were wrong, and both were mine.

**Slot count belongs to the garment, not the character.** The six-slot table
implied a fixed layout on the player. It is two levels: the character has body
slots (legs, torso, feet, back-pack, back-unique) that take garments, and each
garment contributes its own item slots. "Two trouser pockets, two jacket
pockets" describes those particular garments — a different jacket brings a
different number, and a jacket with no pockets is a legitimate jacket. This
generalises the rule already agreed for the backpack from one special case to
how all clothing works, which is what makes clothing replaceable at all. It
also sharpens the pistol rule: the jacket is what grants concealed carry, so
taking it off takes the capability with it.

Consequence recorded for the layout resource: it describes **body slots**;
pocket counts live on the garment items. The earlier framing would have baked
the pockets into the player.

**There is no "naked baseline".** The character starts dressed and stays that
way — boots are boots, and the jumpsuit stands in for trousers and jacket until
separate garments exist. Starter clothing is equipped items by default, not an
absence. The observation about the five meshes on `OriginalSkeleton` stands;
the conclusion drawn from it did not.

Work proceeds against the meshes that exist, treating the character as
genuinely wearing these things rather than approximating them. Separate garment
meshes and a backpack mesh are an art task, and the logic does not wait on them.

*Исправлена модель слотов: карманы приносит одежда, а не персонаж — два
уровня, тело держит вещи, вещи держат карманы. И никакого «naked baseline»:
болванчик одет, комбинезон подменяет штаны с курткой, пока нет отдельных
мешей.*
- `docs/planned_scope.md`

---

## 2026-08-23 - ItemCatalog: an item id can finally be resolved (H5 S0)

First code of the H5 sequence, and deliberately not the component. H5's whole
design rests on a slot holding `item_id: StringName` resolved through a
registry — and there was no registry. An `ItemResource` reached the game
exactly one way: hand-assigned in the inspector to `InteractableObject`'s
`@export`. Nothing could turn an id back into a resource, so anything that has
to STORE an item rather than hold one had nowhere to go, and storing the
reference instead is barred by `SaveSystem`'s payload rule.

`ItemCatalog` (`core/items/`, `data/items/catalog.tres`) is a plain `Resource`
with a static accessor. Not a `WORLD_SYSTEM_SCRIPTS` entry — those are nodes
because they hold runtime state and have a lifecycle, and a catalog is
immutable data. Not an `@export` per consumer either: scene nodes could take
one, but `.new()`-built consumers and future NPCs cannot, and per-consumer
wiring is what rots. Found by path, not by scanning the folder — the same
export-safety trap `ComicEffectSystem` already documents. `find()` is a silent
query; `get_item()` warns on an unresolvable id.

`ItemResource.id` becomes `StringName`, matching `ActorBase.actor_id`
(`BlockBase.id` is still `String` — a pre-existing inconsistency, left
alone), and `InventoryComponent`'s `take()`/`get_count()` follow. No
external call sites existed, so the signature change is contained.

Recorded in the inventory's own header rather than quietly left: `_stacks`
still holds the `ItemResource` itself, so that component is not saveable as it
stands. Resolvable ids make the fix possible; they are not the fix.

*Первый код H5 и намеренно не компонент: правило «слот хранит item_id»
упиралось в то, что разрешать id было нечем. Добавлен ItemCatalog —
Resource со статическим доступом, без ноды и без @export у каждого
потребителя. id предмета стал StringName.*
- `core/items/item_catalog.gd`, `core/items/item_resource.gd`, `data/items/catalog.tres`, `data/items/test_can.tres`, `player/player_components/inventory_component/inventory_component.gd`, `CLAUDE.md`

---

## 2026-08-23 - Equipment: the slot layout, the pistol rule, the first item property

Documentation only again — H3/H4 still open, H5 still closed. Extends the
section added earlier today with the parts that were still hand-waving.

**Six slots, each a single socket:** two trouser pockets, two jacket pockets,
a back slot for a pack, a back slot for one unique item. Fit is answered by a
size class against the socket, **not a grid** — no packing, no rotation, no
cell UI. The interesting question in this game is what is visible on a person,
not how neatly a bag tessellates.

**A pistol is concealed in the jacket, and a belt holster must never be
added** — it is a visible statement to the world, and it would hand the player
concealment for free where the design wants it to cost a jacket slot. Recorded
as a hard "do not add", alongside `PlayerState`'s removed `TOPDOWN`.

**Drawing a weapon and stance are one state, symmetric both ways:** drawing
sets `COMBAT`, holstering returns to `PEACE`, and toggling to `PEACE` by hand
holsters. Three consequences recorded — `set_stance()` gains a second caller
(only `InputSystems` calls it today); no loop and no guard flag is needed,
because `set_stance()` already returns early on an unchanged value; and
`CLAUDE.md`'s "declared intent, not equipment" line will need refining, in the
same commit as the code and not before it.

**The item gains exactly two enums** — a size class, and how it reads to an
observer (conceals / ordinary / reads as a threat). The unique back slot
refuses the last, which is what makes "a machine gun on the back gives away
your intent" expressible at all: the rule is about what the city sees, so it
can only live on the item. Chosen over a per-slot whitelist because the same
property is what NPC reaction and Iris Access will read later.

**Both attachment techniques are needed** and are not interchangeable: clothing
is a skinned mesh (it has to bend at the knee), rigid props — the drawn pistol,
the pack, the unique back item — are `BoneAttachment3D`.

**The rig gap is recorded rather than worked around:** there are no separate
trousers and jacket, `Low Poly Jumpsuit` is one mesh. Slots can be declared
now, but the visuals cannot be independent, and "conceal the pistol in the
jacket" has no distinct jacket yet.

*Уточнён раздел про экипировку: шесть слотов-гнёзд без сетки, кобура на поясе
запрещена навсегда, оружие и стойка — одно состояние симметрично в обе
стороны, у предмета появляются ровно два enum (размер и то, как он читается
наблюдателем). Записано и то, что отдельных штанов с курткой в риге нет.*
- `docs/planned_scope.md`

---

## 2026-08-23 - Record the Equipment / Inventory / Interact direction

Documentation only, no code: H3 and H4 are still open and this project builds
one horizon at a time, so H5 stays closed. The direction existed only in
conversation, and three findings made writing it down worth doing now rather
than at H5.

`InteractComponent` owns item-flow that is not its job — it holds
`@onready var inventory: InventoryComponent` and decides an item's fate itself
in `_store_to_inventory()`. Equipment belongs between the two, and the seam
needs naming before anyone widens Interact further.

A slot holding an `ItemResource` reference would be **unsaveable by
construction**: `SaveSystem`'s payload rule is dictionaries, arrays and
primitives only. Recorded as a hard rule — `item_id: StringName` resolved
through a registry, and the three save-contract methods from the first commit,
not retrofitted. The open sub-problem is recorded too rather than solved:
`SaveSystem` walks `WORLD_SYSTEM_SCRIPTS` only, so no player component has a
route into a save today.

The clothing technique was wrong in the sketch and the repository already holds
the right one. Trousers on a `BoneAttachment3D` follow one bone rigidly and
will not bend at the knee; `Low Poly Jumpsuit` in `player.tscn` is a
`MeshInstance3D` skinned to the whole `OriginalSkeleton`, and that is the
pattern. Bone attachment stays for rigid props — its one existing use is the
Votive on `Head`. Two traps recorded alongside it: the default body is **not**
naked (five meshes on `OriginalSkeleton`, so a naked baseline hides rather than
adds), and an equipment mesh must never carry the `archetype_body_mesh` group
or `_apply_archetype()` will paint over its material.

The canonical item model — volume, concealment, visibility — is deliberately
NOT recorded. It predates this page, is not recoverable from the repository,
and Stan chose to defer the question rather than have a half-remembered version
written down as canon.

*Записано направление Interact → Equipment → Inventory: кода ноль, H5 закрыт до
закрытия H3/H4. Ключевое — слот обязан хранить StringName, а не ссылку на
ресурс, иначе экипировка несериализуема by construction; и одежда — это
скиннингованный меш, а не BoneAttachment3D, иначе штаны не согнутся в колене.
Модель предмета намеренно не записана.*
- `docs/planned_scope.md`

---

## 2026-08-22 - Attach the morphs: both gesture widgets now drive a glyph

The morph layer landed with no scene wiring, so nothing drove it — the code
was correct and invisible. Both hosts now carry a `Morph` child running
`three_dots_morph.gd`, found by `MorphIcon.find_in()` at `setup()`.

One trap caught while doing it: `btn_drag_handle`'s anchors describe an 8x8
rect, and every pixel beyond that came from its `text = "( )"`. Clearing the
text as the guide said would have collapsed the pause handle into a nearly
unclickable target, so the button gained `custom_minimum_size = Vector2(36,
36)` in the same edit. `%Hammer` is 64x64 by its own offsets and needed no
equivalent.

Both `.tscn` files were edited as text — the godot-ai MCP server needs an open
editor and there is none here. The edits are a leaf `Control` child plus one
`ext_resource` each, written without a `uid` (Godot fills that in on first
save; `perception_debug_panel.gd` is already referenced the same way). Verify
in the editor before trusting them.

Note for play: clearing `%Hammer`'s `text = "PULL"` removes the only words
telling a first-time player what the hammer is for. The morph is now the whole
affordance.

*Морфы привязаны к обеим сценам. По дороге поймана ловушка: паузный хэндл
держался на размере своего текста, и его очистка схлопнула бы кнопку —
добавлен custom_minimum_size. Сцены правлены как текст, MCP-сервер Godot
требует открытого редактора; проверить в редакторе.*
- `ui/ingame_menu/in_game_menu.tscn`, `ui/main_menu/revolver_menu.tscn`, `docs/MORPHS_INTEGRATION.md`

---

## 2026-08-22 - Morph icons: a spring-driven glyph for gesture widgets

The pause handle and the revolver hammer are grab-and-throw widgets with no
visual state of their own — nothing on screen said "you have hold of this".
`ui/widgets/morphs/` adds one: three dots that spring between a line at rest
and a turning circle while held, drawn in `_draw()` with no child nodes.

Stan supplied the solver, the glyph and three controller patches; the patches
went in essentially verbatim (they are additive — `_set_phase()` replacing bare
assignments, a `phase_changed` signal, an optional third `setup()` argument),
including one genuine fix carried in them: `strike()` now enters `RETURNING`
before flying home, where the phase used to stay `STRIKING` the whole way.

Two things were changed from what was supplied, both agreed first:

**`MorphIcon` as the declared type.** The originals typed against
`ThreeDotsMorph`, which would have made the stated goal — "a new morph script,
controllers unchanged" — false: a second glyph could not have been passed
without editing all three controllers. Added a base class in the same shape
`ActorBase` already uses, owning the `Mode` vocabulary, the three named
shortcuts, `get_mode()`, and a static `find_in()` that replaced the duplicated
`_find_morph()`. `ThreeDotsMorph` now overrides exactly one method,
`set_mode()`.

**`SpringPoint.MAX_STEP`.** Semi-implicit Euler at `DAMPING 22` is stable only
below roughly 0.09s per step. At 55 FPS the margin is five-fold, but this build
streams world content on threads with a per-frame instantiation budget, and
past that bound the solver does not degrade — it diverges and the dots leave
the screen. Clamping makes a long frame play slightly slow instead. Stiffness
and damping stay constants: identity with the motion study they came from is
the reason they are constants.

Scene wiring is manual and not done here — attaching a `Morph` child under
`btn_drag_handle` and `%Hammer` is an editor job, described in
`docs/MORPHS_INTEGRATION.md`. Until then nothing changes: a missing morph is
the ordinary silent case. `ui/settings/setting.gd` is a third host that could
take one and currently does not.

*Добавлен слой morph-иконок: три точки, пружинно переходящие между линией
покоя и вращающимся кругом захвата. Патчи Стана легли почти дословно; изменены
две вещи — тип в контроллерах поднят до базового MorphIcon (иначе второй
morph потребовал бы правки контроллеров, вопреки заявленной цели) и в
SpringPoint добавлен кламп шага, иначе на просадке кадра решатель расходится.
Привязка в сценах — вручную в редакторе.*
- `ui/widgets/morphs/morph_icon.gd`, `ui/widgets/morphs/spring_point.gd`, `ui/widgets/morphs/three_dots_morph.gd`, `ui/widgets/toss/drag_handle_controller.gd`, `ui/main_menu/revolver_hammer_controller.gd`, `ui/main_menu/revolver_menu.gd`, `core/controllers/menu_controller/menu_controller.gd`, `docs/MORPHS_INTEGRATION.md`, `CLAUDE.md`

---

## 2026-08-22 - Witness dispatch: a report now brings the city

The H3/H4 playtest ran the witness chain end to end and it worked — and
found that a committed report had **no observable consequence anywhere in
the build**. Three separate causes, one shape: the fact reached
`IncidentRegistry` and nothing acted on it.

**The victim forgot.** `_on_incident_reported()` opens with a knocked-down
guard, and the victim is on the ground in the same frame its own assault is
reported — so it returned before `_remembers_player` was ever set. Every
bystander remembered the player; the one NPC with the best reason to run got
up and stared, waiting for the next punch. Now set on the knockdown edge in
`_decide()` instead: being put on the ground is first-hand knowledge, needs
no cone maths, and covers a punch the NPC never saw coming.

**Drones never came.** Two faults stacked: `alert_incident_radius` (60m) with
drones standing 150–400m from the crowd, so none was ever provoked; and
`_decide_alert()` with no visible player calling `_decide_hold_and_watch()`,
which issues `set_move_intent(Vector3.ZERO, 0.0)` — an alerted drone hovered
in place and could not travel to an incident at all.

**Patrolmen never came.** `responds_by_approaching` sits behind
`earshot_radius` (25m); the two Patrolmen in `world.tscn` stand 65–120m away
and simply did not hear it.

The fix is not a radius tweak but a second channel, carried on the fact
itself. `Incident.Source` (`DIRECT`/`WITNESS_REPORT`) says HOW the city
learned of something. A unit's own perception radius — drone 60m, NPC 25m —
is unchanged and answers "did I notice this myself". A committed Votive
transmission reaches the whole city: every drone is dispatched and now
actually flies to the named point (`_decide_dispatch()`, ahead of
`alert_memory_time`'s tolerance, which is about not twitching over a dropped
perception frame and says nothing about a drone that hasn't arrived), and a
responding archetype bypasses `earshot_radius` and runs
(`respond_speed_ratio` 0.85 → 1.0, the blend space's actual run point).
Ordinary bystanders get no bypass — Flee/Freeze/Call stay hearing-bound.

Only the LIVE signal dispatches; all catch-up queries stay radius-bound, or a
day-old report restored from a save would scramble the whole city on load.
Save format gained `"source"` with NO version bump — it reads back with a
`DIRECT` default, which is the correct reading of a file written before the
field existed, and `SaveSystem` refuses an unrecognised version outright.

Also `flee_far_distance` 40 → 80: at 40m a fleeing NPC was still comfortably
on screen when it stopped, reading as the panic wearing off rather than as
escape.

*Донос теперь имеет последствие. Найдены три причины: жертва не запоминала
(ранний выход по нокдауну), дроны не долетали (радиус 60м и зависание на
месте), патрульные не слышали (25м). Введён Incident.Source: собственный
радиус восприятия остаётся как был, а переданный вотивом отчёт поднимает
весь город — дроны летят, патрульные бегут.*
- `core/world/incident_registry/incident.gd`, `core/world/incident_registry/incident_registry.gd`, `npc/controllers/idle_npc_controller.gd`, `world/police_drone/controllers/patrol_drone_controller.gd`, `CLAUDE.md`, `docs/NPC_REACTIONS.md`, `docs/attribution.md`

---

## 2026-08-22 - docs/visual_language.md: write the comic frame down

New artist- and animator-facing document, not a section inside an existing
one. The criterion was where a concept artist would find it: every existing
doc is a systems or design specification addressed to whoever implements the
loop, and a visual-identity rule buried in `NPC_REACTIONS.md` §2 is a rule
nobody drawing the game will ever read. It is the repository's first
document about *look* rather than mechanism.

States the comic frame as a frame around the noir rather than a replacement
(same high contrast, same hard shadow, same "one big detail instead of an
explanation"); the onomatopoeia rule (voice of the panel, never of the
author — it names an event and never advises, which is what keeps it
compatible with `core_loop.md`'s "the city does not explain itself"); the
hard word-on-EVENT-never-STATE rule with the arithmetic behind it; the
distance gate and the simultaneous-word ceiling as art direction rather than
optimisation; sound as a separate layer; and the vocabulary as data.

Cross-linked from `npc_archetypes.md` §3 and `NPC_REACTIONS.md` §2, since an
artist arrives at readability first. One correction while linking: the flat
archetype colours are named as **scaffolding**, per `npc_archetypes.md` §4's
own wording, not as an established visual decision to build on.

*Написан docs/visual_language.md — отдельный документ для художника, а не
раздел в спецификации: комикс как рамка поверх нуара, правило «слово на
событие, не на состояние», гейты как часть языка, звук отдельным слоем.*
- `docs/visual_language.md`, `docs/npc_archetypes.md`, `docs/NPC_REACTIONS.md`, `CLAUDE.md`

---

## 2026-08-22 - The player gets comic words too

Five new defs (`player_hurt`/`player_death`/`player_winded`/`player_spent`/
`player_combat`) and their wiring in `player.gd`. Until now the comic layer
only spoke for the crowd; the player's own body was silent, which made the
device read as something that happens to NPCs rather than a voice the frame
has.

Every hook is an EDGE, deliberately, since the word-on-event rule is the
one thing that keeps this layer from becoming noise: a health DECREASE seen
through `health_changed` (tracked with `_last_health_seen` — `HealthComponent`
has no `damaged` signal, and growing one to feed a decoration would be the
wrong direction of dependency), `sprint_allowed_changed(false)` for running
out of wind, `stamina_depleted()` for having none left, `died()`, and
`stance_changed` on entering `COMBAT` only. None of them polls a state.

`player_combat` takes its hue from `StanceIndicator.combat_color` so the
floating word and the HUD badge read as one statement, lightened enough to
stay legible unbacked over the world.

*Игрок тоже получил слова: ранение, смерть, одышка, пустая стамина и вход в
COMBAT. Все крючки — на фронт события, не на состояние.*
- `data/comic_effects/player_*.tres`, `data/comic_effects/catalog.tres`, `player/player.gd`, `CLAUDE.md`

---

## 2026-08-22 - Wire the last two comic effects, npc_hit and npc_transmit

Both were registered and called from nowhere.

`npc_hit` goes on `NPCBase.take_hit()`'s other branch — the hit that lands
on a body already down, damaging it (and able to finish it off) without
starting a new knockdown. The early `return` sitting between the two
branches is what guarantees a single hit never produces both words.

`npc_transmit` marks the moment the report actually reaches
`IncidentRegistry` (`_commit_witness_report()`), **not** the start of
transmission as first specified. `_start_calling()` decides to call and
calls `_votive.start_transmitting()` in the same frame, so a `npc_transmit`
placed there would stack a second word on the same head in the same frame,
right next to `npc_call`. Commit time is the only genuinely distinct event
in the chain; the alternative — somewhere mid-countdown — would be a state,
not an event, and states are exactly what the comic layer must not narrate.

*Подключены оставшиеся два эффекта. npc_hit — на попадание по уже лежащему
телу (одна ветка, поэтому два слова с одного удара невозможны).
npc_transmit перенесён с начала передачи на момент фактической отправки
отчёта: начало передачи и решение звонить — один и тот же кадр.*
- `npc/npc_base.gd`, `npc/controllers/idle_npc_controller.gd`, `CLAUDE.md`

---

## 2026-08-22 - Widen the comic vocabulary to 6-7 words per event

Two or three variants per event made repeats obvious within a single fight.
Every pool is now seven, except `npc_death`, deliberately left at three
(…, SILENCE, STILL): the quiet at the end works because there is almost
nothing to say, and a seven-word death pool would talk over it.

Tone held to short, capitalised, no exclamation marks — the word registers
what happened and never tells the player what to do or feel. `npc_freeze`
gained a bare `?`, the most comic-page-native token available and the one
that reads as bewilderment without a syllable.

*Словари расширены до семи вариантов на событие; смерть намеренно оставлена
на трёх — тишина работает за счёт скудости.*
- `data/comic_effects/*.tres`

---

## 2026-08-22 - Comic effect defs move from code into data/comic_effects/

The seven defs seeded by `_load_default_defs()` are now seven `.tres` files
gathered by a `ComicEffectCatalog` (`data/comic_effects/`, one file per
event) — same shape as `data/key_hints.tres`, one file per item like
`data/npc_archetypes/`. `_load_default_defs()`/`_register_simple()` deleted
rather than left unused. The comic layer is a visual language of this
project, not a debug tool, so it will keep growing; growing it must not mean
editing GDScript.

Found by path (`CATALOG_PATH`), not by an `@export` and not by scanning the
folder. `ComicEffectSystem` is built with `.new()` from
`WORLD_SYSTEM_SCRIPTS` and has no inspector, which rules out the `@export`
route `KeyHintsPanel` uses; a `DirAccess` scan is worse than it looks, since
an exported build converts `.tres` to binary behind `.remap` and a runtime
search for `*.tres` would quietly return a full set in the editor and an
empty one in a shipped build. Failure stays non-fatal: a missing catalog or
an empty `texts` pool warns and leaves that id unspawnable, exactly as
before. Also dropped the dead `last` parameter from `_pick_weighted()`.

*Определения комикс-эффектов вынесены из кода в data/comic_effects/ —
по .tres на событие плюс каталог. Каталог грузится по пути: у системы,
создаваемой через .new(), нет инспектора, а скан папки ломается в
экспортированной сборке.*
- `core/ui/comic_effect/comic_effect_catalog.gd`, `core/ui/comic_effect/comic_effect_system.gd`, `data/comic_effects/*.tres`, `CLAUDE.md`

---

## 2026-08-22 - ComicEffectSystem: floating reaction words

New `WORLD_SYSTEM_SCRIPTS` entry (`core/ui/comic_effect/`, three files:
`ComicEffectDef` / `ComicEffectLabel` / `ComicEffectSystem`) drawing a
screen-space word above an event — unprojected from a world point every
frame via `Camera3D.unproject_position()`, so it orbits with the camera
instead of sitting at a fixed viewport spot. Pure visual; explicitly not
audio, and `ComicEffectDef` must not grow a sound field.

Three deliberate constraints: a distance gate (`ComicEffectDef.radius`,
from the player — an event beyond it never spawns anything, so a fight
fifty metres away doesn't litter the screen), a fixed pool (12 labels,
8 active max, reused rather than freed) for a flat cost against the ~55 FPS
target, and per-id anti-repeat. Resolved by consumers through
`GROUP_COMIC_EFFECT_SYSTEM` the same way `IncidentRegistry` is — no static
facade, since no other system entry has one.

Wired at five sites, split by ownership: `NPCBase` spawns `npc_knockdown`
(on the hit that starts a knockdown) and `npc_death` (`_enter_down_phase()`);
`IdleNPCController` spawns `npc_flee`/`npc_freeze`/`npc_call` from its
`_start_*` reaction entries. `npc_hit`/`npc_transmit` are seeded but unused.

*Добавлена система всплывающих слов-реакций над NPC — чисто визуальная, не
звук. Дистанционный гейт, пул фиксированного размера и анти-повтор; систему
находят через группу, как IncidentRegistry. Подключена в пяти точках:
падение и смерть — со стороны тела, бегство/ступор/звонок — со стороны
контроллера.*
- `core/ui/comic_effect/comic_effect_def.gd`, `core/ui/comic_effect/comic_effect_label.gd`, `core/ui/comic_effect/comic_effect_system.gd`, `world/world.gd`, `npc/npc_base.gd`, `npc/controllers/idle_npc_controller.gd`, `CLAUDE.md`

---

## 2026-08-22 — readme.md: the Status line no longer denies what is built

The one-line status still read "Combat, AI, missions and saving are not
[implemented]" — written before the stance/punch/knockdown pass, the NPC and
drone controllers, the witness/incident chain and `SaveSystem` all landed. A
reader's first paragraph was flatly contradicted by the rest of the repo.
Rewritten to name those as first slices, and to keep the genuinely unbuilt
list honest: missions, metro and lift transport, and `attribution.md` §5's
attribution system.

*Строка Status в readme.md утверждала, что боя, ИИ и сохранений нет — всё
это уже собрано первыми срезами. Переписана; в списке нереализованного
остались миссии, метро/лифты и система атрибуции.*
- `readme.md`

---

## 2026-08-21 - Witness reaction: proximity interrupts a call, and witnesses remember

Two additions to `idle_npc_controller.gd`'s incident reaction, both extending
`NPC_REACTIONS.md` §4:

**Call interruption by proximity.** `_step_calling()` now checks
`_is_player_approaching()` every frame a report is `PENDING`; if the player
is closing in on a still-transmitting witness, `_abort_call_for_flee()`
cancels the report (same `CANCELLED` path a knockdown already gives, via
`_cancel_active_witness_report(reason)`, now parameterized instead of a
hardcoded "knocked down" string) and hands off into the ordinary `FLEEING`
state machine — reusing it, not a second implementation.

**The two-phase Flee reaction itself was corrected** to match the task's
own spec: `BACKING_AWAY` is now a fixed `backpedal_duration` (2s), not
gated by distance to the player or by the player still approaching
(`backpedal_distance_threshold` removed); `RUNNING`'s direction
(`_flee_direction`) is now computed exactly once, at the moment
`_enter_flee_phase()` turns into `RUNNING`, away from a fixed
`_flee_threat_position` — never toward the player and never recomputed per
frame; `RUNNING` now ends once `flee_far_distance` (40m default) is
covered, with `flee_duration` repurposed as a per-phase safety cap
(default raised 4.0 → 20.0) rather than the whole reaction's own timer.

**Witness memory.** `_remembers_player`, set once and never cleared the
moment ANY archetype's `vision.is_seen` comes back true in
`_on_incident_reported()` (any witness, not only a caller) — from then on,
`_decide()`'s ordinary observe-player branch skips straight to
`_start_flee(observation.position, false)` the instant the player is seen
again, no incident required. Lives on the controller (a child of the NPC),
so it disappears on block unload — deliberately not moved into
`IncidentRegistry`.

*Реакция свидетеля: приближение игрока прерывает звонок (тот же CANCELLED,
что и нокдаун), двухфазный побег исправлен под спецификацию (пятение по
времени, бег по дистанции, направление фиксируется один раз), и свидетели
теперь запоминают игрока навсегда — флаг живёт на контроллере, не в
IncidentRegistry.*
- `npc/controllers/idle_npc_controller.gd`, `CLAUDE.md`

---

## 2026-08-21 - Fix stale "no run animation" comments

No code change: `NPCAnimationComponent`'s locomotion blend was already
widened from a 2-point idle/walk `BlendSpace1D` to a signed 4-point
idle/walk/run/backward one, and the two-phase flee reaction already reads
correctly off it (`63c9c18`, prior session) — but three comments in
`idle_npc_controller.gd` and one in `CLAUDE.md` still claimed "no run
animation"/"no run clip" and were never updated at the time, exactly the
kind of drift `CLAUDE.md`'s own workflow rule warns about. Fixed the
wording only; `ANIM_BACKWARD`/`ANIM_RUN` (`npc_animation_component.gd`)
were already wired and did not need touching.
*Правка устаревших комментариев — анимации бега/пятения уже подключены
раньше, но комментарии этого не отражали.*
- `npc/controllers/idle_npc_controller.gd`, `CLAUDE.md`

---

## 2026-08-21 - Witness Call becomes a deterministic archetype trait

Removed `IdleNPCController.witness_density`/`call_probability` and the
per-NPC `_is_witness` flag rolled once at spawn — replaced by
`NPCArchetypeData.is_witness_caller` (`false` by default, `true` only on
`Clerk`). Whether an NPC ever calls in what it witnesses is now a property
of its archetype, not a population-wide roll: `_on_incident_reported()` no
longer rolls `call_probability` against a random draw — a calling archetype
that clears the vision gate always calls; a non-calling archetype (or one
that didn't actually see the incident) falls through to the ordinary
Flee/Freeze roll, unchanged. `Patrolman`'s `responds_by_approaching` is
unaffected — it still bypasses both the Call check and the Flee/Freeze roll
entirely. Incident telemetry now logs a non-calling archetype as
`REJECT archetype` instead of `REJECT not-witness`.
*Звонок свидетеля теперь детерминированное свойство архетипа (только
Clerk), а не популяционный бросок кубика — witness_density/call_probability
убраны.*
- `npc/npc_archetype_data.gd`, `data/npc_archetypes/clerk.tres`, `npc/controllers/idle_npc_controller.gd`, `CLAUDE.md`

---

## 2026-08-21 - Remove the crowd witness debug mode

`WitnessDebugSystem` (added 2026-08-19) subsidized numbers instead of proving
the mechanic — a diagnostic that made the chain easy to trigger on demand
told nothing about whether the honest, rare numbers actually worked, and
having a second, debug-only code path (the four `_effective_*()` getters on
`IdleNPCController`) was extra surface for no lasting benefit. Removed
outright: the file, its `WORLD_SYSTEM_SCRIPTS` entry, the `toggle_witness_debug`
action (`[`, now unbound), the `InputSystems.witness_debug_toggled` signal,
and the four `_effective_*()` getters — `IdleNPCController` reads
`_perception.vision_range`/`earshot_radius`/`call_probability`/`_is_witness`
directly again, same as before the debug mode existed.
*Убран режим отладки толпы свидетелей — он подменял числа вместо проверки
механики; тот же четырёхпутевой геттер убран, чтение снова прямое.*
- `core/world/witness_debug_system/` (deleted), `npc/controllers/idle_npc_controller.gd`, `world/world.gd`, `core/input/input_systems.gd`, `project.godot`, `input_map.md`, `CLAUDE.md`

---

## 2026-08-19 - Add a crowd witness debug mode

The honest witness numbers (`witness_density` 0.15, `call_probability` 0.6,
per-archetype `vision_range` 6–20m) are correct by design — Doggerland is
meant to be a city where almost nobody reports anything — but that also
means a playtest only sees a Call once every three or four punches, which
made the whole chain hard to verify by eye (see the incident telemetry
added earlier the same day: the mechanic works, the numbers are just rare).
Added `WitnessDebugSystem` (`core/world/witness_debug_system/`, a new
`WORLD_SYSTEM_SCRIPTS` entry), toggled live for the entire crowd by a new
hotkey (`toggle_witness_debug`, `[`), off by default, printing an unmissable
`push_warning()` naming every overridden value on both enable and disable.
While enabled: `witness_density`/`call_probability` read as `1.0`;
`vision_range`/`earshot_radius` are scaled by two independent `@export`
multipliers (both default `3.0`) rather than one shared multiplier, since
sight and hearing are different channels and tying them together could hide
a channel-specific bug. Never mutates the `.tres` archetypes or
`IdleNPCController`'s own exported values — `IdleNPCController` reads
through four new `_effective_*()` getters instead, so the reaction-selection
logic itself (`_on_incident_reported()`/`_evaluate_incident_vision()`) never
learns the debug mode exists, per this task's own requirement. `_is_witness`
(rolled once per NPC at spawn) can't be retroactively re-rolled by a
mid-session toggle, so `_effective_is_witness()` overrides the CHECK at the
moment a candidacy is evaluated instead.

*Добавлен режим отладки толпы свидетелей — один хоткей ("[") подменяет
плотность/вероятность/дальность на всю толпу вживую, честные числа в
.tres и экспортах не трогаются.*
- `core/world/witness_debug_system/witness_debug_system.gd`, `npc/controllers/idle_npc_controller.gd`, `world/world.gd`, `core/input/input_systems.gd`, `project.godot`, `input_map.md`, `CLAUDE.md`

**Complete incident telemetry with the Flee/Freeze outcome.** A candidate
that got a `REJECT not-witness` (or a vision rejection, or lost the Call
roll) line used to have its story cut off there — the code always falls
through to the ordinary Flee/Freeze roll afterward, but nothing said which
way it landed, so a developer reading the log couldn't tell "the roll
didn't happen" from "it happened but has no visible effect." Added
`_log_incident_outcome()`, printed right after that roll for every
candidate that reaches it — confirmed by reading the code that this path
always resolves to `FLEE` or `FROZEN`, never silently to nothing.

*Телеметрия инцидентов теперь показывает итог броска Flee/Freeze для каждого
кандидата, а не обрывается на причине отказа от звонка.*
- `npc/controllers/idle_npc_controller.gd`, `CLAUDE.md`

---

## 2026-08-19 - Fix: NPC obstacle-avoidance raycast never entered the tree

`IdleNPCController._obstacle_ray` was built in `_ready()` but its
`_npc.add_child(_obstacle_ray)` call had been commented out, so
`is_colliding()` always read false — wander, Flee and Respond all share this
check, so obstacle avoidance was inert everywhere it's used, and NPCs walked
into walls. Root cause: `IdleNPCController` is a child of `NPCBase` in
`npc.tscn`, so its `_ready()` runs while the NPC subtree is still entering
the tree, and `NPCBase` (the ancestor being added to) is still "busy setting
up children" at that point — a plain `add_child()` onto it fails outright.
Fixed with `_npc.call_deferred("add_child", _obstacle_ray)`, the same
pattern already used by `world.gd`'s `WORLD_UI_SCENES` loop, `menu_system.gd`
and `zoom_ruler_system.gd` for the identical ordering problem (see this
file's 2026-08-1X `PlayerHUD` crash entry). Rewrote the file's header, which
had claimed the ray was already working.

*Луч обхода препятствий у NPC никогда не добавлялся в дерево — исправлено
через call_deferred("add_child", ...), та же проблема порядка готовности,
что и раньше у PlayerHUD.*
- `npc/controllers/idle_npc_controller.gd`

**Add a debug action label above NPCs.** `NPCBase.debug_show_action` shows a
second `Label3D` (`DebugActionLabel`, stacked above `DebugHealthLabel`) with
a short word for what the NPC is doing right now — `WALK`/`IDLE`/`LOOK`/
`FLEE`/`CALL`/`DOWN`, plus an optional one-line reason (`saw`, `incident`,
`responding`, `witness`) — so a reaction that fired but has no visible
effect yet can be told apart from one that never fired at all.
`IdleNPCController.get_debug_action_text()` supplies the word/reason for
everything but `DOWN` (resolved directly from `is_knocked_down()`);
`NPCBase` finds it by capability (`has_method()`), resolved once in
`_ready()`, the same opt-in idiom the save contract and `on_world_ready()`
already use — the body still never names a controller class. Updates only
on state change, not every frame, unlike the health label.

*Добавлена вторая отладочная метка над NPC — короткое слово + причина,
что NPC делает прямо сейчас, обновляется по смене состояния.*
- `npc/npc_base.gd`, `npc/controllers/idle_npc_controller.gd`, `npc/npc.tscn`, `CLAUDE.md`

**Mount VotiveProjector on the head bone instead of the body root.** The
projection used to be offset from the root's own facing, so it never
reflected head-look — wrong, since attribution.md §6's Votive is meant to
read as "this NPC is looking at you." Both rigs retarget through
`GeneralSkeleton` (drives the `AnimationPlayer`) into `OriginalSkeleton`
(what every visible mesh is actually skinned to, and what the existing
head-look `LookAtModifier3D` already targets) — `VotiveProjector` now
parents under a `BoneAttachment3D` bound to `OriginalSkeleton`'s `"Head"`
bone (bone index 5) in both `npc.tscn` and `player.tscn`. `player.tscn`
already carried an unused `BoneAttachment3D` at that exact bone, leftover
from an earlier, interrupted pass at this same task; `npc.tscn` gained a
matching one. Replaced the old owner-`get_eye_height()` duck-typed
positioning with `bone_local_offset`/`bone_rotation_compensation_deg`
(both `@export`, tuned by eye — a bone's local axes rarely match this
node's -Z-forward assumption). Since the node no longer sits directly
under the body root, `NPCBase`/`player.gd`/`IdleNPCController` all now
resolve it via scene-unique name (`%VotiveProjector`) instead of a
direct-child path.

*Вотив теперь крепится к кости головы (BoneAttachment3D на OriginalSkeleton),
а не смещением от корня — проекция следует за поворотом головы.*
- `core/components/votive_projector/votive_projector.gd`, `npc/npc.tscn`, `npc/npc_base.gd`, `npc/controllers/idle_npc_controller.gd`, `player/player.tscn`, `player/player.gd`, `CLAUDE.md`

---

## 2026-08-18 - Name collision layers, add CollisionLayers, fix three mask bugs

Six physical query sites were each re-deriving floor/wall bit combinations by
hand, with no shared name for what any of them meant — `project.godot`'s
`[layer_names]` left layers 1 and 9 unnamed (occupied by player/NPC bodies by
default, and the police drone body, respectively; named `Characters` and
`Drones`). Added `docs/COLLISION_LAYERS.md` as the single source of truth for
the layer table (who's on each layer, who queries it — filled in from the
actual scenes/scripts, not assumed) and `core/physics/collision_layers.gd`
(`CollisionLayers`, no autoload, same pattern as `Smoothing`/`BodyMetrics`)
defining named query profiles (`SIGHT`, `CAMERA_OCCLUSION`, `OBSTACLE`,
`GROUND`, `INTERACTION`, `CURSOR_UI`) on top of the raw layer bits. Converted
every bare-literal mask found (perception, camera occlusion, NPC obstacle
avoidance, the interactable RigidBody's own mask, the player's interactable
focus cast, and — found along the way — the 3D cursor's UI hover raycast) to
read from `CollisionLayers` instead.

Three real bugs surfaced while doing this, fixed in the same pass:
`IdleNPCController`'s obstacle-avoidance ray was built but never parented
into the scene tree, so it never actually collided — wander/flee/respond all
share the check and were all silently un-obstructed; checked why it had been
left that way and found an earlier task's brief had explicitly ruled out
navigation changes, not a finding that avoidance broke wandering, so wired it
in. `InteractiveVisualIndicator`'s ground-detection raycast mask was wall,
contradicting its own "layer 2 = ground" comment — now floor.
`PerceptionComponent` and the camera's occlusion raycast used to share one
undifferentiated floor+wall mask; split apart now that each has its own
profile — perception drops floor (`SIGHT` is wall-only, fixing an
already-flagged "open, undiagnosed defect" where sight checks failed on
slopes/stairs), the camera keeps both. `Interactables.gd`'s own
floor+PhysicsObjects mask (missing wall — why a thrown item doesn't stop at
a wall) was left as found; its rationale isn't recoverable from the code and
this pass didn't invent one.

Also recorded `RaycastService` in `docs/planned_scope.md`'s "Not started, not
stubbed" — six one-line queries don't justify a facade over them yet; the
mask drift they shared is what `CollisionLayers` solves instead.

*Названы физические слои 1 (`Characters`) и 9 (`Drones`); добавлены
`docs/COLLISION_LAYERS.md` и `CollisionLayers` с именованными профилями
запросов; код переведён с магических чисел на них. Попутно найдены и
исправлены три бага: не работавший обход препятствий у NPC (луч не был
добавлен в дерево сцены), неверная маска у индикатора направления пола, и
слипшиеся маски восприятия/камеры (у восприятия теперь нет пола — это чинит
уже отмеченный ранее дефект с проверкой видимости на лестницах и уклонах).*
- `project.godot`, `docs/COLLISION_LAYERS.md`, `core/physics/collision_layers.gd`,
  `npc/npc_components/perception_component/perception_component.gd`,
  `camera/camera_component/on_foot_camera_component.gd`,
  `npc/controllers/idle_npc_controller.gd`,
  `world/interactables/interactables.gd`, `world/interactables/interactive_visual_indicator.gd`,
  `player/player_components/interact_component/interact_component.gd`,
  `ui/widgets/dynamic_cursor/dynamic_cursor_ui.gd`,
  `docs/planned_scope.md`, `CLAUDE.md`, `docs/CONTRIBUTING.md`
- Behaviour changes worth confirming by running the game, separately from the
  rest of this pass: NPC obstacle avoidance actually engaging now, and
  perception's sight checks no longer failing through floor on slopes/stairs.

---

## 2026-08-18 - Add witness incident telemetry

`IdleNPCController` now emits a concise `[WitnessTelemetry]` event block per
live incident: every hearing-range NPC is named with its range/cone outcome,
witness status and Call roll, including rejected candidates. The range/cone
calculation was extracted into one typed result shared by the Call gate and
the log, so the explanation cannot diverge from the actual decision. Start,
cancellation (with remaining time), and committed transmission events log
separately. The export defaults on for the current vertical-slice playtest.

*Добавлена событийная телеметрия решений свидетелей: видны все кандидаты и
причина каждого отказа, без покадрового спама.*
- `npc/controllers/idle_npc_controller.gd`, `CLAUDE.md`

---

## 2026-08-17 - Limit archetype colour to authored NPC body meshes

`NPCBase._apply_archetype()` previously walked every descendant
`MeshInstance3D`, so it overwrote the self-lit quad `VotiveProjector` creates
in its own `_ready()` before the parent NPC applies its archetype. The flat
placeholder material now applies only to meshes explicitly tagged
`archetype_body_mesh` in `npc.tscn`; the five existing rig meshes carry that
tag. Component-owned geometry is safe by default: an untagged future Votive
or equipment mesh keeps its own material, while an untagged future body part
visibly keeps its native material and must be tagged deliberately.

*Цвет архетипа теперь применяется только к явно помеченным мешам тела NPC:
вотив и будущая экипировка сохраняют собственный материал; новый меш тела
нужно пометить явно.*
- `npc/npc_base.gd`, `npc/npc_archetype_data.gd`, `npc/npc.tscn`, `CLAUDE.md`

---

## 2026-08-17 - Wire Entire checkpoint capture for Codex

Ran `entire agent add codex`, which installed `.codex/hooks.json` (SessionStart /
PostToolUse / Stop / UserPromptSubmit — same `command -v entire` PATH-lookup shape as
the existing Claude Code hooks in `.claude/settings.json`). `.entire/settings.json`
(`enabled: true`, `push_sessions: false`) is unchanged — those settings are
project-level, not per-agent, so Codex checkpoints are captured locally and do not
auto-push, same as Claude Code's. Documented in `CLAUDE.md` (Entire section) and
`docs/ENTIRE_SETUP.md` (new "Codex hooks" paragraph, PATH-lookup note generalized to
cover both agents).

*Подключён Codex ко второй половине трекинга Entire (`entire agent add codex`) — те же
хуки и то же поведение с PATH, что у Claude Code; настройка `push_sessions: false`
общая на проект, отдельно настраивать для Codex не нужно.*
- `.codex/hooks.json` (new), `CLAUDE.md`, `docs/ENTIRE_SETUP.md`

---

## 2026-08-17 — Stop Entire checkpoints from auto-pushing to public origin

`github.com/Nolavel/ADT` is public; the `entire/checkpoints/v1` branch Entire pushes
alongside normal commits carries full session transcripts, which can include
non-public discussion content. Set `strategy_options.push_sessions: false` in
`.entire/settings.json` (`entire configure --project --skip-push-sessions`) — capture
stays on (`enabled` unchanged), only the pre-push auto-push of the checkpoint branch is
off. Zero checkpoints existed at the time of the fix, so nothing had leaked. Also
documented (`docs/ENTIRE_SETUP.md`, new) that `entire status`'s "Checkpoints sync to"
line doesn't reflect this setting, where the `entire-cli` binary lives relative to the
repo, that Claude Code's own hooks resolve it via PATH (unlike git's hooks, which bake
in an absolute path and are unaffected by PATH changes), and that
`--absolute-git-hook-path` does not cover that PATH-based lookup.

*origin публичный, чекпоинты содержат непубличные транскрипты — отключено
автоматическое проталкивание ветки чекпоинтов (`push_sessions: false`), запись
осталась включена. Задокументировано отдельно: где лежит бинарник, чем поиск через
PATH у хуков Claude Code отличается от абсолютного пути у git-хуков.*
- `.entire/settings.json`, `CLAUDE.md`, `docs/ENTIRE_SETUP.md`

---

## 2026-08-17 — Document Entire in CLAUDE.md and CONTRIBUTING.md

New "Observability (Entire checkpoints)" section in `CLAUDE.md`: what Entire is here,
that a checkpoint is raw session evidence and does not replace a `CHANGELOG.md` entry
(keep writing both), and that `entire/checkpoints/v1` is not a branch to check out,
merge, or clean up. One line in `docs/CONTRIBUTING.md`'s Workflow section so a
collaborator who hasn't seen Entire before isn't confused by an unfamiliar branch in
`git branch -a` or an `Entire-Checkpoint` trailer in a commit message.

*Раздел про Entire в CLAUDE.md (что это, чекпоинт не заменяет CHANGELOG.md, ветку
чекпоинтов не трогать) и строка в CONTRIBUTING.md, чтобы новый коллаборант не удивился
незнакомой ветке/трейлеру.*
- `CLAUDE.md`, `docs/CONTRIBUTING.md`

---

## 2026-08-17 — Entire enabled for Claude Code (checkpoint capture, preview)

Entire (entire.io) added as an observability layer over agent-assisted commits —
versions session transcripts/prompts/tool calls alongside commits on a dedicated
`entire/checkpoints/v1` branch, keeping `main`'s own history untouched. Enabled via
`entire enable -y --agent claude-code`, backend explicitly set to `branch` (the CLI's
actual default on this install was `refs`, contradicting the docs' own comparison
table — forced back to `branch` to match documented behaviour and this repo's
verification steps). `.claude/settings.json` (agent hooks) and `.entire/settings.json`
+ `.entire/.gitignore` (project config) committed per Entire's own guidance for shared
repos; `.entire/settings.local.json` (machine-local: absolute git-hook paths, so
GUI clients like GitHub Desktop that don't load shell `$PATH` can still find the
hooks, plus `commit_linking: always`) stays untracked.

The CLI binary itself is NOT a system install: the official Windows release zip was
downloaded from `entireio/cli`'s GitHub Releases (checksum-verified against the
published `checksums.txt`) into a folder next to this repo, outside the working tree,
and added to this user's own PATH so Claude Code's own agent hooks (which do a plain
`command -v entire` PATH lookup with no absolute-path option, unlike the git hooks)
can find it. No package manager installed, no admin rights used, nothing global to
other users of this machine.

**Not yet verified live in this session:** Claude Code's own hooks are registered at
session start, so the session that ran `entire enable` cannot retroactively capture
itself — Entire's own troubleshooting docs say as much. The first checkpoint will
appear on the next fresh `claude` session in this repo, after both this PATH change
and the new hooks are picked up.

*Entire (entire.io) подключён для Claude Code — версионирует транскрипты/промпты/
вызовы инструментов рядом с коммитами на отдельной ветке entire/checkpoints/v1,
не трогая обычную историю main. Бинарь CLI не ставился как системный пакет — скачан
напрямую с GitHub Releases с проверкой контрольной суммы, лежит рядом с репозиторием,
добавлен в PATH пользователя (это обязательно для перехвата хуков Claude Code, у
которых, в отличие от git-хуков, нет варианта с абсолютным путём). Живая проверка
чекпоинта в этой же сессии невозможна — хуки Claude Code регистрируются в начале
сессии, а `entire enable` выполнялся уже внутри неё.*
- `.claude/settings.json` (new), `.entire/settings.json` (new), `.entire/.gitignore`
  (new); `.entire/settings.local.json` untracked by design

---

## 2026-08-17 — readme.md: fix inconsistent CONTRIBUTING.md path

The "For collaborators" section referenced the file two different ways in the same
file: `docs/CONTRIBUTING.md` earlier in the paragraph, bare `CONTRIBUTING.md` (no
`docs/` prefix, the file does not exist at that path) two sentences later. Made
consistent with the real location and the paragraph's own earlier reference.

*Опечатка в readme.md: ссылка на CONTRIBUTING.md без префикса docs/, при том что в
этом же абзаце чуть выше файл упомянут с правильным путём.*
- `readme.md`

---

## 2026-08-16 — Votive as a projected plane, not a point light

First playtest of the attribution.md §7 slice found the Votive unreadable: a point
`OmniLight3D` at the temple reads as "this NPC is lit," not "this NPC is
transmitting" — no direction, no sense of a screen. `VotiveProjector` now builds a
small self-lit `QuadMesh` floating in front of the face instead (`projection_size`/
`projection_forward_offset`, both `@export`, ~0.2-0.3 range per Stan's own read),
unshaded with `cull_mode` `DISABLED` and a `flip_facing` escape hatch — the quad's
default front-face direction relative to this project's own facing convention
couldn't be verified without running the editor. `temple_side_offset` is gone: the
projection is centred in front of the face, not offset to a side, so that field no
longer meant anything and wasn't kept as dead weight.

**Glow finding, not assumed:** `EnvironmentLightingSystem`'s actual runtime
`Environment` never sets `glow_enabled` — only an unrelated dev tool
(`tools/tests/noir_room/`) does, at `glow_hdr_threshold = 1.1`. Enabling glow
project-wide is a renderer/perf decision this component has no business making on
its own, so visibility here does not depend on it: `shading_mode` `UNSHADED` reads
at full brightness regardless of scene lighting or glow. `emission_energy` (`4.0`)
is still set comfortably above that `1.1` threshold, so the projection blooms for
free the day glow is actually turned on for the real game, without a second pass
here.

Side effect worth as much as the Votive fix itself: the quad turns with the NPC's
own facing, which is the first thing in this build that shows a crowd member's
facing direction at a glance, at distance, without opening the inspector.

*Вотив читался как «этот NPC подсвечен», а не «передаёт» — точечный свет заменён
на самосветящийся квадрат перед лицом, разворачивающийся вместе с NPC. Glow в
реальном окружении игры не включён нигде (только в отдельном dev-инструменте) —
компонент это не трогает и не зависит от glow для видимости.*
- `core/components/votive_projector/votive_projector.gd`, `CLAUDE.md`

---

## 2026-08-16 — Witness Call gated on actually seeing the incident, not just hearing it

Second finding from the same playtest: witnesses reacted as if they could see through
their own backs. `idle_npc_controller.gd`'s Call branch had a distance/attention model
but no vision-cone check at all — an NPC facing entirely away from an incident still
became a caller, just at a level one step lower.

This was a spec bug, not a tuning one: `attribution.md` §2 had folded "didn't see it"
and "saw it, but worse" into one `REDUCED` case, with "facing away" standing in for
both. They aren't the same case. §2 is corrected to split them explicitly, and this
build now only implements the first: `_is_incident_in_vision_cone()` (range against
`PerceptionComponent.vision_range`, angle against half of `vision_angle_deg` — read
from that component's public exports, not called into it, and deliberately without a
line-of-sight raycast, since that component's own `LINE_OF_SIGHT_MASK` already has an
undiagnosed floor-layer defect this gate has no business inheriting) gates entry into
`ReactionState.CALLING` outright. A witness who fails it falls through to the ordinary
Flee/Freeze roll instead of quietly downgrading. `earshot_radius` still gates whether
this NPC reacts AT ALL (hearing-based, unchanged) — only actually reporting now
additionally requires having seen it.

`Attention`, `witness_attention_angle_deg`, `_resolve_attention()` and
`_lower_one_step()` are removed outright rather than left unused: attention itself
isn't applied this iteration (its two real triggers — talking, looking into one's own
Votive — have no mechanic to derive them from), so `_resolve_observation_level()` is
now pure distance ceiling. The debug panel's "attention" line became "in FOV" (always
true by construction today, shown as a plain fact rather than assumed — `attribution.md`
§7's own panel example updated to match, attention line dropped). §7's test case D
("witness talking", one level below IRIS) is corrected to "witness facing away, does
not become a witness at all" — the only version of that case this build can actually
reproduce.

*Свидетель мог "видеть" инцидент затылком — проверки конуса зрения не было вообще,
только дистанция+внимание. Это ошибка спецификации: attribution.md §2 путал "не видел"
и "видел хуже". Добавлен жёсткий гейт по конусу (дистанция+угол через публичные поля
PerceptionComponent, без линии видимости — в компоненте уже известный баг с маской
пола). Attention как модификатор убран целиком, а не оставлен неиспользуемым - для
него просто нет реализованных триггеров. Тест-кейс D в §7 поправлен под то, что
реально воспроизводимо.*
- `npc/controllers/idle_npc_controller.gd`, `ui/debug/perception_debug_panel.gd`,
  `docs/attribution.md`, `CLAUDE.md`

---

## 2026-08-16 — `attribution.md`: Observation → Incident → Report → Attribution design

New design doc (`docs/attribution.md`), Stan's — Observation → Incident → Report →
Attribution as four distinct stages, none of them collapsing "player did X" straight
into "wanted += 1". Only §7 (a witness perception → observation quality →
`WitnessReport` → Votive transmission → COMMITTED/CANCELLED vertical slice) is in the
horizon; §1–§6 and §8 are written down so they aren't re-derived later and stay
deliberately unbuilt until §7 has been played.

Added to `CLAUDE.md`'s Documents table. `NPC_REACTIONS.md` §4's witness-flag-density
open question got a pointer to `attribution.md` §6/§7 instead of a rewrite — the flag
stops being a hidden coin flip once the Call response is a transmission the player can
see happening. `scope_horizon.md`'s H4 entry now describes attribution.md §7 as its
scope directly, and notes H3 stays open (crowd reactions still unverified in play) even
though H4's own prior work (archetypes, witness flag, Flee/Freeze/Call) already landed
in `idle_npc_controller.gd` ahead of H3's Definition of Done being exercised.

*Новый дизайн-документ Стэна: Observation → Incident → Report → Attribution как четыре
отдельные стадии. Строится только §7 (вертикальный срез свидетельской цепочки);
остальное сознательно не реализуется. Обновлены CLAUDE.md, NPC_REACTIONS.md §4 и
scope_horizon.md (H4) — без переписывания текста целиком, только ссылки/срез.*
- `docs/attribution.md`, `CLAUDE.md`, `docs/NPC_REACTIONS.md`, `docs/scope_horizon.md`

---

## 2026-08-16 — Witness observation quality and `WitnessReport` (attribution.md §7, part 1/3)

Witness Call (`NPC_REACTIONS.md` §4) stopped being instant and fully attributed the
moment a witness rolls it. `idle_npc_controller.gd` gained a new `ReactionState.CALLING`:
a witness that decides to call resolves an observation quality — a distance ceiling
(`attribution.md` §2's table, thresholds `@export`) that a binary attention modifier
(facing away from the incident, the only trigger this build can currently derive) can
only ever lower by one step, never raise — into a new `WitnessReport`
(`npc/controllers/witness_report.gd`), then holds it `PENDING` for
`call_report_duration` seconds before actually reporting. Interrupting the witness
(any hit that knocks them down) cancels the report instead — nothing reaches
`IncidentRegistry`. `WitnessReport` has no field a suspect could ever go in
(`attribution.md` §1's "REPORT is not IDENTIFICATION"), is never saved (in-memory only,
`IncidentRegistry`'s save format is untouched), and its `observation_level` field is
written but read by nothing yet — a deferred output for attribution (§5, not
scheduled), not dead code.

No visual change yet — this is the logic half only. `attribution.md` §7's Votive
escalation (blue → red/off ×3 → solid red) and the chain wiring that actually drives it
are the next two commits.

*Свидетельский Call больше не мгновенный и не сразу атрибутированный. Новое
ReactionState.CALLING резолвит качество наблюдения (потолок по дистанции + внимание,
только "отвёрнут" реализовано) в WitnessReport и держит его PENDING
call_report_duration секунд перед фактическим отчётом; прерывание (нокдаун) отменяет
отчёт. Без визуала — это только логическая половина.*
- `npc/controllers/idle_npc_controller.gd`, `npc/controllers/witness_report.gd` (new),
  `CLAUDE.md`

---

## 2026-08-16 — `VotiveProjector`, the Votive's visible layer (attribution.md §7, part 2/3)

New shared component, `core/components/votive_projector/votive_projector.gd` — same
placement as `HealthComponent`, one instance each in `npc.tscn`/`player.tscn`. State
(`IDLE`/`TRANSMITTING`/`DARK`) plus a visual representation (a small `OmniLight3D`
built in code, positioned at temple height from the owner's own `get_eye_height()`)
and nothing else — no `communication_state`, no `current_call`, no identity binding,
per `docs/attribution.md` §6's "game code must not let these two touch". Driven every
physics frame by its owner (`NPCBase`/`player.gd`), same "dumb component" convention
`NPCAnimationComponent` already uses — never its own `_process()`.

Purely additive and inert this commit: every instance sits `IDLE` (steady blue) with
nothing yet calling `start_transmitting()`/`go_dark()`. The witness chain built last
commit and this visual layer get wired together next.

Also settled, in `attribution.md` §6 itself: Votive is not `EquipmentComponent`'s
business. It's worn always, by everyone, never removed in this iteration — it doesn't
belong to the "what's held, stowed, drawn" contract equipment will own once H5 exists.
Revisit that question once H5 lands, with a working chain already in place.

*Новый общий компонент VotiveProjector — состояние (IDLE/TRANSMITTING/DARK) плюс
визуал, ничего больше. По одному экземпляру в npc.tscn/player.tscn, ведётся
физическим кадром владельца. Пока инертен — везде IDLE, никто не переключает
состояние. Зафиксировано: вотив не относится к EquipmentComponent.*
- `core/components/votive_projector/votive_projector.gd` (new), `npc/npc.tscn`,
  `npc/npc_base.gd`, `player/player.tscn`, `player/player.gd`, `CLAUDE.md`

---

## 2026-08-16 — Witness chain wired to VotiveProjector, debug panel (attribution.md §7, part 3/3)

Closes the vertical slice. `idle_npc_controller.gd`'s CALLING reaction now drives its
sibling `VotiveProjector`: `start_transmitting(call_report_duration)` on entry,
`go_idle()` on commit, `go_dark()`/`go_idle()` on the knocked-down guard as the witness
goes down and gets back up (any knocked-down NPC's terminal blacks out now, not only one
mid-report — a natural reading of "unconscious", not part of the chain itself).
`perception_debug_panel.gd` gained a WITNESS/REPORT block (distance, attention, ceiling,
resolved level, status, time remaining, plus a literal `actor UNRESOLVED` line) for
whichever NPC is currently CALLING — `attribution.md` §7's own required format, the
only place any of this is visible.

**Recursion, checked rather than assumed:** suppressing a witness is itself an incident
(the punch that knocks them down already reports through `player.gd`'s own
`punch_landed` → `IncidentRegistry.report()`, unconditional, existing since H1) —
nothing new was needed for that half. What this pass adds is that a report already
`PENDING` when the suppression lands gets `CANCELLED`, not silently orphaned. Two/three
iterations (witness A reports on the player hitting B; player hits A to suppress it;
that assault is itself witnessed by C, who may start a report about A's beating; hitting
C to suppress that repeats the pattern) terminate on their own — each step consumes one
witness (knocked down, `is_knocked_down()` already blocks `_on_incident_reported()` and
`_decide()` from reacting further) and the population is finite. No infinite loop, no
new guard needed; `IncidentRegistry`'s own `max_incidents`/`max_incident_age` bound the
worst case regardless.

**Boundaries respected, not crossed:** `PerceptionComponent` was only read from (facing/
position), never modified — attention's "facing away" trigger is computed directly
against `NPCBase.get_facing_direction()` and the incident's own position, not through
that component. `IncidentRegistry`'s save format is untouched — `WitnessReport` is
never persisted. No navigation was added or fixed — `_step_calling()` doesn't move the
NPC at all, same as `_step_freeze()`.

*Цепочка свидетеля теперь управляет VotiveProjector (transmit/idle/dark по состояниям),
добавлен блок WITNESS/REPORT в отладочной панели. Рекурсия (подавление свидетеля - само
инцидент) проверена, а не просто заявлена: конечна, т.к. каждый шаг расходует одного
свидетеля из конечной популяции; новых защит не потребовалось. Границы (PerceptionComponent,
формат сохранения реестра, навигация) не нарушены.*
- `npc/controllers/idle_npc_controller.gd`, `ui/debug/perception_debug_panel.gd`,
  `CLAUDE.md`

---

## Earlier entries

Everything dated before **2026-08-15** now lives in
[`CHANGELOG_2026-07..08.md`](CHANGELOG_2026-07..08.md) — the start of Vertical
Trespass through the pre-demo pass, including the four longest entries this log
has ever carried. Split out on 2026-09-03 (work plan Task 4): a 405 KB chronicle
is not read, and the entries that made it that size are the ones that should
have been post-mortems (`docs/postmortems/`).

> *Записи до 2026-08-15 переехали в `CHANGELOG_2026-07..08.md`.*

---

## Parallel tracks currently in flight

- **NPC perception & body language** — `npc/`, perception debug panel, head/body turning.
- **Player animation** — `PlayerAnimationComponent`, stance-branched AnimationTree, blending.

*Параллельные треки: NPC (восприятие, язык тела) и анимации игрока.*
