# Watercolor Simulation Painting Tool

This project is a digital painting tool focused on simulating the unique behavior of watercolor.  
It is being developed using the [Godot Game Engine](https://godotengine.org/).

## Goals
- Realistic watercolor brush dynamics
- Artist-friendly interface and tools
- Web-ready performance

## Status

Trial4 is fully GPU-accelerated with compute shaders. Physics settings window implemented with real-time parameter adjustment. Working on advanced features and UI improvements.

## Next Steps
- Support broader brush inputs (pressure sensitivity - fully implemented, stroke speed pending)
- Implement a momentum map to reduce oscillation in the water layer (implemented)
- Batch stroke upload for improved performance with fast brush strokes
- Add layer visibility UI buttons (Tab key toggle implemented, UI buttons pending)
- Add a pigment lifting brush for digital workflow advantages
- Expand pencil input range
- Improve the UI, especially snapshot/history
- Optimize for web performance

## Trial Descriptions
- **`trial1`**: Focused on learning the basics of the Godot engine.
- **`trial2`**: Introduced a more robust data structure to support future expansion.
- **`trial3`**:
- Improved data structure for faster simulation and easier feature expansion.
- CPU implementation with GPU-friendly logic in place
- Completed watercolor physics simulation with gravity, surface tension, evaporation, and deposition

- **`trial4`**:
- Fully GPU-accelerated using compute shaders (GLSL)
- Physics settings window with real-time parameter adjustment
- Pressure-sensitive brush support (tablet/Wacom)
- Layer visibility controls (Tab to toggle water layer, Q to boost evaporation)
- Camera controls (pan with middle mouse, zoom with scroll wheel)
- PNG export functionality
- 256x256 canvas running at interactive framerates
