#include <nds.h>
#include "simulation.hpp"
#include "presentation.hpp"
#include "assets.hpp"
#include "level.hpp"

struct diagnostics {
    std::uint32_t magic = 0x44585250, version = 1;
    std::uint32_t frames = 0, ticks = 0, state = 0, stars = 0;
    std::uint32_t micros = 0, peak = 0, late = 0, vblanks = 0;
    float x = 0, y = 0;
    std::uint32_t cuts = 0, touches = 0, resets = 0, paused = 0;
};
extern "C" {
volatile diagnostics telemetry;
}
static volatile unsigned vblanks = 0;
static void vertical() { vblanks = vblanks + 1; }
static dx::simulation game;

static void sound(const unsigned char* data, unsigned size) {
    soundPlaySample(data, SoundFormat_16Bit, size, 16000, 100, 64, false, 0);
}

int main() {
    irqSet(IRQ_VBLANK, vertical);
    irqEnable(IRQ_VBLANK);
    display::initialize();
    soundEnable();
    game.reset(dx::firstlevel);
    bool held = false, paused = false;
    dx::point previous{};
    int frame = 0, shownstars = 0;
    bool shownmouth = false, shownresult = false;
    unsigned total = 0, peak = 0, late = 0;
    nocashMessage("CTRD DS: ready");
    while (true) {
        swiWaitForVBlank();
        const unsigned beginblank = vblanks;
        cpuStartTiming(0);
        scanKeys();
        const int down = keysDown(), keys = keysHeld();
        touchPosition touch{};
        touchRead(&touch);
        const bool touching = keys & KEY_TOUCH;
        const dx::point pointer = display::world(touch.px, touch.py);
        if (down & KEY_START) paused = !paused;
        if ((down & KEY_A) || ((down & KEY_TOUCH) &&
            (display::retry(touch.px, touch.py) || game.state != dx::outcome::playing))) {
            game.reset(dx::firstlevel);
            frame = shownstars = 0;
            shownmouth = shownresult = held = paused = false;
            telemetry.resets = telemetry.resets + 1;
        }
        if (!paused) {
            if (touching && held && game.swipe(previous, pointer)) {
                telemetry.cuts = telemetry.cuts + 1;
                sound(ropebleak1data, ropebleak1bytes);
            }
            if (touching && !held) telemetry.touches = telemetry.touches + 1;
            previous = pointer;
            held = touching;
            game.tick();
            ++frame;
        } else held = false;
        if (game.count != shownstars) {
            if (game.count == 1) sound(star1data, star1bytes);
            if (game.count == 2) sound(star2data, star2bytes);
            if (game.count == 3) sound(star3data, star3bytes);
            shownstars = game.count;
        }
        if (game.mouth && !shownmouth) {
            sound(monsteropendata, monsteropenbytes);
            shownmouth = true;
        }
        if (game.state == dx::outcome::won && !shownresult) {
            sound(monsterchewingdata, monsterchewingbytes);
            sound(windata, winbytes);
            shownresult = true;
            nocashMessage("CTRD DS: level won");
        }
        display::draw(game, frame, paused, touching && !paused, pointer);
        const unsigned micros = timerTicks2usec(cpuEndTiming());
        if (micros > peak) peak = micros;
        const unsigned elapsed = vblanks - beginblank;
        late += elapsed;
        ++total;
        telemetry.frames = total;
        telemetry.ticks = game.ticks;
        telemetry.state = static_cast<unsigned>(game.state);
        telemetry.stars = game.count;
        telemetry.micros = micros;
        telemetry.peak = peak;
        telemetry.late = late;
        telemetry.vblanks = vblanks;
        telemetry.x = game.candy().pos.x;
        telemetry.y = game.candy().pos.y;
        telemetry.paused = paused;
    }
}
