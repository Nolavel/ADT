# =============================================================================
# shot_effect_system.gd — what a shot looks like. Two things, two lifetimes.
#
# Not an autoload and not a component: one line in world.gd's
# WORLD_SYSTEM_SCRIPTS, and callers that never receive a WorldContext find it
# by group — the same scheme ComicEffectSystem uses, and player.gd already
# reaches that one exactly this way (_try_spawn_comic_effect()).
#
# TWO EFFECTS, AND THEY DO NOT SHARE A PARENT OR A LIFETIME:
#
#   FLASH    at the barrel, ~0.08 s. FOLLOWS the muzzle while it is alive —
#            the hand moves visibly inside that brief impulse, and a
#            flash pinned to where the barrel WAS reads as a detached spark.
#   TRACER   muzzle to impact, ~0.07 s. A SNAPSHOT, taken once when the
#            trigger is pulled. It is a record of where the round went; a
#            line that keeps re-anchoring to a moving hand is a rubber band.
#
# The flash follows WITHOUT being a child of the weapon. EquipmentVisuals
# queue_free()s the held mesh the instant the weapon is holstered, and a child
# of it would die mid-life with no way to finish. So it stays in this system's
# own subtree and re-reads get_muzzle_position() each frame, which is the same
# answer parenting would have given and the same shape ComicEffectLabel's
# set_follow() already uses.
#
# NO TWEENS. Lifetimes run in one _process(), like ComicEffectSystem ticks its
# labels. A tween per effect is how TargetIndicator._disappear() once built one
# per frame and left "27 resources still in use at exit" — a gated line in CI.
#
# NOTHING IS LOADED FROM DISK. The flash is a QuadMesh with a radial
# GradientTexture2D and the tracer is a four-sided CylinderMesh, both built in
# code, so this costs no asset and no shader. Materials are per-pool-unit
# duplicates so alpha can be faded one effect at a time.
# =============================================================================
class_name ShotEffectSystem
extends Node3D

## Lookup group for callers with no WorldContext — same role as
## ComicEffectSystem.GROUP_COMIC_EFFECT_SYSTEM, resolved once and cached by
## the caller.
const GROUP_SHOT_EFFECT_SYSTEM: StringName = &"shot_effect_system"

## Four is two more than the fire rate can put on screen at once: a shot locks
## movement for the length of the rifle_shot clip (1.167 s) and both effects
## are gone inside a tenth of a second. The pool exists to keep allocation off
## the frame the trigger is pulled, not to hold a backlog.
const POOL_SIZE: int = 4

## Shorter than this and the tracer is a point rather than a line; a shot
## resolved against a target standing on the muzzle is not a shot to draw.
const MIN_TRACER_LENGTH: float = 0.05

## --- Tunables. NOT @export, and that is not an oversight. ---
##
## This system is created with .new() from world.gd's WORLD_SYSTEM_SCRIPTS, so
## it has no node in any scene and no inspector — an @export here would draw a
## field nobody can reach. ComicEffectSystem is in the same position and
## answers it with const for the same reason. These stay `var` rather than
## const only because a throwaway probe raises the two durations: at
## render_probe.sh's 20 fps a 0.05 s effect can fall between two captures and
## be photographed as nothing at all.
##
## EVERY ONE OF THEM IS READ AT SPAWN. Nothing here is baked into a mesh at
## _ready(): a number that only takes effect on the next run is a number that
## silently ignores whoever changed it, and this file had exactly that bug in
## flash_size and tracer_radius before the sizes moved onto the node scale.

## Seconds the muzzle flash is on screen. Short on purpose — a flash that
## outlasts the frame it belongs to reads as a fire, not a shot.
var flash_duration: float = 0.08
## Width of the flash quad at birth, metres. It shrinks to flash_end_scale of
## this over its life.
var flash_size: float = 0.56
var flash_end_scale: float = 0.45
## Warm and saturated against a muted world — 3D_ART_BIBLE.md §10's "muted
## industrial palette + selective saturated accents". The shot IS the accent.
var flash_color: Color = Color(1.0, 0.86, 0.55)

## Seconds the tracer streak is on screen. Slightly longer than the flash so
## the eye reads the line after the bang rather than with it.
var tracer_duration: float = 0.07
## Radius of the tracer cylinder, metres.
var tracer_radius: float = 0.015
## Near-white, warmed a little so it belongs to the same shot as the flash.
var tracer_color: Color = Color(1.0, 0.95, 0.86)

## An OmniLight3D at the muzzle for the length of the flash. It is shadowless
## and short-lived: a visible firing impulse needs to light nearby geometry,
## while a per-shot shadow map would exceed the low-end FPS budget.
var flash_light_energy: float = 4.0
var flash_light_range: float = 3.0

## One pool unit. Not a class of its own — it is three nodes and two clocks,
## and a Resource or a Node subclass for that would be a file to open every
## time someone wants to know what a shot looks like.
var _units: Array[Dictionary] = []
## Shared between every unit; only the materials are per-unit.
var _flash_texture: GradientTexture2D = null
var _flash_mesh: QuadMesh = null
var _tracer_mesh: CylinderMesh = null


func _ready() -> void:
	add_to_group(GROUP_SHOT_EFFECT_SYSTEM)
	_build_shared_resources()
	for _i in POOL_SIZE:
		_units.append(_build_unit())


# -----------------------------------------------------------------------------
# ## ENG: Public API
# -----------------------------------------------------------------------------

## One shot: a flash at `from` and a streak from `from` to `to`.
##
## `muzzle_source` is what the flash follows while it is alive. Null is
## allowed and means the flash stays where it was born — correct for anything
## that fires without a hand, and harmless for anything that does not.
##
## Silently does nothing when the pool is exhausted. A shot is decoration over
## damage that has already been dealt, and a missing streak is a better
## outcome than a stutter.
func spawn_shot(
	from: Vector3, to: Vector3, muzzle_source: EquipmentVisualsComponent = null
) -> void:
	var unit := _acquire()
	if unit.is_empty():
		return

	unit["muzzle_source"] = muzzle_source
	unit["flash_left"] = flash_duration
	unit["tracer_left"] = tracer_duration

	var flash: MeshInstance3D = unit["flash"]
	flash.global_position = from
	flash.scale = Vector3.ONE * flash_size
	flash.visible = flash_duration > 0.0

	var light: OmniLight3D = unit["light"]
	light.omni_range = flash_light_range
	light.light_energy = flash_light_energy
	light.visible = flash_duration > 0.0 and flash_light_energy > 0.0

	var tracer: MeshInstance3D = unit["tracer"]
	tracer.visible = tracer_duration > 0.0 and _place_tracer(tracer, from, to)

	_paint(unit, 1.0)


# -----------------------------------------------------------------------------
# ## ENG: Lifetimes — one loop, no tweens
# -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	for unit in _units:
		if unit["flash_left"] <= 0.0 and unit["tracer_left"] <= 0.0:
			continue
		_tick(unit, delta)


func _tick(unit: Dictionary, delta: float) -> void:
	var flash: MeshInstance3D = unit["flash"]
	var light: OmniLight3D = unit["light"]
	var tracer: MeshInstance3D = unit["tracer"]

	if unit["flash_left"] > 0.0:
		unit["flash_left"] = unit["flash_left"] - delta
		if unit["flash_left"] <= 0.0:
			flash.visible = false
			light.visible = false
		else:
			## Re-read every frame rather than parenting — see this file's
			## header on why the weapon must not own this node.
			var source: EquipmentVisualsComponent = unit["muzzle_source"]
			if is_instance_valid(source) and source.has_muzzle():
				flash.global_position = source.get_muzzle_position()
				light.global_position = flash.global_position
			var life: float = _fraction_left(unit["flash_left"], flash_duration)
			flash.scale = Vector3.ONE * flash_size * lerpf(flash_end_scale, 1.0, life)
			light.light_energy = flash_light_energy * life

	if unit["tracer_left"] > 0.0:
		unit["tracer_left"] = unit["tracer_left"] - delta
		if unit["tracer_left"] <= 0.0:
			tracer.visible = false

	_paint(unit, -1.0)


## Alpha on both materials from whatever is left of each clock. Called with
## 1.0 at birth so the first frame is drawn at full strength rather than one
## frame's worth faded.
func _paint(unit: Dictionary, forced: float) -> void:
	var flash_alpha: float = (
		forced if forced >= 0.0 else _fraction_left(unit["flash_left"], flash_duration)
	)
	var tracer_alpha: float = (
		forced if forced >= 0.0 else _fraction_left(unit["tracer_left"], tracer_duration)
	)
	var flash_material: StandardMaterial3D = unit["flash_material"]
	var tracer_material: StandardMaterial3D = unit["tracer_material"]
	flash_material.albedo_color = Color(flash_color, flash_color.a * maxf(flash_alpha, 0.0))
	tracer_material.albedo_color = Color(tracer_color, tracer_color.a * maxf(tracer_alpha, 0.0))


## How much of a clock is left, 0..1. A zero-length duration reads as spent
## rather than dividing by nothing — that is what an @export of 0.0 means, and
## it is the backward control the render probe uses.
func _fraction_left(left: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(left / duration, 0.0, 1.0)


# -----------------------------------------------------------------------------
# ## ENG: Placement
# -----------------------------------------------------------------------------

## Stretches the tracer cylinder along the segment. False — and no tracer —
## for a segment too short to have a direction.
##
## CylinderMesh runs along +Y and look_at() aims -Z, hence the quarter turn
## after it. The up vector is swapped when the shot is near-vertical, because
## look_at() has no basis to build from when the direction and the up vector
## are parallel — a shot straight down at a target below is exactly that case.
func _place_tracer(tracer: MeshInstance3D, from: Vector3, to: Vector3) -> bool:
	var delta := to - from
	var length := delta.length()
	if length < MIN_TRACER_LENGTH:
		return false

	var direction := delta / length
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT

	tracer.global_position = from + delta * 0.5
	tracer.look_at(to, up)
	tracer.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	## The mesh is a unit cylinder, so the Y scale IS the length in metres and
	## the X/Z scale IS the diameter.
	tracer.scale = Vector3(tracer_radius * 2.0, length, tracer_radius * 2.0)
	return true


# -----------------------------------------------------------------------------
# ## ENG: Construction
# -----------------------------------------------------------------------------

func _build_shared_resources() -> void:
	## A radial gradient instead of an imported sprite: the flash is a soft
	## round blob, GradientTexture2D draws exactly that, and this way the
	## effect adds no file to the repository and no shader to compile.
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.75))

	_flash_texture = GradientTexture2D.new()
	_flash_texture.gradient = gradient
	_flash_texture.fill = GradientTexture2D.FILL_RADIAL
	_flash_texture.fill_from = Vector2(0.5, 0.5)
	_flash_texture.fill_to = Vector2(1.0, 0.5)
	_flash_texture.width = 64
	_flash_texture.height = 64

	## A ONE METRE quad, scaled on the node. The size used to be baked here,
	## which meant flash_size was read once at _ready() and changing it later
	## did nothing at all.
	_flash_mesh = QuadMesh.new()
	_flash_mesh.size = Vector2.ONE

	## Unit cylinder — diameter 1, height 1 — so the node scale carries both
	## the radius and the length, and both are read at spawn. Same fix and
	## same reason as the flash quad above.
	_tracer_mesh = CylinderMesh.new()
	_tracer_mesh.top_radius = 0.5
	_tracer_mesh.bottom_radius = 0.5
	_tracer_mesh.height = 1.0
	## Eight triangles. A tracer is on screen for four frames and is seen
	## end-on; nobody is going to count its sides.
	_tracer_mesh.radial_segments = 4
	_tracer_mesh.rings = 0
	_tracer_mesh.cap_top = false
	_tracer_mesh.cap_bottom = false


func _build_unit() -> Dictionary:
	var flash_material := _make_material()
	flash_material.albedo_texture = _flash_texture
	## Billboard so the flash has no wrong side. The alternative is aiming it
	## down the barrel, which needs a forward axis on the item — a second
	## source of truth about where a shot goes, which muzzle_offset is
	## deliberately not (see ItemResource.muzzle_offset).
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	## Without this the billboard basis REPLACES the node's scale, so both
	## flash_size and the shrink over the flash's life are silently discarded
	## and every flash draws one metre wide. Godot's default is false.
	flash_material.billboard_keep_scale = true

	var flash := MeshInstance3D.new()
	flash.mesh = _flash_mesh
	flash.material_override = flash_material
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)

	var light := OmniLight3D.new()
	## Never shadow-casting. The directional shadow map is tuned to 1024 for
	## the FPS target and a per-shot shadow-casting light is exactly the kind
	## of effect that budget refuses.
	light.shadow_enabled = false
	light.light_color = flash_color
	light.visible = false
	add_child(light)

	var tracer_material := _make_material()
	var tracer := MeshInstance3D.new()
	tracer.mesh = _tracer_mesh
	tracer.material_override = tracer_material
	tracer.visible = false
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)

	return {
		"flash": flash,
		"flash_material": flash_material,
		"light": light,
		"tracer": tracer,
		"tracer_material": tracer_material,
		"muzzle_source": null,
		"flash_left": 0.0,
		"tracer_left": 0.0,
	}


## Unshaded and additive: a muzzle flash and a tracer are light, not surfaces,
## and lighting them would put the world's shading on top of the brightest
## thing in the frame.
func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material


func _acquire() -> Dictionary:
	for unit in _units:
		if unit["flash_left"] <= 0.0 and unit["tracer_left"] <= 0.0:
			return unit
	return {}
