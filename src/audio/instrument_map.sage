import strings

proc get_instrument_sfz(name):
    if strings.starts_with(name, "Flute"):
        return "assets/sfz/VSCO2/Woodwinds/Flute/Flute-sus-stac.sfz"
    elif strings.starts_with(name, "Oboe") or strings.starts_with(name, "English Horn"):
        return "assets/sfz/VSCO2/Woodwinds/Oboe/Oboe-sus-stac.sfz"
    elif strings.starts_with(name, "Clarinet"):
        return "assets/sfz/VSCO2/Woodwinds/Clarinet/Clarinet-sus-stac.sfz"
    elif strings.starts_with(name, "Bassoon"):
        return "assets/sfz/VSCO2/Woodwinds/Bassoon/Bassoon-sus-stac.sfz"
    elif strings.starts_with(name, "Trumpet"):
        return "assets/sfz/VSCO2/Brass/Trumpet/Trumpet-sus-stac.sfz"
    elif strings.starts_with(name, "Horn"):
        return "assets/sfz/VSCO2/Brass/Horn/Horn-sus-stac.sfz"
    elif strings.starts_with(name, "Trombone"):
        return "assets/sfz/VSCO2/Brass/Trombone/Trombone-sus-stac.sfz"
    elif strings.starts_with(name, "Tuba"):
        return "assets/sfz/VSCO2/Brass/Tuba/Tuba-sus-stac.sfz"
    elif strings.starts_with(name, "Violin"):
        return "assets/sfz/VSCO2/Strings/Violin/Violin-sus-stac.sfz"
    elif strings.starts_with(name, "Viola"):
        return "assets/sfz/VSCO2/Strings/Viola/Viola-sus-stac.sfz"
    elif strings.starts_with(name, "Cello"):
        return "assets/sfz/VSCO2/Strings/Cello/Cello-sus-stac.sfz"
    elif strings.starts_with(name, "Double Bass") or strings.starts_with(name, "Contrabass") or strings.starts_with(name, "Bass"):
        return "assets/sfz/VSCO2/Strings/Double Bass/Double Bass-sus-stac.sfz"
    elif strings.starts_with(name, "Piano"):
        return "assets/sfz/VSCO2/Keyboards/Piano/Piano.sfz"
    elif strings.starts_with(name, "Snare"):
        return "assets/sfz/VSCO2/Percussion/Snare/Snare.sfz"
    elif strings.starts_with(name, "Timpani"):
        return "assets/sfz/VSCO2/Percussion/Timpani/Timpani.sfz"
    elif strings.starts_with(name, "Alto Sax") or strings.starts_with(name, "Tenor Sax") or strings.starts_with(name, "Baritone Sax"):
        return "assets/sfz/VSCO2/Woodwinds/Clarinet/Clarinet-sus-stac.sfz" # fallback
    else:
        return "assets/sfz/test_flute.sfz"

proc pitch_to_midi(pitch):
    if len(pitch) < 2:
        return 60

    let letter = pitch[0]
    let step_idx = 0
    if letter == "C" or letter == "c":
        step_idx = 0
    elif letter == "D" or letter == "d":
        step_idx = 2
    elif letter == "E" or letter == "e":
        step_idx = 4
    elif letter == "F" or letter == "f":
        step_idx = 5
    elif letter == "G" or letter == "g":
        step_idx = 7
    elif letter == "A" or letter == "a":
        step_idx = 9
    elif letter == "B" or letter == "b":
        step_idx = 11

    let oct_char = pitch[len(pitch) - 1]
    let octave = 4
    if oct_char >= "0" and oct_char <= "9":
        octave = int(oct_char)
        
    let acc = 0
    if len(pitch) > 2:
        if pitch[1] == "#":
            acc = 1
        elif pitch[1] == "b":
            acc = -1

    return (octave + 1) * 12 + step_idx + acc
