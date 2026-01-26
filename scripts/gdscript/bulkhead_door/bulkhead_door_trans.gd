extends Node3D

#testing

@onready var area = $Area3D
@onready var anima = $anima_bulkhead_door
@onready var sound = $ASP

func _ready() -> void:
	area.body_entered.connect(_on_player_entered_on_bulkhead_door)
	area.body_exited.connect(_on_player_exited_on_bulkhead_door)
	
func _on_player_entered_on_bulkhead_door(body):
	if body.name == "Player":
		anima.play("door_open")
		sound.play()
		sound.pitch_scale = 1.0
	
func _on_player_exited_on_bulkhead_door(body):
	if body.name == "Player":
		anima.play("door_close")
		sound.play()
		sound.pitch_scale = 0.8
		
		
	
	
