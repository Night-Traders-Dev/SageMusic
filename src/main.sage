# -----------------------------------------
# main.sage - SageMusic Main Application
# Orchestrates UI, Renderer, and Interaction
# -----------------------------------------

import gpu
import sys
import graphics.ui as ui
import graphics.renderer as base_renderer

# Local imports
from model.model import create_empty_score, Note, Rest, Measure, Score, Part, get_safe_part, get_safe_measure, get_safe_voice, get_safe_element
from renderer.renderer import MusicRenderer
from layout.layout import layout_score, y_to_pitch, pitch_to_y, get_measure_layout_pos, get_element_width, STAFF_LINE_GAP, STAFF_HEIGHT, STAFF_STEP
from command.command import CommandHistory, AddElementCommand, DeleteElementCommand
from ui.editor_ui import process_editor_ui

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

proc main():
    print "Starting SageMusic..."
    
    # 1. Initialize Renderer
    let renderer = MusicRenderer(1280, 720)
    if renderer.base == nil:
        print "Failed to initialize GPU renderer"
        return

    # 2. Create UI Context
    let ui_ctx = ui.ui_create()
    
    # Initialize Undo/Redo history
    let history = CommandHistory()
    
    # 3. Initialize Data Model with 3 separate parts (staffs)
    let score = Score("Untitled Symphony")
    
    let treble_part = Part("Treble Staff")
    let alto_part = Part("Alto Staff")
    let bass_part = Part("Bass Staff")
    
    let i = 0
    while i < 4:
        let m_treble = Measure()
        m_treble.clef = "treble"
        treble_part.add_measure(m_treble)
        
        let m_alto = Measure()
        m_alto.clef = "alto"
        alto_part.add_measure(m_alto)
        
        let m_bass = Measure()
        m_bass.clef = "bass"
        bass_part.add_measure(m_bass)
        
        i = i + 1
        
    score.add_part(treble_part)
    score.add_part(alto_part)
    score.add_part(bass_part)
    
    # Add some demo notes to Treble Staff, Measure 1
    let v1 = score.parts[0].measures[0].get_voice(0)
    v1.add_element(Note("C4", 0.25))
    v1.add_element(Note("E4", 0.25))
    v1.add_element(Note("G4", 0.25))
    v1.add_element(Rest(0.25))

    # Treble Staff, Measure 2 (Ledger lines & Flats)
    let v4 = score.parts[0].measures[1].get_voice(0)
    v4.add_element(Note("A3", 0.25)) # Ledger line below
    v4.add_element(Note("C4", 0.25)) # Ledger line below
    v4.add_element(Note("Bb4", 0.25)) # Flat accidental
    v4.add_element(Note("A5", 0.25)) # Ledger line above

    # Alto Staff, Measure 1
    let v3 = score.parts[1].measures[0].get_voice(0)
    v3.add_element(Note("F3", 0.25))
    v3.add_element(Note("C4", 0.25))
    v3.add_element(Note("E4", 0.25))
    v3.add_element(Note("G4", 0.25))

    # Alto Staff, Measure 2 (Whole rest)
    let v3_2 = score.parts[1].measures[1].get_voice(0)
    v3_2.add_element(Rest(1.0))

    # Bass Staff, Measure 1
    let v2 = score.parts[2].measures[0].get_voice(0)
    v2.add_element(Note("G2", 0.25))
    v2.add_element(Note("B2", 0.25))
    v2.add_element(Note("D3", 0.25))
    v2.add_element(Note("F#3", 0.25))

    # Bass Staff, Measure 2 (Whole rest)
    let v2_2 = score.parts[2].measures[1].get_voice(0)
    v2_2.add_element(Rest(1.0))

    # Default rests for Measure 3 and 4
    score.parts[0].measures[2].get_voice(0).add_element(Rest(1.0))
    score.parts[0].measures[3].get_voice(0).add_element(Rest(1.0))
    score.parts[1].measures[2].get_voice(0).add_element(Rest(1.0))
    score.parts[1].measures[3].get_voice(0).add_element(Rest(1.0))
    score.parts[2].measures[2].get_voice(0).add_element(Rest(1.0))
    score.parts[2].measures[3].get_voice(0).add_element(Rest(1.0))

    # Editor State Context
    let editor_ctx = {}
    editor_ctx["current_tool"] = "note_entry"
    editor_ctx["selected_duration"] = 0.25
    editor_ctx["selected_accidental"] = nil
    editor_ctx["selected_element"] = nil
    editor_ctx["selected_element_info"] = nil
    editor_ctx["last_mouse_x"] = 0.0
    editor_ctx["last_mouse_y"] = 0.0
    editor_ctx["view_mode"] = "page"
    editor_ctx["active_menu"] = nil
    editor_ctx["modal_active"] = nil
    editor_ctx["modal_measure_info"] = nil
    
    let should_exit = false

    # 4. Main Loop
    while true:
        if should_exit:
            break
        
        if renderer.base == nil:
            break
            
        let frame_info = renderer.begin_frame()
        if frame_info == nil:
            if gpu.window_should_close():
                break
            sys.sleep(0.01)
            gpu.poll_events()
            renderer.recreate_swapchain()
            continue
            
        # UI Pass - Start
        should_exit = process_editor_ui(ui_ctx, editor_ctx, score, history, renderer)
        
        # Interaction Logic
        let mx = ui_ctx["mouse_x"]
        let my = ui_ctx["mouse_y"]
        let mouse_moved = false
        if mx != editor_ctx["last_mouse_x"] or my != editor_ctx["last_mouse_y"]:
            mouse_moved = true
            editor_ctx["last_mouse_x"] = mx
            editor_ctx["last_mouse_y"] = my

        if mouse_moved or ui_ctx["mouse_clicked"] or score.dirty:
            score.clear_hovered_delete()

            let is_over_score = mx > 250 and my > 40 # Account for sidebar and top menu bar
            let hovered = find_hovered_measure(score, mx, my, editor_ctx["view_mode"])

            if is_over_score and hovered != nil and editor_ctx["modal_active"] == nil:
                let part = get_safe_part(score, hovered["part_idx"])
                let measure = get_safe_measure(part, hovered["measure_idx"])

                if measure != nil:
                    let voice = measure.get_voice(0)

                    # Note Entry Tool
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
                            let new_note = Note(pitch, editor_ctx["selected_duration"])
                            if editor_ctx["selected_accidental"] != nil:
                                new_note.set_accidental(editor_ctx["selected_accidental"])
                                editor_ctx["selected_accidental"] = nil # Reset accidental after applying
                            history.execute(AddElementCommand(voice, new_note))
                    else:
                        renderer.preview_info = nil

                    # Eraser Tool
                    if editor_ctx["current_tool"] == "eraser":
                        let note_hover = find_hovered_note(score, mx, my, editor_ctx["view_mode"])
                        if note_hover != nil:
                            let target_part = get_safe_part(score, note_hover["part_idx"])
                            let target_measure = get_safe_measure(target_part, note_hover["measure_idx"])
                            let target_voice = get_safe_voice(target_measure, note_hover["voice_idx"])
                            let target_elem = get_safe_element(target_voice, note_hover["element_idx"])

                            if target_elem != nil:
                                target_elem.hovered_delete = true
                                if ui_ctx["mouse_clicked"]:
                                    history.execute(DeleteElementCommand(target_voice, target_elem))

                    # Select Tool
                    if editor_ctx["current_tool"] == "select":
                        let note_hover = find_hovered_note(score, mx, my, editor_ctx["view_mode"])
                        if ui_ctx["mouse_clicked"]:
                            score.clear_selection()
                            editor_ctx["selected_element"] = nil
                            if note_hover != nil:
                                let target_part = get_safe_part(score, note_hover["part_idx"])
                                let target_measure = get_safe_measure(target_part, note_hover["measure_idx"])
                                let target_voice = get_safe_voice(target_measure, note_hover["voice_idx"])
                                let target_elem = get_safe_element(target_voice, note_hover["element_idx"])

                                if target_elem != nil:
                                    target_elem.selected = true
                                    editor_ctx["selected_element"] = target_elem
                                    editor_ctx["selected_element_info"] = note_hover

                    # Clef Tool (Click to trigger Clef dialog modal)
                    if editor_ctx["current_tool"] == "clef":
                        if ui_ctx["mouse_clicked"]:
                            editor_ctx["modal_active"] = "clef"
                            editor_ctx["modal_measure_info"] = hovered

                    # Key Signature Tool (Click to trigger Key Signature dialog modal)
                    if editor_ctx["current_tool"] == "key_signature":
                        if ui_ctx["mouse_clicked"]:
                            editor_ctx["modal_active"] = "key_signature"
                            editor_ctx["modal_measure_info"] = hovered

                    # Time Signature Tool (Click to trigger Time Signature dialog modal)
                    if editor_ctx["current_tool"] == "time_signature":
                        if ui_ctx["mouse_clicked"]:
                            editor_ctx["modal_active"] = "time_signature"
                            editor_ctx["modal_measure_info"] = hovered
            else:
                renderer.preview_info = nil

        # Keyboard element deletion
        if editor_ctx["selected_element"] != nil:
            if gpu.key_just_pressed(gpu.KEY_DELETE) or gpu.key_just_pressed(gpu.KEY_BACKSPACE):
                let info = editor_ctx["selected_element_info"]
                if info != nil:
                    let target_part = get_safe_part(score, info["part_idx"])
                    let target_measure = get_safe_measure(target_part, info["measure_idx"])
                    let target_voice = get_safe_voice(target_measure, info["voice_idx"])
                    let target_elem = editor_ctx["selected_element"]

                    if target_voice != nil and target_elem != nil:
                        history.execute(DeleteElementCommand(target_voice, target_elem))
                        editor_ctx["selected_element"] = nil

        # Layout Pass (only if dirty)
        if score.dirty:
            layout_score(score, renderer.base["width"] - 290.0, editor_ctx["view_mode"]) # score width minus sidebar and padding
            score.dirty = false

        
        # Rendering Pass
        renderer.draw_score(frame_info, score, editor_ctx["view_mode"])
        
        # Draw UI on top
        renderer.draw_ui(frame_info["cmd"], ui_ctx)
        
        # Draw SMuFL icons on top of Simple Entry buttons for real Finale feel
        if editor_ctx["current_tool"] == "note_entry":
            let cmd = frame_info["cmd"]
            renderer.add_glyph("noteheadWhole", 35.0, 345.0, [1.0, 1.0, 1.0, 1.0])
            renderer.add_glyph("noteheadHalf", 145.0, 345.0, [1.0, 1.0, 1.0, 1.0])
            renderer.add_glyph("noteheadBlack", 35.0, 385.0, [1.0, 1.0, 1.0, 1.0])
            renderer.add_glyph("noteheadBlack", 145.0, 385.0, [1.0, 1.0, 1.0, 1.0])
            renderer.add_glyph("noteheadBlack", 35.0, 425.0, [1.0, 1.0, 1.0, 1.0])
            renderer.add_glyph("accidentalSharp", 145.0, 425.0, [1.0, 1.0, 1.0, 1.0])
            renderer.add_glyph("accidentalFlat", 35.0, 465.0, [1.0, 1.0, 1.0, 1.0])
            renderer.add_glyph("accidentalNatural", 145.0, 465.0, [1.0, 1.0, 1.0, 1.0])
            renderer.flush_batches(cmd)
        
        renderer.end_frame(frame_info)

main()
