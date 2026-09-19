#include "frontend.hpp"
#include "menuassets.hpp"
#include "packed.hpp"
#include "trace.hpp"
#include "result.hpp"
#include <nds.h>
#include <gl2d.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <filesystem.h>

namespace frontend {
static int textures[menuart::pagecount]{};
static unsigned touched[menuart::pagecount]{}, frame = 0, occupied = 0;
static unsigned reserved = 0;
alignas(4) static unsigned char unpacked[131072];
alignas(4) static unsigned char compressed[147456];
static FILE* catalog;
void initialize() {
    if (nitroFSInit(nullptr)) catalog = std::fopen("nitro:/menu.bin", "rb");
    if (!catalog) {
        nocashMessage("CTRD DS: ROM filesystem unavailable");
        while (true) swiWaitForVBlank();
    }
}
void reserve(unsigned bytes) { reserved = bytes; }
struct clip { int left = 0, top = 0, right = 256, bottom = 192; };
struct command {
    int id, x, y, alpha = 31, flip = GL_FLIP_NONE, angle = 0;
    float scale = 1;
    clip bounds{};
    u16 color = RGB15(31, 31, 31);
    float vertical = 1;
};
static std::array<command, 384> commands;
static int count = 0;
static int overlaystart = -1;
static constexpr float pixels = 192.0f / 1440;

static int x(float value, float fit = menuart::fit) { return std::lround(128 + (value - 1280) * pixels * fit); }
static int y(float value, float fit = menuart::fit) { return std::lround(96 + (value - 720) * pixels * fit); }

static void add(int id, int px, int py, clip bounds = {}, int flip = GL_FLIP_NONE, float scale = 1, int angle = 0, int alpha = 31, u16 color = RGB15(31, 31, 31)) {
    if (id < 0 || count >= static_cast<int>(commands.size()) || scale <= .001f || alpha <= 0) return;
    commands[count++] = {id, px, py, alpha, flip, angle, scale, bounds, color, scale};
}

static void label(const ui::controller& menu, int id, int px, int py, clip bounds = {}) {
    add(menuart::labels[menu.locale][id], px, py, bounds);
}

static unsigned bytes(int page) {
    const auto& item = menuart::pages[page];
    return item.width * item.height * (item.direct ? 2 : 1);
}

void reset() {
    glResetTextures();
    std::fill(std::begin(textures), std::end(textures), 0);
    std::fill(std::begin(touched), std::end(touched), 0);
    occupied = 0;
    reserved = 0;
}

unsigned texturebytes() { return occupied + reserved; }

static void upload(bool repacked = false) {
    ++frame;
    bool needed[menuart::pagecount]{};
    bool missing = false;
    unsigned required = 0;
    for (int i = 0; i < count; ++i) {
        if (commands[i].id < 0) continue;
        const int page = menuart::sprites[commands[i].id].page;
        if (!needed[page]) required += bytes(page);
        needed[page] = true;
        touched[page] = frame;
        missing = missing || !textures[page];
    }
    if (required + reserved > 384 * 1024) {
        nocashMessage("CTRD DS: menu working set exceeds texture VRAM");
        while (true) swiWaitForVBlank();
    }
    if (!missing) return;
    auto evict = [&]() {
        int oldest = -1;
        for (int candidate = 0; candidate < menuart::pagecount; ++candidate) {
            if (textures[candidate] && !needed[candidate] && (oldest < 0 || touched[candidate] < touched[oldest])) oldest = candidate;
        }
        if (oldest < 0) return false;
        glDeleteTextures(1, &textures[oldest]);
        textures[oldest] = 0;
        occupied -= bytes(oldest);
        return true;
    };
    std::array<int, menuart::pagecount> order;
    for (int index = 0; index < menuart::pagecount; ++index) order[index] = index;
    std::sort(order.begin(), order.end(), [](int a, int b) { return bytes(a) > bytes(b); });
    for (int index : order) {
        if (!needed[index] || textures[index]) continue;
        while (occupied + reserved + bytes(index) > 384 * 1024) {
            if (!evict()) break;
        }
        const auto& page = menuart::pages[index];
        if (page.packed > sizeof(compressed) || std::fseek(catalog, page.offset, SEEK_SET) ||
            std::fread(compressed, 1, page.packed, catalog) != page.packed ||
            !packed::unpack(compressed, unpacked, sizeof(unpacked))) {
            nocashMessage("CTRD DS: invalid packed menu texture");
            while (true) swiWaitForVBlank();
        }
        glGenTextures(1, &textures[index]);
        glBindTexture(0, textures[index]);
        int width = 0, height = 0;
        for (int size = page.width; size > 8; size >>= 1) ++width;
        for (int size = page.height; size > 8; size >>= 1) ++height;
        while (!glTexImage2D(0, 0, page.direct ? GL_RGBA : page.alphabits == 5 ? GL_RGB8_A5 : GL_RGB32_A3, width, height, 0, TEXGEN_OFF, unpacked)) {
            if (!evict()) {
                // A/B/D are three separate 128 KiB banks. Enough free bytes
                // need not imply a contiguous allocation after locale changes.
                if (!repacked && !reserved) { reset(); upload(true); return; }
                nocashMessage("CTRD DS: menu texture allocation failed");
                while (true) swiWaitForVBlank();
            }
            glBindTexture(0, textures[index]);
        }
        if (!page.direct) glColorTableEXT(0, 0, 1 << (8 - page.alphabits), 0, 0, reinterpret_cast<const u16*>(page.palette));
        occupied += bytes(index);
    }
}

static void packs(const ui::controller& menu) {
    const clip strip{38, 0, 218, 192};
    add(menuart::pack4, 45, 96);
    add(menuart::pack4, 211, 96, {}, GL_FLIP_H | GL_FLIP_V);
    const float step = 640 * menuart::fit * pixels;
    for (int i = 0; i < menuart::boxcount; ++i) {
        const int center = std::lround(128 + (i - menu.packposition) * step);
        if (center + 45 < strip.left || center - 45 >= strip.right) continue;
        if (i == 0 || menu.unlockall()) {
            static constexpr unsigned char colors[17][3] = {{70,37,0},{39,52,0},{44,45,54},{31,42,84},{69,31,50},{75,33,0},
                {84,22,0},{0,51,78},{98,0,0},{66,40,0},{0,47,90},{0,58,0},{63,42,0},{89,12,0},{56,45,0},{37,32,104},{55,38,62}};
            const clip hole{std::max(strip.left, center - 16), 96, std::min(strip.right, center + 16), 122};
            commands[count++] = {-1, 0, 0, 31, GL_FLIP_NONE, 0, 1, hole, static_cast<u16>(RGB15(colors[i][0] >> 3, colors[i][1] >> 3, colors[i][2] >> 3))};
            add(menuart::pack1, 128, 96, hole);
        }
        const int first = count;
        add(menuart::boxes[i], center, 96, strip);
        label(menu, menuart::boxname0 + i, center, 76, strip);
        if (i > 0 && !menu.unlockall()) {
            add(menuart::pack2, center, 96, strip);
            label(menu, menuart::required0 + i, center - 4, 111, strip);
            add(menuart::pack3, center + 12, 113, strip);
            label(menu, menuart::hint0 + i, center, 143, strip);
        }
        if (i == menuart::boxcount - 1) {
            add(menuart::pack9, center + 18, 115, strip);
            add(menuart::labels[menu.locale][menuart::HARDEST_LABEL], center + 18, 115, strip, GL_FLIP_NONE, 1, -1456);
        }
        const float time = menu.settled * .016f;
        if (i == menu.pack && time < .6f) {
            const float start = time < .15f ? 1 : time < .35f ? .95f : 1.05f;
            const float end = time < .15f ? .95f : time < .35f ? 1.05f : 1;
            const float duration = time < .15f ? .15f : time < .35f ? .2f : .25f;
            const float local = (time - (time < .15f ? 0 : time < .35f ? .15f : .35f)) / duration;
            const float sx = start + (end - start) * (1 - (1 - local) * (1 - local));
            const float sy = 2 - sx;
            for (int part = first; part < count; ++part) {
                command& item = commands[part];
                item.x = std::lround(center + (item.x - center) * sx);
                item.y = std::lround(96 + (item.y - 96) * sy);
                item.scale *= sx;
                item.vertical *= sy;
            }
        }
    }
    add(menuart::pack5, 38, 96);
    add(menuart::pack5, 218, 96, {}, GL_FLIP_H | GL_FLIP_V);
    const int text = menuart::labels[menu.locale][menuart::total0 + menu.beststars];
    const auto& definition = menuart::sprites[text];
    add(text, 243 - definition.w / 2, 10);
    add(menuart::pack3, 248, 9);
}

static void options(const ui::controller& menu) {
    add(menuart::option5, x(1130.5f), y(1018.5f));
    add(menuart::option6, x(1428.5f), y(1018.5f));
    label(menu, menuart::DRAG_TO_CUT, x(1130.5f), y(1212));
    label(menu, menuart::CLICK_TO_CUT, x(1428.5f), y(1215));
    add(menuart::option10, x(1120.5f), y(1303.5f));
    add(menuart::option7, x(1130.5f), y(1289.5f));
    add(menuart::option9, x(1418.5f), y(1306.5f));
    if (menu.clickcut) add(menuart::option8, x(1428.5f), y(1293));
    label(menu, menuart::unlockall, 125, 185);
    add(menu.unlockall() ? menuart::option8 : menuart::option9, 164, 185, {}, GL_FLIP_NONE, .65f);
}

static int animation(int index, float seconds, bool preview = false) {
    for (int limit = 0; limit < 64; ++limit) {
        const auto& item = menuart::animations[index];
        if (seconds < item.duration || item.followup < 0) return (preview ? item.previewframes : item.frames)[std::min(item.count - 1, static_cast<int>(seconds * item.fps))];
        if (item.followup == index) seconds = std::fmod(seconds, item.duration);
        else { seconds -= item.duration; index = item.followup; }
    }
    return menuart::animations[index].frames[0];
}

static float unit(float value) { return std::clamp(value, 0.0f, 1.0f); }
static void gamelabel(const ui::controller& menu, int key, int px, int py, float alpha = 1) {
    add(menuart::gamelabels[menu.locale][key], px, py, {}, GL_FLIP_NONE, 1, 0, std::lround(unit(alpha) * 31));
}
static void digits(const ui::controller& menu, const char* value, int px, int py, bool score, float alpha = 1) {
    const auto* font = score ? menuart::scoredigits : menuart::digits[menu.locale];
    float width = 0;
    for (const char* p = value; *p; ++p) width += font[*p == ':' ? 10 : *p - '0'].advance;
    float left = px - width / 2;
    for (; *value; ++value) {
        const auto& glyph = font[*value == ':' ? 10 : *value - '0'];
        add(glyph.sprite, std::lround(left + glyph.advance / 2), py, {}, GL_FLIP_NONE, 1, 0, std::lround(unit(alpha) * 31));
        left += glyph.advance;
    }
}
static void rect(clip bounds, u16 color, int alpha) {
    if (count < static_cast<int>(commands.size()) && alpha > 0) commands[count++] = {-1, 0, 0, alpha, GL_FLIP_NONE, 0, 1, bounds, color};
}
static void piece(int id, float left, float top, float width, float height, int flip = GL_FLIP_NONE, float brightness = 1) {
    if (width < .1f || height < .1f) return;
    const auto& source = menuart::sprites[id];
    const float sx = width / source.w, sy = height / source.h;
    const int shade = std::lround(unit(brightness) * 31);
    add(id, std::lround(left - source.ox * sx), std::lround(top - source.oy * sy), {}, flip, sx, 0, 31, RGB15(shade, shade, shade));
    commands[count - 1].vertical = sy;
}
static void doors(float progress, bool opening, bool loading) {
    const float t = unit(progress), closed = opening ? 1 - t : t;
    const float base = -320 * pixels, width = 1293 * pixels, height = 192 * (1.1f - .1f * closed);
    const float side = (1 - closed) * 72 * pixels;
    piece(menuart::doorshade, (opening ? -t : t - 1) * 891 * 4 * pixels + base, 0, 891 * 4 * pixels, 400 * 4 * pixels);
    const float leftside = opening ? (1280 - 12) * (1 - t) - 25 * t : -13 * (1 - t) + (1293 - 16) * t;
    const float rightside = opening ? (1280 + 14) * (1 - t) + 2560 * t : (2560 - 40) * (1 - t) + (1280 + 20) * t;
    piece(menuart::cover1, base + leftside * pixels, 0, side, 192 * (1 + .3f * closed));
    piece(menuart::cover1, base + rightside * pixels, 0, side, 192 * (1 + .3f * closed));
    piece(menuart::cover0, base - 13 * pixels, (192 - height) / 2, width * closed, height, GL_FLIP_NONE, 1 - .15f * closed);
    piece(menuart::cover0, base + (1280 + 1293) * pixels - width * closed, (192 - height) / 2, width * closed, height,
          GL_FLIP_H | GL_FLIP_V, .4f + .45f * closed);
    if (loading) {
        const float lx = (1293 - 50) * closed - 40 * (1 - closed), rx = (1280 + 10) * closed + (2560 + 25) * (1 - closed);
        const auto& left = menuart::sprites[menuart::loading6];
        const auto& right = menuart::sprites[menuart::loading7];
        piece(menuart::loading6, base + lx * pixels, 80 * pixels, left.w * closed, left.h * (1.3f - .3f * closed));
        piece(menuart::loading7, base + rx * pixels, 80 * pixels, right.w * closed, right.h * (1.3f - .3f * closed));
    }
}

static void results(const ui::controller& menu, bool hiding = false) {
    const float t = (hiding ? menu.resulttime + menu.doorframe : menu.age) * .016f;
    const float opacity = hiding ? 1 - unit(menu.doorframe * .016f / .5f) : unit(t / .5f);
    const auto& a = menuart::resultanchors;
    for (int i = 0; i < 3; ++i) add(i < menu.resultstars ? menuart::result13 : menuart::result14, a[i][0], a[i][1], {}, GL_FLIP_NONE, 1, 0, std::lround(opacity * 31));
    gamelabel(menu, menuart::gameLEVEL_CLEARED1 + menu.resultstars, a[3][0], a[3][1], opacity);
    add(menuart::result15, a[4][0], a[4][1], {}, GL_FLIP_NONE, 1, 0, std::lround(opacity * 31));
    const auto state = ui::resultat(t, menu.resultstars, menu.score, menu.elapsed);
    const int title = menuart::gameSTAR_BONUS + state.row, total = state.score, value = state.value;
    const float alpha = state.alpha, scorealpha = state.scorealpha;
    const bool time = state.row == 1, final = state.row == 2;
    gamelabel(menu, title, a[final ? 7 : 5][0], a[final ? 7 : 5][1], opacity * alpha);
    char buffer[24];
    if (time) std::snprintf(buffer, sizeof(buffer), "%d:%02d", value / 60, value % 60);
    else std::snprintf(buffer, sizeof(buffer), "%d", value);
    if (!final) digits(menu, buffer, a[6][0], a[6][1], false, opacity * alpha);
    std::snprintf(buffer, sizeof(buffer), "%d", total);
    digits(menu, buffer, a[8][0], a[8][1], true, opacity * scorealpha);
    if (menu.improved && t > 3.8f) {
        const float f = unit((t - 3.8f) / .5f), eased = f * f;
        add(menuart::stamp17 + menuart::stamps[menu.locale] - 17, a[12][0], a[12][1], {}, GL_FLIP_NONE, 3 - 2 * eased, 0, std::lround(31 * eased * opacity));
    }
    for (int i = 0; i < 3; ++i) {
        const int slot = i == 0 ? 11 : i == 1 ? 10 : 9;
        const float alpha = opacity * (i == 1 ? .35f : 1);
        add(menu.pressed == i && !hiding ? menuart::shortdown : menuart::shortup, a[slot][0], a[slot][1], {}, GL_FLIP_NONE, 1, 0, std::lround(alpha * 31));
        gamelabel(menu, menuart::gameREPLAY + i, a[slot][0], a[slot][1], alpha);
    }
    if (!hiding && menu.resultstars == 3 && t > .5f && t < 5.5f) {
        unsigned seed = 0x43545244;
        auto random = [&seed](float low, float high) { seed = seed * 1664525 + 1013904223; return low + (high - low) * ((seed >> 8) / 16777215.0f); };
        const float age = t - .5f;
        for (int i = 0; i < 70; ++i) {
            const int variant = random(0, 2.999f), offset = random(0, 7.999f);
            const float px = random(-200, 2560), py = random(-80, 200), life = random(2, 5), fall = random(300, 800), first = random(-360, 360), last = random(-360, 360);
            const float ratio = age / life;
            if (ratio >= 1) continue;
            add(menuart::confetti0 + variant * 9 + (static_cast<int>(age / .05f) + offset) % 9,
                x(px + 7.5f), y(py - 61 + fall * ratio), {}, GL_FLIP_NONE, unit(age / .3f),
                static_cast<int>((first + (last - first) * ratio) * 32768 / 360), std::max(1, static_cast<int>(std::lround((1 - ratio) * 31))));
        }
    }
}

void prepareoverlay(const ui::controller& menu, const dx::simulation& game) {
    overlaystart = count;
    if ((menu.mode == ui::view::playing || menu.mode == ui::view::paused) && menu.door != 2 && !(menu.door == 1 && menu.replaypanel)) {
        for (int i = 0; i < 3; ++i) {
            const int frame = menu.starage[i] < 0 ? 0 : std::min(10, 1 + menu.starage[i] / 3);
            add(menuart::hud1 + frame, std::lround((86 * i + 43) * menuart::fit * pixels), std::lround(43.5f * menuart::fit * pixels));
        }
        const auto& p = menuart::hudpositions[menu.locale];
        add(menuart::hud0, p[2], p[3], {}, GL_FLIP_NONE, 1, 0, menu.pressed == 0 ? 31 : 19);
        add(menuart::hud0 + menuart::hudquads[menu.locale], p[0], p[1], {}, GL_FLIP_NONE, 1, 0, menu.pressed == 1 ? 31 : 19);
        const auto& name = menuart::sprites[menuart::levelnames[menu.locale]];
        const float time = game.ticks * .016f;
        const float alpha = time < 1 ? unit((time - .5f) / .5f) : time > 2 ? 1 - unit((time - 2) / .5f) : 1;
        const int inset = std::lround(40 * menuart::fit * pixels), bottom = menu.locale >= 10 ? 180 : 183;
        add(menuart::levelnames[menu.locale], inset + name.w / 2, bottom, {}, GL_FLIP_NONE, 1, 0, std::lround(alpha * 31));
        add(menuart::levelwords[menu.locale], inset + menuart::sprites[menuart::levelwords[menu.locale]].w / 2, bottom - 9, {}, GL_FLIP_NONE, 1, 0, std::lround(alpha * 31));
        if (game.state == dx::outcome::playing && time < 10.5f) {
            const int opacity = std::lround(31 * (time < .5f ? unit(time / .5f) : time > 10 ? 1 - unit((time - 10) / .5f) : 1));
            for (const auto& item : menuart::tutorials[menu.locale]) {
                if (item.sprite < 0) break;
                add(item.sprite, item.x, item.y, {}, GL_FLIP_NONE, 1, 0, opacity);
            }
        }
    }
    if (menu.mode == ui::view::paused && !menu.door) {
        rect({}, RGB15(3, 3, 3), 16);
        const auto& plate = menuart::sprites[menuart::pauseplate];
        add(menuart::pauseplate, 128, plate.h / 2);
        char score[24];
        std::snprintf(score, sizeof(score), "%d", menu.bestscore);
        float width = 0;
        for (const char* p = score; *p; ++p) width += menuart::digits[menu.locale][*p - '0'].advance;
        const float right = 256 - (menu.locale == 9 ? 76 : 20) * pixels;
        digits(menu, score, std::lround(right - width / 2), 5, false);
        const auto& best = menuart::bestlabels[menu.locale];
        add(best.sprite, std::lround(right - width - best.advance / 2), 5);
        ui::button buttons[8];
        const int size = menu.buttons(buttons);
        for (int i = 0; i < size; ++i) {
            const auto& b = buttons[i];
            if (i < 4) {
                add(menu.pressed == i ? menuart::longdown : menuart::longup, b.x, b.y, {}, GL_FLIP_NONE, 1, 0, b.enabled ? 31 : 11);
                gamelabel(menu, menuart::gameCONTINUE + i, b.x, b.y, b.enabled ? 1 : .35f);
            } else {
                add(menu.pressed == i ? menuart::option1 : menuart::option0, b.x, b.y);
                add(i == 4 ? menuart::option2 : menuart::option3, b.x, b.y);
                if (!(i == 4 ? menu.effects : menu.music)) add(menuart::option4, b.x, b.y);
            }
        }
    }
    if (menu.mode == ui::view::results) { doors(menu.age * .016f / .5f, false, false); results(menu); }
    if (menu.mode == ui::view::failure) {
        rect({}, RGB15(2, 1, 0), 24);
        add(menuart::failuretitle, 128, 32);
        add(menuart::failurehint, 128, 66);
        ui::button buttons[8];
        const int size = menu.buttons(buttons);
        for (int i = 0; i < size; ++i) {
            const auto& b = buttons[i];
            add(menu.pressed == i ? menuart::shortdown : menuart::shortup, b.x, b.y, {}, GL_FLIP_NONE, 1, 0, b.enabled ? 31 : 11);
            gamelabel(menu, menuart::gameREPLAY + i, b.x, b.y, b.enabled ? 1 : .35f);
        }
    }
    if (menu.door) doors(menu.doorframe * .016f / .5f, menu.door == 1, menu.door == 1);
    if (menu.door == 1 && menu.replaypanel) results(menu, true);
    (void)game;
    upload();
}

void drawresult(const ui::controller& menu, const dx::simulation& game) {
    count = 0;
    prepareoverlay(menu, game);
    glBegin2D();
    render(true);
    glEnd2D();
    glFlush(GL_TRANS_MANUALSORT);
}

static void skins(const ui::controller& menu) {
    const clip window{static_cast<int>(menuart::skinleft), static_cast<int>(menuart::skintop),
        static_cast<int>(256 - menuart::skinleft), static_cast<int>(menuart::skinbottom)};
    for (int i = 0; i < menuart::skincounts[menu.skintab]; ++i) {
        const int px = std::lround(menuart::skinleft + (i % 4) * menuart::skinpitch + menuart::skinwidth / 2);
        const int py = std::lround(menuart::skintop + (i / 4) * menuart::skinrow + (menuart::skinrow - 10 * pixels * menuart::fit) / 2 - menu.skinoffsets[menu.skintab]);
        if (py + 30 < window.top || py - 30 >= window.bottom) continue;
        const bool selected = menu.skins[menu.skintab] == i;
        add(menuart::skin0 + (selected ? 2 : 0) + (menu.pressedskin() == i ? 1 : 0), px, py, window);
        int preview = menuart::previews[menu.skintab][i];
        float factor = 1;
        if (menu.skintab == 2) {
            if (i == 0) { if (selected) preview = menuart::classicpreviews[menu.skinage / 3 % 19]; }
            else {
                if (selected) preview = animation(menuart::costumes[i - 1][5], menu.skinage * .016f, true);
            }
        }
        add(preview, px, py - (menu.skintab == 2 ? 1 : 3), window, GL_FLIP_NONE, factor);
    }
}

void preparegame(const ui::controller& menu, const dx::simulation& game, int elapsed) {
    count = 0;
    overlaystart = -1;
    if (menu.skins[2] > 0) {
        int state = 0, since = elapsed;
        if (game.mouth) { state = 2; since = game.ticks - game.mouthtick; }
        if (game.state == dx::outcome::won) { state = 4; since = elapsed - game.resulttick; }
        if (game.state == dx::outcome::lost) { state = 3; since = elapsed - game.resulttick; }
        add(animation(menuart::costumes[menu.skins[2] - 1][state], since * .016f),
            std::lround(128 + (game.definition.target.x - 1280) * pixels), std::lround(game.definition.target.y * pixels));
    }
    if (menu.skins[0] > 0 && game.state != dx::outcome::won) {
        const int px = std::lround(128 + (game.candy().pos.x - 1280) * pixels), py = std::lround(game.candy().pos.y * pixels);
        for (int id : menuart::gamecandies[menu.skins[0]]) add(id, px, py);
    }
    const auto& trail = trace::trail;
    auto px = [](float value) { return std::lround(128 + (value - 1280) * pixels); };
    auto py = [](float value) { return std::lround(value * pixels); };
    if (trail.mode == 2 && trail.length > 1) {
        float total = 0;
        for (int i = 0; i < trail.length; ++i) total += (trail.segments[i].last - trail.segments[i].first).length();
        const int pieces = static_cast<int>(total / 112) + 1;
        int first = 0;
        for (int piece = 0; piece < pieces && first < trail.length; ++piece) {
            int last = first;
            float distance = 0;
            do { distance += (trail.segments[last].last - trail.segments[last].first).length(); ++last; }
            while (distance < total / pieces && last < trail.length);
            const int end = std::min(last, trail.length - 1);
            if (end > first) {
                const auto a = trail.segments[first].first, b = trail.segments[end].last, d = b - a;
                const int id = menuart::particle0 + (piece == 0 ? 20 + elapsed / 4 % 4 : 14 + (elapsed / 4 + piece) % 6);
                add(id, px((a.x + b.x) / 2), py((a.y + b.y) / 2), {}, GL_FLIP_NONE,
                    (piece + 1) * 30 * pixels / menuart::sprites[id].w,
                    static_cast<int>((std::atan2(d.y, d.x) + 1.5707963f) * 32768 / 6.2831853f), 31,
                    RGB15(31, 31, std::min(31, static_cast<int>((piece + .5f) / pieces * 31))));
                commands[count - 1].vertical = d.length() * 1.25f * pixels / menuart::sprites[id].h;
            }
            first = end + 1;
        }
    }
    const int glow = trail.mode == 2 || trail.mode == 3 ? 0 : trail.mode == 4 ? 1 : trail.mode >= 6 ? 2 : -1;
    if (glow >= 0 && trail.length) {
        const int alpha = std::clamp(static_cast<int>(std::min(trail.length / 5.0f, trail.direction.length() / 10) * 31), 0, 31);
        if (alpha) add(menuart::traceglow0 + glow, px(trail.head.x), py(trail.head.y), {}, GL_FLIP_NONE, 1,
            static_cast<int>((trail.angle + 1.5707963f) * 32768 / 6.2831853f), alpha);
    }
    for (int i = 0; i < trail.count; ++i) {
        const auto& item = trail.particles[i];
        const auto& config = menuart::tracepresets[item.preset];
        const float ratio = item.life / item.total;
        const float size = item.size + (config.endscale - item.size) * (1 - ratio);
        const int alpha = std::clamp(static_cast<int>(config.alpha * (config.fadealphawithlife ? ratio : 1) * 31), 0, 31);
        if (alpha && size > .01f) add(menuart::particle0 + item.quad, px(item.position.x), py(item.position.y), {}, GL_FLIP_NONE, size,
            static_cast<int>(item.rotation * 32768 / 360), alpha);
    }
    upload();
}

struct tint { float r, g, b, a = 1; };
static tint mix(tint a, tint b, float value) {
    value = std::clamp(value, 0.0f, 1.0f);
    return {a.r + (b.r - a.r) * value, a.g + (b.g - a.g) * value, a.b + (b.b - a.b) * value, a.a + (b.a - a.a) * value};
}
static tint color(int mode, float t) {
    if (mode == 0) return {1, 1, 1};
    if (mode == 3) {
        if (t < .33f) return mix({1,.30196f,.99216f}, {1,.64314f,.29412f}, t * 3);
        if (t < .66f) return mix({1,.64314f,.29412f}, {1,.95294f,.20392f}, (t - .33f) * 3);
        return mix({1,.95294f,.20392f}, {1,1,1}, (t - .66f) * 3);
    }
    if (mode == 4) return t < .5f ? mix({.13f,.59608f,.75686f,0}, {.51765f,1,1}, t * 2) : mix({.51765f,1,1}, {1,1,1}, (t - .5f) * 2);
    if (mode == 5) return t < .7f ? mix({.7882f,.2157f,.298f,0}, {.98824f,.20784f,.16863f}, t * 2) : mix({.98824f,.20784f,.16863f}, {.95294f,.61961f,.41961f}, (t - .7f) * 2);
    if (mode == 6) return mix({.14118f,.81961f,.87451f}, {1,1,1}, t * 3);
    return mix({1,.87451f,.0549f}, {1,1,1}, t * 3);
}
void ribbon() {
    const auto& trail = trace::trail;
    if (!trail.length || trail.mode == 1 || trail.mode == 2) return;
    dx::point points[41], left[41], right[41];
    const int size = trail.length * 2 + 1;
    for (int i = 0; i < size; ++i) {
        dx::point work[21];
        for (int j = 0; j < trail.length; ++j) work[j] = trail.segments[j].first;
        work[trail.length] = trail.segments[trail.length - 1].last;
        const float t = static_cast<float>(i) / (size - 1);
        for (int n = trail.length; n > 0; --n) for (int j = 0; j < n; ++j) work[j] = work[j] + (work[j + 1] - work[j]) * t;
        points[i] = {128 + (work[0].x - 1280) * pixels, work[0].y * pixels};
    }
    for (int i = 0; i < size; ++i) {
        const auto direction = points[std::min(size - 1, i + 1)] - points[std::max(0, i - 1)];
        const float width = (i == size - 1 ? 1 : 1 + 12.0f * i / (size - 1)) * pixels;
        const auto normal = dx::point{-direction.y, direction.x} * (width / std::max(.0001f, direction.length()));
        left[i] = points[i] - normal; right[i] = points[i] + normal;
    }
    for (int i = 1; i < size; ++i) {
        const auto a = color(trail.mode, static_cast<float>(i - 1) / (size - 1)), b = color(trail.mode, static_cast<float>(i) / (size - 1));
        const u16 first = RGB15(std::lround(a.r * 31), std::lround(a.g * 31), std::lround(a.b * 31));
        const u16 last = RGB15(std::lround(b.r * 31), std::lround(b.g * 31), std::lround(b.b * 31));
        glPolyFmt(POLY_ALPHA(std::max(1, static_cast<int>((a.a + b.a) * 15.5f))) | POLY_CULL_NONE | POLY_ID(50));
        glTriangleFilledGradient(left[i - 1].x, left[i - 1].y, right[i - 1].x, right[i - 1].y, left[i].x, left[i].y, first, first, last);
        glTriangleFilledGradient(right[i - 1].x, right[i - 1].y, right[i].x, right[i].y, left[i].x, left[i].y, first, last, last);
    }
}

void draw(const ui::controller& menu) {
    count = 0;
    overlaystart = -1;
    add(menu.mode == ui::view::home ? menuart::titleback : menu.mode == ui::view::levels ? menuart::levelbacks[menu.pack] : menu.mode == ui::view::skins ? menuart::skinback : menuart::menuback, 128, 96);
    if (menu.mode != ui::view::skins) add(menuart::shadow, 128, 96, {}, GL_FLIP_NONE, (1781 * 2 * pixels) / 256, 4096 + (frame % 4500) * 32768 / 4500);
    switch (menu.mode) {
    case ui::view::home:
        add(menuart::titlelogo, x(1280, menuart::mainfit), y(410, menuart::mainfit));
        add(menuart::titlecandies[menu.skins[0]], x(1423, menuart::mainfit), y(685.5f, menuart::mainfit));
        if (menu.candyhint) add(menuart::titlehand, x(1603 + 10 * std::cos(menu.age * .087266f), menuart::mainfit), y(729.5f, menuart::mainfit));
        break;
    case ui::view::packs: packs(menu); break;
    case ui::view::options: options(menu); break;
    case ui::view::skins: skins(menu); break;
    case ui::view::resetmenu: label(menu, menuart::RESET_TEXT, 128, y(520)); break;
    case ui::view::credits: {
        const int first = std::max(0, static_cast<int>(menu.creditoffset) / 96);
        const int last = std::min(static_cast<int>(std::size(menuart::credits[0])) - 1, static_cast<int>(menu.creditoffset + 146) / 96);
        for (int i = first; i <= last; ++i) add(menuart::credits[menu.locale][i], 41, 23 + i * 96 - static_cast<int>(menu.creditoffset), {41, 23, 215, 169});
        break;
    }
    case ui::view::levels:
        for (int row = 0; row < 5; ++row) {
            for (int column = 0; column < 5; ++column) {
                const int px = x(824 + column * 228), py = y(203.5f + row * 258);
                const bool unlocked = menu.unlockall() || (menu.pack == 0 && row == 0 && column == 0);
                add(unlocked ? menuart::level0 : menuart::level1, px, py);
                if (unlocked) {
                    add(menuart::level2 + (menu.pack == 0 && row == 0 && column == 0 ? menu.beststars : 0), px, py);
                    label(menu, menuart::number1 + row * 5 + column, px, py - 1);
                }
            }
        }
        label(menu, menuart::count0 + menu.beststars, 231, 10);
        add(menuart::pack3, 248, 9);
        if (menu.notice) label(menu, menuart::unavailable, 128, 186);
        break;
    default: break;
    }
    int index = menu.mode == ui::view::levels ? 25 : 0;
    for (const auto& item : menuart::controls) {
        if (item.view != menu.mode) continue;
        bool pressed = menu.pressed == index || (menu.keyboard && menu.focus == index);
        if (item.action == ui::action::language && item.argument == menu.locale) pressed = !pressed;
        if (item.action == ui::action::skintab && item.argument == menu.skintab) pressed = true;
        const float factor = menu.mode == ui::view::home ? menuart::mainfit / menuart::fit : 1;
        add(pressed ? item.down : item.up, item.x, item.y, {}, item.action == ui::action::nextpack ? GL_FLIP_H : GL_FLIP_NONE, factor);
        if (item.label >= 0) add(menuart::labels[menu.locale][item.label], item.x, item.y, {}, GL_FLIP_NONE, factor);
        if (item.action == ui::action::music || item.action == ui::action::effects) {
            const bool enabled = item.action == ui::action::music ? menu.music : menu.effects;
            add(menuart::option0 + item.argument, item.x, item.y, {}, GL_FLIP_NONE, 1, 0, enabled ? 31 : 16, enabled ? RGB15(31,31,31) : RGB15(15,15,15));
            if (!enabled) add(menuart::option4, item.x + (item.argument == 2 ? 10 : 7), item.y + 5);
        }
        ++index;
    }
    upload();
    glBegin2D();
    render();
    glEnd2D();
    glFlush(GL_TRANS_MANUALSORT);
}

void render(bool overlay) {
    const int first = overlay ? overlaystart : 0, last = !overlay && overlaystart >= 0 ? overlaystart : count;
    for (int i = first; i < last; ++i) {
        const command& item = commands[i];
        if (item.id < 0) {
            glPolyFmt(POLY_ALPHA(item.alpha) | POLY_CULL_NONE | POLY_ID(60));
            glBoxFilled(item.bounds.left, item.bounds.top, item.bounds.right - 1, item.bounds.bottom - 1, item.color);
            continue;
        }
        const auto& source = menuart::sprites[item.id];
        glImage image{source.w, source.h, source.x, source.y, textures[source.page]};
        glColor(item.color);
        glPolyFmt(POLY_ALPHA(item.alpha) | POLY_CULL_NONE | POLY_ID(i % 48 + 1));
        if (item.angle) {
            const float angle = item.angle * (6.2831853f / 32768);
            const float dx = (source.ox + source.w / 2.0f) * item.scale, dy = (source.oy + source.h / 2.0f) * item.vertical;
            glSpriteRotateScaleXY(item.x + std::lround(dx * std::cos(angle) - dy * std::sin(angle)),
                item.y + std::lround(dx * std::sin(angle) + dy * std::cos(angle)), item.angle,
                floattof32(item.scale), floattof32(item.vertical), item.flip, &image);
        } else {
            int px = item.x + std::lround(source.ox * item.scale), py = item.y + std::lround(source.oy * item.vertical);
            {
                const int left = std::max(0, static_cast<int>(std::ceil((item.bounds.left - px) / item.scale)));
                const int top = std::max(0, static_cast<int>(std::ceil((item.bounds.top - py) / item.vertical)));
                image.width = std::min(source.w - left, static_cast<int>((item.bounds.right - px) / item.scale) - left);
                image.height = std::min(source.h - top, static_cast<int>((item.bounds.bottom - py) / item.vertical) - top);
                if (image.width <= 0 || image.height <= 0) continue;
                image.u_off += item.flip & GL_FLIP_H ? source.w - left - image.width : left;
                image.v_off += item.flip & GL_FLIP_V ? source.h - top - image.height : top;
                if (item.scale == 1 && item.vertical == 1) glSprite(px + left, py + top, item.flip, &image);
                else glSpriteScaleXY(px + std::lround(left * item.scale), py + std::lround(top * item.vertical), floattof32(item.scale), floattof32(item.vertical), item.flip, &image);
            }
        }
    }
}
}
