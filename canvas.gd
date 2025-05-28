extends Node2D

#@onready var brush_layer := get_tree().root.get_node("BurshLayer")
@onready var brush_layer := $BrushLayer

func _input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		brush_layer.draw_dot(event.position)
