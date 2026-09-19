#include "audio.hpp"
#include "assets.hpp"
#include <nds.h>

namespace audio {
static bool enabled = true;
static int track = -1, channel = 1;
static bool musicpaused = false;
static ui::view lastview = ui::view::playing;

void initialize() { soundEnable(); }

void effect(const unsigned char* data, unsigned size) {
    if (!enabled) return;
    soundPlaySampleChannel(channel, data, SoundFormat_16Bit, size, 16000, 100, 64, false, 0);
    channel = channel % 15 + 1;
}

void update(const ui::controller& menu) {
    const bool silenced = enabled && !menu.effects;
    enabled = menu.effects;
    if (silenced || (menu.mode != lastview && menu.mode == ui::view::paused) || menu.reset) {
        for (int i = 1; i < 16; ++i) soundKill(i);
    }
    const int target = menu.mode == ui::view::home || menu.mode == ui::view::levels ? 1 : 0;
    if (target != track) {
        soundKill(0);
        soundPlaySampleChannel(0, target ? menumusicdata : gamemusicdata, SoundFormat_8Bit,
                               target ? menumusicbytes : gamemusicbytes, 11025, menu.music ? 45 : 0, 64, true, 0);
        track = target;
        musicpaused = false;
    }
    const bool pause = !menu.music || menu.mode == ui::view::paused;
    if (pause != musicpaused) {
        if (pause) soundPause(0);
        else soundResume(0);
        musicpaused = pause;
    }
    soundSetVolume(0, menu.music ? 45 : 0);
    if (menu.clicked) effect(tapdata, tapbytes);
    lastview = menu.mode;
}
}
