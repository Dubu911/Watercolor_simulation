# GPU Implementation Plan for Trial4

## Overview
Convert trial4 from CPU-based Image processing to GPU compute shaders with direct GPU-to-display rendering. Target: 512x512 canvas, scalable to 3000x3000+.

---

## Architecture Summary

### Current (CPU) Architecture:
```
CPU: Image buffers (64x64)
  ↓
CPU: Physics simulation (for loops)
  ↓
CPU: ImageTexture.update() - copies to GPU every frame
  ↓
GPU: Display via Sprite2D
```

### New (GPU) Architecture:
```
GPU: Texture storage (512x512)
  ↓
GPU: Compute shaders (parallel)
  ↓
GPU: Direct sampling in fragment shaders
  ↓
Display: Zero CPU readback
```

---

## File Structure

### Completed Files ✅

**Compute Shaders (trial4/shaders/):**
1. `evaporation.glsl` - 68 lines
2. `calculate_displacement.glsl` - 195 lines
3. `apply_inflow.glsl` - 350 lines (largest, includes momentum)
4. `diffusion.glsl` - 130 lines
5. `deposition.glsl` - 115 lines

**Display Shader:**
- `display_layer.gdshader` - 20 lines

**GPU Simulator Framework:**
- `physics_simulator_gpu.gd` - 264 lines (partial)

### Files to Modify 📝

1. **trial4/painting_coordinator.gd**
   - Change canvas size to 512x512
   - Replace physics_simulator with physics_simulator_gpu
   - Remove CPU Image buffers for simulation layers
   - Keep pencil_image as CPU (doesn't need physics)
   - Set up Sprite2D materials to sample GPU textures

2. **trial4/main4.tscn**
   - Update painting_coordinator scene to use GPU simulator

3. **trial4/physics_simulator_gpu.gd**
   - Complete shader compilation
   - Complete uniform set creation
   - Implement dispatch logic
   - Implement brush upload

---

## Implementation Details

### Part 1: Shader Compilation (~150 lines)

**Location:** `physics_simulator_gpu.gd::_create_compute_pipelines()`

**Steps:**
1. Load `.glsl` shader source files from disk
2. Compile GLSL → SPIR-V using `RenderingDevice.shader_compile_spirv_from_source()`
3. Create shader RIDs from SPIR-V
4. Create compute pipeline RIDs from shaders

**Code Pattern:**
```gdscript
func _create_compute_pipelines() -> bool:
    # Load evaporation shader
    var evap_file = FileAccess.open("res://trial4/shaders/evaporation.glsl", FileAccess.READ)
    var evap_source = evap_file.get_as_text()
    evap_file.close()

    var shader_source := RDShaderSource.new()
    shader_source.source_compute = evap_source

    var spirv := rd.shader_compile_spirv_from_source(shader_source)
    if spirv.compile_error_compute != "":
        printerr("Evaporation shader error: ", spirv.compile_error_compute)
        return false

    evaporation_shader = rd.shader_create_from_spirv(spirv)
    evaporation_pipeline = rd.compute_pipeline_create(evaporation_shader)

    # Repeat for all 5 shaders...
    return true
```

**Challenges:**
- Shader compilation errors need detailed logging
- SPIR-V binary format is opaque (errors only show at compile time)
- File paths must be correct (res:// protocol)

---

### Part 2: Uniform Set Creation (~200 lines)

**Location:** `physics_simulator_gpu.gd::_create_uniform_sets()`

**What are Uniform Sets?**
They bind GPU textures to shader binding points. Each shader declares bindings:
```glsl
layout(set = 0, binding = 0, r32f) uniform readonly image2D water_read;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D water_write;
```

**Steps for Each Shader:**
1. Create array of `RDUniform` objects (one per binding)
2. Each uniform specifies:
   - Binding number (0, 1, 2, ...)
   - Uniform type (STORAGE_IMAGE)
   - Texture RID(s)
3. Call `rd.uniform_set_create()` with uniform array + pipeline

**Example for Evaporation Shader:**
```gdscript
func _create_uniform_sets() -> bool:
    # Evaporation shader has 2 bindings
    var evap_uniforms := []

    # Binding 0: water_read (readonly)
    var u0 := RDUniform.new()
    u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    u0.binding = 0
    u0.add_id(water_read_tex)
    evap_uniforms.append(u0)

    # Binding 1: water_write (writeonly)
    var u1 := RDUniform.new()
    u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    u1.binding = 1
    u1.add_id(water_write_tex)
    evap_uniforms.append(u1)

    evaporation_uniform_set = rd.uniform_set_create(evap_uniforms, evaporation_shader, 0)

    # Repeat for all 5 shaders with their respective bindings...
```

**Binding Counts per Shader:**
- Evaporation: 2 bindings (water_read, water_write)
- Displacement: 2 bindings (water_read, displacement_map)
- Inflow: 8 bindings (water_read/write, mobile_read/write, absorbency, displacement, inertia_read/write)
- Diffusion: 3 bindings (water_read, mobile_read/write)
- Deposition: 6 bindings (water_read, mobile_read/write, static_read/write, absorbency)

**Challenges:**
- Must match shader binding declarations exactly
- Read/write access must match shader qualifications
- Texture formats must match (R32F vs RGBA32F)

---

### Part 3: GPU Dispatch Logic (~100 lines)

**Location:** `physics_simulator_gpu.gd::run_simulation_step_gpu()`

**What is Dispatching?**
Telling the GPU to run a compute shader across the canvas. For 512x512 canvas with 8x8 work groups:
- Dispatch size: (512/8, 512/8, 1) = (64, 64, 1)
- Total invocations: 64×64 work groups × 8×8 threads = 512×512 threads (one per pixel)

**Simulation Pipeline:**
```
1. Evaporation      (water_read → water_write)
2. Swap water       (water_read ⟷ water_write)
3. Displacement     (water_read → displacement_map)
4. Inflow           (all textures, computes movement + momentum)
5. Swap water/mobile/inertia
6. Diffusion        (mobile_read → mobile_write)
7. Swap mobile
8. Deposition       (mobile/static_read → mobile/static_write)
9. Swap mobile/static
```

**Code Structure:**
```gdscript
func run_simulation_step_gpu(delta: float, g_x: float, g_y: float):
    # Calculate dispatch dimensions
    var groups_x = int(ceil(float(canvas_width) / 8.0))
    var groups_y = int(ceil(float(canvas_height) / 8.0))

    # Create compute list (command buffer)
    var compute_list = rd.compute_list_begin()

    # --- Step 1: Evaporation ---
    rd.compute_list_bind_compute_pipeline(compute_list, evaporation_pipeline)
    rd.compute_list_bind_uniform_set(compute_list, evaporation_uniform_set, 0)

    # Push constants (parameters)
    var evap_params = PackedFloat32Array([
        delta,
        EVAPORATION_CONST,
        DRY_PIXEL_LIMIT,
        float(canvas_width),
        float(canvas_height)
    ])
    rd.compute_list_set_push_constant(compute_list, evap_params.to_byte_array(), evap_params.size() * 4)

    # Dispatch
    rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)

    # Memory barrier (ensure writes finish before next shader reads)
    rd.compute_list_add_barrier(compute_list)

    # End compute list and submit
    rd.compute_list_end()
    rd.submit()
    rd.sync() # Wait for GPU to finish

    # Swap water buffers
    _swap_water_textures()

    # Repeat for all 5 shaders...
```

**Push Constants per Shader:**
Each shader needs different parameters passed as push constants.

**Evaporation:**
- delta, evaporation_const, dry_pixel_limit, canvas_width, canvas_height

**Displacement:**
- gravity_x, gravity_y, S, SP, hold_threshold, energy_loss, dry_pixel_limit, canvas_width, canvas_height

**Inflow:**
- delta, canceling_power, acceleration_power, dry_pixel_limit, k_absorption, eps_a, canvas_width, canvas_height

**Diffusion:**
- delta, diffusion_rate, diffusion_limiter, dry_pixel_limit, k_absorption, eps_a, canvas_width, canvas_height

**Deposition:**
- delta, k_deposit_base, w_scale, dry_pixel_limit, k_absorption, eps_a, canvas_width, canvas_height

**Challenges:**
- Push constant layout must match shader exactly (order, types, padding)
- Barriers required between dependent shaders
- Texture swapping updates uniform sets (need to recreate or use double buffering)

---

### Part 4: Texture Swapping

**Problem:** Shaders read from `_read` texture and write to `_write` texture. After each step, swap references.

**Current approach (won't work):**
```gdscript
# ❌ This swaps GDScript variables but doesn't update uniform sets!
var temp = water_read_tex
water_read_tex = water_write_tex
water_write_tex = temp
```

**Solution A: Recreate Uniform Sets (simpler but slower)**
```gdscript
func _swap_water_textures():
    var temp = water_read_tex
    water_read_tex = water_write_tex
    water_write_tex = temp

    # Recreate uniform sets that use water textures
    _create_evaporation_uniform_set()
    _create_displacement_uniform_set()
    _create_inflow_uniform_set()
```

**Solution B: Dual Uniform Sets (faster, more complex)**
Create two uniform sets for each shader (one for each swap state).
```gdscript
var evaporation_uniform_set_A: RID # water_read=A, water_write=B
var evaporation_uniform_set_B: RID # water_read=B, water_write=A
var use_set_A: bool = true

func _swap_water_textures():
    use_set_A = !use_set_A # Just flip a boolean
```

**Recommendation:** Start with Solution A for simplicity. Optimize to Solution B if performance is an issue.

---

### Part 5: Brush Painting GPU Upload (~80 lines)

**Challenge:** User paints with brush → need to modify GPU textures from CPU.

**Approach:**
1. Keep small CPU-side Image buffer (e.g., 32×32 pixels)
2. User paints into CPU buffer (using existing `paint_watercolor_pixel()` logic)
3. Upload dirty region to GPU using `rd.texture_update()`
4. Clear CPU buffer for next stroke

**Code:**
```gdscript
# CPU-side paint buffer
var paint_buffer_water: Image
var paint_buffer_mobile: Image
var paint_dirty_rect: Rect2i # Track dirty region

func init_gpu(...):
    # ...
    # Create small CPU buffers for brush painting
    paint_buffer_water = Image.create(canvas_width, canvas_height, false, Image.FORMAT_RF)
    paint_buffer_mobile = Image.create(canvas_width, canvas_height, false, Image.FORMAT_RGBAF)
    paint_dirty_rect = Rect2i(0, 0, 0, 0) # Empty

func paint_watercolor_pixel(x: int, y: int, color: Color, water: float, pressure: float):
    # Paint into CPU buffers
    var current_water = paint_buffer_water.get_pixel(x, y).r
    var new_water = current_water + water
    paint_buffer_water.set_pixel(x, y, Color(new_water, 0, 0))

    var current_pigment = paint_buffer_mobile.get_pixel(x, y)
    var mixed = PigmentMixer._mix_pigments_optical(color, current_pigment)
    paint_buffer_mobile.set_pixel(x, y, mixed)

    # Expand dirty rectangle
    if paint_dirty_rect.size.x == 0:
        paint_dirty_rect = Rect2i(x, y, 1, 1)
    else:
        paint_dirty_rect = paint_dirty_rect.expand(Vector2i(x, y))

func flush_paint_to_gpu():
    if paint_dirty_rect.size.x == 0:
        return # Nothing to upload

    # Extract dirty region from CPU buffers
    var water_bytes = _extract_region_r32f(paint_buffer_water, paint_dirty_rect)
    var mobile_bytes = _extract_region_rgba32f(paint_buffer_mobile, paint_dirty_rect)

    # Upload to GPU (ADDITIVE - adds to existing water/pigment)
    # This requires a small compute shader or manual read-modify-write
    # For simplicity, can do readback → modify → write (only for small regions)

    # Clear dirty region
    paint_buffer_water.fill_rect(paint_dirty_rect, Color(0, 0, 0, 0))
    paint_buffer_mobile.fill_rect(paint_dirty_rect, Color(1, 1, 1, 0))
    paint_dirty_rect = Rect2i(0, 0, 0, 0)
```

**Alternative (Simpler):** Upload helper compute shader
```glsl
// add_paint.glsl
layout(set = 0, binding = 0, r32f) uniform image2D water_texture;
layout(set = 0, binding = 1, rgba32f) uniform image2D mobile_texture;
layout(set = 0, binding = 2, r32f) uniform readonly image2D water_upload;
layout(set = 0, binding = 3, rgba32f) uniform readonly image2D mobile_upload;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);

    // Add uploaded water to existing
    float current_water = imageLoad(water_texture, pos).r;
    float upload_water = imageLoad(water_upload, pos).r;
    imageStore(water_texture, pos, vec4(current_water + upload_water, 0, 0, 0));

    // Mix uploaded pigment with existing
    vec4 current_pigment = imageLoad(mobile_texture, pos);
    vec4 upload_pigment = imageLoad(mobile_upload, pos);
    vec4 mixed = mix_pigments_optical(upload_pigment, current_pigment);
    imageStore(mobile_texture, pos, mixed);
}
```

**Recommendation:** Use compute shader approach for consistency with rest of system.

---

### Part 6: Display Setup (painting_coordinator.gd)

**Current display (CPU):**
```gdscript
# Every frame:
water_texture.update(water_read_buffer)  # CPU → GPU copy
mobile_texture.update(mobile_read_buffer)
static_texture.update(static_read_buffer)
```

**New display (GPU-only):**
```gdscript
# In _ready():
# Set up fragment shader materials
var mobile_material = ShaderMaterial.new()
mobile_material.shader = load("res://trial4/shaders/display_layer.gdshader")
mobile_layer_sprite.material = mobile_material

var static_material = ShaderMaterial.new()
static_material.shader = load("res://trial4/shaders/display_layer.gdshader")
static_layer_sprite.material = static_material

# In _process() or after simulation:
# Bind GPU textures to shader materials
mobile_material.set_shader_parameter("gpu_texture", physics_simulator.get_mobile_texture())
static_material.set_shader_parameter("gpu_texture", physics_simulator.get_static_texture())

# NO CPU READBACK! Textures sampled directly by GPU fragment shaders
```

**Challenge:** `set_shader_parameter()` with RID might not work directly. May need to use `RenderingServer` APIs:

```gdscript
# Alternative using RenderingServer
var mobile_canvas_item = mobile_layer_sprite.get_canvas_item()
RenderingServer.canvas_item_add_texture_rect_region(
    mobile_canvas_item,
    Rect2(0, 0, canvas_width, canvas_height),
    physics_simulator.get_mobile_texture(),
    Rect2(0, 0, 1, 1) # UV coords
)
```

**Research needed:** Best way to display compute shader output textures in Godot 4.x

---

## Canvas Size Scaling

### Memory Usage by Resolution

| Resolution | Pixels | Memory per Layer | Total (8 layers) | Notes |
|-----------|--------|------------------|------------------|-------|
| 64×64 | 4K | 16 KB | 128 KB | Current trial3/4 |
| 512×512 | 262K | 1 MB | 8 MB | Target default |
| 1024×1024 | 1M | 4 MB | 32 MB | Mid-range GPU |
| 2048×2048 | 4M | 16 MB | 128 MB | High-end GPU |
| 3000×3000 | 9M | 36 MB | 288 MB | Future goal |

**8 Layers:** water_read, water_write, mobile_read, mobile_write, static_read, static_write, inertia_read, inertia_write
(displacement and absorbency are smaller/shared)

### Performance Expectations

| Resolution | Work Groups | Threads | Est. FPS (mid GPU) |
|-----------|-------------|---------|-------------------|
| 512×512 | 64×64 | 262K | 60+ |
| 1024×1024 | 128×128 | 1M | 30-60 |
| 2048×2048 | 256×256 | 4M | 15-30 |
| 3000×3000 | 375×375 | 9M | 5-15 |

**GPU Scalability:**
- RTX 3060: Should handle 2048×2048 at 30+ FPS
- RTX 4080: Should handle 3000×3000 at 30+ FPS
- Integrated GPU: 512×512 recommended

---

## Implementation Order

### Phase 1: Core GPU Pipeline ✅
- [x] Create all compute shaders
- [x] Create display shader
- [x] Create GPU simulator framework

### Phase 2: Shader Compilation & Binding (NEXT)
- [ ] Implement `_create_compute_pipelines()`
- [ ] Implement `_create_uniform_sets()`
- [ ] Test shader compilation (may need debugging)

### Phase 3: Dispatch Logic
- [ ] Implement `run_simulation_step_gpu()`
- [ ] Implement push constant packing
- [ ] Implement texture swapping
- [ ] Test basic simulation (without user input)

### Phase 4: Display Integration
- [ ] Update painting_coordinator to 512×512
- [ ] Replace CPU physics_simulator with GPU version
- [ ] Set up Sprite2D materials for GPU texture display
- [ ] Test visualization

### Phase 5: Brush Input
- [ ] Implement brush paint upload (CPU→GPU)
- [ ] Create add_paint compute shader (optional)
- [ ] Test interactive painting

### Phase 6: Optimization & Scaling
- [ ] Profile performance at different resolutions
- [ ] Implement dual uniform sets if needed
- [ ] Add resolution selector UI
- [ ] Test on different GPUs

---

## Testing Strategy

### Unit Tests (Per Phase)

**Phase 2: Shader Compilation**
- Test: All 5 shaders compile without errors
- Expected: No SPIR-V compilation errors
- Debug: Print shader source if compilation fails

**Phase 3: Dispatch**
- Test: Run simulation with simple initial conditions
  - Add water blob at center
  - Let it spread via gravity/surface tension
- Expected: Water moves downward (if gravity_y > 0)
- Debug: Read back water texture after N frames, verify spreading

**Phase 4: Display**
- Test: Visualize simulation on screen
- Expected: See water/pigment layers rendering
- Debug: Compare CPU vs GPU output (run both in parallel)

**Phase 5: Brush**
- Test: Paint with mouse, see paint appear and flow
- Expected: Interactive painting works as in trial3
- Debug: Print GPU upload counts, verify upload timing

**Phase 6: Performance**
- Test: Benchmark different resolutions (512, 1024, 2048)
- Expected: Acceptable FPS at target resolutions
- Metrics: Frame time, GPU utilization, memory usage

---

## Potential Issues & Solutions

### Issue 1: Shader Compilation Errors

**Symptom:** SPIR-V compilation fails with cryptic errors

**Causes:**
- Syntax errors in GLSL
- Unsupported GLSL features (Godot uses subset)
- Version mismatch (#version 450 required)

**Solution:**
- Test shaders individually in simple project first
- Use external GLSL validator (glslangValidator)
- Check Godot docs for supported GLSL features

### Issue 2: Uniform Set Binding Mismatches

**Symptom:** Shader sees wrong textures or crashes

**Causes:**
- Binding numbers don't match shader declarations
- Texture formats don't match (R32F vs RGBA32F)
- Read/write access mismatch

**Solution:**
- Double-check shader binding declarations
- Log uniform set creation with binding numbers
- Use validation layers (if available in Godot)

### Issue 3: Black Screen / No Display

**Symptom:** Simulation runs but nothing visible

**Causes:**
- Fragment shader not sampling GPU texture correctly
- Texture RID not bound to material
- UV coordinates incorrect

**Solution:**
- Test fragment shader with simple colored output first
- Verify RID is valid with `RID.is_valid()`
- Check if RenderingServer API is needed instead of ShaderMaterial

### Issue 4: Performance Lower Than Expected

**Symptom:** FPS drops below target

**Causes:**
- Too many rd.sync() calls (blocks CPU)
- Recreating uniform sets every frame
- Inefficient work group size

**Solution:**
- Remove sync() calls except after full simulation step
- Use dual uniform sets to avoid recreation
- Profile with Godot profiler (GPU section)

### Issue 5: Brush Upload Artifacts

**Symptom:** Painted areas flicker or have wrong values

**Causes:**
- Race condition (uploading while shader is reading)
- Wrong texture being uploaded to
- Additive blending not working correctly

**Solution:**
- Upload only when simulation is paused (or between frames)
- Use dedicated upload compute shader
- Verify texture_update() targets correct texture

---

## Code Complexity Breakdown

### Lines of Code to Write

| Component | Lines | Difficulty | Time Estimate |
|-----------|-------|------------|---------------|
| Shader compilation | ~150 | Medium | 1-2 hours |
| Uniform set creation | ~200 | Medium-High | 2-3 hours |
| Dispatch logic | ~100 | Medium | 1-2 hours |
| Texture swapping | ~30 | Low | 30 min |
| Brush upload | ~80 | Medium | 1-2 hours |
| Painting coordinator update | ~150 | Low-Medium | 1 hour |
| Testing & debugging | N/A | High | 3-5 hours |
| **Total** | **~710** | **Medium-High** | **10-15 hours** |

### Difficulty Factors

**Medium Difficulty:**
- RenderingDevice API is well-documented
- Similar patterns repeat for each shader
- Can reference Godot compute shader examples

**High Difficulty:**
- Debugging GPU code is challenging (limited visibility)
- Shader/uniform mismatches cause crashes with little feedback
- Performance profiling requires GPU tools
- Display integration may require RenderingServer APIs (less documented)

---

## Success Criteria

### Minimum Viable GPU Implementation

1. ✅ All shaders compile without errors
2. ✅ Simulation runs at >30 FPS at 512×512
3. ✅ Water flows correctly (gravity, surface tension)
4. ✅ Pigment mixes and deposits correctly
5. ✅ Momentum system reduces oscillation (as in trial3)
6. ✅ Display shows simulation output without CPU readback
7. ✅ Brush painting works interactively

### Stretch Goals

- [ ] Runs at 60 FPS at 1024×1024
- [ ] Scalable to 3000×3000 on high-end GPU
- [ ] < 1ms per frame GPU time at 512×512
- [ ] Brush upload has no visible lag
- [ ] UI slider to change resolution at runtime

---

## Next Steps

### Immediate Actions (Phase 2):

1. **Implement `_create_compute_pipelines()`**
   - Load 5 shader files
   - Compile each to SPIR-V
   - Handle compilation errors gracefully
   - Create pipeline RIDs

2. **Implement `_create_uniform_sets()`**
   - Create uniform arrays for each shader
   - Bind correct textures to each binding
   - Call `rd.uniform_set_create()`

3. **Test Compilation**
   - Run trial4 scene
   - Check console for "GPU physics simulator initialized successfully"
   - If errors, debug shader compilation

### After Phase 2:

Move to Phase 3 (Dispatch Logic) and implement `run_simulation_step_gpu()`.

---

## Questions to Resolve

1. **Display Method:**
   - Can ShaderMaterial.set_shader_parameter() accept RID?
   - Or do we need RenderingServer.canvas_item_add_texture()?
   - **Action:** Test in minimal project first

2. **Uniform Set Update Frequency:**
   - Solution A (recreate) vs Solution B (dual sets)?
   - **Action:** Start with A, profile, switch to B if needed

3. **Brush Upload Timing:**
   - Upload immediately or batch at frame end?
   - **Action:** Immediate upload for responsiveness

4. **Resolution Switching:**
   - Allow runtime change or require restart?
   - **Action:** Require restart (simpler), add UI later

---

## Reference Documentation

### Godot 4 APIs Used

- `RenderingDevice` - GPU compute interface
- `RDShaderSource` - GLSL source container
- `RDTextureFormat` - Texture format specification
- `RDUniform` - Uniform binding descriptor
- `ShaderMaterial` / `RenderingServer` - Display options

### External Resources

- [Godot Compute Shader Tutorial](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html)
- [Vulkan Compute Pipeline](https://www.khronos.org/registry/vulkan/specs/1.3/html/chap9.html)
- [GLSL Shader Compilation](https://github.com/KhronosGroup/glslang)

---

## Summary

This is a **substantial but feasible** implementation. The biggest challenges are:

1. **Shader/uniform binding correctness** - Requires meticulous attention to detail
2. **Display integration** - May need RenderingServer experimentation
3. **Debugging** - GPU errors are harder to diagnose than CPU

**Estimated total time:** 10-15 hours for experienced developer, 15-20 hours if learning RenderingDevice API.

**Payoff:**
- 64×64 → 512×512 canvas (64x more pixels)
- Scalable to 3000×3000+ (2,100x more pixels!)
- No CPU bottleneck
- Foundation for future GPU-accelerated features

---

**Ready to proceed with implementation?**

Let me know if you want to:
- Start with Phase 2 (shader compilation)
- Clarify any section
- Adjust the approach
