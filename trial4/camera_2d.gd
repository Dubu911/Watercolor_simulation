extends Camera2D

var is_panning: bool = false

# --- New variables for zooming ---
@export var zoom_factor: float = 1.1 # How much to zoom in/out per scroll step
									 # Values > 1. Greater means faster zoom.
@export var min_zoom: float = 0.2    # Smallest zoom value (most zoomed in)
@export var max_zoom: float = 10.0    # Largest zoom value (most zoomed out)
# ---------------------------------

func _ready():
	# Get canvas size from painting_coordinator
	var painting_coordinator = get_node_or_null("../painting_coordinator")
	if painting_coordinator:
		var canvas_width = painting_coordinator.CANVAS_WIDTH
		var canvas_height = painting_coordinator.CANVAS_HEIGHT

		# Center camera on canvas
		offset = Vector2(canvas_width / 2.0, canvas_height / 2.0)

		# Set reasonable initial zoom based on canvas size
		# Adjust zoom so canvas fits nicely on screen
		var screen_size = get_viewport().get_visible_rect().size
		var zoom_x = screen_size.x / canvas_width * 0.8
		var zoom_y = screen_size.y / canvas_height * 0.8
		var initial_zoom = min(zoom_x, zoom_y)
		zoom = Vector2(initial_zoom, initial_zoom)
	else:
		# Fallback if coordinator not found
		offset = Vector2(256, 256)
		zoom = Vector2(2.0, 2.0)

func _process(_delta: float) -> void:
	# Check middle mouse button state every frame (works even when other windows are focused)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		if not is_panning:
			is_panning = true
	else:
		is_panning = false

func _input(event: InputEvent) -> void:
	# Handle panning motion - always process if middle button is held
	if event is InputEventMouseMotion:
		if is_panning:
			# Pan the camera regardless of which window has focus
			position -= event.relative / zoom  # Adjust for zoom level
			# Mark as handled so it doesn't propagate further
			get_viewport().set_input_as_handled()

	# --- Mouse Wheel Zoom Logic ---
	# Check if the event is a mouse button event (scroll wheel events are also button events)
	if event is InputEventMouseButton:
		if event.is_pressed(): # Process scroll only on the press event
			var new_zoom := zoom # Start with current zoom

			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: # =Zoom In
				new_zoom /= zoom_factor
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP: # Zoom Out
				new_zoom *= zoom_factor

			# Clamp the zoom to stay within min_zoom and max_zoom
			# We apply clamp to both x and y components of the zoom Vector2
			new_zoom.x = clampf(new_zoom.x, min_zoom, max_zoom)
			new_zoom.y = clampf(new_zoom.y, min_zoom, max_zoom)

			zoom = new_zoom # Apply the new (potentially clamped) zoom
