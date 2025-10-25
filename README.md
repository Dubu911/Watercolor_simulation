# Watercolor Simulation Painting Tool

This project is a digital painting tool focused on simulating the unique behavior of watercolor.  
It is being developed using the [Godot Game Engine](https://godotengine.org/).

## Goals
- Realistic watercolor brush dynamics
- Artist-friendly interface and tools
- Web-ready performance

## Status

Trial4 is fully GPU-accelerated with compute shaders. Physics settings window, pigment lifting brush, and responsive UI anchoring implemented. Working on advanced features and performance optimization.

## Next Steps
- Support broader brush inputs (pressure sensitivity - fully implemented, stroke speed pending)
- Batch stroke upload for improved performance with fast brush strokes (batching implemented, further optimization possible)
- Add layer visibility UI buttons (Tab key toggle implemented, UI buttons pending)
- Expand pencil input range
- Improve the UI, especially snapshot/history
- Optimize for web performance

## Completed Features
- ✓ Pressure-sensitive watercolor brush (tablet/Wacom support)
- ✓ Removing brush for pigment lifting (digital advantage feature)
- ✓ Momentum map to reduce water oscillation
- ✓ Real-time physics parameter adjustment
- ✓ Layer visibility controls (Tab/Q keys)
- ✓ PNG export functionality
- ✓ Responsive UI with proper anchoring

## Trial Descriptions
- **`trial1`**: Focused on learning the basics of the Godot engine.
- **`trial2`**: Introduced a more robust data structure to support future expansion.
- **`trial3`**:
- Improved data structure for faster simulation and easier feature expansion.
- CPU implementation with GPU-friendly logic in place
- Completed watercolor physics simulation with gravity, surface tension, evaporation, and deposition

- **`trial4`**:
- Fully GPU-accelerated using compute shaders (GLSL) - 7 compute shaders
- Physics settings window with real-time parameter adjustment
- Four brush types:
  - Watercolor brush (pressure-sensitive, wet-on-wet effects)
  - Removing brush (pigment lifting from mobile and static layers)
  - Pencil brush (separate layer for sketching)
  - Eraser brush (removes pencil marks)
- Layer visibility controls (Tab to toggle water layer, Q to boost evaporation)
- Camera controls (pan with middle mouse, zoom with scroll wheel)
- PNG export functionality
- Responsive UI with proper anchoring (adapts to window size changes)
- 256x256 canvas running at interactive framerates
