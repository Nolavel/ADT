# =============================================================================
# KeyHintEntry.gd
# Resource — one row of the key-hints HUD panel (key_hints_panel.gd,
# docs/scope_horizon.md H2). Describes one InputMap action — or a small
# group of them that share one meaning (WASD → "Move") — and under which
# PlayerState combination the row is currently relevant.
#
# The key LABEL is never authored here — KeyHintsPanel resolves it live from
# InputMap by action name, so a rebind in Project Settings never lets the
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

## Section order follows THIS ENUM'S declaration order. Camera/view actions
## live in ACTION; system and debug controls are deliberately not advertised.
enum Category { MOVEMENT, ACTION }

## Action name as registered in InputMap (Project Settings → Input Map).
## Used when this entry describes a SINGLE action. Ignored (action_names
## wins) once action_names is non-empty — leave this at its default for a
## grouped entry, do not set both.
@export var action_name: StringName = &""
## Action names for a GROUPED entry, e.g. move_forward/backward/left/right
## for one "Move" row: their key labels are joined into a single cell
## (KeyHintsPanel.group_key_separator) sharing this entry's one
## description. Empty for an ordinary single-action entry — see
## get_action_names().
@export var action_names: Array[StringName] = []
## Short description shown next to the resolved key label(s).
@export var description: String = ""
## ACTION, not MOVEMENT's or Category's own first member: chosen so every
## entry authored before this field existed — none of which set it — lands
## somewhere plausible rather than in a column its content doesn't suggest.
## Section order is MOVEMENT/ACTION (Category's declaration order); this
## default is a separate choice from that order.
@export var category: Category = Category.ACTION

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
## The condition fields apply to the entry as a whole — a grouped entry has
## exactly one set of them, same as a single-action one.
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


## The action name(s) this entry resolves key labels for: action_names if
## the entry is a group, else the single action_name.
func get_action_names() -> Array[StringName]:
	if not action_names.is_empty():
		return action_names
	return [action_name]


## Stable identity for this entry's on-screen row, used by KeyHintsPanel to
## track it across a diffed rebuild. For an ordinary single-action entry
## this is just action_name, unchanged from before grouping existed.
func get_row_key() -> StringName:
	var names := get_action_names()
	var joined := String(names[0])
	for i in range(1, names.size()):
		joined += "|" + String(names[i])
	return StringName(joined)
