# =============================================================================
# hover_entry_trigger.gd — HoverEntryTrigger.
#
# Посадка/высадка игрока в ховер. ОТДЕЛЬНАЯ система, не InteractComponent:
# триггер сам захватывает кнопку interact через InputSystems.claim_interact()
# пока игрок в зоне двери или сидит внутри — интеракт-компонент в это время
# сигнала не получает (маршрутизация — один владелец решения, без гонки
# подписчиков).
#
# СЦЕНА ХОВЕРА — ожидаемый контракт (маркеры добавляются в сцену ховера):
#   Hover (корень, позже — CharacterBody3D с hover_base.gd)
#   ├── HoverEntryTrigger (Area3D, этот скрипт) — зона у боковой двери,
#   │       слой 11 (TransportTriggers), маска 2 (Player)
#   ├── DoorAnchor   (Marker3D) — точка входа/выхода персонажа
#   ├── DoorSide     (Marker3D) — опорная точка дуги камеры (камера — позже)
#   └── CockpitAnchor(Marker3D) — камера первого лица (позже)
#
# FSM: IDLE → BOARDING → SEATED → EXITING → IDLE
#   BOARDING: mode=HOVER с первого кадра (пеший ввод гаснет сразу), твин
#             персонажа к DoorAnchor, затем скрытие внутрь ховера.
#   SEATED:   управление у input_hover_controller (когда появится).
#   EXITING:  только при почти нулевой скорости ховера; персонаж появляется
#             у DoorAnchor, mode=ON_FOOT.
# Посадки на ходу и выхода в полёте нет — жёстко на октябрь.
#
# Анимации персонажа нет намеренно: твин позиции — плейсхолдер под
# мокап-пайплайн. Вся индикация — консоль-лог (решение 2026-07-16).
# =============================================================================

extends Area3D
class_name HoverEntryTrigger

enum State { IDLE, BOARDING, SEATED, EXITING }

## Корень ховера. По умолчанию — родитель триггера.
@export var hover_path: NodePath = ^".."

## Длительность твина персонажа к двери, сек.
@export var boarding_duration: float = 0.45

## Порог скорости ховера (м/с), выше которого высадка запрещена.
## Пока hover_base не реализован, скорость считается нулевой.
@export var exit_speed_threshold: float = 0.5

var _state: State = State.IDLE
var _hover: Node3D = null
var _player: Node3D = null            # игрок в зоне (IDLE) или на борту
var _door_anchor: Marker3D = null


func _ready() -> void:
	_hover = get_node(hover_path)
	_door_anchor = _hover.get_node_or_null("DoorAnchor")
	if _door_anchor == null:
		push_error("[HoverEntryTrigger] У ховера '%s' нет Marker3D 'DoorAnchor'"
				% _hover.name)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


# ── Зона двери ───────────────────────────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	if _state != State.IDLE or not body is CharacterBody3D:
		return
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return
	_player = body
	InputSystems.claim_interact(self)
	print("[HoverEntryTrigger] Игрок у двери '%s' — interact для посадки"
			% _hover.name)


func _on_body_exited(body: Node3D) -> void:
	if _state != State.IDLE or body != _player:
		return
	_player = null
	InputSystems.release_interact(self)
	print("[HoverEntryTrigger] Игрок отошёл от '%s'" % _hover.name)


# ── Маршрутизированный interact (вызывает InputSystems, не сигнал) ──────────

func on_interact_claimed() -> void:
	match _state:
		State.IDLE:
			if _player != null:
				_begin_boarding()
		State.SEATED:
			_begin_exiting()
		_:
			pass   # BOARDING/EXITING — переходы не прерываем


# ── Посадка ──────────────────────────────────────────────────────────────────

func _begin_boarding() -> void:
	_state = State.BOARDING
	PlayerState.mode = PlayerState.Mode.HOVER   # пеший ввод гаснет сразу
	print("[HoverEntryTrigger] BOARDING → '%s'" % _hover.name)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_player, "global_position",
			_door_anchor.global_position, boarding_duration)
	tween.tween_callback(_finish_boarding)


func _finish_boarding() -> void:
	# Персонаж "внутри": скрыт и полностью выключен до высадки.
	_player.visible = false
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_state = State.SEATED
	print("[HoverEntryTrigger] SEATED в '%s' — interact для выхода" % _hover.name)
	# TODO(hover_base): передать управление input_hover_controller.


# ── Высадка ──────────────────────────────────────────────────────────────────

func _begin_exiting() -> void:
	if _hover_speed() > exit_speed_threshold:
		print("[HoverEntryTrigger] ✖ Выход запрещён: скорость %.1f м/с"
				% _hover_speed())
		return

	_state = State.EXITING
	print("[HoverEntryTrigger] EXITING из '%s'" % _hover.name)
	# TODO(hover_base): забрать управление у input_hover_controller.

	_player.global_position = _door_anchor.global_position
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_player.visible = true

	PlayerState.mode = PlayerState.Mode.ON_FOOT
	_state = State.IDLE
	# Игрок стоит у двери — он всё ещё в Area, поэтому claim сохраняем:
	# повторный interact = снова посадка. Claim снимется в body_exited.
	print("[HoverEntryTrigger] ON_FOOT у '%s'" % _hover.name)


func _hover_speed() -> float:
	if _hover is CharacterBody3D:
		return (_hover as CharacterBody3D).velocity.length()
	return 0.0   # болванка без hover_base неподвижна
