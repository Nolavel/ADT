extends Control

class_name CryopodUIController

@export var cryo_ui_controller: CryoUIController
@export var cryopod: CryoPod
@export var cryosilo_manager: CryoBedSilo

@onready var panel_detect_cp = $PanelDetectCryoPod
@onready var btn_unlock = $PanelDetectCryoPod/VBoxContainer/btn_UnlockCryopod
@onready var btn_lock = $PanelDetectCryoPod/VBoxContainer/btn_LockCryopod

@onready var panel_internal_mon = $PanelInternalMonitor
@onready var btn_start_cryosleep = $PanelInternalMonitor/VBoxContainer/btn_StartCryosleepProcedure
@onready var btn_start_wake = $PanelInternalMonitor/VBoxContainer/btn_StartWake
@onready var lbl_cryosleep_warning = $PanelInternalMonitor/VBoxContainer/lbl_CryosleepWarning

var _player_near_capsule: bool = false
var _player_in_capsule: bool = false
var _just_woke_up: bool = false

func _ready() -> void:
	print("UI: cryopod ref =", cryopod)

	visible = false
	panel_detect_cp.visible = false
	panel_internal_mon.visible = false
	btn_unlock.visible = false
	btn_lock.visible = false
	btn_start_cryosleep.visible = false
	btn_start_wake.visible = false
	lbl_cryosleep_warning.visible = false

	btn_unlock.pressed.connect(_on_btn_unlock_pressed)
	btn_lock.pressed.connect(_on_btn_lock_pressed)
	btn_start_cryosleep.pressed.connect(_on_btn_start_cryosleep_pressed)
	btn_start_wake.pressed.connect(_on_btn_start_wake_pressed)

	if cryopod:
		cryopod.player_detect_cryopod.connect(_on_player_detect_cryopod)
		cryopod.capsule_state_changed.connect(_on_capsule_state_changed)
		cryopod.player_entered_capsule.connect(_on_player_in_capsule)
		cryopod.player_exited_capsule.connect(_on_player_out_capsule)

	if cryosilo_manager:
		cryosilo_manager.sleep_sequence_completed.connect(_on_sleep_sequence_completed)
		cryosilo_manager.wake_sequence_completed.connect(_on_wake_sequence_completed)

	if cryopod:
		_on_capsule_state_changed(cryopod.is_open, cryopod.capsule_id)

	_update_sleep_wake_buttons()
	_update_ui_state()

# === STATES AND UI UPDATE ===

func _on_player_detect_cryopod(player_in_interaction_zone: bool) -> void:
	if _just_woke_up:
		print("UIController %d: Ignoring interaction zone (just woke up)" % cryopod.capsule_id)
		return
	
	_player_near_capsule = player_in_interaction_zone
	_update_ui_state()

func _on_player_in_capsule(capsule_id: int) -> void:
	if cryopod and capsule_id == cryopod.capsule_id:
		if _just_woke_up:
			print("UIController %d: Ignoring interior zone (just woke up)" % cryopod.capsule_id)
			return
		
		_player_in_capsule = true
		_update_ui_state()
		_update_sleep_wake_buttons()
		print("UIController %d: Player entered MY capsule" % cryopod.capsule_id)

func _on_player_out_capsule(capsule_id: int) -> void:
	if cryopod and capsule_id == cryopod.capsule_id:
		_player_in_capsule = false
		
		if _just_woke_up:
			_just_woke_up = false
			_player_near_capsule = false
			print("UIController %d: Flag 'just woke up' reset" % cryopod.capsule_id)
		
		_update_ui_state()
		_update_sleep_wake_buttons()
		print("UIController %d: Player exited MY capsule" % cryopod.capsule_id)

func _update_ui_state() -> void:
	if not _player_near_capsule and not _player_in_capsule:
		visible = false
		panel_detect_cp.visible = false
		panel_internal_mon.visible = false
		return

	visible = true

	if _player_in_capsule:
		panel_detect_cp.visible = false
		panel_internal_mon.visible = true
	else:
		panel_detect_cp.visible = true
		panel_internal_mon.visible = false

# === CAPSULE STATE (LOCK/UNLOCK) ===

func _on_capsule_state_changed(is_open: bool, capsule_id: int) -> void:
	_update_sleep_wake_buttons()
	
	if cryopod and capsule_id != cryopod.capsule_id:
		return
	
	btn_unlock.visible = false
	btn_lock.visible = false

	if is_open:
		btn_lock.visible = true
	else:
		btn_unlock.visible = true

# === CAPSULE CONTROL BUTTONS ===

func _on_btn_unlock_pressed() -> void:
	if not cryopod:
		return
	await cryopod.open_capsule()

func _on_btn_lock_pressed() -> void:
	if not cryopod:
		return
	await cryopod.close_capsule()

# === SLEEP / WAKE BUTTONS ===

func _update_sleep_wake_buttons() -> void:
	if not _player_in_capsule:
		btn_start_cryosleep.visible = false
		btn_start_wake.visible = false
		lbl_cryosleep_warning.visible = false
		return

	if cryopod and cryopod.is_open:
		btn_start_cryosleep.visible = true
		btn_start_wake.visible = false
		
		if _check_other_capsules_open():
			btn_start_cryosleep.disabled = true
			lbl_cryosleep_warning.visible = true
			lbl_cryosleep_warning.text = "CRYO SILO SECURITY SYSTEM﻿:\nAll unoccupied cryopods must be verified\n in locked state prior to sleep sequence start.﻿"
			print("UIController %d: Other capsules open - blocking sleep" % cryopod.capsule_id)
		else:
			btn_start_cryosleep.disabled = false
			lbl_cryosleep_warning.visible = false
	else:
		btn_start_cryosleep.visible = false
		btn_start_wake.visible = true
		lbl_cryosleep_warning.visible = false

func _check_other_capsules_open() -> bool:
	if not cryosilo_manager:
		return false
	
	var other_open = false
	
	if cryosilo_manager.cryopod_1 and cryosilo_manager.cryopod_1 != cryopod:
		if cryosilo_manager.cryopod_1.is_open:
			other_open = true
	
	if cryosilo_manager.cryopod_2 and cryosilo_manager.cryopod_2 != cryopod:
		if cryosilo_manager.cryopod_2.is_open:
			other_open = true
	
	if cryosilo_manager.cryopod_3 and cryosilo_manager.cryopod_3 != cryopod:
		if cryosilo_manager.cryopod_3.is_open:
			other_open = true
	
	return other_open

func _on_btn_start_cryosleep_pressed() -> void:
	if not cryopod or not cryosilo_manager:
		return

	print("UIController %d: Starting sleep for capsule %d" % [cryopod.capsule_id, cryopod.capsule_id])
	
	panel_internal_mon.visible = false
	cryopod.disable_ground_collision()
	cryosilo_manager.start_sleep_sequence(cryopod)

func _on_btn_start_wake_pressed() -> void:
	if not cryopod or not cryosilo_manager:
		return
	
	print("UIController %d: Starting wake for capsule %d" % [cryopod.capsule_id, cryopod.capsule_id])

	panel_internal_mon.visible = false
	cryosilo_manager.start_wake_sequence(null)

func _on_sleep_sequence_completed() -> void:
	if not cryosilo_manager or not cryopod:
		return
	
	if cryosilo_manager.last_sleeping_capsule != cryopod:
		print("UIController %d: Player sleeping NOT in my capsule, ignoring" % cryopod.capsule_id)
		return
	
	print("UIController %d: Player sleeping in MY capsule!" % cryopod.capsule_id)
	
	_player_in_capsule = true
	_player_near_capsule = true
	visible = true
	panel_internal_mon.visible = true
	panel_detect_cp.visible = false
	_update_sleep_wake_buttons()

func _on_wake_sequence_completed() -> void:
	if not cryosilo_manager or not cryopod:
		return
	
	if cryosilo_manager.last_sleeping_capsule != cryopod:
		print("UIController %d: Player woke up NOT in my capsule, ignoring" % cryopod.capsule_id)
		return
	
	print("UIController %d: Player woke up in MY capsule!" % cryopod.capsule_id)
	
	if cryopod:
		cryopod.enable_ground_collision()

	_just_woke_up = true
	_player_in_capsule = false
	_player_near_capsule = false
	
	visible = false
	panel_internal_mon.visible = false
	panel_detect_cp.visible = false
	
	print("UIController %d: Set 'just woke up' flag - UI hidden" % cryopod.capsule_id)
