# painting_coordinator.gd (Corrected and with new add_paint_at function)
extends Node

# --- Canvas Properties ---
const CANVAS_WIDTH := 2000
const CANVAS_HEIGHT := 2000

@onready var physics_simulator = $physics_simulator

# --- Node Path Managements ---
@export var water_layer_sprite_path: NodePath
@export var mobile_layer_sprite_path: NodePath
@export var static_layer_sprite_path: NodePath
@export var pencil_layer_sprite_path: NodePath
@export var brush_manager_path: NodePath

# --- Internal Layer Sprite References ---
var water_layer_sprite: Sprite2D
var mobile_layer_sprite: Sprite2D
var static_layer_sprite: Sprite2D
var pencil_layer_sprite: Sprite2D

# --- Image Data (The actual data for the simulation) ---
var water_image: Image
var mobile_image: Image
var static_image: Image
var pencil_image: Image

# --- Textures (The GPU version of the data for display) ---
var water_texture: ImageTexture
var mobile_texture: ImageTexture
var static_texture: ImageTexture
var pencil_texture: ImageTexture

# --- Status Flags ---
var _dirty_watercolor: bool = false
var _dirty_pencil: bool = false
var active_brush_node: Node = null


func _ready():
	# 1. Get Layer Sprite2D Nodes with more robust checks
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
	# Water layer uses a floating-point format for precision
	water_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RF)
	water_texture = ImageTexture.create_from_image(water_image)
	water_layer_sprite.texture = water_texture
	
	# Mobile layer is for wet pigment, starts transparent
	mobile_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	mobile_image.fill(Color(0, 0, 0, 0)) # Start fully transparent
	mobile_texture = ImageTexture.create_from_image(mobile_image)
	mobile_layer_sprite.texture = mobile_texture
	
	# Static layer is the "paper", starts white
	static_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	static_image.fill(Color.WHITE)
	static_texture = ImageTexture.create_from_image(static_image)
	static_layer_sprite.texture = static_texture
	
	# The pencil layer starts transparent
	pencil_image = Image.create(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	pencil_image.fill(Color(0, 0, 0, 0))
	pencil_texture = ImageTexture.create_from_image(pencil_image)
	pencil_layer_sprite.texture = pencil_texture
	
	# All layers are centered = false to draw from top-left (0,0)
	water_layer_sprite.centered = false
	mobile_layer_sprite.centered = false
	static_layer_sprite.centered = false
	pencil_layer_sprite.centered = false

	# Start dirty for initial update
	mark_watercolor_dirty()
	mark_pencil_dirty()
	
# The main simulation loop
func _process(_delta: float):
	# --- Physics Simulations will go here in the future ---
	
	# --- Texture Updates ---
	if _dirty_watercolor:
		if water_texture and water_image: water_texture.update(water_image)
		if mobile_texture and mobile_image: mobile_texture.update(mobile_image)
		if static_texture and static_image: static_texture.update(static_image)
		_dirty_watercolor = false
	
	if _dirty_pencil:
		if pencil_texture and pencil_image: pencil_texture.update(pencil_image)
		_dirty_pencil = false


# This is the function your watercolor brush will now call.
# This function applies a "dab" of paint directly to the data layers.
func add_paint_at(pos: Vector2, color: Color, water: float, size: float):
	var i_radius = int(size)
	# Loop through a square around the dab position
	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			# Check if the pixel is inside the circular dab
			if Vector2(x_offset, y_offset).length_squared() <= size * size:
				var draw_x = int(pos.x + x_offset)
				var draw_y = int(pos.y + y_offset)

				# Check if the pixel is within the canvas bounds
				if draw_x >= 0 and draw_x < CANVAS_WIDTH and draw_y >= 0 and draw_y < CANVAS_HEIGHT:
					
					# --- Add water to the water layer ---
					var current_water = water_image.get_pixel(draw_x, draw_y).r
					var new_water = min(1.0, current_water + water) # Cap water at 1.0
					water_image.set_pixel(draw_x, draw_y, Color(new_water, 0, 0))
					
					# --- Add color to the mobile pigment layer ---
					# This is a simple blend for now. More complex logic can be added later.
					var existing_mobile_color = mobile_image.get_pixel(draw_x, draw_y)
					var blended_color = existing_mobile_color.blend(color)
					mobile_image.set_pixel(draw_x, draw_y, blended_color)
	
	# After adding paint, we MUST mark the watercolor layers as dirty for an update.
	mark_watercolor_dirty()

func draw_line_on_pencil_layer(from_pos: Vector2, to_pos: Vector2, color: Color, radius: float):
	if not is_instance_valid(pencil_image): return
	
	var distance = from_pos.distance_to(to_pos)
	
	# Determine number of steps to draw circles along the line to avoid gaps
	var step_size = max(1.0, radius * 0.5)
	var steps = int(ceil(distance / step_size))
	if steps == 0: steps = 1

	for i in range(steps + 1):
		var p = from_pos.lerp(to_pos, float(i) / steps)
		_draw_dot(pencil_image, p.floor(), color, radius)
	
	mark_pencil_dirty()

func _draw_dot(img: Image, center_pos: Vector2, color: Color, radius: float):
	var i_radius = int(ceil(radius))
	var center_x = int(center_pos.x)
	var center_y = int(center_pos.y)

	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= radius * radius:
				var draw_x = center_x + x_offset
				var draw_y = center_y + y_offset
				if draw_x >= 0 and draw_x < CANVAS_WIDTH and draw_y >= 0 and draw_y < CANVAS_HEIGHT:
					# For pencil/eraser, we just overwrite the pixel
					img.set_pixel(draw_x, draw_y, color)


func mark_watercolor_dirty():
	_dirty_watercolor = true

func mark_pencil_dirty():
	_dirty_pencil = true

func set_active_brush(brush_node: Node):
	self.active_brush_node = brush_node
