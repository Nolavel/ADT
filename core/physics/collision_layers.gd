# =============================================================================
# collision_layers.gd
# Static physics-layer helper, not a system — never instantiated, never
# autoloaded. Same pattern as core/math/smoothing.gd and
# core/characters/body_metrics.gd: reachable anywhere via the class_name
# below, including from outside WorldContext (map_source, map_cursor,
# dynamic_cursor_ui — a service only some consumers could reach wouldn't
# solve the drift this file exists to fix).
#
# Two kinds of constant here. Raw layer bits mirror project.godot's
# [layer_names] one-to-one — a new layer is named there, given a constant
# here, and given a row in docs/COLLISION_LAYERS.md, all in the same commit,
# never one without the other two (see that file's own "Rule" section).
# Query profiles compose those bits into what a specific raycast/shapecast
# is actually asking about; docs/COLLISION_LAYERS.md explains the reasoning
# behind each one, this file only holds the values.
#
# Deliberately not RaycastService — six one-line queries don't justify a
# facade over them yet. See docs/planned_scope.md, "Not started, not
# stubbed", for when that stops being true.
# =============================================================================
extends RefCounted
class_name CollisionLayers

## Raw layer bits — mirrors project.godot [layer_names] exactly. Named so no
## query site re-derives a bit shift (1 << N) by hand.
const CHARACTERS: int = 1 << 0
const FLOOR: int = 1 << 1
const WALL: int = 1 << 2
const PHYSICS_OBJECTS: int = 1 << 3
const DRONES: int = 1 << 8
const INTERACTABLES: int = 1 << 9
const TRANSPORT_TRIGGERS: int = 1 << 10
const GUI_3D: int = 1 << 19

## What blocks one character's view of another. Walls only: a floor between
## two actors means they are on different decks, and the geometry of the
## city already makes that unreachable — including the floor here made the
## perception ray fail on slopes and stairs for no gain.
const SIGHT: int = WALL

## What the camera must not pass through. Floor as well as walls, unlike
## SIGHT: the camera is not an eye at head height, it swings low behind the
## character and would sink through the deck without this.
const CAMERA_OCCLUSION: int = FLOOR | WALL

## What a straight-ahead wander/flee/respond bump check treats as blocking.
## Wall only — floor is what an NPC walks on, not an obstacle to walking.
const OBSTACLE: int = WALL

## What a dropped/thrown interactable's "which way is down" raycast should
## hit — the floor it's meant to land on, not a nearby wall.
const GROUND: int = FLOOR

## What an interactable RigidBody physically rests against and bumps into:
## the floor it lands on, plus other physics objects. Not a raycast query —
## this is the body's own collision_mask — grouped here anyway since it was
## one more bare literal. Wall is deliberately absent; see
## docs/COLLISION_LAYERS.md's open-questions section for why that gap is
## left as found, not fixed, here.
const INTERACTION: int = FLOOR | PHYSICS_OBJECTS

## What the screen-space cursor's 3D-UI hover raycast should hit: the
## dedicated 3D-UI layer, nothing else.
const CURSOR_UI: int = GUI_3D
