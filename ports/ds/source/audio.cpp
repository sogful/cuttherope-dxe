#include "audio.hpp"
#include "assets.hpp"
#include "gamelog.hpp"
#include "assetio.hpp"
#include <nds.h>
#include <cstdio>

namespace audio {
static bool enabled = true;
static int track = -1, channel = 1;
static bool musicpaused = false;
static bool buzzing = false;
static ui::view lastview = ui::view::playing;
// Only long sleep clips need the large slot. Normal voices and mouse/star
// sounds retain a second simultaneous channel without doubling that maximum.
static constexpr unsigned shortvoice = 72964;
alignas(32) static unsigned char longbuffer[assetio::padded(art::voicemax)], shortbuffer[assetio::padded(shortvoice)];
alignas(32) static unsigned char musicbuffer[assetio::padded(gamemusicbytes > menumusicbytes ? gamemusicbytes : menumusicbytes)];
static int voiceslot = 0;
static unsigned spoken = 0, spokenid = 0;

void initialize() { soundEnable(); }

void effect(const unsigned char* data, unsigned size) {
    if (!enabled) return;
    soundPlaySampleChannel(channel, data, SoundFormat_16Bit, size, 16000, 100, 64, false, 0);
    channel = channel % 12 + 1;
}

static bool playstream(const art::voice& sample) {
    if (!enabled) return false;
    if (!sample.size) return false;
    const int slot = sample.size > shortvoice ? 0 : voiceslot++ % 2;
    unsigned char* buffer = slot ? shortbuffer : longbuffer;
    soundKill(13 + slot);
    FILE* file = std::fopen("nitro:/voices.bin", "rb");
    const bool valid = assetio::seek(file,sample.offset,"voice") &&
        assetio::read(file,buffer,sample.size,"voice") == sample.size;
    if (file) std::fclose(file);
    if (!valid) { nocashMessage("CTRD DS: voice read failed"); return false; }
    DC_FlushRange(buffer, sample.size);
    soundPlaySampleChannel(13 + slot, buffer, SoundFormat_16Bit, sample.size, 16000, 100, 64, false, 0);
    return true;
}
bool speak(int costume, voice kind) {
    if (!playstream(art::voices[costume][static_cast<int>(kind)])) return false;
    ++spoken;
    const int index = static_cast<int>(kind);
    spokenid = index < 6 ? costume*6+index+1 : 96+costume*3+index-5;
    return true;
}
bool stream(int index) { return playstream(art::streameffects[index]); }
unsigned voices() { return spoken; }
unsigned lastvoice() { return spokenid; }

void update(const ui::controller& menu) {
    const bool silenced = enabled && !menu.effects;
    enabled = menu.effects;
    if (silenced || (menu.mode != lastview && menu.mode == ui::view::paused) || menu.reset) {
        for (int i = 1; i < 16; ++i) soundKill(i);
        buzzing = false;
    }
    const int target = menu.frontend() ? 1 : 0;
    if (target != track) {
        gamelog::trace("music.load.begin track=%d",target);
        gamelog::mark("music.read",target);
        soundKill(0);
        const unsigned size = target ? menumusicbytes : gamemusicbytes;
        FILE* file = std::fopen(target ? "nitro:/menumusic.bin" : "nitro:/gamemusic.bin", "rb");
        const bool valid = assetio::read(file,musicbuffer,size,"music") == size;
        if (file) std::fclose(file);
        if (!valid) { nocashMessage("CTRD DS: music read failed"); gamelog::event("music.load.failed track=%d",target); return; }
        DC_FlushRange(musicbuffer,size);
        soundPlaySampleChannel(0, musicbuffer, SoundFormat_8Bit, size, 11025, menu.music ? 45 : 0, 64, true, 0);
        track = target;
        musicpaused = false;
        gamelog::trace("music.load.end track=%d bytes=%u",target,size);
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
void world(const ui::controller& menu, const dx::simulation& game) {
    bool active = false;
    if (enabled && !menu.frontend() && menu.mode != ui::view::paused && menu.mode != ui::view::results)
        for (int i = 0; i < game.definition.spikecount; ++i) active = active || game.electric[i];
    if (active == buzzing) return;
    if (active) soundPlaySampleChannel(15, electricdata, SoundFormat_16Bit, electricbytes, 16000, 60, 64, true, 0);
    else soundKill(15);
    buzzing = active;
}
}
