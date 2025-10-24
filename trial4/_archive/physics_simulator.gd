# physics_simulator.gd
extends Node

# --- SIMULATION CONSTANTS ---
# Water related
@export var S: float = 0.10 # Surface tension coefficient
@export var SP: float = 0.50 # Spread force coefficient
@export var canceling_power: float = 0.6747  # How much outflow is reduced when pushing against recent inflow (0.0 .. 1.0)
@export var acceleration_power: float = 0.1536  # How much outflow is increased when pushing with momentum (0.0 .. 1.0)
@export var EVAPORATION_CONST: float = 0.01  # water evaporation rate (0.001 .. 0.05)
@export var HOLD_THRESHOLD: float = 5.0 # The force needed to wet a dry pixel

# Diffusion related
@export var DIFFUSION_RATE: float = 0.1  # pigment diffusion speed (0.01 .. 0.5)
@export var diffusion_limiter: float = 0.25  # max fraction of pigment that can diffuse per neighbor per frame (0.1 .. 0.5)
@export var k_deposit_base: float = 1.0  # overall deposition speed (0.3..3.0)
@export var w_scale: float = 0.2        # water scale (≈ how much water feels "wet"); 0.05 .. 0.3

# Internal variables 
const DRY_PIXEL_LIMIT = 0.0001 # Any water amount below this is considered "dry"
const ENERGY_LOSS_ON_REDISTRIBUTION = 0.3 # How much energy is lost when flow is redirected
const K_ABSORPTION = 0.5 # Higher numbers make the paint more opaque, faster.
const EPS_A = 1e-6 # avoid log(0)



# --- MEMBER VARIABLES TO HOLD REFERENCES TO DATA LAYERS ---
var canvas_width := 0
var canvas_height := 0

var water_read: Image
var water_write: Image
var mobile_read: Image
var mobile_write: Image
var static_read: Image
var static_write: Image
var absorbency_map: Image
var displacement_map: Image
var inertia_read: Image
var inertia_write: Image

# Fine tunning purpose
# A flag to prevent spamming the print statement
var values_changed_this_frame := false
# --- FUNCTION FOR LIVE TUNING ---
func _process(delta: float):
	var change_speed = 0.1 * delta # How fast the values change
	values_changed_this_frame = false
	# --- Controls for Canceling Power ---
	if Input.is_key_pressed(KEY_R):
		canceling_power += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_F):
		canceling_power -= change_speed
		values_changed_this_frame = true
	# --- Controls for Acceleration Power ---
	if Input.is_key_pressed(KEY_T):
		acceleration_power += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_G):
		acceleration_power -= change_speed
		values_changed_this_frame = true

	# Clamp momentum powers to 0-1 range
	canceling_power = clamp(canceling_power, 0.0, 1.0)
	acceleration_power = clamp(acceleration_power, 0.0, 1.0)

	# Print the new values to the console only if they changed
	if values_changed_this_frame:
		print("Canceling Power: %.4f | Acceleration Power: %.4f" % [canceling_power, acceleration_power])


func init(p_width: int, p_height: int, p_water_read: Image, p_mobile_read: Image, p_water_write: Image,
		  p_mobile_write: Image, p_static_read: Image, p_static_write: Image, p_absorbency: Image, p_displacement: Image,
		  p_inertia_read: Image, p_inertia_write: Image):
	canvas_width = p_width
	canvas_height = p_height

	water_read = p_water_read
	water_write = p_water_write
	mobile_read = p_mobile_read
	mobile_write = p_mobile_write
	static_read = p_static_read
	static_write = p_static_write
	absorbency_map = p_absorbency
	displacement_map = p_displacement
	inertia_read = p_inertia_read
	inertia_write = p_inertia_write

func run_simulation_step(delta: float, g_x: float, g_y: float):
	# step 1, evaporation on the water layer
	_simulate_evaporation(delta)
	_swap_water_buffers()

	# step 2, water fluid simulation considering gravity, surface tension and spreading force
	_calculate_water_displacement_4_dir_redistribution(g_x, g_y)

	# step 3, execute water movement based on step 3 information as well as pigment carried with the water.
	# This also records inflow information into inertia_write
	_apply_water_displacement_with_pigment_inflow(delta)

	_swap_water_buffers()
	_swap_mobile_buffers()
	_swap_inertia_buffers()  # Swap inertia after recording inflows

	# step 4, surface diffusion on the mobile layer (happens before deposition)
	_simulate_diffusion(delta) # pigment diffuses on the wet surface based on contact area
	_swap_mobile_buffers()

	# step 5, the mobile layer pigment goes down to the static layer to set a concrete image.
	_simulate_deposition(delta) # mobile_image -> static_image

	_swap_mobile_buffers()
	_swap_static_buffers()

# --- PRIVATE SIMULATION FUNCTIONS ---
# This functions is used in run_simulation_step to swap read, write buffers after physics calculation
func _swap_water_buffers():
	var temp_water = water_read
	water_read = water_write
	water_write = temp_water

func _swap_mobile_buffers():
	var temp_mobile = mobile_read
	mobile_read = mobile_write
	mobile_write = temp_mobile

func _swap_static_buffers():
	var temp_static = static_read
	static_read = static_write
	static_write = temp_static

func _swap_inertia_buffers():
	var temp_inertia = inertia_read
	inertia_read = inertia_write
	inertia_write = temp_inertia

# Calculate water displacement in regards to gravity, surface tension and spreading force
func _calculate_water_displacement_4_dir_redistribution(g_x: float, g_y: float):
# Acceleration in x direction
	for y in range(canvas_height):
		for x in range(canvas_width):
			var water_amount = water_read.get_pixel(x,y).r
			# Horizontal Force Calculation
			var gravity_force_x = water_amount * g_x
			var left_sum = 0.0
			var right_sum = 0.0
			var count = 0
			
			# Left side
			for i in range(1,11):
				if x-i >= 0 :
					var amount = water_read.get_pixel(x-i,y).r
					if amount <= DRY_PIXEL_LIMIT : break
					left_sum += amount
					count += 1
			if count > 0: left_sum /= count
			
			# Right side
			count = 0
			for i in range(1,11):
				if x+i < canvas_width:
					var amount = water_read.get_pixel(x+i,y).r
					if amount <= DRY_PIXEL_LIMIT : break
					right_sum += amount
					count += 1
			if count > 0 : right_sum /= count
			
			var surface_tension_force_x = S * (right_sum - left_sum)
		
			# 3. Spreading Force Component
			var left_neighbor = 0.0
			var right_neighbor = 0.0
			if x-1 >= 0 :left_neighbor = water_read.get_pixel(x-1,y).r
			if x+1 < canvas_width : right_neighbor = water_read.get_pixel(x+1,y).r
			
			var spread_force_r = SP * (water_amount - right_neighbor)
			var spread_force_l = SP * (water_amount - left_neighbor)

			# 4. Overall Force in x direction
			var horizontal_net_force = gravity_force_x + surface_tension_force_x
			var total_force_r = max(0, horizontal_net_force) + spread_force_r
			var total_force_l = max(0, -horizontal_net_force) + spread_force_l
			
			# Vertical Force Calculation
			var gravity_force_y = water_amount * g_y
			var up_sum = 0.0
			var down_sum = 0.0
			count = 0
			
			# Up side
			for i in range(1,11):
				if y-i >= 0 :
					var amount = water_read.get_pixel(x,y-i).r
					if amount < DRY_PIXEL_LIMIT : break
					up_sum += amount
					count += 1
			if count > 0: up_sum /= count
			
			# Down side
			count = 0
			for i in range(1,11):
				if y+i < canvas_height:
					var amount = water_read.get_pixel(x,y+i).r
					if amount < DRY_PIXEL_LIMIT : break
					down_sum += amount
					count += 1
			if count > 0 : down_sum /= count
			
			var surface_tension_force_y = S * (down_sum - up_sum)
			
			# 3. Spreading Force Component
			var up_neighbor = 0.0
			var down_neighbor = 0.0
			if y-1 >= 0 :up_neighbor = water_read.get_pixel(x,y-1).r
			if y+1 < canvas_height : down_neighbor = water_read.get_pixel(x,y+1).r
			
			var spread_force_u = SP * (water_amount - up_neighbor)
			var spread_force_d = SP * (water_amount - down_neighbor)


			# 4. Overall Force in x direction
			var vertical_net_force = gravity_force_y + surface_tension_force_y
			var total_force_d = max(0, vertical_net_force) + spread_force_d
			var total_force_u = max(0, -vertical_net_force) + spread_force_u
			
			# 5. Redistribution logic (when path is blocked by dry pixels)
			var total_original_force = total_force_r + total_force_l + total_force_d + total_force_u

			# Create copies to modify
			var final_r = total_force_r
			var final_l = total_force_l
			var final_d = total_force_d
			var final_u = total_force_u

			# Nullify blocked paths
			if x < canvas_width - 1 and water_read.get_pixel(x + 1, y).r < DRY_PIXEL_LIMIT and total_force_r < HOLD_THRESHOLD: final_r = 0.0
			if x > 0 and water_read.get_pixel(x - 1, y).r < DRY_PIXEL_LIMIT and total_force_l < HOLD_THRESHOLD: final_l = 0.0
			if y < canvas_height - 1 and water_read.get_pixel(x, y + 1).r < DRY_PIXEL_LIMIT and total_force_d < HOLD_THRESHOLD: final_d = 0.0
			if y > 0 and water_read.get_pixel(x, y - 1).r < DRY_PIXEL_LIMIT and total_force_u < HOLD_THRESHOLD: final_u = 0.0

			var total_available_force = final_r + final_l + final_d + final_u

			if total_available_force > 0.0 and total_original_force > total_available_force:
				# Calculate the amplification, scaled by the artistic constant
				var amplification = 1.0 + ((total_original_force / total_available_force) - 1.0) * ENERGY_LOSS_ON_REDISTRIBUTION
				
				final_r *= amplification
				final_l *= amplification
				final_d *= amplification
				final_u *= amplification
				
			# Store x,y directional force
			displacement_map.set_pixel(x, y, Color(final_r, final_l, final_d, final_u))


# GPU implementation ready approach (still running on CPU)
func _apply_water_displacement_with_pigment_inflow(delta: float):
	water_write.fill(Color(0,0,0,0))
	mobile_write.fill(Color(1,1,1,0))
	inertia_write.fill(Color(0,0,0,0))  # Clear inertia memory for this frame

	for y in range(canvas_height):
		for x in range(canvas_width):
			# --- PART 1: compute my outflow and what stays at source ---
			var water_at_source = water_read.get_pixel(x, y).r
			var pigment_at_source = mobile_read.get_pixel(x, y)
			var capacity_at_source = absorbency_map.get_pixel(x, y).r
			var movable_water_at_source = max(0.0, water_at_source - capacity_at_source)

			# Get scaled outflows using the helper function (avoiding code duplication)
			var outflows_here = _final_outflows_at_with_inertia(x, y, delta)
			var total_outflow_wanted = outflows_here.x + outflows_here.y + outflows_here.z + outflows_here.w

			var water_staying_at_source = water_at_source - total_outflow_wanted

			# pigment partition (absorbed vs movable) and what stays after outflow
			var mass_staying_at_source = 0.0
			var pigment_mass_at_source = PigmentMixer._alpha_to_mass(pigment_at_source.a)

			if water_at_source > 1e-6 and pigment_mass_at_source > 0.0:
				var movable_mass_fraction = movable_water_at_source / water_at_source
				var movable_pigment_mass_at_source = pigment_mass_at_source * movable_mass_fraction
				var absorbed_pigment_mass_at_source = pigment_mass_at_source - movable_pigment_mass_at_source

				var outflow_fraction_of_movable = 0.0
				if movable_water_at_source > EPS_A:
					outflow_fraction_of_movable = total_outflow_wanted / movable_water_at_source

				var pigment_mass_that_flows_out = movable_pigment_mass_at_source * outflow_fraction_of_movable
				mass_staying_at_source = (movable_pigment_mass_at_source - pigment_mass_that_flows_out) + absorbed_pigment_mass_at_source
			else:
				mass_staying_at_source = pigment_mass_at_source

			var pigment_staying_color = Color(
				pigment_at_source.r,
				pigment_at_source.g,
				pigment_at_source.b,
				PigmentMixer._mass_to_alpha(mass_staying_at_source)
			)

			# --- PART 2: gather inflow from neighbors (use helper to get their final outflows) ---
			var total_inflow_water = 0.0
			var inflow_pigment_accum = Color(1, 1, 1, 0) # mass-preserving mix accumulator

			# Initialize inertia accumulator for this pixel (will record inflows from 4 directions)
			var inflow_from_right = 0.0
			var inflow_from_left = 0.0
			var inflow_from_down = 0.0
			var inflow_from_up = 0.0

			# from LEFT neighbor -> their RIGHT outflow lands here
			if x > 0:
				var neighbor_flows = _final_outflows_at_with_inertia(x - 1, y, delta)
				var water_in_from_left = neighbor_flows.x
				if water_in_from_left > 0.0:
					total_inflow_water += water_in_from_left
					inflow_from_left = water_in_from_left  # Record for inertia memory

					var neighbor_water = water_read.get_pixel(x - 1, y).r
					var neighbor_capacity = absorbency_map.get_pixel(x - 1, y).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x - 1, y)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_left / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)

			# from RIGHT neighbor -> their LEFT outflow lands here
			if x < canvas_width - 1:
				var neighbor_flows = _final_outflows_at_with_inertia(x + 1, y, delta)
				var water_in_from_right = neighbor_flows.y
				if water_in_from_right > 0.0:
					total_inflow_water += water_in_from_right
					inflow_from_right = water_in_from_right  # Record for inertia memory

					var neighbor_water = water_read.get_pixel(x + 1, y).r
					var neighbor_capacity = absorbency_map.get_pixel(x + 1, y).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x + 1, y)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_right / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)

			# from UP neighbor -> their DOWN outflow lands here
			if y > 0:
				var neighbor_flows = _final_outflows_at_with_inertia(x, y - 1, delta)
				var water_in_from_up = neighbor_flows.z
				if water_in_from_up > 0.0:
					total_inflow_water += water_in_from_up
					inflow_from_up = water_in_from_up  # Record for inertia memory

					var neighbor_water = water_read.get_pixel(x, y - 1).r
					var neighbor_capacity = absorbency_map.get_pixel(x, y - 1).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x, y - 1)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_up / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)

			# from DOWN neighbor -> their UP outflow lands here
			if y < canvas_height - 1:
				var neighbor_flows = _final_outflows_at_with_inertia(x, y + 1, delta)
				var water_in_from_down = neighbor_flows.w
				if water_in_from_down > 0.0:
					total_inflow_water += water_in_from_down
					inflow_from_down = water_in_from_down  # Record for inertia memory

					var neighbor_water = water_read.get_pixel(x, y + 1).r
					var neighbor_capacity = absorbency_map.get_pixel(x, y + 1).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x, y + 1)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_down / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)

			# --- PART 3: finalize this pixel ---
			var final_water_at_pixel = water_staying_at_source + total_inflow_water
			var final_pigment_at_pixel = PigmentMixer._mix_pigments_optical(pigment_staying_color, inflow_pigment_accum)

			water_write.set_pixel(x, y, Color(final_water_at_pixel, 0, 0))
			mobile_write.set_pixel(x, y, final_pigment_at_pixel)

			# Write inertia memory for this pixel (RGBA = inflows from right, left, down, up)
			inertia_write.set_pixel(x, y, Color(inflow_from_right, inflow_from_left, inflow_from_down, inflow_from_up))


# --- HELPER FUNCTIONS ---
# Computes a neighbor pixel's FINAL, SCALED directional outflows (right, left, down, up).
# Returns a Vector4: (outflow_right, outflow_left, outflow_down, outflow_up).
func _final_outflows_at(neighbor_x: int, neighbor_y: int, delta: float) -> Vector4:
	if neighbor_x < 0 or neighbor_x >= canvas_width or neighbor_y < 0 or neighbor_y >= canvas_height:
		return Vector4(0, 0, 0, 0)

	var water_at_neighbor = water_read.get_pixel(neighbor_x, neighbor_y).r
	if water_at_neighbor <= DRY_PIXEL_LIMIT:
		return Vector4(0, 0, 0, 0)

	var capacity_at_neighbor = absorbency_map.get_pixel(neighbor_x, neighbor_y).r
	var movable_water_at_neighbor = max(0.0, water_at_neighbor - capacity_at_neighbor)
	if movable_water_at_neighbor <= DRY_PIXEL_LIMIT:
		return Vector4(0, 0, 0, 0)

	var displacement_at_neighbor = displacement_map.get_pixel(neighbor_x, neighbor_y)

	var outflow_right_wanted = max(0.0, displacement_at_neighbor.r) * movable_water_at_neighbor * delta
	var outflow_left_wanted  = max(0.0, displacement_at_neighbor.g) * movable_water_at_neighbor * delta
	var outflow_down_wanted  = max(0.0, displacement_at_neighbor.b) * movable_water_at_neighbor * delta
	var outflow_up_wanted    = max(0.0, displacement_at_neighbor.a) * movable_water_at_neighbor * delta

	var total_outflow_wanted = outflow_right_wanted + outflow_left_wanted + outflow_down_wanted + outflow_up_wanted
	if total_outflow_wanted > movable_water_at_neighbor and total_outflow_wanted > 0.0:
		var scale_factor = movable_water_at_neighbor / total_outflow_wanted
		outflow_right_wanted *= scale_factor
		outflow_left_wanted  *= scale_factor
		outflow_down_wanted  *= scale_factor
		outflow_up_wanted    *= scale_factor

	return Vector4(outflow_right_wanted, outflow_left_wanted, outflow_down_wanted, outflow_up_wanted)


# Computes a neighbor pixel's FINAL, SCALED directional outflows WITH MOMENTUM DAMPENING.
# This version applies inertia memory to reduce oscillation by dampening outflows that push
# against recent inflows (and optionally boosting flows that align with momentum).
# Returns a Vector4: (outflow_right, outflow_left, outflow_down, outflow_up).
#
# Uses inertia_read buffer where RGBA stores (inflow_from_right, inflow_from_left, inflow_from_down, inflow_from_up)
# from the previous frame. These represent how much water this pixel RECEIVED from each direction.
func _final_outflows_at_with_inertia(neighbor_x: int, neighbor_y: int, delta: float) -> Vector4:
	if neighbor_x < 0 or neighbor_x >= canvas_width or neighbor_y < 0 or neighbor_y >= canvas_height:
		return Vector4(0, 0, 0, 0)

	var water_at_neighbor = water_read.get_pixel(neighbor_x, neighbor_y).r
	if water_at_neighbor <= DRY_PIXEL_LIMIT:
		return Vector4(0, 0, 0, 0)

	var capacity_at_neighbor = absorbency_map.get_pixel(neighbor_x, neighbor_y).r
	var movable_water_at_neighbor = max(0.0, water_at_neighbor - capacity_at_neighbor)
	if movable_water_at_neighbor <= DRY_PIXEL_LIMIT:
		return Vector4(0, 0, 0, 0)

	# Calculate raw outflows from displacement forces (BEFORE scaling)
	var displacement_at_neighbor = displacement_map.get_pixel(neighbor_x, neighbor_y)

	var outflow_right_wanted = max(0.0, displacement_at_neighbor.r) * movable_water_at_neighbor * delta
	var outflow_left_wanted  = max(0.0, displacement_at_neighbor.g) * movable_water_at_neighbor * delta
	var outflow_down_wanted  = max(0.0, displacement_at_neighbor.b) * movable_water_at_neighbor * delta
	var outflow_up_wanted    = max(0.0, displacement_at_neighbor.a) * movable_water_at_neighbor * delta

	# --- APPLY MOMENTUM DAMPENING (before conservation scaling) ---
	# Read inertia memory: how much water this pixel received from each direction last frame
	var inertia_here = inertia_read.get_pixel(neighbor_x, neighbor_y)
	var inflow_from_right = inertia_here.r  # Water received from the right (flowing leftward into this pixel)
	var inflow_from_left = inertia_here.g   # Water received from the left (flowing rightward into this pixel)
	var inflow_from_down = inertia_here.b   # Water received from below (flowing upward into this pixel)
	var inflow_from_up = inertia_here.a     # Water received from above (flowing downward into this pixel)

	# Apply canceling: If trying to push water RIGHT, but recently received water FROM the right, dampen it
	if inflow_from_right > 0.0:
		var cancel_amount = min(outflow_right_wanted, inflow_from_right) * canceling_power
		outflow_right_wanted -= cancel_amount
	elif acceleration_power > 0.0 and inflow_from_left > 0.0:
		# Boost rightward flow if we have leftward momentum (received from left)
		var boost_amount = min(outflow_right_wanted, inflow_from_left) * acceleration_power
		outflow_right_wanted += boost_amount

	# Apply canceling for LEFT outflow vs inflow from left
	if inflow_from_left > 0.0:
		var cancel_amount = min(outflow_left_wanted, inflow_from_left) * canceling_power
		outflow_left_wanted -= cancel_amount
	elif acceleration_power > 0.0 and inflow_from_right > 0.0:
		# Boost leftward flow if we have rightward momentum (received from right)
		var boost_amount = min(outflow_left_wanted, inflow_from_right) * acceleration_power
		outflow_left_wanted += boost_amount

	# Apply canceling for DOWN outflow vs inflow from down
	if inflow_from_down > 0.0:
		var cancel_amount = min(outflow_down_wanted, inflow_from_down) * canceling_power
		outflow_down_wanted -= cancel_amount
	elif acceleration_power > 0.0 and inflow_from_up > 0.0:
		# Boost downward flow if we have upward momentum (received from up)
		var boost_amount = min(outflow_down_wanted, inflow_from_up) * acceleration_power
		outflow_down_wanted += boost_amount

	# Apply canceling for UP outflow vs inflow from up
	if inflow_from_up > 0.0:
		var cancel_amount = min(outflow_up_wanted, inflow_from_up) * canceling_power
		outflow_up_wanted -= cancel_amount
	elif acceleration_power > 0.0 and inflow_from_down > 0.0:
		# Boost upward flow if we have downward momentum (received from down)
		var boost_amount = min(outflow_up_wanted, inflow_from_down) * acceleration_power
		outflow_up_wanted += boost_amount

	# --- APPLY CONSERVATION SCALING (after momentum dampening) ---
	# Now scale down proportionally if total outflow exceeds available movable water
	var total_outflow_wanted = outflow_right_wanted + outflow_left_wanted + outflow_down_wanted + outflow_up_wanted
	if total_outflow_wanted > movable_water_at_neighbor and total_outflow_wanted > 0.0:
		var scale_factor = movable_water_at_neighbor / total_outflow_wanted
		outflow_right_wanted *= scale_factor
		outflow_left_wanted  *= scale_factor
		outflow_down_wanted  *= scale_factor
		outflow_up_wanted    *= scale_factor

	return Vector4(outflow_right_wanted, outflow_left_wanted, outflow_down_wanted, outflow_up_wanted)


# This function will handle water evaporating from the canvas over time.
func _simulate_evaporation(delta: float):
	for y in range(canvas_height):
		for x in range(canvas_width):
			var current_water_here = water_read.get_pixel(x,y).r
			var water_right = 0.0
			var water_left = 0.0
			var water_up = 0.0
			var water_down = 0.0
			if x < canvas_width - 1 : water_right = water_read.get_pixel(x+1,y).r
			if x > 0 : water_left = water_read.get_pixel(x-1,y).r
			if y > 0 : water_up = water_read.get_pixel(x,y-1).r
			if y < canvas_height - 1 : water_down = water_read.get_pixel(x,y+1).r
			var total_surface = 0.1 # default value
			var differences = []
			differences.append(current_water_here - water_right)
			differences.append(current_water_here - water_left)
			differences.append(current_water_here - water_up)
			differences.append(current_water_here - water_down)
			for area in differences:
				if area > 0.0 : total_surface += area
			var evaporation_amount = total_surface * EVAPORATION_CONST * delta
			var new_water = max(0.0, current_water_here - evaporation_amount)
			water_write.set_pixel(x, y, Color(new_water, 0, 0))


# This function will handle the spreading of mobile pigment based on contact area (water amount).
# Diffusion happens only on the mobile (surface) layer, driven by pigment concentration gradients
# and limited by the available water "contact area" between adjacent pixels.
# Uses INFLOW MODEL: each pixel gathers pigment from neighbors (GPU-parallelizable)
func _simulate_diffusion(delta: float):
	# Copy current state to write buffer first (CPU cache-friendly)
	mobile_write.blit_rect(mobile_read, Rect2i(0, 0, canvas_width, canvas_height), Vector2i(0, 0))

	# Diffusion coefficient - controls overall diffusion speed
	var D_base = DIFFUSION_RATE * delta

	# INFLOW MODEL: Each pixel computes its final state by gathering from neighbors
	# Only reads from mobile_read, only writes to mobile_write
	for y in range(canvas_height):
		for x in range(canvas_width):
			var water_here = water_read.get_pixel(x, y).r
			var pigment_here = mobile_read.get_pixel(x, y)
			var mass_here = PigmentMixer._alpha_to_mass(pigment_here.a)

			# Skip diffusion if this pixel is dry
			if water_here < DRY_PIXEL_LIMIT:
				continue

			# Start with what's already at this pixel
			var final_mass = mass_here
			var final_hue = Color(pigment_here.r, pigment_here.g, pigment_here.b, 1.0)

			# Calculate net inflow/outflow with each of the 4 neighbors
			var neighbors = [
				{"dx": 1, "dy": 0},   # right
				{"dx": -1, "dy": 0},  # left
				{"dx": 0, "dy": 1},   # down
				{"dx": 0, "dy": -1}   # up
			]

			for neighbor in neighbors:
				var nx = x + neighbor.dx
				var ny = y + neighbor.dy

				# Bounds check
				if nx < 0 or nx >= canvas_width or ny < 0 or ny >= canvas_height:
					continue

				var water_neighbor = water_read.get_pixel(nx, ny).r
				var pigment_neighbor = mobile_read.get_pixel(nx, ny)
				var mass_neighbor = PigmentMixer._alpha_to_mass(pigment_neighbor.a)

				# Contact area: use minimum of the two water amounts
				var contact_area = min(water_here, water_neighbor)

				# Skip if contact area is too small (dry boundary)
				if contact_area < DRY_PIXEL_LIMIT:
					continue

				# Calculate mass gradient: positive means neighbor has MORE pigment than here
				# So pigment flows FROM neighbor TO here (inflow to this pixel)
				var mass_gradient = mass_neighbor - mass_here
				var flux = D_base * contact_area * mass_gradient

				# Clamp flux using adjustable diffusion_limiter
				if flux > 0.0:
					# Inflow: pigment coming from neighbor to here
					flux = min(flux, mass_neighbor * diffusion_limiter)

					# Mix incoming pigment with what we already have
					var hue_neighbor = Color(pigment_neighbor.r, pigment_neighbor.g, pigment_neighbor.b, 1.0)
					var incoming_pigment = Color(hue_neighbor.r, hue_neighbor.g, hue_neighbor.b, PigmentMixer._mass_to_alpha(flux))
					var current_accumulated = Color(final_hue.r, final_hue.g, final_hue.b, PigmentMixer._mass_to_alpha(final_mass))

					current_accumulated = PigmentMixer._mix_pigments_optical(incoming_pigment, current_accumulated)
					final_mass = PigmentMixer._alpha_to_mass(current_accumulated.a)
					final_hue = Color(current_accumulated.r, current_accumulated.g, current_accumulated.b, 1.0)
				elif flux < 0.0:
					# Outflow: pigment leaving from here to neighbor
					# Subtract the mass that left (clamped by diffusion_limiter)
					var outflow = min(abs(flux), mass_here * diffusion_limiter)
					final_mass -= outflow
					final_mass = max(0.0, final_mass)

			# Write final result for this pixel (only if diffusion occurred)
			if abs(final_mass - mass_here) > 1e-8:
				var final_pigment = Color(final_hue.r, final_hue.g, final_hue.b, PigmentMixer._mass_to_alpha(final_mass))
				mobile_write.set_pixel(x, y, final_pigment)



# This function will handle wet pigment getting "stuck" to the paper and becoming dry.
func _simulate_deposition(delta: float) -> void:
	# --- start from current buffers ---
	mobile_write.blit_rect(mobile_read, Rect2i(0, 0, canvas_width, canvas_height), Vector2i(0, 0))
	static_write.blit_rect(static_read, Rect2i(0, 0, canvas_width, canvas_height), Vector2i(0, 0))

	for y in range(canvas_height):
		for x in range(canvas_width):
			var water_here = water_read.get_pixel(x, y).r
			var absorbency = absorbency_map.get_pixel(x, y).r

			var mobile_color = mobile_read.get_pixel(x, y)
			var mobile_mass = PigmentMixer._alpha_to_mass(mobile_color.a)
			if mobile_mass <= 0.0:
				continue  # nothing to deposit here

			# If essentially dry, lock everything immediately (snap to paper).
			if water_here < DRY_PIXEL_LIMIT:
				var hue = Color(mobile_color.r, mobile_color.g, mobile_color.b, 1.0)
				var deposit_color = Color(hue.r, hue.g, hue.b, PigmentMixer._mass_to_alpha(mobile_mass))
				var static_here = static_read.get_pixel(x, y)
				static_write.set_pixel(x, y, PigmentMixer._mix_pigments_optical(deposit_color, static_here))

				# Clear mobile at this pixel (all mass moved).
				mobile_write.set_pixel(x, y, Color(1, 1, 1, 0.0))
				continue

			# --- Wet deposition (rate depends on water + absorbency) ---
			# Use squared water_factor to make deposition much slower when there's lots of water
			# This keeps pigments mobile longer, allowing more time for diffusion and flow
			var water_factor = w_scale / (water_here + w_scale)
			water_factor = water_factor * water_factor  # Square it for stronger suppression
			var rate = k_deposit_base * max(0.0, absorbency) * water_factor

			var deposit_fraction = 1.0 - exp(-rate * delta)
			deposit_fraction = clamp(deposit_fraction, 0.0, 1.0)

			var deposit_mass = mobile_mass * deposit_fraction
			if deposit_mass <= 0.0:
				# Nothing significant moves; mobile already copied above, static already copied above.
				# Keep mobile as-is at this pixel for this frame:
				continue

			var remaining_mass = max(0.0, mobile_mass - deposit_mass) # clamp to avoid -0.0

			# Preserve hue: move mass with the same RGB “fingerprint”.
			var hue = Color(mobile_color.r, mobile_color.g, mobile_color.b, 1.0)
			var deposit_color = Color(hue.r, hue.g, hue.b, PigmentMixer._mass_to_alpha(deposit_mass))
			var remaining_color = Color(hue.r, hue.g, hue.b, PigmentMixer._mass_to_alpha(remaining_mass))

			# Add to static using optical mixing (mass-aware), and write back mobile remainder.
			var static_here = static_read.get_pixel(x, y)
			static_write.set_pixel(x, y, PigmentMixer._mix_pigments_optical(deposit_color, static_here))
			mobile_write.set_pixel(x, y, remaining_color)
