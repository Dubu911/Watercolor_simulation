# eraser_brush.gd
extends Node

# --- Eraser Properties ---
@export var base_eraser_size: float = 3.0  # Eraser radius in pixels

# --- Internal State ---
var coordinator_ref
var is_painting: bool = false
var last_pos: Vector2 = Vector2.INF
var canvas_width: int = 64
var canvas_height: int = 64

# --- Eraser Size Range ---
const MIN_ERASER_SIZE: float = 0.5  # Single pixel
var max_eraser_size: float = 6.4  # Will be set to canvas dimension * 0.1

func activate(coordinator):
	coordinator_ref = coordinator
	is_painting = false
	last_pos = Vector2.INF

	# Get canvas dimensions
	if coordinator_ref:
		canvas_width = coordinator_ref.CANVAS_WIDTH
		canvas_height = coordinator_ref.CANVAS_HEIGHT
		# Max size is 10% of canvas dimension
		max_eraser_size = min(canvas_width, canvas_height) * 0.1

func deactivate():
	is_painting = false
	last_pos = Vector2.INF

func set_eraser_size(size: float):
	# Size is normalized 0.0-1.0, map to actual pixel range
	base_eraser_size = lerp(MIN_ERASER_SIZE, max_eraser_size, size)

func handle_input(event: InputEvent, mouse_pos_img_space: Vector2):
	if not is_instance_valid(coordinator_ref):
		return

	var current_draw_pos = mouse_pos_img_space.floor()
	var eraser_color = Color(0, 0, 0, 0) # Erasing is just drawing with transparency

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_painting = true
			last_pos = current_draw_pos
			# For a single click, draw a line from the point to itself (a dot)
			if coordinator_ref.has_method("draw_line_on_pencil_layer"):
				coordinator_ref.draw_line_on_pencil_layer(last_pos, current_draw_pos, eraser_color, base_eraser_size)
		else: # Released
			is_painting = false
			last_pos = Vector2.INF

	elif event is InputEventMouseMotion and is_painting:
		if last_pos != Vector2.INF:
			if coordinator_ref.has_method("draw_line_on_pencil_layer"):
				coordinator_ref.draw_line_on_pencil_layer(last_pos, current_draw_pos, eraser_color, base_eraser_size)
		last_pos = current_draw_pos
