# =============================================================================
# health_component.gd — HealthComponent
#
# Shared health for the player and for NPCs. Pure logic: no UI, no input, no
# animation. Owners subscribe to the signals and decide what a hit or a death
# looks like on their side (the player plays a death clip, NPCBase locks its
# knockdown state machine in a terminal phase).
#
# ATTACHING: a child Node of the actor (player.tscn, npc.tscn). max_health and
# enable_conditions are set per scene, so the component itself never needs to
# know who owns it.
#
# CONDITIONS (bleeding / fracture) are a PLAYER feature: while at least one is
# active AND health is below the CRITICAL band, health ticks down on its own.
# NPCs run with enable_conditions = false — plain hit points, no ticking, no
# clock dependency. That is why setup() is optional.
#
# TIME: the drain is driven by GameClockSystem.minute_passed, never by _process.
# One game minute is ~2 real seconds (48 real minutes per game day), which is
# smooth enough to read on a bar and costs nothing per frame. Menu pause is
# already covered — the clock pauses with the tree. SLEEP IS NOT: a sleep that
# skips time via GameClockSystem.time_scale would fire minute_passed hundreds of
# times in a row and kill the player in the dark. Sleep MUST call
# suspend_conditions() before skipping and resume_conditions() after.
# =============================================================================
class_name HealthComponent
extends Node

## Coarse state of the bar, three equal thirds. Consumers use this instead of
## comparing raw numbers, so the thresholds live in exactly one place.
enum Band { NOMINAL, IMPAIRED, CRITICAL }

## Active injuries, as bit flags — an actor can bleed and have a fracture at
## the same time, and each carries its own drain rate.
enum Condition {
	NONE     = 0,
	BLEEDING = 1 << 0,
	FRACTURE = 1 << 1,
}

## Current health changed for any reason (damage, healing, condition drain).
signal health_changed(current: float, maximum: float)
## The third of the bar changed. Drives bar colour and the stamina ceiling.
signal band_changed(band: Band)
## The set of active injuries changed. Payload is the raw Condition mask.
signal condition_changed(conditions: int)
## Health reached zero. Fired exactly once until revive()/reset() is called.
signal died()

# ── Configuration ────────────────────────────────────────────────────────────

@export var max_health: float = 100.0

## Off for NPCs: they take damage and die, but never bleed or tick.
@export var enable_conditions: bool = false

## Health per GAME hour drained while an injury is active and the band is
## CRITICAL. Two thirds of the bar are a grace zone — a wound only starts
## costing life once the body is already failing.
@export var condition_drain_per_game_hour: float = 2.0

## Drain below TERMINAL_THRESHOLD. Three times faster, roughly three real
## minutes from 10 to zero: long enough to decide, too short to think it over.
@export var terminal_drain_per_game_hour: float = 6.0

## Below this health the accelerated drain takes over.
const TERMINAL_THRESHOLD: float = 10.0

## Band boundaries as a fraction of max_health. Thirds, by design.
const BAND_IMPAIRED_RATIO: float = 2.0 / 3.0
const BAND_CRITICAL_RATIO: float = 1.0 / 3.0

@export_group("Debug")
@export var debug_log: bool = false

# ── State ────────────────────────────────────────────────────────────────────

var current_health: float = 0.0
var conditions: int = Condition.NONE

var _band: Band = Band.NOMINAL
var _is_dead: bool = false
var _conditions_suspended: bool = false
var _clock: GameClockSystem = null

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	if max_health <= 0.0:
		push_warning("[Health] max_health must be positive — clamped to 1.0")
		max_health = 1.0
	current_health = max_health
	_band = _band_for(current_health)


## Called by the owner once the world context exists. Optional: without a clock
## the component still takes damage and dies, it just cannot drain over time.
## NPCs never call this.
func setup(clock: GameClockSystem) -> void:
	if not enable_conditions:
		return
	if clock == null:
		push_warning("[Health] enable_conditions is on but no GameClockSystem was passed — injuries will not drain")
		return
	_clock = clock
	_clock.minute_passed.connect(_on_game_minute_passed)

# ── Public API: damage and healing ───────────────────────────────────────────

## Applies damage. Returns the amount actually taken (0.0 when already dead).
func apply_damage(amount: float) -> float:
	if _is_dead or amount <= 0.0:
		return 0.0
	var taken: float = minf(amount, current_health)
	_set_health(current_health - taken)
	if debug_log:
		print("[Health] -%.1f -> %.1f/%.1f" % [taken, current_health, max_health])
	return taken


## Heals up to a ceiling. Sleep passes a ceiling below max_health when the
## injury was recent or only partly treated — see the sleep contract.
func heal(amount: float, ceiling: float = -1.0) -> void:
	if _is_dead or amount <= 0.0:
		return
	var cap: float = max_health if ceiling < 0.0 else minf(ceiling, max_health)
	if current_health >= cap:
		return
	_set_health(minf(current_health + amount, cap))


## Full reset — new game, load, or respawn at the last sleep save.
func reset() -> void:
	_is_dead = false
	conditions = Condition.NONE
	condition_changed.emit(conditions)
	_set_health(max_health)

# ── Public API: conditions ───────────────────────────────────────────────────

func add_condition(condition: Condition) -> void:
	if _is_dead or not enable_conditions or conditions & condition:
		return
	conditions |= condition
	condition_changed.emit(conditions)
	if debug_log:
		print("[Health] condition added: ", get_condition_names())


## Treating a wound clears the flag: it stops the drain, it does not heal.
func remove_condition(condition: Condition) -> void:
	if not conditions & condition:
		return
	conditions &= ~condition
	condition_changed.emit(conditions)


func has_condition(condition: Condition) -> bool:
	return bool(conditions & condition)


func has_any_condition() -> bool:
	return conditions != Condition.NONE


## Display strings for the HUD, in a fixed order so the lines never jump.
func get_condition_names() -> PackedStringArray:
	var names := PackedStringArray()
	if conditions & Condition.BLEEDING:
		names.append("BLEEDING")
	if conditions & Condition.FRACTURE:
		names.append("FRACTURE")
	return names


## Stops the injury drain. MUST wrap any fast-forward of game time (sleep,
## timed crafting), otherwise the skipped minutes are charged as real damage.
func suspend_conditions() -> void:
	_conditions_suspended = true


func resume_conditions() -> void:
	_conditions_suspended = false

# ── Public API: queries ──────────────────────────────────────────────────────

func get_ratio() -> float:
	return current_health / max_health


func get_band() -> Band:
	return _band


func is_dead() -> bool:
	return _is_dead

# ── Save / load ──────────────────────────────────────────────────────────────
# Data, not nodes; no engine uptime. Game time lives in GameClockSystem and is
# saved there — health only needs its own numbers.

func get_save_data() -> Dictionary:
	return {
		"current_health": current_health,
		"conditions": conditions,
	}


func load_save_data(data: Dictionary) -> void:
	conditions = int(data.get("conditions", Condition.NONE))
	_is_dead = false
	condition_changed.emit(conditions)
	_set_health(float(data.get("current_health", max_health)))

# ── Internals ────────────────────────────────────────────────────────────────

func _on_game_minute_passed(_hour_of_day: float) -> void:
	if _is_dead or _conditions_suspended or not has_any_condition():
		return
	if _band != Band.CRITICAL:
		return

	var per_hour: float = terminal_drain_per_game_hour \
			if current_health < TERMINAL_THRESHOLD \
			else condition_drain_per_game_hour
	_set_health(current_health - per_hour / 60.0)


## The single write path for health. Everything else routes through here so
## that clamping, the band check and death happen in exactly one place.
func _set_health(value: float) -> void:
	var clamped: float = clampf(value, 0.0, max_health)
	if is_equal_approx(clamped, current_health):
		return
	current_health = clamped
	health_changed.emit(current_health, max_health)

	var new_band := _band_for(current_health)
	if new_band != _band:
		_band = new_band
		band_changed.emit(_band)

	if current_health <= 0.0 and not _is_dead:
		_is_dead = true
		died.emit()
		if debug_log:
			print("[Health] died")


func _band_for(value: float) -> Band:
	var ratio: float = value / max_health
	if ratio > BAND_IMPAIRED_RATIO:
		return Band.NOMINAL
	if ratio > BAND_CRITICAL_RATIO:
		return Band.IMPAIRED
	return Band.CRITICAL
