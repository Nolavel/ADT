# =============================================================================
# tps_combat_camera_state.gd
# Sub-state of the TPS camera inside OnFootCameraComponent: Explore <-> Locked.
# NOT a Node — just a state holder, called from the host's update().
#
# Explore: TLOU-style — spring-damper lag + procedural breathing/sway.
# Locked:  Souls-style — fixed on a target, orbiting a weighted pivot.
#
# TODO: target search currently goes through get_nodes_in_group("lockable") —
# once a RaycastService exists, replace _find_best_target() with an
# occlusion-aware version (occlusion isn't checked at all right now).
# =============================================================================
extends RefCounted
class_name TpsCombatCameraState

enum TpsState { EXPLORE, LOCKED, TRANSITION }

signal target_locked(target: Node3D)
signal target_lost()

var state: TpsState = TpsState.EXPLORE
var locked_target: Node3D = null

## Set once _get_facing_direction() has warned about a player with no
## get_facing_direction(), so the warning doesn't spam every frame.
var _warned_missing_facing_direction: bool = false

# --- Explore: spring-damper for yaw only, not for position — position is
# smoothed in _update_camera_position, at TPS_FOLLOW_SPEED once settled in
# steady-state TPS, or at view_transition_speed during the ISOMETRIC <->
# TPS transition animation. ---
@export var explore_spring_stiffness: float = 10.0
@export var explore_spring_damping: float = 6.0
var _yaw_velocity: float = 0.0

# --- Breathing / sway ---
@export var breathing_amplitude_deg: float = 0.4
@export var breathing_speed: float = 0.6
var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0
## External "tension" level, 0..1 — wire it up to health/stamina later.
## For now just a public field, free for anything to poke.
var tension: float = 0.0

# --- Locked: pivot weighting ---
@export var player_pivot_weight: float = 0.65
@export var lock_distance_min: float = 4.0
@export var lock_distance_max: float = 8.0
@export var lock_search_radius: float = 15.0
@export var lock_search_angle_deg: float = 70.0  # cone in front of the player

# --- Transition ---
@export var transition_duration: float = 0.35
var _transition_time: float = 0.0
var _transition_from_state: TpsState = TpsState.EXPLORE


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = breathing_speed


## Called from OnFootCameraComponent when the lock-on button is pressed
## (OnFootCameraComponent reads it via InputSystems.is_lock_on_just_pressed()
## before calling this — this method itself never touches Input).
func try_toggle_lock(player: Node3D) -> void:
	if state == TpsState.LOCKED:
		_clear_lock()
		return

	var target := _find_best_target(player)
	if target == null:
		return

	locked_target = target
	_start_transition(TpsState.LOCKED)
	target_locked.emit(target)


func _clear_lock() -> void:
	locked_target = null
	_start_transition(TpsState.EXPLORE)
	target_lost.emit()


## Group-scan stub. Every "lockable" enemy must be in the "lockable" group
## (add_to_group in its own script). Scoring: angle to screen center matters
## more than raw distance; jitter resistance for target switching isn't
## implemented yet — the first thing to add once "jumpy lock" complaints
## come in.
func _find_best_target(player: Node3D) -> Node3D:
	var candidates := player.get_tree().get_nodes_in_group("lockable")
	var forward := _get_facing_direction(player)
	var best_score := -INF
	var best: Node3D = null

	for c in candidates:
		if not (c is Node3D):
			continue
		var to_target: Vector3 = c.global_position - player.global_position
		var dist := to_target.length()
		if dist > lock_search_radius or dist < 0.01:
			continue

		var dir := to_target.normalized()
		var angle := rad_to_deg(forward.angle_to(dir))
		if angle > lock_search_angle_deg:
			continue

		# Smaller angle and shorter distance both raise the score; angle is weighted more.
		var score := (1.0 - angle / lock_search_angle_deg) * 0.7 \
				+ (1.0 - dist / lock_search_radius) * 0.3
		if score > best_score:
			best_score = score
			best = c

	return best


## Reads player.get_facing_direction() via duck typing, one-time-warning
## pattern matching OnFootCameraComponent's target-metric getters. Falls
## back to Godot's own -Z-is-forward convention if the target doesn't
## expose it — wrong for this project's own characters (they rotate with
## atan2(dir.x, dir.z), +Z forward — see get_facing_direction() on
## player.gd/npc_base.gd), but a safe default for a generic Node3D that
## isn't one of them.
func _get_facing_direction(player: Node3D) -> Vector3:
	if player.has_method(&"get_facing_direction"):
		return player.call(&"get_facing_direction") as Vector3
	if not _warned_missing_facing_direction:
		push_warning("TpsCombatCameraState: player '%s' has no get_facing_direction() — falling back to -basis.z" % player.name)
		_warned_missing_facing_direction = true
	return -player.global_transform.basis.z


## Read-only diagnostic for the lock-on debug overlay
## (ui/debug/stream_debug_panel.gd) — never call this from code that decides
## anything. Deliberately a separate scan, not a refactor of
## _find_best_target(): finds the single nearest "lockable" node by raw
## distance (regardless of angle) and reports which check would reject it,
## so the overlay can show "why" even when nothing would actually lock.
##
## Reads the same _get_facing_direction() as _find_best_target(), so the two
## can't drift apart on which way "forward" means.
func get_lock_on_diagnostic(player: Node3D) -> Dictionary:
	var candidates := player.get_tree().get_nodes_in_group("lockable")
	var result := {
		"lockable_count": candidates.size(),
		"nearest_name": "",
		"distance": 0.0,
		"angle_deg": 0.0,
		"rejected_by": "none",   # "none" = no candidates, "radius", "cone", "" = would pass
		"forward": Vector3.ZERO,
		"to_nearest": Vector3.ZERO,
	}
	if candidates.is_empty():
		return result

	var forward := _get_facing_direction(player)
	result.forward = forward

	var nearest: Node3D = null
	var nearest_dist := INF
	for c in candidates:
		if not (c is Node3D):
			continue
		var dist := player.global_position.distance_to(c.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = c

	if nearest == null:
		return result

	var to_target: Vector3 = nearest.global_position - player.global_position
	var dir := to_target.normalized() if nearest_dist > 0.001 else Vector3.ZERO
	var angle := rad_to_deg(forward.angle_to(dir))

	result.nearest_name = nearest.name
	result.distance = nearest_dist
	result.angle_deg = angle
	result.to_nearest = dir

	if nearest_dist > lock_search_radius:
		result.rejected_by = "radius"
	elif angle > lock_search_angle_deg:
		result.rejected_by = "cone"
	else:
		result.rejected_by = ""   # would pass both checks

	return result


func _start_transition(to_state: TpsState) -> void:
	_transition_from_state = state
	_transition_time = 0.0
	state = TpsState.TRANSITION
	_pending_target_state = to_state

var _pending_target_state: TpsState = TpsState.EXPLORE


## Returns a Dictionary with keys "yaw", "pitch_offset_deg" and
## "distance_override" (-1.0 means "don't override").
## OnFootCameraComponent decides on its own how to apply this to camera_target_*.
func update(delta: float, player: Node3D, current_yaw: float) -> Dictionary:
	match state:
		TpsState.TRANSITION:
			_transition_time += delta
			var t: float = clamp(_transition_time / transition_duration, 0.0, 1.0)
			var te = t * t * (3.0 - 2.0 * t)
			if _transition_time >= transition_duration:
				state = _pending_target_state
			return _blend_result(player, current_yaw, te)

		TpsState.LOCKED:
			if locked_target == null or not is_instance_valid(locked_target):
				_clear_lock()
				return _explore_result(player, current_yaw, delta)
			return _locked_result(player, current_yaw)

		_:
			return _explore_result(player, current_yaw, delta)


func _explore_result(player: Node3D, current_yaw: float, delta: float) -> Dictionary:
	var target_yaw := player.rotation.y + PI

	# Spring-damper instead of a plain lerp — gives viscosity, not a rubber-band snap.
	var diff := wrapf(target_yaw - current_yaw, -PI, PI)
	var accel := diff * explore_spring_stiffness - _yaw_velocity * explore_spring_damping
	_yaw_velocity += accel * delta
	var new_yaw := current_yaw + _yaw_velocity * delta

	# Breathing: small noise on pitch, amplitude grows with tension.
	_noise_time += delta
	var sway := _noise.get_noise_1d(_noise_time * 20.0) * breathing_amplitude_deg * (0.4 + tension)

	return {
		"yaw": new_yaw,
		"pitch_offset_deg": sway,
		"distance_override": -1.0,  # -1 = don't override
	}


func _locked_result(player: Node3D, _current_yaw: float) -> Dictionary:
	var pivot := player.global_position.lerp(
			locked_target.global_position, 1.0 - player_pivot_weight)
	var to_pivot := pivot - player.global_position
	var desired_yaw := atan2(to_pivot.x, to_pivot.z) + PI

	# Distance auto-fits to the distance to the target, clamped to the configured range.
	var dist_to_target := player.global_position.distance_to(locked_target.global_position)
	var distance: float = clamp(dist_to_target * 0.8, lock_distance_min, lock_distance_max)

	return {
		"yaw": desired_yaw,
		"pitch_offset_deg": 0.0,
		"distance_override": distance,
	}


func _blend_result(player: Node3D, current_yaw: float, te: float) -> Dictionary:
	var from_res: Dictionary
	var to_res: Dictionary

	if _transition_from_state == TpsState.LOCKED:
		from_res = _locked_result(player, current_yaw) if is_instance_valid(locked_target) else _explore_result(player, current_yaw, 0.0)
	else:
		from_res = _explore_result(player, current_yaw, 0.0)

	if _pending_target_state == TpsState.LOCKED and is_instance_valid(locked_target):
		to_res = _locked_result(player, current_yaw)
	else:
		to_res = _explore_result(player, current_yaw, 0.0)

	var blended_yaw := lerp_angle(from_res.yaw, to_res.yaw, te)
	var blended_pitch: float = lerp(
	float(from_res.pitch_offset_deg),
	float(to_res.pitch_offset_deg),
	te
)
	var blended_dist: float = float(from_res.distance_override)
	if to_res.distance_override > 0.0:
		var from_dist = from_res.distance_override if from_res.distance_override > 0.0 else lock_distance_max
		blended_dist = lerp(from_dist, to_res.distance_override, te)

	return {
		"yaw": blended_yaw,
		"pitch_offset_deg": blended_pitch,
		"distance_override": blended_dist,
	}
