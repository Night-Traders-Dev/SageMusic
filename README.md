# SageMusic

A professional-grade music notation software clone of Finale, built natively in **SageLang**.

## Features

- **GPU-Accelerated Rendering:** Uses a retained-mode scene graph with Vulkan/OpenGL.
- **Advanced Music Model:** Support for polyphonic voices, measures, parts, and complex rhythmic elements.
- **Intelligent Layout:** Automatic measure justification and rhythmic spacing engine.
- **Immediate-Mode UI:** Professional toolbars and palettes for intuitive music entry.
- **SMuFL Support:** Designed to work with standard music fonts (like Bravura).

## Project Structure

- `src/model/`: Core Object-Oriented music data structures.
- `src/renderer/`: GPU rendering engine, batching system, and glyph management.
- `src/layout/`: Spatial hit-testing, spacing, and justification logic.
- `src/ui/`: Interactive editor interfaces, tool palettes, and modals.
- `src/utils/`: Helper functions for safe model access and hit detection.
- `src/command/`: Command history system for undo/redo capabilities.
- `src/main.sage`: Application entry point and main loop orchestration.

## How to Run

Ensure you have SageLang installed.

sage src/main.sage
