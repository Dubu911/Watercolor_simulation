# painting_coordinator.gd (GPU-accelerated version)
extends Node

# --- Signals ---
signal canvas_reinitialized

# --- Canvas Properties ---
var CANVAS_WIDTH := 256
var CANVAS_HEIGHT := 256
const MAX_WATER_AMOUNT := 1.0

@onready var physics_simulator = $physics_simulator

# --- Node Path Managements ---
@export var background_path: NodePath
@export var water_layer_sprite_path: NodePath
@export var mobile_layer_sprite_path: NodePath
@export var static_layer_sprite_path: NodePath
@export var pencil_layer_sprite_path: NodePath
@export var preview_layer_sprite_path: NodePath
@export var brush_manager_path: NodePath

# --- Internal Layer Sprite References ---
var background_sprite: Sprite2D
var water_layer_sprite: Sprite2D
var mobile_layer_sprite: Sprite2D
var static_layer_sprite: Sprite2D
var pencil_layer_sprite: Sprite2D
var preview_layer_sprite: Sprite2D

# --- Image Data (CPU-based layers only) ---
var background_image: Image
var pencil_image: Image
var preview_image: Image
var absorbency_map: Image

# --- Textures (CPU-based layers only) ---
var background_texture: ImageTexture
var pencil_texture: ImageTexture
var preview_texture: ImageTexture

# --- Status Flags ---
var _dirty_pencil: bool = false
var _dirty_preview: bool = false
var active_brush_node: Node = null
var _water_layer_visible: bool = false

# --- Simulation Parameters ---
const GRAVITY_STRENGTH = 9.8 # Base gravity constant
var horizontal_theta: float = 0.0 # Angle in degrees
var vertical_theta: float = 0.0   # Angle in degrees

# --- Pre-calculated Gravity Components ---
var gravity_x: float = 0.0
var gravity_y: float = 0.0

func _ready():
	# 1. Get Layer Sprite2D Nodes with more robust checks
	background_sprite = get_node_or_null(background_path) as Sprite2D
	if not background_sprite:
		printerr("painting_coordinator ERROR: background_sprite not found! Check the NodePath in the Inspector.")
		return
	
	water_layer_sprite = get_node_or_null(water_layer_sprite_path) as Sprite2D
	if not water_layer_sprite:
		printerr("painting_coordinator ERROR: Water_layer_sprite not found! Check the NodePath in the Inspector.")
		return
	
	mobile_layer_sprite = get_node_or_null(mobile_layer_sprite_path) as Sprite2D
	if not mobile_layer_sprite:
		printerr("painting_coordinator ERROR: mobile_layer_sprite not found! Check the NodePath in the Inspector.")
		return

	static_layer_sprite = get_node_or_null(static_layer_sprite_path) as Sprite2D
	if not static_layer_sprite:
		printerr("painting_coordinator ERROR: static_layer_sprite not found! Check the NodePath in the Inspector.")
		return
		
	pencil_layer_sprite = get_node_or_null(pencil_layer_sprite_path) as Sprite2D
	if not pencil_layer_sprite:
		printerr("PaintingCoordinator ERROR: PencilLayerSprite not found! Check the NodePath in the Inspector.")
		return

	preview_layer_sprite = get_node_or_null(preview_layer_sprite_path) as Sprite2D
	if not preview_layer_sprite:
		printerr("painting_coordinator ERROR: preview_layer_sprite not found! Check the NodePath in the Inspector.")
		return

	# 2. Initialize Images & Textures
	# Background the "paper", starts white
	background_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	background_image.fill(Color.WHITE)
	background_texture = ImageTexture.create_from_image(background_image)
	background_sprite.texture = background_texture

	# Pencil layer (CPU-based, stays on CPU)
	pencil_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	pencil_image.fill(Color(0, 0, 0, 0))
	pencil_texture = ImageTexture.create_from_image(pencil_image)
	pencil_layer_sprite.texture = pencil_texture

	# Preview layer (CPU-based, for instant visual feedback before GPU batch upload)
	preview_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	preview_image.fill(Color(1, 1, 1, 0))  # Transparent white
	preview_texture = ImageTexture.create_from_image(preview_image)
	preview_layer_sprite.texture = preview_texture

	# Initialize absorbency map (will be uploaded to GPU)
	absorbency_map = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RF)
	_initialize_paper_properties()
	
	# All layers are centered = false to draw from top-left (0,0)
	water_layer_sprite.centered = false
	mobile_layer_sprite.centered = false
	static_layer_sprite.centered = false
	pencil_layer_sprite.centered = false
	preview_layer_sprite.centered = false

	# Initialize GPU physics simulator
	if physics_simulator:
		var success = physics_simulator.init_gpu(CANVAS_WIDTH, CANVAS_HEIGHT, absorbency_map)
		if not success:
			printerr("Failed to initialize GPU physics simulator!")
			return
		print("GPU physics simulator initialized successfully")

		# Set up GPU texture display (no CPU readback!)
		_setup_gpu_texture_display()

	# Set layer z-order (back to front)
	background_sprite.z_index = 0
	static_layer_sprite.z_index = 1
	mobile_layer_sprite.z_index = 2
	pencil_layer_sprite.z_index = 3
	water_layer_sprite.z_index = 99  # Debug layer, hidden by default

	# Ensure correct initial visibility
	background_sprite.visible = true
	static_layer_sprite.visible = true
	mobile_layer_sprite.visible = true
	pencil_layer_sprite.visible = true
	preview_layer_sprite.visible = true
	water_layer_sprite.visible = false

	# Start dirty for initial update
	mark_pencil_dirty()
	_update_gravity_components()
								
# The main simulation loop
func _process(_delta: float):
	# Run GPU physics simulation (no CPU readback!)
	physics_simulator.run_simulation_step_gpu(_delta, gravity_x, gravity_y)

	# GPU textures are automatically displayed via Texture2DRD
	# No CPU readback needed!

	# Only update pencil and preview layers (CPU-based)
	if _dirty_pencil:
		if pencil_texture and pencil_image: pencil_texture.update(pencil_image)
		_dirty_pencil = false

	if _dirty_preview:
		if preview_texture and preview_image: preview_texture.update(preview_image)
		_dirty_preview = false

	# Q key: Show only water layer (debug/preview feature)
	_handle_layer_visibility_controls()


# Batch upload multiple pixels at once (trial3 approach: pixel-by-pixel batching)
func add_paint_batch(pixels: Array):
	"""Upload multiple pixels in a single GPU operation - merges all pixels into one buffer"""
	if pixels.size() == 0:
		return

	if not is_instance_valid(physics_simulator):
		return

	# Create full-canvas buffers to accumulate ALL pixels
	var water_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RF)
	var pigment_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)

	# Fill with zeros (no change)
	water_buffer.fill(Color(0, 0, 0))
	pigment_buffer.fill(Color(1, 1, 1, 0))  # Transparent white

	# Paint all pixels into the buffers (trial3 approach: monotonic values per pixel)
	var avg_pressure = 0.0
	for pixel in pixels:
		var x = pixel["x"]
		var y = pixel["y"]
		var color = pixel["color"]
		var water = pixel["water"]
		var pressure = pixel["pressure"]

		avg_pressure += pressure

		# Check if within canvas bounds
		if x >= 0 and x < CANVAS_WIDTH and y >= 0 and y < CANVAS_HEIGHT:
			# Set water for this pixel (trial3: each pixel painted once with monotonic value)
			water_buffer.set_pixel(x, y, Color(water, 0, 0))

			# Set pigment for this pixel (GPU shader will do Beer-Lambert mixing with canvas)
			pigment_buffer.set_pixel(x, y, color)

	# Upload the merged buffers ONCE (instead of once per pixel!)
	avg_pressure /= pixels.size()

	physics_simulator.upload_paint_region(0, 0, water_buffer, pigment_buffer, avg_pressure)

# GPU-compatible paint removal (optimized - only upload affected region)
func remove_paint_at(pos: Vector2, size: float, removal_strength: float):
	var i_radius = int(ceil(size))

	# Calculate bounding box for this dab
	var min_x = max(0, int(pos.x) - i_radius)
	var max_x = min(CANVAS_WIDTH - 1, int(pos.x) + i_radius)
	var min_y = max(0, int(pos.y) - i_radius)
	var max_y = min(CANVAS_HEIGHT - 1, int(pos.y) + i_radius)

	var region_width = max_x - min_x + 1
	var region_height = max_y - min_y + 1

	# Skip if completely out of bounds
	if region_width <= 0 or region_height <= 0:
		return

	# Create CPU buffer ONLY for the affected region
	var removal_buffer = Image.create(region_width, region_height, false, Image.FORMAT_RF)

	# Fill with zeros (no removal)
	removal_buffer.fill(Color(0, 0, 0))

	# Paint the removal dab onto CPU buffer (in region-local coordinates)
	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= size * size:
				var canvas_x = int(pos.x + x_offset)
				var canvas_y = int(pos.y + y_offset)

				# Check if within canvas bounds
				if canvas_x >= min_x and canvas_x <= max_x and canvas_y >= min_y and canvas_y <= max_y:
					# Convert to region-local coordinates
					var region_x = canvas_x - min_x
					var region_y = canvas_y - min_y

					# Set removal amount (this is pigment mass to remove)
					removal_buffer.set_pixel(region_x, region_y, Color(removal_strength, 0, 0))

	# Upload to GPU
	physics_simulator.upload_removal_region(min_x, min_y, removal_buffer)

# GPU-compatible paint upload (optimized - only upload affected region)
func add_paint_at(pos: Vector2, color: Color, water: float, size: float, pressure: float = 1.0):
	var i_radius = int(ceil(size))

	# Calculate bounding box for this dab
	var min_x = max(0, int(pos.x) - i_radius)
	var max_x = min(CANVAS_WIDTH - 1, int(pos.x) + i_radius)
	var min_y = max(0, int(pos.y) - i_radius)
	var max_y = min(CANVAS_HEIGHT - 1, int(pos.y) + i_radius)

	var region_width = max_x - min_x + 1
	var region_height = max_y - min_y + 1

	# Skip if completely out of bounds
	if region_width <= 0 or region_height <= 0:
		return

	# Create CPU buffers ONLY for the affected region
	var water_buffer = Image.create(region_width, region_height, false, Image.FORMAT_RF)
	var pigment_buffer = Image.create(region_width, region_height, false, Image.FORMAT_RGBAF)

	# Fill with zeros (no change)
	water_buffer.fill(Color(0, 0, 0))
	pigment_buffer.fill(Color(1, 1, 1, 0))  # Transparent white

	# Paint the dab onto CPU buffers (in region-local coordinates)
	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= size * size:
				var canvas_x = int(pos.x + x_offset)
				var canvas_y = int(pos.y + y_offset)

				# Check if within canvas bounds
				if canvas_x >= min_x and canvas_x <= max_x and canvas_y >= min_y and canvas_y <= max_y:
					# Convert to region-local coordinates
					var region_x = canvas_x - min_x
					var region_y = canvas_y - min_y

					# Add water
					water_buffer.set_pixel(region_x, region_y, Color(water, 0, 0))

					# Add pigment
					pigment_buffer.set_pixel(region_x, region_y, color)

	# Upload only the affected region to GPU with pressure
	physics_simulator.upload_paint_region(min_x, min_y, water_buffer, pigment_buffer, pressure)
	

func draw_line_on_pencil_layer(from_pos: Vector2, to_pos: Vector2, color: Color, radius: float):
	if not is_instance_valid(pencil_image): return

	var distance = from_pos.distance_to(to_pos)

	# Determine number of steps to draw circles along the line to avoid gaps
	var step_size = max(1.0, radius * 0.5)
	var steps = int(ceil(distance / step_size))
	if steps == 0: steps = 1

	# Check if this is erasing (transparent color)
	var is_erasing = (color.a == 0.0)

	for i in range(steps + 1):
		var p = from_pos.lerp(to_pos, float(i) / steps)
		_draw_dot(pencil_image, p.floor(), color, radius, is_erasing)

	mark_pencil_dirty()

func _draw_dot(img: Image, center_pos: Vector2, color: Color, radius: float, is_erasing: bool = false):
	var i_radius = int(ceil(radius))
	var center_x = int(center_pos.x)
	var center_y = int(center_pos.y)

	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= radius * radius:
				var draw_x = center_x + x_offset
				var draw_y = center_y + y_offset
				if draw_x >= 0 and draw_x < CANVAS_WIDTH and draw_y >= 0 and draw_y < CANVAS_HEIGHT:
					if is_erasing:
						# Erasing: always overwrite with transparent
						img.set_pixel(draw_x, draw_y, color)
					else:
						# Drawing pencil: keep the darkest value (highest alpha)
						# This prevents light pencil strokes from overwriting dark ones
						var existing_color = img.get_pixel(draw_x, draw_y)

						# Only update if new color is darker (higher alpha = more intense)
						if color.a > existing_color.a:
							img.set_pixel(draw_x, draw_y, color)
						# If existing is darker, keep it (do nothing)


# Input handling.
func _unhandled_input(_event: InputEvent):
	var angle_change_speed = 1.0 # How fast the angle changes when a key is held
	var needs_update = false

	# Check for arrow key presses
	if Input.is_key_pressed(KEY_W):
		vertical_theta -= angle_change_speed
		needs_update = true
	if Input.is_key_pressed(KEY_S):
		vertical_theta += angle_change_speed
		needs_update = true
	if Input.is_key_pressed(KEY_A):
		horizontal_theta -= angle_change_speed
		needs_update = true
	if Input.is_key_pressed(KEY_D):
		horizontal_theta += angle_change_speed
		needs_update = true

	# If any key was pressed, clamp the values and update gravity
	if needs_update:
		# Keep the angles within a -90 to 90 degree range
		vertical_theta = clamp(vertical_theta, -90.0, 90.0)
		horizontal_theta = clamp(horizontal_theta, -90.0, 90.0)
		
		# Recalculate the gravity components with the new angles
		_update_gravity_components()
		
		# Print the new angles to the output log for debugging
		print("Vertical Tilt: ", vertical_theta, " | Horizontal Tilt: ", horizontal_theta)

func _setup_gpu_texture_display():
	# Get RenderingDevice
	var rd = RenderingServer.get_rendering_device()
	if not rd:
		printerr("Failed to get RenderingDevice for texture display!")
		return

	# Create Texture2DRD objects that directly display GPU textures (no CPU readback!)
	# Water layer (for debugging)
	var water_tex_rd = Texture2DRD.new()
	water_tex_rd.texture_rd_rid = physics_simulator.get_water_texture()
	water_layer_sprite.texture = water_tex_rd

	# Apply water debug shader
	var shader = load("res://trial4/water_debug_shader.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	water_layer_sprite.material = shader_material

	# Mobile layer (wet pigment) - Use default straight alpha blending (GPU works in pigment/straight space)
	var mobile_tex_rd = Texture2DRD.new()
	mobile_tex_rd.texture_rd_rid = physics_simulator.get_mobile_texture()
	mobile_layer_sprite.texture = mobile_tex_rd
	mobile_layer_sprite.material = null  # Default blend mode (straight alpha)

	# Static layer (dry pigment) - Use default straight alpha blending (GPU works in pigment/straight space)
	var static_tex_rd = Texture2DRD.new()
	static_tex_rd.texture_rd_rid = physics_simulator.get_static_texture()
	static_layer_sprite.texture = static_tex_rd
	static_layer_sprite.material = null  # Default blend mode (straight alpha)

	# Ensure no tinting on any layer
	for n in [background_sprite, water_layer_sprite, mobile_layer_sprite, static_layer_sprite, pencil_layer_sprite]:
		if n:
			n.self_modulate = Color(1, 1, 1, 1)

	print("GPU texture display set up successfully (passthrough for pigment layers)")

func _update_gravity_components():
	var h_rad = deg_to_rad(horizontal_theta)
	var v_rad = deg_to_rad(vertical_theta)
	gravity_x = GRAVITY_STRENGTH * sin(h_rad)
	gravity_y = GRAVITY_STRENGTH * sin(v_rad)
	
func _initialize_paper_properties():
	# Loop through every pixel to set its absorbency
	for y in range(CANVAS_HEIGHT):
		for x in range(CANVAS_WIDTH):
			#var random_absorbency = randf_range(0.1, 0.2)
			var random_absorbency = 0.15  # Uniform absorbency for testing
			# Set the pixel value. Since the format is FORMAT_RF,
			# the value is stored in the red channel.
			absorbency_map.set_pixel(x, y, Color(random_absorbency, 0, 0))

	# Displacement map is now on GPU, initialized to zero in physics_simulator_gpu.gd

func set_vertical_tilt(degrees: float):
	vertical_theta = degrees
	_update_gravity_components()
	
func set_horizontal_tilt(degrees: float):
	horizontal_theta = degrees
	_update_gravity_components()

func mark_pencil_dirty():
	_dirty_pencil = true

func mark_preview_dirty():
	_dirty_preview = true

func clear_preview_layer():
	if preview_image:
		preview_image.fill(Color(1, 1, 1, 0))  # Transparent white
		mark_preview_dirty()

func draw_preview_pixel(x: int, y: int, color: Color):
	"""Draw a single pixel to preview layer (trial3 approach for smooth strokes)"""
	if not is_instance_valid(preview_image):
		return

	if x < 0 or x >= CANVAS_WIDTH or y < 0 or y >= CANVAS_HEIGHT:
		return

	# Use the actual color alpha (no artificial reduction)
	var preview_color = color

	const K_ABSORPTION = 0.5
	const EPS_A = 0.000001

	var existing = preview_image.get_pixel(x, y)

	# Beer-Lambert optical mixing (same as add_paint.glsl)
	var new_pigment: Color

	if preview_color.a > EPS_A and existing.a > EPS_A:
		# Both have pigment - optical mix
		var new_mass = -log(max(EPS_A, 1.0 - preview_color.a)) / K_ABSORPTION
		var existing_mass = -log(max(EPS_A, 1.0 - existing.a)) / K_ABSORPTION

		var total_mass = new_mass + existing_mass

		# Weight by mass for color mixing
		var new_weight = new_mass / total_mass
		var existing_weight = existing_mass / total_mass

		var mixed_rgb = Color(
			preview_color.r * new_weight + existing.r * existing_weight,
			preview_color.g * new_weight + existing.g * existing_weight,
			preview_color.b * new_weight + existing.b * existing_weight
		)

		# Convert total mass back to alpha
		var total_optical_density = total_mass * K_ABSORPTION
		var new_alpha = 1.0 - exp(-total_optical_density)
		new_alpha = clamp(new_alpha, 0.0, 1.0)

		new_pigment = Color(mixed_rgb.r, mixed_rgb.g, mixed_rgb.b, new_alpha)
	elif preview_color.a > EPS_A:
		# Only new pigment
		new_pigment = preview_color
	else:
		# Only existing pigment (or none)
		new_pigment = existing

	preview_image.set_pixel(x, y, new_pigment)
	mark_preview_dirty()

func draw_preview_dab(center: Vector2, color: Color, radius: float):
	"""Draw a simple circular dab to preview layer using Beer-Lambert optical mixing"""
	if not is_instance_valid(preview_image):
		return

	var i_radius = int(ceil(radius))
	var center_x = int(center.x)
	var center_y = int(center.y)

	# Reduce preview opacity to 30% of original to match lighter watercolor appearance
	var preview_color = Color(color.r, color.g, color.b, color.a * 0.3)

	const K_ABSORPTION = 0.5
	const EPS_A = 0.000001

	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= radius * radius:
				var draw_x = center_x + x_offset
				var draw_y = center_y + y_offset
				if draw_x >= 0 and draw_x < CANVAS_WIDTH and draw_y >= 0 and draw_y < CANVAS_HEIGHT:
					var existing = preview_image.get_pixel(draw_x, draw_y)

					# Beer-Lambert optical mixing (same as add_paint.glsl)
					var new_pigment: Color

					if preview_color.a > EPS_A and existing.a > EPS_A:
						# Both have pigment - optical mix
						var new_mass = -log(max(EPS_A, 1.0 - preview_color.a)) / K_ABSORPTION
						var existing_mass = -log(max(EPS_A, 1.0 - existing.a)) / K_ABSORPTION

						var total_mass = new_mass + existing_mass

						# Weight by mass for color mixing
						var new_weight = new_mass / total_mass
						var existing_weight = existing_mass / total_mass

						var mixed_rgb = Color(
							preview_color.r * new_weight + existing.r * existing_weight,
							preview_color.g * new_weight + existing.g * existing_weight,
							preview_color.b * new_weight + existing.b * existing_weight
						)

						# Convert total mass back to alpha
						var total_optical_density = total_mass * K_ABSORPTION
						var new_alpha = 1.0 - exp(-total_optical_density)
						new_alpha = clamp(new_alpha, 0.0, 1.0)

						new_pigment = Color(mixed_rgb.r, mixed_rgb.g, mixed_rgb.b, new_alpha)
					elif preview_color.a > EPS_A:
						# Only new pigment
						new_pigment = preview_color
					else:
						# Only existing pigment (or none)
						new_pigment = existing

					preview_image.set_pixel(draw_x, draw_y, new_pigment)

	mark_preview_dirty()

func set_active_brush(brush_node: Node):
	self.active_brush_node = brush_node

# Handle layer visibility controls (Tab key to toggle water layer preview)
func _handle_layer_visibility_controls():
	# Tab key: Press once to toggle water layer on, press again to toggle off
	if Input.is_action_just_pressed("toggle_water_layer"):
		_water_layer_visible = !_water_layer_visible

		if _water_layer_visible:
			# Hide mobile and static layers to show only water
			if is_instance_valid(mobile_layer_sprite):
				mobile_layer_sprite.visible = false
			if is_instance_valid(static_layer_sprite):
				static_layer_sprite.visible = false
			# Show water layer
			if is_instance_valid(water_layer_sprite):
				water_layer_sprite.visible = true
		else:
			# Restore normal visibility: show mobile and static, hide water
			if is_instance_valid(mobile_layer_sprite):
				mobile_layer_sprite.visible = true
			if is_instance_valid(static_layer_sprite):
				static_layer_sprite.visible = true
			# Hide water layer (normal painting view)
			if is_instance_valid(water_layer_sprite):
				water_layer_sprite.visible = false

# --- File Manager Helper Methods ---

# Get composite image for PNG export (CPU compositing)
func get_composite_image() -> Image:
	print("painting_coordinator: Creating composite image (CPU)...")

	if not is_instance_valid(physics_simulator):
		printerr("painting_coordinator: physics_simulator not valid!")
		return null

	# 1) Pull current GPU state down to CPU
	var water_img: Image = physics_simulator.download_water_layer()   # FORMAT_RF (not used for final, but available)
	var mobile_img: Image = physics_simulator.download_mobile_layer()  # FORMAT_RGBAF
	var static_img: Image = physics_simulator.download_static_layer()  # FORMAT_RGBAF

	if not mobile_img or not static_img:
		printerr("painting_coordinator: Failed to download GPU layers!")
		return null

	# 2) Create final target (RGBA8) and start with white paper
	var width := CANVAS_WIDTH
	var height := CANVAS_HEIGHT
	var composite := Image.create(width, height, false, Image.FORMAT_RGBA8)
	composite.fill(Color.WHITE)

	# 3) Blit the background "paper" if you keep a custom background image
	if background_image != null:
		composite.blit_rect(
			background_image,
			Rect2i(0, 0, background_image.get_width(), background_image.get_height()),
			Vector2i(0, 0)
		)

	# 4) Composite dry pigment (static), wet pigment (mobile), then pencil
	#    Static/mobile images are RGBAF "pigment" images where A is pigment mass.
	#    We'll alpha-blend them over paper.
	_composite_layer(composite, static_img)
	_composite_layer(composite, mobile_img)

	if pencil_image != null:
		_composite_layer(composite, pencil_image)

	print("painting_coordinator: Composite image created (CPU)")
	return composite

# Helper: blend 'layer' over 'base' using standard src-over
func _composite_layer(base: Image, layer: Image) -> void:
	var w = min(base.get_width(), layer.get_width())
	var h = min(base.get_height(), layer.get_height())
	for y in range(h):
		for x in range(w):
			var dst := base.get_pixel(x, y)
			var src := layer.get_pixel(x, y)  # works for RGBA8 and RGBAF

			var a := src.a
			if a <= 0.0:
				continue

			var out_col := Color(
				src.r * a + dst.r * (1.0 - a),
				src.g * a + dst.g * (1.0 - a),
				src.b * a + dst.b * (1.0 - a),
				1.0
			)
			base.set_pixel(x, y, out_col)

# Reinitialize canvas with new dimensions (for New Canvas)
func reinitialize_canvas(width: int, height: int):
	print("painting_coordinator: Reinitializing canvas to ", width, "×", height)

	# Update canvas dimensions first
	CANVAS_WIDTH = width
	CANVAS_HEIGHT = height

	# Clear and reinitialize background
	background_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	background_image.fill(Color.WHITE)
	background_texture = ImageTexture.create_from_image(background_image)
	if is_instance_valid(background_sprite):
		background_sprite.texture = background_texture

	# Clear and reinitialize pencil layer
	pencil_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	pencil_image.fill(Color(0, 0, 0, 0))
	pencil_texture = ImageTexture.create_from_image(pencil_image)
	if is_instance_valid(pencil_layer_sprite):
		pencil_layer_sprite.texture = pencil_texture

	# Reinitialize absorbency map
	absorbency_map = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RF)
	for y in range(CANVAS_HEIGHT):
		for x in range(CANVAS_WIDTH):
			var random_absorbency = 0.15
			absorbency_map.set_pixel(x, y, Color(random_absorbency, 0, 0))

	# Reinitialize GPU physics simulator with new dimensions
	if is_instance_valid(physics_simulator):
		var success = physics_simulator.init_gpu(CANVAS_WIDTH, CANVAS_HEIGHT, absorbency_map)
		if not success:
			printerr("painting_coordinator: Failed to reinitialize GPU physics simulator!")
			return

		# Set up GPU texture display
		_setup_gpu_texture_display()
		print("painting_coordinator: Canvas reinitialized successfully")

		# Emit signal to let other systems know canvas was reinitialized
		emit_signal("canvas_reinitialized")
