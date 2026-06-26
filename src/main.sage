# -----------------------------------------
# main.sage - SageMusic Main Application
# Orchestrates UI, Renderer, and Interaction
# -----------------------------------------

import gpu
import sys
import io
import strings
import graphics.ui as ui
import graphics.renderer as base_renderer

# Local imports
from model.model import create_empty_score, Note, Rest, Measure, Score, Part, Voice, MusicElement
from renderer.renderer import MusicRenderer, mesh_vertex_binding, sprite_vertex_attribs
from layout.layout import layout_score, y_to_pitch, pitch_to_y, get_measure_layout_pos, get_element_width, STAFF_LINE_GAP, STAFF_HEIGHT, STAFF_STEP, calculate_measure_content_width, layout_part
from command.command import CommandHistory, AddElementCommand, DeleteElementCommand
from ui.editor_ui import process_editor_ui
from utils.helpers import get_safe_part, get_safe_measure, get_safe_voice, get_safe_element, find_hovered_measure, find_hovered_note
from audio.engine import AudioEngine


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
    
    # 3. Initialize Data Model with a single empty treble staff
    let score = Score("Untitled Symphony")
    
    let treble_part = Part("Treble Staff")
    
    let i = 0
    while i < 4:
        let m_treble = Measure()
        m_treble.clef = "treble"
        
        # Add default rest for empty measure
        m_treble.get_voice(0).add_element(Rest(1.0))
        
        treble_part.add_measure(m_treble)
        i = i + 1
        
    score.add_part(treble_part)

    # Editor State Context
    let editor_ctx = {}
    
    let audio = AudioEngine()
    audio.start()
    editor_ctx["audio"] = audio
    
    editor_ctx["current_tool"] = "note_entry"
    editor_ctx["selected_duration"] = 0.25
    editor_ctx["selected_accidental"] = nil
    editor_ctx["selected_element"] = nil
    editor_ctx["wiz_ensemble"] = "Create New Ensemble"
    editor_ctx["wiz_style"] = "Engraved Style"
    editor_ctx["wiz_cat"] = "Woodwinds"
    editor_ctx["wiz_inst"] = "Flute"
    editor_ctx["wiz_ts"] = "4/4"
    editor_ctx["wiz_key"] = "C Major"
    editor_ctx["wiz_key_mode"] = "Major"
    editor_ctx["wiz_selected_insts"] = []
    editor_ctx["wiz_sel_added"] = ""
    editor_ctx["selected_element_info"] = nil
    editor_ctx["last_mouse_x"] = 0.0
    editor_ctx["last_mouse_y"] = 0.0
    editor_ctx["view_mode"] = "page"
    editor_ctx["active_menu"] = nil
    editor_ctx["modal_active"] = "startup_wizard_1"
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
            score.rebuild_element_cache() # Rebuild flat element list for fast operations
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
