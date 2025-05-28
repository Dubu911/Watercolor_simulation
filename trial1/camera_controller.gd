extends Camera2D

var is_panning: bool = false

# --- New variables for zooming ---
@export var zoom_factor: float = 1.1 # How much to zoom in/out per scroll step
									 # Values > 1. Greater means faster zoom.
@export var min_zoom: float = 0.2    # Smallest zoom value (most zoomed in)
@export var max_zoom: float = 5.0    # Largest zoom value (most zoomed out)
# ---------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.is_pressed():
				is_panning = true
			else:
				is_panning = false

	if event is InputEventMouseMotion:
		if is_panning:
			position -= event.relative
			
	# --- Mouse Wheel Zoom Logic (new) ---
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
	# --- End Mouse Wheel Zoom Logic ---
