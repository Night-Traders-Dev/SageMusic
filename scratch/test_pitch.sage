from src.layout.layout import pitch_to_y

print "Testing pitch_to_y with valid and invalid inputs:"
print "C4: " + str(pitch_to_y("treble", "C4"))
print "F#3: " + str(pitch_to_y("treble", "F#3"))
print "Empty: " + str(pitch_to_y("treble", ""))
print "Single char: " + str(pitch_to_y("treble", "C"))
print "No octave: " + str(pitch_to_y("treble", "C#"))
print "Invalid letter: " + str(pitch_to_y("treble", "Z4"))
print "Multiple accidentals: " + str(pitch_to_y("treble", "C##4"))
