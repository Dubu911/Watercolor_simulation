# eraser_brush.gd
extends Node2D

@export var brush_radius: float = 10.0 # Eraser is usually larger

var coordinator_ref
var last_pos: Vector2 = Vector2.INF

func activate(coordinator):
	coordinator_ref = coordinator
	# print(name + " activated.") # Debug print removed
	last_pos = Vector2.INF

func handle_input(event: InputEvent, mouse_pos_img_space: Vector2, target_image: Image, coordinator):
	if not coordinator_ref: coordinator_ref = coordinator

	var current_draw_pos = mouse_pos_img_space.floor()
	var eraser_color = Color(0,0,0,0) # Transparent

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			last_pos = current_draw_pos
			_draw_brush_stroke_at_point(target_image, last_pos, eraser_color)
		else: # Released
			last_pos = Vector2.INF
			
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if last_pos != Vector2.INF:
			_draw_line_with_brush(target_image, last_pos, current_draw_pos, eraser_color)
		last_pos = current_draw_pos

func _draw_brush_stroke_at_point(img: Image, center_pos: Vector2, color: Color):
	if not img: return

	var i_radius = int(ceil(brush_radius))
	var center_x_int = int(center_pos.x)
	var center_y_int = int(center_pos.y)

	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= brush_radius * brush_radius:
				var draw_x = center_x_int + x_offset
				var draw_y = center_y_int + y_offset
				if draw_x >= 0 and draw_x < img.get_width() and \
				   draw_y >= 0 and draw_y < img.get_height():
					img.set_pixel(draw_x, draw_y, color)
	
	if coordinator_ref:
		coordinator_ref.mark_pencil_dirty() # Eraser works on the pencil layer

func _draw_line_with_brush(img: Image, from_p: Vector2, to_p: Vector2, color: Color):
	if not img: return

	var distance = from_p.distance_to(to_p)
	if distance < 0.1:
		_draw_brush_stroke_at_point(img, to_p, color)
		return

	var step_size = max(1.0, brush_radius * 0.5)
	var steps = int(ceil(distance / step_size))
	if steps == 0: steps = 1

	for i in range(steps + 1):
		var p = from_p.lerp(to_p, float(i) / steps)
		_draw_brush_stroke_at_point(img, p.floor(), color)
