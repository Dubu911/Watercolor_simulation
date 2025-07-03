# eraser_brush.gd
extends Node

@export var brush_radius: float = 3.0

var coordinator_ref
var is_painting: bool = false
var last_pos: Vector2 = Vector2.INF

func activate(coordinator):
	coordinator_ref = coordinator
	is_painting = false
	last_pos = Vector2.INF

func deactivate():
	is_painting = false
	last_pos = Vector2.INF

func handle_input(event: InputEvent, mouse_pos_img_space: Vector2):
	if not is_instance_valid(coordinator_ref): return

	var current_draw_pos = mouse_pos_img_space.floor()
	var eraser_color = Color(0, 0, 0, 0) # Erasing is just drawing with transparency

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_painting = true
			last_pos = current_draw_pos
			# For a single click, draw a line from the point to itself (a dot)
			if coordinator_ref.has_method("draw_line_on_pencil_layer"):
				coordinator_ref.draw_line_on_pencil_layer(last_pos, current_draw_pos, eraser_color, brush_radius)
		else: # Released
			is_painting = false
			last_pos = Vector2.INF

	elif event is InputEventMouseMotion and is_painting:
		if last_pos != Vector2.INF:
			if coordinator_ref.has_method("draw_line_on_pencil_layer"):
				coordinator_ref.draw_line_on_pencil_layer(last_pos, current_draw_pos, eraser_color, brush_radius)
		last_pos = current_draw_pos
