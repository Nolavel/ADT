# =============================================================================
# hover_base.gd — HoverBase, базовое движение всего hover-транспорта.
#
# CharacterBody3D намеренно (решение 2026-07: RigidBody3D показал статтеры
# и плохую физику на целевом железе). Вся "физика" — кинематическая
# псевдофизика: инерция через lerp к целевой скорости, yaw со сглаживанием,
# визуальный крен корпуса без влияния на коллизии.
#
# ВЕРТИКАЛЬ — полуавтомат ("игроку проще простого"):
#   • hover_up / hover_down удерживаются — набор/сброс высоты;
#   • отпущены — текущая высота удерживается автоматически (без дрейфа),
#     игрок КОРРЕКТИРУЕТ высоту, а не борется с ней.
#
# РАЗДЕЛЕНИЕ ОТВЕТСТВЕННОСТИ:
#   hover_base        — только движение; откуда пришли намерения, не знает.
#   input_hover_controller — читает намерения игрока из InputSystems.
#   ai_hover_controller    — позже, тот же интерфейс set_move_intent()
#                            (условие NPC-трафика к вертикальному срезу).
#
# Контроллер каждый кадр вызывает set_move_intent(); если не вызвал —
# намерения затухают (intent сбрасывается), ховер плавно останавливается.
# =============================================================================

extends CharacterBody3D
class_name HoverBase

@export_group("Horizontal")
## Максимальная горизонтальная скорость, м/с.
@export var max_speed: float = 30.0
## Разгон, м/с². Ниже max — ощущение массы.
@export var acceleration: float = 18.0
## Торможение при отсутствии ввода, м/с² (сильнее разгона — отзывчивый стоп).
@export var braking: float = 26.0

@export_group("Turning")
## Скорость доворота корпуса к направлению движения, рад/с.
@export var yaw_speed: float = 2.2

@export_group("Vertical")
## Скорость набора/сброса высоты, м/с.
@export var vertical_speed: float = 12.0
## Жёсткость удержания высоты (1/с): выше — резче возврат к удерживаемой.
@export var altitude_hold_stiffness: float = 4.0

@export_group("Visual")
## Меш корпуса для визуального крена (не коллизия). Опционально.
@export var body_mesh_path: NodePath
## Максимальный крен в повороте, рад.
@export var max_bank_angle: float = 0.35

## Намерения текущего кадра. move: x=вправо, y=вперёд, в диапазоне [-1..1];
## vertical: [-1..1] (вверх/вниз), 0 = удержание высоты.
var _intent_move: Vector2 = Vector2.ZERO
var _intent_vertical: float = 0.0
var _intent_fresh: bool = false

## Управляет ли кто-то ховером (триггер включает на SEATED).
var _controlled: bool = false

var _hold_altitude: float = 0.0
var _body_mesh: Node3D = null


func _ready() -> void:
	_hold_altitude = global_position.y
	if body_mesh_path != NodePath():
		_body_mesh = get_node_or_null(body_mesh_path)


## Интерфейс контроллеров (input_* и позже ai_*). Вызывать каждый кадр.
func set_move_intent(move: Vector2, vertical: float) -> void:
	_intent_move = move.limit_length(1.0)
	_intent_vertical = clampf(vertical, -1.0, 1.0)
	_intent_fresh = true


func set_controlled(controlled: bool) -> void:
	_controlled = controlled
	if controlled:
		_hold_altitude = global_position.y   # не дёргаться к старой высоте
	else:
		_intent_move = Vector2.ZERO
		_intent_vertical = 0.0


func _physics_process(delta: float) -> void:
	if not _intent_fresh:
		_intent_move = Vector2.ZERO
		_intent_vertical = 0.0
	_intent_fresh = false

	_process_horizontal(delta)
	_process_vertical(delta)
	move_and_slide()
	_process_banking(delta)


# ── Горизонталь: инерция ─────────────────────────────────────────────────────

func _process_horizontal(delta: float) -> void:
	# Намерение в локальных осях корпуса → мировое направление.
	var forward := -global_transform.basis.z
	var right   :=  global_transform.basis.x
	var wish_dir := (forward * _intent_move.y + right * _intent_move.x)
	wish_dir.y = 0.0

	var target_h := wish_dir.normalized() * max_speed * wish_dir.length() \
			if wish_dir.length() > 0.01 else Vector3.ZERO

	var current_h := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target_h.length() > current_h.length() else braking
	current_h = current_h.move_toward(target_h, rate * delta)

	velocity.x = current_h.x
	velocity.z = current_h.z

	# Корпус доворачивается к направлению движения (не мгновенно).
	if current_h.length() > 1.0:
		var target_yaw := atan2(-current_h.x, -current_h.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, yaw_speed * delta)


# ── Вертикаль: полуавтомат ───────────────────────────────────────────────────

func _process_vertical(delta: float) -> void:
	if absf(_intent_vertical) > 0.01:
		velocity.y = _intent_vertical * vertical_speed
		_hold_altitude = global_position.y + velocity.y * delta
	else:
		# Удержание: демпфированный возврат к _hold_altitude, без дрейфа.
		var error := _hold_altitude - global_position.y
		velocity.y = error * altitude_hold_stiffness


# ── Визуальный крен ──────────────────────────────────────────────────────────

func _process_banking(delta: float) -> void:
	if _body_mesh == null:
		return
	var target_bank := -_intent_move.x * max_bank_angle
	_body_mesh.rotation.z = lerpf(_body_mesh.rotation.z, target_bank, 6.0 * delta)
