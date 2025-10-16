# pencil_brush.gd
extends Node

# --- Pencil Properties ---
@export var base_pencil_size: float = 0.5  # Controls both size and intensity range (starts at minimum)
@export var base_pencil_color: Color = Color.BLACK  # Base color (RGB)

# --- Internal State ---
var coordinator_ref
var is_painting: bool = false
var last_pos: Vector2 = Vector2.INF
var current_pressure: float = 1.0
var canvas_width: int = 64
var canvas_height: int = 64

# --- Pencil Size Range (1 pixel to ~10% of canvas dimension) ---
const MIN_PENCIL_SIZE: float = 0.5  # Single pixel (radius 0.5 draws only center)
var max_pencil_size: float = 6.4  # Will be set to canvas dimension * 0.1

func activate(coordinator):
	coordinator_ref = coordinator
	is_painting = false
	last_pos = Vector2.INF

	# Get canvas dimensions
	if coordinator_ref:
		canvas_width = coordinator_ref.CANVAS_WIDTH
		canvas_height = coordinator_ref.CANVAS_HEIGHT
		# Max size is 10% of canvas dimension
		# For 64x64 canvas: 64 * 0.1 = 6.4 pixel radius
		max_pencil_size = min(canvas_width, canvas_height) * 0.05

func deactivate():
	is_painting = false
	last_pos = Vector2.INF

func set_pencil_size(size: float):
	# Size is normalized 0.0-1.0, map to actual pixel range
	base_pencil_size = lerp(MIN_PENCIL_SIZE, max_pencil_size, size)

func handle_input(event: InputEvent, mouse_pos_img_space: Vector2):
	if not is_instance_valid(coordinator_ref):
		return

	# Extract pressure from event
	var pressure = 1.0
	if event is InputEventMouseButton:
		if "pressure" in event:
			pressure = event.pressure
		else:
			pressure = 1.0
	elif event is InputEventMouseMotion:
		if "pressure" in event:
			pressure = event.pressure
		else:
			pressure = 1.0

	current_pressure = pressure
	var current_draw_pos = mouse_pos_img_space.floor()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_painting = true
			last_pos = current_draw_pos
			# Draw initial dot
			_draw_pencil_stroke(last_pos, current_draw_pos, pressure)
		else:
			is_painting = false
			last_pos = Vector2.INF

	elif event is InputEventMouseMotion and is_painting:
		if last_pos != Vector2.INF:
			_draw_pencil_stroke(last_pos, current_draw_pos, pressure)
		last_pos = current_draw_pos

func _draw_pencil_stroke(from_pos: Vector2, to_pos: Vector2, pressure: float):
	if not coordinator_ref.has_method("draw_line_on_pencil_layer"):
		return

	# Calculate intensity based on pencil size and pressure
	# Larger pencil size = higher maximum intensity
	# base_pencil_size ranges from 1.0 to max_pencil_size (e.g., 6.4)
	# Normalize size to 0-1 range for intensity calculation
	var size_range = max_pencil_size - MIN_PENCIL_SIZE
	var size_normalized = 0.0
	if size_range > 0.0:
		size_normalized = (base_pencil_size - MIN_PENCIL_SIZE) / size_range

	# Intensity range: small pencil = 0.1 to 0.5, large pencil = 0.3 to 1.0
	var min_intensity = lerp(0.1, 0.3, size_normalized)
	var max_intensity = lerp(0.5, 1.0, size_normalized)

	# Apply pressure to intensity within the range
	var intensity = lerp(min_intensity, max_intensity, pressure)

	# Create color with calculated intensity (alpha)
	var pencil_color = Color(base_pencil_color.r, base_pencil_color.g, base_pencil_color.b, intensity)

	# Draw the line
	coordinator_ref.draw_line_on_pencil_layer(from_pos, to_pos, pencil_color, base_pencil_size)
