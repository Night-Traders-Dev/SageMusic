# -----------------------------------------
# main.sage - SageMusic Main Application
# Orchestrates UI, Renderer, and Interaction
# -----------------------------------------

import gpu
import graphics.ui as ui
import graphics.renderer as base_renderer

# Local imports
from model import create_empty_score, Note, Rest, Measure
from renderer import MusicRenderer
from layout import layout_score, y_to_pitch, pitch_to_y

# Helper to remove element at index
proc remove_at(lst, idx):
    let new_list = []
    let i = 0
    while i < len(lst):
        if i != idx:
            push(new_list, lst[i])
        i = i + 1
    return new_list

# Helper to clear selection flag on all music elements
proc clear_selection(score):
    let p_idx = 0
    while p_idx < len(score.parts):
        let part = score.parts[p_idx]
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            let v_idx = 0
            while v_idx < len(measure.voices):
                let voice = measure.voices[v_idx]
                let e_idx = 0
                while e_idx < len(voice.elements):
                    voice.elements[e_idx].selected = false
                    voice.elements[e_idx].hovered_delete = false
                    e_idx = e_idx + 1
                v_idx = v_idx + 1
            m_idx = m_idx + 1
        p_idx = p_idx + 1

# Helper to clear hover delete flag on all music elements
proc clear_hovered_delete(score):
    let p_idx = 0
    while p_idx < len(score.parts):
        let part = score.parts[p_idx]
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            let v_idx = 0
            while v_idx < len(measure.voices):
                let voice = measure.voices[v_idx]
                let e_idx = 0
                while e_idx < len(voice.elements):
                    voice.elements[e_idx].hovered_delete = false
                    e_idx = e_idx + 1
                v_idx = v_idx + 1
            m_idx = m_idx + 1
        p_idx = p_idx + 1

# Helper to find which measure boundaries enclose the mouse coordinate
proc find_hovered_measure(score, mx, my):
    let cur_y = 100.0
    let part_idx = 0
    while part_idx < len(score.parts):
        let part = score.parts[part_idx]
        let cur_x = 50.0
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            if mx >= cur_x and mx <= cur_x + measure.width:
                if my >= cur_y - 40.0 and my <= cur_y + 32.0 + 40.0:
                    let res = {}
                    res["part_idx"] = part_idx
                    res["measure_idx"] = m_idx
                    res["measure_x"] = cur_x
                    res["measure_y"] = cur_y
                    return res
            cur_x = cur_x + measure.width
            m_idx = m_idx + 1
        cur_y = cur_y + 200.0
        part_idx = part_idx + 1
    return nil

# Helper to find which note/rest the mouse coordinates lie within a small radius of
proc find_hovered_note(score, mx, my):
    let cur_y = 100.0
    let part_idx = 0
    while part_idx < len(score.parts):
        let part = score.parts[part_idx]
        let cur_x = 50.0
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            let v_idx = 0
            while v_idx < len(measure.voices):
                let voice = measure.voices[v_idx]
                let elem_x = cur_x + 20.0
                let e_idx = 0
                while e_idx < len(voice.elements):
                    let elem = voice.elements[e_idx]
                    if type(elem) == "Note":
                        let step_offset = pitch_to_y(measure.clef, elem.pitch)
                        let elem_y = cur_y + 32.0 - step_offset
                        let dx = mx - elem_x
                        let dy = my - elem_y
                        if dx * dx + dy * dy < 225.0: # 15px radius
                            let res = {}
                            res["part_idx"] = part_idx
                            res["measure_idx"] = m_idx
                            res["voice_idx"] = v_idx
                            res["element_idx"] = e_idx
                            return res
                    elif type(elem) == "Rest":
                        let elem_y = cur_y + 16.0
                        let dx = mx - elem_x
                        let dy = my - elem_y
                        if dx * dx + dy * dy < 225.0: # 15px radius
                            let res = {}
                            res["part_idx"] = part_idx
                            res["measure_idx"] = m_idx
                            res["voice_idx"] = v_idx
                            res["element_idx"] = e_idx
                            return res
                    elem_x = elem_x + 50.0
                    e_idx = e_idx + 1
                v_idx = v_idx + 1
            cur_x = cur_x + measure.width
            m_idx = m_idx + 1
        cur_y = cur_y + 200.0
        part_idx = part_idx + 1
    return nil

proc main():
    print "Starting SageMusic..."
    
    # 1. Initialize Renderer
    let renderer = MusicRenderer(1280, 720)
    if renderer.base == nil:
        print "Failed to initialize GPU renderer"
        return

    # 2. Create UI Context
    let ui_ctx = ui.ui_create()
    
    # 3. Initialize Data Model
    let score = create_empty_score("Untitled Symphony")
    
    # Add some demo notes to Measure 1 (Treble Clef)
    let v1 = score.parts[0].measures[0].get_voice(0)
    v1.add_element(Note("C4", 0.25))
    v1.add_element(Note("E4", 0.25))
    v1.add_element(Note("G4", 0.25))
    v1.add_element(Rest(0.25))

    # Measure 2 (Bass Clef)
    let m2 = score.parts[0].measures[1]
    m2.clef = "bass"
    let v2 = m2.get_voice(0)
    v2.add_element(Note("G2", 0.25))
    v2.add_element(Note("B2", 0.25))
    v2.add_element(Note("D3", 0.25))
    v2.add_element(Note("F#3", 0.25))

    # Measure 3 (Alto Clef)
    let m3 = score.parts[0].measures[2]
    m3.clef = "alto"
    let v3 = m3.get_voice(0)
    v3.add_element(Note("F3", 0.25))
    v3.add_element(Note("C4", 0.25))
    v3.add_element(Note("E4", 0.25))
    v3.add_element(Note("G4", 0.25))

    # Measure 4 (Treble Clef - Ledger lines & Flats)
    let m4 = score.parts[0].measures[3]
    m4.clef = "treble"
    let v4 = m4.get_voice(0)
    v4.add_element(Note("A3", 0.25)) # Ledger line below
    v4.add_element(Note("C4", 0.25)) # Ledger line below
    v4.add_element(Note("Bb4", 0.25)) # Flat accidental
    v4.add_element(Note("A5", 0.25)) # Ledger line above

    # Editor State Context
    let editor_ctx = {}
    editor_ctx["current_tool"] = "note_entry"
    editor_ctx["selected_duration"] = 0.25
    editor_ctx["selected_element"] = nil
    editor_ctx["selected_element_info"] = nil

    # 4. Main Loop
    while true:
        let frame_info = renderer.begin_frame()
        if frame_info == nil:
            break
            
        # UI Pass - Start
        ui.ui_begin_frame(ui_ctx)
        
        # Handle hotkeys
        if gpu.key_just_pressed(gpu.KEY_S):
            editor_ctx["current_tool"] = "select"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
        elif gpu.key_just_pressed(gpu.KEY_N):
            editor_ctx["current_tool"] = "note_entry"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
        elif gpu.key_just_pressed(gpu.KEY_E):
            editor_ctx["current_tool"] = "eraser"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        if gpu.key_just_pressed(gpu.KEY_1):
            editor_ctx["selected_duration"] = 1.0
        elif gpu.key_just_pressed(gpu.KEY_2):
            editor_ctx["selected_duration"] = 0.5
        elif gpu.key_just_pressed(gpu.KEY_3):
            editor_ctx["selected_duration"] = 0.25
        elif gpu.key_just_pressed(gpu.KEY_4):
            editor_ctx["selected_duration"] = 0.125
        elif gpu.key_just_pressed(gpu.KEY_5):
            editor_ctx["selected_duration"] = 0.0625

        # Draw Main Sidebar
        ui.ui_draw_rect(ui_ctx, 0, 0, 250, 720, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 20, 20, "SageMusic v1.0")
        
        # Tools palette
        ui.ui_label(ui_ctx, 20, 60, "Tool Palette")
        let tool_y = 80
        
        let select_label = "Select Tool"
        if editor_ctx["current_tool"] == "select":
            select_label = "[Select Tool]"
        if ui.ui_button(ui_ctx, 20, tool_y, 210, 30, select_label):
            editor_ctx["current_tool"] = "select"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        let note_label = "Note Entry Tool"
        if editor_ctx["current_tool"] == "note_entry":
            note_label = "[Note Entry Tool]"
        if ui.ui_button(ui_ctx, 20, tool_y + 40, 210, 30, note_label):
            editor_ctx["current_tool"] = "note_entry"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        let eraser_label = "Eraser Tool"
        if editor_ctx["current_tool"] == "eraser":
            eraser_label = "[Eraser Tool]"
        if ui.ui_button(ui_ctx, 20, tool_y + 80, 210, 30, eraser_label):
            editor_ctx["current_tool"] = "eraser"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        # Duration selection panel
        ui.ui_label(ui_ctx, 20, 220, "Duration Palette")
        let dur_y = 240
        
        let d_1_0_label = "Whole (1.0)"
        if editor_ctx["selected_duration"] == 1.0:
            d_1_0_label = "[Whole (1.0)]"
        if ui.ui_button(ui_ctx, 20, dur_y, 210, 30, d_1_0_label):
            editor_ctx["selected_duration"] = 1.0
            
        let d_0_5_label = "Half (0.5)"
        if editor_ctx["selected_duration"] == 0.5:
            d_0_5_label = "[Half (0.5)]"
        if ui.ui_button(ui_ctx, 20, dur_y + 40, 210, 30, d_0_5_label):
            editor_ctx["selected_duration"] = 0.5
            
        let d_0_25_label = "Quarter (0.25)"
        if editor_ctx["selected_duration"] == 0.25:
            d_0_25_label = "[Quarter (0.25)]"
        if ui.ui_button(ui_ctx, 20, dur_y + 80, 210, 30, d_0_25_label):
            editor_ctx["selected_duration"] = 0.25
            
        let d_0_125_label = "Eighth (0.125)"
        if editor_ctx["selected_duration"] == 0.125:
            d_0_125_label = "[Eighth (0.125)]"
        if ui.ui_button(ui_ctx, 20, dur_y + 120, 210, 30, d_0_125_label):
            editor_ctx["selected_duration"] = 0.125
            
        let d_0_0625_label = "Sixteenth (0.0625)"
        if editor_ctx["selected_duration"] == 0.0625:
            d_0_0625_label = "[Sixteenth (0.0625)]"
        if ui.ui_button(ui_ctx, 20, dur_y + 160, 210, 30, d_0_0625_label):
            editor_ctx["selected_duration"] = 0.0625

        ui.ui_label(ui_ctx, 20, 470, "Shortcuts:")
        ui.ui_label(ui_ctx, 20, 490, "S: Select Tool")
        ui.ui_label(ui_ctx, 20, 510, "N: Note Entry")
        ui.ui_label(ui_ctx, 20, 530, "E: Eraser Tool")
        ui.ui_label(ui_ctx, 20, 550, "1-5: Select Durations")
        ui.ui_label(ui_ctx, 20, 570, "Del/Bksp: Delete Note")
        
        # UI Pass - End
        ui.ui_end_frame(ui_ctx)
        
        # Interaction Logic
        clear_hovered_delete(score)
        let mx = ui_ctx["mouse_x"]
        let my = ui_ctx["mouse_y"]
        let is_over_score = mx > 250
        
        let hovered = find_hovered_measure(score, mx, my)
        
        if is_over_score and hovered != nil:
            let part = score.parts[hovered["part_idx"]]
            let measure = part.measures[hovered["measure_idx"]]
            let voice = measure.get_voice(0)
            
            # Note Entry
            if editor_ctx["current_tool"] == "note_entry":
                let pos = int((hovered["measure_y"] + 32.0 - my + 2.0) / 4.0)
                let pitch = y_to_pitch(measure.clef, pos)
                
                let preview_y = hovered["measure_y"] + 32.0 - pos * 4.0
                let preview = {}
                preview["x"] = mx
                preview["y"] = preview_y
                preview["duration"] = editor_ctx["selected_duration"]
                renderer.preview_info = preview
                
                if ui_ctx["mouse_clicked"]:
                    voice.add_element(Note(pitch, editor_ctx["selected_duration"]))
            else:
                renderer.preview_info = nil
                
            # Eraser
            if editor_ctx["current_tool"] == "eraser":
                let note_hover = find_hovered_note(score, mx, my)
                if note_hover != nil:
                    let target_measure = score.parts[note_hover["part_idx"]].measures[note_hover["measure_idx"]]
                    let target_voice = target_measure.voices[note_hover["voice_idx"]]
                    let target_elem = target_voice.elements[note_hover["element_idx"]]
                    target_elem.hovered_delete = true
                    
                    if ui_ctx["mouse_clicked"]:
                        target_voice.elements = remove_at(target_voice.elements, note_hover["element_idx"])
                        
            # Select
            if editor_ctx["current_tool"] == "select":
                let note_hover = find_hovered_note(score, mx, my)
                if ui_ctx["mouse_clicked"]:
                    clear_selection(score)
                    editor_ctx["selected_element"] = nil
                    if note_hover != nil:
                        let target_measure = score.parts[note_hover["part_idx"]].measures[note_hover["measure_idx"]]
                        let target_voice = target_measure.voices[note_hover["voice_idx"]]
                        let target_elem = target_voice.elements[note_hover["element_idx"]]
                        target_elem.selected = true
                        editor_ctx["selected_element"] = target_elem
                        editor_ctx["selected_element_info"] = note_hover
        else:
            renderer.preview_info = nil
            
        # Keyboard element deletion
        if editor_ctx["selected_element"] != nil:
            if gpu.key_just_pressed(gpu.KEY_DELETE) or gpu.key_just_pressed(gpu.KEY_BACKSPACE):
                let info = editor_ctx["selected_element_info"]
                let target_measure = score.parts[info["part_idx"]].measures[info["measure_idx"]]
                let target_voice = target_measure.voices[info["voice_idx"]]
                target_voice.elements = remove_at(target_voice.elements, info["element_idx"])
                editor_ctx["selected_element"] = nil
        
        # Layout Pass (only if dirty, but every frame for now)
        layout_score(score, 1280.0 - 250.0) # score width minus sidebar
        
        # Rendering Pass
        renderer.draw_score(frame_info, score)
        
        # Draw UI on top
        renderer.draw_ui(frame_info["cmd"], ui_ctx)
        
        renderer.end_frame(frame_info)

main()
