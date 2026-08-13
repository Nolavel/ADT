# =============================================================================
# KeyHintEntry.gd
# Resource — one row of the key-hints HUD panel (key_hints_panel.gd,
# docs/scope_horizon.md H2). Describes ONE InputMap action: what it does, and
# under which PlayerState combination it is currently relevant.
#
# The key LABEL is never authored here — KeyHintsPanel resolves it live from
# InputMap by action_name, so a rebind in Project Settings never lets the
# panel lie about which key does what.
#
# CONDITION FIELDS: an empty array means "any" on that axis — an entry that
# is valid in every PlayerState.Mode should not force its author to list all
# four. modes/view_modes/stances are typed Array[int] rather than, say,
# Array[PlayerState.Mode]: the values ARE PlayerState.Mode/ViewMode/Stance
# members, but keeping the export itself int-typed avoids this resource's
# on-disk .tres format depending on how Godot happens to serialize a typed
# array of an autoload's nested enum — untested territory with no existing
# precedent in this project. See KeyHintsPanel's report note for the same
# reasoning applied to reading InputMap events.
# =============================================================================
extends Resource
class_name KeyHintEntry

## Whether an entry additionally requires (or forbids) PlayerState.is_aiming.
## A plain bool on the entry itself could not express "don't care".
enum AimRequirement { ANY, AIMING_ONLY, NOT_AIMING }

## Action name as registered in InputMap (Project Settings → Input Map).
@export var action_name: StringName = &""
## Short description shown next to the resolved key label.
@export var description: String = ""

@export_group("Visible when")
## Values are PlayerState.Mode members. Empty = any mode.
@export var modes: Array[int] = []
## Values are PlayerState.ViewMode members. Empty = any view mode.
@export var view_modes: Array[int] = []
## Values are PlayerState.Stance members. Empty = any stance.
@export var stances: Array[int] = []
@export var aiming_requirement: AimRequirement = AimRequirement.ANY

@export_group("Ordering")
## Lower sorts further left. Ties are broken by catalog array order.
@export var sort_order: int = 0


## True if this row belongs on screen for the given PlayerState snapshot.
func matches(mode: PlayerState.Mode, view_mode: PlayerState.ViewMode,
		stance: PlayerState.Stance, is_aiming: bool) -> bool:
	if not modes.is_empty() and not modes.has(mode):
		return false
	if not view_modes.is_empty() and not view_modes.has(view_mode):
		return false
	if not stances.is_empty() and not stances.has(stance):
		return false
	if aiming_requirement == AimRequirement.AIMING_ONLY and not is_aiming:
		return false
	if aiming_requirement == AimRequirement.NOT_AIMING and is_aiming:
		return false
	return true
