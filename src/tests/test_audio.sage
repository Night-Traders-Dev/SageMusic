from tests.test_framework import assert_eq, assert_true
from audio.instrument_map import get_instrument_sfz, pitch_to_midi

proc test_audio():
    print "--- Testing Audio ---"
    
    # Test instrument mapping
    let sfz1 = get_instrument_sfz("Flute")
    assert_true(sfz1 != "assets/sfz/test_flute.sfz", "Flute maps to specific sfz")
    
    let sfz2 = get_instrument_sfz("Trumpet 1")
    let sfz3 = get_instrument_sfz("Trumpet 2")
    assert_eq(sfz2, sfz3, "Trumpet 1 and 2 map to the same sfz base")
    
    # Test pitch to MIDI
    # C4 = 60
    let m1 = pitch_to_midi("C4")
    assert_eq(60, m1, "C4 is 60")
    
    # C#4 = 61
    let m2 = pitch_to_midi("C#4")
    assert_eq(61, m2, "C#4 is 61")
    
    # Bb3 = 58
    let m3 = pitch_to_midi("Bb3")
    assert_eq(58, m3, "Bb3 is 58")
    
    # A4 = 69
    let m4 = pitch_to_midi("A4")
    assert_eq(69, m4, "A4 is 69")
    
    print "Audio tests passed.\n"
