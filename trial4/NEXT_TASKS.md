# Trial4 - Next Development Tasks

This document outlines planned improvements for the GPU-accelerated watercolor simulation.

---

## 1. Layer Visibility Controls

**Goal**: Allow users to toggle which layers are visible for debugging and artistic control.

**Default state**: Mobile + Static layers visible (standard painting view)

### Features to implement:

#### A. Quick water layer preview (Q key) ✅ **COMPLETED**
- **Behavior**: While 'Q' key is held down, show ONLY the water layer
- **Purpose**: Let users see which areas are wet (useful for wet-on-wet techniques)
- **Implementation**: ✨
  - ✅ Detect `Input.is_key_pressed(KEY_Q)` in `_process()`
  - ✅ Temporarily hide mobile/static layers
  - ✅ Show water layer with debug shader
  - ✅ Restore visibility when key released
  - **Implemented in**: `trial4/painting_coordinator.gd` → `_handle_layer_visibility_controls()`

#### B. Manual layer toggle buttons
- Add UI buttons/checkboxes for each layer:
  - ☐ Mobile layer (wet pigment)
  - ☐ Static layer (dry pigment)
  - ☐ Water layer (wetness visualization)
  - ☐ Pencil layer
- Buttons should toggle `layer_sprite.visible` property
- Q key press would be equivalent to temporarily checking only "Water layer"

**Files to modify**:
- `trial4/main4.tscn` - Add UI buttons
- `trial4/brush_manager.gd` or create `trial4/layer_visibility_manager.gd` - Handle button signals and Q key
- `trial4/painting_coordinator.gd` - Expose layer sprite references

---

## 2. Faster Brush Input Processing

**Current bottleneck**: Each dab uploads to GPU sequentially during stroke painting.

### Option 3: Batch Entire Stroke Upload (Recommended)

**Approach**:
1. **Accumulate dabs during stroke**:
   - Instead of uploading each dab immediately, store dab data in memory
   - Track: position, color, water, size, pressure for each dab

2. **Calculate stroke bounding box**:
   - Find min/max X and Y across all dabs in stroke
   - Create single region buffer covering entire stroke

3. **Paint all dabs to region buffer**:
   - Loop through accumulated dabs
   - Paint each dab into the region buffer (CPU-side)

4. **Single GPU upload at stroke end**:
   - When mouse button released, upload entire stroke region once
   - Run GPU compute shader on combined region

**Pros**:
- Massive performance gain for long strokes (1 upload vs 50-200 uploads)
- Smooth input tracking even for fast strokes
- No visible latency during stroke

**Cons**:
- No visual feedback until stroke completes (dabs appear all at once when mouse released)
- Requires refactoring brush input handling
- More complex state management

**Implementation steps**:
1. Add `stroke_accumulator` array to `watercolor_brush.gd`
2. Change `_paint_circular_dab()` to store dab data instead of uploading
3. Add `_finalize_stroke()` function that processes accumulated dabs
4. Modify `_end_stroke()` to call `_finalize_stroke()`
5. Create bounding box calculation function
6. Modify `add_paint_at()` to accept array of dabs or region buffer

**Alternative: Progressive batching**:
- Batch every N dabs (e.g., 5-10) instead of waiting for stroke end
- Provides some visual feedback while still reducing uploads
- Trade-off between responsiveness and performance

---

### Option 4: Deferred/Threaded Painting (Advanced)

**Approach**:
1. **Input thread** (main thread):
   - Captures mouse input at full rate
   - Queues paint operations to thread-safe buffer
   - Immediately returns (no blocking)

2. **Paint worker thread**:
   - Continuously processes queued paint operations
   - Creates region buffers
   - Uploads to GPU asynchronously
   - Runs compute shader dispatches

3. **Synchronization**:
   - Use mutex/semaphore for thread-safe queue access
   - Display thread reads GPU textures (already updated by worker)

**Pros**:
- Completely decouples input from GPU upload
- Smoothest possible input tracking
- No visible lag regardless of stroke complexity

**Cons**:
- Most complex to implement
- Requires careful thread synchronization
- Potential race conditions with GPU state
- Godot's RenderingDevice may not be fully thread-safe

**Implementation considerations**:
- GDScript threading: `Thread.new()`, `Thread.start()`, `Thread.wait_to_finish()`
- Thread-safe queue: Use `Mutex` to protect shared data
- Paint operation struct: `{type, position, color, water, size, pressure}`
- Worker loop: `while running: process_queue() -> upload_to_gpu()`
- Shutdown: Signal worker thread to exit, join on cleanup

**Godot-specific concerns**:
- RenderingDevice access from non-main thread may be restricted
- May need to queue GPU operations to run on main thread via `call_deferred()`
- If RenderingDevice is main-thread-only, threading only helps with CPU work (buffering, region calculations)

**Recommendation**: Try Option 3 first. Option 4 may not provide much benefit if GPU uploads must happen on main thread anyway.

---

## 3. UI Input Blocking Canvas Input

**Problem**: When UI elements (color picker, sliders) are clicked, the canvas underneath also receives input and paints.

**Root cause**: Input events propagate to canvas even when UI is clicked.

### Solution: Input event consumption

**Approach 1: Set UI mouse_filter**:
- Ensure all UI elements have `mouse_filter = MOUSE_FILTER_STOP`
- This prevents mouse events from reaching nodes behind the UI
- Check: ColorPicker, Sliders, Buttons, Panels

**Approach 2: Check input event position**:
- Before processing painting input, check if mouse is over UI
- Use `Control.get_global_rect().has_point(global_mouse_pos)`
- Skip painting if mouse is over any UI element

**Implementation in `brush_manager.gd`**:
```gdscript
func _input(event: InputEvent) -> void:
    # Check if mouse is over UI before forwarding to brush
    if event is InputEventMouseButton or event is InputEventMouseMotion:
        if _is_mouse_over_ui(event.position):
            return  # Don't forward to brush

    # ... existing input forwarding code

func _is_mouse_over_ui(screen_pos: Vector2) -> bool:
    # Check if position overlaps any UI element
    if color_picker.get_global_rect().has_point(screen_pos):
        return true
    if pigment_control_panel.get_global_rect().has_point(screen_pos):
        return true
    # ... check other UI elements
    return false
```

**Alternative: Use CanvasLayer input blocking**:
- UI is already in a `CanvasLayer`
- Set `CanvasLayer.follow_viewport_enabled = false` if needed
- Ensure UI handles input first (higher Z-index or input priority)

**Files to modify**:
- `trial4/main4.tscn` - Check mouse_filter settings on UI nodes
- `trial4/brush_manager.gd` - Add UI overlap detection

---

## 4. Runtime Physics Parameter Adjustment Window ✅ **COMPLETED**

**Goal**: Allow users to tune physics parameters in real-time without editing code.

**Implementation Summary:**
- ✅ Created `physics_settings_window.tscn` - Popup window with organized parameter sections
- ✅ Created `physics_settings_window.gd` - Script handling all slider updates
- ✅ Added "⚙ Settings" button in top-left corner of main UI
- ✅ Organized parameters into 3 sections:
  1. Canvas Orientation (vertical/horizontal tilt)
  2. Water Parameters (S, SP, canceling, acceleration, evaporation, hold threshold)
  3. Diffusion & Deposition (diffusion rate/limiter, deposition rate, w_scale)
- ✅ Each slider shows current value on the right
- ✅ X button to close window
- ✅ Changes apply immediately (live preview)
- ✅ Window opens centered when Settings button clicked

### Features:

**Parameters to expose** (from `physics_simulator_gpu.gd`):
- `S` - Surface tension coefficient
- `SP` - Spread force coefficient
- `canceling_power` - Momentum damping
- `acceleration_power` - Momentum acceleration
- `EVAPORATION_CONST` - Water evaporation rate
- `HOLD_THRESHOLD` - Force needed to wet dry pixels
- `DIFFUSION_RATE` - Pigment diffusion speed
- `diffusion_limiter` - Diffusion maximum
- `k_deposit_base` - Deposition rate
- `w_scale` - Water wetness scaling

**UI Design**:
```
┌─────────────────────────────────┐
│  Physics Parameters             │
├─────────────────────────────────┤
│ Surface Tension (S):     0.10   │
│ [────●─────────────────] 0-1.0  │
│                                 │
│ Spread Force (SP):       0.50   │
│ [────────●─────────────] 0-2.0  │
│                                 │
│ Evaporation:            0.01    │
│ [●─────────────────────] 0-0.1  │
│                                 │
│ ... (more sliders)              │
│                                 │
│ [Reset to Defaults] [Close]     │
└─────────────────────────────────┘
```

### Implementation Options:

#### Option A: Popup Window (Recommended)
- Add a "Physics Settings" button to main UI
- Create `Window` node that opens when button clicked
- Window contains VBoxContainer with labeled sliders
- Sliders directly modify `physics_simulator` variables

**Implementation**:
1. Create new scene: `trial4/physics_settings_window.tscn`
2. Add `Window` node with `close_on_escape = true`, `exclusive = false`
3. Add sliders for each parameter with appropriate min/max/step
4. Connect slider signals to update physics_simulator values
5. Add button to main UI to `popup()` the window

#### Option B: Side Panel
- Add collapsible panel to main UI
- Panel slides in/out from edge of screen
- Contains same sliders as Option A

#### Option C: Godot Inspector Export (Simplest)
- Parameters are already `@export` in physics_simulator_gpu.gd
- Can be edited in Godot Inspector during runtime (F5 → select node)
- No custom UI needed
- Not user-friendly for artists

**Files to create/modify**:
- `trial4/physics_settings_window.tscn` - New UI window scene
- `trial4/physics_settings_window.gd` - Script to handle slider changes
- `trial4/main4.tscn` - Add "Physics Settings" button
- `trial4/brush_manager.gd` or main script - Handle button press to show window

**Additional features**:
- Save/Load presets (export parameter sets to JSON)
- Reset to default values button
- Live preview (changes apply immediately as sliders move)
- Tooltips explaining what each parameter does

---

## Current Status

✅ **Completed**:
- GPU compute shader implementation
- Trial3 paint behavior (water-limited pigment transfer, wet-on-wet diffusion)
- Region-based paint upload optimization
- Brush dab frequency optimization (0.5 step size)
- Pigment display shader with proper alpha blending
- **Task 3 - UI input blocking** ✨ (prevents painting when clicking UI elements)
- **Task 1A - Q key water layer preview** ✨ (hold Q to show only water layer)
- **Task 4 - Physics parameter window** ✨ (real-time parameter adjustment UI)

📝 **Next priorities** (recommended order):
1. ~~Task 3 - UI input blocking~~ ✅ **COMPLETED**
2. Task 1A - ~~Q key water layer preview~~ ✅ **COMPLETED** | Task 1B - Layer toggle buttons (pending)
3. ~~Task 4 - Physics parameter window~~ ✅ **COMPLETED**
4. Task 2 - Faster input (bigger project, requires testing)
5. Task 5 - Save/Load functionality (preserve and restore paintings)
6. Task 6 - Pigment lifting brush (digital advantage - remove/lighten pigment)

---

## 5. Save/Load Functionality

**Goal**: Allow users to save and load their watercolor paintings

### Features to implement:

#### A. Save painting
- **What to save**:
  - Static layer (dried pigment) - main painting data
  - Mobile layer (wet pigment) - preserves wet paint state
  - Water layer - preserves water distribution
  - Pencil layer - preserves pencil sketches
  - Background layer (optional) - custom paper color
  - Metadata: canvas size, creation date, app version

- **File format options**:
  - **Option 1: PNG export** (simple, non-editable)
    - Composite all layers into final image
    - Export as standard PNG
    - Pros: Universal format, small file size
    - Cons: Cannot continue editing, loses layer data

  - **Option 2: Custom format** (editable project file)
    - Save each layer as separate data
    - Use JSON/binary format with layer images embedded
    - Extension: `.wcproj` (watercolor project)
    - Pros: Fully editable, preserves all simulation state
    - Cons: Larger file size, custom format

  - **Option 3: Both** (recommended)
    - "Export PNG" for final artwork
    - "Save Project" for continuing work later

#### B. Load painting
- **Load from file**:
  - Read layer data from saved file
  - Reconstruct GPU textures from loaded images
  - Resume simulation from saved state

- **Validation**:
  - Check file version compatibility
  - Verify canvas size matches
  - Handle corrupted files gracefully

#### C. UI Integration
- Add File menu or buttons:
  - 💾 **Save Project** (Ctrl+S) - saves `.wcproj` file
  - 📁 **Load Project** (Ctrl+O) - opens `.wcproj` file
  - 🖼️ **Export PNG** (Ctrl+E) - exports flattened image
  - 🆕 **New Canvas** (Ctrl+N) - clears all layers (with confirmation)

**Implementation approach**:

1. Create `trial4/file_manager.gd` script
2. Implement save functions:
   ```gdscript
   func save_project(filepath: String) -> bool
   func export_png(filepath: String) -> bool
   ```
3. Implement load functions:
   ```gdscript
   func load_project(filepath: String) -> bool
   ```
4. Add UI buttons and file dialogs (`FileDialog` node)
5. Connect to painting_coordinator to access layer images
6. Handle GPU texture updates after loading

**Files to create/modify**:
- Create: `trial4/file_manager.gd` - handles all save/load logic
- Modify: `trial4/main4.tscn` - add File menu UI and FileDialog nodes
- Modify: `trial4/painting_coordinator.gd` - expose layer images, add methods to load layers

**Save format structure** (Option 2 - Custom format):
```json
{
  "version": "1.0",
  "canvas_width": 256,
  "canvas_height": 256,
  "created_at": "2025-01-15T10:30:00Z",
  "layers": {
    "static": "base64_encoded_image_data",
    "mobile": "base64_encoded_image_data",
    "water": "base64_encoded_image_data",
    "pencil": "base64_encoded_image_data",
    "background": "base64_encoded_image_data"
  }
}
```

---

## 6. Pigment Lifting Brush

**Goal**: Implement a brush that removes/lifts pigment from the canvas (digital-only feature, not possible in real watercolor)

### Purpose:
- **Undo mistakes** without clearing entire canvas
- **Create highlights** by removing pigment in specific areas
- **Lighten colors** by partially lifting pigment
- **Digital advantage** - allows corrections impossible with physical watercolor

### Features to implement:

#### A. Lifting Mechanism
- **What to lift**:
  - **Static layer (dried pigment)** - primary target for lifting
  - **Mobile layer (wet pigment)** - optional, lift wet paint too
  - **Mixing behavior**: Lift more pigment from wet areas vs dry areas

- **Lifting modes**:
  1. **Full lift** - Completely remove pigment (back to white paper)
  2. **Partial lift** - Reduce pigment concentration (lighten color)
  3. **Wet lift** - Add water while lifting (simulates real wet-lifting technique)

#### B. Brush Parameters
- **Lift strength** (0.0 - 1.0)
  - 0.0 = No lifting
  - 0.5 = Lighten by 50%
  - 1.0 = Complete removal

- **Brush size** - Same as watercolor brush (pressure-sensitive)

- **Pressure sensitivity**:
  - Light pressure = gentle lifting (lighten)
  - Heavy pressure = aggressive lifting (remove)

- **Water interaction**:
  - Option 1: Lift only pigment (dry technique)
  - Option 2: Add water while lifting (wet technique, creates blooms)

#### C. Implementation Approach

**GPU Implementation (Recommended):**

1. **Create lifting shader**: `trial4/shaders/lift_pigment.glsl`
   ```glsl
   // Reduce pigment alpha/concentration at lift position
   // Apply circular brush pattern
   // Respect lift strength parameter
   ```

2. **Add to physics pipeline**:
   - New function: `physics_simulator.upload_lift_region()`
   - Similar to `upload_paint_region()` but subtracts pigment
   - Operates on static layer (and optionally mobile layer)

3. **Create lifting brush**: `trial4/lifting_brush.gd`
   - Similar structure to `watercolor_brush.gd`
   - Calls `coordinator.lift_pigment_at(pos, strength, radius, pressure)`
   - Uses same stroke interpolation as watercolor brush

4. **Coordinator integration**: `painting_coordinator.gd`
   ```gdscript
   func lift_pigment_at(pos: Vector2, strength: float, radius: float, pressure: float = 1.0):
       # Create region buffer for lift operation
       # Calculate pigment reduction (strength * pressure)
       # Upload to GPU shader for processing
   ```

**CPU Implementation (Alternative):**
- Directly modify static_read_buffer image
- Reduce pixel alpha/concentration at brush position
- Simpler but slower for large brushes

#### D. UI Integration

**Add lifting brush to brush selector:**
- 🧽 **Lifting Brush** button (new icon needed)
- Size slider (reuse existing popup pattern)
- Strength slider (0-100%)
- Toggle: "Add water while lifting" checkbox

**Keyboard shortcut:**
- **L key** - Switch to lifting brush
- Or add to existing brush cycle (watercolor → pencil → eraser → lifter)

#### E. Visual Feedback

**Cursor visualization:**
- Show lift strength as cursor opacity
- Lighter cursor = gentle lift
- Darker cursor = aggressive lift

**Preview mode (optional):**
- Show what will be lifted before applying
- Similar to selection preview in Photoshop

#### F. Technical Considerations

**Lifting from static layer:**
```gdscript
# Reduce pigment concentration
var current_color = static_layer.get_pixel(x, y)
var lift_amount = strength * pressure
var new_alpha = current_color.a * (1.0 - lift_amount)  # Reduce concentration
static_layer.set_pixel(x, y, Color(current_color.r, current_color.g, current_color.b, new_alpha))
```

**Wet lifting (with water):**
```gdscript
# Add water while lifting pigment
water_layer.set_pixel(x, y, water_amount)
# Move some static pigment to mobile layer
var lifted_pigment = static_color * lift_amount
mobile_layer.set_pixel(x, y, lifted_pigment)
static_layer.set_pixel(x, y, static_color * (1.0 - lift_amount))
```

**GPU shader approach:**
```glsl
// lift_pigment.glsl
void main() {
    vec4 current_pigment = texture(static_layer, uv);
    float lift_amount = lift_strength * brush_pattern * pressure;

    // Reduce pigment concentration
    float new_alpha = current_pigment.a * (1.0 - lift_amount);

    // Optional: Add water to create wet-lift effect
    float water_added = lift_amount * wet_lift_enabled;

    fragColor = vec4(current_pigment.rgb, new_alpha);
}
```

### Files to create/modify:

**Create:**
- `trial4/lifting_brush.gd` - Lifting brush logic
- `trial4/shaders/lift_pigment.glsl` - GPU shader for lifting (if using GPU approach)
- Icon for lifting brush button

**Modify:**
- `trial4/brush_manager.gd` - Add lifting brush to brush array, add UI controls
- `trial4/painting_coordinator.gd` - Add `lift_pigment_at()` function
- `trial4/physics_simulator_gpu.gd` - Add `upload_lift_region()` and shader integration
- `trial4/main4.tscn` - Add lifting brush button and UI controls

### Testing Checklist:

- ✅ Lifting removes pigment from static layer
- ✅ Lift strength affects amount removed
- ✅ Pressure sensitivity works correctly
- ✅ Brush size scales properly
- ✅ Wet lift mode creates realistic blooms (if implemented)
- ✅ Works with GPU rendering pipeline
- ✅ No artifacts or visual glitches
- ✅ Performance is acceptable (no lag during lifting)

---

## Notes

- GPU_IMPLEMENTATION_PLAN.md can be archived/deleted - all phases completed
- Current canvas size: 256×256 (can scale to 512×512 or larger with better GPU)
- All physics simulation runs on GPU with no CPU readback per frame
- Texture2DRD used for direct GPU-to-display rendering
