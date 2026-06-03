# SageMusic Roadmap

This document outlines the development roadmap for **SageMusic**, a professional-grade music notation software clone of Finale, built natively in **SageLang**. 

As a Day-1 prototype, the core architecture is established with clean boundary separation between the data model, layout, and rendering layers. The path forward focuses on transitioning from stubs to a fully functional, high-performance, interactive notation system.

---

## Phase 1: Interactive Rendering & Foundation (Current Priority)
The immediate focus is getting basic visual output on screen and enabling core rendering pipelines.

### 1.1 GPU Primitive Drawing
- [x] Implement `draw_line()` in `renderer.sage` using GPU line list pipelines.
- [x] Implement `draw_rect()` in `renderer.sage` using GPU triangle list/strip pipelines.
- [x] Render standard staff lines (5 lines per staff, 8px spacing).
- [x] Render bar lines at measure boundaries.

### 1.2 SMuFL Font Integration
- [ ] Load the **Bravura** (or equivalent) SMuFL font metadata and texture atlas.
- [ ] Implement the glyph rendering pipeline (`create_glyph_pipeline()`).
- [ ] Map SMuFL codepoints (e.g., treble clef `0xE050`, quarter notehead `0xE0A4`) to texture coordinates (UVs).
- [ ] Render actual music glyphs instead of rectangle stubs.

### 1.3 Pitch-to-Y Layout Logic
- [x] Implement the `pitch_to_y()` mapping function in `layout.sage`.
- [x] Support treble, bass, alto, and tenor clefs.
- [x] Handle ledger lines for notes that extend above or below the 5-staff lines.
- [x] Support basic accidentals (sharps, flats, naturals) positioned horizontally before noteheads.

---

## Phase 2: User Interaction & Editing
Transforming SageMusic from a static renderer into an interactive editor.

### 2.1 Tool State Machine
- [ ] Implement an input handling system for mouse and keyboard events.
- [ ] Create a tool selection state:
  - **Selection Tool**: Select, drag, and delete existing notes/rests/measures.
  - **Note Entry Tool**: Click on the staff to insert notes/rests of the selected duration.
  - **Eraser Tool**: Remove specific notation elements.

### 2.2 Duration Palette & Input
- [ ] Make the immediate-mode UI duration palette interactive (selecting Whole, Half, Quarter, Eighth, etc.).
- [ ] Bind keyboard shortcuts for durations (e.g., `5` for quarter note, `6` for half note, similar to industry standards).
- [ ] Implement pitch preview on hover when the Note Entry tool is active.

### 2.3 Document History (Undo/Redo)
- [ ] Implement a Command Pattern for editing actions (AddNote, DeleteNote, ChangePitch).
- [ ] Support undo/redo stack.

---

## Phase 3: Advanced Notation Data Model
Expanding the core types to support complex musical scores.

### 3.1 Polyphony & Chords
- [ ] Expand the `Note` and `Voice` classes to support multi-pitch chords at a single rhythmic position.
- [ ] Support multiple voices per staff (e.g., Voice 1 stems up, Voice 2 stems down).

### 3.2 Rhythmic Groups & Expressions
- [ ] Implement auto-beaming for eighth and sixteenth notes based on time signature.
- [ ] Support tuplets (triplets, quintuplets, etc.) with custom brackets and numbering.
- [ ] Add support for ties, slurs, and hairpins (crescendo/decrescendo).
- [ ] Add articulations (staccato, accent, tenuto) and dynamics (p, mp, f, ff).

---

## Phase 4: Layout Engine & Engraving Rules
Automating professional-grade formatting and spacing.

### 4.1 Proportional Rhythmic Spacing
- [ ] Replace the constant-width heuristic with duration-proportional spacing (e.g., using a spacing library standard or logarithmic spacing).
- [ ] Handle justification of elements within a measure to distribute space evenly.

### 4.2 System Wrapping & Page Layout
- [ ] Implement system-break algorithms to wrap measures across multiple lines (systems).
- [ ] Implement page margins, headers, footers, and title block layout.
- [ ] Support multi-part scores with page-layout templates.

### 4.3 Collision Avoidance
- [ ] Automatically detect and resolve collisions between:
  - Noteheads and accidentals.
  - Stems/beams and lyrics or articulations.
  - Staves within a system (vertical collision avoidance).

---

## Phase 5: File Import/Export & Audio
Enabling data exchange with other music software.

### 5.1 Native File Format
- [ ] Implement a serialization format (JSON or binary) to save and load `.sagemusic` projects.

### 5.2 Industry Standard XML
- [ ] Implement **MusicXML** import/export to share scores with MuseScore, Finale, and Sibelius.

### 5.3 Audio Playback
- [ ] Integrate a basic MIDI synthesizer or waveform generator.
- [ ] Map note pitches and durations to playback events.
- [ ] Implement a play/pause/stop transport control UI.

---

## Phase 6: Testing & Quality Assurance
Ensuring system stability.

### 6.1 Automated Testing
- [ ] Set up unit testing for the layout justifications in `layout.sage`.
- [ ] Create regression tests for the pitch-to-staff calculation.
- [ ] Implement visual regression tests comparing rendered scores against golden images.

### 6.2 CI/CD Integration
- [ ] Add GitHub Actions CI workflow to run tests on every pull request.
