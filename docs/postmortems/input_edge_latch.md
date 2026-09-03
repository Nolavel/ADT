# Polling an edge from the physics frame, and the latch that replaced it

**Invariant this belongs to:** `CLAUDE.md`, Architecture rules — "Inside
`InputSystems`: edges come from events, levels come from polls."

## Why polling an edge is wrong

`Input.is_action_just_pressed()` answers about the frame it is asked in. Called
from `_physics_process()`, it silently drops presses as soon as the idle and
physics rates diverge.

Measured 2026-09-02, 120 taps:

| Path | Physics rate | Arrived |
|---|---|---|
| poll from `_physics_process` | 5 Hz | **42** |
| event (`_unhandled_input`) | every rate tested | **120** |

## The first fix was wrong, and wrong the same way I usually am

The replacement latch stored `Engine.get_physics_frames()` at the moment of the
event and expired the entry by comparing against it. That is arithmetic which
only works if the engine's flush order is what I assumed it was — and I reasoned
about that order instead of measuring it.

Measured: **six taps produced six latches and zero reads.** Every polled edge in
the project — V, jump, stance, lock-on, shoulder — was dead, and the toggle Stan
reported as broken was only the one he happened to press.

## The shape that works carries no arithmetic

An event files the action. The top of the next physics frame promotes it to
readable. The frame after that drops it. Two phases, a boolean, no frame
numbers:

```gdscript
func _latch_edge(action: StringName) -> void:
    _edge_frames[action] = false

func _expire_edges() -> void:
    for action in _edge_frames.keys():
        if bool(_edge_frames[action]):
            _edge_frames.erase(action)
        else:
            _edge_frames[action] = true
```
