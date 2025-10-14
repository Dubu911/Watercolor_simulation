# Watercolor Simulation Painting Tool

This project is a digital painting tool focused on simulating the unique behavior of watercolor.  
It is being developed using the [Godot Game Engine](https://godotengine.org/).

## Goals
- Realistic watercolor brush dynamics
- Artist-friendly interface and tools
- Web-ready performance

## Status

Implementing the watercolor physics simulation in trial3.

## Next Steps
-Support broader brush inputs (pressure, stroke speed)
- Implement a velocity map to reduce oscillation in the water layer
- Convert GPU-ready code into shaders to scale up canvas size
- Add a whitening(lift) watercolor brush so user can undo the work
- Expand pencil input range
- Improve the UI, especially snapshot/history
- Add load, save functionality
- Optimize for web performance

## Trial Descriptions
- **`trial1`**: Focused on learning the basics of the Godot engine.
- **`trial2`**: Introduced a more robust data structure to support future expansion.
- **`trial3`**: 
- Improved data structure for faster simulation and easier feature expansion.
- CPU implementation with GPU-friendly logic in place
- Core physics algorithms in progress; currently working on watercolor brush

- **`trial4`**:
- To do : Convert trial3 to shaders so it can scale up
