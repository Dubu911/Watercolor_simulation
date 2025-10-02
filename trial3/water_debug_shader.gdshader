// skyblue scale
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

// grey scale
//shader_type canvas_item;
//
//// The color of the paper when it's fully saturated with water.
//// A medium gray (0.5) is a good starting point. 0.0 is black, 1.0 is white.
//uniform float wet_color_cap : hint_range(0.0, 1.0) = 0.5;
//
//void fragment() {
	//// Get the water amount from the texture's red channel.
	//float water_amount = texture(TEXTURE, UV).r;
//
	//// Calculate the grayscale value.
	//// We mix between 1.0 (white, for dry) and our gray cap color.
	//// As water_amount goes from 0.0 to 1.0, gray_value goes from 1.0 down to wet_color_cap.
	//float gray_value = mix(1.0, wet_color_cap, water_amount);
//
	//// Create the final grayscale color.
	//vec3 final_rgb = vec3(gray_value);
//
	//// The final color uses the calculated gray for RGB.
	//// We use water_amount as the alpha to give the wet spot a soft, feathered edge.
	//COLOR = vec4(final_rgb, water_amount);
//}