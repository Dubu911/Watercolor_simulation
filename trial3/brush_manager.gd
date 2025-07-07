# brush_manager.gd
extends Node

# --- Path Managements ---
@export var painting_coordinator_path: NodePath
@export var watercolor_brush_path: NodePath
@export var pencil_brush_path: NodePath
@export var eraser_brush_path: NodePath
@export var layer_for_mouse_pos_path: NodePath
@export var current_color_display_path: NodePath

# --- Internal References to PathNode ---
var painting_coordinator: Node
var watercolor_brush: Node
var pencil_brush: Node
var eraser_brush: Node
var layer_for_mouse_pos: Sprite2D

# --- Current Brush State ---
var selected_pigments: Array[Color] = []
var current_pigment_color: Color = Color.BLACK 
var current_water_amount: float = 0.05 # Default value

func _ready():
	# Get the actual nodes from the NodePaths. Add robust checks.
	painting_coordinator = get_node_or_null(painting_coordinator_path)
	if not painting_coordinator:
		printerr("brush_manager ERROR: painting_coordinator not found! Check the NodePath.")
		return

	watercolor_brush = get_node_or_null(watercolor_brush_path)
	if not watercolor_brush:
		printerr("brush_manager ERROR: watercolor_brush not found! Check the NodePath.")

	pencil_brush = get_node_or_null(pencil_brush_path)
	if not pencil_brush:
		printerr("brush_manager ERROR: pencil_brush not found! Check the NodePath.")

	eraser_brush = get_node_or_null(eraser_brush_path)
	if not eraser_brush:
		printerr("brush_manager ERROR: eraser_brush not found! Check the NodePath.")
		
	layer_for_mouse_pos = get_node_or_null(layer_for_mouse_pos_path) as Sprite2D
	if not layer_for_mouse_pos:
		printerr("BrushManager ERROR: LayerForMousePos not found! Assign a Sprite2D in the Inspector.")
		return
		
	# Set the initial brush when the game starts
	if watercolor_brush:
		_set_active_brush(watercolor_brush)
	
	get_node(current_color_display_path).color = current_pigment_color

func _unhandled_input(event: InputEvent):
	# Get the currently active brush from the coordinator
	var active_brush_node = painting_coordinator.get("active_brush_node")

	# Exit if we don't have a valid brush, coordinator, or layer reference
	if not is_instance_valid(active_brush_node) or \
	not is_instance_valid(painting_coordinator) or \
	not is_instance_valid(layer_for_mouse_pos):
		return

	# Calculate the mouse position in the coordinate space of our canvas layers
	var global_mouse_pos = layer_for_mouse_pos.get_global_mouse_position()
	var mouse_pos_in_image_space = layer_for_mouse_pos.to_local(global_mouse_pos)

	# Pass the event and the calculated position to the active brush's handle_input method
	if active_brush_node.has_method("handle_input"):
		active_brush_node.handle_input(event, mouse_pos_in_image_space)


# This function is the core of the BrushManager's job. It tells the coordinator
# which brush should now be considered the "active" one.
func _set_active_brush(new_brush: Node):
	if not is_instance_valid(painting_coordinator): return

	var current_active_brush = painting_coordinator.get("active_brush_node")
	if is_instance_valid(current_active_brush) and current_active_brush.has_method("deactivate"):
		current_active_brush.deactivate()

	if painting_coordinator.has_method("set_active_brush"):
		painting_coordinator.set_active_brush(new_brush)
	else:
		printerr("BrushManager ERROR: Coordinator missing 'set_active_brush' method!")

	if is_instance_valid(new_brush) and new_brush.has_method("activate"):
		new_brush.activate(painting_coordinator)
		
	_update_active_brush_properties()
	
func _update_active_brush_properties():
	var active_brush = painting_coordinator.get("active_brush_node")
	if not is_instance_valid(active_brush): return
	# Update color for any brush that isn't the eraser
	if active_brush != eraser_brush and active_brush.has_method("set_active_color"):
		active_brush.set_active_color(current_pigment_color)
	# Update water amount only for the watercolor brush
	if active_brush == watercolor_brush and active_brush.has_method("set_water_amount"):
		active_brush.set_water_amount(current_water_amount)

# This function adds or removes a color from our list
func _toggle_pigment(is_on: bool, color: Color):
	if is_on:
		if not selected_pigments.has(color):
			selected_pigments.append(color)
	else:
		if selected_pigments.has(color):
			selected_pigments.erase(color)

	_mix_and_update_brush()

# This function calculates the final mixed color
func _mix_and_update_brush():
	if selected_pigments.is_empty():
		# If no colors are selected, maybe default to black or a neutral gray
		current_pigment_color = Color.BLACK
	else:
		# Simple averaging/blending of all selected colors
		var mixed_color = selected_pigments[0]
		for i in range(1, selected_pigments.size()):
			mixed_color = mixed_color.blend(selected_pigments[i])
		current_pigment_color = mixed_color

	# Now that we have the final color, update the brush
	_update_active_brush_properties()

	# Update the color of the "current color" display square
	get_node(current_color_display_path).color = current_pigment_color

# --- UI Signal Receivers ---
# Connect the 'pressed' signal from your UI Buttons to these functions.

func _on_watercolor_button_pressed():
	if watercolor_brush:
		print("brush_manager: Watercolor Brush selected")
		_set_active_brush(watercolor_brush)

func _on_pencil_button_pressed():
	if pencil_brush:
		print("brush_manager: Pencil Brush selected")
		_set_active_brush(pencil_brush)

func _on_eraser_button_pressed():
	if eraser_brush:
		print("brush_manager: Eraser Brush selected")
		_set_active_brush(eraser_brush)

func _on_magenta_button_toggled(is_on: bool):
	var magenta_color = Color(0.9, 0.1, 0.4, 0.5)
	_toggle_pigment(is_on, magenta_color)

func _on_cyan_button_toggled(is_on: bool):
	var cyan_color = Color(0.0, 0.6, 0.9, 0.5)
	_toggle_pigment(is_on, cyan_color)

func _on_yellow_button_toggled(is_on: bool):
	var yellow_color = Color(1.0, 0.9, 0.2, 0.5)
	_toggle_pigment(is_on, yellow_color)

func _on_water_slider_value_changed(value: float):
	# The slider's value is from 0 to 1
	current_water_amount = value
	print("Current water amount : ", value)
	_update_active_brush_properties()
