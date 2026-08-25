# =============================================================================
# world_border_guard.gd — разворот у границы мира, как на границе карты в GTA.
#
# Владелец: world.gd, WORLD_SYSTEM_SCRIPTS. Следит за тем же anchor'ом, что и
# StreamingSystems._process() (пешком — игрок, в ховере — сам ховер): в
# пределах margin метров до истинной границы World Zone плавно доворачивает
# ЖЕЛАЕМОЕ направление движения анкора к центру — не саму velocity.
#
# ВАЖНО (урок первой версии): прямая запись в anchor.velocity отсюда ловила
# гонку с HoverBase._process_horizontal() — та каждый кадр читает текущую
# velocity и инерционно тянет её обратно к вводу игрока (см. move_toward к
# target_h, посчитанному из _intent_move). Обе системы писали в одно и то же
# свойство — визуально дрожь у границы, независимая от стриминга. Чинится тем
# же принципом, что уже есть в проекте: TPSMovementSystem не трогает
# player.gd.velocity напрямую, а зовёт set_direct_move_input() — подмешивает
# НАМЕРЕНИЕ, оставляя владельца физики единственным писателем скорости.
# Здесь то же самое: HoverBase.set_border_steering_bias() подмешивается в
# wish_dir до расчёта инерции внутри самого HoverBase.
#
# Потолок по Y (GAMEPLAY_HEIGHT) пока НЕ реализован — HoverBase._process_vertical()
# перезаписывает velocity.y с нуля каждый кадр из _intent_vertical/_hold_altitude,
# так что прямая правка отсюда была бы не гонкой, а чистым no-op (перетиралась
# бы молча). Нужен аналогичный intent-хук в _process_vertical() — не браться
# за него, пока не протестирован сценарий подлёта к потолку.
# =============================================================================
extends Node
class_name WorldBorderGuardSystem

## Начинаем доворачивать курс за столько метров до истинной границы (XZ).
@export var margin: float = 500.0

## Доля направления, доворачиваемая к центру у самой границы (0..1).
@export var max_turn_strength: float = 0.6

var _player: CharacterBody3D


func on_world_ready(context: WorldContext) -> void:
	_player = context.player


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	var anchor := _current_anchor()
	if anchor == null:
		return

	_apply_xz_bias(anchor)


## Тот же anchor-паттерн, что в StreamingSystems._process() — пешком игрок,
## в ховере сам ховер (капсула игрока на борту неподвижна).
func _current_anchor() -> CharacterBody3D:
	if is_instance_valid(PlayerState.current_hover):
		return PlayerState.current_hover as CharacterBody3D
	return _player


## Подмешивает намерение довернуть к центру — сама скорость не трогается,
## решение остаётся за HoverBase. У пешего игрока такого хука пока нет
## (приоритет тестирования — ховер); при отсутствии метода тихо ничего не
## делает, а не падает.
func _apply_xz_bias(anchor: CharacterBody3D) -> void:
	if not anchor.has_method("set_border_steering_bias"):
		return

	var pos := anchor.global_position
	var half := WorldSystems.WORLD_ZONE_SIZE * 0.5   # (1750, 1750) — край карты острова

	var turn := maxf(
			_edge_turn_strength(absf(pos.x), half.x),
			_edge_turn_strength(absf(pos.z), half.y))

	var to_center := Vector3(-pos.x, 0.0, -pos.z).normalized()
	anchor.set_border_steering_bias(to_center, turn)


## 0.0 вне margin, растёт линейно до max_turn_strength у самой границы extent.
func _edge_turn_strength(abs_value: float, extent: float) -> float:
	var edge_start := extent - margin
	if abs_value <= edge_start:
		return 0.0
	var t := (abs_value - edge_start) / margin
	return clampf(t, 0.0, 1.0) * max_turn_strength
