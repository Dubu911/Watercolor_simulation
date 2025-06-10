# watercolor_particle.gd in watercolor_particle.tscn
extends Node2D

# --- Particle Properties ---
var color: Color = Color.BLACK       # Color of the particle
var size: float = 5.0              # Radius or influence area of the particle
var lifespan: float = 2.0          # How long the particle exists in seconds
var current_age: float = 0.0
var is_active: bool = true

# --- Reference to the Drawing Layer's Image (to be set when spawned) ---
var target_image: Image = null # Changed from drawing_layer_image
var canvas_width: int = 0
var canvas_height: int = 0

# Removed: drawing_layer_texture (not needed here, BrushLayer handles texture updates)

func _ready():
	pass

func deposit_color():
	if target_image == null or not is_active: # Check target_image
		return

	var local_pos_on_canvas: Vector2 = global_position # Particle's global_position is its position on the canvas image

	var i_radius = int(size)
	for y_offset in range(-i_radius, i_radius + 1):
		for x_offset in range(-i_radius, i_radius + 1):
			if Vector2(x_offset, y_offset).length_squared() <= size * size:
				var draw_x = int(local_pos_on_canvas.x + x_offset)
				var draw_y = int(local_pos_on_canvas.y + y_offset)

				if draw_x >= 0 and draw_x < canvas_width and draw_y >= 0 and draw_y < canvas_height:
					var existing_color = target_image.get_pixel(draw_x, draw_y) # Use target_image
					
					var particle_alpha = color.a 
					var blended_r = (color.r * particle_alpha) + (existing_color.r * (1.0 - particle_alpha))
					var blended_g = (color.g * particle_alpha) + (existing_color.g * (1.0 - particle_alpha))
					var blended_b = (color.b * particle_alpha) + (existing_color.b * (1.0 - particle_alpha))
					var blended_a = max(existing_color.a, particle_alpha) 

					target_image.set_pixel(draw_x, draw_y, Color(blended_r, blended_g, blended_b, blended_a)) # Use target_image
	
	# The BrushLayer.gd will handle marking the image as dirty and updating the texture.
	
# Modified setup function
func setup(p_position: Vector2, p_color: Color, p_size: float, p_lifespan: float, 
		   p_target_image: Image, # Changed parameter name
		   p_canvas_width: int, p_canvas_height: int):
	global_position = p_position
	color = p_color
	size = p_size
	lifespan = p_lifespan
	target_image = p_target_image # Assign to target_image
	canvas_width = p_canvas_width
	canvas_height = p_canvas_height
	current_age = 0.0
	is_active = true
	
	deposit_color() # Initial deposit
	
func _process(delta: float):
	if not is_active:
		return

	current_age += delta
	if current_age >= lifespan:
		is_active = false
		queue_free() 
		return

	# --- Future Particle Logic ---
	# Example: Fading out (you might want to re-deposit with fading color)
	# var life_ratio = 1.0 - (current_age / lifespan)
	# if life_ratio > 0:
	# 	var current_particle_color = Color(color.r, color.g, color.b, color.a * life_ratio)
	# 	# Need a way to deposit with a specific color if you do this,
	# 	# or modify 'color' and call deposit_color().
	# 	# For now, particles only deposit once on setup.
	# else:
	# 	# To ensure it's fully faded if we were re-depositing.
	# 	pass
