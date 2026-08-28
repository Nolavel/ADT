# Item Fitter — fitting a held item to the hand

`addons/item_fitter/`. An editor dock for placing an item in the character's
hand and writing the result into the item's own `.tres`.

> Инструмент для подгонки предмета в руке персонажа. Всё, что он пишет —
> `HeldFit` в ресурсе предмета.

---

## What problem it solves

A held item's mesh is built at **runtime** by `EquipmentVisualsComponent`, so
opening `player.tscn` in the editor shows an empty hand. Before this dock,
tuning the offset meant editing three numbers in a `.tres`, launching the
game, drawing the weapon, squinting, and starting again — which is how the
carbine shipped wearing the pistol's offsets for a whole build.

## Before you start

The plugin is already enabled (`project.godot` → `[editor_plugins]`). Nothing
to install.

It needs a scene open that actually contains a hand. Concretely, the edited
scene's tree must contain a node path ending in:

- `RightHandAttachment/GripPivot`, or
- `LeftHandAttachment/GripPivot`

In this project that means **`player/player.tscn`**. Open it before using the
dock, or the item will have nowhere to go and the status line will say so.

## Step by step

1. **Open `player/player.tscn`** (any scene with the grip pivots above).
2. Find the **Item Fitter** dock — bottom-right dock area, next to the
   Inspector.
3. **Item**: pick the `ItemResource` you are fitting, e.g.
   `data/items/carbine.tres`. The dock reads `item.held_mesh` and spawns a
   preview under the grip pivot. It knows no item by name — a new weapon,
   tool or torch works with nothing changed in the addon.
4. **Hand**: right or left. The preview moves to that grip pivot.
5. **Animation** *(optional but this is the point)*: pick a clip and drag the
   **time slider**. The skeleton poses to that moment, and the preview rides
   the bone. Fit against the pose the item is actually seen in — an idle-only
   fit looks wrong the moment the character aims.
6. **Move it.** The preview is an ordinary node in the viewport: use the
   normal translate / rotate / scale gizmo until it sits in the hand.
7. **Save.** Writes the preview's local transform into the item's `HeldFit`
   and saves the `.tres` to disk. **Revert** puts the preview back to what
   the resource currently says.

## What it writes, and what it does not

- Writes **`HeldFit` on the `ItemResource`**, and nothing else.
- The preview is spawned with `owner = null`, so it **cannot** be serialised
  into `player.tscn` — moving it around never dirties the character scene.
  If you close the dock or disable the plugin, the preview is removed.
- Saving needs the item to already exist as a file on disk. A resource
  created in memory has no path; the status line says so instead of failing
  silently.

## Gotchas

- **Nothing appears after picking an item** — the open scene has no
  `…HandAttachment/GripPivot`, or the item has no `held_mesh`. The status
  line distinguishes the two.
- **The item is the wrong size.** Scale belongs to the grip pivot, not to the
  fit: `player.tscn`'s `GripPivot` nodes carry a reciprocal scale that undoes
  `player_base_mesh`'s own 0.38, and `EquipmentVisualsComponent` warns at
  runtime if that reciprocal has drifted. Do not compensate for a size
  problem inside `HeldFit` — fix the pivot.
- **Switching scenes** keeps the dock alive but drops the preview; pick the
  item again.

## Where a stowed item goes

Not implemented. The intended next use is a second `HeldFit`-shaped field on
the item plus one more picker in the dock — see `plugin.gd`'s header. It is
not started, so there is no placeholder for it.

## Related

- `docs/architecture/items_and_equipment.md` — `ItemCatalog`,
  `EquipmentComponent`, equipment visuals, and where `HeldFit` is consumed.
- `CLAUDE.md` — why this is an `addons/` `EditorPlugin` and not a `tools/`
  script.
