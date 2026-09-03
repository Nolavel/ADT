# "Has it ended" asked before "has it started"

**Invariant this belongs to:** `CLAUDE.md`, Architecture rules — "A gesture's
state machine may not ask 'has it ended' before 'has it started'."

`AnimationTree` updates on the **idle** frame. `player.gd`'s punch, shot and
reload machines run in `_physics_process`. So for at least one physics frame
after a gesture is requested, "the one-shot is not active" and "it has not
started yet" are the same reading — and a machine testing for the end sees the
end immediately.

A one-frame grace is not enough at the project's own 55 FPS against 60 Hz
physics, and never enough under the render probe, which runs at single-digit
frame rates on software OpenGL. That low frame rate turned out to be the useful
part of the probe: it is a free stress test for exactly this class of race.

The shape that works latches first and only then tests for the end, with
`GESTURE_START_GRACE` as the backstop for a gesture that never starts at all:

```gdscript
if not _reload_gesture_seen:
    if _animation_component.is_weapon_gesture_active():
        _reload_gesture_seen = true
    elif _reload_timer < maxf(GESTURE_START_GRACE, reload_time):
        return
    else:
        _is_reloading = false
        set_movement_enabled(true)
        return
```

There are three such flags today. A fourth gesture needs a fourth — without it
the gesture ends on its second physics frame and whatever it was going to do
never happens.
