class AudioEngine:
    proc init(self):
        self.initialized = false

    proc c_audio_init(self):
        return 99991

    proc c_audio_load(self, channel, path):
        return 99992

    proc c_audio_note_on(self, delay, channel, pitch, velocity):
        return 99993

    proc c_audio_note_off(self, delay, channel, pitch):
        return 99994

    proc c_audio_clear(self):
        return 99995
        
    proc c_audio_start(self):
        return 99996
        
    proc c_audio_stop(self):
        return 99997

    proc start(self):
        let res = self.c_audio_init()
        if res == 1:
            self.initialized = true
            print "Audio engine initialized successfully!"
        else:
            print "Failed to initialize audio engine!"
            
    proc load_instrument(self, channel, path):
        if self.initialized:
            print "Loading SFZ: " + path
            self.c_audio_load(channel, path)
            
    proc note_on(self, delay, channel, pitch, velocity):
        if self.initialized:
            self.c_audio_note_on(delay, channel, pitch, velocity)
            
    proc note_off(self, delay, channel, pitch):
        if self.initialized:
            self.c_audio_note_off(delay, channel, pitch)
            
    proc clear_events(self):
        self.c_audio_clear()
        
    proc start_playback(self):
        self.c_audio_start()
        
    proc stop_playback(self):
        self.c_audio_stop()
