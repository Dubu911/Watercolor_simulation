#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input textures (paint to add - from brush)
layout(set = 0, binding = 0, r32f) uniform readonly image2D paint_water;
layout(set = 0, binding = 1, rgba32f) uniform readonly image2D paint_pigment;

// Output textures (existing canvas data - read and write)
layout(set = 0, binding = 2, r32f) uniform image2D water_buffer;
layout(set = 0, binding = 3, rgba32f) uniform image2D mobile_buffer;

layout(push_constant, std430) uniform Params {
    uint canvas_width;
    uint canvas_height;
    float pressure;      // Brush pressure (0.0-1.0)
    float padding;
} params;

const float K_ABSORPTION = 0.5;
const float EPS_A = 0.000001;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= params.canvas_width || pos.y >= params.canvas_height) return;

    // Read brush paint data
    float brush_water = imageLoad(paint_water, pos).r;
    vec4 brush_pigment = imageLoad(paint_pigment, pos);

    // Skip if no paint from brush at this pixel
    if (brush_water < EPS_A && brush_pigment.a < EPS_A) {
        return;
    }

    // Read existing canvas state
    float canvas_water = imageLoad(water_buffer, pos).r;
    vec4 canvas_pigment = imageLoad(mobile_buffer, pos);

    // === WATER TRANSFER (matching trial3) ===
    // Only add water up to the brush's water amount (prevents over-saturation)
    float water_to_add = max(0.0, brush_water - canvas_water);
    float new_water = canvas_water + water_to_add;

    // === PIGMENT TRANSFER (matching trial3) ===
    // Pigment transfer is proportional to water transfer
    float pigment_transfer_ratio = (brush_water > EPS_A) ? (water_to_add / brush_water) : 0.0;

    // Scale incoming pigment by water transfer ratio
    vec4 transferred_pigment = vec4(
        brush_pigment.rgb,
        brush_pigment.a * pigment_transfer_ratio
    );

    // === WET-ON-WET TECHNIQUE: Pressure-based pigment diffusion ===
    // When surface is wet and brush has concentrated pigment, allow diffusion
    bool surface_is_wet = canvas_water > 0.01;

    if (surface_is_wet && params.pressure > 0.0) {
        // Calculate pigment concentration difference
        float brush_concentration = brush_pigment.a;
        float canvas_concentration = canvas_pigment.a;
        float concentration_diff = max(0.0, brush_concentration - canvas_concentration);

        // Pressure-driven diffusion
        float diffusion_strength = params.pressure * concentration_diff * 0.5;

        // Create diffusion pigment
        vec4 diffusion_pigment = vec4(
            brush_pigment.rgb,
            brush_pigment.a * diffusion_strength
        );

        // Add diffusion to transferred pigment
        transferred_pigment.a += diffusion_pigment.a;

        // Mix colors proportionally (weight by mass)
        if (transferred_pigment.a > EPS_A) {
            float total_mass = transferred_pigment.a;
            float water_weight = (brush_pigment.a * pigment_transfer_ratio) / total_mass;
            float diffusion_weight = diffusion_pigment.a / total_mass;

            transferred_pigment.rgb = brush_pigment.rgb * water_weight +
                                     diffusion_pigment.rgb * diffusion_weight;
        }
    }

    // === OPTICAL MIXING (Beer-Lambert) ===
    vec4 new_pigment;

    if (transferred_pigment.a > EPS_A && canvas_pigment.a > EPS_A) {
        // Both have pigment - optical mix
        float transferred_mass = -log(max(EPS_A, 1.0 - transferred_pigment.a)) / K_ABSORPTION;
        float existing_mass = -log(max(EPS_A, 1.0 - canvas_pigment.a)) / K_ABSORPTION;

        float total_mass = transferred_mass + existing_mass;

        // Weight by mass for color mixing
        float transferred_weight = transferred_mass / total_mass;
        float existing_weight = existing_mass / total_mass;

        vec3 mixed_rgb = transferred_pigment.rgb * transferred_weight +
                        canvas_pigment.rgb * existing_weight;

        // Convert total mass back to alpha
        float total_optical_density = total_mass * K_ABSORPTION;
        float new_alpha = 1.0 - exp(-total_optical_density);
        new_alpha = clamp(new_alpha, 0.0, 1.0);

        new_pigment = vec4(mixed_rgb, new_alpha);
    } else if (transferred_pigment.a > EPS_A) {
        // Only transferred pigment
        new_pigment = transferred_pigment;
    } else {
        // Only existing pigment (or none)
        new_pigment = canvas_pigment;
    }

    // Write results back
    imageStore(water_buffer, pos, vec4(new_water, 0.0, 0.0, 0.0));
    imageStore(mobile_buffer, pos, new_pigment);
}
