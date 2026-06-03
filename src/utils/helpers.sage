from layout.layout import STAFF_HEIGHT, get_element_width, pitch_to_y

# Helper to remove element at index
proc remove_at(lst, idx):
    let new_list = []
    let i = 0
    while i < len(lst):
        if i != idx:
            push(new_list, lst[i])
        i = i + 1
    return new_list

# Safe access helpers
proc get_safe_part(score, p_idx):
    if p_idx >= 0 and p_idx < len(score.parts):
        return score.parts[p_idx]
    return nil

proc get_safe_measure(part, m_idx):
    if part != nil and m_idx >= 0 and m_idx < len(part.measures):
        return part.measures[m_idx]
    return nil

proc get_safe_voice(measure, v_idx):
    if measure != nil and v_idx >= 0 and v_idx < len(measure.voices):
        return measure.voices[v_idx]
    return nil

proc get_safe_element(voice, e_idx):
    if voice != nil and e_idx >= 0 and e_idx < len(voice.elements):
        return voice.elements[e_idx]
    return nil

# Helper to find which measure boundaries enclose the mouse coordinate
proc find_hovered_measure(score, mx, my, view_mode):
    let part_idx = 0
    while part_idx < len(score.parts):
        let part = score.parts[part_idx]
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            let cur_x = measure.layout_x
            let cur_y = measure.layout_y
            
            # Spatial pruning: if mx is before this measure, it can't be in any subsequent measure in this part (scroll mode)
            if view_mode == "scroll" and mx < cur_x:
                break

            if mx >= cur_x and mx <= cur_x + measure.width:
                if my >= cur_y - 40.0 and my <= cur_y + STAFF_HEIGHT + 40.0:
                    let res = {}
                    res["part_idx"] = part_idx
                    res["measure_idx"] = m_idx
                    res["measure_x"] = cur_x
                    res["measure_y"] = cur_y
                    return res
            m_idx = m_idx + 1
        part_idx = part_idx + 1
    return nil

# Helper to find which note/rest the mouse coordinates lie within a small radius of
proc find_hovered_note(score, mx, my, view_mode):
    let part_idx = 0
    while part_idx < len(score.parts):
        let part = score.parts[part_idx]
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            let cur_x = measure.layout_x
            let cur_y = measure.layout_y
            
            # Early exit if mouse is not even near this measure
            if mx < cur_x - 50.0 or mx > cur_x + measure.width + 50.0:
                m_idx = m_idx + 1
                continue
                
            let v_idx = 0
            while v_idx < len(measure.voices):
                let voice = measure.voices[v_idx]
                let draw_clef = true
                if measure.parent != nil:
                    if len(measure.parent.measures) > 0:
                        if measure.parent.measures[0] != measure:
                            draw_clef = false
                
                let elem_x = cur_x + 20.0
                if draw_clef:
                    elem_x = cur_x + 65.0
                let e_idx = 0
                while e_idx < len(voice.elements):
                    let elem = voice.elements[e_idx]
                    
                    let elem_w = get_element_width(elem)
                    
                    # Early exit for elements if mx is past them
                    if mx < elem_x - 30.0:
                        break
                    
                    if elem.type == "Note":
                        let step_offset = pitch_to_y(measure.clef, elem.pitch)
                        let elem_y = cur_y + STAFF_HEIGHT - step_offset
                        let dx = mx - elem_x
                        let dy = my - elem_y
                        if dx * dx + dy * dy < 225.0: # 15px radius
                            let res = {}
                            res["part_idx"] = part_idx
                            res["measure_idx"] = m_idx
                            res["voice_idx"] = v_idx
                            res["element_idx"] = e_idx
                            return res
                    elif elem.type == "Rest":
                        let elem_y = cur_y + STAFF_HEIGHT / 2.0
                        let dx = mx - elem_x
                        let dy = my - elem_y
                        if dx * dx + dy * dy < 225.0: # 15px radius
                            let res = {}
                            res["part_idx"] = part_idx
                            res["measure_idx"] = m_idx
                            res["voice_idx"] = v_idx
                            res["element_idx"] = e_idx
                            return res
                    elem_x = elem_x + elem_w
                    e_idx = e_idx + 1
                v_idx = v_idx + 1
            m_idx = m_idx + 1
        part_idx = part_idx + 1
    return nil