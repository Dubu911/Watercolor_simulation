// Fragment shader for displaying GPU textures directly
// Samples from compute shader output textures
// No CPU readback needed

shader_type canvas_item;

// Texture sampler (will be bound to GPU texture RID)
uniform sampler2D gpu_texture : filter_nearest;

// Layer type for different rendering modes
uniform int layer_type = 0; // 0=mobile/static RGBA, 1=water R32F debug

void fragment() {
	vec4 tex_color = texture(gpu_texture, UV);

	if (layer_type == 0) {
		// RGBA layer (mobile or static)
		COLOR = tex_color;
	} else if (layer_type == 1) {
		// Water layer debug visualization (R32F to grayscale)
		float water_amount = tex_color.r;
		// Visualize water: 0.0 = black, 0.5 = gray, 1.0+ = white
		float intensity = clamp(water_amount * 2.0, 0.0, 1.0);
		COLOR = vec4(vec3(intensity), 1.0);
	}
}
