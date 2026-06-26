import re

with open("src/ui/editor_ui.sage", "r") as f:
    content = f.read()

# We need to replace the entire wizard logic from line 286 to 429.
# Let's write the new wizard logic.
new_wizard = """
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
            if editor_ctx["wiz_ensemble"] == ensembles[i]:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 200, 25, [0.35, 0.55, 0.95, 1.0])
            if ui.ui_button(ui_ctx, 260, y - 5, 200, 25, ensembles[i]):
                editor_ctx["wiz_ensemble"] = ensembles[i]
            i = i + 1
        
        ui.ui_label(ui_ctx, 480, 110, "Select a Document Style:")
        ui.ui_draw_rect(ui_ctx, 480, 140, 240, 300, [0.12, 0.12, 0.14, 1.0])
        
        let styles = ["Engraved Style", "Handwritten Style", "> Band", "> Choral", "> General", "> Orchestral"]
        let j = 0
        while j < len(styles):
            let y = 145 + j * 25
            if editor_ctx["wiz_style"] == styles[j]:
                ui.ui_draw_rect(ui_ctx, 480, y - 5, 240, 25, [0.35, 0.55, 0.95, 1.0])
            if ui.ui_button(ui_ctx, 480, y - 5, 240, 25, styles[j]):
                editor_ctx["wiz_style"] = styles[j]
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
            if ui.ui_button(ui_ctx, 260, y - 5, 180, 30, cats[k]):
                pass
            k = k + 1
            
        ui.ui_draw_rect(ui_ctx, 460, 160, 200, 380, [0.12, 0.12, 0.14, 1.0])
        let insts = ["Flute", "Oboe", "English Horn", "Clarinet in Bb", "Bassoon", "Saxophone"]
        let m = 0
        while m < len(insts):
            let y = 165 + m * 30
            if editor_ctx["wiz_inst"] == insts[m]:
                ui.ui_draw_rect(ui_ctx, 460, y - 5, 200, 30, [0.35, 0.55, 0.95, 1.0])
            if ui.ui_button(ui_ctx, 460, y - 5, 200, 30, insts[m]):
                editor_ctx["wiz_inst"] = insts[m]
            m = m + 1
            
        ui.ui_button(ui_ctx, 680, 260, 100, 35, "Add >")
        ui.ui_button(ui_ctx, 680, 310, 100, 35, "< Remove")
        
        ui.ui_draw_rect(ui_ctx, 800, 160, 220, 380, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 810, 170, editor_ctx["wiz_inst"])
        
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
                ui.ui_draw_rect(ui_ctx, x, 150, 45, 45, [0.35, 0.55, 0.95, 1.0])
            if ui.ui_button(ui_ctx, x, 150, 45, 45, ts_list[n]):
                editor_ctx["wiz_ts"] = ts_list[n]
            n = n + 1
            
        ui.ui_draw_rect(ui_ctx, 260, 220, 760, 1, [0.3, 0.3, 0.35, 1.0])
        
        ui.ui_label(ui_ctx, 260, 240, "Select a Concert Key Signature:")
        ui.ui_draw_rect(ui_ctx, 260, 280, 250, 150, [0.12, 0.12, 0.14, 1.0])
        let keys = ["C Major", "G Major", "D Major", "F Major", "Bb Major"]
        let p = 0
        while p < len(keys):
            let y = 285 + p * 25
            if editor_ctx["wiz_key"] == keys[p]:
                ui.ui_draw_rect(ui_ctx, 260, y - 5, 250, 25, [0.35, 0.55, 0.95, 1.0])
            if ui.ui_button(ui_ctx, 260, y - 5, 250, 25, keys[p]):
                editor_ctx["wiz_key"] = keys[p]
            p = p + 1
            
        ui.ui_button(ui_ctx, 530, 330, 100, 35, "Major")
        
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
"""

start_idx = content.find('    if editor_ctx["modal_active"] == "startup_wizard_1":')
end_idx = content.find('    elif editor_ctx["modal_active"] == "time_signature":')

if start_idx != -1 and end_idx != -1:
    new_content = content[:start_idx] + new_wizard + content[end_idx:]
    with open("src/ui/editor_ui.sage", "w") as f:
        f.write(new_content)
    print("Wizard updated successfully.")
else:
    print("Could not find start or end index.")
