# -----------------------------------------
# startup_wizard.sage - SageMusic Startup Wizard
# Finale-style startup wizard for new documents
# -----------------------------------------

import graphics.ui as ui

# Score templates
proc get_templates():
    let templates = []
    
    # Piano Solo
    push(templates, {
        "name": "Piano Solo",
        "icon": "piano",
        "parts": [{"name": "Piano", "staff_count": 2, "clef": "grand"}]
    })
    
    # String Quartet
    push(templates, {
        "name": "String Quartet",
        "icon": "strings",
        "parts": [
            {"name": "Violin I", "staff_count": 1, "clef": "treble"},
            {"name": "Violin II", "staff_count": 1, "clef": "treble"},
            {"name": "Viola", "staff_count": 1, "clef": "alto"},
            {"name": "Cello", "staff_count": 1, "clef": "bass"}
        ]
    })
    
    # Jazz Combo
    push(templates, {
        "name": "Jazz Combo",
        "icon": "jazz",
        "parts": [
            {"name": "Trumpet", "staff_count": 1, "clef": "treble"},
            {"name": "Alto Sax", "staff_count": 1, "clef": "treble"},
            {"name": "Piano", "staff_count": 2, "clef": "grand"},
            {"name": "Bass", "staff_count": 1, "clef": "bass"},
            {"name": "Drums", "staff_count": 1, "clef": "percussion"}
        ]
    })
    
    # Choir SATB
    push(templates, {
        "name": "Choir (SATB)",
        "icon": "choir",
        "parts": [
            {"name": "Soprano", "staff_count": 1, "clef": "treble"},
            {"name": "Alto", "staff_count": 1, "clef": "treble"},
            {"name": "Tenor", "staff_count": 1, "clef": "treble_8vb"},
            {"name": "Bass", "staff_count": 1, "clef": "bass"}
        ]
    })
    
    # Solo Instrument
    push(templates, {
        "name": "Solo Instrument",
        "icon": "solo",
        "parts": [{"name": "Solo", "staff_count": 1, "clef": "treble"}]
    })
    
    # Orchestra
    push(templates, {
        "name": "Small Orchestra",
        "icon": "orchestra",
        "parts": [
            {"name": "Flute", "staff_count": 1, "clef": "treble"},
            {"name": "Oboe", "staff_count": 1, "clef": "treble"},
            {"name": "Clarinet", "staff_count": 1, "clef": "treble"},
            {"name": "Bassoon", "staff_count": 1, "clef": "bass"},
            {"name": "Horn", "staff_count": 1, "clef": "treble"},
            {"name": "Trumpet", "staff_count": 1, "clef": "treble"},
            {"name": "Violin I", "staff_count": 1, "clef": "treble"},
            {"name": "Violin II", "staff_count": 1, "clef": "treble"},
            {"name": "Viola", "staff_count": 1, "clef": "alto"},
            {"name": "Cello", "staff_count": 1, "clef": "bass"}
        ]
    })
    
    # Blank
    push(templates, {
        "name": "Blank Document",
        "icon": "blank",
        "parts": []
    })
    
    return templates

class StartupWizard:
    proc init(self):
        self.active = true
        self.page = 0  # 0=welcome, 1=template, 2=details, 3=settings
        self.templates = get_templates()
        self.selected_template = 0
        
        # Document settings
        self.title = "Untitled"
        self.composer = ""
        self.tempo = 120
        self.time_sig_num = 4
        self.time_sig_den = 4
        self.key_signature = "C Major"
        self.num_measures = 16
        
        # Preferences
        self.auto_save = true
        self.show_tooltips = true
        self.default_instrument = "piano"

    proc draw(self, ui_ctx, renderer):
        if not self.active:
            return false
        
        let width = 600.0
        let height = 500.0
        let x = (renderer.base["width"] - width) / 2.0
        let y = (renderer.base["height"] - height) / 2.0
        
        # Modal background overlay
        renderer.add_rect(0.0, 0.0, renderer.base["width"], renderer.base["height"], [0.0, 0.0, 0.0, 0.5])
        
        # Wizard window
        renderer.add_rect(x, y, width, height, [0.95, 0.95, 0.95, 1.0])
        renderer.add_rect(x, y, width, 60.0, [0.2, 0.3, 0.5, 1.0])  # Header
        
        # Title
        if self.page == 0:
            renderer.add_text("Welcome to SageMusic", x + 20.0, y + 25.0, 24, [1.0, 1.0, 1.0, 1.0])
        elif self.page == 1:
            renderer.add_text("Choose a Template", x + 20.0, y + 25.0, 24, [1.0, 1.0, 1.0, 1.0])
        elif self.page == 2:
            renderer.add_text("Document Details", x + 20.0, y + 25.0, 24, [1.0, 1.0, 1.0, 1.0])
        elif self.page == 3:
            renderer.add_text("Preferences", x + 20.0, y + 25.0, 24, [1.0, 1.0, 1.0, 1.0])
        
        # Page content
        if self.page == 0:
            self.draw_welcome(ui_ctx, renderer, x, y, width, height)
        elif self.page == 1:
            self.draw_templates(ui_ctx, renderer, x, y, width, height)
        elif self.page == 2:
            self.draw_details(ui_ctx, renderer, x, y, width, height)
        elif self.page == 3:
            self.draw_settings(ui_ctx, renderer, x, y, width, height)
        
        # Navigation buttons
        let btn_y = y + height - 50.0
        
        if self.page > 0:
            if self.draw_button(ui_ctx, renderer, "< Back", x + 20.0, btn_y, 100.0, 35.0):
                self.page = self.page - 1
        
        if self.page < 3:
            if self.draw_button(ui_ctx, renderer, "Next >", x + width - 120.0, btn_y, 100.0, 35.0):
                self.page = self.page + 1
        else:
            if self.draw_button(ui_ctx, renderer, "Create", x + width - 120.0, btn_y, 100.0, 35.0):
                self.active = false
                return true  # Signal to create score
        
        if self.draw_button(ui_ctx, renderer, "Cancel", x + 140.0, btn_y, 100.0, 35.0):
            self.active = false
            return false
        
        return nil

    proc draw_welcome(self, ui_ctx, renderer, x, y, width, height):
        let content_y = y + 100.0
        renderer.add_text("Create a new music score", x + 30.0, content_y, 18, [0.2, 0.2, 0.2, 1.0])
        renderer.add_text("This wizard will guide you through:", x + 30.0, content_y + 50.0, 16, [0.3, 0.3, 0.3, 1.0])
        renderer.add_text("• Choosing a template for your score", x + 50.0, content_y + 85.0, 14, [0.4, 0.4, 0.4, 1.0])
        renderer.add_text("• Setting up instruments and parts", x + 50.0, content_y + 110.0, 14, [0.4, 0.4, 0.4, 1.0])
        renderer.add_text("• Configuring time signature and key", x + 50.0, content_y + 135.0, 14, [0.4, 0.4, 0.4, 1.0])
        renderer.add_text("• Customizing your preferences", x + 50.0, content_y + 160.0, 14, [0.4, 0.4, 0.4, 1.0])
        renderer.add_text("Click Next to continue", x + 30.0, content_y + 220.0, 16, [0.2, 0.4, 0.6, 1.0])

    proc draw_templates(self, ui_ctx, renderer, x, y, width, height):
        let content_y = y + 80.0
        let col = 0
        let row = 0
        let idx = 0
        
        while idx < len(self.templates):
            let template = self.templates[idx]
            let btn_x = x + 30.0 + col * 180.0
            let btn_y = content_y + row * 90.0
            
            let color = [0.9, 0.9, 0.9, 1.0]
            if idx == self.selected_template:
                color = [0.6, 0.7, 0.9, 1.0]
            
            renderer.add_rect(btn_x, btn_y, 160.0, 70.0, color)
            renderer.add_text(template["name"], btn_x + 10.0, btn_y + 30.0, 14, [0.1, 0.1, 0.1, 1.0])
            
            let mx = ui_ctx["mouse_x"]
            let my = ui_ctx["mouse_y"]
            if mx >= btn_x and mx <= btn_x + 160.0 and my >= btn_y and my <= btn_y + 70.0:
                if ui_ctx["mouse_clicked"]:
                    self.selected_template = idx
            
            col = col + 1
            if col >= 3:
                col = 0
                row = row + 1
            idx = idx + 1

    proc draw_details(self, ui_ctx, renderer, x, y, width, height):
        let content_y = y + 90.0
        renderer.add_text("Title:", x + 30.0, content_y, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_rect(x + 120.0, content_y - 5.0, 400.0, 25.0, [1.0, 1.0, 1.0, 1.0])
        renderer.add_text(self.title, x + 125.0, content_y, 14, [0.1, 0.1, 0.1, 1.0])
        
        renderer.add_text("Composer:", x + 30.0, content_y + 40.0, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_rect(x + 120.0, content_y + 35.0, 400.0, 25.0, [1.0, 1.0, 1.0, 1.0])
        renderer.add_text(self.composer, x + 125.0, content_y + 40.0, 14, [0.1, 0.1, 0.1, 1.0])
        
        renderer.add_text("Tempo:", x + 30.0, content_y + 80.0, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_text(str(self.tempo) + " BPM", x + 120.0, content_y + 80.0, 14, [0.1, 0.1, 0.1, 1.0])
        
        renderer.add_text("Time Signature:", x + 30.0, content_y + 120.0, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_text(str(self.time_sig_num) + "/" + str(self.time_sig_den), x + 160.0, content_y + 120.0, 14, [0.1, 0.1, 0.1, 1.0])
        
        renderer.add_text("Key Signature:", x + 30.0, content_y + 160.0, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_text(self.key_signature, x + 160.0, content_y + 160.0, 14, [0.1, 0.1, 0.1, 1.0])
        
        renderer.add_text("Measures:", x + 30.0, content_y + 200.0, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_text(str(self.num_measures), x + 120.0, content_y + 200.0, 14, [0.1, 0.1, 0.1, 1.0])

    proc draw_settings(self, ui_ctx, renderer, x, y, width, height):
        let content_y = y + 90.0
        renderer.add_text("Auto-save: " + str(self.auto_save), x + 30.0, content_y, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_text("Show tooltips: " + str(self.show_tooltips), x + 30.0, content_y + 40.0, 14, [0.2, 0.2, 0.2, 1.0])
        renderer.add_text("Default instrument: " + self.default_instrument, x + 30.0, content_y + 80.0, 14, [0.2, 0.2, 0.2, 1.0])
        
        renderer.add_text("Ready to create your score!", x + 30.0, content_y + 150.0, 16, [0.2, 0.4, 0.6, 1.0])

    proc draw_button(self, ui_ctx, renderer, text, x, y, w, h):
        let mx = ui_ctx["mouse_x"]
        let my = ui_ctx["mouse_y"]
        let hover = mx >= x and mx <= x + w and my >= y and my <= y + h
        
        let color = [0.3, 0.4, 0.6, 1.0]
        if hover:
            color = [0.4, 0.5, 0.7, 1.0]
        
        renderer.add_rect(x, y, w, h, color)
        renderer.add_text(text, x + 15.0, y + 12.0, 14, [1.0, 1.0, 1.0, 1.0])
        
        return hover and ui_ctx["mouse_clicked"]

    proc create_score_from_wizard(self):
        let template = self.templates[self.selected_template]
        return {
            "template": template,
            "title": self.title,
            "composer": self.composer,
            "tempo": self.tempo,
            "time_sig": (self.time_sig_num, self.time_sig_den),
            "key_signature": self.key_signature,
            "num_measures": self.num_measures
        }
