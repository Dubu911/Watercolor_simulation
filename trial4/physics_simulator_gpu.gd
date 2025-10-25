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
@export var HOLD_THRESHOLD: float = 15.0
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

# --- Pipeline Cache ---
var _pipelines_ready := false

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
# Temporary paint buffers (for uploading brush strokes)
var paint_water_tex: RID
var paint_pigment_tex: RID
var removal_mask_tex: RID

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
var add_paint_shader: RID
var add_paint_pipeline: RID
var remove_paint_shader: RID
var remove_paint_pipeline: RID

# --- Uniform Sets (bind textures to shaders) ---
var evaporation_uniform_set: RID
var displacement_uniform_set: RID
var inflow_uniform_set: RID
var diffusion_uniform_set: RID
var deposition_uniform_set: RID
var add_paint_uniform_set: RID
var remove_paint_uniform_set: RID

# --- Live tuning ---
var values_changed_this_frame := false

# --- Q key evaporation boost ---
var _saved_evaporation_const: float = 0.01
var _evaporation_boosted: bool = false

func _process(delta: float):
	var change_speed = 0.1 * delta
	values_changed_this_frame = false

	# Q key: Boost evaporation to 1.0 while held
	if Input.is_key_pressed(KEY_Q):
		if not _evaporation_boosted:
			_saved_evaporation_const = EVAPORATION_CONST
			EVAPORATION_CONST = 1.0
			_evaporation_boosted = true
			print("Evaporation boosted to 1.0 (saved: %.4f)" % _saved_evaporation_const)
	else:
		if _evaporation_boosted:
			EVAPORATION_CONST = _saved_evaporation_const
			_evaporation_boosted = false
			print("Evaporation restored to %.4f" % EVAPORATION_CONST)

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

	# Get RenderingDevice (use global device for Texture2DRD compatibility)
	rd = RenderingServer.get_rendering_device()
	if not rd:
		printerr("Failed to get RenderingDevice!")
		return false

	print("GPU RenderingDevice acquired successfully")

	# (Re)create textures for the new size
	if not _create_textures(absorbency_data):
		return false

	# Compile once, reuse across resizes
	if not _pipelines_ready:
		if not _create_compute_pipelines():
			return false
		_pipelines_ready = true

	# Rebuild uniform sets because they depend on the *current* textures
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
						  RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
						  RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	var fmt_rgba32f := RDTextureFormat.new()
	fmt_rgba32f.width = canvas_width
	fmt_rgba32f.height = canvas_height
	fmt_rgba32f.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt_rgba32f.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
							 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
							 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
							 RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

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

	# Create paint buffer textures (for adding paint via compute shader)
	paint_water_tex = rd.texture_create(fmt_r32f, RDTextureView.new(), [empty_r32f_data.to_byte_array()])
	paint_pigment_tex = rd.texture_create(fmt_rgba32f, RDTextureView.new(), [empty_rgba32f_data.to_byte_array()])

	# Create removal mask texture (for removing paint via compute shader)
	removal_mask_tex = rd.texture_create(fmt_r32f, RDTextureView.new(), [empty_r32f_data.to_byte_array()])

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
			var pixel: Color = img.get_pixel(x, y)
			var idx: int = (y * img.get_width() + x) * 4
			data[idx + 0] = pixel.r
			data[idx + 1] = pixel.g
			data[idx + 2] = pixel.b
			data[idx + 3] = pixel.a

	return data.to_byte_array()

# Load and compile compute shaders
func _create_compute_pipelines() -> bool:
	var success = true

	# 1. Evaporation shader
	evaporation_shader = _compile_shader("res://trial4/shaders/evaporation.glsl", "Evaporation")
	if not evaporation_shader.is_valid():
		success = false
	else:
		evaporation_pipeline = rd.compute_pipeline_create(evaporation_shader)

	# 2. Displacement shader
	displacement_shader = _compile_shader("res://trial4/shaders/calculate_displacement.glsl", "Displacement")
	if not displacement_shader.is_valid():
		success = false
	else:
		displacement_pipeline = rd.compute_pipeline_create(displacement_shader)

	# 3. Inflow shader
	inflow_shader = _compile_shader("res://trial4/shaders/apply_inflow.glsl", "Inflow")
	if not inflow_shader.is_valid():
		success = false
	else:
		inflow_pipeline = rd.compute_pipeline_create(inflow_shader)

	# 4. Diffusion shader
	diffusion_shader = _compile_shader("res://trial4/shaders/diffusion.glsl", "Diffusion")
	if not diffusion_shader.is_valid():
		success = false
	else:
		diffusion_pipeline = rd.compute_pipeline_create(diffusion_shader)

	# 5. Deposition shader
	deposition_shader = _compile_shader("res://trial4/shaders/deposition.glsl", "Deposition")
	if not deposition_shader.is_valid():
		success = false
	else:
		deposition_pipeline = rd.compute_pipeline_create(deposition_shader)

	# 6. Add paint shader
	add_paint_shader = _compile_shader("res://trial4/shaders/add_paint.glsl", "AddPaint")
	if not add_paint_shader.is_valid():
		success = false
	else:
		add_paint_pipeline = rd.compute_pipeline_create(add_paint_shader)

	# 7. Remove paint shader
	remove_paint_shader = _compile_shader("res://trial4/shaders/remove_paint.glsl", "RemovePaint")
	if not remove_paint_shader.is_valid():
		success = false
	else:
		remove_paint_pipeline = rd.compute_pipeline_create(remove_paint_shader)

	if success:
		print("GPU: All 7 compute shaders compiled successfully")
	else:
		printerr("GPU: Some shaders failed to compile!")

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
	_create_add_paint_uniform_set()
	_create_remove_paint_uniform_set()

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

# Add paint shader: 4 bindings (paint_water, paint_pigment, water_buffer, mobile_buffer)
func _create_add_paint_uniform_set():
	if add_paint_uniform_set.is_valid():
		rd.free_rid(add_paint_uniform_set)

	var uniforms := []

	# Binding 0: paint_water (readonly input)
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(paint_water_tex)
	uniforms.append(u0)

	# Binding 1: paint_pigment (readonly input)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(paint_pigment_tex)
	uniforms.append(u1)

	# Binding 2: water_buffer (read+write)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 2
	u2.add_id(water_read_tex)
	uniforms.append(u2)

	# Binding 3: mobile_buffer (read+write)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u3.binding = 3
	u3.add_id(mobile_read_tex)
	uniforms.append(u3)

	add_paint_uniform_set = rd.uniform_set_create(uniforms, add_paint_shader, 0)

# Remove paint shader: 3 bindings (removal_mask, mobile_buffer, static_buffer)
func _create_remove_paint_uniform_set():
	if remove_paint_uniform_set.is_valid():
		rd.free_rid(remove_paint_uniform_set)

	var uniforms := []

	# Binding 0: removal_mask (readonly input)
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(removal_mask_tex)
	uniforms.append(u0)

	# Binding 1: mobile_buffer (read+write)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(mobile_read_tex)
	uniforms.append(u1)

	# Binding 2: static_buffer (read+write)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 2
	u2.add_id(static_read_tex)
	uniforms.append(u2)

	remove_paint_uniform_set = rd.uniform_set_create(uniforms, remove_paint_shader, 0)

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

	# Pack push constants (aligned to 16 bytes)
	var params = PackedFloat32Array([
		delta,
		EVAPORATION_CONST,
		DRY_PIXEL_LIMIT,
		float(canvas_width),
		float(canvas_height),
		0.0,  # padding
		0.0,  # padding
		0.0   # padding (total: 8 floats = 32 bytes)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	# Dispatch
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	# Note: submit/sync not needed with global RenderingDevice

# Dispatch displacement calculation shader
func _dispatch_displacement(groups_x: int, groups_y: int, g_x: float, g_y: float):
	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, displacement_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, displacement_uniform_set, 0)

	# Pack push constants (aligned to 16 bytes)
	var params = PackedFloat32Array([
		g_x,
		g_y,
		S,
		SP,
		HOLD_THRESHOLD,
		ENERGY_LOSS_ON_REDISTRIBUTION,
		DRY_PIXEL_LIMIT,
		float(canvas_width),
		float(canvas_height),
		0.0,  # padding
		0.0,  # padding
		0.0   # padding (total: 12 floats = 48 bytes)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	# Note: submit/sync not needed with global RenderingDevice

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

	# Note: submit/sync not needed with global RenderingDevice

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

	# Note: submit/sync not needed with global RenderingDevice

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

	# Note: submit/sync not needed with global RenderingDevice

# Dispatch add_paint shader
func _dispatch_add_paint(groups_x: int, groups_y: int, pressure: float):
	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, add_paint_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, add_paint_uniform_set, 0)

	# Pack push constants (canvas_width, canvas_height, pressure, padding)
	var params = PackedFloat32Array([
		float(canvas_width),
		float(canvas_height),
		pressure,
		0.0   # padding (total: 4 floats = 16 bytes)
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	# Note: submit/sync not needed with global RenderingDevice

# Dispatch remove_paint shader
func _dispatch_remove_paint(groups_x: int, groups_y: int):
	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, remove_paint_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, remove_paint_uniform_set, 0)

	# Pack push constants (canvas_width, canvas_height, k_absorption, eps_a)
	var params = PackedFloat32Array([
		float(canvas_width),
		float(canvas_height),
		K_ABSORPTION,
		EPS_A
	])
	rd.compute_list_set_push_constant(compute_list, params.to_byte_array(), params.size() * 4)

	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	# Note: submit/sync not needed with global RenderingDevice

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
	_create_add_paint_uniform_set()  # Also uses water_read_tex

func _swap_mobile_textures():
	var temp = mobile_read_tex
	mobile_read_tex = mobile_write_tex
	mobile_write_tex = temp

	# Recreate uniform sets that use mobile textures
	_create_inflow_uniform_set()
	_create_diffusion_uniform_set()
	_create_deposition_uniform_set()
	_create_add_paint_uniform_set()  # Also uses mobile_read_tex
	_create_remove_paint_uniform_set()  # Also uses mobile_read_tex

func _swap_static_textures():
	var temp = static_read_tex
	static_read_tex = static_write_tex
	static_write_tex = temp

	# Recreate uniform set that uses static textures
	_create_deposition_uniform_set()
	_create_remove_paint_uniform_set()  # Also uses static_read_tex

func _swap_inertia_textures():
	var temp = inertia_read_tex
	inertia_read_tex = inertia_write_tex
	inertia_write_tex = temp

	# Recreate uniform set that uses inertia textures
	_create_inflow_uniform_set()

# Upload paint data from CPU to GPU (for brush strokes)
# x, y = top-left corner of the region in canvas space
# water_data, pigment_data = Images containing the region data
func upload_paint_region(x: int, y: int, water_data: Image, pigment_data: Image, pressure: float = 1.0):
	var region_width = water_data.get_width()
	var region_height = water_data.get_height()

	# Convert Images to GPU-compatible byte arrays
	var water_bytes = _image_to_r32f_bytes(water_data)
	var pigment_bytes = _image_to_rgba32f_bytes(pigment_data)

	# Clear paint buffer textures first (fill with zeros)
	var empty_water = PackedFloat32Array()
	empty_water.resize(canvas_width * canvas_height)
	empty_water.fill(0.0)

	var empty_pigment = PackedFloat32Array()
	empty_pigment.resize(canvas_width * canvas_height * 4)
	for i in range(canvas_width * canvas_height):
		empty_pigment[i * 4 + 0] = 1.0  # R
		empty_pigment[i * 4 + 1] = 1.0  # G
		empty_pigment[i * 4 + 2] = 1.0  # B
		empty_pigment[i * 4 + 3] = 0.0  # A (transparent)

	rd.texture_update(paint_water_tex, 0, empty_water.to_byte_array())
	rd.texture_update(paint_pigment_tex, 0, empty_pigment.to_byte_array())

	# Now upload the region data to the correct position
	# We need to copy region data into full-size buffer at correct offset
	var full_water = PackedFloat32Array()
	full_water.resize(canvas_width * canvas_height)
	full_water.fill(0.0)

	var full_pigment = PackedFloat32Array()
	full_pigment.resize(canvas_width * canvas_height * 4)
	for i in range(canvas_width * canvas_height):
		full_pigment[i * 4 + 0] = 1.0
		full_pigment[i * 4 + 1] = 1.0
		full_pigment[i * 4 + 2] = 1.0
		full_pigment[i * 4 + 3] = 0.0

	# Copy region data into full buffer at offset
	for ry in range(region_height):
		for rx in range(region_width):
			var canvas_x = x + rx
			var canvas_y = y + ry

			if canvas_x >= 0 and canvas_x < canvas_width and canvas_y >= 0 and canvas_y < canvas_height:
				var canvas_idx = canvas_y * canvas_width + canvas_x
				var region_idx = ry * region_width + rx

				# Copy water
				var region_water_bytes = water_bytes.slice(region_idx * 4, region_idx * 4 + 4)
				var region_water_value = region_water_bytes.decode_float(0)
				full_water[canvas_idx] = region_water_value

				# Copy pigment (RGBA)
				var pigment_base = region_idx * 16  # 4 floats * 4 bytes each
				full_pigment[canvas_idx * 4 + 0] = pigment_bytes.decode_float(pigment_base + 0)
				full_pigment[canvas_idx * 4 + 1] = pigment_bytes.decode_float(pigment_base + 4)
				full_pigment[canvas_idx * 4 + 2] = pigment_bytes.decode_float(pigment_base + 8)
				full_pigment[canvas_idx * 4 + 3] = pigment_bytes.decode_float(pigment_base + 12)

	# Upload full buffers with region data embedded
	rd.texture_update(paint_water_tex, 0, full_water.to_byte_array())
	rd.texture_update(paint_pigment_tex, 0, full_pigment.to_byte_array())

	# Run add_paint compute shader to add paint to canvas with pressure
	var groups_x = int(ceil(float(canvas_width) / 8.0))
	var groups_y = int(ceil(float(canvas_height) / 8.0))
	_dispatch_add_paint(groups_x, groups_y, pressure)

# Upload removal data from CPU to GPU (for removing brush strokes)
# x, y = top-left corner of the region in canvas space
# removal_data = Image containing the removal mask (how much mass to remove per pixel)
func upload_removal_region(x: int, y: int, removal_data: Image):
	var region_width = removal_data.get_width()
	var region_height = removal_data.get_height()

	# Convert Image to GPU-compatible byte array
	var removal_bytes = _image_to_r32f_bytes(removal_data)

	# Clear removal mask texture first (fill with zeros)
	var empty_removal = PackedFloat32Array()
	empty_removal.resize(canvas_width * canvas_height)
	empty_removal.fill(0.0)

	rd.texture_update(removal_mask_tex, 0, empty_removal.to_byte_array())

	# Now upload the region data to the correct position
	var full_removal = PackedFloat32Array()
	full_removal.resize(canvas_width * canvas_height)
	full_removal.fill(0.0)

	# Copy region data into full buffer at offset
	for ry in range(region_height):
		for rx in range(region_width):
			var canvas_x = x + rx
			var canvas_y = y + ry

			if canvas_x >= 0 and canvas_x < canvas_width and canvas_y >= 0 and canvas_y < canvas_height:
				var canvas_idx = canvas_y * canvas_width + canvas_x
				var region_idx = ry * region_width + rx

				# Copy removal amount
				var region_removal_bytes = removal_bytes.slice(region_idx * 4, region_idx * 4 + 4)
				var region_removal_value = region_removal_bytes.decode_float(0)
				full_removal[canvas_idx] = region_removal_value

	# Upload full buffer with region data embedded
	rd.texture_update(removal_mask_tex, 0, full_removal.to_byte_array())

	# Run remove_paint compute shader
	var groups_x = int(ceil(float(canvas_width) / 8.0))
	var groups_y = int(ceil(float(canvas_height) / 8.0))
	_dispatch_remove_paint(groups_x, groups_y)

# Get texture RIDs for display
func get_water_texture() -> RID:
	return water_read_tex

func get_mobile_texture() -> RID:
	return mobile_read_tex

func get_static_texture() -> RID:
	return static_read_tex

# --- File Manager Helper Methods ---

# Download GPU layer to CPU Image (for exporting)
func download_water_layer() -> Image:
	var img = Image.create(canvas_width, canvas_height, false, Image.FORMAT_RF)
	var bytes = rd.texture_get_data(water_read_tex, 0)
	img.set_data(canvas_width, canvas_height, false, Image.FORMAT_RF, bytes)
	return img

func download_mobile_layer() -> Image:
	var img = Image.create(canvas_width, canvas_height, false, Image.FORMAT_RGBAF)
	var bytes = rd.texture_get_data(mobile_read_tex, 0)
	img.set_data(canvas_width, canvas_height, false, Image.FORMAT_RGBAF, bytes)
	return img

func download_static_layer() -> Image:
	var img = Image.create(canvas_width, canvas_height, false, Image.FORMAT_RGBAF)
	var bytes = rd.texture_get_data(static_read_tex, 0)
	img.set_data(canvas_width, canvas_height, false, Image.FORMAT_RGBAF, bytes)
	return img

# Cleanup
func _exit_tree():
	# Note: When using global RenderingDevice, we should NOT free resources
	# The rendering server owns and manages the global device
	# Freeing resources here causes slow shutdown as the engine waits for GPU sync
	# The rendering server will clean up all resources when the application exits
	pass
