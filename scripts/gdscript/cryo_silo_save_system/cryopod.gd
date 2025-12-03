## ============================================
## CRYOPOD.gd - Индивидуальная капсула
## ============================================
extends Node3D
class_name CryoPod

signal capsule_state_changed(is_open: bool, capsule_id: int)
signal player_entered_capsule(capsule_id: int)
signal player_exited_capsule(capsule_id: int)
signal player_detect_cryopod(player_in_interaction_zone: bool)

@onready var animation_player: AnimationPlayer = $anima
@onready var interaction_zone: Area3D = $InteractionZone
@onready var capsule_interior_zone: Area3D = $CapsuleInteriorZone

@export var capsule_id: int = 1  # ID капсулы (1, 2 или 3)
@export var ground_collision: CollisionShape3D

var is_open: bool = false
var player_inside: bool = false
var player_in_interaction_zone: bool = false

func _ready() -> void:
	is_open = false
	# Зона взаимодействия (снаружи капсулы)
	if interaction_zone:
		interaction_zone.body_entered.connect(_on_interaction_zone_entered)
		interaction_zone.body_exited.connect(_on_interaction_zone_exited)
		print("✅ Cryopod %d: Зона взаимодействия подключена" % capsule_id)
	
	# Зона внутри капсулы
	if capsule_interior_zone:
		capsule_interior_zone.body_entered.connect(_on_capsule_interior_entered)
		capsule_interior_zone.body_exited.connect(_on_capsule_interior_exited)
		print("✅ Cryopod %d: Внутренняя зона подключена" % capsule_id)

## === ОТКРЫТИЕ/ЗАКРЫТИЕ КАПСУЛЫ ===
func open_capsule() -> void:
	if is_open:
		return
	
	animation_player.play("open_cryopod")
	await animation_player.animation_finished
	is_open = true
	capsule_state_changed.emit(is_open, capsule_id)
	print("🔓 Капсула %d открыта" % capsule_id)

func close_capsule() -> void:
	if not is_open:
		return
	
	animation_player.play_backwards("open_cryopod")
	await animation_player.animation_finished
	is_open = false
	capsule_state_changed.emit(is_open, capsule_id)
	print("🔒 Капсула %d закрыта" % capsule_id)

func toggle_capsule() -> void:
	if is_open:
		await close_capsule()
	else:
		await open_capsule()

## === УПРАВЛЕНИЕ КОЛЛИЗИЕЙ ПОЛА ===
func disable_ground_collision() -> void:
	if ground_collision:
		ground_collision.set_deferred("disabled", true)
		print("🔽 Коллизия пола капсулы %d отключена" % capsule_id)

func enable_ground_collision() -> void:
	if ground_collision:
		ground_collision.set_deferred("disabled", false)
		print("🔼 Коллизия пола капсулы %d включена" % capsule_id)

## === СИГНАЛЫ ЗОНЫ ВЗАИМОДЕЙСТВИЯ ===
func _on_interaction_zone_entered(body: Node3D) -> void:
	if body.name == "Player":
		player_in_interaction_zone = true
		player_detect_cryopod.emit(player_in_interaction_zone)
		print("👤 Игрок в зоне взаимодействия капсулы %d" % capsule_id)

func _on_interaction_zone_exited(body: Node3D) -> void:
	if body.name == "Player":
		player_in_interaction_zone = false
		player_detect_cryopod.emit(player_in_interaction_zone)
		print("🚶 Игрок вышел из зоны взаимодействия капсулы %d" % capsule_id)

## === СИГНАЛЫ ВНУТРЕННЕЙ ЗОНЫ ===
func _on_capsule_interior_entered(body: Node3D) -> void:
	if body.name == "Player":
		player_inside = true
		player_entered_capsule.emit(capsule_id)
		print("🛏️ Игрок вошёл внутрь капсулы %d" % capsule_id)

func _on_capsule_interior_exited(body: Node3D) -> void:
	if body.name == "Player":
		player_inside = false
		player_exited_capsule.emit(capsule_id)
		print("🚪 Игрок вышел из капсулы %d" % capsule_id)
