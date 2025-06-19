shader_type canvas_item;

uniform vec4 debug_color : source_color = vec4(0.255, 0.412, 0.882, 1.0); // sky blue

void fragment() {
	// Get the original color from the texture at this pixel.
	// For the FORMAT_RF water_image, the water amount is in the 'r' (red) channel.
	vec4 original_color = texture(TEXTURE, UV);
	float water_amount = original_color.r;

	// Create the new color for display.
	// We use the RGB from our sky blue debug_color.
	// We use the water_amount (from the red channel) as the new alpha.
	COLOR = vec4(debug_color.rgb, water_amount);
}