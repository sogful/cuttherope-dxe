#include <nds.h>
#include "simulation.hpp"
#include "presentation.hpp"
#include "assets.hpp"
#include "level.hpp"
#include "audio.hpp"
#include "frontend.hpp"
#include "trace.hpp"
#include <fat.h>
#include <sys/stat.h>
#include <cstdio>

struct diagnostics {
    std::uint32_t magic = 0x44585250, version = 4;
    std::uint32_t frames = 0, ticks = 0, state = 0, stars = 0;
    std::uint32_t micros = 0, peak = 0, late = 0, vblanks = 0;
    float x = 0, y = 0;
    std::uint32_t cuts = 0, touches = 0, resets = 0, paused = 0;
    std::uint32_t view = 0, effects = 1, music = 1, score = 0, bestscore = 0, beststars = 0;
    std::uint32_t locale = 0, pack = 0, clickcut = 0, scroll = 0, texturebytes = 0;
    std::uint32_t unlocked = 0, skintab = 0, candy = 0, rope = 0, costume = 0, trace = 0, skinoffset = 0, transition = 0, storage = 0;
};
extern "C" {
volatile diagnostics telemetry;
}
static volatile unsigned vblanks = 0;
static void vertical() { vblanks = vblanks + 1; }
static dx::simulation game;
static ui::controller menu;

int main() {
    irqSet(IRQ_VBLANK, vertical);
    irqEnable(IRQ_VBLANK);
    display::initialize();
    audio::initialize();
    game.reset(dx::firstlevel);
    if (fatInitDefault()) {
        char directory[192];
        std::snprintf(directory, sizeof(directory), "%sctrdx", fatGetDefaultDrive());
        mkdir(directory, 0777);
        menu.initialize(directory);
    }
    bool held = false;
    int touchx = 0, touchy = 0;
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
        if (touching) { touchx = touch.px; touchy = touch.py; }
        const dx::point pointer = display::world(touchx, touchy);
        int commands = 0;
        if (down & KEY_A) commands |= ui::accept;
        if (down & KEY_B) commands |= ui::cancel;
        if (down & KEY_START) commands |= ui::start;
        if (down & (KEY_UP | KEY_LEFT)) commands |= ui::previous;
        if (down & (KEY_DOWN | KEY_RIGHT)) commands |= ui::following;
        const ui::view oldview = menu.mode;
        if (display::busy()) menu.suspend({touchx, touchy, 0, touching});
        else menu.update(game, {touchx, touchy, commands, touching});
        if (menu.reset) {
            game.reset(dx::firstlevel);
            frame = shownstars = 0;
            shownmouth = shownresult = held = false;
            telemetry.resets = telemetry.resets + 1;
            trace::trail.reset();
        }
        audio::update(menu);
        if (menu.mode == ui::view::playing) {
            trace::trail.update(menu.gameTouch, pointer, menu.skins[3]);
            if (menu.gameTouch && (held ? game.swipe(previous, pointer) : menu.clickcut && game.tap(pointer))) {
                telemetry.cuts = telemetry.cuts + 1;
                audio::effect(ropebleak1data, ropebleak1bytes);
            }
            if (menu.gameTouch && !held) telemetry.touches = telemetry.touches + 1;
            previous = pointer;
            held = menu.gameTouch;
            game.tick();
            ++frame;
        } else held = false;
        if (game.count != shownstars) {
            if (game.count == 1) audio::effect(star1data, star1bytes);
            if (game.count == 2) audio::effect(star2data, star2bytes);
            if (game.count == 3) audio::effect(star3data, star3bytes);
            shownstars = game.count;
        }
        if (game.mouth && !shownmouth) {
            audio::effect(monsteropendata, monsteropenbytes);
            shownmouth = true;
        }
        if (game.state == dx::outcome::won && !shownresult) {
            audio::effect(monsterchewingdata, monsterchewingbytes);
            audio::effect(windata, winbytes);
            shownresult = true;
            nocashMessage("CTRD DS: level won");
        }
        menu.advance(game);
        if (menu.clicked || menu.mode != oldview) menu.persist();
        display::draw(game, frame, menu, menu.gameTouch, pointer);
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
        telemetry.paused = menu.mode != ui::view::playing;
        telemetry.view = static_cast<unsigned>(menu.mode);
        telemetry.effects = menu.effects;
        telemetry.music = menu.music;
        telemetry.score = menu.score;
        telemetry.bestscore = menu.bestscore;
        telemetry.beststars = menu.beststars;
        telemetry.locale = menu.locale;
        telemetry.pack = menu.pack;
        telemetry.clickcut = menu.clickcut;
        telemetry.scroll = static_cast<unsigned>(menu.creditoffset);
        telemetry.texturebytes = frontend::texturebytes();
        telemetry.unlocked = menu.unlockall();
        telemetry.skintab = menu.skintab;
        telemetry.candy = menu.skins[0]; telemetry.rope = menu.skins[1]; telemetry.costume = menu.skins[2]; telemetry.trace = menu.skins[3];
        telemetry.skinoffset = menu.skinoffsets[menu.skintab];
        telemetry.transition = display::busy();
        telemetry.storage = !menu.saves.writable ? 0 : menu.saves.failed ? 2 : 1;
    }
}
