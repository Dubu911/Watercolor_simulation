# removing_brush.gd
# A brush that removes/lightens pigment from the canvas (digital advantage feature)
extends Node

# --- Brush Properties ---
@export var base_brush_size: float = 2.0 # Base size for removal dabs
@export var removal_strength: float = 0.02 # How much pigment to remove per dab (0.0 to 1.0)

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

# --- Stroke Mask (prevents removing same pixel twice in one stroke) ---
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

# Cancel current stroke (called when UI is clicked to prevent ghost lines)
func cancel_stroke():
	is_painting = false

func set_active_color(new_color: Color):
	# Removing brush doesn't use color, but interface requires this method
	pass

func set_water_amount(new_amount: float):
	# Removing brush doesn't use water, but interface requires this method
	pass

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
			print("Removing Brush: Pressure at press (fallback to last motion): ", p)
		else:
			_end_stroke()

	# While moving with pen down, you'll get live pressure from motion
	elif event is InputEventMouseMotion and is_painting:
		# Debug to verify you see 0..1 values while drawing
		print("Removing Brush: Motion pressure: ", p)
		_continue_stroke(mouse_pos_img_space, p)

# Start a new stroke
func _start_new_stroke(pos: Vector2, pressure: float):
	is_painting = true
	current_pressure = pressure
	# IMPORTANT: Set last_paint_pos BEFORE painting to prevent ghost lines
	last_paint_pos = pos

	# Clear the stroke mask for new stroke
	_clear_stroke_mask()

	# Remove initial point (from pos to pos = just a dot)
	print("Removing Brush: Starting new stroke at: ", pos, " (last_paint_pos was: ", last_paint_pos, ")")
	_remove_stroke_segment(pos, pos, pressure)

# Continue an existing stroke
func _continue_stroke(pos: Vector2, pressure: float):
	current_pressure = pressure

	# Interpolate from last position to current position
	_remove_stroke_segment(last_paint_pos, pos, pressure)

	# Update last position
	last_paint_pos = pos

# End the current stroke
func _end_stroke():
	is_painting = false
	# Stroke mask will be cleared on next stroke start

# Remove pigment along a segment of the stroke (interpolated line)
func _remove_stroke_segment(from_pos: Vector2, to_pos: Vector2, pressure: float):
	# Calculate brush radius based on pressure
	var brush_radius = base_brush_size
	if pressure_affects_size:
		var pressure_mult = lerp(min_pressure_size_mult, max_pressure_size_mult, pressure)
		brush_radius = base_brush_size * pressure_mult

	# Calculate distance and interpolation steps
	var distance = from_pos.distance_to(to_pos)

	# Step size - smaller for smoother strokes (25% of radius = 4x overlap)
	var step_size = max(0.25, brush_radius * 0.25)
	var steps = max(1, int(ceil(distance / step_size)))

	# Remove at each interpolated point
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var remove_pos = from_pos.lerp(to_pos, t)
		_remove_circular_dab(remove_pos, brush_radius)

# Remove pigment in a circular dab at the given position
func _remove_circular_dab(center: Vector2, radius: float):
	if not is_instance_valid(coordinator_ref):
		return

	# Calculate removal strength based on current pressure
	# removal_strength is the base amount, scaled by pressure
	var effective_removal = removal_strength * current_pressure

	# Call GPU remove_paint function
	# This removes mobile layer first, then static layer
	# Removal amount is in pigment mass units
	if coordinator_ref.has_method("remove_paint_at"):
		coordinator_ref.remove_paint_at(center, radius, effective_removal)
	else:
		printerr("Coordinator missing remove_paint_at method!")
