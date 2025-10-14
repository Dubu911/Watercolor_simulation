# brush_manager.gd
extends Node

# --- Path Managements ---
@export var painting_coordinator_path: NodePath
@export var watercolor_brush_path: NodePath
@export var pencil_brush_path: NodePath
@export var eraser_brush_path: NodePath
@export var layer_for_mouse_pos_path: NodePath
@export var current_color_display_path: NodePath
@export var color_picker_path: NodePath
@export var brush_size_popup_path: NodePath
@export var brush_size_value_label_path: NodePath

# --- Internal References to PathNode ---
var painting_coordinator: Node
var watercolor_brush: Node
var pencil_brush: Node
var eraser_brush: Node
var layer_for_mouse_pos: Sprite2D
var current_color_display: ColorRect
var color_picker: ColorPicker
var brush_size_popup: PanelContainer
var brush_size_value_label: Label

# --- Current Brush State ---
var current_hue: Color = Color.RED  # Base hue (RGB only, alpha ignored)
var current_pigment_alpha: float = 0.5  # Pigment concentration (0.0 - 1.0)
var current_pigment_color: Color = Color(1.0, 0.0, 0.0, 0.5)  # Final color with alpha
var current_water_amount: float = 0.1  # Water amount


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

	current_color_display = get_node_or_null(current_color_display_path) as ColorRect
	if not current_color_display:
		printerr("BrushManager ERROR: CurrentColorDisplay not found!")
		return

	color_picker = get_node_or_null(color_picker_path) as ColorPicker
	if not color_picker:
		printerr("BrushManager ERROR: ColorPicker not found!")
		return

	brush_size_popup = get_node_or_null(brush_size_popup_path) as PanelContainer
	if not brush_size_popup:
		printerr("BrushManager ERROR: BrushSizePopup not found!")

	brush_size_value_label = get_node_or_null(brush_size_value_label_path) as Label
	if not brush_size_value_label:
		printerr("BrushManager ERROR: BrushSizeValueLabel not found!")

	# Note: Signals are connected in the scene file (main3.tscn)

	# Set the initial brush and update its properties
	if watercolor_brush:
		_set_active_brush(watercolor_brush)

	# Initialize the UI on start
	_update_color_display()

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

# Updates the final pigment color based on hue and alpha
func _update_pigment_color():
	# Combine the hue (RGB) with pigment concentration (alpha)
	current_pigment_color = Color(current_hue.r, current_hue.g, current_hue.b, current_pigment_alpha)
	_update_active_brush_properties()
	_update_color_display()

func _update_color_display():
	if is_instance_valid(current_color_display):
		current_color_display.color = current_pigment_color


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
	if active_brush == watercolor_brush:
		active_brush.set_active_color(current_pigment_color)
		active_brush.set_water_amount(current_water_amount)
	
# --- UI Signal Receivers ---
# Connect these signals from your UI controls

func _on_watercolor_button_pressed():
	if watercolor_brush:
		print("brush_manager: Watercolor Brush selected")
		_set_active_brush(watercolor_brush)

		# Toggle brush size popup
		if is_instance_valid(brush_size_popup):
			brush_size_popup.visible = not brush_size_popup.visible

func _on_pencil_button_pressed():
	if pencil_brush:
		print("brush_manager: Pencil Brush selected")
		_set_active_brush(pencil_brush)

func _on_eraser_button_pressed():
	if eraser_brush:
		print("brush_manager: Eraser Brush selected")
		_set_active_brush(eraser_brush)

# Called when the color picker color changes
func _on_color_picker_changed(new_color: Color):
	# Extract just the RGB (hue), ignore alpha from color picker
	current_hue = Color(new_color.r, new_color.g, new_color.b, 1.0)
	_update_pigment_color()
	print("Color changed to: ", current_hue)

# Called when pigment concentration (alpha) slider changes
func _on_pigment_alpha_slider_changed(value: float):
	current_pigment_alpha = value
	_update_pigment_color()
	print("Pigment concentration: ", value)

# Called when water amount slider changes
func _on_water_slider_value_changed(value: float):
	current_water_amount = value
	_update_active_brush_properties()
	print("Water amount: ", value)

# Called when brush size slider changes
func _on_brush_size_slider_changed(value: float):
	if is_instance_valid(watercolor_brush):
		watercolor_brush.base_brush_size = value

		# Update the label to show current size
		if is_instance_valid(brush_size_value_label):
			brush_size_value_label.text = "%.1f" % value

		print("Brush size: ", value)
