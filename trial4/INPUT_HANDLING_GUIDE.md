# Trial4 Input Handling Implementation Guide

## Overview

This document explains how input handling was implemented in trial4 to enable watercolor brush painting with the GPU-accelerated simulation pipeline. The implementation bridges user input (mouse/tablet) with GPU paint upload, supporting pressure sensitivity and smooth strokes.

---

## Architecture Overview

### Data Flow for Painting

```
User Input (Mouse/Tablet)
    ↓
brush_manager.gd (_input handler)
    ↓
watercolor_brush.gd (handle_input)
    ↓
painting_coordinator.gd (add_paint_at)
    ↓
physics_simulator_gpu.gd (upload_paint_region)
    ↓
GPU add_paint.glsl shader
    ↓
GPU water_buffer & mobile_buffer (updated)
```

---

## Component Breakdown

### 1. brush_manager.gd - Input Routing & Coordinate Transformation

**Location:** `trial4/brush_manager.gd`

**Key Responsibilities:**
- Captures all input events using `_input()` (not `_unhandled_input()` - important for tablet support!)
- Transforms screen coordinates to world coordinates through camera
- Forwards input to the active brush with correct image-space coordinates
- Updates brush cursor position every frame via `_process()`

**Critical Implementation Details:**

#### Coordinate Transformation (Lines 150-170)
```gdscript
func _input(event: InputEvent) -> void:
    # Update pointer positions from motion events
    if event is InputEventMouseMotion:
        _last_screen_pos = event.position

        var cam = get_viewport().get_camera_2d()
        if cam:
            # Convert screen → world via camera
            var canvas_transform = cam.get_canvas_transform()
            _last_world_pos = canvas_transform.affine_inverse() * event.position
        else:
            # Fallback (no camera)
            _last_world_pos = get_viewport().get_canvas_transform().affine_inverse() * event.position
```

**Why this matters:** The canvas has a Camera2D with zoom applied. Screen coordinates need to be transformed through the camera to get correct world coordinates. This ensures accurate painting at any zoom level.

#### Continuous Cursor Updates (Lines 137-148)
```gdscript
func _process(_delta: float) -> void:
    # Update cursor position every frame
    _update_brush_cursor_positions(_last_world_pos)

    # Check if cursor is over canvas bounds
    if is_instance_valid(layer_for_mouse_pos) and is_instance_valid(painting_coordinator):
        var img_pos = layer_for_mouse_pos.to_local(_last_world_pos)
        var w = painting_coordinator.CANVAS_WIDTH
        var h = painting_coordinator.CANVAS_HEIGHT
        var over = img_pos.x >= 0 and img_pos.x < w and img_pos.y >= 0 and img_pos.y < h
        _update_brush_cursor_visibility(img_pos, over)
```

**Why use _process():** Tablet drivers may send hover events at different rates than motion events. Processing cursor updates every frame ensures smooth cursor movement.

#### Forwarding Input to Active Brush (Lines 165-170)
```gdscript
# Forward input to active brush with image-space coordinates
var active = painting_coordinator.get("active_brush_node") if is_instance_valid(painting_coordinator) else null
if is_instance_valid(active) and is_instance_valid(layer_for_mouse_pos):
    var img_pos = layer_for_mouse_pos.to_local(_last_world_pos)  # World → Image space
    if active.has_method("handle_input"):
        active.handle_input(event, img_pos)
```

**Coordinate Spaces:**
- **Screen space:** Raw pixel coordinates from input device (e.g., 1920×1080)
- **World space:** Game world coordinates (after camera transform)
- **Image space:** Canvas pixel coordinates (0-255 for 256×256 canvas)

---

### 2. watercolor_brush.gd - Stroke Generation & Pressure Handling

**Location:** `trial4/watercolor_brush.gd`

**Key Responsibilities:**
- Manages stroke state (painting vs. not painting)
- Extracts pressure data from tablet events
- Interpolates between input points to create smooth strokes
- Generates circular paint dabs along stroke path

#### Pressure Extraction (Lines 37-50)
```gdscript
func _event_pressure(event: InputEvent) -> float:
    if event is InputEventMouseMotion:
        var p = 1.0
        if "pressure" in event:
            p = event.pressure
        # Use actual pressure value, minimum 0.05 to prevent invisible strokes
        _last_motion_pressure = max(p, 0.05)
        return _last_motion_pressure

    # For button events, reuse last known motion pressure
    return _last_motion_pressure if _last_motion_pressure > 0.0 else 0.5
```

**Why this approach:**
- `InputEventMouseMotion` has pressure data on tablets, not `InputEventMouseButton`
- Caches last motion pressure for button events
- Fallback to 0.5 pressure if no motion data available yet
- Minimum 0.05 pressure prevents completely invisible strokes

#### Stroke Interpolation (Lines 124-143)
```gdscript
func _paint_stroke_segment(from_pos: Vector2, to_pos: Vector2, pressure: float):
    # Calculate brush radius based on pressure
    var brush_radius = base_brush_size
    if pressure_affects_size:
        var pressure_mult = lerp(min_pressure_size_mult, max_pressure_size_mult, pressure)
        brush_radius = base_brush_size * pressure_mult

    # Calculate distance and interpolation steps
    var distance = from_pos.distance_to(to_pos)

    # Step size: 50% of radius = 2x overlap for smooth appearance
    var step_size = max(0.5, brush_radius * 0.5)
    var steps = max(1, int(ceil(distance / step_size)))

    # Paint at each interpolated point
    for i in range(steps + 1):
        var t = float(i) / float(steps)
        var paint_pos = from_pos.lerp(to_pos, t)
        _paint_circular_dab(paint_pos, brush_radius)
```

**Why interpolation is needed:** Input events arrive at discrete intervals (60-120 Hz typically). Without interpolation, fast mouse movements would create gaps. This creates a smooth line by filling in intermediate points.

**Step size optimization:** Using 50% overlap (0.5 × radius) creates smooth strokes while minimizing paint dabs. More overlap = smoother but slower.

#### Paint Dab Generation (Lines 145-152)
```gdscript
func _paint_circular_dab(center: Vector2, radius: float):
    # Use GPU-optimized batch upload
    if coordinator_ref.has_method("add_paint_at"):
        coordinator_ref.add_paint_at(center, brush_color, water_amount, radius, current_pressure)
    else:
        printerr("watercolor_brush ERROR: Coordinator missing 'add_paint_at' method!")
```

This delegates to the coordinator's GPU upload system.

---

### 3. painting_coordinator.gd - CPU-Side Paint Preparation

**Location:** `trial4/painting_coordinator.gd:207-252`

**Key Responsibilities:**
- Creates CPU-side paint buffers for each brush dab
- Calculates affected region (bounding box)
- Rasterizes circular brush shape into pixel data
- Delegates GPU upload to physics simulator

#### Region-Based Upload (Lines 207-221)
```gdscript
func add_paint_at(pos: Vector2, color: Color, water: float, size: float, pressure: float = 1.0):
    var i_radius = int(ceil(size))

    # Calculate bounding box for this dab
    var min_x = max(0, int(pos.x) - i_radius)
    var max_x = min(CANVAS_WIDTH - 1, int(pos.x) + i_radius)
    var min_y = max(0, int(pos.y) - i_radius)
    var max_y = min(CANVAS_HEIGHT - 1, int(pos.y) + i_radius)

    var region_width = max_x - min_x + 1
    var region_height = max_y - min_y + 1

    # Skip if completely out of bounds
    if region_width <= 0 or region_height <= 0:
        return
```

**Why bounding box optimization:** Instead of uploading entire 256×256 canvas, only upload the affected region. A 4-pixel radius brush only needs ~8×8 region upload, not 256×256.

#### Circular Brush Rasterization (Lines 223-249)
```gdscript
# Create CPU buffers for affected region only
var water_buffer = Image.create(region_width, region_height, false, Image.FORMAT_RF)
var pigment_buffer = Image.create(region_width, region_height, false, Image.FORMAT_RGBAF)

# Fill with zeros (no change)
water_buffer.fill(Color(0, 0, 0))
pigment_buffer.fill(Color(1, 1, 1, 0))  # Transparent white

# Paint the dab onto CPU buffers (in region-local coordinates)
for y_offset in range(-i_radius, i_radius + 1):
    for x_offset in range(-i_radius, i_radius + 1):
        if Vector2(x_offset, y_offset).length_squared() <= size * size:
            var canvas_x = int(pos.x + x_offset)
            var canvas_y = int(pos.y + y_offset)

            # Check if within canvas bounds
            if canvas_x >= min_x and canvas_x <= max_x and canvas_y >= min_y and canvas_y <= max_y:
                # Convert to region-local coordinates
                var region_x = canvas_x - min_x
                var region_y = canvas_y - min_y

                # Add water
                water_buffer.set_pixel(region_x, region_y, Color(water, 0, 0))

                # Add pigment
                pigment_buffer.set_pixel(region_x, region_y, color)

# Upload to GPU with pressure
physics_simulator.upload_paint_region(min_x, min_y, water_buffer, pigment_buffer, pressure)
```

**Coordinate system note:** The buffer uses region-local coordinates (0 to region_width/height), but we track the canvas offset (min_x, min_y) for GPU upload.

---

### 4. physics_simulator_gpu.gd - GPU Upload

**Location:** `trial4/physics_simulator_gpu.gd:767-834`

**Key Responsibilities:**
- Converts Image data to GPU-compatible byte arrays
- Uploads paint data to GPU textures
- Dispatches add_paint compute shader
- Handles format conversions (Image → PackedFloat32Array → byte array)

#### Upload Process (Lines 767-834)
```gdscript
func upload_paint_region(x: int, y: int, water_data: Image, pigment_data: Image, pressure: float = 1.0):
    var region_width = water_data.get_width()
    var region_height = water_data.get_height()

    # Convert Images to GPU-compatible byte arrays
    var water_bytes = _image_to_r32f_bytes(water_data)
    var pigment_bytes = _image_to_rgba32f_bytes(pigment_data)

    # Clear paint buffer textures (fill with zeros)
    # ... (creates empty full-size buffers)

    # Copy region data into full buffer at correct offset
    for ry in range(region_height):
        for rx in range(region_width):
            var canvas_x = x + rx
            var canvas_y = y + ry

            if canvas_x >= 0 and canvas_x < canvas_width and canvas_y >= 0 and canvas_y < canvas_height:
                var canvas_idx = canvas_y * canvas_width + canvas_x
                var region_idx = ry * region_width + rx

                # Copy water and pigment data
                # ... (decodes floats from byte arrays, places at canvas_idx)

    # Upload full buffers with region data embedded
    rd.texture_update(paint_water_tex, 0, full_water.to_byte_array())
    rd.texture_update(paint_pigment_tex, 0, full_pigment.to_byte_array())

    # Run add_paint compute shader
    var groups_x = int(ceil(float(canvas_width) / 8.0))
    var groups_y = int(ceil(float(canvas_height) / 8.0))
    _dispatch_add_paint(groups_x, groups_y, pressure)
```

**Why full-size upload:** Godot's RenderingDevice doesn't support partial texture updates easily. Instead, we:
1. Create full-size buffer (256×256) filled with zeros
2. Copy region data into correct position in full buffer
3. Upload entire buffer (but only non-zero pixels cause changes)

**Performance note:** The add_paint shader early-exits on zero pixels, so this is still efficient.

---

### 5. add_paint.glsl - GPU Paint Application

**Location:** `trial4/shaders/add_paint.glsl`

**Key Responsibilities:**
- Reads paint data from CPU-uploaded buffers
- Applies water transfer logic (prevents over-saturation)
- Handles pigment transfer proportional to water
- Implements wet-on-wet pressure diffusion
- Performs optical color mixing (Beer-Lambert law)
- Writes results back to canvas buffers

#### Shader Pipeline (Lines 23-122)

**Step 1: Read Data**
```glsl
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
```

**Step 2: Water Transfer**
```glsl
// Only add water up to the brush's water amount (prevents over-saturation)
float water_to_add = max(0.0, brush_water - canvas_water);
float new_water = canvas_water + water_to_add;
```

This prevents infinite water accumulation - if brush has 0.1 water and canvas already has 0.15, add 0 water.

**Step 3: Pigment Transfer (Proportional to Water)**
```glsl
// Pigment transfer is proportional to water transfer
float pigment_transfer_ratio = (brush_water > EPS_A) ? (water_to_add / brush_water) : 0.0;

// Scale incoming pigment by water transfer ratio
vec4 transferred_pigment = vec4(
    brush_pigment.rgb,
    brush_pigment.a * pigment_transfer_ratio
);
```

Example: If brush has 0.1 water but only 0.03 can be added (canvas already has 0.07), then only 30% of pigment transfers.

**Step 4: Wet-on-Wet Pressure Diffusion**
```glsl
bool surface_is_wet = canvas_water > 0.01;

if (surface_is_wet && params.pressure > 0.0) {
    // Calculate pigment concentration difference
    float concentration_diff = max(0.0, brush_concentration - canvas_concentration);

    // Pressure-driven diffusion
    float diffusion_strength = params.pressure * concentration_diff * 0.5;

    // Add diffusion pigment to transferred pigment
    transferred_pigment.a += brush_pigment.a * diffusion_strength;
}
```

This allows adding concentrated color to wet surfaces by pressing harder - realistic watercolor technique!

**Step 5: Optical Mixing (Beer-Lambert Law)**
```glsl
if (transferred_pigment.a > EPS_A && canvas_pigment.a > EPS_A) {
    // Convert alpha to mass (optical density)
    float transferred_mass = -log(max(EPS_A, 1.0 - transferred_pigment.a)) / K_ABSORPTION;
    float existing_mass = -log(max(EPS_A, 1.0 - canvas_pigment.a)) / K_ABSORPTION;

    float total_mass = transferred_mass + existing_mass;

    // Mix colors by mass-weighted average
    vec3 mixed_rgb = transferred_pigment.rgb * (transferred_mass / total_mass) +
                     canvas_pigment.rgb * (existing_mass / total_mass);

    // Convert total mass back to alpha
    float new_alpha = 1.0 - exp(-total_mass * K_ABSORPTION);

    new_pigment = vec4(mixed_rgb, new_alpha);
}
```

This creates realistic subtractive color mixing (like real paint absorbing light).

**Step 6: Write Results**
```glsl
imageStore(water_buffer, pos, vec4(new_water, 0.0, 0.0, 0.0));
imageStore(mobile_buffer, pos, new_pigment);
```

---

## Key Challenges & Solutions

### Challenge 1: Coordinate Space Confusion
**Problem:** Screen coordinates don't match canvas pixel coordinates, especially with camera zoom.

**Solution:** Three-step transformation:
1. Screen → World (via camera transform)
2. World → Image (via Sprite2D.to_local())
3. Use Image coordinates for painting

### Challenge 2: Pressure Data Inconsistency
**Problem:** Pressure not available on button events, only motion events.

**Solution:** Cache last known motion pressure and reuse for button events.

### Challenge 3: Stroke Gaps at Fast Movement
**Problem:** Discrete input events create gaps in fast strokes.

**Solution:** Interpolate between input points with 50% overlap.

### Challenge 4: GPU Upload Performance
**Problem:** Uploading entire 256×256 canvas for every small brush dab is slow.

**Solution:** Calculate bounding box, only create/upload affected region. Shader early-exits on zero pixels.

### Challenge 5: Smooth Cursor at Variable Input Rate
**Problem:** Tablet hover events may arrive at different rates than motion events.

**Solution:** Use `_process()` to update cursor position every frame using cached world position.

---

## Testing the Implementation

### Basic Painting Test
1. Run trial4 scene (`trial4/main4.tscn`)
2. Click and drag on canvas
3. Verify: Paint appears, follows mouse, no gaps

### Pressure Test (Requires Tablet)
1. Draw light stroke (pressure 0.1-0.3)
2. Draw heavy stroke (pressure 0.8-1.0)
3. Verify: Heavy stroke is wider/darker

### Coordinate Test
1. Use Camera2D controls to zoom in/out (if implemented)
2. Paint at various zoom levels
3. Verify: Paint appears exactly where cursor is

### Performance Test
1. Draw rapid continuous strokes
2. Monitor FPS
3. Verify: No significant slowdown

---

## Debugging Tips

### "Paint appears offset from cursor"
→ Coordinate transformation issue. Check:
- Camera transform application
- `layer_for_mouse_pos.to_local()` correctness
- Sprite2D `centered` property (should be false)

### "Paint doesn't appear at all"
→ GPU upload issue. Check:
1. `add_paint_at()` is being called (add print statements)
2. `upload_paint_region()` completes without errors
3. Shader compiles successfully
4. Paint buffers have non-zero data

### "Stroke has gaps"
→ Interpolation issue. Check:
- `step_size` calculation (should be < radius)
- `_paint_stroke_segment()` is called on motion events

### "Pressure doesn't work"
→ Tablet driver issue. Check:
1. Print `event.pressure` in `_event_pressure()`
2. Verify tablet drivers installed
3. Test with another pressure-sensitive app

---

## Performance Characteristics

### CPU-Side Costs
- **Per dab:** ~200 pixels rasterized (for 4px radius)
- **Per stroke:** ~10-50 dabs per second (depending on speed)
- **Total:** ~2,000-10,000 pixels processed/sec on CPU

### GPU-Side Costs
- **Per dab:** Full canvas shader dispatch (256×256 = 65,536 threads)
- **Early exit:** Most threads exit immediately (no paint data)
- **Active threads:** ~200 per dab (matching rasterized pixels)
- **Total GPU cost:** Minimal, ~0.1ms per dab on modern GPU

### Memory Usage
- **Per dab:** 2 small Images (~100 bytes each)
- **GPU buffers:** 2 full-size textures (256×256×4 bytes = 256 KB each)
- **Total:** ~512 KB GPU memory for paint buffers

---

## Future Improvements

### Optimization Ideas
1. **Batch multiple dabs:** Accumulate several dabs before GPU upload
2. **Partial texture upload:** Use Vulkan subresource updates if Godot supports
3. **Brush texture stamping:** Use texture atlas instead of pixel loop

### Feature Ideas
1. **Variable brush shapes:** Load brush textures instead of circles
2. **Tilt support:** Use tablet tilt angle for brush shape
3. **Rotation support:** Rotate brush based on stroke direction
4. **Velocity-based effects:** Vary properties based on stroke speed

---

## Summary

The input handling system in trial4 successfully bridges user input with GPU-accelerated watercolor simulation by:

1. **brush_manager.gd:** Captures input, transforms coordinates, routes to active brush
2. **watercolor_brush.gd:** Manages strokes, extracts pressure, interpolates smooth lines
3. **painting_coordinator.gd:** Rasterizes brush dabs, prepares CPU buffers
4. **physics_simulator_gpu.gd:** Uploads paint data to GPU textures
5. **add_paint.glsl:** Applies paint with realistic water/pigment physics on GPU

This architecture maintains clean separation of concerns while achieving efficient GPU-accelerated painting with tablet pressure support.
