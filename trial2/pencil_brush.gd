# pencil_brush.gd
extends Node2D

@export var brush_radius: float = 3.0 # Radius for the pencil tip
@export var brush_color: Color = Color.BLACK

var coordinator_ref
var last_pos: Vector2 = Vector2.INF # For line drawing

func activate(coordinator):
	coordinator_ref = coordinator
	# print(name + " activated.") # Debug print removed
	last_pos = Vector2.INF

func handle_input(event: InputEvent, mouse_pos_img_space: Vector2, target_image: Image, coordinator):
	if not coordinator_ref: coordinator_ref = coordinator

	var current_draw_pos = mouse_pos_img_space.floor()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			last_pos = current_draw_pos
			_draw_brush_stroke_at_point(target_image, last_pos, brush_color)
		else: # Released
			last_pos = Vector2.INF

	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if last_pos != Vector2.INF:
			_draw_line_with_brush(target_image, last_pos, current_draw_pos, brush_color)
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
					img.set_pixel(draw_x, draw_y, color) # Direct set for pencil
	
	if coordinator_ref:
		coordinator_ref.mark_pencil_dirty()

func _draw_line_with_brush(img: Image, from_p: Vector2, to_p: Vector2, color: Color):
	if not img: return
	
	# Draw circles along the line path
	var distance = from_p.distance_to(to_p)
	if distance < 0.1: # If it's essentially a dot
		_draw_brush_stroke_at_point(img, to_p, color)
		return

	# Determine number of steps based on brush radius to avoid gaps
	# Step size should be smaller than or equal to the radius for good coverage
	var step_size = max(1.0, brush_radius * 0.5) # Ensure step_size is at least 1
	var steps = int(ceil(distance / step_size))
	if steps == 0: steps = 1

	for i in range(steps + 1):
		var p = from_p.lerp(to_p, float(i) / steps)
		_draw_brush_stroke_at_point(img, p.floor(), color)
	
	# The mark_pencil_dirty() is called by _draw_brush_stroke_at_point
