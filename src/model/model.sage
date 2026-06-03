# -----------------------------------------
# model.sage - SageMusic Data Model
# SMuFL-inspired Object-Oriented Hierarchy
# -----------------------------------------

class MusicElement:
    proc init(self):
        self.id = "" # Unique identifier
        self.parent = nil
        self.selected = false
        self.hovered_delete = false

    proc mark_dirty(self):
        if self.parent != nil:
            self.parent.mark_dirty()

class Note(MusicElement):
    proc init(self, pitch, duration):
        super.init()
        self.type = "Note"
        self.pitch = pitch       # e.g., "C4", "G#3"
        
        # SEC-IV-3: Duration validation
        if duration <= 0.0:
            self.duration = 0.25 # Default to quarter if invalid
        else:
            self.duration = duration

        self.accidental = nil    # "sharp", "flat", "natural"
        self.stem_direction = "auto"
        self.dots = 0
        self.tie_to = nil
        self.articulations = []

    # SEC-IV-5: Accidental validation
    proc set_accidental(self, acc):
        if acc == "sharp" or acc == "flat" or acc == "natural":
            self.accidental = acc
        else:
            self.accidental = nil

    proc __str__(self):
        return "Note(" + self.pitch + ", " + str(self.duration) + ")"

class Rest(MusicElement):
    proc init(self, duration):
        super.init()
        self.type = "Rest"
        
        # SEC-IV-3: Duration validation
        if duration <= 0.0:
            self.duration = 0.25
        else:
            self.duration = duration

    proc __str__(self):
        return "Rest(" + str(self.duration) + ")"

class Voice(MusicElement):
    proc init(self):
        super.init()
        self.elements = [] # List of Note/Rest elements

    proc add_element(self, element):
        element.parent = self
        push(self.elements, element)
        self.mark_dirty()

class Measure(MusicElement):
    proc init(self):
        super.init()
        self.voices = [Voice()]
        self.time_signature = (4, 4)
        self.ts_top_str = "4" # SEC-MA-17: Cached string
        self.ts_bot_str = "4" # SEC-MA-17: Cached string
        self.key_signature = "C Major"
        self.clef = "treble"
        self.width = 300.0 # Layout width in units
        self.padding = 10.0
        self.layout_x = 0.0 # Cached layout position
        self.layout_y = 0.0 # Cached layout position

    # SEC-IV-4: Time signature validation
    proc set_time_signature(self, num, den):
        if num > 0 and num <= 32 and (den == 1 or den == 2 or den == 4 or den == 8 or den == 16 or den == 32):
            self.time_signature = (num, den)
            self.ts_top_str = str(num)
            self.ts_bot_str = str(den)
            self.mark_dirty()

    proc get_voice(self, index):
        return self.voices[index]

class Part(MusicElement):
    proc init(self, name):
        super.init()
        self.name = name
        self.measures = []
        self.staff_count = 1 # 1 for single staff, 2 for grand staff

    proc add_measure(self, measure):
        measure.parent = self
        push(self.measures, measure)
        self.mark_dirty()

class Score(MusicElement):
    proc init(self, title):
        super.init()
        self.title = title
        self.parts = []
        self.composer = "Unknown"
        self.tempo = 120
        self.dirty = true # Mark as dirty initially

    proc mark_dirty(self):
        self.dirty = true

    proc add_part(self, part):
        part.parent = self
        push(self.parts, part)
        self.mark_dirty()

# Helper to create a basic score
proc create_empty_score(title):
    let score = Score(title)
    let piano = Part("Piano")
    piano.staff_count = 2
    
    # Add some empty measures
    let i = 0
    while i < 4:
        piano.add_measure(Measure())
        i = i + 1
        
    score.add_part(piano)
    return score
