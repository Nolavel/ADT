# =============================================================================
# hover_camera_component.gd — HoverCameraComponent.
#
# Компонент камеры для PlayerState.Mode.HOVER. Хост — camera_follow
# (вызывает setup/enter/exit/update, кладёт shake ПОВЕРХ — см. хост).
#
# ДВА ПОД-РЕЖИМА (внутри компонента, не в FSM хоста):
#   CHASE   — за кормой: пружина дистанции, лаг поворота, FOV от скорости.
#   COCKPIT — первое лицо у переднего края, якорь CockpitAnchor на сцене
#             ховера, взгляд вдоль носа (−Z корпуса).
# Переключение — V (toggle_view), тот же жест, что ISOMETRIC↔TPS пешком.
# Выбранный под-режим ПЕРСИСТЕНТЕН между посадками: хранится в
# PlayerState.hover_camera_view (состояние игрока, не камеры — компонент
# пересоздаваем/переключаем, поле переживает выход-вход).
#
# ВХОД (enter): дуга от текущей позиции камеры через боковую опорную точку
# DoorSide — камера "залетает" в ховер сбоку (через дверь), не по прямой.
#
# КОНТРАКТ СЦЕНЫ ХОВЕРА (Marker3D): DoorSide, CockpitAnchor. Отсутствуют —
# компонент деградирует без ошибок: дуга → прямой лерп, COCKPIT → CHASE.
#
# Конвенция осей: нос ховера = локальный −Z (как в hover_base).
# =============================================================================
extends Node
class_name HoverCameraComponent

enum HoverView { CHASE, COCKPIT }

@export_group("Chase")
## Смещение за кормой в локальных осях ховера (+Z = назад от носа).
@export var chase_offset: Vector3 = Vector3(0.0, 3.0, 8.0)
## Жёсткость пружины позиции, 1/с.
@export var chase_stiffness: float = 5.0
## Лаг поворота за корпусом, 1/с (ниже жёсткости позиции — кинематографично).
@export var chase_yaw_lag: float = 3.5

@export_group("FOV")
@export var fov_base: float = 70.0
## Прибавка FOV на максимальной скорости ховера.
@export var fov_speed_kick: float = 12.0
@export var fov_lerp_speed: float = 4.0

@export_group("Boarding arc")
## Длительность дуги входа камеры, сек.
@export var arc_duration: float = 0.6

var camera: Camera3D
var target: Node3D            # корень ховера (HoverBase), назначает хост

var _arc_time: float = -1.0   # < 0 — дуга не играет
var _arc_from: Transform3D
var _door_side: Marker3D = null
var _cockpit: Marker3D = null


func setup() -> void:
	pass


func enter() -> void:
	_door_side = target.get_node_or_null("DoorSide") if target else null
	_cockpit  = target.get_node_or_null("CockpitAnchor") if target else null
	# Дуга стартует с фактической позиции камеры (где её оставил пеший режим).
	_arc_from = camera.global_transform
	_arc_time = 0.0


func exit() -> void:
	_arc_time = -1.0
	camera.fov = fov_base


func update(delta: float) -> void:
	if target == null:
		return

	var goal := _desired_transform()

	if _arc_time >= 0.0:
		_update_boarding_arc(delta, goal)
		return

	match _current_view():
		HoverView.COCKPIT:
			# Жёсткая привязка: кабина не "плывёт" относительно корпуса.
			camera.global_transform = goal
		HoverView.CHASE:
			camera.global_position = camera.global_position.lerp(
					goal.origin, 1.0 - exp(-chase_stiffness * delta))
			camera.global_transform.basis = camera.global_transform.basis.slerp(
					goal.basis, 1.0 - exp(-chase_yaw_lag * delta))

	_update_fov(delta)
	_handle_view_toggle()


# ── Целевая трансформация текущего под-режима ────────────────────────────────

func _current_view() -> HoverView:
	# COCKPIT без якоря невозможен — деградация в CHASE.
	if PlayerState.hover_camera_view == HoverView.COCKPIT and _cockpit != null:
		return HoverView.COCKPIT
	return HoverView.CHASE


func _desired_transform() -> Transform3D:
	if _current_view() == HoverView.COCKPIT:
		return _cockpit.global_transform

	# CHASE: позиция за кормой в осях корпуса, взгляд на корпус.
	var pos: Vector3 = target.global_transform * chase_offset
	var t := Transform3D(Basis.IDENTITY, pos)
	return t.looking_at(target.global_position + Vector3.UP * 1.0, Vector3.UP)


# ── Дуга посадки ─────────────────────────────────────────────────────────────

func _update_boarding_arc(delta: float, goal: Transform3D) -> void:
	_arc_time += delta
	var t := clampf(_arc_time / arc_duration, 0.0, 1.0)
	var eased := ease(t, -2.0)   # ease in-out

	var pos := _arc_from.origin.lerp(goal.origin, eased)
	if _door_side != null:
		# Квадратичный Безье через боковую точку — "залёт" через дверь.
		var mid := _door_side.global_position
		var a := _arc_from.origin.lerp(mid, eased)
		var b := mid.lerp(goal.origin, eased)
		pos = a.lerp(b, eased)

	camera.global_position = pos
	camera.global_transform.basis = _arc_from.basis.slerp(goal.basis, eased)

	if t >= 1.0:
		_arc_time = -1.0


# ── FOV и переключение ──────────────────────────────────────────────────────

func _update_fov(delta: float) -> void:
	var speed_ratio := 0.0
	if target is HoverBase:
		var hover := target as HoverBase
		speed_ratio = clampf(
				Vector2(hover.velocity.x, hover.velocity.z).length()
						/ hover.max_speed, 0.0, 1.0)
	# FOV-kick только в CHASE: в кабине дыхание FOV мешает.
	var goal_fov := fov_base
	if _current_view() == HoverView.CHASE:
		goal_fov += fov_speed_kick * speed_ratio
	camera.fov = lerpf(camera.fov, goal_fov, fov_lerp_speed * delta)


func _handle_view_toggle() -> void:
	if not InputSystems.is_toggle_view_just_pressed():
		return
	PlayerState.hover_camera_view = HoverView.COCKPIT \
			if PlayerState.hover_camera_view == HoverView.CHASE \
			else HoverView.CHASE
	print("[HoverCamera] Вид: %s"
			% ("COCKPIT" if PlayerState.hover_camera_view == HoverView.COCKPIT
			   else "CHASE"))
