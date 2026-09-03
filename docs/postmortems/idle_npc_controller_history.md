# IdleNPCController: what was tried first

**Invariant this belongs to:** the header of
`npc/controllers/idle_npc_controller.gd`.

## The obstacle ray was parented with a plain `add_child()`, and then not at all

`_obstacle_ray` is built in code and parented to `_npc` with
`call_deferred("add_child", ...)`, never a direct call. `IdleNPCController` is a
child of `NPCBase` in `npc.tscn`, so this controller's `_ready()` runs while the
NPC subtree is still entering the tree — `NPCBase` is "busy setting up children"
at that moment and a direct `add_child()` onto it fails outright:

```
Parent node is busy setting up children, add_child() failed
```

Same ordering problem `world.gd`'s `WORLD_UI_SCENES` loop, `menu_system.gd` and
`zoom_ruler_system.gd` already work around the same way. Deferring lands it
after the frame's whole ready propagation has settled, which holds whether the
NPC is a static instance in `world.tscn` or streamed in at runtime.

**And a prior pass had the deferred call written but commented out.** That left
`is_colliding()` permanently false, so wander's obstacle avoidance — and
Flee/Respond's, which reuse the same check — was inert: NPCs walked into walls.
Confirm any change here by running the game and watching an NPC retarget off a
wall.

## "Facing away" stood in for attention, and was wrong in kind

`docs/attribution.md` §2's REDUCED attention modifier is not applied. An earlier
pass used "facing away" as a stand-in for it. That is not a tuning error but a
category one: facing away means **not seeing the incident at all**, which is
already what `_evaluate_incident_vision()` decides. Attention's two real
triggers — talking, and looking into one's own Votive — have no mechanic yet.

## The two-phase flee was direction- and duration-wrong

An earlier pass gated `BACKING_AWAY` on distance to the player and on the player
still approaching, and recomputed `RUNNING`'s direction every frame. The result
chased and oscillated. Now: `BACKING_AWAY` is a **fixed** `backpedal_duration`,
ended early only by losing the player node or backing into geometry;
`_flee_direction` is fixed **exactly once**, when `_enter_flee_phase()` turns
into `RUNNING`, away from `_flee_threat_position` and never recomputed.
`RUNNING` became distance-gated (`flee_far_distance`) rather than
duration-gated, with `flee_duration` demoted to a per-phase safety cap in case
geometry traps an NPC short of that distance.

## Reactions are probabilistic on purpose

`NPC_REACTIONS.md` §4 says the crowd reacts **by chance**. A fixed "this
archetype always flees" would turn the crowd into a lookup table — exactly what
§2's "street literacy, learned by observation" argues against. The bias lives on
`NPCArchetypeData.flee_probability`, so retuning it never means touching the
controller.

## Why there is no catch-up replay here

`PatrolDroneController._check_existing_incidents()` has no equivalent in this
file, deliberately. A durable ALERT means "the city still suspects something"; a
crowd flinch is a momentary startle. An NPC freezing over a punch thrown minutes
ago, somewhere it has since wandered away from, reads as a bug rather than as
memory.
