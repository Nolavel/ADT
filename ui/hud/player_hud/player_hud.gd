# =============================================================================
# player_hud.gd — PlayerHUD.
#
# Top-left status stack: health now, hunger and rest later. Instantiated from
# world.gd's WORLD_UI_SCENES list and handed the world context, same as
# aim_reticle — see world.gd's own comment on the three categories.
#
# WHY THIS SITS BETWEEN THE COMPONENT AND THE WIDGET: StatusBarWidget draws a
# ratio and knows nothing about health; HealthComponent tracks health and knows
# nothing about screens. This node is the only place the two meet, so adding
# hunger later means adding a widget and a subscription here — and touching
# neither of the other two files.
#
# NPCs deliberately have no equivalent: they carry the same HealthComponent
# with nothing subscribed to it.
#
# Dependencies: WorldContext (via on_world_ready).
# =============================================================================
class_name PlayerHUD
extends Control

## Distance from the top-left screen corner to the first bar.
@export var margin: Vector2 = Vector2(24.0, 24.0)
## Vertical gap between stacked gauges (health, then hunger, then rest).
@export var gauge_spacing: float = 6.0

@onready var _health_bar: StatusBarWidget = $StatusStack/HealthBar

var _health: HealthComponent = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = margin

	var stack := $StatusStack as VBoxContainer
	if stack != null:
		stack.add_theme_constant_override("separation", int(gauge_spacing))


## Resolves the player's HealthComponent and binds it to the bar. Called by
## world.gd once the context is populated — but for a WORLD_UI_SCENES entry
## world.gd adds this node via call_deferred(), so on_world_ready() can run
## BEFORE this node's own _ready(), while _health_bar is still null. Wait for
## ready first when that happens; already-ready is the common case for every
## other on_world_ready() caller (systems, 3D entities), so this is a no-op
## there.
func on_world_ready(context: WorldContext) -> void:
	if not is_node_ready():
		await ready

	if context.player == null:
		push_warning("[PlayerHUD] no player in context — status bars stay idle")
		return

	_health = context.player.get_node_or_null("HealthComponent") as HealthComponent
	if _health == null:
		push_warning("[PlayerHUD] player has no HealthComponent — status bars stay idle")
		return

	_health.health_changed.connect(_on_health_changed)
	_health.condition_changed.connect(_on_condition_changed)

	# Initial paint: the component reached full health in its own _ready(),
	# before this subscription existed, so the first signal would otherwise
	# only arrive on the first point of damage.
	_on_health_changed(_health.current_health, _health.max_health)
	_on_condition_changed(_health.conditions)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.set_ratio(current / maximum)


func _on_condition_changed(_conditions: int) -> void:
	_health_bar.set_labels(_health.get_condition_names())
