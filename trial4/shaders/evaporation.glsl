#version 450

// Evaporation compute shader
// Calculates water evaporation based on exposed surface area

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Uniforms
layout(set = 0, binding = 0, r32f) uniform readonly image2D water_read;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D water_write;

layout(push_constant, std430) uniform Params {
	float delta;
	float evaporation_const;
	float dry_pixel_limit;
	uint canvas_width;
	uint canvas_height;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);

	// Bounds check
	if (pos.x >= params.canvas_width || pos.y >= params.canvas_height) {
		return;
	}

	float current_water = imageLoad(water_read, pos).r;

	// Get neighbor water amounts
	float water_right = 0.0;
	float water_left = 0.0;
	float water_up = 0.0;
	float water_down = 0.0;

	if (pos.x < params.canvas_width - 1) {
		water_right = imageLoad(water_read, pos + ivec2(1, 0)).r;
	}
	if (pos.x > 0) {
		water_left = imageLoad(water_read, pos + ivec2(-1, 0)).r;
	}
	if (pos.y > 0) {
		water_up = imageLoad(water_read, pos + ivec2(0, -1)).r;
	}
	if (pos.y < params.canvas_height - 1) {
		water_down = imageLoad(water_read, pos + ivec2(0, 1)).r;
	}

	// Calculate exposed surface area
	float total_surface = 0.1; // default value

	float diff_right = current_water - water_right;
	float diff_left = current_water - water_left;
	float diff_up = current_water - water_up;
	float diff_down = current_water - water_down;

	if (diff_right > 0.0) total_surface += diff_right;
	if (diff_left > 0.0) total_surface += diff_left;
	if (diff_up > 0.0) total_surface += diff_up;
	if (diff_down > 0.0) total_surface += diff_down;

	// Calculate evaporation
	float evaporation_amount = total_surface * params.evaporation_const * params.delta;
	float new_water = max(0.0, current_water - evaporation_amount);

	// Write result
	imageStore(water_write, pos, vec4(new_water, 0.0, 0.0, 0.0));
}
