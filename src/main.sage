# -----------------------------------------
# main.sage - SageMusic Main Application
# Orchestrates UI, Renderer, and Interaction
# -----------------------------------------

import gpu
import sys
import graphics.ui as ui
import graphics.renderer as base_renderer

# Local imports
from model.model import create_empty_score, Note, Rest, Measure, Score, Part
from renderer.renderer import MusicRenderer
from layout.layout import layout_score, y_to_pitch, pitch_to_y, get_measure_layout_pos, get_element_width, STAFF_LINE_GAP, STAFF_HEIGHT, STAFF_STEP
from command.command import CommandHistory, AddElementCommand, DeleteElementCommand

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
        ui.ui_begin_frame(ui_ctx)
        
        # Handle hotkeys
        if gpu.key_pressed(gpu.KEY_CTRL):
            if gpu.key_just_pressed(gpu.KEY_Z):
                history.undo()
                clear_selection(score)
                editor_ctx["selected_element"] = nil
            elif gpu.key_just_pressed(gpu.KEY_Y):
                history.redo()
                clear_selection(score)
                editor_ctx["selected_element"] = nil
        elif gpu.key_just_pressed(gpu.KEY_S):
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

        # A. TOP MENU BAR (Finale Style)
        ui.ui_draw_rect(ui_ctx, 0, 0, renderer.base["width"], 40, [0.93, 0.93, 0.93, 1.0])
        ui.ui_draw_rect(ui_ctx, 0, 39, renderer.base["width"], 1, [0.7, 0.7, 0.7, 1.0])
        
        if ui.ui_button(ui_ctx, 10, 5, 55, 30, "File"):
            if editor_ctx["active_menu"] == "file":
                editor_ctx["active_menu"] = nil
            else:
                editor_ctx["active_menu"] = "file"
                
        if ui.ui_button(ui_ctx, 70, 5, 55, 30, "Edit"):
            if editor_ctx["active_menu"] == "edit":
                editor_ctx["active_menu"] = nil
            else:
                editor_ctx["active_menu"] = "edit"

        if ui.ui_button(ui_ctx, 130, 5, 55, 30, "View"):
            if editor_ctx["active_menu"] == "view":
                editor_ctx["active_menu"] = nil
            else:
                editor_ctx["active_menu"] = "view"

        if ui.ui_button(ui_ctx, 190, 5, 80, 30, "Playback"):
            if editor_ctx["active_menu"] == "playback":
                editor_ctx["active_menu"] = nil
            else:
                editor_ctx["active_menu"] = "playback"

        if ui.ui_button(ui_ctx, 275, 5, 55, 30, "Help"):
            if editor_ctx["active_menu"] == "help":
                editor_ctx["active_menu"] = nil
            else:
                editor_ctx["active_menu"] = "help"

        # B. MENU DROPDOWN LISTS
        if editor_ctx["active_menu"] == "file":
            ui.ui_draw_rect(ui_ctx, 10, 40, 150, 70, [0.96, 0.96, 0.96, 1.0])
            if ui.ui_button(ui_ctx, 15, 45, 140, 25, "New Score"):
                # Clear all voices
                let p = 0
                while p < len(score.parts):
                    let m = 0
                    while m < len(score.parts[p].measures):
                        score.parts[p].measures[m].voices[0].elements = []
                        m = m + 1
                    p = p + 1
                editor_ctx["active_menu"] = nil
            if ui.ui_button(ui_ctx, 15, 75, 140, 25, "Exit"):
                should_exit = true
                editor_ctx["active_menu"] = nil
                
        elif editor_ctx["active_menu"] == "edit":
            ui.ui_draw_rect(ui_ctx, 70, 40, 150, 70, [0.96, 0.96, 0.96, 1.0])
            if ui.ui_button(ui_ctx, 75, 45, 140, 25, "Undo"):
                history.undo()
                clear_selection(score)
                editor_ctx["selected_element"] = nil
                editor_ctx["active_menu"] = nil
            if ui.ui_button(ui_ctx, 75, 75, 140, 25, "Redo"):
                history.redo()
                clear_selection(score)
                editor_ctx["selected_element"] = nil
                editor_ctx["active_menu"] = nil
                
        elif editor_ctx["active_menu"] == "view":
            ui.ui_draw_rect(ui_ctx, 130, 40, 150, 70, [0.96, 0.96, 0.96, 1.0])
            let page_lbl = "Page View"
            if editor_ctx["view_mode"] == "page":
                page_lbl = "[Page View]"
            if ui.ui_button(ui_ctx, 135, 45, 140, 25, page_lbl):
                editor_ctx["view_mode"] = "page"
                editor_ctx["active_menu"] = nil
                
            let scroll_lbl = "Scroll View"
            if editor_ctx["view_mode"] == "scroll":
                scroll_lbl = "[Scroll View]"
            if ui.ui_button(ui_ctx, 135, 75, 140, 25, scroll_lbl):
                editor_ctx["view_mode"] = "scroll"
                editor_ctx["active_menu"] = nil
                
        elif editor_ctx["active_menu"] == "playback":
            ui.ui_draw_rect(ui_ctx, 190, 40, 150, 70, [0.96, 0.96, 0.96, 1.0])
            if ui.ui_button(ui_ctx, 195, 45, 140, 25, "Play"):
                print "Playing score..."
                editor_ctx["active_menu"] = nil
            if ui.ui_button(ui_ctx, 195, 75, 140, 25, "Stop"):
                print "Playback stopped."
                editor_ctx["active_menu"] = nil
                
        elif editor_ctx["active_menu"] == "help":
            ui.ui_draw_rect(ui_ctx, 275, 40, 180, 40, [0.96, 0.96, 0.96, 1.0])
            if ui.ui_button(ui_ctx, 280, 45, 170, 30, "About Finale Clone"):
                print "SageMusic - MakeMusic Finale Clone v1.0"
                editor_ctx["active_menu"] = nil

        # C. MAIN SIDEBAR (Tool Grid)
        ui.ui_draw_rect(ui_ctx, 0, 40, 250, renderer.base["height"] - 40, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 20, 60, "Finale Main Palette")
        
        let tool_y = 80
        
        # Grid Row 0
        let sel_btn = "Select"
        if editor_ctx["current_tool"] == "select":
            sel_btn = "[Select]"
        if ui.ui_button(ui_ctx, 20, tool_y, 100, 35, sel_btn):
            editor_ctx["current_tool"] = "select"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        let entry_btn = "Simple"
        if editor_ctx["current_tool"] == "note_entry":
            entry_btn = "[Simple]"
        if ui.ui_button(ui_ctx, 130, tool_y, 100, 35, entry_btn):
            editor_ctx["current_tool"] = "note_entry"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        # Grid Row 1
        let erase_btn = "Eraser"
        if editor_ctx["current_tool"] == "eraser":
            erase_btn = "[Eraser]"
        if ui.ui_button(ui_ctx, 20, tool_y + 45, 100, 35, erase_btn):
            editor_ctx["current_tool"] = "eraser"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        let clef_btn = "Clef Tool"
        if editor_ctx["current_tool"] == "clef":
            clef_btn = "[Clef]"
        if ui.ui_button(ui_ctx, 130, tool_y + 45, 100, 35, clef_btn):
            editor_ctx["current_tool"] = "clef"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        # Grid Row 2
        let key_btn = "Key Sig"
        if editor_ctx["current_tool"] == "key_signature":
            key_btn = "[Key Sig]"
        if ui.ui_button(ui_ctx, 20, tool_y + 90, 100, 35, key_btn):
            editor_ctx["current_tool"] = "key_signature"
            clear_selection(score)
            editor_ctx["selected_element"] = nil
            
        let time_btn = "Time Sig"
        if editor_ctx["current_tool"] == "time_signature":
            time_btn = "[Time Sig]"
        if ui.ui_button(ui_ctx, 130, tool_y + 90, 100, 35, time_btn):
            editor_ctx["current_tool"] = "time_signature"
            clear_selection(score)
            editor_ctx["selected_element"] = nil

        # Grid Row 3 (Playback)
        if ui.ui_button(ui_ctx, 20, tool_y + 135, 100, 35, "Play"):
            print "Playing..."
        if ui.ui_button(ui_ctx, 130, tool_y + 135, 100, 35, "Stop"):
            print "Stopped."

        # Grid Row 4 (Undo/Redo)
        if ui.ui_button(ui_ctx, 20, tool_y + 180, 100, 35, "Undo"):
            history.undo()
            clear_selection(score)
            editor_ctx["selected_element"] = nil
        if ui.ui_button(ui_ctx, 130, tool_y + 180, 100, 35, "Redo"):
            history.redo()
            clear_selection(score)
            editor_ctx["selected_element"] = nil

        # D. SIMPLE ENTRY PALETTE (Visible during note entry)
        if editor_ctx["current_tool"] == "note_entry":
            ui.ui_label(ui_ctx, 20, 310, "Simple Entry Palette")
            let dur_y = 330
            
            # Row 0
            let wh_lbl = "   Whole"
            if editor_ctx["selected_duration"] == 1.0:
                wh_lbl = "   [Whole]"
            if ui.ui_button(ui_ctx, 20, dur_y, 100, 30, wh_lbl):
                editor_ctx["selected_duration"] = 1.0
                
            let hf_lbl = "   Half"
            if editor_ctx["selected_duration"] == 0.5:
                hf_lbl = "   [Half]"
            if ui.ui_button(ui_ctx, 130, dur_y, 100, 30, hf_lbl):
                editor_ctx["selected_duration"] = 0.5
                
            # Row 1
            let qt_lbl = "   Quarter"
            if editor_ctx["selected_duration"] == 0.25:
                qt_lbl = "   [Quart.]"
            if ui.ui_button(ui_ctx, 20, dur_y + 40, 100, 30, qt_lbl):
                editor_ctx["selected_duration"] = 0.25
                
            let ei_lbl = "   Eighth"
            if editor_ctx["selected_duration"] == 0.125:
                ei_lbl = "   [Eighth]"
            if ui.ui_button(ui_ctx, 130, dur_y + 40, 100, 30, ei_lbl):
                editor_ctx["selected_duration"] = 0.125
                
            # Row 2
            let sx_lbl = "   16th"
            if editor_ctx["selected_duration"] == 0.0625:
                sx_lbl = "   [16th]"
            if ui.ui_button(ui_ctx, 20, dur_y + 80, 100, 30, sx_lbl):
                editor_ctx["selected_duration"] = 0.0625
                
            let shp_lbl = "   Sharp"
            if editor_ctx["selected_accidental"] == "sharp":
                shp_lbl = "   [Sharp]"
            if ui.ui_button(ui_ctx, 130, dur_y + 80, 100, 30, shp_lbl):
                if editor_ctx["selected_accidental"] == "sharp":
                    editor_ctx["selected_accidental"] = nil
                else:
                    editor_ctx["selected_accidental"] = "sharp"
                    
            # Row 3
            let flt_lbl = "   Flat"
            if editor_ctx["selected_accidental"] == "flat":
                flt_lbl = "   [Flat]"
            if ui.ui_button(ui_ctx, 20, dur_y + 120, 100, 30, flt_lbl):
                if editor_ctx["selected_accidental"] == "flat":
                    editor_ctx["selected_accidental"] = nil
                else:
                    editor_ctx["selected_accidental"] = "flat"
                    
            let nat_lbl = "   Natural"
            if editor_ctx["selected_accidental"] == "natural":
                nat_lbl = "   [Nat.]"
            if ui.ui_button(ui_ctx, 130, dur_y + 120, 100, 30, nat_lbl):
                if editor_ctx["selected_accidental"] == "natural":
                    editor_ctx["selected_accidental"] = nil
                else:
                    editor_ctx["selected_accidental"] = "natural"

        ui.ui_label(ui_ctx, 20, 520, "Shortcuts:")
        ui.ui_label(ui_ctx, 20, 540, "S: Select Tool")
        ui.ui_label(ui_ctx, 20, 560, "N: Note Entry")
        ui.ui_label(ui_ctx, 20, 580, "E: Eraser Tool")
        ui.ui_label(ui_ctx, 20, 600, "1-5: Select Durations")
        ui.ui_label(ui_ctx, 20, 620, "Del/Bksp: Delete Note")
        ui.ui_label(ui_ctx, 20, 640, "Ctrl+Z/Y: Undo/Redo")

        # E. INTERACTIVE DIALOG MODALS
        if editor_ctx["modal_active"] == "time_signature":
            let m_info = editor_ctx["modal_measure_info"]
            let target_part = get_safe_part(score, m_info["part_idx"])
            let target_measure = get_safe_measure(target_part, m_info["measure_idx"])
            
            if target_measure == nil:
                editor_ctx["modal_active"] = nil
            else:
                ui.ui_draw_rect(ui_ctx, 440, 210, 400, 300, [0.15, 0.15, 0.18, 0.95])
                ui.ui_label(ui_ctx, 460, 230, "Select Time Signature")
                
                if ui.ui_button(ui_ctx, 480, 275, 140, 35, "4/4 Time"):
                    target_measure.set_time_signature(4, 4)
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 630, 275, 140, 35, "3/4 Time"):
                    target_measure.set_time_signature(3, 4)
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 480, 325, 140, 35, "2/4 Time"):
                    target_measure.set_time_signature(2, 4)
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 630, 325, 140, 35, "6/8 Time"):
                    target_measure.set_time_signature(6, 8)
                    editor_ctx["modal_active"] = nil
                    
                if ui.ui_button(ui_ctx, 540, 440, 200, 35, "Cancel"):
                    editor_ctx["modal_active"] = nil
                
        elif editor_ctx["modal_active"] == "key_signature":
            let m_info = editor_ctx["modal_measure_info"]
            let target_part = get_safe_part(score, m_info["part_idx"])
            let target_measure = get_safe_measure(target_part, m_info["measure_idx"])
            
            if target_measure == nil:
                editor_ctx["modal_active"] = nil
            else:
                ui.ui_draw_rect(ui_ctx, 440, 210, 400, 300, [0.15, 0.15, 0.18, 0.95])
                ui.ui_label(ui_ctx, 460, 230, "Select Key Signature")
                
                if ui.ui_button(ui_ctx, 480, 275, 140, 35, "C Major"):
                    target_measure.key_signature = "C Major"
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 630, 275, 140, 35, "G Major (1#)"):
                    target_measure.key_signature = "G Major"
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 480, 325, 140, 35, "F Major (1b)"):
                    target_measure.key_signature = "F Major"
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 630, 325, 140, 35, "D Major (2#)"):
                    target_measure.key_signature = "D Major"
                    editor_ctx["modal_active"] = nil
                    
                if ui.ui_button(ui_ctx, 540, 440, 200, 35, "Cancel"):
                    editor_ctx["modal_active"] = nil
                
        elif editor_ctx["modal_active"] == "clef":
            let m_info = editor_ctx["modal_measure_info"]
            let target_part = get_safe_part(score, m_info["part_idx"])
            let target_measure = get_safe_measure(target_part, m_info["measure_idx"])
            
            if target_measure == nil:
                editor_ctx["modal_active"] = nil
            else:
                ui.ui_draw_rect(ui_ctx, 440, 210, 400, 300, [0.15, 0.15, 0.18, 0.95])
                ui.ui_label(ui_ctx, 460, 230, "Select Staff Clef")
                
                if ui.ui_button(ui_ctx, 480, 275, 140, 35, "Treble Clef"):
                    target_measure.clef = "treble"
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 630, 275, 140, 35, "Bass Clef"):
                    target_measure.clef = "bass"
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 480, 325, 140, 35, "Alto Clef"):
                    target_measure.clef = "alto"
                    editor_ctx["modal_active"] = nil
                if ui.ui_button(ui_ctx, 630, 325, 140, 35, "Tenor Clef"):
                    target_measure.clef = "tenor"
                    editor_ctx["modal_active"] = nil
                    
                if ui.ui_button(ui_ctx, 540, 440, 200, 35, "Cancel"):
                    editor_ctx["modal_active"] = nil

        # UI Pass - End
        ui.ui_end_frame(ui_ctx)
        
        # Interaction Logic
        let mx = ui_ctx["mouse_x"]
        let my = ui_ctx["mouse_y"]
        let mouse_moved = false
        if mx != editor_ctx["last_mouse_x"] or my != editor_ctx["last_mouse_y"]:
            mouse_moved = true
            editor_ctx["last_mouse_x"] = mx
            editor_ctx["last_mouse_y"] = my

        if mouse_moved or ui_ctx["mouse_clicked"] or score.dirty:
            clear_hovered_delete(score)

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
                            clear_selection(score)
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
        renderer.flush_batches(frame_info["cmd"]) # Flush manuscript
        
        # Draw UI on top
        renderer.draw_ui(frame_info["cmd"], ui_ctx)
        renderer.flush_batches(frame_info["cmd"]) # Flush UI
        
        # Draw SMuFL icons on top of Simple Entry buttons for real Finale feel
        if editor_ctx["current_tool"] == "note_entry":
            let cmd = frame_info["cmd"]
            renderer.draw_glyph(cmd, "noteheadWhole", 35.0, 345.0, [1.0, 1.0, 1.0, 1.0])
            renderer.draw_glyph(cmd, "noteheadHalf", 145.0, 345.0, [1.0, 1.0, 1.0, 1.0])
            renderer.draw_glyph(cmd, "noteheadBlack", 35.0, 385.0, [1.0, 1.0, 1.0, 1.0])
            renderer.draw_glyph(cmd, "noteheadBlack", 145.0, 385.0, [1.0, 1.0, 1.0, 1.0])
            renderer.draw_glyph(cmd, "noteheadBlack", 35.0, 425.0, [1.0, 1.0, 1.0, 1.0])
            renderer.draw_glyph(cmd, "accidentalSharp", 145.0, 425.0, [1.0, 1.0, 1.0, 1.0])
            renderer.draw_glyph(cmd, "accidentalFlat", 35.0, 465.0, [1.0, 1.0, 1.0, 1.0])
            renderer.draw_glyph(cmd, "accidentalNatural", 145.0, 465.0, [1.0, 1.0, 1.0, 1.0])
            renderer.flush_batches(cmd)
        
        renderer.end_frame(frame_info)

main()
