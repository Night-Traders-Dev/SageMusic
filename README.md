# SageMusic

A professional-grade music notation software clone of Finale, built natively in **SageLang**.

## Features

- **GPU-Accelerated Rendering:** Uses a retained-mode scene graph with Vulkan/OpenGL.
- **Advanced Music Model:** Support for polyphonic voices, measures, parts, and complex rhythmic elements.
- **Intelligent Layout:** Automatic measure justification and rhythmic spacing engine.
- **Immediate-Mode UI:** Professional toolbars, setup wizard, and palettes for intuitive music entry.
- **SMuFL Support:** Designed to work with standard music fonts (like Maestro and Bravura).
- **Multi-Track Audio Engine:** Integrated MIDI sequencer using miniaudio and sfizz for sample-accurate playback of orchestral instruments.

## Project Structure

- `src/model/`: Core Object-Oriented music data structures.
- `src/renderer/`: GPU rendering engine, batching system, and glyph management.
- `src/layout/`: Spatial hit-testing, spacing, and justification logic.
- `src/ui/`: Interactive editor interfaces, tool palettes, and setup wizards.
- `src/audio/`: Multi-channel MIDI sequencing, instrument mapping, and C-FFI backend.
- `src/utils/`: Helper functions for safe model access and hit detection.
- `src/command/`: Command history system for undo/redo capabilities.
- `src/main.sage`: Application entry point and main loop orchestration.

## How to Build and Run

Ensure you have SageLang installed along with a C compiler (GCC) for the audio engine FFI.

```bash
./build.sh
./sagemusic
```
