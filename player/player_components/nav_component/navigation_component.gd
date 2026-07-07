# NavigationComponent.gd
extends Node
class_name NavigationComponent

# --- Navigation Settings ---
@export var use_navigation: bool = true  # Включить/выключить навигацию
@export var navigation_region_path: NodePath
@export var waypoint_threshold: float = 0.15  # Расстояние для достижения точки

# --- Navigation Data ---
@onready var navigation_region: NavigationRegion3D = get_node_or_null(navigation_region_path)
var nav_map: RID
var navigation_path: PackedVector3Array = []
var current_path_index: int = 0

# --- Parent Reference ---
var parent_body: Node3D

# --- Signals ---
signal path_updated
signal destination_reached
signal waypoint_reached(index: int)

# --- Initialization ---
func _ready():
	parent_body = get_parent() as Node3D
	
	if not parent_body:
		push_error("NavigationComponent must be child of Node3D!")
		return
	
	# Только если навигация включена
	if use_navigation:
		# Wait for navigation to be ready
		await get_tree().process_frame
		_initialize_navigation()

# --- Setup Navigation Map ---
func _initialize_navigation() -> void:
	if not navigation_region or not navigation_region.is_inside_tree():
		push_warning("NavigationRegion3D not found - navigation disabled")
		use_navigation = false
		return
	
	var region_rid = navigation_region.get_rid()
	nav_map = NavigationServer3D.region_get_map(region_rid)
	
	if not nav_map.is_valid():
		push_warning("Navigation map RID is invalid - navigation disabled")
		use_navigation = false

# --- Public API ---
func set_target_position(target_pos: Vector3) -> void:
	if not parent_body:
		return
	
	# Если навигация выключена - прямое движение к цели
	if not use_navigation or not nav_map.is_valid():
		navigation_path = PackedVector3Array([target_pos])
		current_path_index = 0
		emit_signal("path_updated")
		return
	
	# Calculate path using NavigationServer3D
	navigation_path = NavigationServer3D.map_get_path(
		nav_map,
		parent_body.global_position,
		target_pos,
		true  # optimize path
	)
	
	current_path_index = 0
	
	if navigation_path.size() > 0:
		emit_signal("path_updated")
	else:
		push_warning("No valid path found to target position")

func clear_path() -> void:
	navigation_path.clear()
	current_path_index = 0

func has_active_path() -> bool:
	return current_path_index < navigation_path.size()

func get_next_point() -> Vector3:
	if not has_active_path():
		return Vector3.ZERO
	return navigation_path[current_path_index]

func advance_path() -> void:
	if not has_active_path():
		return
	
	emit_signal("waypoint_reached", current_path_index)
	current_path_index += 1
	
	if not has_active_path():
		emit_signal("destination_reached")

func get_remaining_distance() -> float:
	if not has_active_path() or not parent_body:
		return 0.0
	
	var total_distance = 0.0
	var current_pos = parent_body.global_position
	
	for i in range(current_path_index, navigation_path.size()):
		total_distance += current_pos.distance_to(navigation_path[i])
		current_pos = navigation_path[i]
	
	return total_distance

func get_path_progress() -> float:
	if navigation_path.size() <= 1:
		return 1.0
	
	return float(current_path_index) / float(navigation_path.size() - 1)

# --- Debug Helpers ---
func get_full_path() -> PackedVector3Array:
	return navigation_path

func get_current_waypoint_index() -> int:
	return current_path_index

func is_last_waypoint() -> bool:
	return current_path_index >= navigation_path.size() - 1

func is_navigation_enabled() -> bool:
	return use_navigation and nav_map.is_valid()
