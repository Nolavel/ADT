# =============================================================================
# player_hud.gd — PlayerHUD.
#
# Top-left status stack: stamina, health and the magazine now, hunger and rest
# later. Instantiated from world.gd's WORLD_UI_SCENES list and handed the world
# context, same as aim_reticle — see world.gd's own comment on the three
# categories.
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

@onready var _stamina_gauge: StaminaGauge = $StatusStack/HealthRow/StaminaGauge
@onready var _health_bar: StatusBarWidget = $StatusStack/HealthRow/HealthBar
@onready var _ammo: AmmoIndicator = $StatusStack/AmmoIndicator

var _health: HealthComponent = null
var _weapon: WeaponComponent = null
var _equipment: EquipmentComponent = null


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

	_bind_ammo(context)
	## Stamina sits FIRST in the row, left of health: it is the gauge that
	## moves constantly, and reading it should not mean scanning past a bar
	## that only changes when something hits you. It used to be a ring on the
	## ground under the player — see stamina_gauge.gd's header for why it is
	## not there any more.
	_stamina_gauge.bind(context.player)


## The ammo row needs BOTH components, and they answer different halves of
## the question: EquipmentComponent says which weapon is in the hands (and so
## whether to show the row at all), WeaponComponent says how many rounds are
## in it. Neither is an autoload, which is why this is wired here rather than
## read directly the way StanceIndicator reads PlayerState.
##
## Missing either one is not an error worth a warning on every start: a
## character without a weapon component simply never shows an ammo row, the
## same way NPCs carry a HealthComponent with nothing subscribed to it.
func _bind_ammo(context: WorldContext) -> void:
	_weapon = context.player.get_node_or_null("WeaponComponent") as WeaponComponent
	_equipment = context.player.get_node_or_null("EquipmentComponent") as EquipmentComponent
	if _weapon == null or _equipment == null:
		return

	_weapon.ammo_changed.connect(_on_ammo_changed)
	## The refusal comes from the player, not from WeaponComponent: the
	## component answers "would a reload do anything", the player is what
	## decides to ask and therefore what knows the answer was no.
	if context.player.has_signal(&"reload_refused"):
		context.player.reload_refused.connect(_on_reload_refused)
	## The other half of the same answer: a refusal says "nothing to do", this
	## says "under way". Without it the row is silent for the second the
	## gesture takes before the rounds land — see AmmoIndicator.begin_reload().
	if context.player.has_signal(&"reload_started"):
		context.player.reload_started.connect(_on_reload_started)
	_equipment.drawn_changed.connect(_on_drawn_changed)

	# Same initial-paint reasoning as health above — and it is not always a
	# no-op: a loaded save restores the drawn item before this subscription
	# exists.
	_on_drawn_changed(_equipment.get_drawn())


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.set_ratio(current / maximum)


func _on_condition_changed(_conditions: int) -> void:
	_health_bar.set_labels(_health.get_condition_names())


## What is in the hands decides whether the row is on screen at all. Empty
## hands, a torch, or anything that does not feed from a magazine clears it
## rather than leaving the last weapon's count sitting there.
func _on_drawn_changed(item_id: StringName) -> void:
	var capacity := _weapon.get_capacity(item_id)
	if capacity <= 0:
		_ammo.clear()
		return
	_ammo.set_ammo(
		_weapon.get_rounds(item_id), capacity, _weapon.get_reserve(item_id)
	)


## Only the weapon actually in the hands is drawn. WeaponComponent tracks a
## magazine per weapon id and will happily report on one that is stowed —
## which is the right thing for it to do and the wrong thing to show.
## Nothing to load. Flash the row that shows why.
func _on_reload_refused(_item_id: StringName) -> void:
	if _ammo != null and _ammo.visible:
		_ammo.flash_refusal()


## A reload started, and will fill in fill_time seconds.
func _on_reload_started(item_id: StringName, fill_time: float) -> void:
	if _ammo == null or not _ammo.visible:
		return
	## Only the weapon actually in the hands, same rule as _on_ammo_changed().
	if _equipment == null or _equipment.get_drawn() != item_id:
		return
	_ammo.begin_reload(fill_time)


func _on_ammo_changed(item_id: StringName, rounds: int, capacity: int, reserve: int) -> void:
	if _equipment.get_drawn() != item_id:
		return
	_ammo.set_ammo(rounds, capacity, reserve)
