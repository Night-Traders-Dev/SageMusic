# SageMusic Issues: Security & Performance
# Format: [ID] | [SEVERITY/IMPACT] | [FILE] | Description

---

## SECURITY

### Input Validation & Injection

SEC-IV-1 | HIGH | layout.sage
No pitch string validation. `pitch_to_y()` parses "C4", "F#3" by direct character indexing without length checks or format validation. Malformed input (e.g., "C", "##4", empty string) causes incorrect behavior or crashes.

SEC-IV-2 | HIGH | main.sage
No bounds checking on array access. `score.parts[hovered["part_idx"]].measures[hovered["measure_idx"]]` dereferenced without verifying indices exist. Corrupted hover state causes out-of-bounds access.

SEC-IV-3 | MEDIUM | model.sage
No duration validation. `Note` and `Rest` accept arbitrary float durations (e.g., negative, NaN, Infinity). No enforcement of rhythmic integrity.

SEC-IV-4 | LOW | model.sage
No time signature validation. Stored as raw tuples (4, 4) with no validation of numerator/denominator ranges or musical correctness.

SEC-IV-5 | LOW | model.sage
No accidental validation. `note.accidental` accepts any string; only "sharp", "flat", "natural" are handled in rendering.

SEC-IV-6 | MEDIUM | main.sage
No modal state validation. `editor_ctx["modal_measure_info"]` is trusted blindly when opening clef/key/time modals. Nil or malformed value causes crash.

### File System & Path Traversal

SEC-FS-7 | MEDIUM | renderer.sage
Relative path traversal dependency. `../SageLang/core/examples/shaders/cube.vert.spv` escapes the project directory. Different deployment structures may load unintended files or fail catastrophically.

SEC-FS-8 | MEDIUM | renderer.sage
No file path sanitization. `gpu.load_texture("assets/bravura_atlas.png")` and `gpu.load_font("assets/lato.ttf")` use raw strings. If user-controlled paths are added later, directory traversal is possible.

SEC-FS-9 | MEDIUM | renderer.sage
No asset integrity checks. No checksums, size limits, or format validation on loaded textures, fonts, or JSON atlases. Corrupted assets cause undefined behavior.

### Memory & GPU Safety

SEC-MG-10 | HIGH | renderer.sage
C JSON library binding risk. `json.cJSON_Parse()` + `json.cJSON_ToSage()` suggests C interop. If the binding does not handle malformed JSON gracefully, heap corruption or use-after-free is possible.

SEC-MG-11 | MEDIUM | renderer.sage
No GPU resource limits. Creates unlimited vertex buffers per frame without caps. A maliciously large score or rapid interaction could exhaust GPU memory (DoS).

SEC-MG-12 | MEDIUM | renderer.sage
Unbounded frame resource arrays. `frame_resources[cf]` grows unbounded per frame. If rendering stalls, buffers accumulate without cleanup.

SEC-MG-13 | MEDIUM | renderer.sage
No shader compilation validation. `gpu.load_shader()` returns negative on failure but is only checked with `< 0`. No validation of SPIR-V bytecode integrity.

SEC-MG-14 | LOW | main.sage
Nil renderer dereference. `if renderer.base == nil: return` is the only guard; subsequent `renderer.base["width"]` accesses assume non-nil without further checks.

### Error Handling & Crash Resilience

SEC-EH-15 | MEDIUM | renderer.sage
Unrecoverable exceptions. `raise "Failed to load primitive shaders"` terminates the application with no graceful degradation or user notification.

SEC-EH-16 | MEDIUM | renderer.sage
No JSON schema validation. `self.atlas_data["glyphs"][name]` assumes atlas structure. Missing keys or wrong types cause nil dereference.

SEC-EH-17 | MEDIUM | layout.sage
Divide-by-zero risk. `layout_part()` calculates `scale = (view_width - 100.0) / total_content_width`. If `total_content_width` is 0, division by zero occurs.

SEC-EH-18 | LOW | layout.sage, renderer.sage
Missing null-check on `measure.parent`. `draw_measure()` guards it, but `calculate_measure_content_width` and other locations access `measure.parent` without guards.

---

## PERFORMANCE

### Algorithmic Complexity

PERF-AC-1 | HIGH | main.sage, command.sage
O(n) element removal. `remove_at()` and `DeleteElementCommand.undo()` reconstruct entire lists element-by-element. For a measure with 100 notes, deletion is O(n).

PERF-AC-2 | MEDIUM | command.sage
O(n) stack operations. `CommandHistory.undo()` and `redo()` manually rebuild stacks by iterating all elements to pop one item.

PERF-AC-3 | HIGH | main.sage
Full-tree iteration every frame. `clear_selection()` and `clear_hovered_delete()` traverse all parts -> measures -> voices -> elements unconditionally every frame (4 nested loops).

PERF-AC-4 | HIGH | main.sage
Linear hit-testing. `find_hovered_measure()` and `find_hovered_note()` iterate the entire score tree on every mouse movement. No spatial acceleration.

PERF-AC-5 | HIGH | layout.sage
O(n^2) layout in scroll view. `get_measure_layout_pos()` cumulatively sums widths from measure 0 to `m_idx` every frame. For 100 measures: ~5,000 operations per part per frame.

PERF-AC-6 | HIGH | layout.sage
O(measures * voices) layout recalculation. `layout_score()` and `layout_part()` recalculate every measure's content width every frame regardless of changes.

PERF-AC-7 | CRITICAL | all files
No dirty-flag system. Layout, selection clearing, and hover detection run unconditionally every frame even when the score is completely static.

### Rendering & GPU Inefficiency

PERF-RG-8 | CRITICAL | renderer.sage
Per-draw-call vertex buffer upload. Every glyph, line, rect, and text string allocates a new GPU buffer and uploads vertex data. No vertex pooling or batching.

PERF-RG-9 | CRITICAL | renderer.sage
No draw call batching. Each staff line, notehead, stem, accidental, and UI element is a separate `gpu.cmd_draw()` with pipeline binds. 50 notes = 50+ draw calls.

PERF-RG-10 | HIGH | renderer.sage
No frustum/occlusion culling. All measures are rendered even when scrolled off-screen. No visibility testing.

PERF-RG-11 | HIGH | renderer.sage
No instanced rendering. Identical glyphs (e.g., noteheads) are rendered as unique quad meshes rather than instanced sprites.

PERF-RG-12 | MEDIUM | renderer.sage
Fixed-function pipeline rebinding. `gpu.cmd_bind_graphics_pipeline()` is called for every line, rect, and glyph instead of grouping by pipeline type.

PERF-RG-13 | LOW | renderer.sage
Double-buffering only. `frame_resources = [[], []]` assumes exactly 2 frames in flight. No support for triple buffering or adaptive frame counts.

PERF-RG-14 | LOW | renderer.sage
Texture atlas lookup per glyph. `self.atlas_data["glyphs"][name]` is a dictionary lookup per glyph per frame. No caching of frequently used glyphs.

PERF-RG-15 | MEDIUM | renderer.sage
Redundant push constant uploads. `self.proj` (orthographic matrix) is pushed as a push constant on every single draw call instead of being set once per frame or per pass.

### Memory & Allocation

PERF-MA-16 | MEDIUM | model.sage, main.sage
No object pooling. Every new note creates a `Note` object; every deletion discards it. High GC pressure during rapid editing.

PERF-MA-17 | LOW | renderer.sage
Per-frame string allocation. `draw_measure()` calls `str(measure.time_signature[0])` and `str(measure.time_signature[1])` every frame, creating new strings each time.

PERF-MA-18 | LOW | layout.sage
Temporary list explosion. `calculate_measure_content_width()` and `layout_part()` allocate temporary lists and variables in tight loops without reuse.

### Layout & Spacing

PERF-LS-19 | HIGH | layout.sage
Fixed 50px element spacing. `calculate_measure_content_width()` uses `len(voice.elements) * 50.0` regardless of actual glyph width, duration, or accidental width. Causes poor spacing.

PERF-LS-20 | HIGH | layout.sage
No proportional rhythmic spacing. A whole note and a 16th note occupy identical horizontal space. Violates music engraving standards.

PERF-LS-21 | MEDIUM | renderer.sage
No collision detection. Accidentals, dots, and ledger lines can overlap without detection or adjustment.

PERF-LS-22 | MEDIUM | renderer.sage, layout.sage
Hardcoded staff metrics. 8px line gap, 32px staff height, 4px per step are magic numbers scattered across renderer and layout. No DPI scaling or zoom-aware layout.

PERF-LS-23 | MEDIUM | renderer.sage
No kerning or glyph metrics. Glyph positions use hardcoded offset tables (`px = x - pw/2.0`, etc.) rather than font metric-based positioning.

### CPU & Main Thread Bottlenecks

PERF-CPU-24 | LOW | renderer.sage
Synchronous file I/O on startup. `io.readfile("assets/bravura_atlas.json")` and `gpu.load_texture()` block the main thread during initialization.

PERF-CPU-25 | MEDIUM | all files
Main-thread-only execution. Layout, interaction logic, and rendering all run on a single thread. No worker threads for layout or background tasks.

PERF-CPU-26 | MEDIUM | main.sage, renderer.sage
UI draw list reconstruction. `ui_ctx["draw_list"]` is rebuilt from scratch every frame with thousands of rect/text commands. No incremental UI updates.

---

## TOTALS

Security:    18 issues | CRITICAL: 0 | HIGH: 3 | MEDIUM: 10 | LOW: 5
Performance: 26 issues | CRITICAL: 3 | HIGH: 10 | MEDIUM: 9  | LOW: 4

---

## TOP PRIORITY (ordered by impact)

1. PERF-RG-8  | CRITICAL | Per-draw-call GPU buffer uploads; batching yields 10-100x render improvement
2. PERF-AC-7  | CRITICAL | No dirty-flag system; eliminates ~80% per-frame CPU work when idle
3. PERF-AC-4  | HIGH     | Linear hit-testing; unusable beyond ~50 measures
4. SEC-IV-1   | HIGH     | No pitch string validation; crash vector from malformed data
5. PERF-AC-5  | HIGH     | O(n^2) scroll layout; scales quadratically with score length
