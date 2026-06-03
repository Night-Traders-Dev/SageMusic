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

class Note(MusicElement):
    proc init(self, pitch, duration):
        super.init()
        self.type = "Note"
        self.pitch = pitch       # e.g., "C4", "G#3"
        self.duration = duration # e.g., 0.25 (quarter), 0.5 (half)
        self.accidental = nil    # "sharp", "flat", "natural"
        self.stem_direction = "auto"
        self.dots = 0
        self.tie_to = nil
        self.articulations = []

    proc __str__(self):
        return "Note(" + self.pitch + ", " + str(self.duration) + ")"

class Rest(MusicElement):
    proc init(self, duration):
        super.init()
        self.type = "Rest"
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

class Measure(MusicElement):
    proc init(self):
        super.init()
        self.voices = [Voice()]
        self.time_signature = (4, 4)
        self.key_signature = "C Major"
        self.clef = "treble"
        self.width = 300.0 # Layout width in units
        self.padding = 10.0

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

class Score(MusicElement):
    proc init(self, title):
        super.init()
        self.title = title
        self.parts = []
        self.composer = "Unknown"
        self.tempo = 120

    proc add_part(self, part):
        part.parent = self
        push(self.parts, part)

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
