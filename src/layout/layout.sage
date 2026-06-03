# -----------------------------------------
# layout.sage - SageMusic Notation Layout Engine
# Handles spacing, rhythmic alignment, and bounds calculation
# -----------------------------------------

proc layout_score(score, view_width):
    # Iterate through all parts and calculate measure sizes
    let p_idx = 0
    while p_idx < len(score.parts):
        let part = score.parts[p_idx]
        layout_part(part, view_width)
        p_idx = p_idx + 1

proc layout_part(part, view_width):
    # 1. Calculate ideal width for each measure based on content
    let total_content_width = 0.0
    let m_idx = 0
    while m_idx < len(part.measures):
        let measure = part.measures[m_idx]
        let content_w = calculate_measure_content_width(measure)
        measure.width = content_w
        total_content_width = total_content_width + content_w
        m_idx = m_idx + 1
    
    # 2. Horizontal Justification (casting off)
    # If total width < view_width, expand measures to fit
    if total_content_width < view_width - 100.0:
        let scale = (view_width - 100.0) / total_content_width
        let j_idx = 0
        while j_idx < len(part.measures):
            part.measures[j_idx].width = part.measures[j_idx].width * scale
            j_idx = j_idx + 1

proc calculate_measure_content_width(measure):
    # Simple heuristic: padding + (count of elements * constant)
    let max_voice_w = 0.0
    let v_idx = 0
    while v_idx < len(measure.voices):
        let voice = measure.voices[v_idx]
        let voice_w = len(voice.elements) * 50.0 # 50 units per element
        if voice_w > max_voice_w:
            max_voice_w = voice_w
        v_idx = v_idx + 1
    
    let draw_clef = true
    if measure.parent != nil:
        if len(measure.parent.measures) > 0:
            if measure.parent.measures[0] != measure:
                draw_clef = false

    let extra_w = 35.0
    if draw_clef:
        extra_w = 80.0
    return max_voice_w + extra_w

# Pitch to Y-coordinate mapping
# clef: "treble", "bass", etc.
# pitch: "C4", "D4", etc.
proc pitch_to_y(clef, pitch):
    if len(pitch) < 2:
        return 0.0

    let letter = pitch[0]
    let step_idx = 0
    if letter == "C" or letter == "c":
        step_idx = 0
    elif letter == "D" or letter == "d":
        step_idx = 1
    elif letter == "E" or letter == "e":
        step_idx = 2
    elif letter == "F" or letter == "f":
        step_idx = 3
    elif letter == "G" or letter == "g":
        step_idx = 4
    elif letter == "A" or letter == "a":
        step_idx = 5
    elif letter == "B" or letter == "b":
        step_idx = 6

    let oct_char = pitch[len(pitch) - 1]
    let octave = int(oct_char)

    let diatonic_val = octave * 7 + step_idx

    let ref_val = 30 # default Treble Clef
    if clef == "treble":
        ref_val = 30
    elif clef == "bass":
        ref_val = 18
    elif clef == "alto":
        ref_val = 24
    elif clef == "tenor":
        ref_val = 22

    let pos = diatonic_val - ref_val
    return pos * 4.0 # 4 pixels per staff step

# Maps staff position step back to a pitch name
proc y_to_pitch(clef, pos):
    let ref_val = 30
    if clef == "treble":
        ref_val = 30
    elif clef == "bass":
        ref_val = 18
    elif clef == "alto":
        ref_val = 24
    elif clef == "tenor":
        ref_val = 22
        
    let diatonic_val = pos + ref_val
    let octave = int(diatonic_val / 7)
    let step_idx = diatonic_val - octave * 7
    
    # Handle octave offset for negative step index
    if step_idx < 0:
        octave = octave - 1
        step_idx = step_idx + 7

    let letter = "C"
    if step_idx == 0:
        letter = "C"
    elif step_idx == 1:
        letter = "D"
    elif step_idx == 2:
        letter = "E"
    elif step_idx == 3:
        letter = "F"
    elif step_idx == 4:
        letter = "G"
    elif step_idx == 5:
        letter = "A"
    elif step_idx == 6:
        letter = "B"
        
    return letter + str(octave)
