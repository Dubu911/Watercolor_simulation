#version 450

// Pigment diffusion on wet surface
// Uses concentration gradient and water contact area
// INFLOW MODEL for GPU parallelization

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Textures
layout(set = 0, binding = 0, r32f) uniform readonly image2D water_read;
layout(set = 0, binding = 1, rgba32f) uniform readonly image2D mobile_read;
layout(set = 0, binding = 2, rgba32f) uniform writeonly image2D mobile_write;

// Push constants
layout(push_constant, std430) uniform Params {
	float delta;
	float diffusion_rate;
	float diffusion_limiter;
	float dry_pixel_limit;
	float k_absorption;
	float eps_a;
	uint canvas_width;
	uint canvas_height;
} params;

// Helper: Convert alpha to mass
float alpha_to_mass(float alpha) {
	return -log(max(1.0 - alpha, params.eps_a)) / params.k_absorption;
}

// Helper: Convert mass to alpha
float mass_to_alpha(float mass) {
	return 1.0 - exp(-params.k_absorption * mass);
}

// Helper: Optical mixing
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

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);

	if (pos.x >= params.canvas_width || pos.y >= params.canvas_height) {
		return;
	}

	float water_here = imageLoad(water_read, pos).r;
	vec4 pigment_here = imageLoad(mobile_read, pos);
	float mass_here = alpha_to_mass(pigment_here.a);

	// Skip diffusion if dry
	if (water_here < params.dry_pixel_limit) {
		imageStore(mobile_write, pos, pigment_here);
		return;
	}

	// Start with current state
	float final_mass = mass_here;
	vec3 final_hue = pigment_here.rgb;

	float D_base = params.diffusion_rate * params.delta;

	// Check all 4 neighbors
	ivec2 neighbors[4] = ivec2[](
		ivec2(1, 0),   // right
		ivec2(-1, 0),  // left
		ivec2(0, 1),   // down
		ivec2(0, -1)   // up
	);

	for (int i = 0; i < 4; i++) {
		ivec2 neighbor_pos = pos + neighbors[i];

		// Bounds check
		if (neighbor_pos.x < 0 || neighbor_pos.x >= params.canvas_width ||
			neighbor_pos.y < 0 || neighbor_pos.y >= params.canvas_height) {
			continue;
		}

		float water_neighbor = imageLoad(water_read, neighbor_pos).r;
		vec4 pigment_neighbor = imageLoad(mobile_read, neighbor_pos);
		float mass_neighbor = alpha_to_mass(pigment_neighbor.a);

		// Contact area (minimum of two water amounts)
		float contact_area = min(water_here, water_neighbor);

		if (contact_area < params.dry_pixel_limit) {
			continue;
		}

		// Mass gradient (positive = neighbor has more, flows TO here)
		float mass_gradient = mass_neighbor - mass_here;
		float flux = D_base * contact_area * mass_gradient;

		if (flux > 0.0) {
			// Inflow from neighbor
			flux = min(flux, mass_neighbor * params.diffusion_limiter);

			vec4 incoming_pigment = vec4(pigment_neighbor.rgb, mass_to_alpha(flux));
			vec4 current_accumulated = vec4(final_hue, mass_to_alpha(final_mass));

			current_accumulated = mix_pigments_optical(incoming_pigment, current_accumulated);
			final_mass = alpha_to_mass(current_accumulated.a);
			final_hue = current_accumulated.rgb;
		} else if (flux < 0.0) {
			// Outflow to neighbor
			float outflow = min(abs(flux), mass_here * params.diffusion_limiter);
			final_mass -= outflow;
			final_mass = max(0.0, final_mass);
		}
	}

	// Write result
	vec4 final_pigment = vec4(final_hue, mass_to_alpha(final_mass));
	imageStore(mobile_write, pos, final_pigment);
}
