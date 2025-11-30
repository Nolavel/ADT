## ============================================
## TERMNINAL3DMANAGER.gd - Зона активации компьютера
## ============================================
extends Area3D
class_name Terminal3DManager

signal computer_activated
signal computer_deactivated
signal player_entered_control_zone
signal player_exited_control_zone

var player_in_zone: bool = false
var is_computer_on: bool = false
var terminal = self

@onready var display_terminal: Sprite3D = $"../../CryoSiloManager/MeshTerminal/DisplayTerminal"
@onready var terminal_light: OmniLight3D = $"../../CryoSiloManager/MeshTerminal/TerminalLight"
@export var terminal_texture_off: Texture2D
@export var terminal_texture_on: Texture2D
@onready var terminal3d: InteractiveTerminal3D = $"../../InteractiveTerminal3D"

func _ready() -> void:
	terminal3d.visible = false
	
	body_entered.connect(_on_player_entered_zone)
	body_exited.connect(_on_player_exited_zone)
	print("✅ Control Panel: Инициализирована")
	
func _on_player_entered_zone(body: Node3D) -> void:
	if body.name == "Player":
		player_in_zone = true
		terminal3d.visible = true
		
		player_entered_control_zone.emit()
		print("👤 Игрок подошёл к панели управления")

func _on_player_exited_zone(body: Node3D) -> void:
	if body.name == "Player":
		player_in_zone = false
		terminal3d.visible = false
		
		player_exited_control_zone.emit()
		print("🚶 Игрок отошёл от панели управления")

func toggle_computer() -> void:
	is_computer_on = !is_computer_on
	_update_terminal_display()
	
	if is_computer_on:
		# ⚡ Активируем интерактивность только если игрок в зоне
		if player_in_zone and terminal3d:
			terminal3d.visible = true
			terminal3d.set_active(true)
			print("🔓 Terminal interactive: ENABLED")
		
		computer_activated.emit()
		print("💻 Компьютер включён")
	else:
		# ⚡ Деактивируем интерактивность
		if terminal3d:
			terminal3d.set_active(false)
			print("🔒 Terminal interactive: DISABLED")
			
			# Если игрок в зоне - оставляем видимым (кнопка активации)
			if player_in_zone:
				terminal3d.visible = true
			else:
				terminal3d.visible = false
		
		computer_deactivated.emit()
		print("💻 Компьютер выключен")
		
func _update_terminal_display() -> void:
	if not display_terminal:
		return
	var on: bool = terminal != null and terminal.is_computer_on
	if on:
		display_terminal.texture = terminal_texture_on
		display_terminal.modulate = Color(1.0, 1.0, 1.0, 0.5)  # Поярче когда включен
	else:
		display_terminal.texture = terminal_texture_off
		display_terminal.modulate = Color(1.0, 1.0, 1.0, 0.1)  # Потемнее когда выключен
	_terminal_lighting(on)
		
func _terminal_lighting(is_on: bool) -> void:
	if not terminal_light:
		return
	terminal_light.visible = is_on
