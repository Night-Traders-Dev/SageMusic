#define MINIAUDIO_IMPLEMENTATION
#include "../../deps/miniaudio.h"
#include <sfizz.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_BUFFER_FRAMES 1024

static ma_device g_device;
static sfizz_synth_t* g_synths[16] = {NULL};

static float bufL[MAX_BUFFER_FRAMES];
static float bufR[MAX_BUFFER_FRAMES];

typedef struct {
    int delay_samples;
    int type; // 1=note_on, 0=note_off
    int channel;
    int pitch;
    int velocity;
} MidiEvent;

#define MAX_EVENTS 10000
static MidiEvent g_events[MAX_EVENTS];
static int g_event_count = 0;
static int g_current_frame = 0;
static int g_playback_active = 0;

static void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount)
{
    float* out = (float*)pOutput;
    
    ma_uint32 framesToProcess = frameCount > MAX_BUFFER_FRAMES ? MAX_BUFFER_FRAMES : frameCount;
    memset(bufL, 0, sizeof(float) * framesToProcess);
    memset(bufR, 0, sizeof(float) * framesToProcess);
    
    if (g_playback_active) {
        for (int i = 0; i < g_event_count; i++) {
            int ev_frame = g_events[i].delay_samples;
            if (ev_frame >= g_current_frame && ev_frame < g_current_frame + (int)framesToProcess) {
                int offset = ev_frame - g_current_frame;
                int ch = g_events[i].channel;
                if (ch >= 0 && ch < 16 && g_synths[ch]) {
                    if (g_events[i].type == 1) {
                        sfizz_send_note_on(g_synths[ch], offset, g_events[i].pitch, g_events[i].velocity);
                    } else {
                        sfizz_send_note_off(g_synths[ch], offset, g_events[i].pitch, 0);
                    }
                }
            }
        }
        g_current_frame += framesToProcess;
    }
    
    for (int ch = 0; ch < 16; ch++) {
        if (g_synths[ch]) {
            float tempL[MAX_BUFFER_FRAMES];
            float tempR[MAX_BUFFER_FRAMES];
            float* temp_channels[2] = { tempL, tempR };
            sfizz_render_block(g_synths[ch], temp_channels, 2, framesToProcess);
            for (ma_uint32 i = 0; i < framesToProcess; i++) {
                bufL[i] += tempL[i];
                bufR[i] += tempR[i];
            }
        }
    }
    
    for (ma_uint32 i = 0; i < framesToProcess; i++) {
        out[i * 2 + 0] = bufL[i];
        out[i * 2 + 1] = bufR[i];
    }
}

int audio_init(void) {
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format   = ma_format_f32;
    config.playback.channels = 2;
    config.sampleRate        = 48000;
    config.dataCallback      = data_callback;
    
    if (ma_device_init(NULL, &config, &g_device) != MA_SUCCESS) {
        return 0;
    }
    
    ma_device_start(&g_device);
    return 1;
}

int audio_load_instrument(int channel, const char* path) {
    if (channel < 0 || channel >= 16) return 0;
    if (!g_synths[channel]) {
        g_synths[channel] = sfizz_create_synth();
        sfizz_set_samples_per_block(g_synths[channel], 256);
        sfizz_set_sample_rate(g_synths[channel], 48000.0f);
    }
    return sfizz_load_file(g_synths[channel], path) ? 1 : 0;
}

void audio_note_on(int delay, int channel, int pitch, int velocity) {
    if (g_event_count < MAX_EVENTS) {
        g_events[g_event_count].delay_samples = delay;
        g_events[g_event_count].type = 1;
        g_events[g_event_count].channel = channel;
        g_events[g_event_count].pitch = pitch;
        g_events[g_event_count].velocity = velocity;
        g_event_count++;
    }
}

void audio_note_off(int delay, int channel, int pitch) {
    if (g_event_count < MAX_EVENTS) {
        g_events[g_event_count].delay_samples = delay;
        g_events[g_event_count].type = 0;
        g_events[g_event_count].channel = channel;
        g_events[g_event_count].pitch = pitch;
        g_events[g_event_count].velocity = 0;
        g_event_count++;
    }
}

int audio_clear_events(void) {
    g_event_count = 0;
    g_current_frame = 0;
    return 1;
}

int audio_start_playback(void) {
    g_playback_active = 1;
    return 1;
}

int audio_stop_playback(void) {
    g_playback_active = 0;
    for (int ch = 0; ch < 16; ch++) {
        if (g_synths[ch]) {
            sfizz_send_cc(g_synths[ch], 0, 123, 0); // All notes off
        }
    }
    return 1;
}
