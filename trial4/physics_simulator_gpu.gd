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
	# Helper function to load, compile, and create pipeline for one shader
	var success = true

	# 1. Evaporation shader
	evaporation_shader = _compile_shader("res://trial4/shaders/evaporation.glsl", "Evaporation")
	if not evaporation_shader.is_valid():
		success = false
	else:
		evaporation_pipeline = rd.compute_pipeline_create(evaporation_shader)
		print("✓ Evaporation shader compiled")

	# 2. Displacement shader
	displacement_shader = _compile_shader("res://trial4/shaders/calculate_displacement.glsl", "Displacement")
	if not displacement_shader.is_valid():
		success = false
	else:
		displacement_pipeline = rd.compute_pipeline_create(displacement_shader)
		print("✓ Displacement shader compiled")

	# 3. Inflow shader
	inflow_shader = _compile_shader("res://trial4/shaders/apply_inflow.glsl", "Inflow")
	if not inflow_shader.is_valid():
		success = false
	else:
		inflow_pipeline = rd.compute_pipeline_create(inflow_shader)
		print("✓ Inflow shader compiled")

	# 4. Diffusion shader
	diffusion_shader = _compile_shader("res://trial4/shaders/diffusion.glsl", "Diffusion")
	if not diffusion_shader.is_valid():
		success = false
	else:
		diffusion_pipeline = rd.compute_pipeline_create(diffusion_shader)
		print("✓ Diffusion shader compiled")

	# 5. Deposition shader
	deposition_shader = _compile_shader("res://trial4/shaders/deposition.glsl", "Deposition")
	if not deposition_shader.is_valid():
		success = false
	else:
		deposition_pipeline = rd.compute_pipeline_create(deposition_shader)
		print("✓ Deposition shader compiled")

	if success:
		print("All compute shaders compiled successfully")
	else:
		printerr("Some shaders failed to compile!")

	return success

# Helper: Load and compile a single shader
func _compile_shader(path: String, name: String) -> RID:
	# Load shader source
	if not FileAccess.file_exists(path):
		printerr("Shader file not found: ", path)
		return RID()

	var shader_file = FileAccess.open(path, FileAccess.READ)
	if not shader_file:
		printerr("Failed to open shader file: ", path)
		return RID()

	var shader_source = shader_file.get_as_text()
	shader_file.close()

	# Create shader source object
	var shader_src := RDShaderSource.new()
	shader_src.source_compute = shader_source
	shader_src.language = RenderingDevice.SHADER_LANGUAGE_GLSL

	# Compile to SPIR-V
	var spirv := rd.shader_compile_spirv_from_source(shader_src)

	# Check for compilation errors
	if spirv.compile_error_compute != "":
		printerr("=== ", name, " Shader Compilation Error ===")
		printerr(spirv.compile_error_compute)
		printerr("==========================================")
		return RID()

	# Create shader from SPIR-V
	var shader_rid := rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		printerr("Failed to create shader RID for: ", name)
		return RID()

	return shader_rid

# Create uniform sets (bind textures to shader bindings)
func _create_uniform_sets() -> bool:
	_create_evaporation_uniform_set()
	_create_displacement_uniform_set()
	_create_inflow_uniform_set()
	_create_diffusion_uniform_set()
	_create_deposition_uniform_set()

	print("All uniform sets created successfully")
	return true

# Evaporation shader: 2 bindings (water_read, water_write)
func _create_evaporation_uniform_set():
	if evaporation_uniform_set.is_valid():
		rd.free_rid(evaporation_uniform_set)

	var uniforms := []

	# Binding 0: water_read
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(water_read_tex)
	uniforms.append(u0)

	# Binding 1: water_write
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(water_write_tex)
	uniforms.append(u1)

	evaporation_uniform_set = rd.uniform_set_create(uniforms, evaporation_shader, 0)

# Displacement shader: 2 bindings (water_read, displacement_map)
func _create_displacement_uniform_set():
	if displacement_uniform_set.is_valid():
		rd.free_rid(displacement_uniform_set)

	var uniforms := []

	# Binding 0: water_read
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(water_read_tex)
	uniforms.append(u0)

	# Binding 1: displacement_map
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(displacement_tex)
	uniforms.append(u1)

	displacement_uniform_set = rd.uniform_set_create(uniforms, displacement_shader, 0)

# Inflow shader: 8 bindings (water, mobile, absorbency, displacement, inertia)
func _create_inflow_uniform_set():
	if inflow_uniform_set.is_valid():
		rd.free_rid(inflow_uniform_set)

	var uniforms := []

	# Binding 0: water_read
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(water_read_tex)
	uniforms.append(u0)

	# Binding 1: water_write
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(water_write_tex)
	uniforms.append(u1)

	# Binding 2: mobile_read
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 2
	u2.add_id(mobile_read_tex)
	uniforms.append(u2)

	# Binding 3: mobile_write
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u3.binding = 3
	u3.add_id(mobile_write_tex)
	uniforms.append(u3)

	# Binding 4: absorbency_map
	var u4 := RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u4.binding = 4
	u4.add_id(absorbency_tex)
	uniforms.append(u4)

	# Binding 5: displacement_map
	var u5 := RDUniform.new()
	u5.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u5.binding = 5
	u5.add_id(displacement_tex)
	uniforms.append(u5)

	# Binding 6: inertia_read
	var u6 := RDUniform.new()
	u6.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u6.binding = 6
	u6.add_id(inertia_read_tex)
	uniforms.append(u6)

	# Binding 7: inertia_write
	var u7 := RDUniform.new()
	u7.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u7.binding = 7
	u7.add_id(inertia_write_tex)
	uniforms.append(u7)

	inflow_uniform_set = rd.uniform_set_create(uniforms, inflow_shader, 0)

# Diffusion shader: 3 bindings (water_read, mobile_read, mobile_write)
func _create_diffusion_uniform_set():
	if diffusion_uniform_set.is_valid():
		rd.free_rid(diffusion_uniform_set)

	var uniforms := []

	# Binding 0: water_read
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(water_read_tex)
	uniforms.append(u0)

	# Binding 1: mobile_read
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(mobile_read_tex)
	uniforms.append(u1)

	# Binding 2: mobile_write
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 2
	u2.add_id(mobile_write_tex)
	uniforms.append(u2)

	diffusion_uniform_set = rd.uniform_set_create(uniforms, diffusion_shader, 0)

# Deposition shader: 6 bindings (water, mobile, static, absorbency)
func _create_deposition_uniform_set():
	if deposition_uniform_set.is_valid():
		rd.free_rid(deposition_uniform_set)

	var uniforms := []

	# Binding 0: water_read
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(water_read_tex)
	uniforms.append(u0)

	# Binding 1: mobile_read
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(mobile_read_tex)
	uniforms.append(u1)

	# Binding 2: mobile_write
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 2
	u2.add_id(mobile_write_tex)
	uniforms.append(u2)

	# Binding 3: static_read
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u3.binding = 3
	u3.add_id(static_read_tex)
	uniforms.append(u3)

	# Binding 4: static_write
	var u4 := RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u4.binding = 4
	u4.add_id(static_write_tex)
	uniforms.append(u4)

	# Binding 5: absorbency_map
	var u5 := RDUniform.new()
	u5.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u5.binding = 5
	u5.add_id(absorbency_tex)
	uniforms.append(u5)

	deposition_uniform_set = rd.uniform_set_create(uniforms, deposition_shader, 0)

# Run simulation step on GPU
func run_simulation_step_gpu(delta: float, g_x: float, g_y: float):
	# Calculate work group dispatch size (8x8 work groups)
	var groups_x = int(ceil(float(canvas_width) / 8.0))
	var groups_y = int(ceil(float(canvas_height) / 8.0))

	# Step 1: Evaporation (water_read → water_write)
	_dispatch_evaporation(groups_x, groups_y, delta)
	_swap_water_textures()

	# Step 2: Calculate displacement forces (water_read → displacement_map)
	_dispatch_displacement(groups_x, groups_y, g_x, g_y)

	# Step 3: Apply displacement with inflow + momentum (reads all, writes water/mobile/inertia)
	_dispatch_inflow(groups_x, groups_y, delta)
	_swap_water_textures()
	_swap_mobile_textures()
	_swap_inertia_textures()

	# Step 4: Diffusion (mobile_read → mobile_write)
	_dispatch_diffusion(groups_x, groups_y, delta)
	_swap_mobile_textures()

	# Step 5: Deposition (mobile/static_read → mobile/static_write)
	_dispatch_deposition(groups_x, groups_y, delta)
	_swap_mobile_textures()
	_swap_static_textures()

# Dispatch evaporation shader
func _dispatch_evaporation(groups_x: int, groups_y: int, delta: float):
	var compute_list = rd.compute_list_begin()

	# Bind pipeline and uniform set
	rd.compute_list_bind_compute_pipeline(compute_list, evaporation_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, evaporation_uniform_set, 0)

	# Pack push constants
	var params = PackedFloat32Array([
		delta,
		EVAPORATION_CONST,
		DRY_PIXEL_LIMIT,
		float(canvas_width),
		float(canvas_height)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	# Dispatch
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	# Submit and wait
	rd.submit()
	rd.sync()

# Dispatch displacement calculation shader
func _dispatch_displacement(groups_x: int, groups_y: int, g_x: float, g_y: float):
	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, displacement_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, displacement_uniform_set, 0)

	# Pack push constants
	var params = PackedFloat32Array([
		g_x,
		g_y,
		S,
		SP,
		HOLD_THRESHOLD,
		ENERGY_LOSS_ON_REDISTRIBUTION,
		DRY_PIXEL_LIMIT,
		float(canvas_width),
		float(canvas_height)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

# Dispatch inflow shader (with momentum)
func _dispatch_inflow(groups_x: int, groups_y: int, delta: float):
	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, inflow_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, inflow_uniform_set, 0)

	# Pack push constants
	var params = PackedFloat32Array([
		delta,
		canceling_power,
		acceleration_power,
		DRY_PIXEL_LIMIT,
		K_ABSORPTION,
		EPS_A,
		float(canvas_width),
		float(canvas_height)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

# Dispatch diffusion shader
func _dispatch_diffusion(groups_x: int, groups_y: int, delta: float):
	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, diffusion_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, diffusion_uniform_set, 0)

	# Pack push constants
	var params = PackedFloat32Array([
		delta,
		DIFFUSION_RATE,
		diffusion_limiter,
		DRY_PIXEL_LIMIT,
		K_ABSORPTION,
		EPS_A,
		float(canvas_width),
		float(canvas_height)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

# Dispatch deposition shader
func _dispatch_deposition(groups_x: int, groups_y: int, delta: float):
	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, deposition_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, deposition_uniform_set, 0)

	# Pack push constants
	var params = PackedFloat32Array([
		delta,
		k_deposit_base,
		w_scale,
		DRY_PIXEL_LIMIT,
		K_ABSORPTION,
		EPS_A,
		float(canvas_width),
		float(canvas_height)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

# Texture swapping functions (Solution A: recreate uniform sets)
func _swap_water_textures():
	var temp = water_read_tex
	water_read_tex = water_write_tex
	water_write_tex = temp

	# Recreate uniform sets that use water textures
	_create_evaporation_uniform_set()
	_create_displacement_uniform_set()
	_create_inflow_uniform_set()
	_create_diffusion_uniform_set()
	_create_deposition_uniform_set()

func _swap_mobile_textures():
	var temp = mobile_read_tex
	mobile_read_tex = mobile_write_tex
	mobile_write_tex = temp

	# Recreate uniform sets that use mobile textures
	_create_inflow_uniform_set()
	_create_diffusion_uniform_set()
	_create_deposition_uniform_set()

func _swap_static_textures():
	var temp = static_read_tex
	static_read_tex = static_write_tex
	static_write_tex = temp

	# Recreate uniform set that uses static textures
	_create_deposition_uniform_set()

func _swap_inertia_textures():
	var temp = inertia_read_tex
	inertia_read_tex = inertia_write_tex
	inertia_write_tex = temp

	# Recreate uniform set that uses inertia textures
	_create_inflow_uniform_set()

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
