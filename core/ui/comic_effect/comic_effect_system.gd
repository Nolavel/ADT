# =============================================================================
# comic_effect_system.gd — pure visual floating words (emotion / reaction
# text). Not audio. Not an autoload.
#
# Wired only through WORLD_SYSTEM_SCRIPTS + on_world_ready. Callers that never
# receive a WorldContext (NPCBase, IdleNPCController, rooms, drones) resolve
# this system the same way they resolve IncidentRegistry: group lookup once,
# cache the reference, call try_spawn() directly. There is no static facade —
# that pattern does not exist for any other WORLD_SYSTEM_SCRIPTS entry.
#
# Distance gate is load-bearing: events beyond ComicEffectDef.radius never
# spawn a word. Pool + MAX_ACTIVE keep the cost fixed under the ~55 FPS
# target. Anti-repeat avoids the same string on consecutive spawns of one id.
#
# The vocabulary is DATA, not code: every ComicEffectDef lives as its own
# .tres under data/comic_effects/, gathered by a ComicEffectCatalog. The
# comic layer is a visual language of this project, not a debug tool, so it
# will keep growing — adding a word, or a whole event, must never require
# touching this file. register_def() stays as the runtime seam for anything
# that wants to add a def without editing the catalog.
# =============================================================================
class_name ComicEffectSystem
extends Node

## Lookup group for consumers that never receive WorldContext — same role as
## IncidentRegistry.GROUP_INCIDENT_REGISTRY. Resolved via
## get_tree().get_first_node_in_group() and cached by the caller.
const GROUP_COMIC_EFFECT_SYSTEM: StringName = &"comic_effect_system"

const POOL_SIZE: int = 12
const MAX_ACTIVE: int = 8
const DEFAULT_OFFSET: Vector3 = Vector3(0.0, 1.6, 0.0)
## How far to one side of the source a word is placed, metres.
##
## Dead centre above the head put the panel ON the thing it was about, hiding
## the face or the item that is the actual subject of the moment. A word is a
## remark about an event, not a label stuck to it — so it stands beside the
## source and lets it be seen. Stan, 2026-08-28.
const LATERAL_OFFSET: float = 0.55
## Sideways placement is randomised within this arc so two words on one head
## do not land on each other. Radians, centred on "to the side".
const LATERAL_SPREAD: float = 1.1
## Above typical HUD layers (world.gd UI canvas uses 40).
const CANVAS_LAYER_INDEX: int = 45

## Where the vocabulary lives. Loaded by PATH, deliberately, not through an
## @export the way KeyHintsPanel reaches KeyHintsCatalog: this system is
## built with .new() from world.gd's WORLD_SYSTEM_SCRIPTS and so has no
## inspector for anyone to assign a catalog in. Scanning the folder with
## DirAccess was the other candidate and is worse: an exported build turns
## .tres into binary and routes it through .remap, so a runtime search for
## "*.tres" finds a full set in the editor and an empty one in a shipped
## build — the failure would only ever show up after packaging.
const CATALOG_PATH: String = "res://data/comic_effects/catalog.tres"

var _camera: Camera3D = null
var _player: Node3D = null
var _pool: Array[ComicEffectLabel] = []
var _active: Array[ComicEffectLabel] = []
var _defs: Dictionary = {}  # StringName -> ComicEffectDef
var _layer: CanvasLayer = null
## Last text shown per def id — anti-repeat within the same id only.
var _last_text_by_id: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_COMIC_EFFECT_SYSTEM)


func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	## Fallback only — _active_camera() asks the viewport each frame. Capturing
	## one camera at world-ready was how the F panel stopped appearing: a
	## reference that is no longer the current camera unprojects to nowhere.
	_camera = context.camera
	_build_layer()
	_build_pool()
	_load_catalog()


func register_def(def: ComicEffectDef) -> void:
	if def == null or def.id == &"":
		return
	_defs[def.id] = def


## Public API. world_pos is used when follow is null; when follow is valid,
## its global_position is the source and the label tracks it each frame.
func try_spawn(id: StringName, world_pos: Vector3, follow: Node3D = null) -> void:
	if _camera == null or _player == null:
		return
	var def: ComicEffectDef = _defs.get(id) as ComicEffectDef
	if def == null or def.texts.is_empty():
		return

	var origin: Vector3 = world_pos
	if is_instance_valid(follow):
		origin = follow.global_position
	if _player.global_position.distance_to(origin) > def.radius:
		return
	if _active.size() >= MAX_ACTIVE:
		return

	var label: ComicEffectLabel = _acquire()
	if label == null:
		return

	var text: String = _pick_text(def)
	label.setup(text, def.resolve_profile(), def.get_font_size())
	var offset: Vector3 = _spawn_offset()
	if is_instance_valid(follow):
		label.set_follow(follow, offset)
	else:
		label.set_world_source(world_pos, offset)

	if not label.finished.is_connected(_on_label_finished):
		label.finished.connect(_on_label_finished)
	_active.append(label)


## Beside the source, not on top of it, at a random angle so two words on one
## head do not overlap. The vertical part is unchanged.
func _spawn_offset() -> Vector3:
	var angle: float = randf_range(-LATERAL_SPREAD, LATERAL_SPREAD)
	if randf() < 0.5:
		angle += PI
	return DEFAULT_OFFSET + Vector3(
		cos(angle) * LATERAL_OFFSET, 0.0, sin(angle) * LATERAL_OFFSET
	)


func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = CANVAS_LAYER_INDEX
	# Same deferred pattern as world.gd's UI canvas — root may still be
	# settling when on_world_ready runs.
	get_tree().root.call_deferred("add_child", _layer)


func _build_pool() -> void:
	for _i in POOL_SIZE:
		var label := ComicEffectLabel.new()
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Alignment and outline used to be set here as Label properties and
		# theme overrides. The panel draws its own type now, from its
		# ComicVisualProfile — setting them here would be a second, silent
		# source for the same two decisions.
		_pool.append(label)
		call_deferred("_attach_label", label)


func _attach_label(label: ComicEffectLabel) -> void:
	if _layer != null and is_instance_valid(_layer) and label.get_parent() == null:
		_layer.add_child(label)


## Reads the catalog once, at world-ready. A missing file, an unreadable
## one, or a def with an empty texts pool are all non-fatal by design: the
## comic layer is decoration over events that must keep happening either
## way, so every failure here warns and leaves that id simply unspawnable
## (try_spawn() already treats an unknown or empty def as a no-op).
func _load_catalog() -> void:
	var catalog := load(CATALOG_PATH) as ComicEffectCatalog
	if catalog == null:
		push_warning(
			"[ComicEffectSystem] no catalog at %s — no words will spawn" % CATALOG_PATH
		)
		return
	for def in catalog.effects:
		if def == null:
			continue
		if def.texts.is_empty():
			push_warning(
				"[ComicEffectSystem] def '%s' has an empty texts pool — never spawns" % def.id
			)
		register_def(def)


func _pick_text(def: ComicEffectDef) -> String:
	var texts: PackedStringArray = def.texts
	if texts.size() == 1:
		return texts[0]

	var last: String = str(_last_text_by_id.get(def.id, ""))
	var candidates: PackedStringArray = PackedStringArray()
	for t in texts:
		if t != last:
			candidates.append(t)
	if candidates.is_empty():
		candidates = texts

	# Weighted path only when weights match length; otherwise uniform.
	var pick: String
	if def.weights.size() == texts.size():
		pick = _pick_weighted(candidates, def)
	else:
		pick = candidates[randi() % candidates.size()]

	_last_text_by_id[def.id] = pick
	return pick


func _pick_weighted(candidates: PackedStringArray, def: ComicEffectDef) -> String:
	# Build weight list only for candidates (excludes last when possible).
	var weights: Array[float] = []
	var total: float = 0.0
	for t in candidates:
		var idx: int = def.texts.find(t)
		var w: float = def.weights[idx] if idx >= 0 else 1.0
		weights.append(w)
		total += w
	if total <= 0.0:
		return candidates[randi() % candidates.size()]
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in candidates.size():
		acc += weights[i]
		if roll <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


func _acquire() -> ComicEffectLabel:
	for label in _pool:
		if not label.is_alive():
			return label
	return null


func _on_label_finished(label: ComicEffectLabel) -> void:
	_active.erase(label)


## The camera that is actually rendering. Same fix, same reason, as
## HoldPrompt._active_camera(): a camera captured once stops being the one on
## screen the first time the view changes, and every word then unprojects to
## coordinates that mean nothing.
func _active_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport != null:
		var live := viewport.get_camera_3d()
		if live != null:
			return live
	return _camera if is_instance_valid(_camera) else null


func _process(delta: float) -> void:
	var camera: Camera3D = _active_camera()
	if camera == null:
		return
	# Snapshot — finished can mutate _active mid-loop.
	var snapshot: Array[ComicEffectLabel] = _active.duplicate()
	for label in snapshot:
		if label.is_alive():
			label.tick(delta, camera)
