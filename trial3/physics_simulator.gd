# physics_simulator.gd
extends Node

# --- SIMULATION CONSTANTS ---
const DIFFUSION_RATE = 0.1
const EVAPORATION_RATE = 0.005
#const S = 0.5 # Surface tension coefficient
#const SP = 1.3 # Spread force coefficient
@export var S: float = 0.5 # Surface tension coefficient
@export var SP: float = 1.35 # Spread force coefficient
@export var HOLD_THRESHOLD = 1.3 # The force needed to wet a dry pixel
const DRY_PIXEL_LIMIT = 0.0 # Any water amount below this is considered "dry"
const ENERGY_LOSS_ON_REDISTRIBUTION = 0.5 # How much energy is lost when flow is redirected


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
	var change_speed = 0.1 * delta # How fast the values change
	values_changed_this_frame = false
	# --- Controls for Surface Tension (S) ---
	if Input.is_key_pressed(KEY_Q):
		S += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_A):
		S -= change_speed
		values_changed_this_frame = true
	# --- Controls for Spreading Force (SP) ---
	if Input.is_key_pressed(KEY_W):
		SP += change_speed
		values_changed_this_frame = true
	if Input.is_key_pressed(KEY_S):
		SP -= change_speed
		values_changed_this_frame = true
		
	# Ensure values don't go below zero
	S = max(0.0, S)
	SP = max(0.0, SP)

	# Print the new values to the console only if they changed
	if values_changed_this_frame:
		print("Surface Tension (S): %.2f | Spreading Force (SP): %.2f" % [S, SP])


func init(p_width: int, p_height: int, p_water_read: Image, p_water_write: Image, p_mobile_read: Image, 
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
	_calculate_water_displacement(g_x, g_y)
	#_apply_water_displacement(delta) # surface water movements happen with pigments in mobile_image
	_apply_water_displacement_outflow_model(delta)
	# _simulate_deposition(delta, water_img, mobile_img, static_img) # mobile_image -> static_image
	
	# Swap the buffers so the new state becomes the current state for the next frame.
	var temp = water_read
	water_read = water_write
	water_write = temp
	# Clear the new write buffer for the next iteration.
	#water_write.fill(Color(0,0,0,0))

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
					if amount <= 0 : break
					left_sum += amount
					count += 1
			if count > 0: left_sum /= count
			
			# Right side
			count = 0
			for i in range(1,11):
				if x+i < canvas_width:
					var amount = water_read.get_pixel(x+i,y).r
					if amount <= 0 : break
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
			
# Move the water based on the calculated forces.(Inflow model)
func _apply_water_displacement(delta: float):
	# First, copy the current state to the write buffer.
	# We will then move water between pixels *within* this write buffer.
	water_write.blit_rect(water_read, Rect2i(0, 0, canvas_width, canvas_height), Vector2i(0, 0))
	#water_write.fill(Color(0,0,0,0))
	
	# Now, iterate and apply transfers between pixels.
	for y in range(canvas_height):
		for x in range(canvas_width):
			var water_at_source = water_read.get_pixel(x, y).r
			if water_at_source < DRY_PIXEL_LIMIT:
				continue # Skip dry pixels

			var D = displacement_map.get_pixel(x, y)
			
			# --- Horizontal Transfer ---
			if D.r > 0 and x < canvas_width - 1: # Wants to move RIGHT
				var amount_to_move = D.r * water_at_source * delta
				var neighbor_water = water_write.get_pixel(x + 1, y).r
				if not (neighbor_water < DRY_PIXEL_LIMIT and amount_to_move < HOLD_THRESHOLD):
					# Can't move more than we have
					var actual_move_amount = min(amount_to_move, water_at_source)
					# Get current values from the WRITE buffer
					var source_val = water_write.get_pixel(x, y).r
					var dest_val = water_write.get_pixel(x + 1, y).r
					# Update the ledger
					water_write.set_pixel(x, y, Color(source_val - actual_move_amount, 0, 0))
					water_write.set_pixel(x + 1, y, Color(dest_val + actual_move_amount, 0, 0))
			elif D.r < 0 and x > 0: # Wants to move LEFT
				var amount_to_move = abs(D.r * water_at_source * delta)
				var neighbor_water = water_write.get_pixel(x - 1, y).r
				if not (neighbor_water < DRY_PIXEL_LIMIT and amount_to_move < HOLD_THRESHOLD):
					var actual_move_amount = min(amount_to_move, water_at_source)
					var source_val = water_write.get_pixel(x, y).r
					var dest_val = water_write.get_pixel(x - 1, y).r
					water_write.set_pixel(x, y, Color(source_val - actual_move_amount, 0, 0))
					water_write.set_pixel(x - 1, y, Color(dest_val + actual_move_amount, 0, 0))

			# --- Vertical Transfer ---
			# We need to re-read the water amount at the source, as it might have changed
			# from the horizontal transfer. This is why the blit_rect is so important.
			water_at_source = water_write.get_pixel(x,y).r 
			
			if D.g > 0 and y < canvas_height - 1: # Wants to move DOWN
				var amount_to_move = D.g * water_at_source * delta
				var neighbor_water = water_write.get_pixel(x, y + 1).r
				if not (neighbor_water < DRY_PIXEL_LIMIT and amount_to_move < HOLD_THRESHOLD):
					var actual_move_amount = min(amount_to_move, water_at_source)
					var source_val = water_write.get_pixel(x, y).r
					var dest_val = water_write.get_pixel(x, y + 1).r
					water_write.set_pixel(x, y, Color(source_val - actual_move_amount, 0, 0))
					water_write.set_pixel(x, y + 1, Color(dest_val + actual_move_amount, 0, 0))
			elif D.g < 0 and y > 0: # Wants to move UP
				var amount_to_move = abs(D.g * water_at_source * delta)
				var neighbor_water = water_write.get_pixel(x, y - 1).r
				if not (neighbor_water < DRY_PIXEL_LIMIT and amount_to_move < HOLD_THRESHOLD):
					var actual_move_amount = min(amount_to_move, water_at_source)
					var source_val = water_write.get_pixel(x, y).r
					var dest_val = water_write.get_pixel(x, y - 1).r
					water_write.set_pixel(x, y, Color(source_val - actual_move_amount, 0, 0))
					water_write.set_pixel(x, y - 1, Color(dest_val + actual_move_amount, 0, 0))
	
# Outflow model
func _apply_water_displacement_outflow_model(delta: float):
	 #Getting write buffer ready for work
	water_write.fill(Color(0,0,0,0))

	for y in range(canvas_height):
		for x in range(canvas_width):

			var total_here = water_read.get_pixel(x,y).r
			var capacity = absorbency_map.get_pixel(x,y).r  # 0.0 if unused
			var movable_water = max(0.0, total_here - capacity)
			if movable_water <= DRY_PIXEL_LIMIT:
				#water_write.set_pixel(x,y, Color(total_here,0,0))
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

			# --- Commit the transfers using the ACCUMULATOR pattern ---
			
			# Add the water that STAYS to the write buffer at the source pixel
			var water_staying = total_here - total_outflow
			var source_val = water_write.get_pixel(x, y).r
			water_write.set_pixel(x, y, Color(source_val + water_staying, 0, 0))
			
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
	
