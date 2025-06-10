extends Sprite2D

# Enum to define brush types
enum BrushType { WATERCOLOR, PENCIL, ERASER }

# --- Canvas Properties ---
const CANVAS_WIDTH := 2000
const CANVAS_HEIGHT := 2000

# --- Current Brush State ---
var current_brush_type: BrushType = BrushType.WATERCOLOR:
	set(value):
		current_brush_type = value
		# Reset last_draw_pos when brush changes to avoid connecting lines across brush types
		last_draw_pos = Vector2.INF
		print("Brush changed to: ", BrushType.keys()[current_brush_type])


# --- Watercolor Layer (this Sprite2D) ---
var watercolor_image : Image
var watercolor_texture : ImageTexture
var dirty_watercolor_image: bool = false

# --- Particle System Properties (for Watercolor) ---
const WatercolorParticleScene = preload("res://particle/watercolor_particle.tscn") # Path to the particle scene
var particles_node: Node # A node to hold all active particles for organization
var watercolor_brush_color: Color = Color(0.1, 0.2, 0.8, 0.3) # Current watercolor brush color
var watercolor_brush_size: float = 15.0      # Base size for watercolor particles
var particle_lifespan: float = 1.0 # How long particles from this brush live
var particles_per_frame: int = 5  # How many particles to spawn while dragging watercolor

# --- Pencil Layer ---
@export var pencil_layer_node_path: NodePath # Assign the PencilLayer Sprite2D from the editor
var pencil_layer_sprite: Sprite2D
var pencil_image: Image
var pencil_texture: ImageTexture
var dirty_pencil_image: bool = false

# --- Pencil Properties ---
var pencil_color: Color = Color.BLACK
var pencil_stroke_width: float = 2.0 # Pixel width for pencil lines

# --- Eraser Properties ---
var eraser_stroke_width: float = 20.0 # Pixel width for eraser

# --- Common Drawing State ---
var last_draw_pos: Vector2 = Vector2.INF # Stores the last mouse position for drawing continuous lines (pencil/eraser)
var is_drawing: bool = false # Tracks if the left mouse button is currently pressed

func _ready():
	# --- Initialize Watercolor Layer (this node) ---
	watercolor_image = Image.create_empty(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	# Optional: Fill watercolor background if needed, e.g., transparent
	# watercolor_image.fill(Color(0,0,0,0)) 
	watercolor_texture = ImageTexture.create_from_image(watercolor_image)
	texture = watercolor_texture # Set this Sprite2D's texture to the watercolor texture
	
	# Create a container node for particles, child of this watercolor layer
	particles_node = Node.new()
	particles_node.name = "ActiveParticles"
	add_child(particles_node)

	# --- Initialize Pencil Layer ---
	if pencil_layer_node_path.is_empty():
		printerr("Pencil Layer Node Path is not set in BrushLayer.gd inspector!")
		return
	
	pencil_layer_sprite = get_node_or_null(pencil_layer_node_path) as Sprite2D
	if not pencil_layer_sprite:
		printerr("Pencil Layer Sprite2D not found at path: ", pencil_layer_node_path)
		return

	pencil_image = Image.create_empty(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	# Pencil layer starts transparent
	pencil_image.fill(Color(0,0,0,0)) 
	pencil_texture = ImageTexture.create_from_image(pencil_image)
	pencil_layer_sprite.texture = pencil_texture
	
	print("BrushLayer ready. Watercolor and Pencil layers initialized.")


func _input(event : InputEvent):
	var global_mouse_pos = get_global_mouse_position()
	# Convert global mouse position to local coordinates of this Sprite2D (which is the watercolor canvas)
	# This assumes this node (BrushLayer/WatercolorLayer) is not scaled or rotated relative to the pencil layer.
	# If they have different transforms, you'd need to ensure positions are consistent.
	var local_mouse_pos_on_canvas: Vector2 = to_local(global_mouse_pos)

	# Handle mouse button presses for starting/stopping drawing
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_drawing = true
			last_draw_pos = local_mouse_pos_on_canvas # Record start position
			# For pencil/eraser, draw a dot on initial click
			if current_brush_type == BrushType.PENCIL:
				_draw_line_on_pencil_layer(local_mouse_pos_on_canvas, local_mouse_pos_on_canvas, pencil_color, pencil_stroke_width)
			elif current_brush_type == BrushType.ERASER:
				_erase_line_on_pencil_layer(local_mouse_pos_on_canvas, local_mouse_pos_on_canvas, eraser_stroke_width)
		else:
			is_drawing = false
			last_draw_pos = Vector2.INF # Reset last position

	# Handle mouse motion for continuous drawing/particle spawning
	if event is InputEventMouseMotion and is_drawing:
		if not (local_mouse_pos_on_canvas.x >= 0 and local_mouse_pos_on_canvas.x < CANVAS_WIDTH and \
				local_mouse_pos_on_canvas.y >= 0 and local_mouse_pos_on_canvas.y < CANVAS_HEIGHT):
			# Mouse is outside canvas, stop drawing and reset last_draw_pos
			# is_drawing = false # Optional: stop drawing if mouse leaves canvas while pressed
			last_draw_pos = Vector2.INF
			return

		match current_brush_type:
			BrushType.WATERCOLOR:
				for i in range(particles_per_frame):
					spawn_particle(local_mouse_pos_on_canvas)
			
			BrushType.PENCIL:
				if last_draw_pos != Vector2.INF:
					_draw_line_on_pencil_layer(last_draw_pos, local_mouse_pos_on_canvas, pencil_color, pencil_stroke_width)
				last_draw_pos = local_mouse_pos_on_canvas
			
			BrushType.ERASER:
				if last_draw_pos != Vector2.INF:
					_erase_line_on_pencil_layer(last_draw_pos, local_mouse_pos_on_canvas, eraser_stroke_width)
				last_draw_pos = local_mouse_pos_on_canvas


func spawn_particle(position_on_canvas: Vector2):
	if WatercolorParticleScene == null:
		printerr("WatercolorParticleScene not loaded!")
		return

	var particle_instance = WatercolorParticleScene.instantiate() as Node2D
	particles_node.add_child(particle_instance) # Add to dedicated particle container

	var spawn_pos = position_on_canvas
	var offset_radius = watercolor_brush_size * 0.5
	spawn_pos.x += randf_range(-offset_radius, offset_radius)
	spawn_pos.y += randf_range(-offset_radius, offset_radius)
	spawn_pos.x = clampf(spawn_pos.x, 0, CANVAS_WIDTH - 1)
	spawn_pos.y = clampf(spawn_pos.y, 0, CANVAS_HEIGHT - 1)

	# Call the particle's setup function
	# Pass the watercolor_image for particles to draw on
	particle_instance.setup(
		spawn_pos,
		watercolor_brush_color,
		watercolor_brush_size * randf_range(0.7, 1.3),
		particle_lifespan * randf_range(0.8, 1.2),
		watercolor_image, # Pass the watercolor image
		CANVAS_WIDTH,
		CANVAS_HEIGHT
	)
	dirty_watercolor_image = true # Mark watercolor image as changed


# --- Pencil Drawing ---
func _draw_line_on_pencil_layer(from_pos: Vector2, to_pos: Vector2, color: Color, width: float):
	if not pencil_image: return

	# Simple line drawing by drawing circles along the path
	# More sophisticated line algorithms (e.g., Bresenham for lines, then stroke) exist
	# but this is a basic approach.
	var distance = from_pos.distance_to(to_pos)
	var direction = from_pos.direction_to(to_pos)
	var radius = width / 2.0
	
	if distance < 0.1: # If it's essentially a dot
		_draw_circle_on_image(pencil_image, to_pos, radius, color)
	else:
		# Iterate along the line and draw circles
		var current_pos = from_pos
		var step_size = radius * 0.5 # Smaller step for smoother lines
		var steps = int(distance / step_size)
		if steps == 0: steps = 1

		for i in range(steps + 1):
			var p = from_pos.lerp(to_pos, float(i)/steps)
			_draw_circle_on_image(pencil_image, p, radius, color)
			
	dirty_pencil_image = true

# --- Eraser ---
func _erase_line_on_pencil_layer(from_pos: Vector2, to_pos: Vector2, width: float):
	# Erasing is drawing with a transparent color on the pencil layer
	_draw_line_on_pencil_layer(from_pos, to_pos, Color(0,0,0,0), width)
	# dirty_pencil_image is already set by _draw_line_on_pencil_layer

# --- Helper to draw a filled circle on an Image ---
func _draw_circle_on_image(img: Image, center: Vector2, radius: float, color: Color):
	var i_radius = int(ceil(radius)) # Use ceil to ensure full coverage
	var center_x_int = int(round(center.x))
	var center_y_int = int(round(center.y))

	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			# Check if the pixel is within the circle
			if Vector2(x_offset, y_offset).length_squared() <= radius * radius:
				var draw_x = center_x_int + x_offset
				var draw_y = center_y_int + y_offset

				if draw_x >= 0 and draw_x < CANVAS_WIDTH and \
				   draw_y >= 0 and draw_y < CANVAS_HEIGHT:
					# For pencil and eraser, we directly set the pixel (no blending needed for basic pencil)
					# If you want blending for pencil (e.g. softer pencil), you'd do similar to watercolor particle
					img.set_pixel(draw_x, draw_y, color)


func _process(_delta: float):
	if dirty_watercolor_image:
		watercolor_texture.update(watercolor_image)
		dirty_watercolor_image = false
	
	if dirty_pencil_image:
		if pencil_texture and pencil_image:
			pencil_texture.update(pencil_image)
		dirty_pencil_image = false

# --- Button Signal Handlers ---
func _on_watercolor_button_pressed():
	current_brush_type = BrushType.WATERCOLOR

func _on_pencil_button_pressed():
	current_brush_type = BrushType.PENCIL

func _on_eraser_button_pressed():
	current_brush_type = BrushType.ERASER
