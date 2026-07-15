# =============================================================================
# tps_shoulder_camera_state.gd
#
# Под-состояние TPS-камеры.
#
# Отвечает ТОЛЬКО за положение камеры относительно плеча игрока.
#
# НЕ знает:
#   - про Input;
#   - про PlayerState;
#   - про Camera3D;
#   - про CombatState.
#
# Хост (OnFootCameraComponent) сам вызывает toggle()/set_left()/set_right()
# и каждый кадр читает текущий shoulder_offset().
#
# Сейчас поддерживает:
#   • Left
#   • Right
#   • Плавный переход
#
# Позже можно добавить:
#   • Auto Shoulder
#   • Wall Avoidance
#   • Shoulder Bias
# =============================================================================

extends RefCounted
class_name TpsShoulderCameraState


enum ShoulderState {
	LEFT,
	RIGHT,
	TRANSITION
}


signal shoulder_changed(is_right: bool)


@export var right_offset: float = 0.45
@export var left_offset: float = -0.45

@export var transition_duration: float = 0.18


var state: ShoulderState = ShoulderState.RIGHT

var _pending_state: ShoulderState = ShoulderState.RIGHT
var _transition_from: ShoulderState = ShoulderState.RIGHT
var _transition_time: float = 0.0


# =============================================================================
# PUBLIC API
# =============================================================================

func toggle() -> void:

	if state == ShoulderState.TRANSITION:
		return

	if state == ShoulderState.RIGHT:
		set_left()
	else:
		set_right()


func set_left() -> void:

	if state == ShoulderState.LEFT:
		return

	_start_transition(ShoulderState.LEFT)


func set_right() -> void:

	if state == ShoulderState.RIGHT:
		return

	_start_transition(ShoulderState.RIGHT)


func is_right() -> bool:
	return state == ShoulderState.RIGHT


func is_left() -> bool:
	return state == ShoulderState.LEFT


# =============================================================================
# UPDATE
# =============================================================================

func update(delta: float) -> float:

	match state:

		ShoulderState.LEFT:
			return left_offset

		ShoulderState.RIGHT:
			return right_offset

		ShoulderState.TRANSITION:

			_transition_time += delta

			var t: float = clamp(
				_transition_time / transition_duration,
				0.0,
				1.0
			)

			var te: float = t * t * (3.0 - 2.0 * t)

			var from_offset: float = _offset_for(_transition_from)
			var to_offset: float = _offset_for(_pending_state)

			var result: float = lerp(
				from_offset,
				to_offset,
				te
			)

			if _transition_time >= transition_duration:

				state = _pending_state

				shoulder_changed.emit(
					state == ShoulderState.RIGHT
				)

			return result

	return right_offset


# =============================================================================
# INTERNAL
# =============================================================================

func _start_transition(to_state: ShoulderState) -> void:

	_transition_from = state
	_pending_state = to_state
	_transition_time = 0.0

	state = ShoulderState.TRANSITION


func _offset_for(s: ShoulderState) -> float:

	match s:

		ShoulderState.LEFT:
			return left_offset

		ShoulderState.RIGHT:
			return right_offset

		_:
			return right_offset
