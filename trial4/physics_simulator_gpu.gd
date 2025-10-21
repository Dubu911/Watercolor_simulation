# physics_simulator_gpu.gd
# GPU-accelerated watercolor physics using compute shaders
extends Node

# --- SIMULATION CONSTANTS ---
# These will be passed to shaders as uniforms
@export var S: float = 0.10 # Surface tension coefficient
@export var SP: float = 0.50 # Spread force coefficient
@export var canceling_power: float = 0.6747
@export var acceleration_power: float = 0.1536
@export var EVAPORATION_CONST: float = 0.01
@export var HOLD_THRESHOLD: float = 5.0
@export var DIFFUSION_RATE: float = 0.1
@export var diffusion_limiter: float = 0.25
@export var k_deposit_base: float = 1.0
@export var w_scale: float = 0.2

const DRY_PIXEL_LIMIT = 0.0001
const ENERGY_LOSS_ON_REDISTRIBUTION = 0.3
const K_ABSORPTION = 0.5
const EPS_A = 1e-6

# --- Canvas Dimensions ---
var canvas_width := 0
var canvas_height := 0

# --- RenderingDevice ---
var rd: RenderingDevice

# --- GPU Texture IDs (RIDs) ---
var water_read_tex: RID
var water_write_tex: RID
var mobile_read_tex: RID
var mobile_write_tex: RID
var static_read_tex: RID
var static_write_tex: RID
var inertia_read_tex: RID
var inertia_write_tex: RID
var absorbency_tex: RID
var displacement_tex: RID

# --- Compute Shader Pipeline RIDs ---
var evaporation_shader: RID
var evaporation_pipeline: RID
var displacement_shader: RID
var displacement_pipeline: RID
var inflow_shader: RID
var inflow_pipeline: RID
var diffusion_shader: RID
var diffusion_pipeline: RID
var deposition_shader: RID
var deposition_pipeline: RID

# --- Uniform Sets (bind textures to shaders) ---
var evaporation_uniform_set: RID
var displacement_uniform_set: RID
var inflow_uniform_set: RID
var diffusion_uniform_set: RID
var deposition_uniform_set: RID

# --- Live tuning ---
var values_changed_this_frame := false

func _process(delta: float):
	var change_speed = 0.1 * delta
	values_changed_this_frame = false

	if Input.is_key_pressed(KEY_R):
		canceling_power += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_F):
		canceling_power -= change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_T):
		acceleration_power += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_G):
		acceleration_power -= change_speed
		values_changed_this_frame = true

	canceling_power = clamp(canceling_power, 0.0, 1.0)
	acceleration_power = clamp(acceleration_power, 0.0, 1.0)

	if values_changed_this_frame:
		print("Canceling Power: %.4f | Acceleration Power: %.4f" % [canceling_power, acceleration_power])

# Initialize GPU resources
func init_gpu(p_width: int, p_height: int, absorbency_data: Image) -> bool:
	canvas_width = p_width
	canvas_height = p_height

	# Get RenderingDevice
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		printerr("Failed to create RenderingDevice!")
		return false

	print("GPU RenderingDevice created successfully")

	# Create GPU textures
	if not _create_textures(absorbency_data):
		return false

	# Load and compile compute shaders
	if not _create_compute_pipelines():
		return false

	# Create uniform sets (bind textures to shaders)
	if not _create_uniform_sets():
		return false

	print("GPU physics simulator initialized successfully")
	return true

# Create all GPU textures
func _create_textures(absorbency_data: Image) -> bool:
	var fmt_r32f := RDTextureFormat.new()
	fmt_r32f.width = canvas_width
	fmt_r32f.height = canvas_height
	fmt_r32f.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt_r32f.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
						  RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
						  RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

	var fmt_rgba32f := RDTextureFormat.new()
	fmt_rgba32f.width = canvas_width
	fmt_rgba32f.height = canvas_height
	fmt_rgba32f.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt_rgba32f.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
							 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
							 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

	# Create water textures (R32F format)
	var empty_r32f_data := PackedFloat32Array()
	empty_r32f_data.resize(canvas_width * canvas_height)
	empty_r32f_data.fill(0.0)

	water_read_tex = rd.texture_create(fmt_r32f, RDTextureView.new(), [empty_r32f_data.to_byte_array()])
	water_write_tex = rd.texture_create(fmt_r32f, RDTextureView.new(), [empty_r32f_data.to_byte_array()])

	# Create absorbency map and upload data
	var absorbency_bytes := _image_to_r32f_bytes(absorbency_data)
	absorbency_tex = rd.texture_create(fmt_r32f, RDTextureView.new(), [absorbency_bytes])

	# Create RGBA32F textures
	var empty_rgba32f_data := PackedFloat32Array()
	empty_rgba32f_data.resize(canvas_width * canvas_height * 4)
	# Fill with transparent white (1, 1, 1, 0)
	for i in range(canvas_width * canvas_height):
		empty_rgba32f_data[i * 4 + 0] = 1.0  # R
		empty_rgba32f_data[i * 4 + 1] = 1.0  # G
		empty_rgba32f_data[i * 4 + 2] = 1.0  # B
		empty_rgba32f_data[i * 4 + 3] = 0.0  # A

	mobile_read_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])
	mobile_write_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])
	static_read_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])
	static_write_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])
	inertia_read_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])
	inertia_write_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])
	displacement_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])

	print("GPU textures created successfully")
	return true

# Helper: Convert Image (FORMAT_RF) to R32F byte array
func _image_to_r32f_bytes(img: Image) -> PackedByteArray:
	var data := PackedFloat32Array()
	data.resize(img.get_width() * img.get_height())

	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel = img.get_pixel(x, y)
			data[y * img.get_width() + x] = pixel.r

	return data.to_byte_array()

# Helper: Convert Image (FORMAT_RGBAF) to RGBA32F byte array
func _image_to_rgba32f_bytes(img: Image) -> PackedByteArray:
	var data := PackedFloat32Array()
	data.resize(img.get_width() * img.get_height() * 4)

	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel = img.get_pixel(x, y)
			var idx = (y * img.get_width() + x) * 4
			data[idx + 0] = pixel.r
			data[idx + 1] = pixel.g
			data[idx + 2] = pixel.b
			data[idx + 3] = pixel.a

	return data.to_byte_array()

# Load and compile compute shaders
func _create_compute_pipelines() -> bool:
	# TODO: Load shader files and create pipelines
	# For now, return true (we'll implement shaders next)
	print("Compute pipelines creation placeholder - shaders needed")
	return true

# Create uniform sets (bind textures to shader bindings)
func _create_uniform_sets() -> bool:
	# TODO: Create uniform sets for each shader
	print("Uniform sets creation placeholder")
	return true

# Run simulation step on GPU
func run_simulation_step_gpu(delta: float, g_x: float, g_y: float):
	# TODO: Dispatch compute shaders
	# 1. Evaporation
	# 2. Calculate displacement
	# 3. Apply displacement with inflow
	# 4. Diffusion
	# 5. Deposition
	# 6. Swap texture references
	pass

# Upload paint data from CPU to GPU (for brush strokes)
func upload_paint_region(x: int, y: int, water_data: Image, pigment_data: Image):
	# Upload small region to GPU textures
	# This will be called when brush paints
	pass

# Get texture RIDs for display
func get_water_texture() -> RID:
	return water_read_tex

func get_mobile_texture() -> RID:
	return mobile_read_tex

func get_static_texture() -> RID:
	return static_read_tex

# Cleanup
func _exit_tree():
	if rd:
		# Free all textures
		if water_read_tex.is_valid(): rd.free_rid(water_read_tex)
		if water_write_tex.is_valid(): rd.free_rid(water_write_tex)
		if mobile_read_tex.is_valid(): rd.free_rid(mobile_read_tex)
		if mobile_write_tex.is_valid(): rd.free_rid(mobile_write_tex)
		if static_read_tex.is_valid(): rd.free_rid(static_read_tex)
		if static_write_tex.is_valid(): rd.free_rid(static_write_tex)
		if inertia_read_tex.is_valid(): rd.free_rid(inertia_read_tex)
		if inertia_write_tex.is_valid(): rd.free_rid(inertia_write_tex)
		if absorbency_tex.is_valid(): rd.free_rid(absorbency_tex)
		if displacement_tex.is_valid(): rd.free_rid(displacement_tex)

		# Free pipelines
		if evaporation_pipeline.is_valid(): rd.free_rid(evaporation_pipeline)
		if displacement_pipeline.is_valid(): rd.free_rid(displacement_pipeline)
		if inflow_pipeline.is_valid(): rd.free_rid(inflow_pipeline)
		if diffusion_pipeline.is_valid(): rd.free_rid(diffusion_pipeline)
		if deposition_pipeline.is_valid(): rd.free_rid(deposition_pipeline)

		# Free shaders
		if evaporation_shader.is_valid(): rd.free_rid(evaporation_shader)
		if displacement_shader.is_valid(): rd.free_rid(displacement_shader)
		if inflow_shader.is_valid(): rd.free_rid(inflow_shader)
		if diffusion_shader.is_valid(): rd.free_rid(diffusion_shader)
		if deposition_shader.is_valid(): rd.free_rid(deposition_shader)

		rd.free()
