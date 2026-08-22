# =============================================================================
# comic_effect_def.gd — one emotion / event definition for ComicEffectSystem.
#
# Pure data. texts[] is the random pool; the system picks one on spawn and
# avoids immediate repeats of the same string for the same id. radius is the
# comic "hearing" distance — beyond it the effect is never spawned, even if
# the source is on-screen. That gate is deliberate: a reaction fifty metres
# away must not litter the screen.
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
@export var color: Color = Color(0.92, 0.90, 0.82, 1.0)
@export var font_size: int = 26
@export var duration: float = 0.9
## Screen-space rise in pixels over the lifetime.
@export var rise_px: float = 32.0
## Metres from the player beyond which try_spawn is a no-op.
@export var radius: float = 22.0
