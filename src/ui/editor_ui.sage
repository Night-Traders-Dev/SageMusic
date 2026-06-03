import gpu
import graphics.ui as ui
from model.model import get_safe_part, get_safe_measure

proc process_editor_ui(ui_ctx, editor_ctx, score, history, renderer):
    let should_exit = false
    ui.ui_begin_frame(ui_ctx)
    
    # Handle hotkeys
    if gpu.key_pressed(gpu.KEY_CTRL):
        if gpu.key_just_pressed(gpu.KEY_Z):
            history.undo()
            score.clear_selection()
            editor_ctx["selected_element"] = nil
        elif gpu.key_just_pressed(gpu.KEY_Y):
            history.redo()
            score.clear_selection()
            editor_ctx["selected_element"] = nil
    elif gpu.key_just_pressed(gpu.KEY_S):
        editor_ctx["current_tool"] = "select"
        score.clear_selection()
        editor_ctx["selected_element"] = nil
    elif gpu.key_just_pressed(gpu.KEY_N):
        editor_ctx["current_tool"] = "note_entry"
        score.clear_selection()
        editor_ctx["selected_element"] = nil
    elif gpu.key_just_pressed(gpu.KEY_E):
        editor_ctx["current_tool"] = "eraser"
        score.clear_selection()
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
            score.clear_selection()
            editor_ctx["selected_element"] = nil
            editor_ctx["active_menu"] = nil
        if ui.ui_button(ui_ctx, 75, 75, 140, 25, "Redo"):
            history.redo()
            score.clear_selection()
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
        score.clear_selection()
        editor_ctx["selected_element"] = nil
        
    let entry_btn = "Simple"
    if editor_ctx["current_tool"] == "note_entry":
        entry_btn = "[Simple]"
    if ui.ui_button(ui_ctx, 130, tool_y, 100, 35, entry_btn):
        editor_ctx["current_tool"] = "note_entry"
        score.clear_selection()
        editor_ctx["selected_element"] = nil
        
    # Grid Row 1
    let erase_btn = "Eraser"
    if editor_ctx["current_tool"] == "eraser":
        erase_btn = "[Eraser]"
    if ui.ui_button(ui_ctx, 20, tool_y + 45, 100, 35, erase_btn):
        editor_ctx["current_tool"] = "eraser"
        score.clear_selection()
        editor_ctx["selected_element"] = nil
        
    let clef_btn = "Clef Tool"
    if editor_ctx["current_tool"] == "clef":
        clef_btn = "[Clef]"
    if ui.ui_button(ui_ctx, 130, tool_y + 45, 100, 35, clef_btn):
        editor_ctx["current_tool"] = "clef"
        score.clear_selection()
        editor_ctx["selected_element"] = nil
        
    # Grid Row 2
    let key_btn = "Key Sig"
    if editor_ctx["current_tool"] == "key_signature":
        key_btn = "[Key Sig]"
    if ui.ui_button(ui_ctx, 20, tool_y + 90, 100, 35, key_btn):
        editor_ctx["current_tool"] = "key_signature"
        score.clear_selection()
        editor_ctx["selected_element"] = nil
        
    let time_btn = "Time Sig"
    if editor_ctx["current_tool"] == "time_signature":
        time_btn = "[Time Sig]"
    if ui.ui_button(ui_ctx, 130, tool_y + 90, 100, 35, time_btn):
        editor_ctx["current_tool"] = "time_signature"
        score.clear_selection()
        editor_ctx["selected_element"] = nil

    # Grid Row 3 (Playback)
    if ui.ui_button(ui_ctx, 20, tool_y + 135, 100, 35, "Play"):
        print "Playing..."
    if ui.ui_button(ui_ctx, 130, tool_y + 135, 100, 35, "Stop"):
        print "Stopped."

    # Grid Row 4 (Undo/Redo)
    if ui.ui_button(ui_ctx, 20, tool_y + 180, 100, 35, "Undo"):
        history.undo()
        score.clear_selection()
        editor_ctx["selected_element"] = nil
    if ui.ui_button(ui_ctx, 130, tool_y + 180, 100, 35, "Redo"):
        history.redo()
        score.clear_selection()
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

    ui.ui_end_frame(ui_ctx)
    return should_exit