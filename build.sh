#!/bin/bash
set -e

echo "Skipping sfizz build..."
# cd deps/sfizz
# rm -rf build
# mkdir -p build
# cd build
# cmake .. -DSFIZZ_SHARED_LIBRARY=OFF -DSFIZZ_TESTS=OFF -DCMAKE_BUILD_TYPE=Release -DSFIZZ_JACK=OFF -DSFIZZ_RENDER=OFF -DSFIZZ_USE_SNDFILE=OFF
# make -j4
# cd ../../../

echo "Compiling SageMusic to C..."
sage --emit-c src/main.sage -o out.c || true

# Inject C wrapper declarations
sed -i '1s/^/#include <string.h>\nint audio_init();\nint audio_load_instrument(int channel, const char* path);\nvoid audio_note_on(int delay, int channel, int pitch, int velocity);\nvoid audio_note_off(int delay, int channel, int pitch);\nint audio_clear_events();\nint audio_start_playback();\nint audio_stop_playback();\n/' out.c

# Inject C wrapper calls
sed -i 's/return sage_gc_return(&sage_gc_frame, sage_number(99991));/int res = audio_init(); return sage_gc_return(\&sage_gc_frame, sage_number(res));/' out.c
sed -i 's/return sage_gc_return(&sage_gc_frame, sage_number(99992));/int res = audio_load_instrument((int)_argv[0].as.number, _argv[1].as.string); return sage_gc_return(\&sage_gc_frame, sage_number(res));/' out.c
sed -i 's/return sage_gc_return(&sage_gc_frame, sage_number(99993));/audio_note_on((int)_argv[0].as.number, (int)_argv[1].as.number, (int)_argv[2].as.number, (int)_argv[3].as.number); return sage_gc_return(\&sage_gc_frame, sage_number(0));/' out.c
sed -i 's/return sage_gc_return(&sage_gc_frame, sage_number(99994));/audio_note_off((int)_argv[0].as.number, (int)_argv[1].as.number, (int)_argv[2].as.number); return sage_gc_return(\&sage_gc_frame, sage_number(0));/' out.c
sed -i 's/return sage_gc_return(&sage_gc_frame, sage_number(99995));/int res = audio_clear_events(); return sage_gc_return(\&sage_gc_frame, sage_number(res));/' out.c
sed -i 's/return sage_gc_return(&sage_gc_frame, sage_number(99996));/int res = audio_start_playback(); return sage_gc_return(\&sage_gc_frame, sage_number(res));/' out.c
sed -i 's/return sage_gc_return(&sage_gc_frame, sage_number(99997));/int res = audio_stop_playback(); return sage_gc_return(\&sage_gc_frame, sage_number(res));/' out.c


gcc -O3 out.c src/audio/engine_ffi.c -o sagemusic -I./deps/sfizz/src -L./deps/sfizz/build/library/lib -lsfizz -lstdc++ -lm -lpthread -ldl -lglfw -lvulkan

echo "Done!"
