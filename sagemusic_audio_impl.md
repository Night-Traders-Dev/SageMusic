# SageMusic Audio Engine: Implementation Plan
# Format: [ID] | [PRIORITY] | [MODULE] | Description
# PRIORITY: P1=blocking, P2=core feature, P3=polish
# DEPENDS field listed where ordering is required

---

## PHASE 1: SFIZZ + VSCO2 EMBEDDING

### Build System Integration

AUDIO-SF-1 | P1 | CMakeLists.txt / build.sh
Add sfizz as a submodule or fetched dependency. Repo: https://github.com/sfztools/sfizz
Build as a static library (`SFIZZ_SHARED_LIBRARY=OFF`). Link against SageMusic binary.
Minimum required: sfizz >= 1.2.0. Depends on: libsndfile, JACK or miniaudio backend.

AUDIO-SF-2 | P1 | CMakeLists.txt
Add miniaudio as single-header audio output backend. Drop `miniaudio.h` into `deps/`.
Repo: https://github.com/mackron/miniaudio. Define `MINIAUDIO_IMPLEMENTATION` in exactly one .c/.sage FFI file.
Handles WASAPI (Windows), ALSA/PulseAudio (Linux), CoreAudio (macOS) transparently.

AUDIO-SF-3 | P1 | audio/engine.sage (new file)
Create `AudioEngine` struct wrapping sfizz client handle and miniaudio device.
Fields: `sfizz_handle`, `ma_device`, `sample_rate` (default 48000), `buffer_size` (default 256 frames).
Init order: sfizz_create() -> sfizz_set_samples_per_block() -> sfizz_set_sample_rate() -> ma_device_init().

AUDIO-SF-4 | P1 | audio/engine.sage
Implement miniaudio data callback. On each callback invocation, call `sfizz_render_block(handle, outputs, num_frames)`.
Output is stereo float32. Pass directly to miniaudio output buffer. Keep callback lock-free; no allocations inside callback.

### VSCO2 Asset Pipeline

AUDIO-SF-5 | P1 | assets/sfz/ (new directory)
Download VSCO2 Community Edition SFZ edition.
Source: https://github.com/sgossner/VSCO-2-CE
Place sample .wav files under `assets/sfz/VSCO2/`. Keep directory structure from repo intact.
SFZ descriptor files reference relative paths; do not flatten the directory tree.

AUDIO-SF-6 | P1 | audio/instrument_map.sage (new file)
Build an instrument registry mapping SageMusic instrument names to VSCO2 SFZ file paths.
Example entries:
  "violin_1"       -> "assets/sfz/VSCO2/Strings/Violin/Violin-sus-stac.sfz"
  "cello"          -> "assets/sfz/VSCO2/Strings/Cello/Cello-sus-stac.sfz"
  "flute"          -> "assets/sfz/VSCO2/Woodwinds/Flute/Flute-sus-stac.sfz"
  "trumpet"        -> "assets/sfz/VSCO2/Brass/Trumpet/Trumpet-sus-stac.sfz"
  "snare"          -> "assets/sfz/VSCO2/Percussion/Snare/Snare.sfz"
Expose as a flat dict keyed by instrument name string.

AUDIO-SF-7 | P1 | audio/engine.sage
Implement `load_instrument(name: str)`. Looks up SFZ path from instrument_map, calls
`sfizz_load_file(handle, path)`. Returns bool success. Call once per instrument at score load time, not per note.
Cache loaded instrument state; do not reload on every playback start.

### Note Triggering

AUDIO-SF-8 | P1 | audio/engine.sage
Implement `note_on(channel: int, pitch: int, velocity: int, delay_samples: int)`.
Maps to `sfizz_send_note_on(handle, delay_samples, channel, pitch, velocity)`.
MIDI pitch: middle C = 60. Delay_samples allows sample-accurate scheduling within buffer.

AUDIO-SF-9 | P1 | audio/engine.sage
Implement `note_off(channel: int, pitch: int, delay_samples: int)`.
Maps to `sfizz_send_note_off(handle, delay_samples, channel, pitch, 0)`.
Note_off must be scheduled at note end, accounting for note duration in samples at current tempo.

AUDIO-SF-10 | P1 | audio/engine.sage
Implement `send_cc(channel: int, cc_number: int, value: int, delay_samples: int)`.
Maps to `sfizz_send_hdcc(handle, delay_samples, channel, cc_number, value / 127.0)`.
Used for CC1 (mod/vibrato), CC7 (volume), CC11 (expression). CC11 is the primary dynamic control.

AUDIO-SF-11 | P2 | audio/engine.sage
Implement `send_keyswitch(channel: int, ks_pitch: int, delay_samples: int)`.
Sends a note_on at velocity 1 on the keyswitch pitch. VSCO2 uses low-octave pitches (C-1 to B0) as keyswitches.
Each SFZ file documents its own keyswitch map; read from SFZ `<group>` sw_lokey/sw_hikey tags at load time.

AUDIO-SF-12 | P2 | audio/sequencer.sage (new file)
Implement a sample-accurate event sequencer. Converts score positions (beat + subdivision)
to absolute sample offsets using: `sample_offset = (beat_position / tempo_bpm) * 60.0 * sample_rate`.
Output is a sorted event queue of {sample_offset, event_type, params}. Fill audio buffer by
dequeuing all events whose sample_offset falls within the current buffer window.

---

## PHASE 2: ARTICULATION INFERENCE LAYER

### Score Analysis Pass

AUDIO-ART-1 | P1 | audio/articulation.sage (new file)
Implement `ArticulationAnalyzer` that takes a `Score` and produces a `PerformanceMap`.
`PerformanceMap` is a dict keyed by (part_idx, measure_idx, voice_idx, element_idx) -> `ArticulationEvent`.
`ArticulationEvent` fields: `keyswitch`, `velocity_override`, `duration_scale`, `cc1_value`, `stagger_ms`.
Run once when playback starts or score changes (dirty flag from PERF-AC-7 can trigger this).

AUDIO-ART-2 | P1 | audio/articulation.sage
Implement slur detection. Traverse each voice; when a slur span is open, mark all covered notes
with articulation "legato". First note in slur uses normal attack sample. Subsequent notes use
legato transition keyswitch if VSCO2 instrument provides one, else reduce gap between note_off and
next note_on to 0 samples to simulate legato.

AUDIO-ART-3 | P1 | audio/articulation.sage
Implement single-note articulation detection from note.notations list.
  staccato    -> duration_scale = 0.35, keyswitch = ks_staccato (if available)
  tenuto      -> duration_scale = 1.0, slight velocity boost (+8)
  accent      -> velocity_override = clamp(base_velocity + 25, 0, 127)
  marcato     -> velocity_override = clamp(base_velocity + 35, 0, 127), duration_scale = 0.6
  staccatiss. -> duration_scale = 0.15

AUDIO-ART-4 | P1 | audio/articulation.sage
Implement text expression / playing technique detection from measure or note text markings.
  "pizz."     -> set channel flag pizzicato=true, send pizzicato keyswitch
  "arco"      -> clear pizzicato flag, send sustain keyswitch
  "con sord." -> send mute keyswitch
  "senza sord"-> send normal keyswitch
  "tremolo"   -> send tremolo keyswitch or set LFO rate on CC1
  "flutter"   -> woodwind flutter-tongue: send flutter keyswitch if present

AUDIO-ART-5 | P2 | audio/articulation.sage
Implement trill inference. Notes marked with trill symbol trigger rapid alternation between
written pitch and pitch + interval (default major 2nd, or specified by accidental above trill).
Alternation rate defaults to 8 notes per beat. Generate individual note_on/note_off events
for each alternation into the sequencer event queue at analysis time.

AUDIO-ART-6 | P2 | audio/articulation.sage
Implement lookahead phrase detection. Scan forward up to 4 measures from current position.
If phrase ends with a half/whole note or rest at a cadence point, reduce tempo slightly (rubato)
on approach: scale last 2-4 beat durations by 1.03-1.08. Store tempo multipliers per beat
in a TempoMap alongside the PerformanceMap.

AUDIO-ART-7 | P2 | audio/articulation.sage
Implement ensemble humanization. For each part, generate a random stagger_ms in range [0, 12]
sampled once per note per part (use seeded RNG keyed on part_idx + measure_idx for reproducibility).
Also add per-note velocity jitter: +/- rand(0, 6) after all other velocity calculations.
Apply timing jitter: +/- rand(0, 8) ms on note attack time.

### Instrument-Specific Articulation Maps

AUDIO-ART-8 | P2 | audio/articulation_maps.sage (new file)
Define per-instrument-family articulation capability tables. Structure:
  InstrumentArticMap { family: str, has_legato: bool, has_tremolo: bool,
                       has_pizz: bool, has_flutter: bool, ks_map: dict }
Family groups: "strings", "brass", "woodwind", "perc_pitched", "perc_unpitched", "keys".
Used by ArticulationAnalyzer to skip keyswitches the instrument does not support.

AUDIO-ART-9 | P2 | audio/articulation_maps.sage
Populate VSCO2-specific keyswitch pitch values per instrument SFZ.
These must be read from the actual SFZ files at load time via `sfizz_get_key_labels()` or
by parsing the SFZ `<global>` / `<group>` sw_label tags. Build the ks_map dynamically at
instrument load time rather than hardcoding, as VSCO2 versions differ.

---

## PHASE 3: CC11 DYNAMIC SHAPING

### Dynamic Marking Extraction

AUDIO-DYN-1 | P1 | audio/dynamics.sage (new file)
Implement `DynamicMap` builder. Traverse score and extract all dynamic markings (pp, p, mp, mf, f, ff, fff)
and hairpins (crescendo, diminuendo) with their score positions.
Store as sorted list of `DynamicEvent { position_beats: float, type: str, value: int }`.
Dynamic marking to CC11 base value mapping:
  ppp=10, pp=20, p=35, mp=55, mf=72, f=90, ff=108, fff=120

AUDIO-DYN-2 | P1 | audio/dynamics.sage
Implement hairpin CC11 envelope generation. Between a hairpin's start and end beat positions,
interpolate CC11 from start_value to end_value. Use a logarithmic curve for crescendo
(human hearing is logarithmic) and linear for diminuendo. Generate one CC11 event every
128 samples (approx 2.7ms at 48kHz). Store in the sequencer event queue.

AUDIO-DYN-3 | P1 | audio/dynamics.sage
Implement per-voice dynamic state tracking. Each voice independently tracks current CC11 value.
When a dynamic marking is encountered mid-stream with no preceding hairpin, emit a CC11 event
at the exact beat position transitioning over 1 beat (not instantaneous) to avoid clicks.

AUDIO-DYN-4 | P2 | audio/dynamics.sage
Implement CC1 (mod wheel) shaping for sustain instruments (strings, brass, woodwind).
CC1 controls vibrato/expressiveness in VSCO2. On long notes (>= 1 beat), ramp CC1 from
0 to target_vibrato_depth over the first 20% of the note duration (delayed vibrato).
Target depth per dynamic: p=20, mp=35, mf=50, f=60, ff=70. Percussion and keys: CC1=0 always.

AUDIO-DYN-5 | P2 | audio/dynamics.sage
Implement note-level velocity scaling from CC11. Base velocity is set per dynamic level.
Additionally scale velocity by current CC11 value: `final_velocity = base_velocity * (cc11 / 127.0)`.
This double-dips (velocity layer selection + continuous expression) matching how live players work.

AUDIO-DYN-6 | P2 | audio/dynamics.sage
Implement per-instrument dynamic offset. Different instruments in an ensemble are balanced
differently: brass naturally projects more than strings at notated mf.
Apply balance offsets to CC11 base values:
  strings     -> +0
  woodwinds   -> -5
  brass       -> -15
  pitched perc -> -10
  piano       -> +5
These preserve relative balance when all parts are at the same dynamic marking.

---

## PHASE 4: CONVOLUTION REVERB

### IR Loading

AUDIO-REV-1 | P1 | audio/reverb.sage (new file)
Implement `ImpulseResponse` loader. Read stereo 32-bit float WAV file (IR) using libsndfile or
dr_wav (single-header: https://github.com/mackron/dr_libs). Normalize IR peak to 0.5 to prevent
clipping when convolved with loud signals. Resample to match engine sample_rate using linear
interpolation if IR sample rate differs.

AUDIO-REV-2 | P1 | assets/ir/ (new directory)
Include a concert hall impulse response. Recommended free sources:
  OpenAIR library: https://www.openair.hosted.york.ac.uk/ (CC licensed)
  Recommended IR: "St. George's Episcopal Church" or "Usina del Arte Symphony Hall"
  Target specs: stereo, 48kHz, 2-4 second tail length, ~96000-192000 samples.
Bundle one default IR at `assets/ir/concert_hall_default.wav`.

### Partitioned Convolution Engine

AUDIO-REV-3 | P1 | audio/reverb.sage
Implement partitioned convolution (Overlap-Save method) on CPU as baseline.
Partition IR into segments of size `partition_size` = `buffer_size` (256 samples).
For each partition: FFT(partition) stored in freq_domain at load time.
Per buffer: FFT(input_block) -> complex multiply with each IR partition -> accumulate ->
IFFT(sum) -> overlap-add to output. Use kissfft (MIT, C, single-file) for FFT:
https://github.com/mborgerding/kissfft

AUDIO-REV-4 | P2 | audio/reverb.sage
Implement minimum-phase conversion of IR to reduce pre-ringing and perceived latency.
Cepstral method: FFT(IR) -> log magnitude -> IFFT -> window with causal half-window ->
FFT -> exp -> IFFT. Optional; improves perceived attack transient clarity.

AUDIO-REV-5 | P3 | audio/reverb_gpu.sage (new file)
Implement GPU-accelerated partitioned convolution via Vulkan compute.
Shader pipeline: one compute shader per partition doing complex multiply-accumulate.
Input/output via storage buffers. Use Cooley-Tukey radix-2 FFT in GLSL.
Only dispatch for partitions with non-negligible IR energy (skip near-zero tail partitions).
GPU path is opt-in; fall back to CPU (AUDIO-REV-3) if compute queue unavailable.

### Mixing & Routing

AUDIO-REV-6 | P1 | audio/reverb.sage
Implement wet/dry mix. Final output: `out = (dry_gain * dry_signal) + (wet_gain * reverb_out)`.
Default mix: dry_gain=0.7, wet_gain=0.3. Expose as user-facing parameters.
Wet signal is the convolution output. Dry signal bypasses convolution entirely (zero-latency path).

AUDIO-REV-7 | P2 | audio/reverb.sage
Implement per-instrument-group reverb send levels. Instruments closer to the back of the stage
(in orchestral seating) should send more wet signal.
Send levels by section:
  strings     -> wet=0.28
  woodwinds   -> wet=0.32
  brass       -> wet=0.35
  percussion  -> wet=0.40
  piano       -> wet=0.20
Multiply each instrument's dry output by (1 - send) and wet output by send before summing.

AUDIO-REV-8 | P2 | audio/mix_bus.sage (new file)
Implement a simple mix bus. Sections route to group buses (strings_bus, brass_bus, etc.).
Group buses apply mild EQ (low-shelf at 80Hz, presence at 3kHz) before reverb send.
All buses sum to master bus. Master bus applies soft-knee limiter to prevent clipping
on tutti passages. Limiter threshold: -3dBFS, ratio: 4:1, attack: 5ms, release: 150ms.

---

## NEW FILES SUMMARY

audio/engine.sage          -> sfizz + miniaudio wrapper, note_on/off/cc, sample scheduling
audio/sequencer.sage       -> sample-accurate event queue, beat-to-sample conversion
audio/articulation.sage    -> score analysis pass, PerformanceMap builder
audio/articulation_maps.sage -> per-instrument capability tables, VSCO2 keyswitch maps
audio/dynamics.sage        -> DynamicMap builder, hairpin CC11 envelopes, velocity scaling
audio/reverb.sage          -> IR loader, partitioned convolution (CPU), wet/dry mix
audio/reverb_gpu.sage      -> Vulkan compute FFT convolution (optional GPU path)
audio/mix_bus.sage         -> group buses, EQ, limiter

---

## EXTERNAL DEPENDENCIES

sfizz        | https://github.com/sfztools/sfizz       | MIT    | C++ | submodule or FetchContent
miniaudio    | https://github.com/mackron/miniaudio    | MIT    | C   | single header
kissfft      | https://github.com/mborgerding/kissfft  | BSD    | C   | single header, for CPU FFT
dr_wav       | https://github.com/mackron/dr_libs      | MIT    | C   | single header, for IR loading
VSCO2-CE     | https://github.com/sgossner/VSCO-2-CE   | CC0    | SFZ | asset directory
OpenAIR IR   | https://www.openair.hosted.york.ac.uk/  | CC-BY  | WAV | one default IR bundled

---

## TOTALS

Phase 1 (sfizz + VSCO2):          12 tasks | P1: 9  | P2: 3  | P3: 0
Phase 2 (Articulation Inference):   9 tasks | P1: 4  | P2: 5  | P3: 0
Phase 3 (CC11 Dynamic Shaping):     6 tasks | P1: 3  | P2: 3  | P3: 0
Phase 4 (Convolution Reverb):       8 tasks | P1: 3  | P2: 4  | P3: 1
Total:                             35 tasks | P1: 19 | P2: 15 | P3: 1

---

## IMPLEMENTATION ORDER

1.  AUDIO-SF-1   P1 — sfizz submodule + build system link
2.  AUDIO-SF-2   P1 — miniaudio single-header drop-in
3.  AUDIO-SF-3   P1 — AudioEngine struct and init sequence
4.  AUDIO-SF-4   P1 — miniaudio callback wired to sfizz render
5.  AUDIO-SF-5   P1 — VSCO2 asset directory placed under assets/sfz/
6.  AUDIO-SF-6   P1 — instrument_map registry
7.  AUDIO-SF-7   P1 — load_instrument() with sfizz_load_file()
8.  AUDIO-SF-8   P1 — note_on() implementation
9.  AUDIO-SF-9   P1 — note_off() implementation
10. AUDIO-SF-10  P1 — send_cc() for CC11
11. AUDIO-SF-12  P2 — sample-accurate sequencer (beat -> sample offset)
12. AUDIO-DYN-1  P1 — DynamicMap extraction from score
13. AUDIO-DYN-2  P1 — hairpin CC11 envelope generation
14. AUDIO-DYN-3  P1 — per-voice dynamic state tracking
15. AUDIO-ART-1  P1 — ArticulationAnalyzer scaffold + PerformanceMap
16. AUDIO-ART-2  P1 — slur -> legato detection
17. AUDIO-ART-3  P1 — single-note articulation (staccato/tenuto/accent)
18. AUDIO-ART-4  P1 — text expression detection (pizz/arco/mute)
19. AUDIO-REV-1  P1 — IR WAV loader + normalization
20. AUDIO-REV-2  P1 — bundle default concert hall IR
21. AUDIO-REV-3  P1 — CPU partitioned convolution (kissfft)
22. AUDIO-REV-6  P1 — wet/dry mix output
23. AUDIO-SF-11  P2 — keyswitch sending
24. AUDIO-DYN-4  P2 — CC1 vibrato shaping
25. AUDIO-DYN-5  P2 — velocity scaling from CC11
26. AUDIO-DYN-6  P2 — per-instrument dynamic balance offsets
27. AUDIO-ART-5  P2 — trill note generation
28. AUDIO-ART-6  P2 — phrase lookahead + rubato
29. AUDIO-ART-7  P2 — ensemble humanization (stagger + jitter)
30. AUDIO-ART-8  P2 — instrument articulation capability tables
31. AUDIO-ART-9  P2 — VSCO2 keyswitch map from SFZ tags
32. AUDIO-REV-7  P2 — per-section reverb send levels
33. AUDIO-REV-8  P2 — mix bus with group EQ and limiter
34. AUDIO-REV-4  P2 — minimum-phase IR conversion
35. AUDIO-REV-5  P3 — Vulkan compute GPU convolution path
