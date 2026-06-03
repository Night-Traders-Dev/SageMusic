# SageMusic

A professional-grade music notation software clone of Finale, built natively in **SageLang**.

## Features

- **GPU-Accelerated Rendering:** Uses a retained-mode scene graph with Vulkan/OpenGL.
- **Advanced Music Model:** Support for polyphonic voices, measures, parts, and complex rhythmic elements.
- **Intelligent Layout:** Automatic measure justification and rhythmic spacing engine.
- **Immediate-Mode UI:** Professional toolbars and palettes for intuitive music entry.
- **SMuFL Support:** Designed to work with standard music fonts (like Bravura).

## Project Structure

- src/model.sage: Core Object-Oriented music data structures.
- src/renderer.sage: GPU rendering engine and glyph management.
- src/layout.sage: Spacing and justification logic.
- src/main.sage: Application entry point and UI orchestration.

## How to Run

Ensure you have SageLang installed.

sage src/main.sage
