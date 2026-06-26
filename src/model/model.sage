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
        self.dirty = true

    proc mark_dirty(self):
        self.dirty = true
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
        
        # Advanced features
        self.dynamics = "mf"  # Dynamic marking: ppp, pp, p, mp, mf, f, ff, fff
        self.velocity = 80    # MIDI velocity (0-127)
        self.articulation = nil  # staccato, accent, tenuto, marcato, etc.
        self.technique = nil  # pizzicato, tremolo, trill, glissando, etc.
        self.expression = {}  # Custom expression data

    # SEC-IV-5: Accidental validation
    proc set_accidental(self, acc):
        if acc == "sharp" or acc == "flat" or acc == "natural":
            self.accidental = acc
        else:
            self.accidental = nil

    proc set_dynamics(self, dynamic_level):
        let valid_dynamics = ["ppp", "pp", "p", "mp", "mf", "f", "ff", "fff"]
        if contains(valid_dynamics, dynamic_level):
            self.dynamics = dynamic_level
            # Map to MIDI velocity
            if dynamic_level == "ppp":
                self.velocity = 20
            elif dynamic_level == "pp":
                self.velocity = 35
            elif dynamic_level == "p":
                self.velocity = 50
            elif dynamic_level == "mp":
                self.velocity = 65
            elif dynamic_level == "mf":
                self.velocity = 80
            elif dynamic_level == "f":
                self.velocity = 95
            elif dynamic_level == "ff":
                self.velocity = 110
            elif dynamic_level == "fff":
                self.velocity = 127
    
    proc set_articulation(self, articulation_type):
        let valid_articulations = ["staccato", "accent", "tenuto", "marcato", "staccatissimo", "fermata"]
        if contains(valid_articulations, articulation_type):
            self.articulation = articulation_type
    
    proc set_technique(self, technique_type):
        let valid_techniques = ["pizzicato", "tremolo", "trill", "glissando", "harmonics", "mute"]
        if contains(valid_techniques, technique_type):
            self.technique = technique_type

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
        let v = Voice()
        self.voices = [v]
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
        self.all_elements = [] # Flat list of all elements for fast iteration

    proc mark_dirty(self):
        self.dirty = true

    proc rebuild_element_cache(self):
        self.all_elements = []
        let p_idx = 0
        while p_idx < len(self.parts):
            let part = self.parts[p_idx]
            let m_idx = 0
            while m_idx < len(part.measures):
                let measure = part.measures[m_idx]
                let v_idx = 0
                while v_idx < len(measure.voices):
                    let voice = measure.voices[v_idx]
                    let e_idx = 0
                    while e_idx < len(voice.elements):
                        push(self.all_elements, voice.elements[e_idx])
                        e_idx = e_idx + 1
                    v_idx = v_idx + 1
                m_idx = m_idx + 1
            p_idx = p_idx + 1

    proc clear_selection(self):
        let i = 0
        while i < len(self.all_elements):
            self.all_elements[i].selected = false
            self.all_elements[i].hovered_delete = false
            i = i + 1

    proc clear_hovered_delete(self):
        let i = 0
        while i < len(self.all_elements):
            self.all_elements[i].hovered_delete = false
            i = i + 1

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
