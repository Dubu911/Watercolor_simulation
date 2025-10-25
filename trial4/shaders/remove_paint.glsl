#version 450

// Pigment removal shader - removes paint from mobile layer first, then static layer
// Preserves hue (RGB), only reduces mass (alpha)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input texture (removal mask - how much pigment mass to remove per pixel)
layout(set = 0, binding = 0, r32f) uniform readonly image2D removal_mask;

// Output textures (canvas layers - read and write)
layout(set = 0, binding = 1, rgba32f) uniform image2D mobile_buffer;
layout(set = 0, binding = 2, rgba32f) uniform image2D static_buffer;

layout(push_constant, std430) uniform Params {
	uint canvas_width;
	uint canvas_height;
	float k_absorption;
	float eps_a;
} params;

// Helper: Convert alpha to mass
float alpha_to_mass(float alpha) {
	return -log(max(1.0 - alpha, params.eps_a)) / params.k_absorption;
}

// Helper: Convert mass to alpha
float mass_to_alpha(float mass) {
	return 1.0 - exp(-params.k_absorption * mass);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= params.canvas_width || pos.y >= params.canvas_height) return;

	// Read how much pigment mass to remove at this pixel
	float removal_amount = imageLoad(removal_mask, pos).r;

	// Skip if no removal at this pixel
	if (removal_amount <= 0.0) {
		return;
	}

	// Read existing canvas state
	vec4 mobile_pigment = imageLoad(mobile_buffer, pos);
	vec4 static_pigment = imageLoad(static_buffer, pos);

	// Convert alpha to mass
	float mobile_mass = alpha_to_mass(mobile_pigment.a);
	float static_mass = alpha_to_mass(static_pigment.a);

	// PRIORITY 1: Remove from mobile layer first
	float mobile_mass_removed = min(mobile_mass, removal_amount);
	float remaining_removal = removal_amount - mobile_mass_removed;

	float new_mobile_mass = max(0.0, mobile_mass - mobile_mass_removed);
	vec4 new_mobile_pigment;

	if (new_mobile_mass <= 0.0) {
		// Mobile layer is now empty
		new_mobile_pigment = vec4(1.0, 1.0, 1.0, 0.0);
	} else {
		// Preserve hue, only reduce alpha (mass)
		new_mobile_pigment = vec4(mobile_pigment.rgb, mass_to_alpha(new_mobile_mass));
	}

	// PRIORITY 2: If mobile is exhausted, remove from static layer
	vec4 new_static_pigment = static_pigment;

	if (remaining_removal > 0.0 && static_mass > 0.0) {
		float static_mass_removed = min(static_mass, remaining_removal);
		float new_static_mass = max(0.0, static_mass - static_mass_removed);

		if (new_static_mass <= 0.0) {
			// Static layer is now empty
			new_static_pigment = vec4(1.0, 1.0, 1.0, 0.0);
		} else {
			// Preserve hue, only reduce alpha (mass)
			new_static_pigment = vec4(static_pigment.rgb, mass_to_alpha(new_static_mass));
		}
	}

	// Write results back
	imageStore(mobile_buffer, pos, new_mobile_pigment);
	imageStore(static_buffer, pos, new_static_pigment);
}
