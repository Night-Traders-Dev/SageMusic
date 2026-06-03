# -----------------------------------------
# layout.sage - SageMusic Notation Layout Engine
# Handles spacing, rhythmic alignment, and bounds calculation
# -----------------------------------------

# Staff metrics constants
let STAFF_LINE_GAP = 8.0
let STAFF_HEIGHT = 32.0
let STAFF_STEP = 4.0

proc layout_score(score, view_width, view_mode):
    # Iterate through all parts and calculate measure sizes
    let p_idx = 0
    while p_idx < len(score.parts):
        let part = score.parts[p_idx]
        
        # PERF-AC-6: Only layout part if it's dirty
        if part.dirty:
            layout_part(part, view_width)
            
            # 3. Calculate and cache absolute positions based on view_mode
            # This addresses PERF-AC-5 by moving summation to the layout pass
            let cur_x = 270.0
            let m_idx = 0
            while m_idx < len(part.measures):
                let measure = part.measures[m_idx]
                if view_mode == "scroll":
                    measure.layout_x = cur_x
                    measure.layout_y = 100.0 + p_idx * 200.0
                    cur_x = cur_x + measure.width
                else: # "page"
                    let sys_idx = int(m_idx / 2)
                    let local_m_idx = m_idx % 2
                    
                    let px = 270.0
                    if local_m_idx == 1:
                        px = 270.0 + part.measures[sys_idx * 2].width
                    
                    measure.layout_x = px
                    measure.layout_y = 100.0 + sys_idx * 380.0 + p_idx * 100.0
                m_idx = m_idx + 1
            
            part.dirty = false
            
        p_idx = p_idx + 1

proc layout_part(part, view_width):
    # 1. Calculate ideal width for each measure based on content
    let total_content_width = 0.0
    let m_idx = 0
    while m_idx < len(part.measures):
        let measure = part.measures[m_idx]
        
        # PERF-AC-6: Only recalculate measure content if dirty
        if measure.dirty:
            let content_w = calculate_measure_content_width(measure)
            measure.width = content_w
            measure.dirty = false
            
        total_content_width = total_content_width + measure.width
        m_idx = m_idx + 1
    
    # 2. Horizontal Justification (casting off)
    # SEC-EH-17: Divide-by-zero risk fix
    if total_content_width > 0.0 and total_content_width < view_width - 100.0:
        let scale = (view_width - 100.0) / total_content_width
        let j_idx = 0
        while j_idx < len(part.measures):
            part.measures[j_idx].width = part.measures[j_idx].width * scale
            j_idx = j_idx + 1

# Calculate width of a single element based on its duration
proc get_element_width(element):
    # SMuFL spacing heuristic: base width + proportional duration
    return 20.0 + (element.duration * 120.0)

proc calculate_measure_content_width(measure):
    # Improved heuristic: sum of element widths
    let max_voice_w = 0.0
    let v_idx = 0
    while v_idx < len(measure.voices):
        let voice = measure.voices[v_idx]
        let voice_w = 0.0
        let e_idx = 0
        while e_idx < len(voice.elements):
            voice_w = voice_w + get_element_width(voice.elements[e_idx])
            e_idx = e_idx + 1
            
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
        extra_w = 110.0
    return max_voice_w + extra_w

# Pitch to Y-coordinate mapping
# clef: "treble", "bass", etc.
# pitch: "C4", "D4", etc.
proc pitch_to_y(clef, pitch):
    if len(pitch) < 2:
        return 0.0

    let letter = pitch[0]
    let step_idx = -1
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
    
    if step_idx == -1:
        return 0.0

    let oct_char = pitch[len(pitch) - 1]
    if oct_char < "0" or oct_char > "9":
        return 0.0

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
    return pos * STAFF_STEP # 4 pixels per staff step

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

# Calculate x, y coordinate position for a measure based on view mode
proc get_measure_layout_pos(part_idx, m_idx, score, view_mode):
    # This now uses cached values, addressing PERF-AC-5
    let res = {}
    let measure = score.parts[part_idx].measures[m_idx]
    res["x"] = measure.layout_x
    res["y"] = measure.layout_y
    return res
