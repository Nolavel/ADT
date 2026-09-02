# =============================================================================
# dynamic_cursor_ui.gd — MouseCursorUI.
#
# One job: say what the player is aimed at. Nothing else.
#
# It used to say two things at once — what is under the cursor AND how much
# stamina is left, with arcs, recovery rings, a jump charge and walk/sprint
# icons all stacked on the same few pixels. Aiming is a fast, precise read;
# stamina is a slow, ambient one, and stacked together the aiming half loses.
# All of the stamina and movement visuals moved out — first to a ring on the
# ground (StaminaIndicator3D), then, when that turned out to draw through the
# character it was under, into the HUD as StaminaGauge. This file no longer
# references StaminaComponent at all.
#
# Three states, and that is the whole vocabulary:
#
#   nothing under it   dim grey ring
#   NPC or item        the same ring, brightened
#   firearm in hand    brackets instead of a ring, breathing with speed
#
# The brackets are [ ✛ ] — spine outwards, tips toward the target. They open
# as the character moves and close as they settle, driven by a spring off the
# REAL speed rather than off is_running, so the movement reads as continuous
# rather than as two states.
#
# Dependencies: PlayerState (mode), the player (parent — speed, and
# get_drawn_firearm() for the bracket state).
# =============================================================================
extends Control
class_name MouseCursorUI

signal button_3d_clicked(button_name: String)

## Lookup group, so AimReticle can ask whether this cursor is already the aim
## without either widget being able to name the other by path.
const GROUP_MOUSE_CURSOR: StringName = &"mouse_cursor_ui"

## Half-angle each bracket arc covers, radians. The pair reads as ( ✛ ) —
## curved, convex side away from the target, tips pointing at it.
const BRACKET_ARC_HALF_ANGLE: float = 0.62
## Straight segments the arc is built from. Enough to read as a curve at the
## sizes this is drawn, few enough that six of them cost nothing.
const BRACKET_ARC_SEGMENTS: int = 10

# === НАСТРОЙКИ КУРСОРА ===
@export_group("Основной курсор")
@export var cursor_radius: float = 8.0
@export var cursor_thickness: float = 2.0
## Ничего под курсором — приглушённый серый.
@export var cursor_color_idle: Color = Color(0.62, 0.64, 0.66, 0.75)
## Под курсором NPC или предмет.
@export var cursor_color_target: Color = Color(1.0, 1.0, 1.0, 0.95)
## Скорость перехода между ними. Не мгновенно: подсветка, появляющаяся
## рывком, читается как мигание, а не как отклик.
@export var cursor_color_speed: float = 10.0

@export_group("Прицельные скобки")
## Смещение скобок от центра, когда персонаж стоит.
@export var bracket_offset_min: float = 10.0
## ...и когда бежит во весь опор.
@export var bracket_offset_max: float = 34.0
@export var bracket_width: float = 8.0
@export var bracket_height: float = 20.0
@export var bracket_color: Color = Color(0.3, 0.8, 1.0, 0.9)
## Пружина, а не lerp: скобки должны слегка проскакивать и оседать, иначе
## движение читается как переключение состояния.
@export var bracket_spring_stiffness: float = 90.0
@export var bracket_spring_damping: float = 14.0

## The step clamp comes from SpringPoint.MAX_STEP (ui/widgets/morphs/), which
## is not a morph-only number: it is the bound every semi-implicit Euler
## spring in this project needs, and that file already states why in its own
## header — "a hitch past that bound does not degrade gracefully: it
## diverges".
##
## What that costs when it is missing, measured on Stan's machine 2026-08-28:
## this spring is stable only while the step stays under roughly
## 2 / bracket_spring_damping, about 0.14 s. One frame longer — a streaming
## hitch, a breakpoint, the editor stealing focus — and the offset runs to
## infinity and then to NaN. NaN never comes back, so every later frame drew
## the brackets at a non-finite position, and each antialiased draw_line()
## normalized it and warned. 7714 warnings in one session, six per frame,
## forever. Reusing the constant instead of copying the number is the point.

@export_group("Статичность")
@export var mouse_stationary_px: float = 2.0

# === НАСТРОЙКИ 3D КУРСОРА ===
@export_group("3D UI")
@export var bracket_3d_offset: float = 12.0
@export var bracket_3d_max_offset: float = 30.0
@export var bracket_3d_color: Color = Color(0.3, 0.8, 1.0, 0.9)
@export var bracket_3d_animation_speed: float = 8.0

# === СОСТОЯНИЕ 3D UI ===
var is_over_3d_ui: bool = false
var is_over_3d_button: bool = false
var current_3d_button_name: String = ""
var bracket_offset_current: float = 12.0

# === ССЫЛКИ ===
@onready var player: CharacterBody3D = $".."

# === СОСТОЯНИЕ КУРСОРА ===
var current_cursor_color: Color
var cursor_position: Vector2 = Vector2.ZERO
var mouse_stationary_timer: float = 0.0
var last_mouse_pos: Vector2 = Vector2.ZERO
var last_player_pos: Vector3 = Vector3.ZERO

## Что-то интерактивное под курсором прямо сейчас.
var is_over_target: bool = false
## Огнестрел в руках — курсор становится скобками.
var has_firearm: bool = false

## Разведение прицельных скобок и его скорость (пружина).
var aim_bracket_offset: float = 0.0
var _aim_bracket_velocity: float = 0.0


func _ready() -> void:
	add_to_group(GROUP_MOUSE_CURSOR)
	current_cursor_color = cursor_color_idle
	aim_bracket_offset = bracket_offset_min
	PlayerState.mode_changed.connect(_on_player_state_mode_changed)
	_apply_cursor_for_mode(PlayerState.mode)

	if player:
		last_player_pos = player.global_transform.origin
	else:
		push_error("❌ Player не найден!")

	last_mouse_pos = get_viewport().get_mouse_position()


func _on_player_state_mode_changed(_old_mode, new_mode) -> void:
	_apply_cursor_for_mode(new_mode)


func _process(delta: float) -> void:
	if not player:
		return

	cursor_position = _resolve_cursor_position()

	var mouse_moved: bool = cursor_position.distance_to(last_mouse_pos) > mouse_stationary_px
	if mouse_moved:
		mouse_stationary_timer = 0.0
		last_mouse_pos = cursor_position
	else:
		mouse_stationary_timer += delta

	var player_pos: Vector3 = player.global_transform.origin
	var lin_speed: float = (player_pos - last_player_pos).length() / max(delta, 0.0001)
	last_player_pos = player_pos

	_update_target_state(delta)
	_update_firearm_state()
	_update_aim_brackets(delta, lin_speed)
	_update_3d_ui_state(delta)

	queue_redraw()


## Мышь захвачена всегда, пока игрок пешком (InputSystems ставит
## MOUSE_MODE_CAPTURED), так что водить курсором нельзя — целятся камерой.
## Значит и рисовать его, и бить луч надо из центра экрана: это и есть
## направление взгляда. Ветка «идти за мышью» жила ради изометрии и ушла
## вместе с ней 2026-09-02.
func _resolve_cursor_position() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


# -----------------------------------------------------------------------------
# ## ENG: What is under the cursor
# -----------------------------------------------------------------------------

## One ray, from the camera through the cursor, against characters and
## interactables. Deliberately NOT reusing InteractComponent's answer: that
## one asks "what would F act on", which is a question about the character's
## position and facing. This asks "what is the player pointing at", which in
## ISOMETRIC is a different thing entirely.
func _update_target_state(delta: float) -> void:
	var target_found := false
	var cam := get_viewport().get_camera_3d()
	var space := get_world_3d()
	if cam != null and space != null:
		var from: Vector3 = cam.project_ray_origin(cursor_position)
		var to: Vector3 = from + cam.project_ray_normal(cursor_position) * 1000.0
		var params := PhysicsRayQueryParameters3D.create(from, to)
		params.collision_mask = CollisionLayers.CHARACTERS | CollisionLayers.INTERACTABLES
		params.collide_with_areas = true
		params.collide_with_bodies = true
		## Иначе луч из камеры за спиной упирается в самого игрока и курсор
		## белеет всегда.
		params.exclude = [player.get_rid()]
		var hit := space.direct_space_state.intersect_ray(params)
		target_found = not hit.is_empty() and _is_targetable(hit.get("collider"))

	is_over_target = target_found
	var wanted: Color = cursor_color_target if is_over_target else cursor_color_idle
	current_cursor_color = current_cursor_color.lerp(
		wanted, clampf(cursor_color_speed * delta, 0.0, 1.0)
	)


## Является ли то, во что упёрся луч, целью — NPC или интерактивный объект.
##
## Проверка ПО ТИПУ, а не только по маске слоя, и на то есть измеренная
## причина: терраин острова стоит с collision_layer = 3, то есть сидит и на
## слое CHARACTERS вместе с персонажами. Маской их не разделить, и без этой
## проверки курсор белел от одного взгляда на землю.
##
## Побочно это даёт честное перекрытие: луч возвращает БЛИЖАЙШЕЕ попадание,
## так что NPC за холмом отсекается вместе с самим холмом — что и правильно.
func _is_targetable(collider: Variant) -> bool:
	if collider is NPCBase or collider is InteractableObject:
		return true
	## Предмет предлагает себя через дочернюю Area — тот же разбор, что
	## делает InteractComponent.
	return collider is Area3D and collider.get_parent() is InteractableObject


## Скобки — прицел, поэтому вопрос ровно один: в руках ли то, чем стреляют.
## Ответ берётся у игрока (get_drawn_firearm()), а не выводится заново из
## каталога: два определения «это оружие» рано или поздно разойдутся.
func _update_firearm_state() -> void:
	var drawn: bool = player.has_method(&"get_drawn_firearm") \
			and player.call(&"get_drawn_firearm") != null

	## Held through a weapon gesture. Draw, holster and the Tab cycle all pass
	## through a frame or two with nothing drawn, and flipping the cursor from
	## brackets to a circle and back inside a quarter of a second reads as a
	## glitch rather than as information — "the aim sometimes doesn't work, a
	## cursor shows up instead" (Stan, 2026-08-28). The hands being busy is
	## not the same as the hands being empty.
	if not drawn and _weapon_gesture_active():
		return
	has_firearm = drawn


func _weapon_gesture_active() -> bool:
	if not player.has_method(&"is_weapon_gesture_active"):
		return false
	return bool(player.call(&"is_weapon_gesture_active"))


## Разведение ведётся от НЕПРЕРЫВНОЙ скорости, а не от is_running: между
## «стоит» и «бежит» есть всё остальное, и именно оно делает прицел живым.
## Пружина вместо lerp — скобки слегка проскакивают и оседают.
func _update_aim_brackets(delta: float, lin_speed: float) -> void:
	var speed_ratio: float = 0.0
	if player.run_speed > 0.0:
		speed_ratio = clampf(lin_speed / player.run_speed, 0.0, 1.0)
	var target: float = lerpf(bracket_offset_min, bracket_offset_max, speed_ratio)

	## Clamped, not raw: see the note on SpringPoint.MAX_STEP above. A long frame plays back
	## slightly slow, which is invisible on a cursor and cannot explode.
	var step: float = minf(delta, SpringPoint.MAX_STEP)
	var to_target: float = target - aim_bracket_offset
	_aim_bracket_velocity += to_target * bracket_spring_stiffness * step
	_aim_bracket_velocity -= _aim_bracket_velocity * bracket_spring_damping * step
	aim_bracket_offset += _aim_bracket_velocity * step

	## Recovery, not just prevention. The clamp makes divergence impossible
	## from THIS integrator, but a non-finite value arriving from anywhere
	## else — a NaN speed out of the player, a bad export — would still be
	## permanent, because every later frame feeds it back into itself. Two
	## comparisons a frame turn a permanent break into one lost frame.
	if not is_finite(aim_bracket_offset) or not is_finite(_aim_bracket_velocity):
		aim_bracket_offset = bracket_offset_min
		_aim_bracket_velocity = 0.0


func _draw() -> void:
	if has_firearm:
		## Огнестрел в руках — вместо кружка прицельные скобки.
		_draw_aim_brackets()
	else:
		_draw_circle_outline(cursor_position, cursor_radius, current_cursor_color, cursor_thickness)
		var inner_color: Color = current_cursor_color
		inner_color.a *= 0.3
		draw_circle(cursor_position, cursor_radius * 0.3, inner_color)

	## Скобки 3D-UI живут отдельно от прицельных: это указатель на кнопку в
	## мире, а не на цель, и он должен работать и с пустыми руками.
	if is_over_3d_ui:
		_draw_3d_ui_brackets()


func _draw_aim_brackets() -> void:
	var color: Color = bracket_color
	if is_over_target:
		color = bracket_color.lightened(0.35)
	_draw_bracket_left(
		cursor_position.x - aim_bracket_offset, cursor_position.y,
		bracket_width, bracket_height, color
	)
	_draw_bracket_right(
		cursor_position.x + aim_bracket_offset, cursor_position.y,
		bracket_width, bracket_height, color
	)


func _update_3d_ui_state(delta: float) -> void:
	# Проверяем raycast для 3D UI
	var viewport := get_viewport()
	var cam := viewport.get_camera_3d()
	if not cam:
		is_over_3d_ui = false
		is_over_3d_button = false
		return
	
	var mouse_pos: Vector2 = cursor_position
	var from: Vector3 = cam.project_ray_origin(mouse_pos)
	var dir: Vector3 = cam.project_ray_normal(mouse_pos)
	var to: Vector3 = from + dir * 1000.0
	
	var space := get_world_3d()
	if not space:
		return
	
	var direct_space := space.direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = CollisionLayers.CURSOR_UI
	
	var result := direct_space.intersect_ray(params)
	
	if result.is_empty():
		is_over_3d_ui = false
		is_over_3d_button = false
		bracket_offset_current = lerp(bracket_offset_current, bracket_3d_offset, bracket_3d_animation_speed * delta)
		return
	
	# Попали в 3D UI область
	var collider: Node = result.get("collider")
	if collider:
		is_over_3d_ui = true
		
		# Проверяем, это кнопка?
		if collider is StaticBody3D:
			var parent = collider.get_parent()
			if parent and parent is MeshInstance3D:
				is_over_3d_button = true
				current_3d_button_name = parent.name
				# Раздвигаем скобки
				bracket_offset_current = lerp(bracket_offset_current, bracket_3d_max_offset, bracket_3d_animation_speed * delta)
			else:
				is_over_3d_button = false
				bracket_offset_current = lerp(bracket_offset_current, bracket_3d_offset, bracket_3d_animation_speed * delta)
		else:
			is_over_3d_button = false
			bracket_offset_current = lerp(bracket_offset_current, bracket_3d_offset, bracket_3d_animation_speed * delta)


func get_world_3d() -> World3D:
	if player:
		return player.get_world_3d()
	return get_viewport().get_world_3d()


func _draw_circle_outline(center: Vector2, radius: float, color: Color, thickness: float) -> void:
	var segments: int = 32
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(segments + 1):
		var angle: float = (TAU / segments) * i
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	for i in range(segments):
		draw_line(points[i], points[i + 1], color, thickness, true)


func _draw_3d_ui_brackets() -> void:
	var color = bracket_3d_color
	if is_over_3d_button:
		color = bracket_3d_color.lightened(0.3)
	
	# Левая скобка [
	var left_offset = bracket_offset_current
	_draw_bracket_left(cursor_position.x - left_offset, cursor_position.y, bracket_width, bracket_height, color)
	
	# Правая скобка ]
	var right_offset = bracket_offset_current
	_draw_bracket_right(cursor_position.x + right_offset, cursor_position.y, bracket_width, bracket_height, color)

## The brackets are ARCS, not three straight lines — segments of a circle
## centred on the cursor, so both bow away from the target and their tips
## point at it. A reticle made of corners reads as a UI frame; one made of
## arcs reads as something closing on a thing.
##
## The guard exists because antialiased draw_line() normalizes the segment
## direction: one non-finite coordinate is a warning PER LINE PER FRAME, and
## it never stops on its own. The spring above should make this unreachable
## — this is what keeps "should" from being load-bearing.
func _draw_bracket_left(x: float, y: float, width: float, height: float, color: Color) -> void:
	if not _is_bracket_drawable(x, y, width, height):
		return
	## x is already offset to the left of the cursor, so the distance between
	## them is the arc's radius and cursor_position is its centre.
	_draw_bracket_arc(Vector2(x, y), PI, height, width, color)


func _draw_bracket_right(x: float, y: float, width: float, height: float, color: Color) -> void:
	if not _is_bracket_drawable(x, y, width, height):
		return
	_draw_bracket_arc(Vector2(x, y), 0.0, height, width, color)


## One bracket. `tip` is where the old straight bracket's spine sat, `facing`
## is the direction from the cursor to it, and the arc is struck around the
## cursor through that point.
##
## height still sets how much of the circle is covered and width still sets
## the stroke, so both exports keep meaning roughly what they did — the shape
## changed, the knobs did not.
func _draw_bracket_arc(
		tip: Vector2, facing: float, height: float, width: float, color: Color
	) -> void:
	var radius: float = tip.distance_to(cursor_position)
	if radius < 1.0:
		## Degenerate: the brackets are sitting on the cursor. An arc of
		## radius zero is a point, and drawing it antialiased warns.
		return
	var half_angle: float = clampf(
		BRACKET_ARC_HALF_ANGLE * (height / maxf(bracket_height, 0.001)), 0.05, PI * 0.49
	)
	var points := PackedVector2Array()
	for i in BRACKET_ARC_SEGMENTS + 1:
		var t: float = float(i) / float(BRACKET_ARC_SEGMENTS)
		var a: float = facing - half_angle + t * half_angle * 2.0
		points.append(cursor_position + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(points, color, maxf(width * 0.3, 1.5), true)


## Tested AS A Vector2, not as floats, and the difference is the whole point.
## GDScript floats are 64-bit, so a diverged spring stays "finite" there for a
## very long time — measured on the real integrator, 1e150 after 200 long
## frames. Vector2 stores 32-bit components, so that same number is already
## inf by the time draw_line() sees it. A guard written with is_finite() on
## the floats passed exactly the value that caused this bug; the probe caught
## that, which is why it is written this way now.
##
## The size test is separate and just as necessary: a zero-length antialiased
## segment normalizes a zero vector and warns exactly as loudly as a NaN one.
static func _is_bracket_drawable(x: float, y: float, width: float, height: float) -> bool:
	if not Vector2(x, y).is_finite():
		return false
	if not Vector2(x + width, y + height).is_finite():
		return false
	return absf(width) > 0.001 and absf(height) > 0.001


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_over_3d_button:
			_on_3d_button_clicked(current_3d_button_name)
			get_viewport().set_input_as_handled()


func _on_3d_button_clicked(button_name: String) -> void:
	button_3d_clicked.emit(button_name)


## Кастомный курсор (нарисованный вручную) актуален только в ON_FOOT.
## В остальных режимах (MENU, VEHICLE_HOVER, TUBE_TRANSIT) прячем его —
## иначе в меню он рисуется поверх настоящего.
##
## IT NO LONGER TOUCHES Input.mouse_mode, AND THAT WAS A REAL BUG rather than
## tidying. This used to set MOUSE_MODE_HIDDEN on foot and MOUSE_MODE_VISIBLE
## everywhere else — a SECOND writer of a value InputSystems also writes, and
## the last one to run won. HIDDEN keeps the pointer inside the window: it
## stops at the edge, so relative motion stops with it and the camera cannot
## turn past a certain angle. Reported by Stan 2026-09-02 as "I turn the
## cursor left, we stop; right, it stops somewhere too", and measured on the
## running build as mouse_mode 0 (VISIBLE) where InputSystems had asked for 2
## (CAPTURED).
##
## The rule this restores is already in CLAUDE.md: only InputSystems touches
## Input. This widget decides its own visibility and nothing else.
func _apply_cursor_for_mode(mode) -> void:
	visible = mode == PlayerState.Mode.ON_FOOT
