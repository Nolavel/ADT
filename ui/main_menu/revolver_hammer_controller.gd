# =============================================================================
# revolver_hammer_controller.gd
# ## RU: Курок барабана. Тянешь и отпускаешь — курок бьёт по каморе на фронте.
#        Направление броска не учитывается: цель одна и она всегда одна и та же
#        точка — фронт барабана. Поэтому это НЕ DragHandleController: тот
#        выбирает из неподвижной россыпи целей по направлению толчка, здесь
#        выбирать не из чего, и половина его кода была бы мёртвой.
# ## ENG: Revolver hammer. Pull and release — it strikes the front chamber.
#         Throw direction is ignored: there is exactly one destination, the
#         front of the drum. Hence a dedicated controller rather than
#         DragHandleController, whose target-picking would be dead code here.
#
# Куда лететь — спрашивает снаружи через Callable, чтобы не знать ни про
# барабан, ни про камору.
#
# Morph (optional): a MorphIcon parented under the hammer, driven from Phase:
#   IDLE / RETURNING  → LINE
#   PULLED / STRIKING → CIRCLE
# Typed against the MorphIcon base, never a concrete morph — a second morph
# is a new script under ui/widgets/morphs/ and nothing here changes.
# =============================================================================
extends Node
class_name RevolverHammerController

## RU: Курок взят в руку.
signal pulled()
## RU: Жест дотянул до зачёта (или перестал дотягивать). По нему камора
##     показывает, встретит она курок или нет.
signal aim_changed(valid: bool)
## RU: Курок долетел до каморы. Выстрел вешать сюда.
signal struck()
## Emitted whenever the internal phase changes.
signal phase_changed(phase: int)

## RU: Минимальный путь курка от дома, px. Короче — жеста не было,
##     курок возвращается домой и не стреляет.
@export var min_travel: float = 45.0
## RU: Насколько точно тянуть в сторону каморы. Это dot направлений:
##     1.0 — строго в неё, 0.0 — любое перпендикулярное, −1.0 — куда угодно.
##     0.25 ≈ конус ±75°.
@export var aim_cone_dot: float = 0.25

## RU: Время полёта до каморы, сек / ENG: flight time to the chamber, sec
@export var strike_time: float = 0.22
## RU: Пауза на попадании до возврата домой, сек
@export var hold_time: float = 0.10
## RU: Время возврата на исходное место, сек
@export var return_time: float = 0.30

enum Phase { IDLE, PULLED, STRIKING, RETURNING }

var hammer: Button
## Optional morph icon. Null is the normal, silent case.
var morph: MorphIcon = null

var _phase: int = Phase.IDLE
var _home: Vector2 = Vector2.ZERO
var _grab_offset: Vector2 = Vector2.ZERO
## RU: Откуда начали тянуть, в глобальных координатах.
var _pull_start: Vector2 = Vector2.ZERO
var _aim_valid: bool = false
var _locked: bool = false
## RU: Возвращает глобальный центр каморы, по которой бить.
var _destination: Callable = Callable()


func setup(p_hammer: Button, p_destination: Callable, p_morph: MorphIcon = null) -> void:
	hammer = p_hammer
	_destination = p_destination
	morph = p_morph
	_home = hammer.position
	hammer.button_down.connect(_on_hammer_down)
	hammer.button_up.connect(_on_hammer_up)
	_sync_morph()


## RU: Перезахват домашней точки. Звать при ресайзе окна: курок закреплён
##     якорями по центру экрана, его дом уезжает вместе с окном. В полёте и
##     в руке не трогаем — иначе дом сползёт на текущую позицию курка.
## ENG: Re-capture the home point on window resize. Ignored while the hammer
##      is held or flying, otherwise home would drift to its current position.
func capture_home() -> void:
	if _phase == Phase.IDLE and hammer != null:
		_home = hammer.position


func _process(_delta: float) -> void:
	if _phase != Phase.PULLED:
		return
	hammer.global_position = hammer.get_global_mouse_position() - _grab_offset

	## RU: Пересчитываем зачёт каждый кадр, чтобы игрок ВИДЕЛ, выстрелит
	##     отпускание или нет, а не узнавал об этом после.
	var valid: bool = _gesture_valid()
	if valid != _aim_valid:
		_aim_valid = valid
		aim_changed.emit(valid)


func is_busy() -> bool:
	return _phase != Phase.IDLE


func set_locked(value: bool) -> void:
	_locked = value
	if hammer != null:
		hammer.disabled = value


func get_phase() -> int:
	return _phase


# -----------------------------------------------------------------------------

func _on_hammer_down() -> void:
	if _locked or _phase != Phase.IDLE:
		return
	_set_phase(Phase.PULLED)
	_grab_offset = hammer.get_global_mouse_position() - hammer.global_position
	_pull_start = hammer.global_position
	_aim_valid = false
	hammer.z_index = 100
	pulled.emit()


## RU: Отпускание стреляет ТОЛЬКО если жест состоялся: курок протянули
##     достаточно далеко и в сторону каморы. Просто клик по курку — не выстрел.
##     Это единственное место с проверкой: клавиатурный путь идёт через
##     strike() напрямую, там жест проигрывается автоматически и проверять
##     нечего.
func _on_hammer_up() -> void:
	if _phase != Phase.PULLED:
		return

	if _gesture_valid():
		strike()
		return

	## RU: Жеста не было — курок возвращается домой, камора остаётся ждать.
	_set_phase(Phase.RETURNING)
	_aim_valid = false
	aim_changed.emit(false)
	await _return_home()
	_set_phase(Phase.IDLE)
	hammer.z_index = 0


## RU: Путь достаточной длины И в сторону каморы.
func _gesture_valid() -> bool:
	if not _destination.is_valid():
		return false
	var travel: Vector2 = hammer.global_position - _pull_start
	if travel.length() < min_travel:
		return false
	var to_dest: Vector2 = _destination.call() - hammer.get_global_rect().get_center()
	if to_dest.length() < 1.0:
		return true
	return travel.normalized().dot(to_dest.normalized()) >= aim_cone_dot


## RU: Ударить по каморе. Тот же путь для руки и для клавиши — клавиша не
##     обходит механику, а проигрывает жест за игрока.
## ENG: Strike the chamber. Same path for hand and keyboard — the key does not
##      bypass the mechanic, it performs the gesture for the player.
func strike() -> void:
	if _phase == Phase.STRIKING:
		return
	if not _destination.is_valid():
		push_error("RevolverHammerController: не задан Callable назначения.")
		return

	_set_phase(Phase.STRIKING)
	_aim_valid = false
	hammer.disabled = true

	var dest: Vector2 = _destination.call() - hammer.size * 0.5
	var tw: Tween = hammer.create_tween()
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(hammer, "global_position", dest, strike_time)
	await tw.finished

	struck.emit()

	await hammer.get_tree().create_timer(hold_time).timeout
	_set_phase(Phase.RETURNING)
	await _return_home()

	_set_phase(Phase.IDLE)
	hammer.z_index = 0
	hammer.disabled = _locked


func _return_home() -> void:
	var tw: Tween = hammer.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(hammer, "position", _home, return_time)
	await tw.finished


# -----------------------------------------------------------------------------
# ## ENG: Phase + morph sync
# -----------------------------------------------------------------------------

func _set_phase(p: int) -> void:
	if p == _phase:
		return
	_phase = p
	phase_changed.emit(_phase)
	_sync_morph()


func _sync_morph() -> void:
	if morph == null:
		return
	match _phase:
		Phase.PULLED, Phase.STRIKING:
			morph.to_circle()
		_:
			morph.to_line()
