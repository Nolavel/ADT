# =============================================================================
# comic_visual_profile.gd — the look of one CLASS of comic events.
#
# One profile is referenced by many ComicEffectDef. Retuning a profile
# retunes a whole class of events at once — every NPC reaction, or every
# hurt — which is the point: the comic layer is a language, and a language
# has a handful of registers, not one per word.
#
# WHAT LIVES HERE AND WHAT DOES NOT. The profile owns how a panel is DRAWN.
# It does not own what is said (ComicEffectDef.texts), when it is allowed to
# appear (ComicEffectDef.radius, ComicEffectSystem.MAX_ACTIVE) or whether it
# is heard (nothing — see docs/visual_language.md §5, sound is a separate
# layer and this resource must never grow a sound field).
#
# NO TAIL, DELIBERATELY. An early draft of this had a pointer tail toward the
# source, which turns the panel into a speech bubble — the character's voice
# rather than the panel's. §2 of the visual language is explicit that a comic
# word is "the voice of the panel, not the voice of the author". The link to
# the source is already made by projection: the panel sits on it and rises
# from it. If a tail ever appears here, that rule went with it.
#
# Colour lives in the BORDER and the text outline, not in a filled slab. A
# large coloured rectangle reads as a UI tooltip, which is the one thing this
# device must not look like.
# =============================================================================
class_name ComicVisualProfile
extends Resource

## Shape of the panel outline. Four registers, matched to what the event is,
## not to who sent it — a hurt reads differently from a machine noise even
## when both come from the player.
enum BorderStyle {
	## Hard rectangular plate. The default comic panel.
	RECT,
	## Same rectangle, corners eased. Softer, for a reaction rather than an
	## impact.
	SOFT,
	## Skewed and broken. For damage.
	AGGRESSIVE,
	## Thin, exact, no jitter. For the world and its machines.
	TECHNICAL,
}

@export var id: StringName = &""

@export_group("Colour")
## The word itself.
@export var primary_color: Color = Color(0.92, 0.90, 0.82, 1.0)
@export var border_color: Color = Color(0.92, 0.90, 0.82, 1.0)
## Near-black on purpose — see the header on why this is not a coloured slab.
@export var background_color: Color = Color(0.05, 0.05, 0.06, 0.88)
## The print grid inside the panel. Its alpha is the ONLY place the grid's
## strength is set; there is no second opacity multiplier to fight with.
@export var pattern_color: Color = Color(0.55, 0.55, 0.62, 0.07)

@export_group("Type")
@export var font_size: int = 26
@export var outline_size: int = 5
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.9)

@export_group("Panel")
@export var border_style: BorderStyle = BorderStyle.RECT
@export var border_thickness: float = 2.5
@export var padding: Vector2 = Vector2(14.0, 7.0)
## How far the corners wander from true, in pixels. Zero is a clean
## rectangle. Sampled once per spawn, never per redraw — see
## ComicEffectLabel._jitter_offsets.
@export var corner_jitter: float = 2.0
## Spacing of the print grid, pixels. Larger = sparser.
@export var pattern_step: float = 5.0

@export_group("Timing")
## Total life of the panel. The old flat 0.9 s was too short to read a word
## and register the shape around it.
@export var duration: float = 1.4
## Length of the pop-in, seconds. Short — it is an arrival, not an entrance.
@export var pop_time: float = 0.09
## Fraction of the whole life spent held at full alpha before the fade.
@export var hold_ratio: float = 0.5
## Screen-space rise over the life, pixels.
@export var rise_px: float = 30.0
## How far the pop overshoots in scale. 1.0 = no overshoot.
@export var pop_overshoot: float = 1.10
