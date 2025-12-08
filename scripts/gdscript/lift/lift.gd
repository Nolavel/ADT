extends MeshInstance3D
## ЛИФТ

@export var current_deck: String = "Deck-B"
@export var move_speed: float = 5.0 # скорость движения в единицах/сек
@export var door_speed: float = 2.0
@export var slowdown_distance: float = 1.5 # расстояние для начала замедления
@export var min_speed: float = 1.5 # минимальная скорость при подъезде
@export var arrival_threshold: float = 0.05 # порог остановки

@onready var area_lift = $AreaTriggerLift
@onready var lift_ui = $"../../WIDGETS/LiftUI"
@onready var btn_deck_a = lift_ui.get_node("VBoxContainer/DECK_A")
@onready var btn_deck_b = lift_ui.get_node("VBoxContainer/DECK_B")
@onready var btn_out = lift_ui.get_node("VBoxContainer/OUT")

@onready var mesh_door = $LIFT_DOOR

# Две зоны вызова лифта (по одной на каждом этаже)
@export var area_call_deck_a: Area3D
@export var area_call_deck_b: Area3D

@export var anima_shaft_door_deck_a: AnimationPlayer
@export var anima_shaft_door_deck_b: AnimationPlayer

var lift_mesh := self
var target_height: float = 0.0
var moving: bool = false
var door_moving: bool = false
var door_open: bool = false
var door_target_rot: float = -90.0

var player_on_lift: Node3D = null # ссылка на игрока
var player_in_call_zone: bool = false # игрок в зоне вызова
var player_current_zone_deck: String = "" # в какой зоне сейчас игрок
var called_from_deck: String = "" # с какого этажа вызвали лифт
var last_arrival_deck: String = "" # последний этаж куда приехал лифт
var can_be_called_away: bool = true # можно ли увезти лифт с текущего этажа
var player_near_lift: bool = false # игрок рядом с лифтом (в любой зоне)

@export var deck_positions = {
	"Deck-A": -57.3,
	"Deck-B": -65.3
}

var want_open_door: bool = false
var prev_player_deck: String = ""

signal player_moved_between_decks(from_deck: String, to_deck: String)


func _ready() -> void:
	lift_ui.visible = false
	
	mesh_door.rotation_degrees.z = -90.0
	
	btn_deck_a.pressed.connect(_move_to_deck.bind("Deck-A"))
	btn_deck_b.pressed.connect(_move_to_deck.bind("Deck-B"))
	
	btn_out.pressed.connect(_on_out_pressed)
	
	area_lift.body_entered.connect(_on_player_entered_on_lift)
	area_lift.body_exited.connect(_on_player_exited_on_lift)
	
	area_call_deck_a.body_entered.connect(_on_call_zone_entered.bind("Deck-A"))
	area_call_deck_a.body_exited.connect(_on_call_zone_exited)
	
	area_call_deck_b.body_entered.connect(_on_call_zone_entered.bind("Deck-B"))
	area_call_deck_b.body_exited.connect(_on_call_zone_exited)
	
	# Определяем текущую позицию лифта по его высоте
	await get_tree().process_frame
	current_deck = _get_deck_by_height(lift_mesh.global_position.y)
	print("🛗 Лифт изначально находится на: ", current_deck, " (высота: ", lift_mesh.global_position.y, ")")
	
	_update_ui()
	
	# Проверяем после загрузки сцены, есть ли игрок в зоне вызова
	_check_initial_player_in_call_zones()

func _on_out_pressed():
	_open_door_lift()

func check_should_show_out_button():
	if player_on_lift != null and not moving and not door_open and not door_moving:
		btn_out.visible = true
	else:
		btn_out.visible = false


func _on_player_entered_on_lift(body):
	if body.name == "Player":
		player_on_lift = body
		player_in_call_zone = false
		if not moving:
			lift_ui.visible = true
			_update_ui()
		check_should_show_out_button()


func _on_player_exited_on_lift(body):
	if body.name == "Player":
		player_on_lift = null
		lift_ui.visible = false
		print("Игрок вышел из лифта")
		check_should_close_door()
		check_should_show_out_button()


func _on_call_zone_entered(body, deck_name: String):
	if body.name == "Player":
		player_in_call_zone = true
		player_current_zone_deck = deck_name
		print("Игрок вошёл в зону вызова этажа: ", deck_name)

		if current_deck != deck_name:
			can_be_called_away = true

		want_open_door = true
		print("want_open_door set TRUE, вход: ", deck_name, ", door_moving=", door_moving, ", door_open=", door_open)

		if current_deck == deck_name:
			if not can_be_called_away:
				print("Блокировка вызова - лифт нельзя увезти с ", deck_name)
				if not door_open and not door_moving:
					_open_door_lift()
				return

		if current_deck != deck_name and not moving and not door_moving:
			called_from_deck = deck_name
			_call_lift_to_deck(deck_name)
		elif current_deck == deck_name and not moving and not door_moving:
			_open_door_lift()


func _on_call_zone_exited(body):
	if body.name == "Player":
		var previous_zone = player_current_zone_deck
		player_in_call_zone = false
		player_current_zone_deck = ""
		want_open_door = false
		print("want_open_door set FALSE (выход из зоны)")
		
		print("Игрок вышел из зоны вызова этажа: ", previous_zone)

		if previous_zone == last_arrival_deck and previous_zone == current_deck:
			print("Игрок покинул этаж ", previous_zone, " - снимаем блокировку через 2 секунды")
			await get_tree().create_timer(2.0).timeout
			if not player_in_call_zone or player_current_zone_deck != previous_zone:
				can_be_called_away = true
				print("Блокировка снята - лифт можно вызвать с ", current_deck)

		check_should_close_door()


func _open_door_lift():
	if door_open or door_moving:
		print("door already open or moving, skip open")
		return
	print("door OPEN command")
	btn_out.visible = false
	door_open = true
	door_target_rot = 30.0
	door_moving = true
	
	# --- Запуск анимации двери шахты на текущем этаже ---
	match current_deck:
		"Deck-A":
			anima_shaft_door_deck_a.play("open")
		"Deck-B":
			anima_shaft_door_deck_b.play("open")


func _close_door_lift():
	if door_moving:
		print("door is moving, SKIP CLOSE")
		return
	if door_open:
		print("door CLOSE command")
		door_open = false
	door_target_rot = -90.0
	door_moving = true
	want_open_door = false
	print("want_open_door set FALSE")
	
	# --- Запуск анимации закрытия двери шахты ---
	match current_deck:
		"Deck-A":
			anima_shaft_door_deck_a.play("close")
		"Deck-B":
			anima_shaft_door_deck_b.play("close")
			
	check_should_show_out_button()

func _update_ui():
	btn_deck_a.visible = false
	btn_deck_b.visible = false
	
	match current_deck:
		"Deck-A":
			btn_deck_b.visible = true
		"Deck-B":
			btn_deck_a.visible = true


func _call_lift_to_deck(to_deck: String):
	if moving or to_deck == current_deck:
		return
	if not deck_positions.has(to_deck):
		return
	
	if not can_be_called_away and current_deck == last_arrival_deck:
		print("БЛОКИРОВКА: Нельзя увезти лифт с этажа ", current_deck)
		return
	
	prev_player_deck = current_deck
	print("Лифт вызван на этаж: ", to_deck)
	
	_close_door_lift()
	await _wait_until_door_closed()
	
	await get_tree().create_timer(0.1).timeout
	
	target_height = deck_positions[to_deck]
	moving = true


func _move_to_deck(to_deck: String):
	if moving or door_moving or to_deck == current_deck:
		return
	if not deck_positions.has(to_deck):
		return
	
	prev_player_deck = current_deck
	print("Лифт едет на этаж: ", to_deck, " (игрок внутри)")
	
	lift_ui.visible = false
	
	_close_door_lift()
	await _wait_until_door_closed()
	
	await get_tree().create_timer(0.1).timeout
	
	target_height = deck_positions[to_deck]
	moving = true


func _physics_process(delta):
	if door_moving:
		var cur_rot = mesh_door.rotation_degrees
		cur_rot.z = lerp(cur_rot.z, door_target_rot, delta * door_speed)
		mesh_door.rotation_degrees = cur_rot
		
		if abs(cur_rot.z - door_target_rot) < 0.5:
			mesh_door.rotation_degrees.z = door_target_rot
			door_moving = false
			# want_open_door гарантирует открытие после завершения анимации!
			if want_open_door and not door_open and player_in_call_zone:
				print("want_open_door trigger OPEN, door was closed!")
				want_open_door = false
				_open_door_lift()

	if moving:
		var prev_y = lift_mesh.global_position.y
		var curpos = lift_mesh.global_position
		
		var distance = abs(target_height - curpos.y)
		
		if distance < arrival_threshold:
			lift_mesh.global_position.y = target_height
			moving = false
			current_deck = _get_deck_by_height(target_height)
			last_arrival_deck = current_deck
			
			print("Лифт прибыл на этаж: ", current_deck)
			can_be_called_away = false
			print("Блокировка установлена - лифт нельзя увезти с ", current_deck)
			
			if player_on_lift:
				lift_ui.visible = true
				_update_ui()
			
			_open_door_lift()
			if player_on_lift and prev_player_deck != current_deck and prev_player_deck != "":
				emit_signal("player_moved_between_decks", prev_player_deck, current_deck)
			prev_player_deck = ""
		else:
			var current_speed: float
			if distance < slowdown_distance:
				var t = distance / slowdown_distance
				current_speed = lerp(min_speed, move_speed, t)
			else:
				current_speed = move_speed
			
			var direction = sign(target_height - curpos.y)
			var move_amount = current_speed * delta
			
			if move_amount > distance:
				lift_mesh.global_position.y = target_height
			else:
				lift_mesh.global_position.y += direction * move_amount

		if player_on_lift:
			var lift_delta_y = lift_mesh.global_position.y - prev_y
			player_on_lift.global_position.y += lift_delta_y
			
	if not door_moving:  # Когда дверь закончила движение
		check_should_show_out_button()


func _get_deck_by_height(h: float) -> String:
	for deck_name in deck_positions:
		if abs(deck_positions[deck_name] - h) < 0.1:
			return deck_name
	return current_deck

func check_should_close_door():
	if not player_in_call_zone and player_on_lift == null:
		_close_door_lift()
		want_open_door = false
		print("want_open_door set FALSE FINAL")

func _wait_until_door_closed() -> void:
	while door_moving:
		await get_tree().process_frame

func _check_initial_player_in_call_zones():
	"""Проверяет при старте игры, находится ли игрок в зоне вызова лифта"""
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_node_or_null("../../Player")
	
	if not player:
		print("⚠️ Игрок не найден при инициализации лифта")
		return
	
	# Проверяем Deck A
	var overlapping_a = area_call_deck_a.get_overlapping_bodies()
	if player in overlapping_a:
		print("✅ Игрок изначально в зоне Deck-A, вызываем лифт")
		player_in_call_zone = true
		player_current_zone_deck = "Deck-A"
		want_open_door = true
		
		if current_deck == "Deck-A":
			_open_door_lift()
		else:
			_call_lift_to_deck("Deck-A")
		return
	
	# Проверяем Deck B
	var overlapping_b = area_call_deck_b.get_overlapping_bodies()
	if player in overlapping_b:
		print("✅ Игрок изначально в зоне Deck-B, вызываем лифт")
		player_in_call_zone = true
		player_current_zone_deck = "Deck-B"
		want_open_door = true
		
		if current_deck == "Deck-B":
			_open_door_lift()
		else:
			_call_lift_to_deck("Deck-B")
		return
	
	print("ℹ️ Игрок не в зоне вызова лифта при старте")
