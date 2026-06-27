from tests.test_framework import assert_eq, assert_true
from model.model import Score, Part, Measure, Voice, Note, Rest, MusicElement

proc test_model():
    print "--- Testing Model ---"
    
    let score = Score("Test Score")
    assert_eq("Test Score", score.title, "Score title matches")
    assert_eq(0, len(score.parts), "Score starts with 0 parts")
    
    let part = Part("Test Part")
    score.add_part(part)
    assert_eq(1, len(score.parts), "Score has 1 part after adding")
    assert_eq("Test Part", score.parts[0].name, "Part name matches")
    
    let measure = Measure()
    assert_eq("treble", measure.clef, "Measure defaults to treble clef")
    assert_eq("C Major", measure.key_signature, "Measure defaults to C Major")
    
    measure.set_time_signature(3, 4)
    assert_eq(3, measure.time_signature[0], "Time signature numerator")
    assert_eq(4, measure.time_signature[1], "Time signature denominator")
    
    part.add_measure(measure)
    assert_eq(1, len(part.measures), "Part has 1 measure")
    
    let voice = measure.get_voice(0)
    assert_true(voice != nil, "Voice 0 is created automatically or retrieved")
    
    let note = Note("C4", 0.25)
    assert_eq("Note", note.type, "Note type")
    assert_eq("C4", note.pitch, "Note pitch")
    assert_eq(0.25, note.duration, "Note duration")
    
    let rest = Rest(0.5)
    assert_eq("Rest", rest.type, "Rest type")
    assert_eq(0.5, rest.duration, "Rest duration")
    
    voice.add_element(note)
    voice.add_element(rest)
    assert_eq(2, len(voice.elements), "Voice has 2 elements")
    
    print "Model tests passed.\n"
