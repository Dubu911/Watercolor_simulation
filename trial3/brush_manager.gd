# brush_manager.gd
extends Node

# --- Path Managements ---
@export var painting_coordinator_path: NodePath
@export var watercolor_brush_path: NodePath
@export var pencil_brush_path: NodePath
@export var eraser_brush_path: NodePath
@export var layer_for_mouse_pos_path: NodePath
@export var current_color_display_path: NodePath
@export var magenta_button_path: NodePath
@export var cyan_button_path: NodePath
@export var yellow_button_path: NodePath

# --- Internal References to PathNode ---
var painting_coordinator: Node
var watercolor_brush: Node
var pencil_brush: Node
var eraser_brush: Node
var layer_for_mouse_pos: Sprite2D
var current_color_display: ColorRect
var magenta_button: Button
var cyan_button: Button
var yellow_button: Button

# --- Current Brush State ---
var current_pigment_color: Color = Color.GRAY 
var current_water_amount: float = 0.1 # Default value

# A dictionary to store the state of each pigment.
# The key is the pure color, the value is another dictionary holding its state.
var pigment_states = {
	Color(1.0, 0.0, 1.0, 1.0): {"selected": false, "alpha": 0.5, "button_node": null}, # Magenta
	Color(0.0, 1.0, 1.0, 1.0): {"selected": false, "alpha": 0.5, "button_node": null}, # Cyan
	Color(1.0, 1.0, 0.0, 1.0): {"selected": false, "alpha": 0.5, "button_node": null}  # Yellow
}


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
	
	magenta_button = get_node_or_null(magenta_button_path) as Button
	if not magenta_button: 
		printerr("BrushManager ERROR: magenta_button not found!")
		return
	pigment_states[Color(1.0, 0.0, 1.0, 1.0)].button_node = magenta_button
		
	cyan_button = get_node_or_null(cyan_button_path) as Button
	if not cyan_button: 
		printerr("BrushManager ERROR: cyan_button not found!")
		return
	pigment_states[Color(0.0, 1.0, 1.0, 1.0)].button_node = cyan_button
		
	yellow_button = get_node_or_null(yellow_button_path) as Button
	if not yellow_button: 
		printerr("BrushManager ERROR: yellow_button not found!")
		return
	pigment_states[Color(1.0, 1.0, 0.0, 1.0)].button_node = yellow_button
	# Set the initial brush and update its properties
	if watercolor_brush:
		_set_active_brush(watercolor_brush)
	
	# Initialize the UI on start
	_update_all_button_visuals()
	_mix_and_update_all()

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

# This function calculates the final mixed color and updates both the brush and the UI
# --- The core logic for calculating the final brush color ---
func _mix_and_update_all():
	# 1. Mix the RGB values using subtractive mixing (multiplication)
	var final_rgb_color = Color.WHITE
	var pigments_in_mix = 0
	for pigment_hue in pigment_states:
		var state = pigment_states[pigment_hue]
		if state.selected:
			final_rgb_color.r *= pigment_hue.r
			final_rgb_color.g *= pigment_hue.g
			final_rgb_color.b *= pigment_hue.b
			pigments_in_mix += 1
	
	if pigments_in_mix == 0:
		final_rgb_color = Color.BLACK 

	# 2. Calculate the final ALPHA by layering the selected pigments
	var final_alpha_color = Color(1, 1, 1, 0) # Start with transparent white
	for pigment_hue in pigment_states:
		var state = pigment_states[pigment_hue]
		if state.selected:
			var current_pigment = Color(pigment_hue.r, pigment_hue.g, pigment_hue.b, state.alpha)
			final_alpha_color = _layer_colors(current_pigment, final_alpha_color)
			
	# 3. Create the final color and update the brush
	current_pigment_color = Color(final_rgb_color.r, final_rgb_color.g, final_rgb_color.b, final_alpha_color.a)
	_update_active_brush_properties()
	
	# 4. Update the UI display
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
	if active_brush != eraser_brush and active_brush.has_method("set_active_color"):
		active_brush.set_active_color(current_pigment_color)
	# Update water amount only for the watercolor brush
	if active_brush == watercolor_brush:
		active_brush.set_active_color(current_pigment_color)
		active_brush.set_water_amount(current_water_amount)

func _update_all_button_visuals():
	for pigment_hue in pigment_states:
		_update_button_visual(pigment_hue)

func _update_button_visual(hue: Color):
	var state = pigment_states[hue]
	var button = state.button_node # Corrected from "botten_node"
	if not is_instance_valid(button): return
	
	var alpha = state.alpha
	var display_color = Color(hue.r, hue.g, hue.b, alpha)
	
	var normal_stylebox = StyleBoxFlat.new()
	normal_stylebox.bg_color = display_color
	normal_stylebox.border_width_left = 2
	normal_stylebox.border_width_right = 2
	normal_stylebox.border_width_top = 2
	normal_stylebox.border_width_bottom = 2
	normal_stylebox.border_color = Color(0.3, 0.3, 0.3, 0.8)
	
	var pressed_stylebox = normal_stylebox.duplicate()
	pressed_stylebox.border_color = Color(1, 1, 0.8, 1)
	pressed_stylebox.border_width_left = 4
	pressed_stylebox.border_width_right = 4
	pressed_stylebox.border_width_top = 4
	pressed_stylebox.border_width_bottom = 4

	button.add_theme_stylebox_override("normal", normal_stylebox)
	button.add_theme_stylebox_override("pressed", pressed_stylebox)

# Helper functions
func _layer_colors(source_color: Color, dest_color: Color) -> Color:
	var out_a = source_color.a + dest_color.a * (1.0 - source_color.a)
	if out_a < 0.0001: return Color(1, 1, 1, 0)
	var out_r = (source_color.r * source_color.a + dest_color.r * dest_color.a * (1.0 - source_color.a)) / out_a
	var out_g = (source_color.g * source_color.a + dest_color.g * dest_color.a * (1.0 - source_color.a)) / out_a
	var out_b = (source_color.b * source_color.a + dest_color.b * dest_color.a * (1.0 - source_color.a)) / out_a
	return Color(out_r, out_g, out_b, out_a)
	
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
	var magenta_hue = Color(1.0, 0.0, 1.0)
	pigment_states[magenta_hue].selected = is_on
	_update_button_visual(magenta_hue)
	_mix_and_update_all()

func _on_cyan_button_toggled(is_on: bool):
	var cyan_hue = Color(0.0, 1.0, 1.0)
	pigment_states[cyan_hue].selected = is_on
	_update_button_visual(cyan_hue)
	_mix_and_update_all()

func _on_yellow_button_toggled(is_on: bool):
	var yellow_hue = Color(1.0, 1.0, 0.0)
	pigment_states[yellow_hue].selected = is_on
	_update_button_visual(yellow_hue)
	_mix_and_update_all()

func _on_magenta_alpha_slider_changed(value: float):
	var magenta_hue = Color(1.0, 0.0, 1.0)
	pigment_states[magenta_hue].alpha = value
	_update_button_visual(magenta_hue)
	_mix_and_update_all()

func _on_cyan_alpha_slider_changed(value: float):
	var cyan_hue = Color(0.0, 1.0, 1.0)
	pigment_states[cyan_hue].alpha = value
	_update_button_visual(cyan_hue)
	_mix_and_update_all()

func _on_yellow_alpha_slider_changed(value: float):
	var yellow_hue = Color(1.0, 1.0, 0.0)
	pigment_states[yellow_hue].alpha = value
	_update_button_visual(yellow_hue)
	_mix_and_update_all()

func _on_water_slider_value_changed(value: float):
	# The slider's value is from 0 to 1
	current_water_amount = value
	_mix_and_update_all()
	print("Current water amount : ", value)
	_update_active_brush_properties()
