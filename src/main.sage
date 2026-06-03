# -----------------------------------------
# main.sage - SageMusic Main Application
# Orchestrates UI, Renderer, and Interaction
# -----------------------------------------

import graphics.ui as ui
import graphics.renderer as base_renderer

# Local imports
from model import create_empty_score, Note, Rest, Measure
from renderer import MusicRenderer
from layout import layout_score

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

    # 4. Main Loop
    while true:
        let frame_info = renderer.begin_frame()
        if frame_info == nil:
            break
            
        # UI Pass - Start
        ui.ui_begin_frame(ui_ctx)
        
        # Draw Main Sidebar
        ui.ui_draw_rect(ui_ctx, 0, 0, 250, 720, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 20, 20, "SageMusic v1.0")
        
        if ui.ui_button(ui_ctx, 20, 60, 210, 30, "Add Measure"):
            score.parts[0].add_measure(Measure())
            print "Added measure"
            
        if ui.ui_button(ui_ctx, 20, 100, 210, 30, "Reset Score"):
            # logic to reset
            nil
            
        # Draw Entry Palette
        ui.ui_label(ui_ctx, 20, 160, "Duration Palette")
        ui.ui_draw_rect(ui_ctx, 20, 180, 210, 100, [0.18, 0.18, 0.22, 1.0])
        
        # UI Pass - End
        ui.ui_end_frame(ui_ctx)
        
        # Layout Pass (only if dirty, but every frame for now)
        layout_score(score, 1280.0 - 250.0) # score width minus sidebar
        
        # Rendering Pass
        renderer.draw_score(frame_info, score)
        
        # Draw UI on top
        # (In a real implementation, we'd have a UI pipeline)
        # For now, UI elements are accumulated in ui_ctx["draw_list"]
        
        renderer.end_frame(frame_info)

main()
