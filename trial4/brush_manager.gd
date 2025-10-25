# brush_manager.gd
extends Node

# --- Path Managements ---
@export var painting_coordinator_path: NodePath
@export var watercolor_brush_path: NodePath
@export var removing_brush_path: NodePath
@export var pencil_brush_path: NodePath
@export var eraser_brush_path: NodePath
@export var layer_for_mouse_pos_path: NodePath
@export var current_color_display_path: NodePath
@export var color_picker_path: NodePath
@export var brush_size_popup_path: NodePath
@export var brush_size_value_label_path: NodePath
@export var removing_brush_size_popup_path: NodePath
@export var removing_brush_size_value_label_path: NodePath
@export var pencil_size_popup_path: NodePath
@export var pencil_size_value_label_path: NodePath
@export var eraser_size_popup_path: NodePath
@export var eraser_size_value_label_path: NodePath

# --- Internal References to PathNode ---
var painting_coordinator: Node
var watercolor_brush: Node
var removing_brush: Node
var pencil_brush: Node
var eraser_brush: Node
var layer_for_mouse_pos: Sprite2D
var current_color_display: ColorRect
var color_picker: ColorPicker
var brush_size_popup: PanelContainer
var brush_size_value_label: Label
var removing_brush_size_popup: PanelContainer
var removing_brush_size_value_label: Label
var pencil_size_popup: PanelContainer
var pencil_size_value_label: Label
var eraser_size_popup: PanelContainer
var eraser_size_value_label: Label
var brush_cursor_outer: Sprite2D
var brush_cursor_inner: Sprite2D
var pencil_cursor: Sprite2D
var eraser_cursor: Sprite2D

# --- Current Brush State ---
var current_hue: Color = Color.RED  # Base hue (RGB only, alpha ignored)
var current_pigment_alpha: float = 0.5  # Pigment concentration (0.0 - 1.0)
var current_pigment_color: Color = Color(1.0, 0.0, 0.0, 0.5)  # Final color with alpha
var current_water_amount: float = 0.1  # Water amount

# --- Tablet/Mouse Position Tracking ---
var _last_screen_pos: Vector2 = Vector2.ZERO
var _last_world_pos: Vector2 = Vector2.ZERO

# --- Input Cooldown (prevents ghost clicks after canvas reinit) ---
var _eat_clicks_until_frame := -1

# Helper: Set how many frames to eat clicks for
func _set_eat_clicks_frames(n: int) -> void:
	_eat_clicks_until_frame = Engine.get_frames_drawn() + max(1, n)


func _ready():
	# Get the actual nodes from the NodePaths. Add robust checks.
	painting_coordinator = get_node_or_null(painting_coordinator_path)
	if not painting_coordinator:
		printerr("brush_manager ERROR: painting_coordinator not found! Check the NodePath.")
		return

	watercolor_brush = get_node_or_null(watercolor_brush_path)
	if not watercolor_brush:
		printerr("brush_manager ERROR: watercolor_brush not found! Check the NodePath.")

	removing_brush = get_node_or_null(removing_brush_path)
	if not removing_brush:
		printerr("brush_manager ERROR: removing_brush not found! Check the NodePath.")

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

	removing_brush_size_popup = get_node_or_null(removing_brush_size_popup_path) as PanelContainer
	if not removing_brush_size_popup:
		printerr("BrushManager ERROR: RemovingBrushSizePopup not found!")

	removing_brush_size_value_label = get_node_or_null(removing_brush_size_value_label_path) as Label
	if not removing_brush_size_value_label:
		printerr("BrushManager ERROR: RemovingBrushSizeValueLabel not found!")

	pencil_size_popup = get_node_or_null(pencil_size_popup_path) as PanelContainer
	if not pencil_size_popup:
		printerr("BrushManager ERROR: PencilSizePopup not found!")

	pencil_size_value_label = get_node_or_null(pencil_size_value_label_path) as Label
	if not pencil_size_value_label:
		printerr("BrushManager ERROR: PencilSizeValueLabel not found!")

	eraser_size_popup = get_node_or_null(eraser_size_popup_path) as PanelContainer
	if not eraser_size_popup:
		printerr("BrushManager ERROR: EraserSizePopup not found!")

	eraser_size_value_label = get_node_or_null(eraser_size_value_label_path) as Label
	if not eraser_size_value_label:
		printerr("BrushManager ERROR: EraserSizeValueLabel not found!")

	# Get brush cursor sprites
	brush_cursor_outer = get_node_or_null("../layers_container/brush_cursor_outer") as Sprite2D
	brush_cursor_inner = get_node_or_null("../layers_container/brush_cursor_inner") as Sprite2D
	pencil_cursor = get_node_or_null("../layers_container/pencil_cursor") as Sprite2D
	eraser_cursor = get_node_or_null("../layers_container/eraser_cursor") as Sprite2D

	# Initialize brush cursor textures
	if brush_cursor_outer and brush_cursor_inner:
		_initialize_brush_cursor()

	# Initialize pencil cursor
	if pencil_cursor:
		_initialize_pencil_cursor()

	# Initialize eraser cursor
	if eraser_cursor:
		_initialize_eraser_cursor()

	# Note: Signals are connected in the scene file (main3.tscn)

	# Listen for canvas reinitialization to prevent ghost clicks
	if painting_coordinator and painting_coordinator.has_signal("canvas_reinitialized"):
		painting_coordinator.canvas_reinitialized.connect(func():
			_eat_clicks_until_frame = Engine.get_frames_drawn() + 2)

	# Set the initial brush and update its properties
	if watercolor_brush:
		_set_active_brush(watercolor_brush)

	# Initialize the UI on start
	_update_color_display()

	# Enable process for frame-by-frame cursor updates (works better with tablets)
	set_process(true)

# Update cursor position every frame using latest tracked position
func _process(_delta: float) -> void:
	# Always place cursor at the latest world position
	_update_brush_cursor_positions(_last_world_pos)

	# Bounds test in image (layer) space using the same last world pos
	if is_instance_valid(layer_for_mouse_pos) and is_instance_valid(painting_coordinator):
		var img_pos = layer_for_mouse_pos.to_local(_last_world_pos)
		var w = painting_coordinator.CANVAS_WIDTH
		var h = painting_coordinator.CANVAS_HEIGHT
		var over = img_pos.x >= 0 and img_pos.x < w and img_pos.y >= 0 and img_pos.y < h
		_update_brush_cursor_visibility(img_pos, over)

# IMPORTANT: use _input (not _unhandled_input) so pen hover/motion reaches us even if UI handles it
func _input(event: InputEvent) -> void:
	# 0) Eat clicks for a few frames after canvas reinit (prevents ghost strokes)
	if event is InputEventMouseButton and event.pressed:
		if Engine.get_frames_drawn() <= _eat_clicks_until_frame:
			get_viewport().set_input_as_handled()
			return

	# 1) ALWAYS update pointer positions from motion events (even when over UI)
	if event is InputEventMouseMotion:
		_last_screen_pos = event.position

		var cam = get_viewport().get_camera_2d()
		if cam:
			# Convert screen position to world position through camera
			var canvas_transform = cam.get_canvas_transform()
			_last_world_pos = canvas_transform.affine_inverse() * event.position
		else:
			# Fallback if no Camera2D
			_last_world_pos = get_viewport().get_canvas_transform().affine_inverse() * event.position

	# ALSO update position from button events to handle clicks when settings window has focus
	elif event is InputEventMouseButton:
		_last_screen_pos = event.position

		var cam = get_viewport().get_camera_2d()
		if cam:
			# Convert screen position to world position through camera
			var canvas_transform = cam.get_canvas_transform()
			_last_world_pos = canvas_transform.affine_inverse() * event.position
		else:
			# Fallback if no Camera2D
			_last_world_pos = get_viewport().get_canvas_transform().affine_inverse() * event.position

	# 2) Check if mouse is over UI - if so, don't forward to brush but still update cursor
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if _is_mouse_over_ui(event.position):
			# Cancel any active stroke to prevent ghost lines
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				var active = painting_coordinator.get("active_brush_node") if is_instance_valid(painting_coordinator) else null
				if is_instance_valid(active) and active.has_method("cancel_stroke"):
					active.cancel_stroke()
			# DON'T call set_input_as_handled() - let UI elements process the event normally
			# Note: We still update _last_world_pos above, so cursor will follow mouse
			return  # Just block input from reaching canvas/brush

	# 3) Forward input to active brush with correct image-space position (for draws & pressure)
	var active = painting_coordinator.get("active_brush_node") if is_instance_valid(painting_coordinator) else null
	if is_instance_valid(active) and is_instance_valid(layer_for_mouse_pos):
		var img_pos = layer_for_mouse_pos.to_local(_last_world_pos)
		if active.has_method("handle_input"):
			active.handle_input(event, img_pos)

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

func _on_removing_brush_button_pressed():
	if removing_brush:
		print("brush_manager: Removing Brush selected")
		_set_active_brush(removing_brush)

		# Toggle removing brush size popup
		if is_instance_valid(removing_brush_size_popup):
			removing_brush_size_popup.visible = not removing_brush_size_popup.visible

func _on_pencil_button_pressed():
	if pencil_brush:
		print("brush_manager: Pencil Brush selected")
		_set_active_brush(pencil_brush)

		# Toggle pencil size popup
		if is_instance_valid(pencil_size_popup):
			pencil_size_popup.visible = not pencil_size_popup.visible

func _on_eraser_button_pressed():
	if eraser_brush:
		print("brush_manager: Eraser Brush selected")
		_set_active_brush(eraser_brush)

		# Toggle eraser size popup
		if is_instance_valid(eraser_size_popup):
			eraser_size_popup.visible = not eraser_size_popup.visible

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

		# Update brush cursor size
		_update_brush_cursor_size()

		print("Brush size: ", value)

# Called when removing brush size slider changes
func _on_removing_brush_size_slider_changed(value: float):
	if is_instance_valid(removing_brush):
		removing_brush.base_brush_size = value

		# Update the label to show current size
		if is_instance_valid(removing_brush_size_value_label):
			removing_brush_size_value_label.text = "%.1f" % value

		# Update brush cursor size (removing brush uses same dual-ring cursor as watercolor)
		_update_brush_cursor_size()

		print("Removing brush size: ", value)

# Called when pencil size slider changes
func _on_pencil_size_slider_changed(value: float):
	if is_instance_valid(pencil_brush):
		# Value is normalized 0.0-1.0
		pencil_brush.set_pencil_size(value)

		# Update the label to show actual pixel size
		if is_instance_valid(pencil_size_value_label):
			pencil_size_value_label.text = "%.2f" % pencil_brush.base_pencil_size

		# Update pencil cursor size
		_update_pencil_cursor_size()

		print("Pencil size: ", pencil_brush.base_pencil_size)

# Called when eraser size slider changes
func _on_eraser_size_slider_changed(value: float):
	if is_instance_valid(eraser_brush):
		# Value is normalized 0.0-1.0
		eraser_brush.set_eraser_size(value)

		# Update the label to show actual pixel size
		if is_instance_valid(eraser_size_value_label):
			eraser_size_value_label.text = "%.2f" % eraser_brush.base_eraser_size

		# Update eraser cursor size
		_update_eraser_cursor_size()

		print("Eraser size: ", eraser_brush.base_eraser_size)

# Initialize brush cursor circle textures
func _initialize_brush_cursor():
	# Create circle textures (32x32 is enough for most brush sizes)
	var circle_outer = _create_circle_texture(32, 15.5, Color(0, 0, 0, 1))
	var circle_inner = _create_circle_texture(32, 15.5, Color(0, 0, 0, 1))

	brush_cursor_outer.texture = circle_outer
	brush_cursor_inner.texture = circle_inner

	# Update initial size
	_update_brush_cursor_size()

# Create a circle texture procedurally
func _create_circle_texture(size: int, radius: float, color: Color) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)

	# Draw circle outline (1 pixel thick)
	for y in range(size):
		for x in range(size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)

			# Draw circle outline
			if abs(dist - radius) < 0.7:  # 1 pixel thick outline
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))  # Transparent

	return ImageTexture.create_from_image(img)

# Update brush cursor size based on current brush settings
func _update_brush_cursor_size():
	if not is_instance_valid(brush_cursor_outer) or not is_instance_valid(brush_cursor_inner):
		return

	# Determine which brush to use for cursor size (watercolor or removing)
	var active_brush = painting_coordinator.get("active_brush_node") if is_instance_valid(painting_coordinator) else null
	var brush_to_use = null

	if active_brush == watercolor_brush and is_instance_valid(watercolor_brush):
		brush_to_use = watercolor_brush
	elif active_brush == removing_brush and is_instance_valid(removing_brush):
		brush_to_use = removing_brush
	elif is_instance_valid(watercolor_brush):
		# Default to watercolor if no active brush
		brush_to_use = watercolor_brush

	if not brush_to_use:
		return

	var base_size = brush_to_use.base_brush_size
	var min_mult = brush_to_use.min_pressure_size_mult
	var max_mult = brush_to_use.max_pressure_size_mult

	# Outer circle shows maximum size (full pressure)
	var max_radius = base_size * max_mult
	brush_cursor_outer.scale = Vector2(max_radius / 15.5, max_radius / 15.5)

	# Inner circle shows minimum size (light pressure)
	var min_radius = base_size * min_mult
	brush_cursor_inner.scale = Vector2(min_radius / 15.5, min_radius / 15.5)

# Update brush cursor positions using global coordinates
func _update_brush_cursor_positions(global_mouse_pos: Vector2) -> void:
	if is_instance_valid(brush_cursor_outer):
		brush_cursor_outer.global_position = global_mouse_pos
	if is_instance_valid(brush_cursor_inner):
		brush_cursor_inner.global_position = global_mouse_pos
	if is_instance_valid(pencil_cursor):
		pencil_cursor.global_position = global_mouse_pos
	if is_instance_valid(eraser_cursor):
		eraser_cursor.global_position = global_mouse_pos

# Update brush cursor visibility based on active brush and canvas bounds
func _update_brush_cursor_visibility(mouse_pos_img_space: Vector2, is_over_canvas: bool) -> void:
	if not is_instance_valid(painting_coordinator):
		return

	# Get active brush
	var active_brush = painting_coordinator.get("active_brush_node")

	# Show watercolor brush cursor when watercolor or removing brush is active and mouse is over canvas
	var should_show_brush = is_over_canvas and (active_brush == watercolor_brush or active_brush == removing_brush)
	if is_instance_valid(brush_cursor_outer):
		brush_cursor_outer.visible = should_show_brush
	if is_instance_valid(brush_cursor_inner):
		brush_cursor_inner.visible = should_show_brush

	# Show pencil cursor when pencil is active and mouse is over canvas
	var should_show_pencil = is_over_canvas and active_brush == pencil_brush
	if is_instance_valid(pencil_cursor):
		pencil_cursor.visible = should_show_pencil

	# Show eraser cursor when eraser is active and mouse is over canvas
	var should_show_eraser = is_over_canvas and active_brush == eraser_brush
	if is_instance_valid(eraser_cursor):
		eraser_cursor.visible = should_show_eraser

# Initialize pencil cursor circle texture
func _initialize_pencil_cursor():
	# Create single circle texture for pencil (smaller texture size)
	var circle = _create_circle_texture(32, 15.5, Color(0, 0, 0, 1))
	pencil_cursor.texture = circle

	# Update initial size
	_update_pencil_cursor_size()

# Update pencil cursor size based on current pencil settings
func _update_pencil_cursor_size():
	if not is_instance_valid(pencil_brush) or not is_instance_valid(pencil_cursor):
		return

	var pencil_size = pencil_brush.base_pencil_size

	# Scale the cursor to match pencil size (15.5 is the base radius in the texture)
	pencil_cursor.scale = Vector2(pencil_size / 15.5, pencil_size / 15.5)

# Initialize eraser cursor circle texture
func _initialize_eraser_cursor():
	# Create single circle texture for eraser
	var circle = _create_circle_texture(32, 15.5, Color(1, 1, 1, 1))
	eraser_cursor.texture = circle

	# Update initial size
	_update_eraser_cursor_size()

# Update eraser cursor size based on current eraser settings
func _update_eraser_cursor_size():
	if not is_instance_valid(eraser_brush) or not is_instance_valid(eraser_cursor):
		return

	var eraser_size = eraser_brush.base_eraser_size

	# Scale the cursor to match eraser size (15.5 is the base radius in the texture)
	eraser_cursor.scale = Vector2(eraser_size / 15.5, eraser_size / 15.5)

# Check if mouse position is over any UI element
func _is_mouse_over_ui(screen_pos: Vector2) -> bool:
	# Check File menu button
	var file_menu_button = get_node_or_null("../CanvasLayer/FileMenuButton")
	if is_instance_valid(file_menu_button) and file_menu_button.visible:
		if file_menu_button.get_global_rect().has_point(screen_pos):
			return true
		# Also check the popup menu when it's open
		var popup = file_menu_button.get_popup()
		if is_instance_valid(popup) and popup.visible:
			# PopupMenu uses global position and size
			var popup_rect: Rect2 = Rect2(popup.position, popup.size)
			if popup_rect.has_point(screen_pos):
				return true

	# Check settings button
	var settings_button = get_node_or_null("../CanvasLayer/SettingsButton")
	if is_instance_valid(settings_button) and settings_button.visible:
		if settings_button.get_global_rect().has_point(screen_pos):
			return true

	# Check physics settings window (correct path)
	var settings_window = get_node_or_null("../PhysicsSettingsWindow")
	if is_instance_valid(settings_window) and settings_window.visible:
		if settings_window.get_global_rect().has_point(screen_pos):
			return true

	# Check all file dialogs (they're exclusive, but include for completeness)
	var load_d = get_node_or_null("../LoadFileDialog")
	var save_d = get_node_or_null("../SaveFileDialog")
	var export_d = get_node_or_null("../ExportFileDialog")
	for d in [load_d, save_d, export_d]:
		if is_instance_valid(d) and d.visible:
			if d.get_global_rect().has_point(screen_pos):
				return true

	# Check new canvas dialog
	var new_canvas_d = get_node_or_null("../NewCanvasDialog")
	if is_instance_valid(new_canvas_d) and new_canvas_d.visible:
		if new_canvas_d.get_global_rect().has_point(screen_pos):
			return true

	# Check color picker
	if is_instance_valid(color_picker) and color_picker.visible:
		if color_picker.get_global_rect().has_point(screen_pos):
			return true

	# Check pigment alpha slider and its container
	var pigment_control = get_node_or_null("../CanvasLayer/pigment_control")
	if is_instance_valid(pigment_control) and pigment_control.visible:
		if pigment_control.get_global_rect().has_point(screen_pos):
			return true

	# Check water slider and its container
	var water_control = get_node_or_null("../CanvasLayer/water_control")
	if is_instance_valid(water_control) and water_control.visible:
		if water_control.get_global_rect().has_point(screen_pos):
			return true

	# Check color swatch
	var color_swatch = get_node_or_null("../CanvasLayer/color_swatch")
	if is_instance_valid(color_swatch) and color_swatch.visible:
		if color_swatch.get_global_rect().has_point(screen_pos):
			return true

	# Check brush buttons container
	var vbox_container = get_node_or_null("../CanvasLayer/VBoxContainer")
	if is_instance_valid(vbox_container) and vbox_container.visible:
		if vbox_container.get_global_rect().has_point(screen_pos):
			return true

	# Check brush size popup
	if is_instance_valid(brush_size_popup) and brush_size_popup.visible:
		if brush_size_popup.get_global_rect().has_point(screen_pos):
			return true

	# Check pencil size popup
	if is_instance_valid(pencil_size_popup) and pencil_size_popup.visible:
		if pencil_size_popup.get_global_rect().has_point(screen_pos):
			return true

	# Check eraser size popup
	if is_instance_valid(eraser_size_popup) and eraser_size_popup.visible:
		if eraser_size_popup.get_global_rect().has_point(screen_pos):
			return true

	return false
