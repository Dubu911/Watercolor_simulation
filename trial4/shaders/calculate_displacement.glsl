#version 450

// Calculate water displacement forces
// Computes gravity, surface tension (10-pixel lookahead), and spreading forces
// Includes dry boundary detection and force redistribution

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Textures
layout(set = 0, binding = 0, r32f) uniform readonly image2D water_read;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D displacement_map;

// Push constants
layout(push_constant, std430) uniform Params {
	float gravity_x;
	float gravity_y;
	float S;  // Surface tension
	float SP; // Spreading force
	float hold_threshold;
	float energy_loss;
	float dry_pixel_limit;
	uint canvas_width;
	uint canvas_height;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);

	if (pos.x >= params.canvas_width || pos.y >= params.canvas_height) {
		return;
	}

	float water_amount = imageLoad(water_read, pos).r;

	// --- HORIZONTAL FORCES ---

	// 1. Gravity force
	float gravity_force_x = water_amount * params.gravity_x;

	// 2. Surface tension force (10-pixel lookahead)
	float left_sum = 0.0;
	float right_sum = 0.0;
	int count = 0;

	// Left side lookahead
	for (int i = 1; i <= 10; i++) {
		if (pos.x - i >= 0) {
			float amount = imageLoad(water_read, pos + ivec2(-i, 0)).r;
			if (amount <= params.dry_pixel_limit) break;
			left_sum += amount;
			count++;
		}
	}
	if (count > 0) left_sum /= float(count);

	// Right side lookahead
	count = 0;
	for (int i = 1; i <= 10; i++) {
		if (pos.x + i < params.canvas_width) {
			float amount = imageLoad(water_read, pos + ivec2(i, 0)).r;
			if (amount <= params.dry_pixel_limit) break;
			right_sum += amount;
			count++;
		}
	}
	if (count > 0) right_sum /= float(count);

	float surface_tension_force_x = params.S * (right_sum - left_sum);

	// 3. Spreading force (immediate neighbors)
	float left_neighbor = 0.0;
	float right_neighbor = 0.0;
	if (pos.x > 0) {
		left_neighbor = imageLoad(water_read, pos + ivec2(-1, 0)).r;
	}
	if (pos.x < params.canvas_width - 1) {
		right_neighbor = imageLoad(water_read, pos + ivec2(1, 0)).r;
	}

	float spread_force_r = params.SP * (water_amount - right_neighbor);
	float spread_force_l = params.SP * (water_amount - left_neighbor);

	// 4. Total horizontal forces
	float horizontal_net_force = gravity_force_x + surface_tension_force_x;
	float total_force_r = max(0.0, horizontal_net_force) + spread_force_r;
	float total_force_l = max(0.0, -horizontal_net_force) + spread_force_l;

	// --- VERTICAL FORCES ---

	// 1. Gravity force
	float gravity_force_y = water_amount * params.gravity_y;

	// 2. Surface tension force (10-pixel lookahead)
	float up_sum = 0.0;
	float down_sum = 0.0;
	count = 0;

	// Up side lookahead
	for (int i = 1; i <= 10; i++) {
		if (pos.y - i >= 0) {
			float amount = imageLoad(water_read, pos + ivec2(0, -i)).r;
			if (amount < params.dry_pixel_limit) break;
			up_sum += amount;
			count++;
		}
	}
	if (count > 0) up_sum /= float(count);

	// Down side lookahead
	count = 0;
	for (int i = 1; i <= 10; i++) {
		if (pos.y + i < params.canvas_height) {
			float amount = imageLoad(water_read, pos + ivec2(0, i)).r;
			if (amount < params.dry_pixel_limit) break;
			down_sum += amount;
			count++;
		}
	}
	if (count > 0) down_sum /= float(count);

	float surface_tension_force_y = params.S * (down_sum - up_sum);

	// 3. Spreading force (immediate neighbors)
	float up_neighbor = 0.0;
	float down_neighbor = 0.0;
	if (pos.y > 0) {
		up_neighbor = imageLoad(water_read, pos + ivec2(0, -1)).r;
	}
	if (pos.y < params.canvas_height - 1) {
		down_neighbor = imageLoad(water_read, pos + ivec2(0, 1)).r;
	}

	float spread_force_u = params.SP * (water_amount - up_neighbor);
	float spread_force_d = params.SP * (water_amount - down_neighbor);

	// 4. Total vertical forces
	float vertical_net_force = gravity_force_y + surface_tension_force_y;
	float total_force_d = max(0.0, vertical_net_force) + spread_force_d;
	float total_force_u = max(0.0, -vertical_net_force) + spread_force_u;

	// --- REDISTRIBUTION LOGIC (blocked dry paths) ---

	float total_original_force = total_force_r + total_force_l + total_force_d + total_force_u;

	float final_r = total_force_r;
	float final_l = total_force_l;
	float final_d = total_force_d;
	float final_u = total_force_u;

	// Nullify blocked paths (dry neighbors below hold threshold)
	if (pos.x < params.canvas_width - 1) {
		float neighbor_water = imageLoad(water_read, pos + ivec2(1, 0)).r;
		if (neighbor_water < params.dry_pixel_limit && total_force_r < params.hold_threshold) {
			final_r = 0.0;
		}
	}

	if (pos.x > 0) {
		float neighbor_water = imageLoad(water_read, pos + ivec2(-1, 0)).r;
		if (neighbor_water < params.dry_pixel_limit && total_force_l < params.hold_threshold) {
			final_l = 0.0;
		}
	}

	if (pos.y < params.canvas_height - 1) {
		float neighbor_water = imageLoad(water_read, pos + ivec2(0, 1)).r;
		if (neighbor_water < params.dry_pixel_limit && total_force_d < params.hold_threshold) {
			final_d = 0.0;
		}
	}

	if (pos.y > 0) {
		float neighbor_water = imageLoad(water_read, pos + ivec2(0, -1)).r;
		if (neighbor_water < params.dry_pixel_limit && total_force_u < params.hold_threshold) {
			final_u = 0.0;
		}
	}

	float total_available_force = final_r + final_l + final_d + final_u;

	// Redistribute blocked force to available directions
	if (total_available_force > 0.0 && total_original_force > total_available_force) {
		float amplification = 1.0 + ((total_original_force / total_available_force) - 1.0) * params.energy_loss;
		final_r *= amplification;
		final_l *= amplification;
		final_d *= amplification;
		final_u *= amplification;
	}

	// Store forces: R=right, G=left, B=down, A=up
	imageStore(displacement_map, pos, vec4(final_r, final_l, final_d, final_u));
}
