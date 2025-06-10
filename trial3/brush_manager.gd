# brush_manager.gd
extends Node

# --- Path Managements ---
@export var painting_coordinator_path: NodePath
@export var watercolor_brush_path: NodePath
@export var pencil_brush_path: NodePath
@export var eraser_brush_path: NodePath
@export var layer_for_mouse_pos_path: NodePath


# --- Internal References to PathNode ---
var painting_coordinator: Node
var watercolor_brush: Node
var pencil_brush: Node
var eraser_brush: Node
var layer_for_mouse_pos: Sprite2D

var last_selected_color: Color = Color(0.1, 0.2, 0.8, 0.5)

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

	# Deactivate the current brush if it exists
	var current_active_brush = painting_coordinator.get("active_brush_node")
	if is_instance_valid(current_active_brush) and current_active_brush.has_method("deactivate"):
		current_active_brush.deactivate()

	# Tell the coordinator to set its new active brush
	# We call a function on the coordinator instead of changing its variable directly.
	if painting_coordinator.has_method("set_active_brush"):
		painting_coordinator.set_active_brush(new_brush)
	else:
		printerr("BrushManager ERROR: PaintingCoordinator is missing the 'set_active_brush' method!")

	# Activate the new brush
	if is_instance_valid(new_brush) and new_brush.has_method("activate"):
		new_brush.activate(painting_coordinator)
		
	# If the new brush is colorable, update its color to the last selected color
	if new_brush != eraser_brush and new_brush.has_method("set_active_color"):
		new_brush.set_active_color(last_selected_color)


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

# to do : custom color palette UI to this function in the future.
func _on_color_selected(new_color: Color):
	last_selected_color = new_color
	
	var current_active_brush = painting_coordinator.get("active_brush_node")
	# Update the color of the active brush, if it's not the eraser
	if is_instance_valid(current_active_brush) and current_active_brush != eraser_brush:
		if current_active_brush.has_method("set_active_color"):
			current_active_brush.set_active_color(last_selected_color)
