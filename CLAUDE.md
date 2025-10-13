# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A digital watercolor painting tool built in **Godot Engine 4.4** that simulates realistic watercolor behavior through physics-based fluid dynamics. The project implements water flow, pigment transport, deposition, and evaporation to create authentic watercolor effects.

## Running the Project

**Open and run in Godot:**
- Open the project in Godot 4.4 or later
- The main scene is configured in `project.godot` (run/main_scene)
- Press F5 to run the project, or use the "Play" button in the Godot editor
- Press Escape to quit (mapped to the "Quit" input action)

**Current working version:** `trial3/` directory contains the active implementation

## Architecture

### Trial System

The codebase is organized into progressive "trials" representing development iterations:

- **trial1/**: Initial Godot learning prototype
- **trial2/**: Introduced improved data structures for extensibility
- **trial3/**: **Active version** - CPU implementation with GPU-friendly logic, improved physics simulation
- **trial4/**: Planned - Will convert trial3 to shaders for scaling

When making changes, work in `trial3/` unless specifically adding new features that require a new trial iteration.

### Core Components (trial3/)

#### 1. main_3.gd
Entry point that handles quit input only. All application logic is delegated to child nodes.

#### 2. painting_coordinator.gd
Central orchestrator managing all canvas layers and the simulation loop. Key responsibilities:
- Manages 6 image layers (64x64 resolution): water, mobile pigment, static pigment, pencil, absorbency map, displacement map
- Implements double-buffering (read/write buffers) for water, mobile, and static layers
- Runs physics simulation each frame via `physics_simulator.run_simulation_step()`
- Handles gravity tilt controls (WASD keys to adjust horizontal/vertical angles)
- Provides `add_paint_at()` interface for brushes to add water and pigment
- Updates GPU textures from CPU image buffers each frame

**Canvas Constants:**
- `CANVAS_WIDTH`: 64
- `CANVAS_HEIGHT`: 64
- `MAX_WATER_AMOUNT`: 1.0

#### 3. physics_simulator.gd
Physics engine running on CPU with GPU-ready algorithms. Contains the entire watercolor simulation:

**Simulation Pipeline (run_simulation_step):**
1. Evaporation - water gradually evaporates based on exposed surface area
2. Water displacement calculation - 4-directional forces (right, left, down, up) computed from:
   - Gravity (adjustable tilt)
   - Surface tension (looks ahead 10 pixels, stops at dry boundaries)
   - Spreading force (immediate neighbors)
3. Water movement execution - moves water and carries pigment proportionally
4. Deposition - mobile pigment settles onto static layer based on water content and absorbency
5. Diffusion - (currently disabled) would spread static pigment

**Key Parameters (exported for live tuning):**
- `S`: Surface tension coefficient (tune with R/F keys)
- `SP`: Spreading force coefficient (tune with T/G keys)
- `HOLD_THRESHOLD`: Force needed to wet a dry pixel (5.0)
- `k_deposit_base`: Deposition speed (1.0)
- `w_scale`: Water wetness scale (0.2)
- `DRY_PIXEL_LIMIT`: Threshold below which pixel is "dry" (0.0001)

**Implementation Notes:**
- Three displacement calculation methods exist; currently uses `_calculate_water_displacement_4_directional()`
- Pigment transport uses `_apply_water_displacement_with_pigment()` (outflow model)
- An inflow model also exists (`_apply_water_displacement_with_pigment_inflow()`) but is not currently active
- Surface tension looks ahead up to 10 pixels until hitting dry boundary
- Forces split into 4 directions to avoid checkerboard artifacts

#### 4. pigment_mixer.gd (Autoloaded as PigmentMixer)
Global singleton providing optical color mixing based on Beer-Lambert law:
- `_mix_pigments_optical()`: Mixes two pigments using optical density, mass-weighted
- `_alpha_to_mass()` / `_mass_to_alpha()`: Convert between visual alpha and abstract pigment mass
- Uses optical density calculations to simulate subtractive color mixing (light absorption)
- `K_ABSORPTION`: Controls paint opacity (0.5)

#### 5. brush_manager.gd
Handles input routing, brush switching, and pigment mixing UI. Responsibilities:
- Routes mouse input to active brush based on canvas-relative coordinates
- Manages CMY (Cyan, Magenta, Yellow) pigment selection with individual alpha controls
- Mixes selected pigments using simple multiplicative RGB blending for hue, layered alpha for concentration
- Updates watercolor brush properties when pigment or water settings change
- Switches between watercolor, pencil, and eraser brushes

#### 6. watercolor_brush.gd
Applies paint dabs with randomized variation:
- Uses `coordinator.add_paint_at()` to stamp paint onto canvas
- Randomizes position (within 0.5× brush radius), size (0.7-1.3×), pigment concentration (0.8-1.2× alpha), water (0.9-1.1×)
- Applies multiple dabs per frame when dragging
- Color's alpha channel represents pigment concentration

#### 7. Other Brushes
- `pencil_brush.gd`: Draws on separate pencil layer using `draw_line_on_pencil_layer()`
- `eraser_brush.gd`: Clears pencil layer

### Data Flow

```
User Input
    ↓
brush_manager (routes input)
    ↓
active_brush (e.g., watercolor_brush)
    ↓
painting_coordinator.add_paint_at() (adds water + pigment to canvas)
    ↓
painting_coordinator._process() → physics_simulator.run_simulation_step()
    ↓
    1. Evaporation (water layer)
    2. Calculate forces (gravity + surface tension + spreading)
    3. Move water + pigment (mobile layer follows water)
    4. Deposition (mobile → static layer)
    ↓
Update GPU textures for rendering
```

### Image Layer Formats

- **Water layer**: `FORMAT_RF` (single float) - stores water amount
- **Mobile/Static pigment layers**: `FORMAT_RGBAF` (RGBA floats) - RGB = pigment hue, A = pigment mass (encoded)
- **Absorbency map**: `FORMAT_RF` - per-pixel paper absorbency (randomized 0.1-0.2)
- **Displacement map**: `FORMAT_RGBAF` - RGBA stores forces (right, left, down, up)

## Common Development Tasks

### Tuning Physics Parameters

**Real-time parameter adjustment (while running):**
- R/F keys: Increase/decrease surface tension (S)
- T/G keys: Increase/decrease spreading force (SP)
- WASD keys: Adjust gravity tilt angles

**Modifying physics constants:**
Edit exported variables in `trial3/physics_simulator.gd` via Godot Inspector, or modify constants directly in the script:
- `DIFFUSION_RATE`, `EVAPORATION_CONST`, `HOLD_THRESHOLD`, `k_deposit_base`, `w_scale`, `K_ABSORPTION`

### Switching Physics Algorithms

In `physics_simulator.gd`, `run_simulation_step()` has commented alternatives:
- **Displacement calculation**: Switch between `_calculate_water_displacement()`, `_calculate_water_displacement_4_directional()`, or `_calculate_water_displacement_4_dir_redistribution()`
- **Water movement**: Switch between `_apply_water_displacement()`, `_apply_water_displacement_with_pigment()`, or `_apply_water_displacement_with_pigment_inflow()`
- **Diffusion**: Currently disabled; uncomment `_simulate_diffusion()` call to enable static layer pigment diffusion

### Adding New Brush Types

1. Create a new `.gd` script in `trial3/`
2. Implement `activate(coordinator)`, `deactivate()`, and `handle_input(event, mouse_pos_img_space)` methods
3. Use `coordinator.add_paint_at()` for watercolor effects or `coordinator.draw_line_on_pencil_layer()` for dry media
4. Add brush node to scene and reference in `brush_manager.gd` export paths
5. Add button press handler in `brush_manager.gd` to call `_set_active_brush()`

### Debugging Visualization

Water layer uses a custom shader (`trial3/water_debug_shader.gdshader`) for visualization. To modify or disable:
- Edit the shader file to change water rendering
- Comment out shader assignment in `painting_coordinator.gd` `_ready()` to show raw water data

## Important Implementation Details

### Double Buffering
Water, mobile, and static layers use read/write buffer pairs. After each simulation step, buffers are swapped via `_swap_water_buffers()`, `_swap_mobile_buffers()`, `_swap_static_buffers()`. Always read from `*_read` and write to `*_write` during simulation.

### Force Calculation and Dry Boundaries
Surface tension looks ahead up to 10 pixels in each direction but stops at dry pixels (`water < DRY_PIXEL_LIMIT`). This creates natural boundaries and prevents water from "jumping" across dry areas.

### Pigment Transport
Pigment moves proportionally with water. When water flows out of a pixel, pigment mass is split: movable mass follows the water, absorbed mass stays. Uses optical mixing (Beer-Lambert) via `PigmentMixer._mix_pigments_optical()`.

### Deposition Mechanism
Two modes:
- **Dry deposition**: When water < DRY_PIXEL_LIMIT, all mobile pigment instantly deposits to static layer
- **Wet deposition**: Exponential deposition rate based on water content and absorbency: `rate = k_deposit_base × absorbency × (w_scale / (water + w_scale))`

### Coordinate Systems
- Canvas images are 64×64, top-left origin
- Sprite2D layers have `centered = false` to align with image coordinates
- Mouse input is converted to image space via `layer_for_mouse_pos.to_local(global_mouse_position)`

## Future Work (from README.md)

- Broader brush inputs (pressure sensitivity, stroke speed)
- Velocity map to reduce water oscillation
- Convert to GPU shaders (trial4) to support larger canvas sizes
- Lifting/whitening brush for undoing work
- Expanded pencil range
- UI improvements (snapshot/history)
- Load/save functionality
- Web performance optimization
