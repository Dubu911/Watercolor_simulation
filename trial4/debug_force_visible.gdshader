shader_type canvas_item;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // Force RGB to be visible, ignore alpha completely
    COLOR = vec4(tex.rgb, 1.0);
}
