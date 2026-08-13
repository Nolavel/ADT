# =============================================================================
# KeyHintsCatalog.gd
# Resource — the full list of KeyHintEntry rows shown by KeyHintsPanel. One
# catalog, res://data/key_hints.tres by convention. Data-driven so the set of
# valid actions per mode/view/stance/aiming can keep changing without
# touching code — see docs/scope_horizon.md H2.
# =============================================================================
extends Resource
class_name KeyHintsCatalog

@export var entries: Array[KeyHintEntry] = []


## Entries relevant to the given PlayerState snapshot, sorted by sort_order.
func get_active_entries(mode: PlayerState.Mode, view_mode: PlayerState.ViewMode,
		stance: PlayerState.Stance, is_aiming: bool) -> Array[KeyHintEntry]:
	var active: Array[KeyHintEntry] = []
	for entry in entries:
		if entry.matches(mode, view_mode, stance, is_aiming):
			active.append(entry)
	active.sort_custom(func(a: KeyHintEntry, b: KeyHintEntry) -> bool:
		return a.sort_order < b.sort_order)
	return active
