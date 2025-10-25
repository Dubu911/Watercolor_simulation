# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A digital watercolor painting tool built in **Godot Engine 4.4** that simulates realistic watercolor behavior through GPU-accelerated physics-based fluid dynamics. The project implements water flow, pigment transport, deposition, and evaporation using compute shaders to create authentic watercolor effects.

## Running the Project

**Open and run in Godot:**
- Open the project in Godot 4.4 or later
- The main scene is configured in `project.godot` (run/main_scene)
- Press F5 to run the project, or use the "Play" button in the Godot editor
- Press Escape to quit (mapped to the "Quit" input action)

**Current working version:** `trial4/` directory contains the active GPU-accelerated implementation

## Architecture

### Trial System

The codebase is organized into progressive "trials" representing development iterations:

- **trial1/**: Initial Godot learning prototype
- **trial2/**: Introduced improved data structures for extensibility
- **trial3/**: CPU implementation with GPU-friendly logic, completed physics algorithms
- **trial4/**: **Active version** - Full GPU implementation using compute shaders (GLSL)

When making changes, work in `trial4/` as this is the current production version.

### Core Components (trial4/)

#### 1. main_4.gd
Entry point that handles quit input and settings window toggle. All application logic is delegated to child nodes.

#### 2. painting_coordinator.gd
Central orchestrator managing canvas GPU textures and the simulation loop. Key responsibilities:
- Manages GPU textures (256×256 resolution): water, mobile pigment, static pigment, pencil, absorbency map, displacement map
- Implements double-buffering using RenderingDevice texture pairs for physics computation
- Runs GPU physics simulation each frame via `physics_simulator.run_simulation_step()`
- Handles gravity tilt controls (WASD keys or physics settings window)
- Provides `add_paint_at()` interface for brushes to add water and pigment via GPU
- Displays computed textures directly (no CPU readback for rendering)
- Layer visibility controls (Tab key to toggle water layer, Q key for quick evaporation)

**Canvas Constants:**
- `CANVAS_WIDTH`: 256
- `CANVAS_HEIGHT`: 256
- `MAX_WATER_AMOUNT`: 1.0

#### 3. physics_simulator_gpu.gd
GPU-accelerated physics engine using compute shaders. All physics runs on GPU via RenderingDevice:

**Simulation Pipeline (run_simulation_step):**
1. Evaporation shader - water gradually evaporates based on exposed surface area
2. Water displacement calculation shader - 4-directional forces (right, left, down, up) from:
   - Gravity (adjustable tilt)
   - Surface tension (looks ahead multiple pixels, stops at dry boundaries)
   - Spreading force (immediate neighbors)
3. Water inflow application shader - moves water and carries pigment proportionally
4. Deposition shader - mobile pigment settles onto static layer based on water content and absorbency
5. Diffusion shader - spreads static pigment (optional)

**Compute Shaders (trial4/shaders/):**
- `evaporation.glsl` - Water evaporation
- `calculate_displacement.glsl` - Force computation
- `apply_inflow.glsl` - Water and pigment movement
- `deposition.glsl` - Pigment settling
- `diffusion.glsl` - Pigment spreading
- `add_paint.glsl` - Brush stroke application

**Key Parameters (adjustable via physics settings window):**
- `S`: Surface tension coefficient
- `SP`: Spreading force coefficient
- `canceling_power`: Force cancellation between opposing flows
- `acceleration_power`: Water acceleration scaling
- `EVAPORATION_CONST`: Evaporation rate
- `HOLD_THRESHOLD`: Force needed to wet a dry pixel (5.0)
- `k_deposit_base`: Deposition speed (1.0)
- `w_scale`: Water wetness scale (0.2)
- `DIFFUSION_RATE`: Pigment diffusion rate
- `diffusion_limiter`: Limits diffusion amount

**Implementation Notes:**
- All physics computation happens on GPU, no CPU processing
- RenderingDevice API used for compute shader dispatch
- Double-buffered textures for read/write operations
- Uniform sets manage shader parameters and texture bindings

#### 4. brush_manager.gd
Handles input routing, brush switching, cursor rendering, and UI blocking. Responsibilities:
- Routes mouse/tablet input to active brush with pressure support
- Manages brush cursor sprites (dual-ring for watercolor showing pressure range)
- Blocks input when mouse is over UI elements (`_is_mouse_over_ui()`)
- Updates cursor position from both motion and button events (prevents ghost lines)
- Switches between watercolor, pencil, and eraser brushes
- Manages color picker and brush size controls

**Cursor System:**
- `brush_cursor_outer`: Shows maximum brush size (full pressure)
- `brush_cursor_inner`: Shows minimum brush size (light pressure)
- `pencil_cursor`: Single ring for pencil
- `eraser_cursor`: Single ring for eraser
- All cursors use procedurally generated circle textures

#### 5. watercolor_brush.gd
Applies paint with pressure sensitivity and stroke masking:
- Uses `coordinator.add_paint_at()` to apply paint via GPU shader
- Supports tablet pressure for size variation (`pressure_affects_size`)
- Stroke mask prevents painting same pixel twice in one stroke
- Interpolates between positions for smooth strokes
- Color's alpha channel represents pigment concentration

**Pressure Mapping:**
- `min_pressure_size_mult`: 0.1 (10% size at light pressure)
- `max_pressure_size_mult`: 2.0 (200% size at full pressure)
- Pressure read from `InputEventMouseMotion.pressure` for tablets
- Falls back to 1.0 for mouse input

#### 6. Other Brushes
- `pencil_brush.gd`: Draws on separate pencil layer
- `eraser_brush.gd`: Clears pencil layer

#### 7. camera_2d.gd
Handles viewport navigation:
- Middle mouse button for panning
- Mouse wheel for zoom (in/out)
- Polls `Input.is_mouse_button_pressed()` for persistent panning state
- Adjusts pan speed based on zoom level

#### 8. physics_settings_window.gd & physics_settings_window.tscn
Real-time physics parameter adjustment UI:
- PopupPanel with organized parameter sections
- Canvas Orientation (vertical/horizontal tilt)
- Water Parameters (6 sliders)
- Diffusion Parameters (4 sliders)
- Close button (✕) in title bar
- All parameters update live during simulation

#### 9. file_manager.gd
Handles file operations:
- `new_canvas(width, height)`: Reinitializes canvas with custom dimensions
- `export_png(filepath)`: Exports current painting as PNG (composites all visible layers)
- Calls `painting_coordinator.get_composite_image()` for CPU-side layer compositing
- **Note**: Save/load project functionality was removed; only PNG export is supported

### Data Flow

```
User Input (with tablet pressure)
    ↓
brush_manager (routes input, blocks UI, updates cursor)
    ↓
active_brush (e.g., watercolor_brush with pressure)
    ↓
painting_coordinator.add_paint_at() (uploads to GPU via add_paint shader)
    ↓
painting_coordinator._process() → physics_simulator_gpu.run_simulation_step()
    ↓
    GPU Compute Shaders:
    1. Evaporation (evaporation.glsl)
    2. Calculate forces (calculate_displacement.glsl)
    3. Move water + pigment (apply_inflow.glsl)
    4. Deposition (deposition.glsl)
    ↓
Display GPU textures directly (no CPU readback)
```

### GPU Texture Formats

All textures use RenderingDevice format `RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT`:

- **Water layer**: R channel = water amount, GBA unused
- **Mobile/Static pigment layers**: RGBA = pigment color with alpha as concentration
- **Absorbency map**: R channel = paper absorbency (randomized 0.1-0.2)
- **Displacement map**: RGBA = forces (right, left, down, up)

## Common Development Tasks

### Tuning Physics Parameters

**Real-time parameter adjustment:**
- Open physics settings window via "⚙ Settings" button (top-left)
- Adjust sliders to see immediate effects
- All parameters update GPU shaders in real-time

**Layer Visibility:**
- **Tab key**: Toggle water layer visibility on/off (press once to show, press again to hide)
- **Q key**: Hold to temporarily boost evaporation to 1.0 for quick drying (releases when key released)

### Modifying Compute Shaders

Shaders are in `trial4/shaders/`. After editing:
1. Godot will reimport the shader automatically
2. GPU simulator will reload shader on next run
3. Check console for compilation errors

**Shader Structure:**
```glsl
#version 450

layout(local_size_x = 8, local_size_y = 8) in;

layout(set = 0, binding = 0, rgba32f) uniform readonly image2D input_texture;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D output_texture;

layout(push_constant) uniform Params {
    float param1;
    float param2;
} params;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    // shader logic here
}
```

### Adding New Brush Types

1. Create a new `.gd` script in `trial4/`
2. Implement `activate(coordinator)`, `deactivate()`, `cancel_stroke()`, and `handle_input(event, mouse_pos_img_space)` methods
3. Use `coordinator.add_paint_at()` for watercolor effects
4. Add brush node to main4.tscn and reference in `brush_manager.gd` export paths
5. Add button and press handler in `brush_manager.gd`
6. Create custom cursor sprite if needed

### Debugging GPU Shaders

- Check console output for shader compilation errors
- Use `print()` statements in GDScript to verify data being sent to shaders
- Water layer visualization uses a debug shader for rendering
- Enable Godot's verbose output for RenderingDevice errors

## Important Implementation Details

### GPU Double Buffering
All physics textures use read/write pairs. Compute shaders read from one texture and write to another, then textures are swapped. This prevents read/write conflicts.

### Pressure Sensitivity
Watercolor brush reads tablet pressure from `InputEventMouseMotion.pressure`. The value ranges 0.0-1.0:
- Checked with `"pressure" in event` for compatibility
- Clamped to minimum 0.05 to prevent invisible strokes
- Falls back to cached value for button events
- Mouse input defaults to 1.0 (full pressure)

### UI Input Blocking
`brush_manager._is_mouse_over_ui()` checks if mouse is over any UI element:
- Settings button
- Physics settings panel
- Color picker
- Brush size popups
- Alpha/water sliders
- Tool buttons

When over UI, input is blocked from reaching canvas (prevents accidental painting).

### Cursor Tracking
Position tracked in two places:
- `_last_world_pos`: Updated from motion events AND button events
- Button event updates prevent "ghost line" bug when windows steal focus
- Cursor sprites positioned at `_last_world_pos` every frame in `_process()`

### Compute Shader Dispatch
Shaders dispatched in 8×8 work groups. For 256×256 canvas:
- Dispatch groups: `(256/8, 256/8, 1)` = `(32, 32, 1)`
- Each invocation processes one pixel
- `gl_GlobalInvocationID.xy` gives pixel coordinates

### File Organization
Active files only:
- `_archive/` folder contains old CPU implementations and test files
- Only GPU versions are used in production

## Future Work

**High Priority:**
- Pigment lifting brush (digital advantage - remove/lighten pigment)
- Fix preview layer white edges during batch uploads (occurs at CPU→GPU handoff during continuous strokes)
- Fix save/load system (currently saves correctly but fails to load project data back)

**Lower Priority:**
- Support stroke speed variation
- Implement velocity map to reduce water oscillation
- Scale canvas size further (currently 256×256, can go larger with optimization)
- Expand pencil input range
- UI improvements (snapshot/history)
- Web performance optimization

**Known Issues:**
- **White edge artifact during batch upload**: When CPU preview uploads batched pixels to GPU during continuous painting, a white outline briefly appears at the handoff boundary (last dab outline). This is a rendering/compositing timing issue between preview and GPU-processed layers.
- **White outline during fast evaporation**: When holding Q key for maximum evaporation speed, white outlines appear at water boundaries as the wet area shrinks. Only occurs with fast evaporation, not natural drying. Likely related to deposition/evaporation rate mismatch at edges.
- **Save/load broken - RenderingDevice texture update issue**: Project can save state correctly and data loads correctly on CPU, but GPU display shows black canvas after load. See "Save/Load Debugging Session" below for details.

## Save/Load Debugging Session (4+ Hours)

This section documents an extensive debugging session attempting to fix the save/load functionality. The session involved multiple developers (Claude Code + ChatGPT consultation) and spanned multiple approaches.

### The Problem

**Symptom:** After loading a saved `.wcproj` file, the canvas displays as completely black, even though:
- ✅ PNG export works correctly (shows the painting)
- ✅ New canvas + painting works fine
- ✅ File saves correctly
- ✅ File loads correctly into CPU (verified 994 pixels with correct data like `(0.9961, 0.0, 0.0, 0.498)`)
- ✅ CPU compositing (`get_composite_image()`) works correctly
- ✅ GPU upload reports success
- ❌ GPU display shows black canvas

### What We Confirmed

1. **Save path works**: `get_layer_images_for_save_flat()` correctly downloads GPU layers and bakes them into a single static layer
2. **File format is valid**: JSON decodes successfully with correct pixel data
3. **Load/decode works**: `_rgba8_to_rgbaf()` converts PNG data to RGBAF format correctly
4. **Data reaches GPU**: Added extensive debug logging showing:
   - Correct pixel data in CPU buffers (e.g., 994 non-empty pixels)
   - Successful byte conversion via `_image_to_rgba32f_bytes()`
   - `rd.texture_update()` completes without errors
   - Data uploaded to BOTH read and write texture buffers (to survive buffer swaps)
5. **Display binding works**: `Texture2DRD` objects created and bound to sprites
6. **Simulation paused during load**: `_loading_in_progress` flag prevents physics from running during upload

### Debugging Attempts (All Failed to Fix Issue)

#### Phase 1: Alpha Format Investigations
Suspected premultiplied vs. straight alpha mismatch:

**Tried:**
- Converting to premultiplied alpha on save, unpremultiplying on load
- Keeping straight alpha throughout
- Forcing empty pixels to white `(1,1,1,0)` instead of black `(0,0,0,0)`
- Forcing empty pixels to `(0,0,0,0)` everywhere
- Using `CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA` on sprites
- Removing all custom shaders (set `material = null`)

**Result:** No change - still black canvas

#### Phase 2: Display Path Debugging
Suspected sprite rendering or layer ordering issues:

**Tried:**
- Removing `pigment_display_shader` (set `material = null` on mobile/static sprites)
- Forcing z-index ordering (background=0, static=1, mobile=2, pencil=3)
- Resetting `self_modulate = Color(1,1,1,1)` on all sprites
- Ensuring correct visibility flags after load
- Rebinding `Texture2DRD` objects after upload
- Waiting one frame after upload: `await get_tree().process_frame`
- CPU preview fallback test (works - proves data is correct)

**Result:** CPU preview showed painting correctly, but RenderingDevice path still showed black

#### Phase 3: RenderingDevice State Management
Suspected GPU texture update timing or state issues:

**Tried:**
- Adding `rd.barrier(RenderingDevice.BARRIER_MASK_TRANSFER)` after upload
- Uploading to BOTH read and write textures (to survive first buffer swap)
- Pausing simulation for multiple frames during load
- Creating fresh `Texture2DRD` objects after upload
- Downloading texture back from GPU after upload (confirmed data was there)
- Changing texture upload format from RGBA8 to RGBAF
- Verifying GPU texture format matches (R32G32B32A32_SFLOAT)

**Result:** Data confirmed present on GPU (readback worked), but display still black

#### Phase 4: Byte Conversion Verification
Suspected data conversion issues:

**Tried:**
- Logging byte array contents before upload
- Verifying float packing/unpacking in `_image_to_rgba32f_bytes()`
- Testing with simplified single-color test images
- Comparing byte arrays from live painting vs. loaded data
- Saving debug PNGs at each conversion step

**Result:** All byte conversions verified correct - identical to live painting path

### The Conclusion: RenderingDevice Texture Update Bug

After exhausting all reasonable approaches, we concluded this is likely a **Godot RenderingDevice limitation or bug**:

**Key Observation:**
- **Live painting path** (new canvas → paint → display): Works perfectly
  - `init_gpu()` creates fresh textures
  - `upload_paint_region()` updates textures during painting
  - Display shows correctly

- **Load path** (init → later update via load): Fails
  - `init_gpu()` creates textures with empty data
  - `upload_full_layers()` calls `rd.texture_update()` with new data
  - Upload reports success, data confirmed present via readback
  - Display shows black

**Root Cause Theory:**

The `RenderingDevice.texture_update()` method may not properly commit texture data updates in all cases, OR the texture RID becomes "stale" for rendering purposes even though the data is updated in GPU memory. The RenderingDevice is a **singleton global object** in Godot, and there may be undocumented state management requirements when updating existing textures vs. creating new ones.

**Evidence:**
1. CPU readback after `texture_update()` shows correct data (GPU memory updated)
2. Same texture RID used for live painting works fine
3. Creating new `Texture2DRD` objects doesn't help (same RID referenced)
4. All alpha/format/timing approaches failed
5. CPU composite path works (proves data is correct)

### Attempted Solutions

#### Solution A: Recreate Textures (Not Implemented)
```gdscript
func upload_full_layers(water_img: Image, mobile_img: Image, static_img: Image):
    # Free old textures
    if static_read_tex.is_valid():
        rd.free_rid(static_read_tex)
    if static_write_tex.is_valid():
        rd.free_rid(static_write_tex)

    # Recreate textures from scratch with new data
    static_read_tex = _create_texture_from_image(static_img)
    static_write_tex = _create_texture_from_image(static_img)

    # Rebind to sprites
    _setup_gpu_texture_display()
```

This would bypass `texture_update()` entirely by destroying and recreating textures.

**Not implemented because:** Uncertain if it would work, and might cause other issues with shader bindings.

#### Solution B: Compute Shader Copy (Not Implemented)
Use a compute shader to copy from a staging texture instead of using `texture_update()`:

```glsl
// copy_texture.glsl
layout(set = 0, binding = 0) uniform readonly image2D src;
layout(set = 0, binding = 1) uniform writeonly image2D dst;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    vec4 data = imageLoad(src, pos);
    imageStore(dst, pos, data);
}
```

**Not implemented because:** Would require significant refactoring and might hit the same issue.

### Current Workaround

**Save/load functionality has been disabled.** Only PNG export is available:

- **File → Save Project**: Disabled/removed
- **File → Load Project**: Disabled/removed
- **File → Export PNG**: ✅ Works correctly (uses CPU compositing)

Users can export their work as PNG files, but cannot save/load the editable project state with physics layers intact.

### Lessons Learned

1. **RenderingDevice is complex**: Godot's low-level GPU API has subtle state management requirements
2. **Texture RIDs may have lifecycle constraints**: Creating textures vs. updating them may behave differently
3. **Alpha handling is error-prone**: Even though we ruled it out, it consumed significant debugging time
4. **CPU/GPU path divergence**: The fact that CPU composite works but GPU display doesn't is highly unusual
5. **Documentation gaps**: Godot's RenderingDevice docs don't clearly explain texture update semantics

### Future Investigation Ideas

If someone wants to tackle this again:

1. **Test on different GPU/drivers**: Might be driver-specific bug
2. **Try Vulkan vs. OpenGL backend**: Compare behavior across rendering backends
3. **Inspect RenderingDevice source code**: Look at `texture_update()` implementation in Godot engine
4. **File Godot bug report**: With minimal reproduction case
5. **Use RenderingServer instead**: Higher-level API might handle state management better
6. **Alternative: CPU-only simulation during load**: Run one physics frame on CPU to "warm up" GPU state

**Recently Completed:**
- ✓ GPU compute shader implementation
- ✓ Physics settings window with real-time parameter adjustment
- ✓ Pressure-sensitive brush support (tablet/Wacom)
- ✓ Tab key water layer toggle
- ✓ Q key quick evaporation boost
- ✓ PNG export functionality
- ✓ UI input blocking (prevents painting when clicking UI elements)
- ✓ Batched pixel upload system (time-based GPU uploads for performance)
- ✓ CPU preview layer with Beer-Lambert optical mixing
- ✓ Pixel-by-pixel stroke masking (trial3 approach for smooth continuous strokes)