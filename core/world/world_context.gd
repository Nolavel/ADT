# =============================================================================
# world_context.gd
#
# Простой набор общих ссылок (player/camera/stream_container), который
# world.gd строит один раз после спавна игрока и камеры, и раздаёт всем
# "мировым системам" через единый метод on_world_ready(context).
#
# ВАЖНО — что это НЕ: это не про контент мира (башни/зоны/стриминг), тем
# занимается StreamingSystems (autoload) — грузит/выгружает BlockData по
# дистанции от игрока, это отдельный, уже существующий и не связанный с
# этим файлом механизм. WorldContext — исключительно про то, как игровые
# системы (ClickToMoveSystem, TPSMovementSystem, MenuSystem,
# ZoomRulerSystem и все следующие) получают нужные им ссылки при старте,
# без ручного набора register_player()/register_camera() на каждую
# систему в world.gd.
# =============================================================================
class_name WorldContext
extends RefCounted

var player: Node3D
var camera: Camera3D
var stream_container: Node3D

## Все уже созданные системы из WORLD_SYSTEM_SCRIPTS — на случай, если
## 3D/UI-сцене нужна конкретная система (например HUD нужен ClickToMoveSystem
## для setup()), а не только player/camera/stream_container.
var systems: Array[Node] = []


func get_system(system_script: GDScript) -> Node:
	for s in systems:
		if is_instance_of(s, system_script):
			return s
	return null
