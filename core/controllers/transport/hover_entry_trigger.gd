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
#
# BOARDING AND EXITING ARE HOLD-TO-CONFIRM (2026-08-28). A press starts the
# hold; the transition only runs once the key has been down for
# interact_hold_time. Getting into a vehicle by brushing a key is the one
# mis-press in this build that is expensive to undo, and this trigger is the
# only claimant in the project, so the claim contract carries the hold rather
# than InteractComponent — the threshold belongs to whoever decides, and
# InputSystems relays a duration and nothing else.
# =============================================================================

extends Area3D
class_name HoverEntryTrigger

enum State { IDLE, BOARDING, SEATED, EXITING }

@onready var _entry_light: AreaLight3D = $EntryLight

## Корень ховера. По умолчанию — родитель триггера.
@export var hover_path: NodePath = ^".."

## Длительность твина персонажа к двери, сек.
@export var boarding_duration: float = 0.45

## Порог скорости ховера (м/с), выше которого высадка запрещена.
## Пока hover_base не реализован, скорость считается нулевой.
@export var exit_speed_threshold: float = 0.5

## Сколько держать interact, чтобы сесть или выйти, сек. Порог живёт здесь,
## а не в InputSystems: решение принимает этот триггер, реле только сообщает
## длительность.
@export var interact_hold_time: float = 0.7

var _state: State = State.IDLE
var _hover: Node3D = null
var _player: Node3D = null            # игрок в зоне (IDLE) или на борту
var _door_anchor: Marker3D = null
var _controller: InputHoverController = null
## Удержание уже сработало — чтобы переход не запускался каждый кадр, пока
## клавиша всё ещё зажата.
var _hold_committed: bool = false
## Экранный prompt, ищется по группе и кэшируется. null — нормальное
## состояние: виджет только рисует, посадка работает и без него.
var _prompt: HoldPrompt = null
var _hud: HUDComponent = null

func _ready() -> void:
	_set_entry_light_enabled(false)
	_hover = get_node(hover_path)
	_door_anchor = _hover.get_node_or_null("DoorAnchor")
	if _door_anchor == null:
		push_error("[HoverEntryTrigger] У ховера '%s' нет Marker3D 'DoorAnchor'"
				% _hover.name)
				
	_controller = _hover.get_node_or_null("InputHoverController")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


# ── Зона двери ───────────────────────────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	if body == _hover:
		return   # собственный корпус ховера — не пассажир
	if _state != State.IDLE or not body is CharacterBody3D:
		return
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return
	_player = body
	_set_entry_light_enabled(true)
	InputSystems.claim_interact(self)
	## The affordance goes up on ARRIVAL, not on the first press. It used to
	## be raised inside on_interact_claimed(), which meant the door said
	## nothing at all until the player had already pressed F — measured
	## 2026-09-02 at the door: key claimed, no panel, no decal. Nothing else
	## in the build asks the player to guess that a key does something.
	_show_affordance()
	print("[HoverEntryTrigger] Игрок у двери '%s' — interact для посадки"
			% _hover.name)


func _on_body_exited(body: Node3D) -> void:
	if _state != State.IDLE or body != _player:
		return
	_player = null
	_set_entry_light_enabled(false)
	InputSystems.release_interact(self)
	_end_hold()
	_hide_affordance()
	print("[HoverEntryTrigger] Игрок отошёл от '%s'" % _hover.name)


# ── Маршрутизированный interact (вызывает InputSystems, не сигнал) ──────────

## Нажатие. Больше не выполняет переход — только начинает удержание.
func on_interact_claimed() -> void:
	if not _can_start_hold():
		return
	_hold_committed = false
	## The panel is already up (see _on_body_entered); the press only says the
	## hold has started. show_prompt() for the same anchor is a no-op, so the
	## entrance does not replay under the player's finger.
	_show_affordance()
	var prompt := _resolve_prompt()
	if prompt != null:
		prompt.set_holding(true)
		prompt.set_progress(0.0)


## Каждый кадр, пока клавиша зажата. Переход выполняется ровно один раз, при
## пересечении порога.
func on_interact_held(duration: float) -> void:
	if _hold_committed or not _can_start_hold():
		return
	var t: float = clampf(duration / maxf(interact_hold_time, 0.01), 0.0, 1.0)
	var prompt := _resolve_prompt()
	if prompt != null:
		prompt.set_progress(t)
	if t < 1.0:
		return

	_hold_committed = true
	match _state:
		State.IDLE:
			PlayerState.current_hover = _hover
			_begin_boarding()
		State.SEATED:
			_begin_exiting()
	_end_hold()
	## The offer is spent — the transition is running. This is the one place
	## the panel goes away without the player leaving the zone.
	_hide_affordance()


## Отпустили. Раньше порога — откат; после — уже ничего не значит.
func on_interact_released(_duration: float) -> void:
	if _hold_committed:
		_hold_committed = false
		return
	_end_hold()


## Удержание имеет смысл только в двух состояниях: у двери снаружи и сидя
## внутри. BOARDING/EXITING — переходы, их не прерываем.
func _can_start_hold() -> bool:
	if _state == State.IDLE:
		return _player != null
	return _state == State.SEATED


## Ends the HOLD, not the offer. The panel stays up while the player is still
## standing at the door — releasing the key early should roll the ring back,
## not take the door's label away.
func _end_hold() -> void:
	var prompt := _resolve_prompt()
	if prompt == null:
		return
	prompt.set_holding(false)
	prompt.set_progress(0.0)


## Both halves of "you can act here" — the decal on the ground and the key
## panel above it — raised and lowered together, so they can never disagree
## about whether the door is offering anything.
func _show_affordance() -> void:
	if _door_anchor == null or not _can_start_hold():
		return
	var prompt := _resolve_prompt()
	if prompt != null:
		prompt.show_prompt(_door_anchor)
	var hud := _resolve_hud()
	if hud != null:
		## in_reach: standing in the door zone IS the reach test here. There
		## is no walk-up phase to distinguish, the trigger volume is it.
		hud.show_candidate_at(_door_anchor, true)


func _hide_affordance() -> void:
	var prompt := _resolve_prompt()
	if prompt != null:
		prompt.hide_prompt()
	var hud := _resolve_hud()
	if hud != null:
		hud.hide_candidate()


func _resolve_hud() -> HUDComponent:
	if is_instance_valid(_hud):
		return _hud
	_hud = get_tree().get_first_node_in_group(
		HUDComponent.GROUP_HUD_COMPONENT
	) as HUDComponent
	return _hud


func _resolve_prompt() -> HoldPrompt:
	if is_instance_valid(_prompt):
		return _prompt
	_prompt = get_tree().get_first_node_in_group(
		HoldPrompt.GROUP_HOLD_PROMPT
	) as HoldPrompt
	return _prompt


# ── Посадка ──────────────────────────────────────────────────────────────────

func _begin_boarding() -> void:
	_state = State.BOARDING
	_set_entry_light_enabled(false)
	PlayerState.set_mode(PlayerState.Mode.HOVER)   # пеший ввод гаснет сразу
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
	if _controller: _controller.set_active(true)


# ── Высадка ──────────────────────────────────────────────────────────────────

func _begin_exiting() -> void:
	var v := (_hover as CharacterBody3D).velocity
	print("[exit] v=(%.2f, %.2f, %.2f)  on_floor=%s" % [v.x, v.y, v.z, str((_hover as CharacterBody3D).is_on_floor())])
	if _hover_speed() > exit_speed_threshold:
		print("[HoverEntryTrigger] ✖ Выход запрещён: скорость %.1f м/с"
				% _hover_speed())
		return

	_state = State.EXITING
	print("[HoverEntryTrigger] EXITING из '%s'" % _hover.name)
	if _controller: _controller.set_active(false)

	_player.global_position = _door_anchor.global_position
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_player.visible = true

	PlayerState.set_mode(PlayerState.Mode.ON_FOOT)
	PlayerState.current_hover = null
	_state = State.IDLE
	# Игрок стоит у двери — он всё ещё в Area, поэтому claim сохраняем:
	# повторный interact = снова посадка. Claim снимется в body_exited.
	print("[HoverEntryTrigger] ON_FOOT у '%s'" % _hover.name)


func _hover_speed() -> float:
	if _hover is CharacterBody3D:
		var v := (_hover as CharacterBody3D).velocity
		return Vector2(v.x, v.z).length()
	return 0.0
	
func _set_entry_light_enabled(enabled: bool) -> void:
	if _entry_light:
		_entry_light.visible = enabled
