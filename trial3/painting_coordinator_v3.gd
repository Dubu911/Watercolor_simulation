# painting_coordinator.gd (Corrected and with new add_paint_at function)
extends Node

# --- Canvas Properties ---
const CANVAS_WIDTH := 64
const CANVAS_HEIGHT := 64
const MAX_WATER_AMOUNT := 1.0

@onready var physics_simulator = $physics_simulator

# --- Node Path Managements ---
@export var background_path: NodePath
@export var water_layer_sprite_path: NodePath
@export var mobile_layer_sprite_path: NodePath
@export var static_layer_sprite_path: NodePath
@export var pencil_layer_sprite_path: NodePath
@export var brush_manager_path: NodePath

# --- Internal Layer Sprite References ---
var background_sprite: Sprite2D
var water_layer_sprite: Sprite2D
var mobile_layer_sprite: Sprite2D
var static_layer_sprite: Sprite2D
var pencil_layer_sprite: Sprite2D

# --- Image Data (The actual data for the simulation) ---
var background_image: Image
var water_read_buffer: Image
var water_write_buffer: Image
var mobile_read_buffer: Image
var mobile_write_buffer : Image
var static_read_buffer: Image
var static_write_buffer: Image
var pencil_image: Image
var absorbency_map : Image
var displacement_map : Image
var inertia_read_buffer: Image
var inertia_write_buffer: Image

# --- Textures (The GPU version of the data for display) ---
var background_texture: ImageTexture
var water_texture: ImageTexture
var mobile_texture: ImageTexture
var static_texture: ImageTexture
var pencil_texture: ImageTexture

# --- Status Flags ---
var _dirty_watercolor: bool = false
var _dirty_pencil: bool = false
var active_brush_node: Node = null

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

	# 2. Initialize Images & Textures
	# background the "paper", starts white
	background_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	background_image.fill(Color.WHITE)
	background_texture = ImageTexture.create_from_image(background_image)
	background_sprite.texture = background_texture

	# Water layer uses a floating-point format for precision
	water_read_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RF)
	water_texture = ImageTexture.create_from_image(water_read_buffer)
	water_layer_sprite.texture = water_texture
	
	water_write_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RF)
	
	# Mobile layer is for wet pigment, starts transparent
	mobile_read_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	mobile_read_buffer.fill(Color(1, 1, 1, 0))  # Fill with transparent white
	mobile_texture = ImageTexture.create_from_image(mobile_read_buffer)
	mobile_layer_sprite.texture = mobile_texture
	
	mobile_write_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	
	# Static layer is the "paper", starts transparent
	static_read_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	static_read_buffer.fill(Color(1, 1, 1, 0))
	static_texture = ImageTexture.create_from_image(static_read_buffer)
	static_layer_sprite.texture = static_texture
	
	static_write_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	
	# The pencil layer starts transparent
	pencil_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	pencil_image.fill(Color(0, 0, 0, 0))
	pencil_texture = ImageTexture.create_from_image(pencil_image)
	pencil_layer_sprite.texture = pencil_texture
	
	# Physics layers
	absorbency_map = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RF)
	displacement_map = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)

	# Inertia memory buffers (store water inflows from 4 directions: right, left, down, up)
	inertia_read_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)
	inertia_read_buffer.fill(Color(0, 0, 0, 0))
	inertia_write_buffer = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBAF)

	# Initialize the paper properties
	_initialize_paper_properties()
	
	# All layers are centered = false to draw from top-left (0,0)
	water_layer_sprite.centered = false
	mobile_layer_sprite.centered = false
	static_layer_sprite.centered = false
	pencil_layer_sprite.centered = false

	# --- DEBUG PURPOSE APPLYING CUSTOM SHADER FOR WATER LAYER ---
	var shader = load("res://trial3/water_debug_shader_v3.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	water_layer_sprite.material = shader_material
	
	# Start dirty for initial update
	mark_watercolor_dirty()
	mark_pencil_dirty()
	_update_gravity_components()
	
	# Getting local variables ready in physics_simulator.gd
	if physics_simulator:
		physics_simulator.init(	CANVAS_WIDTH,
								CANVAS_HEIGHT,
								water_read_buffer,
								mobile_read_buffer,
								water_write_buffer,
								mobile_write_buffer,
								static_read_buffer,
								static_write_buffer,
								absorbency_map,
								displacement_map,
								inertia_read_buffer,
								inertia_write_buffer)
								
# The main simulation loop
func _process(_delta: float):
	# --- Physics Simulations will go here in the future ---
	physics_simulator.run_simulation_step(_delta, gravity_x, gravity_y)
	water_read_buffer = physics_simulator.water_read
	mobile_read_buffer = physics_simulator.mobile_read
	mark_watercolor_dirty()
	# --- Texture Updates ---
	if _dirty_watercolor:
		#--- for water fluid check. needs to be disabled for faster performance ---
		if water_texture and water_read_buffer: water_texture.update(water_read_buffer)
		
		if mobile_texture and mobile_read_buffer: mobile_texture.update(mobile_read_buffer)
		if static_texture and static_read_buffer: static_texture.update(static_read_buffer)
		_dirty_watercolor = false
	
	if _dirty_pencil:
		if pencil_texture and pencil_image: pencil_texture.update(pencil_image)
		_dirty_pencil = false


# Paint a single pixel with watercolor (optical mixing + water limiting)
# Called by watercolor_brush for each pixel in a stroke
# Pigment transfer is now proportional to water transfer
# Pressure allows concentrated pigment to diffuse into wet surfaces (wet-on-wet technique)
func paint_watercolor_pixel(x: int, y: int, color: Color, water: float, pressure: float = 1.0):
	# Bounds check
	if x < 0 or x >= CANVAS_WIDTH or y < 0 or y >= CANVAS_HEIGHT:
		return

	# Get current canvas state
	var canvas_color = mobile_read_buffer.get_pixel(x, y)
	var canvas_water = water_read_buffer.get_pixel(x, y).r

	# Calculate actual water transfer
	# Only add water up to the brush's water amount (prevents over-saturation)
	var water_to_add = max(0.0, water - canvas_water)
	var new_water = canvas_water + water_to_add
	water_read_buffer.set_pixel(x, y, Color(new_water, 0, 0))

	# Calculate pigment transfer ratio based on actual water transfer
	# If water_to_add is 0 (surface already wet), no pigment transfer via water
	# If water_to_add equals water (dry surface), full pigment transfer
	var pigment_transfer_ratio = water_to_add / water if water > 0.0 else 0.0

	# Scale the incoming pigment by the water transfer ratio
	var transferred_pigment = Color(color.r, color.g, color.b, color.a * pigment_transfer_ratio)

	# --- WET-ON-WET TECHNIQUE: Pressure-based pigment diffusion ---
	# When surface is wet and brush has concentrated pigment, allow diffusion based on:
	# 1. Concentration difference (brush pigment vs canvas pigment)
	# 2. Applied pressure (harder press = more pigment forced into wet surface)
	# 3. Surface wetness (only works on wet surfaces)

	var surface_is_wet = canvas_water > 0.01  # Surface needs some water for diffusion

	if surface_is_wet and pressure > 0.0:
		# Calculate pigment mass difference (alpha represents concentration/mass)
		var brush_concentration = color.a
		var canvas_concentration = canvas_color.a
		var concentration_diff = max(0.0, brush_concentration - canvas_concentration)

		# Pressure-driven diffusion: proportional to pressure and concentration difference
		# This allows adding strong color to wet surfaces by pressing hard
		var diffusion_strength = pressure * concentration_diff * 0.5  # 0.5 is tuning factor

		# Create diffusion pigment (same color as brush, scaled by diffusion strength)
		var diffusion_pigment = Color(color.r, color.g, color.b, color.a * diffusion_strength)

		# Add diffusion pigment to transferred pigment
		transferred_pigment.a += diffusion_pigment.a
		# Mix colors proportionally (weight by their alpha values)
		if transferred_pigment.a > 0.0:
			var total_mass = transferred_pigment.a
			var water_weight = (color.a * pigment_transfer_ratio) / total_mass if total_mass > 0 else 0
			var diffusion_weight = (diffusion_pigment.a) / total_mass if total_mass > 0 else 0
			transferred_pigment.r = color.r * water_weight + diffusion_pigment.r * diffusion_weight
			transferred_pigment.g = color.g * water_weight + diffusion_pigment.g * diffusion_weight
			transferred_pigment.b = color.b * water_weight + diffusion_pigment.b * diffusion_weight

	# Mix the transferred pigment (water + diffusion) with existing pigment
	var mixed_color = PigmentMixer._mix_pigments_optical(transferred_pigment, canvas_color)
	mobile_read_buffer.set_pixel(x, y, mixed_color)

	mark_watercolor_dirty()

# LEGACY: Old multi-dab function (can be removed after testing new brush)
func add_paint_at(pos: Vector2, color: Color, water: float, size: float):
	var i_radius = int(size)
	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= size * size:
				var draw_x = int(pos.x + x_offset)
				var draw_y = int(pos.y + y_offset)

				if draw_x >= 0 and draw_x < CANVAS_WIDTH and draw_y >= 0 and draw_y < CANVAS_HEIGHT:
					# --- Add water ---
					var current_water = water_read_buffer.get_pixel(draw_x, draw_y).r
					var new_water = min(MAX_WATER_AMOUNT, current_water + water)
					water_read_buffer.set_pixel(draw_x, draw_y, Color(new_water, 0, 0))
					
					# --- Mix Pigment ---
					var new_pigment_wash = color # The color from the brush
					var existing_pigment_wash = mobile_read_buffer.get_pixel(draw_x, draw_y)
					
					# Use the new helper function to correctly mix the two washes
					var final_mixed_color = PigmentMixer._mix_pigments_optical(new_pigment_wash, existing_pigment_wash)
					
					mobile_read_buffer.set_pixel(draw_x, draw_y, final_mixed_color)

	mark_watercolor_dirty()
	

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

	# It's also a good idea to initialize the displacement map to zero here
	displacement_map.fill(Color(0,0,0,0))

func set_vertical_tilt(degrees: float):
	vertical_theta = degrees
	_update_gravity_components()
	
func set_horizontal_tilt(degrees: float):
	horizontal_theta = degrees
	_update_gravity_components()

func mark_watercolor_dirty():
	_dirty_watercolor = true

func mark_pencil_dirty():
	_dirty_pencil = true

func set_active_brush(brush_node: Node):
	self.active_brush_node = brush_node
