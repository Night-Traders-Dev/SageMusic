import re

with open("src/ui/editor_ui.sage", "r") as f:
    content = f.read()

target = """        ui.ui_draw_rect(ui_ctx, 260, 280, 250, 150, [0.12, 0.12, 0.14, 1.0])
        let keys = ["C Major", "G Major", "D Major", "F Major", "Bb Major"]
        let p = 0"""

replacement = """        ui.ui_draw_rect(ui_ctx, 260, 280, 250, 150, [0.12, 0.12, 0.14, 1.0])
        let keys = []
        if editor_ctx["wiz_key_mode"] == "Major":
            keys = ["C Major", "G Major", "D Major", "F Major", "Bb Major"]
        else:
            keys = ["A minor", "E minor", "B minor", "D minor", "G minor"]
            
        let p = 0"""

content = content.replace(target, replacement)

target_button = """        ui.ui_button(ui_ctx, 530, 330, 100, 35, "Major")"""

replacement_button = """        if ui.ui_button(ui_ctx, 530, 330, 100, 35, editor_ctx["wiz_key_mode"]):
            if editor_ctx["wiz_key_mode"] == "Major":
                editor_ctx["wiz_key_mode"] = "minor"
                editor_ctx["wiz_key"] = "A minor"
            else:
                editor_ctx["wiz_key_mode"] = "Major"
                editor_ctx["wiz_key"] = "C Major"
"""

content = content.replace(target_button, replacement_button)

with open("src/ui/editor_ui.sage", "w") as f:
    f.write(content)
print("Updated key toggler")
