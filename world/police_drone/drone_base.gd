# =============================================================================
# drone_base.gd — DroneBase, the flying body shared by every police drone.
#
# Same separation as NPCBase/HoverBase: this body integrates a movement
# intent and holds itself above the ground, it never decides where to go or
# what to look at — set_move_intent()/set_look_target() are the only way in,
# and only PatrolDroneController (world/police_drone/controllers/) calls
# them. Extends ActorBase (core/characters/actor_base.gd) instead of
# CharacterBody3D directly, the same base NPCBase extends — that is what
# lets PatrolDroneController extend NPCControllerBase and PerceptionComponent
# attach here unmodified; see actor_base.gd's own header for why.
#
# CharacterBody3D, not RigidBody3D (the old police_drone.gd's base) — same
# reasoning as HoverBase (core/controllers/transport/base/hover_base.gd):
# fighting a rigid body's physics by writing linear_velocity directly and
# lerping toward a target every frame is pseudo-physics wearing a physics
# engine's clothes. A kinematic body doing the pseudo-physics honestly needs
# no gravity_scale hack and no angular axis locks — this body's rotation is
# simply never written to (see the mesh-orientation note below).
#
# Horizontal movement reuses HoverBase's exact approach: one smoothing
# coefficient chosen by whether there's move intent right now (acceleration
# vs braking), not by comparing current/target speed — see that file's own
# comment on why a compared-magnitude rate produces bang-bang jitter at top
# speed. Framerate-independent smoothing here goes through
# Smoothing.damp_factor() (core/math/smoothing.gd) instead of HoverBase's
# hand-inlined 1-exp(-k*delta) — identical formula, this project's usual way
# of writing it; see that file's own header for why it exists.
#
# Vertical hold also mirrors HoverBase's semi-automatic altitude hold
# (proportional return toward a held altitude: velocity.y = error *
# stiffness) but the target itself is NOT a captured world Y — HoverBase
# holds whatever Y the pilot last left it at, appropriate for a vehicle that
# can be anywhere. This drone patrols over uneven city terrain, so its held
# altitude is continuously re-derived from HeightRayCast — hover_height
# above whatever ground is directly beneath it right now, resampled every
# frame rather than captured once. That resampling is the one piece
# HoverBase's own altitude hold has no equivalent for.
#
# Mesh orientation (set_look_target) is intentionally NOT body rotation:
# this body's own rotation.y never moves — there is no equivalent of
# NPCBase's _face_move_direction here — only DroneMesh turns to face the
# look target, damped the same way the old police_drone.gd already did
# (Transform3D.interpolate_with). That is why get_facing_direction() below
# overrides ActorBase's default instead of inheriting it: ActorBase's
# formula reads rotation.y, which would report a constant here.
# =============================================================================
extends ActorBase
class_name DroneBase

@export_group("Flight")
## Height this drone holds above the ground directly beneath it, sampled by
## HeightRayCast every frame. Not a fixed world Y — the ground moves as the
## drone patrols over uneven city terrain.
@export var hover_height: float = 7.0
## Top horizontal speed, m/s. Movement intent's speed_ratio scales this.
@export var max_speed: float = 15.0
## Horizontal acceleration responsiveness — a Smoothing.damp_factor() rate,
## not m/s²; see the file header for why this is HoverBase's approach.
@export var acceleration: float = 5.0
## Horizontal braking responsiveness, no movement intent this frame. Higher
## than acceleration on purpose, same feel convention as HoverBase.
@export var braking: float = 5.0
## Vertical altitude-hold stiffness (1/s) — higher snaps back to
## hover_height above ground more sharply. Same formula as HoverBase's
## altitude_hold_stiffness.
@export var altitude_hold_stiffness: float = 4.0
## How fast DroneMesh turns to face its look target, a
## Smoothing.damp_factor() rate.
@export var mesh_turn_smoothing: float = 5.0

@export_group("Sensor")
## Height of this drone's sensor point above its own origin. Origin already
## sits at the drone body's centre (DroneMesh is centred on it, same as the
## old RigidBody3D sphere), hence 0 — exported in case a future mesh puts
## the sensor housing somewhere else. Unverified without an actual model.
@export var eye_height: float = 0.0

## Movement intent for this frame, written by whatever controller drives
## this drone. direction is expected normalised and horizontal (Y ignored);
## speed_ratio is 0..1, a fraction of max_speed.
var _move_direction: Vector3 = Vector3.ZERO
var _move_speed_ratio: float = 0.0

## World point DroneMesh turns toward — set by set_look_target()/
## clear_look_target(), read only by _update_mesh_look(). No fallback
## "neutral" orientation: in practice PatrolDroneController always has a
## patrol point or a player to look at, so an unset look target just leaves
## DroneMesh at its last orientation instead of manufacturing one.
var _has_look_target: bool = false
var _look_target_point: Vector3 = Vector3.ZERO

@onready var _height_ray: RayCast3D = $HeightRayCast
@onready var _mesh: Node3D = $DroneMesh


func _physics_process(delta: float) -> void:
	_process_horizontal(delta)
	_process_altitude(delta)
	move_and_slide()
	_update_mesh_look(delta)



## Movement intent for this frame, written by whatever controller drives this
## drone. The body integrates it; it never decides where to go.
func set_move_intent(direction: Vector3, speed_ratio: float) -> void:
	_move_direction = direction
	_move_speed_ratio = clampf(speed_ratio, 0.0, 1.0)


## World point the drone orients its mesh toward. Where to look is a
## decision; aiming the mesh is not.
func set_look_target(point: Vector3) -> void:
	_has_look_target = true
	_look_target_point = point


func clear_look_target() -> void:
	_has_look_target = false


func get_eye_height() -> float:
	return eye_height


## Overrides ActorBase's default: this body's own rotation.y never turns
## (see the file header), so the inherited atan2 formula would report a
## constant. Reports DroneMesh's actual horizontal facing instead — Godot's
## native -Z-forward convention, since DroneMesh turns via looking_at()
## rather than this project's usual atan2(x, z) rotation.y writes.
func get_facing_direction() -> Vector3:
	if not _mesh:
		return Vector3.FORWARD
	var forward := -_mesh.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()


func get_debug_type_label() -> String:
	return "Drone"


## Horizontal inertia — see the file header for why this is HoverBase's
## approach (one rate chosen by move-intent presence) rather than a
## per-frame current/target magnitude comparison.
func _process_horizontal(delta: float) -> void:
	var target_h := _move_direction * (max_speed * _move_speed_ratio)
	target_h.y = 0.0

	var has_intent := _move_speed_ratio > 0.01 and _move_direction.length() > 0.01
	var k := acceleration if has_intent else braking

	var current_h := Vector3(velocity.x, 0.0, velocity.z)
	current_h = current_h.lerp(target_h, Smoothing.damp_factor(k, delta))

	velocity.x = current_h.x
	velocity.z = current_h.z


## Ground-following altitude hold — see the file header for how this
## differs from HoverBase's own (fixed held Y vs. continuously resampled
## ground height). No raycast hit yet (e.g. the first physics frame, before
## RayCast3D has updated) holds velocity.y at 0 rather than guessing.
func _process_altitude(_delta: float) -> void:
	if not _height_ray or not _height_ray.is_colliding():
		velocity.y = 0.0
		return
	var ground_y := _height_ray.get_collision_point().y
	var target_y := ground_y + hover_height
	var error := target_y - global_position.y
	velocity.y = error * altitude_hold_stiffness


## Turns DroneMesh to face _look_target_point, projected onto the mesh's own
## height so it turns rather than pitches. Never snaps.
func _update_mesh_look(delta: float) -> void:
	if not _mesh or not _has_look_target:
		return

	var target_point := Vector3(_look_target_point.x, _mesh.global_position.y, _look_target_point.z)
	if _mesh.global_position.distance_to(target_point) < 0.05:
		return

	var target_transform := _mesh.global_transform.looking_at(target_point, Vector3.UP)
	var t := Smoothing.damp_factor(mesh_turn_smoothing, delta)
	_mesh.global_transform = _mesh.global_transform.interpolate_with(target_transform, t)
