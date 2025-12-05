## ============================================
## ZoneTerminal.gd - Зона активации компьютера
## ============================================
extends Area3D
class_name ZoneTerminal

signal terminal_switch_ON
signal terminal_switch_OFF
signal player_entered_control_zone
signal player_exited_control_zone
signal movement_blocked

var player_in_zone: bool = false
var is_terminal_on: bool = false
var terminal = self

@onready var display_terminal_station: Sprite3D = $MeshTerminalStation/DisplayTerminal
@onready var terminal_light: OmniLight3D = $MeshTerminalStation/TerminalLight
@onready var _3d_screen: MeshInstance3D = $"../3D_Screen"
@onready var area_gui: Area3D = $"../3D_Screen/AreaGUI"
@onready var power_switch_gui: PowerSwitchGUI = $"../PowerSwitch_GUI_Terminal"

@export var terminal_texture_off: Texture2D
@export var terminal_texture_on: Texture2D

var camera: Camera3D
var player: CharacterBody3D  # 🔥 Ссылка на игрока

func _ready() -> void:
	body_entered.connect(_on_player_entered_zone)
	body_exited.connect(_on_player_exited_zone)
	
	camera = get_viewport().get_camera_3d()
	if camera:
		pass
	else:
		print("✅ Камера для терминала не найдена")

func _input(event: InputEvent) -> void:
	if not is_terminal_on or not player:
		return
	
	## Проверяем правую кнопку мыши
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			## Игрок пытается двигаться, но терминал включен
			movement_blocked.emit()

func _process(delta: float) -> void:
	if not is_terminal_on or not _3d_screen or not camera:
		return
		
	var camera_pos = camera.global_position
	var screen_pos = _3d_screen.global_position
	var target_pos = camera_pos
	target_pos.y = screen_pos.y
	
	if screen_pos.distance_to(target_pos) > 0.001:
		_3d_screen.look_at(target_pos, Vector3.UP)
		_3d_screen.rotation_degrees.y += 180.0
		_3d_screen.rotation_degrees.x = 50.0
		_3d_screen.rotation_degrees.z = 0.0

func _on_player_entered_zone(body: Node3D) -> void:
	if body.name == "Player":
		player_in_zone = true
		player = body  # 🔥 Сохраняем ссылку на игрока
		power_switch_gui.show_with_anim()
		
		player_entered_control_zone.emit()
		print("👤 Игрок подошёл к панели управления")

func _on_player_exited_zone(body: Node3D) -> void:
	if body.name == "Player":
		player_in_zone = false
		player = null  # 🔥 Очищаем ссылку
		power_switch_gui.hide_with_anim()
		
		if is_terminal_on:
			toggle_terminal()
		
		player_exited_control_zone.emit()


func toggle_terminal() -> void:
	is_terminal_on = !is_terminal_on
	_update_terminal_display_station()
	
	if is_terminal_on:
		if player and player.has_method("set_movement_enabled"):
			player.set_movement_enabled(false)
		
		if player_in_zone:
			_update_terminal_display_station()
		
		terminal_switch_ON.emit()
	else:
		# 🔥 РАЗБЛОКИРУЕМ движение игрока
		if player and player.has_method("set_movement_enabled"):
			player.set_movement_enabled(true)
		
		terminal_switch_OFF.emit()

func _update_terminal_display_station() -> void:
	if not display_terminal_station:
		return
	var on: bool = terminal != null and terminal.is_terminal_on
	if on:
		display_terminal_station.texture = terminal_texture_on
		display_terminal_station.modulate = Color(1.0, 1.0, 1.0, 0.5)
	else:
		display_terminal_station.texture = terminal_texture_off
		display_terminal_station.modulate = Color(1.0, 1.0, 1.0, 0.1)
	_terminal_lighting(on)

func _terminal_lighting(is_on: bool) -> void:
	if not terminal_light:
		return
	terminal_light.visible = is_on
