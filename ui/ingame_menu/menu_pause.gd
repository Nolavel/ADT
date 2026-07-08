extends Control

# === СИГНАЛЫ ===
signal continue_pressed  # 🔥 сигнал для камеры

@onready var continue_button = $btn_continue
@onready var quit_button = $btn_out

@export var input_manager: NodePath
var input_manager_node: Node
var mp_is_active: bool = false

func _ready():
	visible = false
	modulate.a = 0.0
	
	# Подключение к InputManager
	if input_manager:
		input_manager_node = get_node(input_manager)
		if input_manager_node:
			input_manager_node.menu_pause_toggled.connect(_on_menu_pause_toggled)
			print("✅ PauseMenu: Подключен к InputManager")
		else:
			push_error("❌ InputManager node not found!")
	
	# Подключаем кнопки
	if continue_button:
		continue_button.pressed.connect(on_continue_button_pressed)
		print("✅ Continue button подключена")
	else:
		print("❌ Continue button не найдена!")
	
	if quit_button:
		quit_button.pressed.connect(on_quit_button_pressed)
		print("✅ Quit button подключена")
	else:
		print("❌ Quit button не найдена!")

func _on_menu_pause_toggled(active: bool) -> void:
	mp_is_active = active
	if active:
		print("🎬 PauseMenu: Показываем меню")
		fade_in()
	else:
		print("🎬 PauseMenu: Скрываем меню")
		fade_out()

func on_continue_button_pressed():
	print("🎮 Continue нажата - закрываем меню")
	
	# 1️⃣ Закрываем меню через InputManager (восстанавливает menu_pause_active = false)
	if input_manager_node and input_manager_node.has_method("close_pause_menu"):
		input_manager_node.close_pause_menu()
	
	# 2️⃣ Отправляем сигнал камере для возврата в GAME
	continue_pressed.emit()
	
	# 3️⃣ Плавно скрываем меню
	await fade_out()
	
	print("✅ Continue завершён: меню скрыто, игрок может двигаться")

func on_quit_button_pressed():
	print("🚪 Выход из игры через 1 секунду...")
	
	# Блокируем кнопки
	if continue_button:
		continue_button.disabled = true
	if quit_button:
		quit_button.disabled = true
		quit_button.text = "Выход..."
	
	# Плавное исчезновение
	await fade_out()
	
	# Задержка перед выходом
	await get_tree().create_timer(1.0).timeout
	
	print("👋 Выход!")
	get_tree().quit()

# Альтернативный метод с обратным отсчётом
func on_quit_button_pressed_with_countdown():
	print("🚪 Выход из игры через 3 секунды...")
	
	if continue_button:
		continue_button.disabled = true
	if quit_button:
		quit_button.disabled = true
	
	await fade_out()
	
	for i in range(3, 0, -1):
		if quit_button:
			quit_button.text = "Выход через " + str(i) + "..."
		await get_tree().create_timer(1.0).timeout
	
	print("👋 Выход!")
	get_tree().quit()

# Метод отмены выхода
func cancel_quit():
	if continue_button:
		continue_button.disabled = false
	if quit_button:
		quit_button.disabled = false
		quit_button.text = "Quit"

# Плавное появление
func fade_in():
	visible = true
	modulate.a = 0.0
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	await tween.finished

# Плавное исчезновение
func fade_out():
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
