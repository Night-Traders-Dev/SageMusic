import re

with open("src/ui/editor_ui.sage", "r") as f:
    content = f.read()

# Replace the Add/Remove and list rendering on page 2:
target_page2 = """        ui.ui_button(ui_ctx, 680, 260, 100, 35, "Add >")
        ui.ui_button(ui_ctx, 680, 310, 100, 35, "< Remove")
        
        ui.ui_draw_rect(ui_ctx, 800, 160, 220, 380, [0.12, 0.12, 0.14, 1.0])
        ui.ui_label(ui_ctx, 810, 170, editor_ctx["wiz_inst"])"""

replacement_page2 = """        if ui.ui_button(ui_ctx, 680, 260, 100, 35, "Add >"):
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
            q = q + 1"""

content = content.replace(target_page2, replacement_page2)

# Replace Finish button logic on page 3
target_finish = """        if ui.ui_button(ui_ctx, 920, 600, 100, 35, "Finish"):
            editor_ctx["modal_active"] = nil"""

from textwrap import dedent
replacement_finish = """        if ui.ui_button(ui_ctx, 920, 600, 100, 35, "Finish"):
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
                        
                    m.get_voice(0).add_element(Rest(1.0))
                    new_part.add_measure(m)
                    m_idx = m_idx + 1
                    
                score.add_part(new_part)
                inst_idx = inst_idx + 1
            score.mark_dirty()"""

content = content.replace(target_finish, replacement_finish)

with open("src/ui/editor_ui.sage", "w") as f:
    f.write(content)
print("Updated wizard logic.")
