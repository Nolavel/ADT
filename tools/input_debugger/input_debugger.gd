extends Control

@export var display_label: Label
@export var display_time: float = 1.0
@export var show_mouse_motion: bool = true
@export var default_text: String = "InputDebugger"

var _timer: Timer

func _ready():
	display_label.visible = true
	display_label.text = default_text

	_timer = Timer.new()
	_timer.wait_time = display_time
	_timer.one_shot = true
	_timer.connect("timeout", Callable(self, "_on_timer_timeout"))
	add_child(_timer)

func _input(event):
	if event is InputEventKey and event.pressed:
		var key_name: String = event.as_text()  # <-- вот так получаем нормальное имя клавиши
		_show_input("Key: %s" % key_name)
	elif event is InputEventMouseButton and event.pressed:
		var button_name: String
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				button_name = "Left Button"
			MOUSE_BUTTON_RIGHT:
				button_name = "Right Button"
			MOUSE_BUTTON_MIDDLE:
				button_name = "Middle Button"
			_:
				button_name = "Button %d" % event.button_index
		_show_input("Mouse: %s" % button_name)
	elif show_mouse_motion and event is InputEventMouseMotion:
		_show_input("Mouse moved: (%.1f, %.1f)" % [event.relative.x, event.relative.y])

func _show_input(text: String) -> void:
	display_label.text = text
	display_label.visible = true
	_timer.stop()
	_timer.start()

func _on_timer_timeout():
	display_label.text = default_text
	display_label.visible = true
