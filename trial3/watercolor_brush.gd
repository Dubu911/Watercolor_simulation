# watercolor_brush.gd (Refactored to work with the new Coordinator)
extends Node

# --- Brush Properties ---
@export var brush_color: Color = Color(0.1, 0.2, 0.8, 0.5) # Color and alpha (pigment concentration)
@export var water_amount: float = 0.8 # How much water this brush lays down (0.0 to 1.0)
@export var base_brush_size: float = 25.0 # Base size for dabs
@export var dabs_per_frame: int = 5     # How many dabs to make while dragging

# --- Internal ---
var coordinator_ref # Reference to the painting_coordinator
var is_painting: bool = false # Tracks if the mouse button is held for painting

func set_active_color(new_color: Color):
	self.brush_color = new_color

func activate(coordinator):
	coordinator_ref = coordinator
	is_painting = false

func deactivate():
	is_painting = false

# This function is called by the BrushManager, which gets the input event.
func handle_input(event: InputEvent, mouse_pos_img_space: Vector2):
	if not is_instance_valid(coordinator_ref):
		# This brush can't do anything without a coordinator to talk to.
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_painting = true
			# Apply a burst of dabs on initial click
			for i in range(dabs_per_frame * 2): # More dabs on initial press
				_apply_paint_dab(mouse_pos_img_space)
		else: # Mouse button released
			is_painting = false
			
	elif event is InputEventMouseMotion and is_painting:
		# Apply dabs continuously while dragging
		for i in range(dabs_per_frame):
			_apply_paint_dab(mouse_pos_img_space)


# It calculates properties and tells the coordinator to add paint.
func _apply_paint_dab(position_on_image: Vector2):
	# Calculate dab position with some randomness based on brush size
	var dab_pos = position_on_image
	var offset_radius = base_brush_size * 0.5
	dab_pos.x += randf_range(-offset_radius, offset_radius)
	dab_pos.y += randf_range(-offset_radius, offset_radius)

	# Calculate randomized dab properties
	var dab_size = base_brush_size * randf_range(0.7, 1.3)
	
	# Create a color with randomized alpha to simulate varying pigment density
	var dab_color = brush_color
	dab_color.a *= randf_range(0.8, 1.2) # Vary pigment concentration slightly

	# Vary water amount slightly per dab
	var dab_water = water_amount * randf_range(0.9, 1.1)

	# Tell the Coordinator to Add Paint
	# This is where the brush's responsibility ends.
	if coordinator_ref.has_method("add_paint_at"):
		coordinator_ref.add_paint_at(dab_pos, dab_color, dab_water, dab_size)
	else:
		printerr(name + ": Coordinator does not have an 'add_paint_at' method!")
