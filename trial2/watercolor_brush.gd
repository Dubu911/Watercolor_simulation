# watercolor_brush.gd
extends Node2D

# --- Particle System Properties (Export these to adjust in Inspector) ---
@export var particle_scene_path: String = "res://trial1/watercolor_particle.tscn" # Adjust if your path is different
@export var brush_color: Color = Color(0.1, 0.2, 0.8, 0.3) # Default watercolor color with alpha
@export var base_brush_size: float = 15.0      # Base size for particles spawned
@export var particle_lifespan: float = 1.0 # How long particles from this brush live
@export var particles_per_frame: int = 5  # How many particles to spawn while dragging

# --- Internal ---
var WatercolorParticleScene: PackedScene
var particles_node: Node # A node to hold all active particles for organization
var coordinator_ref # Reference to the painting_coordinator
var is_painting: bool = false # Tracks if the mouse button is held for painting

func _ready():
	# Preload the particle scene
	if particle_scene_path.is_empty():
		printerr(name + ": Particle Scene Path is not set!")
		return
	WatercolorParticleScene = load(particle_scene_path)
	if WatercolorParticleScene == null:
		printerr(name + ": Failed to load WatercolorParticleScene from path: " + particle_scene_path)
		return

	# Create a container node for particles, child of this brush node
	particles_node = Node.new()
	particles_node.name = "ActiveParticlesContainer"
	add_child(particles_node)


func activate(coordinator):
	coordinator_ref = coordinator
	is_painting = false # Reset painting state when activated
	# print(name + " activated.") # Debug print removed

func deactivate():
	is_painting = false # Ensure painting stops if brush is deactivated mid-stroke
	# print(name + " deactivated.") # Debug print removed


func handle_input(event: InputEvent, mouse_pos_img_space: Vector2, target_image: Image, coordinator):
	if not coordinator_ref: coordinator_ref = coordinator
	if WatercolorParticleScene == null: return # Scene not loaded

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_painting = true
			# Spawn a burst of particles on initial click
			for i in range(particles_per_frame * 2): # More particles on initial dab
				_spawn_particle(mouse_pos_img_space, target_image, coordinator)
		else: # Mouse button released
			is_painting = false
			
	elif event is InputEventMouseMotion and is_painting:
		# Spawn particles continuously while dragging
		for i in range(particles_per_frame):
			_spawn_particle(mouse_pos_img_space, target_image, coordinator)


func _spawn_particle(position_on_image: Vector2, target_img: Image, coordinator):
	if WatercolorParticleScene == null:
		# This check is a bit redundant if _ready() succeeded, but good for safety
		printerr(name + ": WatercolorParticleScene not loaded in _spawn_particle!")
		return
	if not is_instance_valid(target_img):
		printerr(name + ": Target image is not valid in _spawn_particle!")
		return

	var particle_instance = WatercolorParticleScene.instantiate() as Node2D
	if not particle_instance:
		printerr(name + ": Failed to instantiate particle scene.")
		return
		
	particles_node.add_child(particle_instance) # Add to the dedicated particle container

	# Calculate spawn position with some randomness based on brush size
	var spawn_pos = position_on_image
	var offset_radius = base_brush_size * 0.5 # Randomness relative to base size
	spawn_pos.x += randf_range(-offset_radius, offset_radius)
	spawn_pos.y += randf_range(-offset_radius, offset_radius)

	# Clamp spawn position to be within canvas bounds (using constants from coordinator if available, or hardcode)
	# Assuming coordinator has CANVAS_WIDTH and CANVAS_HEIGHT constants
	var canvas_width = coordinator.CANVAS_WIDTH if coordinator and coordinator.has_meta("CANVAS_WIDTH") else 2000
	var canvas_height = coordinator.CANVAS_HEIGHT if coordinator and coordinator.has_meta("CANVAS_HEIGHT") else 2000
	
	spawn_pos.x = clampf(spawn_pos.x, 0, canvas_width - 1)
	spawn_pos.y = clampf(spawn_pos.y, 0, canvas_height - 1)

	# Particle setup call
	# The particle's global_position will be set based on its parent (particles_node)
	# and its own position. Since particles_node is a child of this brush node,
	# and this brush node is likely at (0,0) in the painting_coordinator's space,
	# the particle's position needs to be set relative to the image.
	# The particle's script should handle its drawing based on its own global_position
	# being interpreted as image coordinates.
	
	# If particles_node is at (0,0) relative to this watercolor_brush node,
	# and watercolor_brush node is at (0,0) relative to painting_coordinator,
	# and painting_coordinator's layers are at (0,0) relative to main2,
	# then spawn_pos (which is in image space) is the correct local position for the particle
	# *if the particle itself interprets its global_position as image coordinates*.
	
	# Let's assume the particle's setup function takes the position in image coordinates
	# and the particle itself will use this to draw on the target_img.
	# The particle's own node position will be set to this spawn_pos.
	particle_instance.position = spawn_pos # Set particle's local position within particles_node

	if particle_instance.has_method("setup"):
		particle_instance.setup(
			spawn_pos, # The particle will use this position for drawing logic
			brush_color,
			base_brush_size * randf_range(0.7, 1.3), # Randomize size slightly
			particle_lifespan * randf_range(0.8, 1.2), # Randomize lifespan slightly
			target_img, # Pass the reference to the Image (e.g., watercolor_image)
			canvas_width,
			canvas_height
		)
	else:
		printerr(name + ": Particle instance does not have a setup method!")
		particle_instance.queue_free() # Clean up unsetup-able particle
		return

	# Mark the relevant image as dirty so painting_coordinator updates the texture
	if coordinator_ref:
		if target_img == coordinator_ref.watercolor_image:
			coordinator_ref.mark_watercolor_dirty()
		# Add similar check if watercolor could ever draw on pencil_image (unlikely)
