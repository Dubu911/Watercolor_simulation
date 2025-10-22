# Trial4 - Next Development Tasks

This document outlines planned improvements for the GPU-accelerated watercolor simulation.

---

## 1. Layer Visibility Controls

**Goal**: Allow users to toggle which layers are visible for debugging and artistic control.

**Default state**: Mobile + Static layers visible (standard painting view)

### Features to implement:

#### A. Quick water layer preview (Q key)
- **Behavior**: While 'Q' key is held down, show ONLY the water layer
- **Purpose**: Let users see which areas are wet (useful for wet-on-wet techniques)
- **Implementation**:
  - Detect `Input.is_key_pressed(KEY_Q)` in `_process()`
  - Temporarily hide mobile/static layers
  - Show water layer with debug shader
  - Restore visibility when key released

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

## 4. Runtime Physics Parameter Adjustment Window

**Goal**: Allow users to tune physics parameters in real-time without editing code.

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

📝 **Next priorities** (recommended order):
1. Task 3 - UI input blocking (quick fix, improves usability)
2. Task 1 - Layer visibility controls (useful for debugging)
3. Task 4 - Physics parameter window (helps with tuning)
4. Task 2 - Faster input (bigger project, requires testing)

---

## Notes

- GPU_IMPLEMENTATION_PLAN.md can be archived/deleted - all phases completed
- Current canvas size: 256×256 (can scale to 512×512 or larger with better GPU)
- All physics simulation runs on GPU with no CPU readback per frame
- Texture2DRD used for direct GPU-to-display rendering
