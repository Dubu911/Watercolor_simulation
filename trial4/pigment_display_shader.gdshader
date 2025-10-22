shader_type canvas_item;

// This shader displays pigment layers (mobile and static)
// The alpha channel represents pigment concentration/mass
// We need to display it as a transparent layer that can blend with other layers

void fragment() {
	vec4 pigment = texture(TEXTURE, UV);

	// pigment.rgb = hue (which color the pigment is)
	// pigment.a = concentration (how much pigment mass)

	if (pigment.a < 0.0001) {
		// No pigment - fully transparent
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Output the pigment color with its alpha as transparency
		// This allows proper blending when multiple layers are visible
		// The pigment color is already encoded in RGB
		// The alpha represents how opaque this pigment is
		COLOR = vec4(pigment.rgb, pigment.a);
	}
}
