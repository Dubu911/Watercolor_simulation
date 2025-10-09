# physics_simulator.gd
extends Node

# --- SIMULATION CONSTANTS ---
const DIFFUSION_RATE = 0.1
const EVAPORATION_CONST = 0.01
#const S = 0.5 # Surface tension coefficient
#const SP = 1.3 # Spread force coefficient
@export var S: float = 0.10 # Surface tension coefficient
@export var SP: float = 0.50 # Spread force coefficient
@export var HOLD_THRESHOLD = 5.0 # The force needed to wet a dry pixel
const DRY_PIXEL_LIMIT = 0.0001 # Any water amount below this is considered "dry"
const ENERGY_LOSS_ON_REDISTRIBUTION = 0.5 # How much energy is lost when flow is redirected
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

# Fine tunning purpose
# A flag to prevent spamming the print statement
var values_changed_this_frame := false
# --- FUNCTION FOR LIVE TUNING ---
func _process(delta: float):
	var change_speed = 0.01 * delta # How fast the values change
	values_changed_this_frame = false
	# --- Controls for Surface Tension (S) ---
	if Input.is_key_pressed(KEY_R):
		S += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_F):
		S -= change_speed
		values_changed_this_frame = true
	# --- Controls for Spreading Force (SP) ---
	if Input.is_key_pressed(KEY_T):
		SP += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_G):
		SP -= change_speed
		values_changed_this_frame = true
		
	# Ensure values don't go below zero
	S = max(0.0, S)
	SP = max(0.0, SP)

	# Print the new values to the console only if they changed
	if values_changed_this_frame:
		print("Surface Tension (S): %.4f | Spreading Force (SP): %.4f" % [S, SP])


func init(p_width: int, p_height: int, p_water_read: Image, p_mobile_read: Image, p_water_write: Image,  
		  p_mobile_write: Image, p_static_read: Image, p_static_write: Image, p_absorbency: Image, p_displacement: Image):
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
	
func run_simulation_step(delta: float, g_x: float, g_y: float):
	# step 1, evaporation on the water layer
	_simulate_evaporation(delta)
	_swap_water_buffers()
	
	# step 2, diffusion in the static layer. This is independent from water movement, about pigment movement
	#_simulate_diffusion(delta) # pigments in mstatic_image diffusses
	
	# step 3, water fluid simulation considering gravity, surface tension and spreading force
	#_calculate_water_displacement(g_x, g_y)
	#_calculate_water_displacement_4_directional(g_x, g_y)
	_calculate_water_displacement_4_dir_redistribution(g_x, g_y)
	
	# step 4, execute water movement based on step 3 information as well as pigment carried with the water.
	#_apply_water_displacement(delta)
	#_apply_water_displacement_with_pigment(delta)
	_apply_water_displacement_with_pigment_inflow(delta)

	# step 5, the mobile layer pigment goes down to the static layer to set a concrete image.
	# _simulate_deposition(delta) # mobile_image -> static_image
	
	_swap_water_buffers()
	_swap_mobile_buffers()	
	

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


# This function calculates force acting on water due to gravity, surface tention and spreading force.
# This function is directly from David Small's paper.
func _calculate_water_displacement(g_x: float, g_y: float):
	# Acceleration in x direction
	for y in range(canvas_height):
		for x in range(canvas_width):
			# Horizontal Force Calculation
			var water_amount = water_read.get_pixel(x,y).r
			# 1. Gravity Force Component
			var gravity_force_x = water_amount * g_x
			
			# 2. Surface Tension Force Component
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
			
			var spread_force_x = SP * (left_neighbor - right_neighbor)
			
			# 4. Overall Force in x direction
			var Dx = gravity_force_x + surface_tension_force_x + spread_force_x
			
			# Vertical Force Calculation
			# 1. Gravity Force Component
			var gravity_force_y = water_amount * g_y
			
			# . 2Surface Tension Force Component
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

			#var difference = abs(left_neighbor-right_neighbor)
			#if difference < 0.01 : difference = 0.0
			var spread_force_y = SP * (up_neighbor - down_neighbor)
			
			# 4. Overall Force in x direction
			var Dy = gravity_force_y + surface_tension_force_y + spread_force_y
			
			# Store x,y directional force
			displacement_map.set_pixel(x, y, Color(Dx, Dy, 0))
			
# This function is an improved version. It calculates 4 directions. It solves checker board pattern problem I had from
# David Small's paper implementation.
func _calculate_water_displacement_4_directional(g_x: float, g_y: float):
	# Acceleration in x direction
	for y in range(canvas_height):
		for x in range(canvas_width):
			# Horizontal Force Calculation
			var water_amount = water_read.get_pixel(x,y).r
			# 1. Gravity Force Component
			var gravity_force_x = water_amount * g_x
			
			# . 2Surface Tension Force Component
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
			# 1. Gravity Force Component
			var gravity_force_y = water_amount * g_y
			
			# . 2Surface Tension Force Component
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
			
			# Store x,y directional force
			displacement_map.set_pixel(x, y, Color(total_force_r, total_force_l, total_force_d, total_force_u))

# Improved version to make it GPU friendly and considers redistribution of water by blocked paths
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

# Move the water according to calculated forces.(outflow model)
func _apply_water_displacement(delta: float):
	# copy the current state to the write buffer.
	water_write.fill(Color(0,0,0,0))
	mobile_write.blit_rect(mobile_read, Rect2i(0, 0, canvas_width, canvas_height), Vector2i(0, 0))

	
	# Now, iterate and apply transfers between pixels.
	for y in range(canvas_height):
		for x in range(canvas_width):
			var total_here = water_read.get_pixel(x,y).r
			var capacity = absorbency_map.get_pixel(x,y).r  # 0.0 if unused
			var movable_water = max(0.0, total_here - capacity)
			
			if movable_water < DRY_PIXEL_LIMIT:
				var possible_inflow = water_write.get_pixel(x,y).r
				water_write.set_pixel(x,y, Color(total_here + possible_inflow, 0, 0))
				continue

			# force field from previous stage
			var F = displacement_map.get_pixel(x,y)
			var want_r = max(0.0, F.r) * movable_water * delta
			var want_l = max(0.0, F.g) * movable_water * delta
			var want_d = max(0.0, F.b) * movable_water * delta
			var want_u = max(0.0, F.a) * movable_water * delta
			
			var directions = [["right",want_r],["left",want_l],["down",want_d], ["up",want_u]]
			directions.sort_custom(func(a, b): return a[1] > b[1])
			
			var passed_water = 0.0
			for dir_info in directions:
				var key = dir_info[0]
				var value = dir_info[1]
				match key:
					"right":
						want_r += passed_water
						if x < canvas_width - 1 and water_read.get_pixel(x+1,y).r < DRY_PIXEL_LIMIT and want_r < HOLD_THRESHOLD:
							passed_water = want_r * ENERGY_LOSS_ON_REDISTRIBUTION; want_r = 0.0
						else: passed_water = 0.0
					"left":
						want_l += passed_water
						if x > 0 and water_read.get_pixel(x-1,y).r < DRY_PIXEL_LIMIT and want_l < HOLD_THRESHOLD:
							passed_water = want_l * ENERGY_LOSS_ON_REDISTRIBUTION; want_l = 0.0
						else: passed_water = 0.0
					"up":
						want_u += passed_water
						if y > 0 and water_read.get_pixel(x,y-1).r < DRY_PIXEL_LIMIT and want_u < HOLD_THRESHOLD:
							passed_water = want_u * ENERGY_LOSS_ON_REDISTRIBUTION; want_u = 0.0
						else: passed_water = 0.0
					"down":
						want_d += passed_water
						if y < canvas_height - 1 and water_read.get_pixel(x,y+1).r < DRY_PIXEL_LIMIT and want_d < HOLD_THRESHOLD:
							passed_water = want_d * ENERGY_LOSS_ON_REDISTRIBUTION; want_d = 0.0
						else: passed_water = 0.0
			
			var total_outflow = want_r + want_l + want_d + want_u
			if total_outflow > movable_water:
				var scaling_factor = movable_water / total_outflow
				want_r *= scaling_factor
				want_l *= scaling_factor
				want_d *= scaling_factor
				want_u *= scaling_factor
				total_outflow = movable_water # The total is now exactly the movable amount
				
			# Add the outflow amounts to the neighbors in the write buffer
			if want_r > 0.0:
				var neighbor_val = water_write.get_pixel(x + 1, y).r
				water_write.set_pixel(x + 1, y, Color(neighbor_val + want_r, 0, 0))
			if want_l > 0.0:
				var neighbor_val = water_write.get_pixel(x - 1, y).r
				water_write.set_pixel(x - 1, y, Color(neighbor_val + want_l, 0, 0))
			if want_d > 0.0:
				var neighbor_val = water_write.get_pixel(x, y + 1).r
				water_write.set_pixel(x, y + 1, Color(neighbor_val + want_d, 0, 0))
			if want_u > 0.0:
				var neighbor_val = water_write.get_pixel(x, y - 1).r
				water_write.set_pixel(x, y - 1, Color(neighbor_val + want_u, 0, 0))
				
			var current_val_at_source = water_write.get_pixel(x, y).r
			water_write.set_pixel(x, y, Color(current_val_at_source + total_here - total_outflow, 0, 0))

# This carries pigments with water
func _apply_water_displacement_with_pigment(delta: float):
	# copy the current state to the write buffer.
	water_write.fill(Color(0,0,0,0))
	mobile_write.fill(Color(1,1,1,0))
	
	# Now, iterate and apply transfers between pixels.
	for y in range(canvas_height):
		for x in range(canvas_width):
			var current_water_here = water_read.get_pixel(x,y).r
			var capacity = absorbency_map.get_pixel(x,y).r  # 0.0 if unused
			var movable_water = max(0.0, current_water_here - capacity)
			var pigment_here = mobile_read.get_pixel(x,y)
			
			if movable_water < DRY_PIXEL_LIMIT:
				_add_content(x, y, current_water_here, pigment_here)
				continue

			# force field from previous stage
			var F = displacement_map.get_pixel(x,y)
			var want_r = max(0.0, F.r) * movable_water * delta
			var want_l = max(0.0, F.g) * movable_water * delta
			var want_d = max(0.0, F.b) * movable_water * delta
			var want_u = max(0.0, F.a) * movable_water * delta
			
			var directions = [["right",want_r],["left",want_l],["down",want_d], ["up",want_u]]
			directions.sort_custom(func(a, b): return a[1] > b[1])
			
			var passed_water = 0.0
			for dir_info in directions:
				var key = dir_info[0]
				var value = dir_info[1]
				match key:
					"right":
						want_r += passed_water
						if x < canvas_width - 1 and water_read.get_pixel(x+1,y).r < DRY_PIXEL_LIMIT and want_r < HOLD_THRESHOLD:
							passed_water = want_r * ENERGY_LOSS_ON_REDISTRIBUTION; want_r = 0.0
						else: passed_water = 0.0
					"left":
						want_l += passed_water
						if x > 0 and water_read.get_pixel(x-1,y).r < DRY_PIXEL_LIMIT and want_l < HOLD_THRESHOLD:
							passed_water = want_l * ENERGY_LOSS_ON_REDISTRIBUTION; want_l = 0.0
						else: passed_water = 0.0
					"up":
						want_u += passed_water
						if y > 0 and water_read.get_pixel(x,y-1).r < DRY_PIXEL_LIMIT and want_u < HOLD_THRESHOLD:
							passed_water = want_u * ENERGY_LOSS_ON_REDISTRIBUTION; want_u = 0.0
						else: passed_water = 0.0
					"down":
						want_d += passed_water
						if y < canvas_height - 1 and water_read.get_pixel(x,y+1).r < DRY_PIXEL_LIMIT and want_d < HOLD_THRESHOLD:
							passed_water = want_d * ENERGY_LOSS_ON_REDISTRIBUTION; want_d = 0.0
						else: passed_water = 0.0
			
			var total_outflow = want_r + want_l + want_d + want_u
			if total_outflow > movable_water:
				var scaling_factor = movable_water / total_outflow
				want_r *= scaling_factor
				want_l *= scaling_factor
				want_d *= scaling_factor
				want_u *= scaling_factor
				total_outflow = movable_water # The total is now exactly the movable amount
				
			# Caluation of remaining pigment after outflow of water
			var fraction_outflow = 0.0
			if current_water_here > 1e-6:
				fraction_outflow = total_outflow / current_water_here

			var pigment_alpha = pigment_here.a
			var pigment_mass = PigmentMixer._alpha_to_mass(pigment_alpha)
			var mass_movable = pigment_mass * fraction_outflow
			var mass_staying = pigment_mass - mass_movable
			
			var pigment_staying = Color(pigment_here.r, pigment_here.g, pigment_here.b, PigmentMixer._mass_to_alpha(mass_staying))
			_add_content(x, y, current_water_here - total_outflow, pigment_staying)
			
			# Distribute the content that MOVES to the neighbors
			if total_outflow > 0.0001:
				var hue = Color(pigment_here.r, pigment_here.g, pigment_here.b, 1.0)
				# and pass the correct water amount (want_r, etc.)
				if want_r > 0.0:
					var mass_out = mass_movable * ( want_r / total_outflow)
					_add_content(x + 1, y, want_r, Color(hue.r, hue.g, hue.b, PigmentMixer._mass_to_alpha(mass_out)))
				if want_l > 0.0:
					var mass_out = mass_movable * (want_l / total_outflow)
					_add_content(x - 1, y, want_l, Color(hue.r, hue.g, hue.b, PigmentMixer._mass_to_alpha(mass_out)))
				if want_d > 0.0:
					var mass_out = mass_movable * (want_d / total_outflow)
					_add_content(x, y + 1, want_d, Color(hue.r, hue.g, hue.b, PigmentMixer._mass_to_alpha(mass_out)))
				if want_u > 0.0:
					var mass_out = mass_movable * (want_u / total_outflow)
					_add_content(x, y - 1, want_u, Color(hue.r, hue.g, hue.b, PigmentMixer._mass_to_alpha(mass_out)))

# GPU implementation ready approach (still running on CPU)
func _apply_water_displacement_with_pigment_inflow(delta: float):
	water_write.fill(Color(0,0,0,0))
	mobile_write.fill(Color(1,1,1,0))

	for y in range(canvas_height):
		for x in range(canvas_width):
			# --- PART 1: compute my outflow and what stays at source ---
			var water_at_source = water_read.get_pixel(x, y).r
			var pigment_at_source = mobile_read.get_pixel(x, y)
			var capacity_at_source = absorbency_map.get_pixel(x, y).r
			var movable_water_at_source = max(0.0, water_at_source - capacity_at_source)

			var displacement_here = displacement_map.get_pixel(x, y)
			var outflow_right_wanted = max(0.0, displacement_here.r) * movable_water_at_source * delta
			var outflow_left_wanted  = max(0.0, displacement_here.g) * movable_water_at_source * delta
			var outflow_down_wanted  = max(0.0, displacement_here.b) * movable_water_at_source * delta
			var outflow_up_wanted    = max(0.0, displacement_here.a) * movable_water_at_source * delta

			var total_outflow_wanted = outflow_right_wanted + outflow_left_wanted + outflow_down_wanted + outflow_up_wanted
			if total_outflow_wanted > movable_water_at_source and total_outflow_wanted > 0.0:
				var scale_factor = movable_water_at_source / total_outflow_wanted
				outflow_right_wanted *= scale_factor
				outflow_left_wanted  *= scale_factor
				outflow_down_wanted  *= scale_factor
				outflow_up_wanted    *= scale_factor
				total_outflow_wanted  = movable_water_at_source

			var water_staying_at_source = water_at_source - total_outflow_wanted

			# pigment partition (absorbed vs movable) and what stays after outflow
			var mass_staying_at_source = 0.0
			var pigment_mass_at_source = PigmentMixer._alpha_to_mass(pigment_at_source.a)

			if water_at_source > 1e-6 and pigment_mass_at_source > 0.0:
				var movable_mass_fraction = movable_water_at_source / water_at_source
				var movable_pigment_mass_at_source = pigment_mass_at_source * movable_mass_fraction
				var absorbed_pigment_mass_at_source = pigment_mass_at_source - movable_pigment_mass_at_source

				var outflow_fraction_of_movable = 0.0
				if movable_water_at_source > 1e-6:
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

			# from LEFT neighbor -> their RIGHT outflow lands here
			if x > 0:
				var neighbor_flows = _final_outflows_at(x - 1, y, delta)
				var water_in_from_left = neighbor_flows.x
				if water_in_from_left > 0.0:
					total_inflow_water += water_in_from_left

					var neighbor_water = water_read.get_pixel(x - 1, y).r
					var neighbor_capacity = absorbency_map.get_pixel(x - 1, y).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x - 1, y)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_left / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					#inflow_pigment_accum = _mix_pigments_with_mass_conversion(inflow_pigment_accum, incoming_pigment_color)
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)
					
			# from RIGHT neighbor -> their LEFT outflow lands here
			if x < canvas_width - 1:
				var neighbor_flows = _final_outflows_at(x + 1, y, delta)
				var water_in_from_right = neighbor_flows.y
				if water_in_from_right > 0.0:
					total_inflow_water += water_in_from_right

					var neighbor_water = water_read.get_pixel(x + 1, y).r
					var neighbor_capacity = absorbency_map.get_pixel(x + 1, y).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x + 1, y)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_right / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					#inflow_pigment_accum = _mix_pigments_with_mass_conversion(inflow_pigment_accum, incoming_pigment_color)
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)

			# from UP neighbor -> their DOWN outflow lands here
			if y > 0:
				var neighbor_flows = _final_outflows_at(x, y - 1, delta)
				var water_in_from_up = neighbor_flows.z
				if water_in_from_up > 0.0:
					total_inflow_water += water_in_from_up

					var neighbor_water = water_read.get_pixel(x, y - 1).r
					var neighbor_capacity = absorbency_map.get_pixel(x, y - 1).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x, y - 1)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_up / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					#inflow_pigment_accum = _mix_pigments_with_mass_conversion(inflow_pigment_accum, incoming_pigment_color)
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)

			# from DOWN neighbor -> their UP outflow lands here
			if y < canvas_height - 1:
				var neighbor_flows = _final_outflows_at(x, y + 1, delta)
				var water_in_from_down = neighbor_flows.w
				if water_in_from_down > 0.0:
					total_inflow_water += water_in_from_down

					var neighbor_water = water_read.get_pixel(x, y + 1).r
					var neighbor_capacity = absorbency_map.get_pixel(x, y + 1).r
					var neighbor_movable_water = max(0.0, neighbor_water - neighbor_capacity)
					var neighbor_pigment = mobile_read.get_pixel(x, y + 1)

					var neighbor_mass = PigmentMixer._alpha_to_mass(neighbor_pigment.a)
					var neighbor_movable_mass = neighbor_mass * (neighbor_movable_water / max(neighbor_water, 1e-6))
					var incoming_mass = neighbor_movable_mass * (water_in_from_down / max(neighbor_movable_water, 1e-6))

					var incoming_pigment_color = Color(neighbor_pigment.r, neighbor_pigment.g, neighbor_pigment.b, PigmentMixer._mass_to_alpha(incoming_mass))
					#inflow_pigment_accum = _mix_pigments_with_mass_conversion(inflow_pigment_accum, incoming_pigment_color)
					inflow_pigment_accum = PigmentMixer._mix_pigments_optical(inflow_pigment_accum, incoming_pigment_color)

			# --- PART 3: finalize this pixel ---
			var final_water_at_pixel = water_staying_at_source + total_inflow_water
			var final_pigment_at_pixel = PigmentMixer._mix_pigments_optical(pigment_staying_color, inflow_pigment_accum)

			water_write.set_pixel(x, y, Color(final_water_at_pixel, 0, 0))
			mobile_write.set_pixel(x, y, final_pigment_at_pixel)


# --- HELPER FUNCTIONS ---

# A helper function to make water and pigment transfers. This also considers updated amounts in write buffer
func _add_content(x: int, y: int, water_amount: float, pigment_color: Color):
	if x < 0 or x >= canvas_width or y < 0 or y >= canvas_height: return
	# Add water
	var incoming_water = water_write.get_pixel(x, y).r
	water_write.set_pixel(x, y, Color(incoming_water + water_amount, 0, 0))
	
	# Add pigment
	var incoming_pigment = mobile_write.get_pixel(x, y)
	mobile_write.set_pixel(x, y, PigmentMixer._mix_pigments_optical(pigment_color, incoming_pigment))

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



# This function will handle the spreading of water and mobile pigment.
func _simulate_diffusion(delta: float, water: Image, mobile_pigment: Image):
	# TODO: Implement the diffusion logic here.
	# This will involve looping through each pixel and its neighbors.
	pass


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


# This function will handle wet pigment getting "stuck" to the paper and becoming dry.
func _simulate_deposition(delta: float, water: Image, mobile_pigment: Image, static_pigment: Image):
	# TODO: Implement deposition logic here.
	# This will move color from the mobile_pigment Image to the static_pigment Image.
	pass
	
