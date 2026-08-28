# =============================================================================
# comic_effect_def.gd — one emotion / event definition for ComicEffectSystem.
#
# Pure data. texts[] is the random pool; the system picks one on spawn and
# avoids immediate repeats of the same string for the same id. radius is the
# comic "hearing" distance — beyond it the effect is never spawned, even if
# the source is on-screen. That gate is deliberate: a reaction fifty metres
# away must not litter the screen.
#
# WHAT SAYS IT vs WHAT IT LOOKS LIKE. This resource owns the words and the
# gate. How the panel is drawn belongs to ComicVisualProfile, shared by a
# whole class of events, so retuning the look of "every NPC reaction" is one
# edit rather than eight. A def without a profile still works — see
# resolve_profile().
#
# Not audio. A future AudioSystem may share the same event ids, but this
# resource does not know about sound and must not grow a sound field.
# =============================================================================
class_name ComicEffectDef
extends Resource

@export var id: StringName = &""
## Random pool. Empty def is skipped at spawn time.
@export var texts: PackedStringArray = []
## Optional weights, same length as texts. Empty = uniform pick.
@export var weights: PackedFloat32Array = []
## Metres from the player beyond which try_spawn is a no-op.
@export var radius: float = 22.0

@export_group("Look")
## The visual register this event is drawn in. Null is legal and supported —
## see resolve_profile().
@export var visual_profile: ComicVisualProfile = null
## Per-event weight within its profile: scales the font size only. A def that
## needs to shout uses 1.15, one that mutters uses 0.85. It does NOT change
## colour or timing — those stay the property of the register, which is what
## keeps four profiles reading as four voices instead of thirteen.
@export var emphasis: float = 1.0

@export_group("Legacy")
## The pre-profile fields. Kept working, not kept forever: a def with no
## visual_profile is drawn from these via a profile synthesised on first use.
## Migration is therefore per-def and optional, and no event silently stops
## rendering halfway through it.
@export var color: Color = Color(0.92, 0.90, 0.82, 1.0)
@export var font_size: int = 26
@export var duration: float = 0.9
## Screen-space rise in pixels over the lifetime.
@export var rise_px: float = 32.0

## Built once from the legacy fields, on the first resolve_profile() that
## needs it. Editing a legacy field at runtime after that will not be picked
## up — the inspector path is the profile, and this is the compatibility
## shim, not a second way to author a look.
var _legacy_profile: ComicVisualProfile = null


## Always returns a usable profile. This is the whole of the migration
## strategy: the system never has to ask whether a def has been migrated, and
## a def that has not been is drawn as a plain light panel rather than not at
## all.
func resolve_profile() -> ComicVisualProfile:
	if visual_profile != null:
		return visual_profile
	if _legacy_profile == null:
		_legacy_profile = _synthesise_legacy_profile()
	return _legacy_profile


## Single place the drawn size is decided. ComicEffectLabel must not
## recompute it — two sources for one number is how the panel and the text
## end up disagreeing about how big the panel should be.
func get_font_size() -> int:
	return maxi(1, roundi(resolve_profile().font_size * maxf(emphasis, 0.01)))


func _synthesise_legacy_profile() -> ComicVisualProfile:
	var p := ComicVisualProfile.new()
	p.id = id
	p.primary_color = color
	p.border_color = color
	p.font_size = font_size
	p.duration = duration
	p.rise_px = rise_px
	# Deliberately understated: a def that has not been given a register yet
	# should look plain, not invent one. No jitter, thin border, no grid.
	p.border_style = ComicVisualProfile.BorderStyle.RECT
	p.border_thickness = 1.5
	p.corner_jitter = 0.0
	p.pattern_color = Color(0.0, 0.0, 0.0, 0.0)
	return p
