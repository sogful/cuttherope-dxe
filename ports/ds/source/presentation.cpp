#include "presentation.hpp"
#include "assets.hpp"
#include "frontend.hpp"
#include "profiling.hpp"
#include "logo.hpp"
#include <nds.h>
#include <gl2d.h>
#include <algorithm>
#include <cstdio>

namespace display {
static glImage sprites[art::spritecount];
static glImage background;
static int polygon = 0;
static bool gamecached = false;
static int gamebox = -1;
static int backgroundtop = -1, backgroundsections = 0;
static float cameray = 0;
static constexpr float scale = 192.0f / 1440;
static void transferwindow() {}
static int backgroundoffset(float position) { return static_cast<int>(std::round(position * scale)) / 64 * 64; }

static dx::point screen(dx::point position) { return {128 + (position.x - 1280) * scale, (position.y - cameray) * scale}; }
dx::point world(int x, int y) { return {1280 + (x - 128) / scale, y / scale + cameray}; }

static void image(int id, dx::point point, bool absolute = false, int alpha = 31) {
    const art::sprite& definition = art::sprites[id];
    const dx::point origin = absolute ? point : screen(point);
    glColor(RGB15(31, 31, 31));
    polygon = polygon % 48 + 1;
    glPolyFmt(POLY_ALPHA(alpha) | POLY_CULL_NONE | POLY_ID(polygon));
    glSprite(static_cast<int>(std::round(origin.x)) + definition.ox,
             static_cast<int>(std::round(origin.y)) + definition.oy, GL_FLIP_NONE, &sprites[id]);
}


static void strand(const dx::simulation& game, int index, int first, int count, int skin) {
    DS_SCOPE(ropes);
    dx::point points[125];
    int size = 0;
    game.samples(index, first, count, points, size);
    DS_PROFILE_DO(if (size > 0) profiling::data[profiling::segments] += (size - 1) * 2);
    const dx::rope& rope = game.ropes[index];
    const int alpha = rope.cut ? std::max(1, std::min(31, static_cast<int>(rope.remaining / 1.95f * 31))) : 31;
    glPolyFmt(POLY_ALPHA(alpha) | POLY_CULL_NONE | POLY_ID(49));
    static constexpr float colors[9][2][3] = {
        {{.475f,.305f,.185f},{.67555556f,.44f,.27555556f}}, {{.624f,.294f,.114f},{1,.627f,.463f}},
        {{.404f,.612f,.635f},{.773f,.898f,.902f}}, {{.757f,.533f,0},{.98f,.843f,.2f}},
        {{.980f,.243f,.243f},{.282f,.525f,.153f}}, {{.176f,.318f,.659f},{1,1,1}},
        {{.631f,.957f,1},{.996f,.631f,.953f}}, {{1,.329f,.318f},{1,.992f,.941f}},
        {{1,.831f,.404f},{.251f,.239f,.278f}}
    };
    u16 palette[2];
    for (int i = 0; i < 2; ++i) {
        const float* rgb = colors[skin][i];
        palette[i] = rope.pending >= 0 ? RGB15(31, 31, 31) : RGB15(std::lround(rgb[0] * 31), std::lround(rgb[1] * 31), std::lround(rgb[2] * 31));
    }
    int previousx = 0, previousy = 0, previouswide = 0;
    for (int i = 0; i < size; ++i) {
        const auto pixel = screen(points[i]);
        const int x = static_cast<int>(pixel.x), y = static_cast<int>(pixel.y);
        const int wide = static_cast<int>(screen(points[i] + dx::point{4, 0}).x);
        if (i) {
            const u16 color = palette[(i / 3) % 2 == 0];
            glLine(previousx, previousy, x, y, color);
            glLine(previouswide, previousy, wide, y, color);
        }
        previousx = x; previousy = y; previouswide = wide;
    }
}

void initialize() {
    irqSet(IRQ_VCOUNT, transferwindow);
    SetYtrigger(148);
    irqEnable(IRQ_VCOUNT);
    videoSetMode(MODE_0_3D);
    videoSetModeSub(MODE_5_2D);
    lcdMainOnBottom();
    vramSetBankA(VRAM_A_TEXTURE_SLOT0);
    vramSetBankB(VRAM_B_TEXTURE_SLOT1);
    vramSetBankC(VRAM_C_LCD);
    vramSetBankH(VRAM_H_SUB_BG);
    vramSetBankI(VRAM_I_SUB_BG_0x06208000);
    const int upper = bgInitSub(3, BgType_Bmp8, BgSize_B8_256x256, 0, 0);
    dmaCopy(logodata, bgGetGfxPtr(upper), 256 * 192);
    dmaCopy(logopalettedata, BG_PALETTE_SUB, 512);
    // libnds allocates using LCD-bank addresses; preserve D's physical slot.
    vramSetBankD(VRAM_D_TEXTURE_SLOT3);
    vramSetBankE(VRAM_E_TEX_PALETTE);
    glScreen2D();
    glClearColor(8, 5, 3, 31);
    glEnable(GL_ANTIALIAS);
    setBrightness(1, -16);
    frontend::initialize();
}

static void loadgame(const ui::controller& menu, const dx::simulation& game) {
    frontend::reset();
    unsigned occupied = 131072;
    int textures[art::texturecount];
    glGenTextures(art::texturecount, textures);
    for (int index = 0; index < art::texturecount; ++index) {
        const art::texture& source = art::textures[index];
        // Seats/Om Nom/HUD are pageable now. Only these three atlases are
        // actually referenced by the immediate gameplay renderer.
        if (index != art::sprites[art::star0].page && index != art::sprites[art::hookback].page &&
            (menu.skins[0] > 0 || index != art::sprites[art::candy0].page)) continue;
        occupied += source.width * source.height;
        glBindTexture(0, textures[index]);
        int width = 0, height = 0;
        for (int size = source.width; size > 8; size >>= 1) ++width;
        for (int size = source.height; size > 8; size >>= 1) ++height;
        if (!glTexImage2D(0, 0, GL_RGB32_A3, width, height, 0, TEXGEN_OFF, nullptr)) {
            nocashMessage("CTRD DS: sprite texture allocation failed");
            while (true) swiWaitForVBlank();
        }
        frontend::stage(textures[index], source.pixels, source.width * source.height, source.palette, 32);
    }
    for (int index = 0; index < art::spritecount; ++index) {
        const art::sprite& source = art::sprites[index];
        sprites[index] = {source.w, source.h, source.x, source.y, textures[source.page]};
    }
    backgroundsections = std::clamp(static_cast<int>(std::ceil(game.definition.height / 1440)), 1, 3);
    backgroundtop = backgroundoffset(game.cameray);
    background = {256, 256, 0, 0, frontend::background(menu.pack, backgroundsections, backgroundtop)};
    frontend::reserve(occupied);
    gamecached = true;
    gamebox = menu.pack;
}

static void scene(const dx::simulation& game, int frame, const ui::controller& menu, bool, dx::point) {
    DS_SCOPE(scene);
    if (menu.frontend()) { frontend::draw(menu); return; }
    if (menu.mode == ui::view::results && menu.age >= 32) {
        frontend::drawresult(menu, game);
        return;
    }
    if (!gamecached || gamebox != menu.pack) loadgame(menu, game);
    cameray = game.cameray;
    const int sectioncount = std::clamp(static_cast<int>(std::ceil(game.definition.height / 1440)), 1, 3);
    const int top = backgroundoffset(cameray);
    if (top != backgroundtop || sectioncount != backgroundsections) {
        frontend::background(menu.pack, sectioncount, top, background.textureID);
        backgroundtop = top; backgroundsections = sectioncount;
    }
    frontend::preparegame(menu, game, frame);
    frontend::prepareoverlay(menu, game);
    glBegin2D();
    polygon = 0;
    glColor(RGB15(31, 31, 31));
    const int backgroundy = backgroundtop - static_cast<int>(std::round(cameray * scale));
    glSprite(0, backgroundy, GL_FLIP_NONE, &background);
    frontend::render(false, true);
    for (int index = 0; index < game.definition.hookcount; ++index) if (!game.definition.hooks[index].rail && !game.ghostapp(4,index)) image(art::hookback, game.anchors[index]);
    for (int index = 0; index < game.definition.hookcount; ++index) {
        const dx::rope& item = game.ropes[index];
        const auto& hook = game.definition.hooks[index];
        if (item.count && !item.cut) strand(game, index, 0, item.count, menu.skins[1]);
        else if (item.remaining > 0) {
            strand(game, index, 0, item.split, menu.skins[1]);
            if (!item.hidetail) strand(game, index, item.split, item.count - item.split, menu.skins[1]);
        }
        if (!hook.rail && !game.ghostapp(4,index)) image(art::hookfront, game.anchors[index]);
    }
    frontend::render(false, false, 1);
    for (int index = 0; index < 3; ++index) {
        if (game.stars[index] || game.expired[index]) continue;
        if (!game.definition.night) image(art::star0, game.starpositions[index], false, 12);
        const int alpha = game.definition.night ? std::lround(game.lightalpha[index]*31) : 31;
        if (alpha) image(art::star1 + (frame / 3 + index * 5) % 18, game.starpositions[index],false,alpha);
    }
    frontend::render(false, false, 2);
    if (!game.split && !game.hidden() && menu.skins[0] == 0 && game.state != dx::outcome::won && game.failreason != 2 && game.failreason != 3) {
        image(art::candy0, game.candy().pos);
        image(art::candy1, game.candy().pos);
        image(art::candy2, game.candy().pos);
    }
    frontend::render();
    frontend::ribbon();
    frontend::render(true);
    if (menu.white() > 0) {
        glPolyFmt(POLY_ALPHA(std::max(1, static_cast<int>(std::lround(menu.white() * 31)))) | POLY_CULL_NONE | POLY_ID(63));
        glBoxFilled(0, 0, 255, 191, RGB15(31, 31, 31));
    }
    glEnd2D();
    frontend::present();
}

static int loaded = -1, transition = 0;
static ui::controller previous;
bool busy() { return loaded < 0 || transition != 0; }
bool active() { return loaded >= 0 && (transition == 0 || transition >= 14); }
int fadephase() { return transition; }
void draw(const dx::simulation& game, int frame, const ui::controller& menu, bool touching, dx::point finger) {
    const int desired = menu.frontend() ? static_cast<int>(menu.mode) * 12 + menu.locale : menu.pack;
    if (loaded < 0) {
        scene(game, frame, menu, false, finger);
        swiWaitForVBlank();
        swiWaitForVBlank();
        loaded = desired;
        previous = menu;
        setBrightness(1, 0);
        return;
    }
    if (loaded != desired && !transition) transition = 1;
    if (transition > 0 && transition <= 12) {
        setBrightness(1, -(transition * 16 / 12));
        scene(game, frame, previous, false, finger);
        ++transition;
        return;
    }
    if (transition == 13) {
        setBrightness(1, -16);
        if (menu.frontend()) { if (!previous.frontend()) { frontend::reset(); gamecached = false; } }
        else loadgame(menu, game);
        loaded = desired;
    }
    if (transition >= 13) {
        setBrightness(1, -std::clamp((27 - transition) * 16 / 12, 0, 16));
        if (++transition > 27) transition = 0;
    }
    scene(game, frame, menu, touching, finger);
    previous = menu;
}

}
