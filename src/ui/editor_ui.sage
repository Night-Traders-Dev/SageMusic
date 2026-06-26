import gpu
import graphics.ui as ui
from utils.helpers import get_safe_part, get_safe_measure, get_safe_voice, get_safe_element, find_hovered_measure, find_hovered_note
from audio.instrument_map import get_instrument_sfz, pitch_to_midi

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
            editor_ctx["audio"].clear_events()
            
            # Load instruments for each part
            let p_idx = 0
            while p_idx < len(score.parts):
                let part = score.parts[p_idx]
                # Default channel mapping
                let sfz_path = get_instrument_sfz(part.name)
                editor_ctx["audio"].load_instrument(p_idx, sfz_path)
                p_idx = p_idx + 1

            let current_sample_rate = 48000.0
            let tempo_bpm = 120.0
            let samples_per_beat = (60.0 / tempo_bpm) * current_sample_rate
            
            p_idx = 0
            while p_idx < len(score.parts):
                let part = score.parts[p_idx]
                let current_beat = 0.0
                
                let m_idx = 0
                while m_idx < len(part.measures):
                    let measure = part.measures[m_idx]
                    
                    if len(measure.voices) > 0:
                        let voice = measure.voices[0]
                        let e_idx = 0
                        while e_idx < len(voice.elements):
                            let el = voice.elements[e_idx]
                            
                            if el.type == "Note":
                                let delay = int(current_beat * samples_per_beat)
                                let duration_samples = int(el.duration * 4.0 * samples_per_beat) # duration is in whole notes
                                let midi_pitch = pitch_to_midi(el.pitch)
                                
                                editor_ctx["audio"].note_on(delay, p_idx, midi_pitch, el.velocity)
                                editor_ctx["audio"].note_off(delay + duration_samples, p_idx, midi_pitch)
                                
                            current_beat = current_beat + (el.duration * 4.0)
                            e_idx = e_idx + 1
                    
                    m_idx = m_idx + 1
                
                p_idx = p_idx + 1
                
            editor_ctx["audio"].start_playback()
        if ui.ui_button(ui_ctx, 195, 75, 140, 25, "Stop"):
            print "Playback stopped."
            editor_ctx["audio"].stop_playback()
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
        editor_ctx["audio"].load_instrument("Flute", "assets/sfz/test_flute.sfz")
        let pitches = [60, 62, 64, 65, 67, 69, 71, 72]
        let i = 0
        while i < len(pitches):
            let delay = i * 12000
            editor_ctx["audio"].note_on(delay, 0, pitches[i], 100)
            editor_ctx["audio"].note_off(delay + 10000, 0, pitches[i])
            i = i + 1
    if ui.ui_button(ui_ctx, 130, tool_y + 135, 100, 35, "Stop"):
        print "Stop"
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


    if editor_ctx["modal_active"] == "startup_wizard_1":
        ui.ui_draw_rect(ui_ctx, 0, 0, renderer.base["width"], renderer.base["height"], [0.0, 0.0, 0.0, 0.7])
        ui.ui_draw_rect(ui_ctx, 240, 60, 800, 600, [0.18, 0.18, 0.20, 1.0])
        ui.ui_draw_rect(ui_ctx, 240, 60, 800, 40, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 260, 70, "Document Setup Wizard - Select an Ensemble and Document Style")
        
        ui.ui_label(ui_ctx, 260, 110, "Select an Ensemble:")
        ui.ui_draw_rect(ui_ctx, 260, 140, 200, 300, [0.12, 0.12, 0.14, 1.0])
        
        let ensembles = ["Create New Ensemble", "SATB+Piano", "Brass Trio", "Brass Quintet", "Jazz Band", "Concert Band (Full)", "Woodwind Trio"]
        let i = 0
        while i < len(ensembles):
            let y = 145 + i * 25
            let hovered = ui.ui_point_in_rect(ui_ctx, 260, y - 5, 200, 25)
            if hovered and ui_ctx["mouse_clicked"]:
                editor_ctx["wiz_ensemble"] = ensembles[i]
            if editor_ctx["wiz_ensemble"] == ensembles[i]:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 200, 25, [0.35, 0.55, 0.95, 1.0])
            elif hovered:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 200, 25, [0.22, 0.22, 0.26, 1.0])
            ui.ui_label(ui_ctx, 270, y, ensembles[i])
            i = i + 1
        
        ui.ui_label(ui_ctx, 480, 110, "Select a Document Style:")
        ui.ui_draw_rect(ui_ctx, 480, 140, 240, 300, [0.12, 0.12, 0.14, 1.0])
        
        let styles = ["Engraved Style", "Handwritten Style", "> Band", "> Choral", "> General", "> Orchestral"]
        let j = 0
        while j < len(styles):
            let y = 145 + j * 25
            let hovered_s = ui.ui_point_in_rect(ui_ctx, 480, y - 5, 240, 25)
            if hovered_s and ui_ctx["mouse_clicked"]:
                editor_ctx["wiz_style"] = styles[j]
            if editor_ctx["wiz_style"] == styles[j]:
                ui.ui_draw_rect(ui_ctx, 480, y - 5, 240, 25, [0.35, 0.55, 0.95, 1.0])
            elif hovered_s:
                ui.ui_draw_rect(ui_ctx, 480, y - 5, 240, 25, [0.22, 0.22, 0.26, 1.0])
            ui.ui_label(ui_ctx, 490, y, styles[j])
            j = j + 1
        
        ui.ui_label(ui_ctx, 740, 140, "Engraved Style (Maestro Font)")
        ui.ui_label(ui_ctx, 740, 175, "* Finale's all-purpose document")
        ui.ui_label(ui_ctx, 740, 195, "  style")
        ui.ui_label(ui_ctx, 740, 230, "* Title, Subtitle, Composer,")
        ui.ui_label(ui_ctx, 740, 250, "  Arranger, Score/Part, and")
        ui.ui_label(ui_ctx, 740, 270, "  Copyright text inserts")
        
        ui.ui_label(ui_ctx, 260, 480, "Score Page Size:  Letter (8.5 x 11)")
        ui.ui_label(ui_ctx, 260, 520, "Part Page Size:   Letter (8.5 x 11)")
        
        ui.ui_draw_rect(ui_ctx, 240, 580, 800, 1, [0.3, 0.3, 0.35, 1.0])
        
        if ui.ui_button(ui_ctx, 260, 600, 100, 35, "Cancel"):
            editor_ctx["modal_active"] = nil
        ui.ui_button(ui_ctx, 800, 600, 100, 35, "< Back")
        if ui.ui_button(ui_ctx, 920, 600, 100, 35, "Next >"):
            editor_ctx["modal_active"] = "startup_wizard_2"
            let ens = editor_ctx["wiz_ensemble"]
            if ens != "Create New Ensemble":
                editor_ctx["wiz_selected_insts"] = []
                if ens == "SATB+Piano":
                    editor_ctx["wiz_selected_insts"] = ["Soprano", "Alto", "Tenor", "Bass", "Piano"]
                elif ens == "Brass Trio":
                    editor_ctx["wiz_selected_insts"] = ["Trumpet", "Horn", "Trombone"]
                elif ens == "Brass Quintet":
                    editor_ctx["wiz_selected_insts"] = ["Trumpet 1", "Trumpet 2", "Horn", "Trombone", "Tuba"]
                elif ens == "Jazz Band":
                    editor_ctx["wiz_selected_insts"] = ["Alto Sax", "Tenor Sax", "Baritone Sax", "Trumpet", "Trombone", "Piano", "Bass", "Drum Set"]
                elif ens == "Woodwind Trio":
                    editor_ctx["wiz_selected_insts"] = ["Flute", "Oboe", "Clarinet in Bb"]
                elif ens == "Concert Band (Full)":
                    editor_ctx["wiz_selected_insts"] = ["Flute", "Oboe", "Clarinet in Bb", "Bassoon", "Alto Sax", "Tenor Sax", "Trumpet", "Horn", "Trombone", "Tuba", "Percussion"]
            
    elif editor_ctx["modal_active"] == "startup_wizard_2":
        ui.ui_draw_rect(ui_ctx, 0, 0, renderer.base["width"], renderer.base["height"], [0.0, 0.0, 0.0, 0.7])
        ui.ui_draw_rect(ui_ctx, 240, 60, 800, 600, [0.18, 0.18, 0.20, 1.0])
        ui.ui_draw_rect(ui_ctx, 240, 60, 800, 40, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 260, 70, "Document Setup Wizard - Select Instrument(s)")
        
        ui.ui_label(ui_ctx, 260, 120, "Select From:")
        ui.ui_button(ui_ctx, 380, 115, 150, 30, "All Instruments")
        
        ui.ui_draw_rect(ui_ctx, 260, 160, 180, 380, [0.12, 0.12, 0.14, 1.0])
        let cats = ["Blank Staff", "Keyboards", "Voices", "Woodwinds", "Brass", "Strings", "Plucked Strings", "Pitched Percussion"]
        let k = 0
        while k < len(cats):
            let y = 165 + k * 30
            let hov_c = ui.ui_point_in_rect(ui_ctx, 260, y - 5, 180, 30)
            if hov_c and ui_ctx["mouse_clicked"]:
                editor_ctx["wiz_cat"] = cats[k]
            if editor_ctx["wiz_cat"] == cats[k]:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 180, 30, [0.35, 0.55, 0.95, 1.0])
            elif hov_c:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 180, 30, [0.22, 0.22, 0.26, 1.0])
            ui.ui_label(ui_ctx, 270, y, cats[k])
            k = k + 1
            
        ui.ui_draw_rect(ui_ctx, 460, 160, 200, 380, [0.12, 0.12, 0.14, 1.0])
        let insts = []
        if editor_ctx["wiz_cat"] == "Blank Staff": insts = ["Blank Staff", "Treble Staff", "Bass Staff"]
        elif editor_ctx["wiz_cat"] == "Keyboards": insts = ["Piano", "Harpsichord", "Organ", "Celesta"]
        elif editor_ctx["wiz_cat"] == "Voices": insts = ["Soprano", "Alto", "Tenor", "Bass", "Voice", "Choir"]
        elif editor_ctx["wiz_cat"] == "Woodwinds": insts = ["Flute", "Piccolo", "Oboe", "English Horn", "Clarinet in Bb", "Bass Clarinet", "Bassoon", "Alto Sax", "Tenor Sax", "Baritone Sax"]
        elif editor_ctx["wiz_cat"] == "Brass": insts = ["Trumpet", "Horn", "Trombone", "Bass Trombone", "Euphonium", "Tuba"]
        elif editor_ctx["wiz_cat"] == "Strings": insts = ["Violin", "Viola", "Cello", "Contrabass"]
        elif editor_ctx["wiz_cat"] == "Plucked Strings": insts = ["Guitar", "Bass Guitar", "Harp"]
        elif editor_ctx["wiz_cat"] == "Pitched Percussion": insts = ["Timpani", "Glockenspiel", "Xylophone", "Marimba", "Vibraphone"]
        else: insts = ["Blank Staff"]
        
        let m = 0
        while m < len(insts):
            let y = 165 + m * 30
            let hov_i = ui.ui_point_in_rect(ui_ctx, 460, y - 5, 200, 30)
            if hov_i and ui_ctx["mouse_clicked"]:
                editor_ctx["wiz_inst"] = insts[m]
            if editor_ctx["wiz_inst"] == insts[m]:
                ui.ui_draw_rect(ui_ctx, 460, y - 5, 200, 30, [0.35, 0.55, 0.95, 1.0])
            elif hov_i:
                ui.ui_draw_rect(ui_ctx, 460, y - 5, 200, 30, [0.22, 0.22, 0.26, 1.0])
            ui.ui_label(ui_ctx, 470, y, insts[m])
            m = m + 1
            
        if ui.ui_button(ui_ctx, 680, 260, 100, 35, "Add >"):
            if editor_ctx["wiz_inst"] != "":
                push(editor_ctx["wiz_selected_insts"], editor_ctx["wiz_inst"])
                editor_ctx["wiz_sel_added"] = editor_ctx["wiz_inst"]
                
        if ui.ui_button(ui_ctx, 680, 310, 100, 35, "< Remove"):
            if editor_ctx["wiz_sel_added"] != "":
                let new_list = []
                let removed = false
                let r = 0
                while r < len(editor_ctx["wiz_selected_insts"]):
                    if editor_ctx["wiz_selected_insts"][r] == editor_ctx["wiz_sel_added"] and not removed:
                        removed = true
                    else:
                        push(new_list, editor_ctx["wiz_selected_insts"][r])
                    r = r + 1
                editor_ctx["wiz_selected_insts"] = new_list
                editor_ctx["wiz_sel_added"] = ""
        
        ui.ui_draw_rect(ui_ctx, 800, 160, 220, 380, [0.12, 0.12, 0.14, 1.0])
        let q = 0
        while q < len(editor_ctx["wiz_selected_insts"]):
            let y = 165 + q * 30
            let hov_a = ui.ui_point_in_rect(ui_ctx, 800, y - 5, 220, 30)
            if hov_a and ui_ctx["mouse_clicked"]:
                editor_ctx["wiz_sel_added"] = editor_ctx["wiz_selected_insts"][q]
            if editor_ctx["wiz_sel_added"] == editor_ctx["wiz_selected_insts"][q]:
                ui.ui_draw_rect(ui_ctx, 800, y - 5, 220, 30, [0.35, 0.55, 0.95, 1.0])
            elif hov_a:
                ui.ui_draw_rect(ui_ctx, 800, y - 5, 220, 30, [0.22, 0.22, 0.26, 1.0])
            ui.ui_label(ui_ctx, 810, y, editor_ctx["wiz_selected_insts"][q])
            q = q + 1
        
        ui.ui_draw_rect(ui_ctx, 240, 580, 800, 1, [0.3, 0.3, 0.35, 1.0])
        
        if ui.ui_button(ui_ctx, 260, 600, 100, 35, "Cancel"):
            editor_ctx["modal_active"] = nil
        if ui.ui_button(ui_ctx, 800, 600, 100, 35, "< Back"):
            editor_ctx["modal_active"] = "startup_wizard_1"
        if ui.ui_button(ui_ctx, 920, 600, 100, 35, "Next >"):
            editor_ctx["modal_active"] = "startup_wizard_3"
            
    elif editor_ctx["modal_active"] == "startup_wizard_3":
        ui.ui_draw_rect(ui_ctx, 0, 0, renderer.base["width"], renderer.base["height"], [0.0, 0.0, 0.0, 0.7])
        ui.ui_draw_rect(ui_ctx, 240, 60, 800, 600, [0.18, 0.18, 0.20, 1.0])
        ui.ui_draw_rect(ui_ctx, 240, 60, 800, 40, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 260, 70, "Document Setup Wizard - Score Settings")
        
        ui.ui_label(ui_ctx, 260, 120, "Select a Time Signature:")
        let ts_list = ["2/2", "C|", "2/4", "3/4", "4/4", "C", "3/8", "6/8", "9/8", "12/8"]
        let n = 0
        while n < len(ts_list):
            let x = 260 + n * 50
            if editor_ctx["wiz_ts"] == ts_list[n]:
                ui.ui_draw_rect(ui_ctx, x - 2, 148, 49, 49, [0.35, 0.55, 0.95, 1.0])
            if ui.ui_button(ui_ctx, x, 150, 45, 45, ts_list[n]):
                editor_ctx["wiz_ts"] = ts_list[n]
            n = n + 1
            
        ui.ui_draw_rect(ui_ctx, 260, 220, 760, 1, [0.3, 0.3, 0.35, 1.0])
        
        ui.ui_label(ui_ctx, 260, 240, "Select a Concert Key Signature:")
        ui.ui_draw_rect(ui_ctx, 260, 280, 250, 150, [0.12, 0.12, 0.14, 1.0])
        let keys = []
        if editor_ctx["wiz_key_mode"] == "Major":
            keys = ["C Major", "G Major", "D Major", "F Major", "Bb Major"]
        else:
            keys = ["A minor", "E minor", "B minor", "D minor", "G minor"]
            
        let p = 0
        while p < len(keys):
            let y = 285 + p * 25
            let hov_k = ui.ui_point_in_rect(ui_ctx, 260, y - 5, 250, 25)
            if hov_k and ui_ctx["mouse_clicked"]:
                editor_ctx["wiz_key"] = keys[p]
            if editor_ctx["wiz_key"] == keys[p]:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 250, 25, [0.35, 0.55, 0.95, 1.0])
            elif hov_k:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 250, 25, [0.22, 0.22, 0.26, 1.0])
            ui.ui_label(ui_ctx, 270, y, keys[p])
            p = p + 1
            
        if ui.ui_button(ui_ctx, 530, 330, 100, 35, editor_ctx["wiz_key_mode"]):
            if editor_ctx["wiz_key_mode"] == "Major":
                editor_ctx["wiz_key_mode"] = "minor"
                editor_ctx["wiz_key"] = "A minor"
            else:
                editor_ctx["wiz_key_mode"] = "Major"
                editor_ctx["wiz_key"] = "C Major"

        
        ui.ui_draw_rect(ui_ctx, 260, 460, 760, 1, [0.3, 0.3, 0.35, 1.0])
        
        ui.ui_label(ui_ctx, 260, 480, "Specify Initial Tempo Marking")
        ui.ui_label(ui_ctx, 350, 520, "Text: ")
        ui.ui_button(ui_ctx, 400, 510, 250, 35, "Allegro")
        
        ui.ui_draw_rect(ui_ctx, 240, 580, 800, 1, [0.3, 0.3, 0.35, 1.0])
        
        if ui.ui_button(ui_ctx, 260, 600, 100, 35, "Cancel"):
            editor_ctx["modal_active"] = nil
        if ui.ui_button(ui_ctx, 800, 600, 100, 35, "< Back"):
            editor_ctx["modal_active"] = "startup_wizard_2"
        if ui.ui_button(ui_ctx, 920, 600, 100, 35, "Finish"):
            editor_ctx["modal_active"] = nil
            score.parts = []
            
            if len(editor_ctx["wiz_selected_insts"]) == 0:
                push(editor_ctx["wiz_selected_insts"], "Treble Staff")
                
            let inst_idx = 0
            while inst_idx < len(editor_ctx["wiz_selected_insts"]):
                let inst_name = editor_ctx["wiz_selected_insts"][inst_idx]
                let new_part = Part(inst_name)
                
                let m_idx = 0
                while m_idx < 4:
                    let m = Measure()
                    if inst_name == "Bassoon" or inst_name == "Cello" or inst_name == "Trombone" or inst_name == "Tuba":
                        m.clef = "bass"
                    else:
                        m.clef = "treble"
                        
                    if editor_ctx["wiz_ts"] == "4/4" or editor_ctx["wiz_ts"] == "C":
                        m.set_time_signature(4, 4)
                    elif editor_ctx["wiz_ts"] == "3/4":
                        m.set_time_signature(3, 4)
                    elif editor_ctx["wiz_ts"] == "2/4":
                        m.set_time_signature(2, 4)
                    elif editor_ctx["wiz_ts"] == "6/8":
                        m.set_time_signature(6, 8)
                    elif editor_ctx["wiz_ts"] == "9/8":
                        m.set_time_signature(9, 8)
                    elif editor_ctx["wiz_ts"] == "12/8":
                        m.set_time_signature(12, 8)
                    elif editor_ctx["wiz_ts"] == "2/2" or editor_ctx["wiz_ts"] == "C|":
                        m.set_time_signature(2, 2)
                        
                    m.key_signature = editor_ctx["wiz_key"]
                        
                    m.get_voice(0).add_element(Rest(1.0))
                    new_part.add_measure(m)
                    m_idx = m_idx + 1
                    
                score.add_part(new_part)
                inst_idx = inst_idx + 1
            score.mark_dirty()
    elif editor_ctx["modal_active"] == "time_signature":
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