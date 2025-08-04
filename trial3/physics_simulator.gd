# physics_simulator.gd
extends Node

# --- SIMULATION CONSTANTS ---
const DIFFUSION_RATE = 0.1
const EVAPORATION_RATE = 0.005
#const S = 0.5 # Surface tension coefficient
#const SP = 1.3 # Spread force coefficient
@export var S: float = 0.10 # Surface tension coefficient
@export var SP: float = 0.50 # Spread force coefficient
@export var HOLD_THRESHOLD = 3.5 # The force needed to wet a dry pixel
const DRY_PIXEL_LIMIT = 0.0001 # Any water amount below this is considered "dry"
const ENERGY_LOSS_ON_REDISTRIBUTION = 0.7 # How much energy is lost when flow is redirected


# --- MEMBER VARIABLES TO HOLD REFERENCES TO DATA LAYERS ---
var canvas_width := 0
var canvas_height := 0

var water_read: Image
var water_write: Image
var mobile_read: Image
var mobile_write: Image
var static_pigment: Image
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
		  p_mobile_write: Image, p_static_pigment: Image, p_absorbency: Image, p_displacement: Image):
	canvas_width = p_width
	canvas_height = p_height
	
	water_read = p_water_read
	water_write = p_water_write
	mobile_read = p_mobile_read
	mobile_write = p_mobile_write
	static_pigment = p_static_pigment
	absorbency_map = p_absorbency
	displacement_map = p_displacement
	
func run_simulation_step(delta: float, g_x: float, g_y: float):
	#pass
	#_simulate_evaporation(delta, water_img)
	#_simulate_diffusion(delta, water_img, mobile_img) # pigments in mobile_image diffusses
	#_calculate_water_displacement(g_x, g_y)
	_calculate_water_displacement2(g_x, g_y)
	_apply_water_displacement(delta) # surface water movements happen with pigments in mobile_image
	#_apply_water_displacement_outflow_model(delta)
	#_apply_water_displacement_outflow_model_with_pigment(delta)
	# _simulate_deposition(delta, water_img, mobile_img, static_img) # mobile_image -> static_image
	
	# Swap both sets of buffers for the next frame
	var temp_water = water_read
	water_read = water_write
	water_write = temp_water
	
	var temp_mobile = mobile_read
	mobile_read = mobile_write
	mobile_write = temp_mobile

# --- PRIVATE SIMULATION FUNCTIONS ---

# This function calculates force acting on water due to gravity, surface tention and spreading.
func _calculate_water_displacement(g_x: float, g_y: float):
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
			

# This function is an improved version. It calculates 4 directions.
func _calculate_water_displacement2(g_x: float, g_y: float):
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

# Move the water based on the calculated forces.(Inflow model)
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
				
			var current_val_at_source = water_write.get_pixel(x, y).r
			water_write.set_pixel(x, y, Color(current_val_at_source + total_here - total_outflow, 0, 0))
			
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


func _apply_water_displacement_outflow_model_with_pigment(delta: float):
	# Start with clean slates for the next frame's data.
	water_write.fill(Color(0,0,0,0))
	mobile_write.fill(Color(1,1,1,0)) # Use transparent white to prevent black outlines
	#mobile_write.fill(Color(0,0,0,0))
	
	# This loop calculates the final state of each pixel and writes it to the buffers.
	for y in range(canvas_height):
		for x in range(canvas_width):
			# --- Step 1: Calculate what STAYS vs. what MOVES ---
			var total_water_here = water_read.get_pixel(x,y).r
			var capacity = absorbency_map.get_pixel(x,y).r
			var movable_water = max(0.0, total_water_here - capacity)
			
			var pigment_here = mobile_read.get_pixel(x,y)
			
			# --- Step 2: Add the water and pigment that STAYS to the write buffers first. ---			
			if movable_water < DRY_PIXEL_LIMIT:
				_add_content(x, y, total_water_here, pigment_here)
				continue

			# force field from previous stage
			var F = displacement_map.get_pixel(x,y)
			var want_r = max(0.0, F.r) * movable_water * delta
			var want_l = max(0.0,-F.r) * movable_water * delta
			var want_d = max(0.0, F.g) * movable_water * delta
			var want_u = max(0.0,-F.g) * movable_water * delta

			# Identify blocked paths and sum the blocked flow.
			var total_blocked_flow = 0.0
			
			if x < canvas_width - 1 and water_read.get_pixel(x+1,y).r < DRY_PIXEL_LIMIT and want_r < HOLD_THRESHOLD:
				total_blocked_flow += want_r; want_r = 0.0
			if x > 0 and water_read.get_pixel(x-1,y).r < DRY_PIXEL_LIMIT and want_l < HOLD_THRESHOLD:
				total_blocked_flow += want_l; want_l = 0.0
			if y < canvas_height - 1 and water_read.get_pixel(x,y+1).r < DRY_PIXEL_LIMIT and want_d < HOLD_THRESHOLD:
				total_blocked_flow += want_d; want_d = 0.0
			if y > 0 and water_read.get_pixel(x,y-1).r < DRY_PIXEL_LIMIT and want_u < HOLD_THRESHOLD:
				total_blocked_flow += want_u; want_u = 0.0

			# Redistribute the blocked flow to any open paths.
			var open_paths_count = 0
			if want_r > 0.0: open_paths_count += 1
			if want_l > 0.0: open_paths_count += 1
			if want_d > 0.0: open_paths_count += 1
			if want_u > 0.0: open_paths_count += 1
			
			if open_paths_count > 0 and total_blocked_flow > 0:
				var redistributed_flow = (total_blocked_flow * ENERGY_LOSS_ON_REDISTRIBUTION) / open_paths_count
				if want_r > 0.0: want_r += redistributed_flow
				if want_l > 0.0: want_l += redistributed_flow
				if want_d > 0.0: want_d += redistributed_flow
				if want_u > 0.0: want_u += redistributed_flow
				
			# Scale down outflows if they exceed the available movable water
			var total_outflow = want_r + want_l + want_d + want_u
			if total_outflow > movable_water:
				var scaling_factor = movable_water / total_outflow
				want_r *= scaling_factor
				want_l *= scaling_factor
				want_d *= scaling_factor
				want_u *= scaling_factor
				total_outflow = movable_water # The total is now exactly the movable amount
			
			var water_staying = total_water_here - total_outflow
			var pigment_concentration = pigment_here.a

			# If there's no pigment, just commit the water transfers and we're done with this pixel.
			if pigment_concentration < 0.0001:
				_add_content(x, y, water_staying, Color(0,0,0,0))
				if total_outflow > 0.0:
					if want_r > 0: _add_content(x + 1, y, want_r, Color(0,0,0,0))
					if want_l > 0: _add_content(x - 1, y, want_l, Color(0,0,0,0))
					if want_d > 0: _add_content(x, y + 1, want_d, Color(0,0,0,0))
					if want_u > 0: _add_content(x, y - 1, want_u, Color(0,0,0,0))
			else:
				# This branch runs only if there IS pigment, solving the hue shift problem.
				var movable_pigment_fraction = 0.0
				if total_water_here > 0.0001:
					movable_pigment_fraction = total_outflow / total_water_here
				
				# This is now safe from "white pigment" contamination.
				var pigment_hue = Color(pigment_here.r, pigment_here.g, pigment_here.b, 1.0)
				
				var concentration_movable = pigment_concentration * movable_pigment_fraction
				var concentration_staying = pigment_concentration - concentration_movable
				
				var pigment_staying = Color(pigment_hue.r, pigment_hue.g, pigment_hue.b, concentration_staying)
				
				# Commit staying content.
				_add_content(x, y, water_staying, pigment_staying)
				
				# Commit moving content.
				if total_outflow > 0.0001:
					# FIX for mass loss: Construct the outgoing pigment correctly.
					var scale_r = want_r / total_outflow
					var scale_l = want_l / total_outflow
					var scale_d = want_d / total_outflow
					var scale_u = want_u / total_outflow
					
					if want_r > 0: _add_content(x + 1, y, want_r, Color(pigment_hue.r, pigment_hue.g, pigment_hue.b, concentration_movable * scale_r))
					if want_l > 0: _add_content(x - 1, y, want_l, Color(pigment_hue.r, pigment_hue.g, pigment_hue.b, concentration_movable * scale_l))
					if want_d > 0: _add_content(x, y + 1, want_d, Color(pigment_hue.r, pigment_hue.g, pigment_hue.b, concentration_movable * scale_d))
					if want_u > 0: _add_content(x, y - 1, want_u, Color(pigment_hue.r, pigment_hue.g, pigment_hue.b, concentration_movable * scale_u))
			


# --- HELPER FUNCTIONS ---

# A new helper function to make transfers atomic and clean
func _add_content(x: int, y: int, water_amount: float, pigment_color: Color):
	if x < 0 or x >= canvas_width or y < 0 or y >= canvas_height: return
	# Add water
	var current_water = water_write.get_pixel(x, y).r
	water_write.set_pixel(x, y, Color(current_water + water_amount, 0, 0))
	
	# Add pigment by layering
	var current_pigment = mobile_write.get_pixel(x, y)
	mobile_write.set_pixel(x, y, _layer_colors(pigment_color, current_pigment))

func _layer_colors(pigment1: Color, pigment2: Color) -> Color:
	# If one pigment has no concentration, just return the other.
	if pigment1.a < 0.0001: return pigment2
	if pigment2.a < 0.0001: return pigment1
	
	# Calculate the total concentration, capped at 1.0
	var total_alpha = pigment1.a + pigment2.a
	var final_alpha = min(1.0, total_alpha)

	# Calculate the total "mass" of each color component
	var total_r = (pigment1.r * pigment1.a) + (pigment2.r * pigment2.a)
	var total_g = (pigment1.g * pigment1.a) + (pigment2.g * pigment2.a)
	var total_b = (pigment1.b * pigment1.a) + (pigment2.b * pigment2.a)

	# The final color is the weighted average of the components.
	var final_r = total_r / total_alpha
	var final_g = total_g / total_alpha
	var final_b = total_b / total_alpha
	
	return Color(final_r, final_g, final_b, final_alpha)


# This function will handle the spreading of water and mobile pigment.
func _simulate_diffusion(delta: float, water: Image, mobile_pigment: Image):
	# TODO: Implement the diffusion logic here.
	# This will involve looping through each pixel and its neighbors.
	pass


# This function will handle water evaporating from the canvas over time.
func _simulate_evaporation(delta: float, water: Image):
	# TODO: Implement evaporation logic here.
	# This will likely involve reducing the water amount at each pixel slightly.
	pass


# This function will handle wet pigment getting "stuck" to the paper and becoming dry.
func _simulate_deposition(delta: float, water: Image, mobile_pigment: Image, static_pigment: Image):
	# TODO: Implement deposition logic here.
	# This will move color from the mobile_pigment Image to the static_pigment Image.
	pass
	
