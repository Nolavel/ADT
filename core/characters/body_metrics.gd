# =============================================================================
# body_metrics.gd
# Static math helper, not a system — never instantiated, never autoloaded.
# Same pattern as core/math/smoothing.gd: reachable anywhere via class_name,
# no project.godot autoload entry.
#
# The ratios below are anatomy, shared by every character in the game.
# BODY_HEIGHT itself stays per-character data (player/player.gd, npc/npc_base.gd,
# ...) — copying these ratios into each character's own script is how they'd
# quietly drift apart; this file is the single place that defines them.
# =============================================================================
extends RefCounted
class_name BodyMetrics

## Anatomical landmark heights as fractions of a character's total height,
## measured from the feet. Shared by every character in the game: the ratios
## are anatomy, the height itself is per-character data.
const EYE_RATIO: float = 0.94
const SHOULDER_RATIO: float = 0.82
const CHEST_RATIO: float = 0.72


static func eye_height(body_height: float) -> float:
	return body_height * EYE_RATIO


static func shoulder_height(body_height: float) -> float:
	return body_height * SHOULDER_RATIO


static func chest_height(body_height: float) -> float:
	return body_height * CHEST_RATIO
