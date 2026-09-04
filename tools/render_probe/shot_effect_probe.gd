# =============================================================================
# shot_effect_probe.gd — deterministic visual evidence for the firing VFX.
#
# CI cannot press LMB in the playable world. This isolated stage creates the
# actual ShotEffectSystem, repeatedly calls its public spawn_shot() API, and
# keeps the effect square to the camera. It tests that the flash and tracer
# draw at all; it does not replace a gameplay-input or Forward+ lighting test.
# =============================================================================
extends Node3D

const SHOT_INTERVAL: float = 0.5
const SHOT_FROM: Vector3 = Vector3(-2.0, 1.2, 0.0)
const SHOT_TO: Vector3 = Vector3(2.0, 1.2, 0.0)

var _shot_effects: ShotEffectSystem = null
var _shot_age: float = 0.0


func _ready() -> void:
	_build_stage()
	_shot_effects = ShotEffectSystem.new()
	add_child(_shot_effects)
	await get_tree().process_frame
	_spawn_probe_shot()


func _process(delta: float) -> void:
	_shot_age += delta
	if _shot_age >= SHOT_INTERVAL:
		_shot_age = 0.0
		_spawn_probe_shot()


func _spawn_probe_shot() -> void:
	if _shot_effects != null:
		_shot_effects.spawn_shot(SHOT_FROM, SHOT_TO)


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.028)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 5.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, 0.0))
	camera.make_current()

	var backdrop := MeshInstance3D.new()
	var backdrop_mesh := QuadMesh.new()
	backdrop_mesh.size = Vector2(8.0, 4.5)
	backdrop.mesh = backdrop_mesh
	backdrop.position = Vector3(0.0, 1.5, -1.0)
	backdrop.material_override = _make_stage_material(Color(0.045, 0.06, 0.09))
	add_child(backdrop)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	floor.mesh = floor_mesh
	floor.material_override = _make_stage_material(Color(0.025, 0.032, 0.05))
	add_child(floor)


func _make_stage_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
