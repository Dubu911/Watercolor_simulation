#version 450

// Apply water displacement with pigment transport (INFLOW MODEL)
// Includes momentum/inertia system to reduce oscillation
// Each pixel gathers water and pigment from neighbors

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Textures
layout(set = 0, binding = 0, r32f) uniform readonly image2D water_read;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D water_write;
layout(set = 0, binding = 2, rgba32f) uniform readonly image2D mobile_read;
layout(set = 0, binding = 3, rgba32f) uniform writeonly image2D mobile_write;
layout(set = 0, binding = 4, r32f) uniform readonly image2D absorbency_map;
layout(set = 0, binding = 5, rgba32f) uniform readonly image2D displacement_map;
layout(set = 0, binding = 6, rgba32f) uniform readonly image2D inertia_read;
layout(set = 0, binding = 7, rgba32f) uniform writeonly image2D inertia_write;

// Push constants
layout(push_constant, std430) uniform Params {
	float delta;
	float canceling_power;
	float acceleration_power;
	float dry_pixel_limit;
	float k_absorption;
	float eps_a;
	uint canvas_width;
	uint canvas_height;
} params;

// Helper: Convert alpha to mass (Beer-Lambert law)
float alpha_to_mass(float alpha) {
	return -log(max(1.0 - alpha, params.eps_a)) / params.k_absorption;
}

// Helper: Convert mass to alpha
float mass_to_alpha(float mass) {
	return 1.0 - exp(-params.k_absorption * mass);
}

// Helper: Optical mixing of two pigments
vec4 mix_pigments_optical(vec4 pigment_a, vec4 pigment_b) {
	float mass_a = alpha_to_mass(pigment_a.a);
	float mass_b = alpha_to_mass(pigment_b.a);
	float total_mass = mass_a + mass_b;

	if (total_mass < params.eps_a) {
		return vec4(1.0, 1.0, 1.0, 0.0);
	}

	float weight_a = mass_a / total_mass;
	float weight_b = mass_b / total_mass;

	vec3 mixed_hue = pigment_a.rgb * weight_a + pigment_b.rgb * weight_b;
	float mixed_alpha = mass_to_alpha(total_mass);

	return vec4(mixed_hue, mixed_alpha);
}

// Helper: Calculate final outflows with momentum dampening
vec4 final_outflows_at(ivec2 neighbor_pos) {
	// Bounds check
	if (neighbor_pos.x < 0 || neighbor_pos.x >= params.canvas_width ||
		neighbor_pos.y < 0 || neighbor_pos.y >= params.canvas_height) {
		return vec4(0.0);
	}

	float water_at_neighbor = imageLoad(water_read, neighbor_pos).r;
	if (water_at_neighbor <= params.dry_pixel_limit) {
		return vec4(0.0);
	}

	float capacity = imageLoad(absorbency_map, neighbor_pos).r;
	float movable_water = max(0.0, water_at_neighbor - capacity);
	if (movable_water <= params.dry_pixel_limit) {
		return vec4(0.0);
	}

	// Get displacement forces
	vec4 displacement = imageLoad(displacement_map, neighbor_pos);

	// Calculate raw outflows
	float outflow_right = max(0.0, displacement.r) * movable_water * params.delta;
	float outflow_left = max(0.0, displacement.g) * movable_water * params.delta;
	float outflow_down = max(0.0, displacement.b) * movable_water * params.delta;
	float outflow_up = max(0.0, displacement.a) * movable_water * params.delta;

	// --- MOMENTUM DAMPENING ---
	// Read inertia memory from previous frame
	vec4 inertia = imageLoad(inertia_read, neighbor_pos);
	float inflow_from_right = inertia.r;
	float inflow_from_left = inertia.g;
	float inflow_from_down = inertia.b;
	float inflow_from_up = inertia.a;

	// Apply canceling: dampen outflows pushing against recent inflows
	if (inflow_from_right > 0.0) {
		float cancel = min(outflow_right, inflow_from_right) * params.canceling_power;
		outflow_right -= cancel;
	} else if (params.acceleration_power > 0.0 && inflow_from_left > 0.0) {
		float boost = min(outflow_right, inflow_from_left) * params.acceleration_power;
		outflow_right += boost;
	}

	if (inflow_from_left > 0.0) {
		float cancel = min(outflow_left, inflow_from_left) * params.canceling_power;
		outflow_left -= cancel;
	} else if (params.acceleration_power > 0.0 && inflow_from_right > 0.0) {
		float boost = min(outflow_left, inflow_from_right) * params.acceleration_power;
		outflow_left += boost;
	}

	if (inflow_from_down > 0.0) {
		float cancel = min(outflow_down, inflow_from_down) * params.canceling_power;
		outflow_down -= cancel;
	} else if (params.acceleration_power > 0.0 && inflow_from_up > 0.0) {
		float boost = min(outflow_down, inflow_from_up) * params.acceleration_power;
		outflow_down += boost;
	}

	if (inflow_from_up > 0.0) {
		float cancel = min(outflow_up, inflow_from_up) * params.canceling_power;
		outflow_up -= cancel;
	} else if (params.acceleration_power > 0.0 && inflow_from_down > 0.0) {
		float boost = min(outflow_up, inflow_from_down) * params.acceleration_power;
		outflow_up += boost;
	}

	// --- CONSERVATION SCALING ---
	float total_outflow = outflow_right + outflow_left + outflow_down + outflow_up;
	if (total_outflow > movable_water && total_outflow > 0.0) {
		float scale = movable_water / total_outflow;
		outflow_right *= scale;
		outflow_left *= scale;
		outflow_down *= scale;
		outflow_up *= scale;
	}

	return vec4(outflow_right, outflow_left, outflow_down, outflow_up);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);

	if (pos.x >= params.canvas_width || pos.y >= params.canvas_height) {
		return;
	}

	// --- PART 1: Calculate what stays at this pixel ---
	float water_at_source = imageLoad(water_read, pos).r;
	vec4 pigment_at_source = imageLoad(mobile_read, pos);
	float capacity_at_source = imageLoad(absorbency_map, pos).r;
	float movable_water_at_source = max(0.0, water_at_source - capacity_at_source);

	// Get my own outflows
	vec4 outflows_here = final_outflows_at(pos);
	float total_outflow = outflows_here.x + outflows_here.y + outflows_here.z + outflows_here.w;
	float water_staying = water_at_source - total_outflow;

	// Calculate pigment staying (absorbed + non-outflowing movable)
	float pigment_mass = alpha_to_mass(pigment_at_source.a);
	float mass_staying = pigment_mass;

	if (water_at_source > 1e-6 && pigment_mass > 0.0) {
		float movable_mass_fraction = movable_water_at_source / water_at_source;
		float movable_mass = pigment_mass * movable_mass_fraction;
		float absorbed_mass = pigment_mass - movable_mass;

		float outflow_fraction = 0.0;
		if (movable_water_at_source > params.eps_a) {
			outflow_fraction = total_outflow / movable_water_at_source;
		}

		float mass_flowing_out = movable_mass * outflow_fraction;
		mass_staying = (movable_mass - mass_flowing_out) + absorbed_mass;
	}

	vec4 pigment_staying = vec4(
		pigment_at_source.rgb,
		mass_to_alpha(mass_staying)
	);

	// --- PART 2: Gather inflows from neighbors ---
	float total_inflow_water = 0.0;
	vec4 inflow_pigment_accum = vec4(1.0, 1.0, 1.0, 0.0);

	// Track inflows for inertia memory
	float inflow_from_right = 0.0;
	float inflow_from_left = 0.0;
	float inflow_from_down = 0.0;
	float inflow_from_up = 0.0;

	// From LEFT neighbor (their RIGHT outflow)
	if (pos.x > 0) {
		ivec2 neighbor_pos = pos + ivec2(-1, 0);
		vec4 neighbor_flows = final_outflows_at(neighbor_pos);
		float water_in = neighbor_flows.x; // Their right outflow

		if (water_in > 0.0) {
			total_inflow_water += water_in;
			inflow_from_left = water_in;

			float neighbor_water = imageLoad(water_read, neighbor_pos).r;
			float neighbor_capacity = imageLoad(absorbency_map, neighbor_pos).r;
			float neighbor_movable = max(0.0, neighbor_water - neighbor_capacity);
			vec4 neighbor_pigment = imageLoad(mobile_read, neighbor_pos);

			float neighbor_mass = alpha_to_mass(neighbor_pigment.a);
			float neighbor_movable_mass = neighbor_mass * (neighbor_movable / max(neighbor_water, 1e-6));
			float incoming_mass = neighbor_movable_mass * (water_in / max(neighbor_movable, 1e-6));

			vec4 incoming_pigment = vec4(neighbor_pigment.rgb, mass_to_alpha(incoming_mass));
			inflow_pigment_accum = mix_pigments_optical(inflow_pigment_accum, incoming_pigment);
		}
	}

	// From RIGHT neighbor (their LEFT outflow)
	if (pos.x < params.canvas_width - 1) {
		ivec2 neighbor_pos = pos + ivec2(1, 0);
		vec4 neighbor_flows = final_outflows_at(neighbor_pos);
		float water_in = neighbor_flows.y; // Their left outflow

		if (water_in > 0.0) {
			total_inflow_water += water_in;
			inflow_from_right = water_in;

			float neighbor_water = imageLoad(water_read, neighbor_pos).r;
			float neighbor_capacity = imageLoad(absorbency_map, neighbor_pos).r;
			float neighbor_movable = max(0.0, neighbor_water - neighbor_capacity);
			vec4 neighbor_pigment = imageLoad(mobile_read, neighbor_pos);

			float neighbor_mass = alpha_to_mass(neighbor_pigment.a);
			float neighbor_movable_mass = neighbor_mass * (neighbor_movable / max(neighbor_water, 1e-6));
			float incoming_mass = neighbor_movable_mass * (water_in / max(neighbor_movable, 1e-6));

			vec4 incoming_pigment = vec4(neighbor_pigment.rgb, mass_to_alpha(incoming_mass));
			inflow_pigment_accum = mix_pigments_optical(inflow_pigment_accum, incoming_pigment);
		}
	}

	// From UP neighbor (their DOWN outflow)
	if (pos.y > 0) {
		ivec2 neighbor_pos = pos + ivec2(0, -1);
		vec4 neighbor_flows = final_outflows_at(neighbor_pos);
		float water_in = neighbor_flows.z; // Their down outflow

		if (water_in > 0.0) {
			total_inflow_water += water_in;
			inflow_from_up = water_in;

			float neighbor_water = imageLoad(water_read, neighbor_pos).r;
			float neighbor_capacity = imageLoad(absorbency_map, neighbor_pos).r;
			float neighbor_movable = max(0.0, neighbor_water - neighbor_capacity);
			vec4 neighbor_pigment = imageLoad(mobile_read, neighbor_pos);

			float neighbor_mass = alpha_to_mass(neighbor_pigment.a);
			float neighbor_movable_mass = neighbor_mass * (neighbor_movable / max(neighbor_water, 1e-6));
			float incoming_mass = neighbor_movable_mass * (water_in / max(neighbor_movable, 1e-6));

			vec4 incoming_pigment = vec4(neighbor_pigment.rgb, mass_to_alpha(incoming_mass));
			inflow_pigment_accum = mix_pigments_optical(inflow_pigment_accum, incoming_pigment);
		}
	}

	// From DOWN neighbor (their UP outflow)
	if (pos.y < params.canvas_height - 1) {
		ivec2 neighbor_pos = pos + ivec2(0, 1);
		vec4 neighbor_flows = final_outflows_at(neighbor_pos);
		float water_in = neighbor_flows.w; // Their up outflow

		if (water_in > 0.0) {
			total_inflow_water += water_in;
			inflow_from_down = water_in;

			float neighbor_water = imageLoad(water_read, neighbor_pos).r;
			float neighbor_capacity = imageLoad(absorbency_map, neighbor_pos).r;
			float neighbor_movable = max(0.0, neighbor_water - neighbor_capacity);
			vec4 neighbor_pigment = imageLoad(mobile_read, neighbor_pos);

			float neighbor_mass = alpha_to_mass(neighbor_pigment.a);
			float neighbor_movable_mass = neighbor_mass * (neighbor_movable / max(neighbor_water, 1e-6));
			float incoming_mass = neighbor_movable_mass * (water_in / max(neighbor_movable, 1e-6));

			vec4 incoming_pigment = vec4(neighbor_pigment.rgb, mass_to_alpha(incoming_mass));
			inflow_pigment_accum = mix_pigments_optical(inflow_pigment_accum, incoming_pigment);
		}
	}

	// --- PART 3: Finalize and write results ---
	float final_water = water_staying + total_inflow_water;
	vec4 final_pigment = mix_pigments_optical(pigment_staying, inflow_pigment_accum);

	imageStore(water_write, pos, vec4(final_water, 0.0, 0.0, 0.0));
	imageStore(mobile_write, pos, final_pigment);

	// Write inertia memory (RGBA = inflow from right, left, down, up)
	imageStore(inertia_write, pos, vec4(inflow_from_right, inflow_from_left, inflow_from_down, inflow_from_up));
}
