# =============================================================================
# world_border_guard.gd — разворот у границы мира, как на границе карты в GTA.
#
# Владелец: world.gd, WORLD_SYSTEM_SCRIPTS. Следит за тем же anchor'ом, что и
# StreamingSystems._process() (пешком — игрок, в ховере — сам ховер): в
# пределах margin метров до истинной границы World Zone плавно доворачивает
# горизонтальную скорость анкора обратно к центру, сила растёт по мере
# приближения к самой границе — не жёсткая стена, а мягкая коррекция курса.
# Аналогично — потолок по Y (GAMEPLAY_HEIGHT): гасит/разворачивает вертикальную
# скорость, если анкор поднимается слишком высоко.
#
# Приоритет тестирования — ховер (см. рабочие заметки проекта); пеший игрок
# получает ту же логику бесплатно за счёт общего anchor-паттерна, но
# практически до границы дойти пешком почти нереально (буфер 1500м между
# городом и краем мира).
# =============================================================================
extends Node
class_name WorldBorderGuardSystem

## Начинаем доворачивать курс за столько метров до истинной границы (и XZ, и Y).
@export var margin: float = 500.0

## Доля скорости, направляемая к центру/вниз у самой границы (0..1).
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

	_apply_xz_turn(anchor)
	_apply_ceiling_turn(anchor)


## Тот же anchor-паттерн, что в StreamingSystems._process() — пешком игрок,
## в ховере сам ховер (капсула игрока на борту неподвижна).
func _current_anchor() -> CharacterBody3D:
	if is_instance_valid(PlayerState.current_hover):
		return PlayerState.current_hover as CharacterBody3D
	return _player


func _apply_xz_turn(anchor: CharacterBody3D) -> void:
	var pos := anchor.global_position
	var half := WorldSystems.WORLD_ZONE_SIZE * 0.5   # (4800, 4800)

	var turn := maxf(
			_edge_turn_strength(absf(pos.x), half.x),
			_edge_turn_strength(absf(pos.z), half.y))
	if turn <= 0.0:
		return

	var horizontal := Vector3(anchor.velocity.x, 0.0, anchor.velocity.z)
	var speed := horizontal.length()
	if speed < 0.01:
		return

	var current_dir := horizontal / speed
	var to_center := Vector3(-pos.x, 0.0, -pos.z).normalized()
	var blended := current_dir.lerp(to_center, turn).normalized()

	anchor.velocity.x = blended.x * speed
	anchor.velocity.z = blended.z * speed


## Потолок односторонний (пол уже держит физическая коллизия, страта Y=0
## границей "мира" в смысле разворота не является) — гасим только подъём.
func _apply_ceiling_turn(anchor: CharacterBody3D) -> void:
	if anchor.velocity.y <= 0.0:
		return

	var turn := _edge_turn_strength(anchor.global_position.y, WorldSystems.GAMEPLAY_HEIGHT)
	if turn <= 0.0:
		return

	anchor.velocity.y = lerpf(anchor.velocity.y, 0.0, turn)


## 0.0 вне margin, растёт линейно до max_turn_strength у самой границы extent.
func _edge_turn_strength(abs_value: float, extent: float) -> float:
	var edge_start := extent - margin
	if abs_value <= edge_start:
		return 0.0
	var t := (abs_value - edge_start) / margin
	return clampf(t, 0.0, 1.0) * max_turn_strength
