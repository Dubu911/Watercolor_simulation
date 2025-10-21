#version 450

// Pigment deposition from mobile (wet) to static (dry) layer
// Wet deposition rate depends on water amount and paper absorbency
// Dry pixels instantly deposit all pigment

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Textures
layout(set = 0, binding = 0, r32f) uniform readonly image2D water_read;
layout(set = 0, binding = 1, rgba32f) uniform readonly image2D mobile_read;
layout(set = 0, binding = 2, rgba32f) uniform writeonly image2D mobile_write;
layout(set = 0, binding = 3, rgba32f) uniform readonly image2D static_read;
layout(set = 0, binding = 4, rgba32f) uniform writeonly image2D static_write;
layout(set = 0, binding = 5, r32f) uniform readonly image2D absorbency_map;

// Push constants
layout(push_constant, std430) uniform Params {
	float delta;
	float k_deposit_base;
	float w_scale;
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
	float absorbency = imageLoad(absorbency_map, pos).r;
	vec4 mobile_color = imageLoad(mobile_read, pos);
	vec4 static_color = imageLoad(static_read, pos);

	float mobile_mass = alpha_to_mass(mobile_color.a);

	// Nothing to deposit
	if (mobile_mass <= 0.0) {
		imageStore(mobile_write, pos, mobile_color);
		imageStore(static_write, pos, static_color);
		return;
	}

	// DRY DEPOSITION: Instant snap to paper
	if (water_here < params.dry_pixel_limit) {
		vec4 deposit_color = vec4(mobile_color.rgb, mass_to_alpha(mobile_mass));
		vec4 new_static = mix_pigments_optical(deposit_color, static_color);

		imageStore(static_write, pos, new_static);
		imageStore(mobile_write, pos, vec4(1.0, 1.0, 1.0, 0.0)); // Clear mobile
		return;
	}

	// WET DEPOSITION: Gradual deposition based on water and absorbency
	// Square water_factor to make deposition much slower when lots of water
	float water_factor = params.w_scale / (water_here + params.w_scale);
	water_factor = water_factor * water_factor;

	float rate = params.k_deposit_base * max(0.0, absorbency) * water_factor;
	float deposit_fraction = 1.0 - exp(-rate * params.delta);
	deposit_fraction = clamp(deposit_fraction, 0.0, 1.0);

	float deposit_mass = mobile_mass * deposit_fraction;

	if (deposit_mass <= 0.0) {
		// No significant deposition
		imageStore(mobile_write, pos, mobile_color);
		imageStore(static_write, pos, static_color);
		return;
	}

	float remaining_mass = max(0.0, mobile_mass - deposit_mass);

	// Preserve hue
	vec4 deposit_color = vec4(mobile_color.rgb, mass_to_alpha(deposit_mass));
	vec4 remaining_color = vec4(mobile_color.rgb, mass_to_alpha(remaining_mass));

	// Mix deposit into static layer
	vec4 new_static = mix_pigments_optical(deposit_color, static_color);

	imageStore(static_write, pos, new_static);
	imageStore(mobile_write, pos, remaining_color);
}
