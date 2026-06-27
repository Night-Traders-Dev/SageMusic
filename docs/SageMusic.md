# SageMusic Documentation

Welcome to the **SageMusic** documentation. SageMusic is a professional-grade music notation software clone of Finale, built natively in **SageLang**. This document provides a comprehensive overview of the architecture, core subsystems, audio engine, and development workflows.

---

## 1. Architecture Overview

SageMusic is built around a clean separation of concerns, heavily utilizing a Model-View-Controller (MVC) paradigm adapted for immediate-mode GUI and high-performance GPU rendering. 

The core application loop (found in `src/main.sage`) orchestrates the following:
1. **Input Polling:** Reads mouse and keyboard states via `gpu` module.
2. **UI Processing:** Resolves the immediate-mode UI state (toolbars, dialogs, wizard).
3. **Editor Logic:** Handles spatial hit-testing on the score to interact with the music elements.
4. **Layout:** Dynamically recalculates measure widths and note coordinates.
5. **Rendering:** Batches all graphics commands (lines, rectangles, and SMuFL font glyphs) to the Vulkan/OpenGL GPU backend.
6. **Audio Output:** Queues synthesized playback events asynchronously via the C-FFI backend.

---

## 2. Core Subsystems

### 2.1 The Model (`src/model/model.sage`)
The structural representation of the music notation. It follows an Object-Oriented hierarchy:
- **Score:** The root object, holding global properties (title) and a list of `Part`s.
- **Part:** Represents a single instrument (e.g., Flute, Violin). Contains a list of `Measure`s.
- **Measure:** A specific bar of music, holding time signatures, key signatures, and clefs. Contains multiple `Voice`s.
- **Voice:** A container for sequential music elements to support polyphony.
- **MusicElements:** The base class for `Note` and `Rest`. Notes store pitch strings (e.g., `"C4"`) and floating-point durations.

### 2.2 Layout Engine (`src/layout/layout.sage`)
The layout system maps the abstract logical model to 2D screen coordinates.
- **Staff Geometry:** Defines constants for `STAFF_LINE_GAP` (8.0px), `STAFF_HEIGHT`, and `STAFF_STEP`.
- **Pitch-to-Y Translation:** Uses reference pitch values for Treble, Bass, Alto, and Tenor clefs to accurately place notes on the correct staff line or space.
- **Dynamic Spacing:** `calculate_measure_content_width` ensures that measures expand proportionally to accommodate whole notes, eighth notes, and accidentals without overlapping.

### 2.3 GPU Renderer (`src/renderer/renderer.sage`)
SageMusic leverages hardware acceleration instead of slow CPU canvas drawing.
- **Primitive Drawing:** Batched GPU calls for `draw_line` and `draw_rect`.
- **SMuFL Font Integration:** Uses standard music fonts (like Bravura/Maestro). Glyphs are mapped to texture UVs and drawn directly using textured triangle strips via `draw_glyph()`.

### 2.4 Multi-Track Audio Engine (`src/audio/`)
SageMusic features a professional sample-accurate audio engine built directly into the C backend.
- **Engine Components:** `engine.sage` (SageLang interface), `engine_ffi.c` (C implementation).
- **Libraries:** Uses `miniaudio` for low-latency audio device management and `sfizz` for parsing and rendering SFZ sample libraries.
- **MIDI Sequencer:** Supports 16 concurrent channels. The `Play` button parses the score and queues tempo-synced MIDI `note_on` and `note_off` events into the C backend.
- **Instrument Map:** `instrument_map.sage` parses string names (e.g., "Trumpet 1") to load the corresponding high-quality VSCO2 orchestral samples dynamically.

### 2.5 Immediate-Mode UI (`src/ui/`)
The user interface is completely custom-built using immediate-mode concepts.
- **Setup Wizard:** A multi-page interactive modal (`editor_ui.sage`) that lets users select Ensembles (e.g., Brass Quintet), time signatures, and keys to dynamically generate the score.
- **Tools Palette:** Supports various interaction states like the Note Entry tool, Eraser, and Selection tool.

### 2.6 Command History (`src/command/command.sage`)
Implements the **Command Pattern** for robust Undo and Redo functionality.
- Every mutating action (adding a note, deleting an element) is encapsulated in a Command object (e.g., `AddElementCommand`).
- The `CommandHistory` stack allows unlimited undo/redo traversals.

---

## 3. Development and Testing

### 3.1 Building and Running
The application requires the SageLang compiler and a GCC compiler for the FFI integration. To build the customized audio engine, we compile SageLang to C, patch the output to include our FFI headers, and compile via GCC.

```bash
# Build the binary
./build.sh

# Run the application
./sagemusic
```

### 3.2 Testing Suite
SageMusic features a custom native testing framework located in `src/tests/`. It provides unit test coverage across all major components without relying on external testing libraries.

**Available Test Suites:**
- `test_model.sage`: Verifies structural object integrity.
- `test_layout.sage`: Validates mathematical pitch-to-screen coordinate mapping.
- `test_commands.sage`: Exercises the Undo/Redo stack.
- `test_audio.sage`: Tests pitch-to-MIDI conversions and instrument string mapping.
- `test_utils.sage`: Checks bounds-safe helper functions.

**Run all tests:**
```bash
sage src/tests/run_tests.sage
```
