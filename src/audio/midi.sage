# -----------------------------------------
# midi.sage - SageMusic MIDI Input/Output
# Professional MIDI integration
# -----------------------------------------

# MIDI note number to pitch string
proc midi_to_pitch(midi_note):
    let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let octave = int(midi_note / 12) - 1
    let note_idx = midi_note % 12
    return notes[note_idx] + str(octave)

# Pitch string to MIDI note number
proc pitch_to_midi(pitch_str):
    if len(pitch_str) < 2:
        return 60 # Middle C default
    
    let note_map = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    let letter = pitch_str[0]
    let octave_str = pitch_str[1]
    
    if len(pitch_str) == 3:
        let accidental = pitch_str[1]
        octave_str = pitch_str[2]
        if accidental == "#":
            return pitch_to_midi(letter + octave_str) + 1
        elif accidental == "b":
            return pitch_to_midi(letter + octave_str) - 1
    
    if not dict_has(note_map, letter):
        return 60
    
    let semitone = note_map[letter]
    let octave = int(octave_str)
    return 12 * (octave + 1) + semitone

# MIDI Controller
class MIDIController:
    proc init(self):
        self.input_enabled = false
        self.output_enabled = false
        self.recording = false
        self.recorded_events = []
        self.quantize_enabled = true
        self.quantize_value = 0.25 # Quarter note
    
    proc enable_input(self):
        self.input_enabled = true
        print "MIDI input enabled"
    
    proc enable_output(self):
        self.output_enabled = true
        print "MIDI output enabled"
    
    proc start_recording(self):
        self.recording = true
        self.recorded_events = []
        print "MIDI recording started"
    
    proc stop_recording(self):
        self.recording = false
        print "MIDI recording stopped - captured " + str(len(self.recorded_events)) + " events"
        return self.recorded_events
    
    proc quantize_duration(self, duration):
        if not self.quantize_enabled:
            return duration
        let ratio = duration / self.quantize_value
        let rounded = math.round(ratio)
        return rounded * self.quantize_value
    
    proc record_note(self, midi_note, velocity, duration):
        let event = {}
        event["type"] = "note"
        event["pitch"] = midi_to_pitch(midi_note)
        event["velocity"] = velocity
        event["duration"] = self.quantize_duration(duration)
        event["timestamp"] = clock()
        push(self.recorded_events, event)
    
    proc export_midi_file(self, score, filename):
        # MIDI file export (simplified)
        print "Exporting MIDI: " + filename
        let midi_events = []
        
        # Convert score to MIDI events
        let p_idx = 0
        while p_idx < len(score.parts):
            let part = score.parts[p_idx]
            let time = 0.0
            let m_idx = 0
            while m_idx < len(part.measures):
                let measure = part.measures[m_idx]
                let v_idx = 0
                while v_idx < len(measure.voices):
                    let voice = measure.voices[v_idx]
                    let e_idx = 0
                    while e_idx < len(voice.elements):
                        let elem = voice.elements[e_idx]
                        if elem.type == "Note":
                            let event = {}
                            event["time"] = time
                            event["midi_note"] = pitch_to_midi(elem.pitch)
                            event["duration"] = elem.duration
                            event["velocity"] = 100
                            push(midi_events, event)
                        time = time + elem.duration
                        e_idx = e_idx + 1
                    v_idx = v_idx + 1
                m_idx = m_idx + 1
            p_idx = p_idx + 1
        
        print "Generated " + str(len(midi_events)) + " MIDI events"
        return midi_events

proc create_midi_controller():
    return MIDIController()
