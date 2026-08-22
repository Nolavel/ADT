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
# Default defs cover H4 witness / reaction vocabulary (knockdown, freeze,
# flee, call, death). Register more via register_def() or replace the seed
# list with a Resource load later — the seed exists so the system is useful
# the frame it is added, without a data-file dependency on day one.
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
## Above typical HUD layers (world.gd UI canvas uses 40).
const CANVAS_LAYER_INDEX: int = 45

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
	_camera = context.camera
	_build_layer()
	_build_pool()
	_load_default_defs()


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
	label.setup(text, def.color, def.font_size, def.duration, def.rise_px)
	if is_instance_valid(follow):
		label.set_follow(follow, DEFAULT_OFFSET)
	else:
		label.set_world_source(world_pos, DEFAULT_OFFSET)

	if not label.finished.is_connected(_on_label_finished):
		label.finished.connect(_on_label_finished)
	_active.append(label)


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
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		label.add_theme_constant_override("outline_size", 4)
		_pool.append(label)
		call_deferred("_attach_label", label)


func _attach_label(label: ComicEffectLabel) -> void:
	if _layer != null and is_instance_valid(_layer) and label.get_parent() == null:
		_layer.add_child(label)


func _load_default_defs() -> void:
	# H4 reaction vocabulary. Short, low-exclamation — closer to noir than
	# Scott-Pilgrim onomatopoeia. Tune texts in place or replace with a
	# Resource load later.
	_register_simple(
		&"npc_knockdown",
		PackedStringArray(["THUD", "DOWN", "FLOP"]),
		Color(0.92, 0.78, 0.55, 1.0),
		28, 0.85, 22.0
	)
	_register_simple(
		&"npc_hit",
		PackedStringArray(["OOF", "UGH", "GHH"]),
		Color(0.90, 0.70, 0.50, 1.0),
		24, 0.65, 18.0
	)
	_register_simple(
		&"npc_death",
		PackedStringArray(["…", "SILENCE"]),
		Color(0.70, 0.72, 0.78, 1.0),
		24, 1.1, 18.0
	)
	_register_simple(
		&"npc_freeze",
		PackedStringArray(["…", "STARE", "HUH"]),
		Color(0.82, 0.88, 0.95, 1.0),
		24, 0.9, 22.0
	)
	_register_simple(
		&"npc_flee",
		PackedStringArray(["RUN", "AAH", "NO"]),
		Color(0.95, 0.82, 0.45, 1.0),
		28, 0.85, 24.0
	)
	_register_simple(
		&"npc_call",
		PackedStringArray(["CALL", "REPORT"]),
		Color(0.55, 0.78, 0.95, 1.0),
		26, 1.0, 26.0
	)
	_register_simple(
		&"npc_transmit",
		PackedStringArray(["…", "SIGNAL"]),
		Color(0.50, 0.80, 0.95, 1.0),
		22, 0.8, 26.0
	)


func _register_simple(
		id: StringName,
		texts: PackedStringArray,
		color: Color,
		font_size: int,
		duration: float,
		radius: float
	) -> void:
	var def := ComicEffectDef.new()
	def.id = id
	def.texts = texts
	def.color = color
	def.font_size = font_size
	def.duration = duration
	def.radius = radius
	_defs[id] = def


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
		pick = _pick_weighted(candidates, def, last)
	else:
		pick = candidates[randi() % candidates.size()]

	_last_text_by_id[def.id] = pick
	return pick


func _pick_weighted(candidates: PackedStringArray, def: ComicEffectDef, last: String) -> String:
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


func _process(delta: float) -> void:
	if _camera == null:
		return
	# Snapshot — finished can mutate _active mid-loop.
	var snapshot: Array[ComicEffectLabel] = _active.duplicate()
	for label in snapshot:
		if label.is_alive():
			label.tick(delta, _camera)
