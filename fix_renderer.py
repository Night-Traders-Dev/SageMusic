import re

with open("src/renderer/renderer.sage", "r") as f:
    content = f.read()

# Fix part name rendering in draw_score:
target_draw_score = """            let part = score.parts[part_idx]
            let m_idx = 0
            while m_idx < len(part.measures):"""

replacement_draw_score = """            let part = score.parts[part_idx]
            if len(part.measures) > 0:
                let first_m = part.measures[0]
                self.add_text(part.name, first_m.layout_x - 120.0, first_m.layout_y + 20.0, [0.0, 0.0, 0.0, 1.0])
            let m_idx = 0
            while m_idx < len(part.measures):"""

content = content.replace(target_draw_score, replacement_draw_score)

# Fix draw_measure to handle clefs, keys, and time sig placement:
target_draw_measure = """        if draw_clef:
            self.add_glyph(measure.clef + "Clef", x + 15.0, y + 24.0, [0.0, 0.0, 0.0, 1.0])
            self.add_text(measure.ts_top_str, x + 42.0, y + 22.0, [0.0, 0.0, 0.0, 1.0])
            self.add_text(measure.ts_bot_str, x + 42.0, y + 10.0, [0.0, 0.0, 0.0, 1.0])"""

replacement_draw_measure = """        if draw_clef:
            let clef_glyph = ""
            if measure.clef == "treble": clef_glyph = "gClef"
            elif measure.clef == "bass": clef_glyph = "fClef"
            elif measure.clef == "alto" or measure.clef == "tenor": clef_glyph = "cClef"
            
            if clef_glyph != "":
                self.add_glyph(clef_glyph, x + 15.0, y + 24.0, [0.0, 0.0, 0.0, 1.0])
                
            let key_x = x + 42.0
            
            # 1 sharp
            if measure.key_signature == "G Major" or measure.key_signature == "E minor":
                self.add_glyph("accidentalSharp", key_x, y + 4.0, [0.0, 0.0, 0.0, 1.0])
                key_x = key_x + 12.0
            # 2 sharps
            elif measure.key_signature == "D Major" or measure.key_signature == "B minor":
                self.add_glyph("accidentalSharp", key_x, y + 4.0, [0.0, 0.0, 0.0, 1.0])
                self.add_glyph("accidentalSharp", key_x + 10.0, y + 16.0, [0.0, 0.0, 0.0, 1.0])
                key_x = key_x + 22.0
            # 1 flat
            elif measure.key_signature == "F Major" or measure.key_signature == "D minor":
                self.add_glyph("accidentalFlat", key_x, y + 16.0, [0.0, 0.0, 0.0, 1.0])
                key_x = key_x + 12.0
            # 2 flats
            elif measure.key_signature == "Bb Major" or measure.key_signature == "G minor":
                self.add_glyph("accidentalFlat", key_x, y + 16.0, [0.0, 0.0, 0.0, 1.0])
                self.add_glyph("accidentalFlat", key_x + 10.0, y + 4.0, [0.0, 0.0, 0.0, 1.0])
                key_x = key_x + 22.0
                
            self.add_text(measure.ts_top_str, key_x, y + 10.0, [0.0, 0.0, 0.0, 1.0])
            self.add_text(measure.ts_bot_str, key_x, y + 24.0, [0.0, 0.0, 0.0, 1.0])"""

content = content.replace(target_draw_measure, replacement_draw_measure)

with open("src/renderer/renderer.sage", "w") as f:
    f.write(content)
print("Updated renderer.sage")
