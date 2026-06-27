from tests.test_framework import assert_eq, assert_true
from layout.layout import y_to_pitch, pitch_to_y, get_element_width, calculate_measure_content_width
from model.model import Note, Rest, Measure, Voice

proc test_layout():
    print "--- Testing Layout ---"
    
    # y_to_pitch tests
    # Treble clef ref_val = 30 (E4, bottom line). pos = 0 should be E4
    let pitch1 = y_to_pitch("treble", 0)
    assert_eq("E4", pitch1, "Treble pos 0 is E4")
    
    # pos = 8 should be F5 (top line)
    let pitch2 = y_to_pitch("treble", 8)
    assert_eq("F5", pitch2, "Treble pos 8 is F5")
    
    # Bass clef ref_val = 18 (G2, bottom line). pos = 0 should be G2
    let pitch3 = y_to_pitch("bass", 0)
    assert_eq("G2", pitch3, "Bass pos 0 is G2")
    
    # pitch_to_y tests
    # ref_val = 38 (F5, top line). pitch_to_y(F5) should be 0
    let y1 = pitch_to_y("treble", "F5")
    assert_eq(0.0, y1, "Treble F5 maps to 0")
    
    # pitch_to_y(E4) (which is 30, so 30-38 = -8). -8 * 4.0 = -32.0
    let y2 = pitch_to_y("treble", "E4")
    assert_eq(-32.0, y2, "Treble E4 maps to -32")
    
    # Element width tests
    let n1 = Note("C4", 1.0)
    let n2 = Note("C4", 0.5)
    let n3 = Note("C4", 0.25)
    let n4 = Note("C4", 0.125)
    
    let w1 = get_element_width(n1)
    let w2 = get_element_width(n2)
    let w3 = get_element_width(n3)
    let w4 = get_element_width(n4)
    
    assert_true(w1 > w2, "Whole note wider than half")
    assert_true(w2 > w3, "Half note wider than quarter")
    assert_true(w3 > w4, "Quarter note wider than eighth")
    
    # Measure width tests
    let m = Measure()
    let v = m.get_voice(0)
    v.add_element(n3)
    v.add_element(n3)
    
    let m_width = calculate_measure_content_width(m)
    assert_true(m_width > 0.0, "Measure width is positive")
    
    print "Layout tests passed.\n"
