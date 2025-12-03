## ============================================
## CRYO_UI_CONTROLLER.gd - UI Controller
## ============================================
extends Control
class_name CryoUIController

@onready var vbox: VBoxContainer = $VBox

# Buttons
@onready var btn_silo: Button = $VBox/BtnSilo
@onready var btn_capsules: Button = $VBox/BtnCapsules
@onready var btn_capsule_1: Button = $VBox/BtnCapsule1
@onready var btn_capsule_2: Button = $VBox/BtnCapsule2
@onready var btn_capsule_3: Button = $VBox/BtnCapsule3

# Components
@onready var zone_terminal: ZoneTerminal = $"../ZoneTerminal"
@onready var silo_manager: CryoBedSilo = $".."

var active_cryopod: CryoPod = null
var is_player_at_terminal: bool = false
var is_initialized: bool = false

func _ready() -> void:
	visible = false
	_hide_all_buttons()
	#display_terminal.modulate = Color (1.0, 1.0, 1.0, 0.1)
	
	# Connect buttons
	btn_silo.pressed.connect(_on_silo_pressed)
	btn_capsules.pressed.connect(_on_capsules_pressed)
	btn_capsule_1.pressed.connect(_on_capsule_1_pressed)
	btn_capsule_2.pressed.connect(_on_capsule_2_pressed)
	btn_capsule_3.pressed.connect(_on_capsule_3_pressed)
	
	# Wait for scene loading
	await get_tree().process_frame
	await get_tree().process_frame
	
	#_find_components()
	_connect_signals()
	
	print("Cryo UI Controller: Initialized")

## === CONNECT SIGNALS ===
func _connect_signals() -> void:
	if not zone_terminal or not silo_manager:
		print("UI: Missing required components")
		return
	
	# Connect control panel
	zone_terminal.player_entered_control_zone.connect(_on_player_at_terminal)
	zone_terminal.player_exited_control_zone.connect(_on_player_left_terminal)
	print("UI: Connected to ControlPanel")
	
	# Connect manager
	silo_manager.silo_state_changed.connect(_on_silo_state_changed)
	silo_manager.capsules_state_changed.connect(_on_capsules_state_changed)
	silo_manager.animation_started.connect(_on_animation_started)
	silo_manager.animation_finished.connect(_on_animation_finished)
	print("UI: Connected to SiloManager")
	
	# Connect capsules
	if silo_manager.cryopod_1:
		silo_manager.cryopod_1.player_entered_capsule.connect(_on_player_entered_capsule)
		silo_manager.cryopod_1.player_exited_capsule.connect(_on_player_exited_capsule)
		silo_manager.cryopod_1.capsule_state_changed.connect(_on_capsule_changed)
		print("UI: Connected to Cryopod 1")
	
	if silo_manager.cryopod_2:
		silo_manager.cryopod_2.player_entered_capsule.connect(_on_player_entered_capsule)
		silo_manager.cryopod_2.player_exited_capsule.connect(_on_player_exited_capsule)
		silo_manager.cryopod_2.capsule_state_changed.connect(_on_capsule_changed)
		print("UI: Connected to Cryopod 2")
	
	if silo_manager.cryopod_3:
		silo_manager.cryopod_3.player_entered_capsule.connect(_on_player_entered_capsule)
		silo_manager.cryopod_3.player_exited_capsule.connect(_on_player_exited_capsule)
		silo_manager.cryopod_3.capsule_state_changed.connect(_on_capsule_changed)
		print("UI: Connected to Cryopod 3")
	
	is_initialized = true
	_update_ui()

## === BUTTON HANDLERS ===

func _on_silo_pressed() -> void:
	print("UI: Silo button pressed")
	if silo_manager:
		silo_manager.toggle_silo()

func _on_capsules_pressed() -> void:
	print("UI: Capsules button pressed")
	if silo_manager:
		silo_manager.toggle_capsules()

func _on_capsule_1_pressed() -> void:
	print("UI: Capsule 1 button pressed")
	if silo_manager and silo_manager.cryopod_1:
		await silo_manager.cryopod_1.toggle_capsule()

func _on_capsule_2_pressed() -> void:
	print("UI: Capsule 2 button pressed")
	if silo_manager and silo_manager.cryopod_2:
		await silo_manager.cryopod_2.toggle_capsule()

func _on_capsule_3_pressed() -> void:
	print("UI: Capsule 3 button pressed")
	if silo_manager and silo_manager.cryopod_3:
		await silo_manager.cryopod_3.toggle_capsule()

func _on_sleep_wake_pressed() -> void:
	print("UI: Sleep/Wake button pressed")
	if not active_cryopod or not silo_manager:
		return
	
	if active_cryopod.player_inside:
		active_cryopod.disable_ground_collision()
		await silo_manager.start_sleep_sequence(active_cryopod)
	else:
		await silo_manager.start_wake_sequence(active_cryopod)
		active_cryopod.enable_ground_collision()

## === SIGNAL HANDLERS ===
func _on_player_at_terminal() -> void:
	is_player_at_terminal = true
	visible = true
	_update_ui()
	print("UI: Player at panel - showing terminal button")

func _on_player_left_terminal() -> void:
	is_player_at_terminal = false
	visible = false
	print("UI: Player left panel")
	
func show_ui_with_buttons() -> void:
	visible = true
	_update_ui()

func _on_silo_state_changed(is_raised: bool) -> void:
	_update_ui()

func _on_capsules_state_changed(are_raised: bool) -> void:
	_update_ui()

func _on_capsule_changed(is_open: bool, capsule_id: int) -> void:
	print("UI: Capsule %d changed: %s" % [capsule_id, "open" if is_open else "closed"])
	_update_ui()

func _on_animation_started() -> void:
	_lock_all_buttons(true)

func _on_animation_finished() -> void:
	_lock_all_buttons(false)
	_update_ui()

func _on_player_entered_capsule(capsule_id: int) -> void:
	match capsule_id:
		1: active_cryopod = silo_manager.cryopod_1
		2: active_cryopod = silo_manager.cryopod_2
		3: active_cryopod = silo_manager.cryopod_3
	print("UI: Player in capsule %d" % capsule_id)
	_update_ui()

func _on_player_exited_capsule(capsule_id: int) -> void:
	active_cryopod = null
	print("UI: Player exited capsule")
	_update_ui()

## === UI UPDATE ===
func _update_ui() -> void:
	if not is_initialized or not silo_manager or not zone_terminal:
		return
	
	var terminal_on = zone_terminal.is_terminal_on
	var silo_raised = silo_manager.is_silo_raised
	var caps_raised = silo_manager.are_capsules_raised
	
	# Если терминал выключен — UI вообще спрятан
	if not terminal_on:
		_hide_all_buttons()
		return
	
	# Если игрок не у панели — не показывать кнопки
	if not is_player_at_terminal:
		_hide_all_buttons()
		return
	
	# Дальше — терминал включён и игрок у панели
	btn_silo.visible = true
	btn_capsules.visible = true
	
	if silo_raised:
		btn_silo.text = "Lower CryoSilo"
		btn_silo.disabled = caps_raised
	else:
		btn_silo.text = "Raise CryoSilo"
		btn_silo.disabled = false
	
	if caps_raised:
		btn_capsules.text = "Lower Cryopods"
		btn_capsules.disabled = _any_capsule_open()
	else:
		btn_capsules.text = "Raise Cryopods"
		btn_capsules.disabled = not silo_raised
	
	btn_capsule_1.visible = caps_raised
	btn_capsule_2.visible = caps_raised
	btn_capsule_3.visible = caps_raised
	
	if caps_raised:
		if silo_manager.cryopod_1:
			btn_capsule_1.text = "Lock Pod R1" if silo_manager.cryopod_1.is_open else "Unlock Pod R1"
		if silo_manager.cryopod_2:
			btn_capsule_2.text = "Lock Pod R2" if silo_manager.cryopod_2.is_open else "Unlock Pod R2"
		if silo_manager.cryopod_3:
			btn_capsule_3.text = "Lock Pod R3" if silo_manager.cryopod_3.is_open else "Unlock Pod R3"

	
	## Sleep/Wake button visible only when player inside capsule
	#btn_sleep_wake.visible = (active_cryopod != null and active_cryopod.player_inside)
	#
	#if active_cryopod and active_cryopod.player_inside:
		#btn_sleep_wake.text = "Enter Cryosleep"

## === HELPER FUNCTIONS ===
func _any_capsule_open() -> bool:
	var result = false
	if silo_manager.cryopod_1 and silo_manager.cryopod_1.is_open:
		result = true
	if silo_manager.cryopod_2 and silo_manager.cryopod_2.is_open:
		result = true
	if silo_manager.cryopod_3 and silo_manager.cryopod_3.is_open:
		result = true
	return result

func _hide_all_buttons() -> void:
	btn_silo.visible = false
	btn_capsules.visible = false
	btn_capsule_1.visible = false
	btn_capsule_2.visible = false
	btn_capsule_3.visible = false
	
func _lock_all_buttons(locked: bool) -> void:
	btn_silo.disabled = locked
	btn_capsules.disabled = locked
	btn_capsule_1.disabled = locked
	btn_capsule_2.disabled = locked
	btn_capsule_3.disabled = locked
