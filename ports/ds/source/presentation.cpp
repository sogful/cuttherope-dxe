#include "presentation.hpp"
#include "assets.hpp"
#include <nds.h>
#include <gl2d.h>
#include <algorithm>

namespace display {
static glImage sprites[art::spritecount];
static glImage background;
static constexpr float scale = 192.0f / 1440;

static dx::point screen(dx::point position) { return {128 + (position.x - 1280) * scale, position.y * scale}; }
dx::point world(int x, int y) { return {1280 + (x - 128) / scale, y / scale}; }
bool retry(int x, int y) { return x >= 205 && y < 24; }

static void image(int id, dx::point point, bool absolute = false, int alpha = 31) {
    const art::sprite& definition = art::sprites[id];
    const dx::point origin = absolute ? point : screen(point);
    glColor(RGB15(31, 31, 31));
    glPolyFmt(POLY_ALPHA(alpha) | POLY_CULL_NONE | POLY_ID(1));
    glSprite(static_cast<int>(std::round(origin.x)) + definition.ox,
             static_cast<int>(std::round(origin.y)) + definition.oy, GL_FLIP_NONE, &sprites[id]);
}

static void text(int x, int y, const char* value) {
    for (; *value; ++value) {
        if (*value < 32 || *value > 126) continue;
        const int id = art::glyph32 + *value - 32;
        image(id, {static_cast<float>(x), static_cast<float>(y)}, true);
        x += art::sprites[id].advance;
    }
}

static void line(dx::point a, dx::point b, u16 color) {
    a = screen(a);
    b = screen(b);
    glLine(static_cast<int>(a.x), static_cast<int>(a.y), static_cast<int>(b.x), static_cast<int>(b.y), color);
}

static void strand(const dx::simulation& game, int index, int first, int count) {
    dx::point points[125];
    int size = 0;
    game.samples(index, first, count, points, size);
    const dx::rope& rope = game.ropes[index];
    const int alpha = rope.cut ? std::max(1, std::min(31, static_cast<int>(rope.remaining / 1.95f * 31))) : 31;
    glPolyFmt(POLY_ALPHA(alpha) | POLY_CULL_NONE | POLY_ID(2));
    for (int segment = 1; segment < size; ++segment) {
        const bool bright = (segment / 3) % 2 == 0;
        const u16 color = rope.pending >= 0 ? RGB15(31, 31, 31) : bright ? RGB15(21, 14, 8) : RGB15(15, 9, 5);
        line(points[segment - 1], points[segment], color);
        line(points[segment - 1] + dx::point{4, 0}, points[segment] + dx::point{4, 0}, color);
    }
}

void initialize() {
    videoSetMode(MODE_0_3D);
    videoSetModeSub(MODE_5_2D);
    lcdMainOnBottom();
    vramSetBankA(VRAM_A_TEXTURE_SLOT0);
    vramSetBankB(VRAM_B_TEXTURE_SLOT1);
    vramSetBankC(VRAM_C_SUB_BG);
    const int upper = bgInitSub(3, BgType_Bmp16, BgSize_B16_256x256, 0, 0);
    dmaCopy(logodata, bgGetGfxPtr(upper), 256 * 256 * 2);
    // libnds allocates using LCD-bank addresses; preserve D's physical slot.
    vramSetBankD(VRAM_D_TEXTURE_SLOT3);
    vramSetBankE(VRAM_E_TEX_PALETTE);
    glScreen2D();
    glClearColor(8, 5, 3, 31);
    glEnable(GL_ANTIALIAS);
    int textures[art::texturecount];
    glGenTextures(art::texturecount, textures);
    for (int index = 0; index < art::texturecount; ++index) {
        const art::texture& source = art::textures[index];
        glBindTexture(0, textures[index]);
        int width = 0, height = 0;
        for (int size = source.width; size > 8; size >>= 1) ++width;
        for (int size = source.height; size > 8; size >>= 1) ++height;
        if (!glTexImage2D(0, 0, GL_RGB32_A3, width, height, 0, TEXGEN_OFF, source.pixels)) {
            nocashMessage("CTRD DS: sprite texture allocation failed");
            while (true) swiWaitForVBlank();
        }
        glColorTableEXT(0, 0, 32, 0, 0, reinterpret_cast<const u16*>(source.palette));
    }
    for (int index = 0; index < art::spritecount; ++index) {
        const art::sprite& source = art::sprites[index];
        sprites[index] = {source.w, source.h, source.x, source.y, textures[source.page]};
    }
    int texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(0, texture);
    if (!glTexImage2D(0, 0, GL_RGBA, TEXTURE_SIZE_256, TEXTURE_SIZE_256, 0, TEXGEN_OFF, backgrounddata)) {
        nocashMessage("CTRD DS: background texture allocation failed");
        while (true) swiWaitForVBlank();
    }
    background = {256, 192, 0, 0, texture};
}

void draw(const dx::simulation& game, int frame, bool paused, bool touching, dx::point finger) {
    glBegin2D();
    glColor(RGB15(31, 31, 31));
    glSprite(0, 0, GL_FLIP_NONE, &background);
    for (int index = 0; index < game.definition.hookcount; ++index) image(art::hookback, game.definition.hooks[index].anchor);
    image(art::support, game.definition.target);
    for (int index = 0; index < game.definition.hookcount; ++index) {
        const dx::rope& item = game.ropes[index];
        if (!item.cut) strand(game, index, 0, item.count);
        else if (item.remaining > 0) {
            strand(game, index, 0, item.split);
            strand(game, index, item.split, item.count - item.split);
        }
        image(art::hookfront, game.definition.hooks[index].anchor);
    }
    for (int index = 0; index < 3; ++index) {
        if (game.stars[index]) continue;
        image(art::star0, game.definition.stars[index], false, 12);
        image(art::star1 + (frame / 3 + index * 5) % 18, game.definition.stars[index]);
    }
    int target = art::omnom0 + frame / 3 % 19;
    if (game.mouth) target = art::omnom19 + std::min(8, (game.ticks - game.mouthtick) / 3);
    if (game.state == dx::outcome::won) {
        const int elapsed = frame - game.resulttick;
        target = elapsed < 12 ? art::omnom28 + elapsed / 3 : art::omnom32 + (elapsed - 12) / 3 % 9;
    }
    if (game.state == dx::outcome::lost) target = art::sad0 + std::min(12, (frame - game.resulttick) / 3);
    image(target, game.definition.target);
    if (game.state != dx::outcome::won) {
        image(art::candy0, game.candy().pos);
        image(art::candy1, game.candy().pos);
        image(art::candy2, game.candy().pos);
    }
    if (touching) {
        const dx::point position = screen(finger);
        glPolyFmt(POLY_ALPHA(20) | POLY_CULL_NONE | POLY_ID(3));
        glBoxFilled(position.x - 1, position.y - 1, position.x + 1, position.y + 1, RGB15(31, 30, 26));
    }
    text(7, 4, "1-1");
    text(208, 4, "RETRY");
    if (paused) text(103, 86, "PAUSED");
    else if (game.state == dx::outcome::won) {
        text(90, 82, "WELL DONE!");
        text(84, 100, "Touch to retry");
    } else if (game.state == dx::outcome::lost) {
        text(96, 82, "TRY AGAIN");
        text(84, 100, "Touch to retry");
    } else if (!game.ropes[0].cut) text(156, 35, "Cut the rope!");
    glEnd2D();
    glFlush(0);
}

}
