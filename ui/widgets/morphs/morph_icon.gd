# =============================================================================
# morph_icon.gd
# ## ENG: The contract every morph icon answers to, and the only type a
#         controller ever names. A morph is a small spring-driven glyph
#         parented under a Button, saying what the widget is doing right now:
#         at rest, hovered, or held.
#
#         Same shape as ActorBase (core/characters/actor_base.gd) — a base
#         class whose methods are stubs meant to be overridden, existing so
#         the layer above can type-check against something real without
#         knowing which concrete implementation it got. DragHandleController
#         and RevolverHammerController hold a MorphIcon, never a
#         ThreeDotsMorph, so a second morph is a new script here and nothing
#         else: no controller changes, which is the whole point of this file.
#
#         A morph never reads input. It is told what mode to be in, by
#         whoever owns the gesture. The one exception a concrete morph may
#         offer is an opt-in hover behaviour, and that must default OFF so it
#         cannot fight a controller for the same glyph.
#
#         Mode is deliberately not per-morph: the vocabulary is shared so a
#         controller's to_circle() means the same thing whatever is drawing.
# =============================================================================
class_name MorphIcon
extends Control

## The shared vocabulary. LINE is rest, WAVE is noticed-but-untouched,
## CIRCLE is held. A morph that cannot express one of them should still
## accept it and pick its nearest reading rather than refuse.
enum Mode { LINE, WAVE, CIRCLE }

## Current mode. Written through set_mode(), which subclasses override to
## react — never assigned directly from outside.
var mode: Mode = Mode.LINE


## The one method a concrete morph must override. The base does the
## bookkeeping only; everything visual belongs to the subclass.
func set_mode(new_mode: Mode) -> void:
	mode = new_mode


## The three named shortcuts controllers actually call. Deliberately not
## virtual: they route through set_mode() so a subclass overrides one method
## rather than four, and a controller cannot reach a mode set_mode() has not
## seen.
func to_line() -> void:
	set_mode(Mode.LINE)


func to_wave() -> void:
	set_mode(Mode.WAVE)


func to_circle() -> void:
	set_mode(Mode.CIRCLE)


func get_mode() -> Mode:
	return mode


## Finds the morph a host Button carries, if it carries one. Direct children
## only — a morph is drawn on the button, not somewhere in its subtree.
##
## Null is a valid, silent outcome and every caller treats it as one: a morph
## is decoration over a gesture that has to keep working without it, so a
## missing one is never a warning. Lives here rather than being copied into
## each controller's own _find_morph().
static func find_in(host: Node) -> MorphIcon:
	if host == null:
		return null
	for child in host.get_children():
		if child is MorphIcon:
			return child as MorphIcon
	return null
