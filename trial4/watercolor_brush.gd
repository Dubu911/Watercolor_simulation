# watercolor_brush.gd (Refactored with pressure support and stroke masking)
extends Node

# --- Brush Properties ---
@export var brush_color: Color = Color.BLACK # Color and alpha (pigment concentration)
@export var water_amount: float = 0.05 # How much water this brush lays down (0.0 to 1.0)
@export var base_brush_size: float = 2.0 # Base size for dabs

# --- Pressure Settings ---
@export var pressure_affects_size: bool = true # Does pressure change brush size?
@export var min_pressure_size_mult: float = 0.1 # Minimum size multiplier at light pressure
@export var max_pressure_size_mult: float = 2.0 # Maximum size multiplier at full pressure

# --- Internal State ---
var coordinator_ref # Reference to the painting_coordinator
var is_painting: bool = false # Tracks if the pen/mouse button is held
var current_pressure: float = 1.0 # Current pressure (1.0 for mouse, 0.0-1.0 for tablet)
var last_paint_pos: Vector2 = Vector2.ZERO # Last position for interpolation
var _last_motion_pressure: float = 1.0 # Updated from motion events

# --- Stroke Mask (prevents painting same pixel twice in one stroke) ---
var stroke_mask: Array  # 2D array [y][x] of booleans
var canvas_width: int = 0
var canvas_height: int = 0

func activate(coordinator):
	coordinator_ref = coordinator
	is_painting = false

	# Get canvas dimensions from coordinator
	canvas_width = coordinator_ref.CANVAS_WIDTH
	canvas_height = coordinator_ref.CANVAS_HEIGHT

	# Initialize stroke mask with canvas dimensions
	_initialize_stroke_mask()

# Helper to safely read pressure from input events
func _event_pressure(event: InputEvent) -> float:
	# Read pressure safely only from motion; buttons may not have it on some platforms.
	if event is InputEventMouseMotion:
		# Only touch .pressure if it exists
		var p = 1.0
		if "pressure" in event:
			p = event.pressure
		# Use actual pressure value, with a small minimum to prevent invisible strokes
		_last_motion_pressure = max(p, 0.05)
		return _last_motion_pressure

	# For button events, reuse the last known motion pressure (or default to 0.5)
	return _last_motion_pressure if _last_motion_pressure > 0.0 else 0.5

func deactivate():
	is_painting = false

func set_active_color(new_color: Color):
	self.brush_color = new_color

func set_water_amount(new_amount: float):
	self.water_amount = new_amount

# Initialize the stroke mask array
func _initialize_stroke_mask():
	stroke_mask = []
	for y in range(canvas_height):
		var row = []
		row.resize(canvas_width)
		row.fill(false)
		stroke_mask.append(row)

# Clear the stroke mask (all pixels unpainted)
func _clear_stroke_mask():
	for y in range(canvas_height):
		for x in range(canvas_width):
			stroke_mask[y][x] = false

# Handle input from brush_manager
func handle_input(event: InputEvent, mouse_pos_img_space: Vector2):
	if not is_instance_valid(coordinator_ref):
		return

	var p = _event_pressure(event)

	# Start/end stroke on button; don't access event.pressure here.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			_start_new_stroke(mouse_pos_img_space, p)
			print("Pressure at press (fallback to last motion): ", p)
		else:
			_end_stroke()

	# While moving with pen down, you'll get live pressure from motion
	elif event is InputEventMouseMotion and is_painting:
		# Debug to verify you see 0..1 values while drawing
		print("Motion pressure: ", p)
		_continue_stroke(mouse_pos_img_space, p)

# Start a new stroke
func _start_new_stroke(pos: Vector2, pressure: float):
	is_painting = true
	current_pressure = pressure
	last_paint_pos = pos

	# Clear the stroke mask for new stroke
	_clear_stroke_mask()

	# Paint initial point
	_paint_stroke_segment(pos, pos, pressure)

# Continue an existing stroke
func _continue_stroke(pos: Vector2, pressure: float):
	current_pressure = pressure

	# Interpolate from last position to current position
	_paint_stroke_segment(last_paint_pos, pos, pressure)

	# Update last position
	last_paint_pos = pos

# End the current stroke
func _end_stroke():
	is_painting = false
	# Stroke mask will be cleared on next stroke start

# Paint a segment of the stroke (interpolated line)
func _paint_stroke_segment(from_pos: Vector2, to_pos: Vector2, pressure: float):
	# Calculate brush radius based on pressure
	var brush_radius = base_brush_size
	if pressure_affects_size:
		var pressure_mult = lerp(min_pressure_size_mult, max_pressure_size_mult, pressure)
		brush_radius = base_brush_size * pressure_mult

	# Calculate distance and interpolation steps
	var distance = from_pos.distance_to(to_pos)

	# Step size - smaller for smoother strokes (25% of radius for good overlap)
	var step_size = max(0.25, brush_radius * 0.25)
	var steps = max(1, int(ceil(distance / step_size)))

	# Paint at each interpolated point
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var paint_pos = from_pos.lerp(to_pos, t)
		_paint_circular_dab(paint_pos, brush_radius)

# Paint a circular dab at the given position
func _paint_circular_dab(center: Vector2, radius: float):
	var i_radius = int(ceil(radius))

	# Iterate over bounding box of the circle
	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			# Check if point is inside circle
			var distance = Vector2(x_offset, y_offset).length()
			if distance <= radius:
				var pixel_x = int(center.x + x_offset)
				var pixel_y = int(center.y + y_offset)

				# Check bounds
				if pixel_x >= 0 and pixel_x < canvas_width and pixel_y >= 0 and pixel_y < canvas_height:
					# Check stroke mask - only paint if not already painted
					if not stroke_mask[pixel_y][pixel_x]:
						_paint_pixel(pixel_x, pixel_y)
						stroke_mask[pixel_y][pixel_x] = true

# Paint a single pixel via coordinator
func _paint_pixel(x: int, y: int):
	if coordinator_ref.has_method("paint_watercolor_pixel"):
		coordinator_ref.paint_watercolor_pixel(x, y, brush_color, water_amount, current_pressure)
	else:
		printerr("watercolor_brush ERROR: Coordinator missing 'paint_watercolor_pixel' method!")
