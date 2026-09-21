#include <nds.h>
#include "simulation.hpp"
#include "presentation.hpp"
#include "assets.hpp"
#include "level.hpp"
#include "audio.hpp"
#include "frontend.hpp"
#include "menuassets.hpp"
#include "trace.hpp"
#include "profiling.hpp"
#include "upper.hpp"
#include <fat.h>
#include <sys/stat.h>
#include <cstdio>
#include <algorithm>

struct diagnostics {
    std::uint32_t magic = 0x44585250, version = 18;
    std::uint32_t frames = 0, ticks = 0, state = 0, stars = 0;
    std::uint32_t micros = 0, peak = 0, late = 0, vblanks = 0;
    float x = 0, y = 0;
    std::uint32_t cuts = 0, touches = 0, resets = 0, paused = 0;
    std::uint32_t view = 0, effects = 1, music = 1, score = 0, bestscore = 0, beststars = 0;
    std::uint32_t locale = 0, pack = 0, clickcut = 0, scroll = 0, texturebytes = 0;
    std::uint32_t unlocked = 0, skintab = 0, candy = 0, rope = 0, costume = 0, trace = 0, skinoffset = 0, transition = 0, storage = 0;
    std::uint32_t door = 0, doorframe = 0, menuage = 0, improved = 0;
    std::uint32_t level = 0, visuals = 0, bubble = 0, pumps = 0, ropes = 0, failure = 0, intro = 0, cameray = 0, hooks = 0;
    std::uint32_t split = 0, merges = 0, teleports = 0, bounces = 0, rail = 0;
    std::uint32_t flash = 0, flashframe = 0, voices = 0, voice = 0;
    std::uint32_t repacks = 0, renderfault = 0;
    std::uint32_t gravity = 0, gravityevents = 0, wheel = 0, wheelevents = 0, wheelparts = 0, wheellength = 0;
    std::uint32_t spikeevents = 0, spikebutton = 0, beex = 0, beey = 0, spiderfalls = 0, spiderclimbers = 0, fadephase = 0;
    std::uint32_t disc = 0, discangle = 0, discevents = 0, ghostforms = 0, ghostevents = 0, ghostapps = 0, bodypool = 0;
    std::uint32_t steamevents = 0, steamstates = 0, captures = 0, releases = 0, occupied = 0, shared = 0, lanternx = 0, lanterny = 0;
    std::uint32_t mouse = 0, mousecaptures = 0, mousereleases = 0, mousehandoffs = 0, mousecarry = 0;
    std::uint32_t bulb = 0, bulbx = 0, bulby = 0, awake = 0, lit = 0;
    std::uint32_t belt = 0, beltwraps = 0, belthandoffs = 0, beltoffset = 0, beltitems = 0;
    std::uint32_t mouth = 0, mouthtick = 0, nightstart = 0;
    std::uint32_t upperfault = 0, upperframes = 0, upperreads = 0;
    std::uint32_t popup = 0, popupage = 0;
};
extern "C" {
volatile diagnostics telemetry;
#ifdef DS_PROFILE
volatile unsigned profiledata[32];
volatile unsigned profilestress = 0;
#endif
}
static volatile unsigned vblanks = 0;
static void vertical() { vblanks = vblanks + 1; frontend::capture(); upper::vblank(); }
static dx::simulation game;
static ui::controller menu;

int main() {
    irqSet(IRQ_VBLANK, vertical);
    irqEnable(IRQ_VBLANK);
    display::initialize();
    audio::initialize();
    game.reset(dx::loadlevel(0));
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
    bool objecttouch = false;
    int shownbubbles = 0, shownpops = 0, shownpumps = 0, shownropes = 0;
    int shownbounces = 0, shownteleports = 0, shownmerges = 0;
    int showngravity = 0, shownwheel = 0;
    int shownspikes = 0, shownspiderfalls = 0, shownspideractivations = 0;
    int showndiscs = 0, shownghosts = 0;
    int shownsteam = 0, showncaptures = 0, shownreleases = 0;
    int shownmice = 0, shownsleep = 0, shownlight[3] = {-1000,-1000,-1000};
    int shownbelts = 0;
    bool shownmouth = false, shownresult = false;
    bool greeting = false;
    unsigned total = 0, peak = 0;
    auto resetgame = [&]() {
        game.reset(dx::loadlevel(menu.levelid()));
        frame = shownstars = 0;
        shownmouth = shownresult = held = objecttouch = false;
        shownbubbles = shownpops = shownpumps = shownropes = 0;
        shownbounces = shownteleports = shownmerges = 0;
        showngravity = shownwheel = 0;
        shownspikes = shownspiderfalls = shownspideractivations = 0;
        showndiscs = shownghosts = 0;
        shownsteam = showncaptures = shownreleases = 0;
        shownbelts = 0;
        shownmice = shownsleep = 0; std::fill(std::begin(shownlight),std::end(shownlight),-1000);
        telemetry.resets = telemetry.resets + 1;
        trace::trail.reset();
        greeting = menu.door == 1 && !menu.replaypanel;
    };
    nocashMessage("CTRD DS: ready");
    while (true) {
        swiWaitForVBlank();
        cpuStartTiming(0);
        DS_PROFILE_DO(profiling::begin());
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
        const bool resetbefore = menu.reset;
        if (resetbefore) resetgame();
        audio::update(menu);
        if (menu.mode == ui::view::playing && !display::busy()) {
            trace::trail.update(menu.gameTouch, pointer, menu.skins[3]);
            if (menu.gameTouch && !held) objecttouch = game.interact(pointer);
            game.drag(pointer, menu.gameTouch && objecttouch);
            if (menu.gameTouch && !objecttouch && (held ? game.swipe(previous, pointer) : menu.clickcut && game.tap(pointer))) {
                telemetry.cuts = telemetry.cuts + 1;
                audio::effect(ropebleak1data, ropebleak1bytes);
            }
            if (menu.gameTouch && !held) telemetry.touches = telemetry.touches + 1;
            previous = pointer;
            held = menu.gameTouch;
            game.tick(menu.flash == 1);
        } else {
            held = false;
            game.dragswitch = game.dragspike = -1;
            game.drag(pointer, false);
            if (!menu.frontend() && (menu.mode != ui::view::paused || menu.door) && display::active()) {
                if (menu.mode == ui::view::paused || (menu.mode == ui::view::results && menu.age >= 32)) game.animate();
                else game.tick();
            }
        }
        DS_PROFILE_DO(if (profilestress & 8) {
            profilestress = profilestress & ~8u;
            for (int i=0;i<game.definition.tubecount;++i) {
                game.valvetap(i); game.valvetap(i);
            }
        });
        DS_PROFILE_DO(if (profilestress & 4) {
            profilestress = profilestress & ~4u;
            game.state = dx::outcome::won;
            game.resulttick = game.ticks; game.resultvisual = game.visuals;
            game.bodies[0].pin = game.candy().pos; game.bodies[0].pinned = true;
            game.stars.fill(true); game.count = 3;
        });
        DS_PROFILE_DO(if (profilestress & 16) {
            // A deterministic overlap probe, profile ROMs only. Bit 32 hides
            // Om Nom so the harness can compare the candy's opaque pixels.
            game.state = dx::outcome::playing; game.failreason = 0;
            game.definition.hookcount = 0;
            game.bodies[0].pos = {1280,1120};
            game.definition.target = {profilestress & 32 ? 4280.0f : 1280.0f,1180};
            game.mouth = true; game.mouthtick = 0; game.ticks = game.visuals = 20;
            game.stars.fill(true); game.count = 0;
        });
        frame = game.visuals;
        audio::world(menu, game);
        if (game.gravityevents != showngravity) {
            audio::effect(game.inverted ? gravityondata : gravityoffdata, game.inverted ? gravityonbytes : gravityoffbytes);
            showngravity = game.gravityevents;
        }
        if (game.wheelevents != shownwheel) { audio::effect(wheeldata, wheelbytes); shownwheel = game.wheelevents; }
        if (game.spikeevents != shownspikes) {
            audio::effect(game.spikedirection ? spikerotateindata : spikerotateoutdata, game.spikedirection ? spikerotateinbytes : spikerotateoutbytes);
            shownspikes = game.spikeevents;
        }
        if (game.discevents != showndiscs) {
            audio::effect(game.discdirection ? scratchoutdata : scratchindata,game.discdirection ? scratchoutbytes : scratchinbytes);
            showndiscs = game.discevents;
        }
        if (game.ghostevents != shownghosts) { audio::effect(ghostpuffdata,ghostpuffbytes); shownghosts = game.ghostevents; }
        if (game.steamevents != shownsteam) {
            const unsigned char* sounds[] = {steamenddata,steamstart2data,steamstartdata};
            const unsigned sizes[] = {steamendbytes,steamstart2bytes,steamstartbytes};
            audio::effect(sounds[game.steamstate],sizes[game.steamstate]); shownsteam = game.steamevents;
        }
        if (game.captures != showncaptures) { audio::effect(lanternteleportindata,lanternteleportinbytes); showncaptures = game.captures; }
        if (game.releases != shownreleases) { audio::effect(lanternteleportoutdata,lanternteleportoutbytes); shownreleases = game.releases; }
        if (game.mouseevents != shownmice) { audio::stream(game.mousesound); shownmice = game.mouseevents; }
        if (game.beltevents != shownbelts) { audio::stream(5+game.beltsound); shownbelts = game.beltevents; }
        if (game.sleepevents != shownsleep) { audio::speak(menu.skins[2],static_cast<audio::voice>(6+game.sleepevents%3)); shownsleep = game.sleepevents; }
        for (int i=0;i<3;++i) if (game.lightchange[i] != shownlight[i]) {
            if (game.starlit[i] && game.lightchange[i] > 1) audio::stream(3+i%2);
            shownlight[i] = game.lightchange[i];
        }
        if (game.spiderfalls != shownspiderfalls) { audio::effect(spiderfalldata, spiderfallbytes); shownspiderfalls = game.spiderfalls; }
        if (game.spideractivations != shownspideractivations) { audio::effect(spideractivatedata, spideractivatebytes); shownspideractivations = game.spideractivations; }
        if (game.bubbleevents != shownbubbles) { audio::effect(bubbledata, bubblebytes); shownbubbles = game.bubbleevents; }
        if (game.pops != shownpops) { audio::effect(bubblebreakdata, bubblebreakbytes); shownpops = game.pops; }
        if (game.pumpevents != shownpumps) { audio::effect(pump1data, pump1bytes); shownpumps = game.pumpevents; }
        if (game.ropeevents != shownropes) { audio::effect(ropegetdata, ropegetbytes); shownropes = game.ropeevents; }
        if (game.bounceevents != shownbounces) { audio::effect(bouncerdata, bouncerbytes); shownbounces = game.bounceevents; }
        if (game.teleportevents != shownteleports) { audio::effect(teleportdata, teleportbytes); shownteleports = game.teleportevents; }
        if (game.mergeevents != shownmerges) { audio::effect(candylinkdata, candylinkbytes); shownmerges = game.mergeevents; }
        if (game.count != shownstars) {
            if (game.count == 1) audio::effect(star1data, star1bytes);
            if (game.count == 2) audio::effect(star2data, star2bytes);
            if (game.count == 3) audio::effect(star3data, star3bytes);
            shownstars = game.count;
            if (menu.skins[2] > 0 && !game.mouth && game.state == dx::outcome::playing &&
                (game.visuals - game.excitement) * .016f >= menuart::animations[menuart::costumes[menu.skins[2] - 1][1]].duration) {
                game.excitement = game.visuals;
                audio::speak(menu.skins[2], audio::voice::excited);
            }
        }
        if (greeting && game.ticks * .016f >= 1.3f) {
            if (!game.mouth && game.state == dx::outcome::playing && menu.skins[2] > 0) {
                game.greeting = game.visuals;
                audio::speak(menu.skins[2], audio::voice::greeting);
            }
            greeting = false;
        }
        if (game.mouth && !shownmouth) {
            audio::speak(menu.skins[2], audio::voice::open);
            shownmouth = true;
        }
        if (!game.mouth && shownmouth) {
            if (game.state == dx::outcome::playing) audio::speak(menu.skins[2], audio::voice::close);
            shownmouth = false;
        }
        if (game.state == dx::outcome::won && !shownresult) {
            audio::speak(menu.skins[2], audio::voice::chewing);
            shownresult = true;
            nocashMessage("CTRD DS: level won");
        }
        if (game.state == dx::outcome::lost && !shownresult) {
            audio::speak(menu.skins[2], audio::voice::sad);
            if (game.failreason == 2) audio::effect(candybreakdata, candybreakbytes);
            if (game.failreason == 3) audio::effect(spiderwindata, spiderwinbytes);
            shownresult = true;
        }
        if (!display::busy() || (!menu.frontend() && display::active())) menu.advance(game);
        if (menu.reset && !resetbefore) { resetgame(); audio::update(menu); }
        if (menu.mode == ui::view::results && oldview != ui::view::results) audio::effect(windata, winbytes);
        if (menu.clicked || menu.mode != oldview) menu.persist();
        display::draw(game, frame, menu, menu.gameTouch, pointer);
        telemetry.upperfault=upper::fault(); telemetry.upperframes=upper::updates(); telemetry.upperreads=upper::reads();
        telemetry.popup=menu.popup; telemetry.popupage=menu.popupage;
        const unsigned micros = timerTicks2usec(cpuEndTiming());
        if (micros > peak) peak = micros;
        ++total;
        const int clocklock=enterCriticalSection();
        const unsigned completedblank=vblanks;
        telemetry.frames = total;
        telemetry.late = completedblank-total;
        telemetry.vblanks = completedblank;
        leaveCriticalSection(clocklock);
        telemetry.ticks = game.ticks;
        telemetry.state = static_cast<unsigned>(game.state);
        telemetry.stars = game.count;
        telemetry.micros = micros;
        telemetry.peak = peak;
        telemetry.x = game.candy().pos.x;
        telemetry.y = game.candy().pos.y;
        telemetry.paused = menu.mode != ui::view::playing;
        telemetry.door = menu.door;
        telemetry.doorframe = menu.doorframe;
        telemetry.menuage = menu.age;
        telemetry.improved = menu.improved;
        telemetry.level = menu.levelid(); telemetry.visuals = game.visuals; telemetry.bubble = game.bubble + 1;
        telemetry.pumps = game.pumpevents; telemetry.ropes = game.ropeevents; telemetry.failure = game.failreason;
        telemetry.intro = game.introduction; telemetry.cameray = std::lround(game.cameray); telemetry.hooks = game.definition.hookcount;
        telemetry.split = game.split; telemetry.merges = game.mergeevents; telemetry.teleports = game.teleportevents;
        telemetry.bounces = game.bounceevents; telemetry.rail = game.draghook + 1;
        telemetry.flash = menu.flash; telemetry.flashframe = menu.flashframe;
        telemetry.voices = audio::voices(); telemetry.voice = audio::lastvoice();
        telemetry.repacks = frontend::cacherepacks(); telemetry.renderfault = frontend::cachefault();
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
        telemetry.gravity = game.inverted; telemetry.gravityevents = game.gravityevents;
        telemetry.wheel = game.dragwheel + 1; telemetry.wheelevents = game.wheelevents;
        telemetry.wheelparts = telemetry.wheellength = 0;
        for (int i = 0; i < game.definition.hookcount; ++i) if (game.definition.hooks[i].wheel) {
            telemetry.wheelparts = game.ropes[i].count; telemetry.wheellength = game.ropelength(i); break;
        }
        telemetry.disc = game.dragdisc + 1;
        telemetry.discangle = 360000 + static_cast<int>(game.definition.discs[0].angle * 100);
        telemetry.discevents = game.discevents; telemetry.ghostevents = game.ghostevents;
        telemetry.ghostforms = telemetry.ghostapps = 0;
        for (int i = 0; i < game.definition.ghostcount; ++i) telemetry.ghostforms |= game.ghosts[i].form << (i*4);
        for (const auto& app : game.apparitions) if (app.form) ++telemetry.ghostapps;
        telemetry.bodypool = game.bodycount;
        telemetry.steamevents = game.steamevents; telemetry.steamstates = 0;
        for (int i=0;i<game.definition.tubecount;++i) telemetry.steamstates |= game.tubes[i].state << (i*2);
        telemetry.captures = game.captures; telemetry.releases = game.releases;
        telemetry.occupied = game.inlantern; telemetry.shared = game.sharedlantern;
        telemetry.lanternx = game.lanterns[0].position.x; telemetry.lanterny = game.lanterns[0].position.y;
        telemetry.mouse = game.activemouse+1; telemetry.mousecaptures = game.mousecaptures; telemetry.mousereleases = game.mousereleases;
        telemetry.mousehandoffs = game.mousehandoffs; telemetry.mousecarry = game.activemouse >= 0 && game.mice[game.activemouse].carry;
        telemetry.bulb = game.definition.bulbcount && game.available(3); telemetry.bulbx = game.bodies[3].pos.x; telemetry.bulby = game.bodies[3].pos.y;
        telemetry.awake = game.awake; telemetry.lit = game.starlit[0] | (game.starlit[1]<<1) | (game.starlit[2]<<2);
        telemetry.mouth = game.mouth; telemetry.mouthtick = game.mouthtick; telemetry.nightstart = game.nightstart;
        telemetry.belt = game.heldbelt+1; telemetry.beltwraps = game.beltwraps; telemetry.belthandoffs = game.belthandoffs;
        telemetry.beltoffset = game.belts[0].offset*100; telemetry.beltitems = 0;
        for (int i=0;i<game.beltitemsused;++i) if (game.beltitems[i].belt>=0) ++telemetry.beltitems;
        telemetry.spikeevents = game.spikeevents; telemetry.spikebutton = game.dragspike + 1;
        telemetry.beex = telemetry.beey = 0;
        telemetry.spiderfalls = game.spiderfalls; telemetry.spiderclimbers = 0;
        telemetry.fadephase = display::fadephase();
        for (int i = 0; i < game.definition.hookcount; ++i) {
            if (game.definition.hooks[i].route >= 0 && !telemetry.beex) {
                telemetry.beex = static_cast<int>(game.anchors[i].x); telemetry.beey = static_cast<int>(game.anchors[i].y);
            }
            if (game.definition.hooks[i].spider && game.ropes[i].count && !game.ropes[i].spiderstate && !game.ropes[i].cut)
                telemetry.spiderclimbers = telemetry.spiderclimbers + 1;
        }
        DS_PROFILE_DO(profiling::finish(total));
    }
}
