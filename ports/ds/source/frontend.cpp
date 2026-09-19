#include "frontend.hpp"
#include "menuassets.hpp"
#include "packed.hpp"
#include "trace.hpp"
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
static std::array<command, 256> commands;
static int count = 0;
static constexpr float pixels = 192.0f / 1440;

static int x(float value, float fit = menuart::fit) { return std::lround(128 + (value - 1280) * pixels * fit); }
static int y(float value, float fit = menuart::fit) { return std::lround(96 + (value - 720) * pixels * fit); }

static void add(int id, int px, int py, clip bounds = {}, int flip = GL_FLIP_NONE, float scale = 1, int angle = 0, int alpha = 31, u16 color = RGB15(31, 31, 31)) {
    if (id < 0 || count >= static_cast<int>(commands.size())) return;
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

static int animation(int index, float seconds) {
    for (int limit = 0; limit < 64; ++limit) {
        const auto& item = menuart::animations[index];
        if (seconds < item.duration || item.followup < 0) return item.frames[std::min(item.count - 1, static_cast<int>(seconds * item.fps))];
        if (item.followup == index) seconds = std::fmod(seconds, item.duration);
        else { seconds -= item.duration; index = item.followup; }
    }
    return menuart::animations[index].frames[0];
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
                factor = 1.25f / 1.73f * menuart::fit;
                if (selected) preview = animation(menuart::costumes[i - 1][5], menu.skinage * .016f);
            }
        }
        add(preview, px, py - (menu.skintab == 2 ? 1 : 3), window, GL_FLIP_NONE, factor);
    }
}

void preparegame(const ui::controller& menu, const dx::simulation& game, int elapsed) {
    count = 0;
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

void render() {
    for (int i = 0; i < count; ++i) {
        const command& item = commands[i];
        if (item.id < 0) {
            glPolyFmt(POLY_ALPHA(31) | POLY_CULL_NONE | POLY_ID(49));
            glBoxFilled(item.bounds.left, item.bounds.top, item.bounds.right - 1, item.bounds.bottom - 1, item.color);
            continue;
        }
        const auto& source = menuart::sprites[item.id];
        glImage image{source.w, source.h, source.x, source.y, textures[source.page]};
        glColor(item.color);
        glPolyFmt(POLY_ALPHA(item.alpha) | POLY_CULL_NONE | POLY_ID(i % 48 + 1));
        if (item.angle) {
            glSpriteRotateScaleXY(item.x, item.y, item.angle, floattof32(item.scale), floattof32(item.vertical), item.flip, &image);
        } else {
            int px = item.x + std::lround(source.ox * item.scale), py = item.y + std::lround(source.oy * item.vertical);
            {
                const int left = std::max(0, static_cast<int>(std::ceil((item.bounds.left - px) / item.scale)));
                const int top = std::max(0, static_cast<int>(std::ceil((item.bounds.top - py) / item.vertical)));
                image.width = std::min(source.w - left, static_cast<int>((item.bounds.right - px) / item.scale) - left);
                image.height = std::min(source.h - top, static_cast<int>((item.bounds.bottom - py) / item.vertical) - top);
                if (image.width <= 0 || image.height <= 0) continue;
                image.u_off += left;
                image.v_off += top;
                if (item.scale == 1 && item.vertical == 1) glSprite(px + left, py + top, item.flip, &image);
                else glSpriteScaleXY(px + std::lround(left * item.scale), py + std::lround(top * item.vertical), floattof32(item.scale), floattof32(item.vertical), item.flip, &image);
            }
        }
    }
}
}
