#include "frontend.hpp"
#include "upper.hpp"
#include "menuassets.hpp"
#include "packed.hpp"
#include "trace.hpp"
#include "result.hpp"
#include "geometry.hpp"
#include "assets.hpp"
#include "profiling.hpp"
#include "routes.hpp"
#include "contraptionview.hpp"
#include "deviceview.hpp"
#include "nocturnalview.hpp"
#include "conveyorview.hpp"
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
static unsigned repacks = 0;
extern "C" { volatile unsigned renderfault = 0; }
#ifdef DS_PROFILE
extern "C" { volatile unsigned renderstamp = 0; }
#endif
alignas(32) static unsigned char staged[393216 + 512*64];
static unsigned stagedbytes = 0;
static unsigned workversion = 0, blendversion = 0;
unsigned char* workspace() { return staged; }
unsigned workgeneration(unsigned boundary) { return boundary==65536?blendversion:workversion; }
struct transfer { void* destination; const void* source; unsigned bytes; };
static transfer transfers[784];
static unsigned transfercount = 0;
static unsigned char compressed[4096];
#ifdef __NDS__
static volatile bool captured = false, armed = false, frozen = false;
#endif
void capture() {
#ifdef __NDS__
    if (frozen) return;
    captured = armed;
    REG_DISPCAPCNT = DCAP_ENABLE | DCAP_BANK(DCAP_BANK_VRAM_C) | DCAP_SIZE(DCAP_SIZE_256x192);
    armed = true;
#endif
}
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
static std::array<command, 512> commands;
static std::array<bool, 512> visibility;
static int count = 0;
static int overlaystart = -1;
static int groundend = 0, starback = 0, starfront = 0;
static constexpr float pixels = 192.0f / 1440;
static float cameray = 0;

static int x(float value, float fit = menuart::fit) { return std::lround(128 + (value - 1280) * pixels * fit); }
static int y(float value, float fit = menuart::fit) { return std::lround(96 + (value - 720) * pixels * fit); }

static void add(int id, int px, int py, clip bounds = {}, int flip = GL_FLIP_NONE, float scale = 1, int angle = 0, int alpha = 31, u16 color = RGB15(31, 31, 31)) {
    if (id < 0 || scale <= .001f || alpha <= 0) return;
    if (count >= static_cast<int>(commands.size())) { renderfault = 6; return; }
    commands[count++] = {id, px, py, alpha, flip, angle, scale, bounds, color, scale};
}

static void label(const ui::controller& menu, int id, int px, int py, clip bounds = {}) {
    add(menuart::labels[menu.locale][id], px, py, bounds);
}

static unsigned bytes(int page) {
    const auto& item = menuart::pages[page];
    return item.width * item.height * (item.direct ? 2 : 1);
}

static bool visible(const command& item) {
    if (item.bounds.right <= item.bounds.left || item.bounds.bottom <= item.bounds.top) return false;
    if (item.id < 0) return true;
    const auto& source = menuart::sprites[item.id];
    float left = item.x + std::lround(source.ox * item.scale);
    float top = item.y + std::lround(source.oy * item.vertical);
    float width = source.w * item.scale, height = source.h * item.vertical;
    if (item.angle) {
        // Conservative all-angle bound avoids extra software trig for every
        // confetti particle in both the cache and drawing passes.
        const float radius = std::max(std::abs(source.ox),std::abs(source.ox + source.w)) * item.scale +
            std::max(std::abs(source.oy),std::abs(source.oy + source.h)) * item.vertical;
        left = item.x - radius; top = item.y - radius;
        width = height = radius * 2;
    }
    // One-pixel margin covers the fixed-point sprite transform's rounding.
    return left + width + 1 > std::max(0,item.bounds.left) && left - 1 < std::min(256,item.bounds.right) &&
        top + height + 1 > std::max(0,item.bounds.top) && top - 1 < std::min(192,item.bounds.bottom);
}

void reset() {
    stagedbytes = transfercount = 0;
    glResetTextures();
    gCurrentTexture = -1;
    std::fill(std::begin(textures), std::end(textures), 0);
    std::fill(std::begin(touched), std::end(touched), 0);
    occupied = 0;
    reserved = 0;
}

unsigned texturebytes() { return occupied + reserved; }
unsigned cacherepacks() { return repacks; }
unsigned cachefault() { return renderfault; }

// Keep gameplay atlas/background handles alive during results/replay.
static void repack() {
    for (int& texture : textures) {
        if (texture) glDeleteTextures(1, &texture);
        texture = 0;
    }
    occupied = 0;
    gCurrentTexture = -1;
    ++repacks;
}

static void enqueue(void* destination, const void* source, unsigned size) {
    if (!destination || transfercount >= std::size(transfers)) {
        renderfault = 0x20000000;
        nocashMessage("CTRD DS: invalid texture transfer");
        while (true) swiWaitForVBlank();
    }
    transfers[transfercount++] = {destination, source, size};
}

void stage(int texture, const void* pixels, unsigned size, const void* palette, int colors) {
    enqueue(glGetTexturePointer(texture), pixels, size);
    if (colors) {
        glBindTexture(0, texture);
        glColorTableEXT(0, 0, colors, 0, 0, nullptr);
        enqueue(glGetColorTablePointer(texture), palette, colors * 2);
    }
}

static unsigned char* staging(unsigned size) {
    if (size > sizeof(staged) - stagedbytes) {
        renderfault = 0x30000000 | (stagedbytes + size);
        nocashMessage("CTRD DS: staging capacity exceeded");
        while (true) swiWaitForVBlank();
    }
    unsigned char* result = staged + stagedbytes;
    stagedbytes += size;
    if (stagedbytes > 65536) ++blendversion;
    if (stagedbytes > 262144) ++workversion;
    return result;
}

void present() {
    if (!transfercount) { glFlush(GL_TRANS_MANUALSORT); DS_PROFILE_DO(++renderstamp); return; }
#ifdef __NDS__
    unsigned bytes = 0;
    for (unsigned i = 0; i < transfercount; ++i) {
        DC_FlushRange(transfers[i].source, transfers[i].bytes);
        bytes += transfers[i].bytes;
    }
    {
        DS_SCOPE(wait);
        while (GFX_BUSY) {}
        while (REG_VCOUNT < 148 || REG_VCOUNT > 188) swiIntrWait(1, IRQ_VCOUNT);
        // The old frame must have finished rendering, including its buffered tail.
        while (REG_VCOUNT < 192 && (GFX_RDLINES_COUNT & 0x3f) < 192u - REG_VCOUNT) {}
    }
    const unsigned lines = (bytes + 2303) / 2304 + transfercount / 4 + 4;
    const bool hidden = (REG_MASTER_BRIGHT & 0xc01f) == 0x8010;
    bool hold = !hidden && lines >= 214u - REG_VCOUNT;
    DS_PROFILE_DO(if (profilestress & 1) { hold = true; profilestress = profilestress & ~1u; });
    if (hold) {
        DS_SCOPE(wait);
        do { swiWaitForVBlank(); } while (!captured);
        frozen = true;
        REG_DISPCAPCNT = 0;
        // Capture is RGB5, so this rare held frame loses the 3D output's low color bit.
        vramSetBankC(VRAM_C_MAIN_BG_0x06000000);
        videoSetMode(MODE_5_2D);
        bgInit(3, BgType_Bmp16, BgSize_B16_256x256, 0, 0);
    } else glFlush(GL_TRANS_MANUALSORT);
    {
        DS_SCOPE(transfer);
        DS_PROFILE_DO(profiling::data[profiling::uploadstart] = REG_VCOUNT);
        const int interrupts = enterCriticalSection();
        const auto a = VRAM_A_CR, b = VRAM_B_CR, d = VRAM_D_CR, e = VRAM_E_CR;
        vramSetBankA(VRAM_A_LCD); vramSetBankB(VRAM_B_LCD);
        vramSetBankD(VRAM_D_LCD); vramSetBankE(VRAM_E_LCD);
        for (unsigned i = 0; i < transfercount; ++i) {
            const auto& item = transfers[i];
            dmaCopyWords(3, item.source, item.destination, item.bytes);
        }
        VRAM_A_CR = a; VRAM_B_CR = b; VRAM_D_CR = d; VRAM_E_CR = e;
        leaveCriticalSection(interrupts);
        DS_PROFILE_DO(profiling::data[profiling::uploadend] = REG_VCOUNT;
            profiling::data[profiling::holds] = hold;
            if (!hidden && !hold && (REG_VCOUNT >= 214 || REG_VCOUNT < 148)) ++profiling::data[profiling::visibleupload]);
    }
    if (hold) {
        DS_SCOPE(wait);
        glFlush(GL_TRANS_MANUALSORT);
        swiWaitForVBlank();
        swiWaitForVBlank();
        vramSetBankC(VRAM_C_LCD);
        videoSetMode(MODE_0_3D);
        frozen = false;
        capture();
    }
#else
    glFlush(GL_TRANS_MANUALSORT);
#endif
    transfercount = stagedbytes = 0;
    DS_PROFILE_DO(++renderstamp);
}

int background(int box, int sections, int top, int texture) {
    FILE* file = std::fopen("nitro:/world.bin", "rb");
    const unsigned offset = art::backgrounds[box][std::clamp(sections, 1, 3) - 1] + top * 512;
    auto* pixels = staging(131072);
    const bool valid = file && !std::fseek(file, offset, SEEK_SET) && std::fread(pixels, 1, 131072, file) == 131072;
    if (file) std::fclose(file);
    if (!valid) { nocashMessage("CTRD DS: background read failed"); while (true) swiWaitForVBlank(); }
    if (!texture) glGenTextures(1, &texture);
    glBindTexture(0, texture);
    if (!glTexImage2D(0, 0, GL_RGBA, TEXTURE_SIZE_256, TEXTURE_SIZE_256, 0, TEXGEN_OFF, nullptr)) {
        nocashMessage("CTRD DS: background allocation failed"); while (true) swiWaitForVBlank();
    }
    stage(texture, pixels, 131072);
    gCurrentTexture = -1;
    return texture;
}

static void upload(bool repacked = false) {
    DS_SCOPE(upload);
    DS_PROFILE_DO(if (profilestress & 2) { profilestress = profilestress & ~2u; repack(); });
    DS_PROFILE_DO(profiling::data[profiling::commands] = count);
    ++frame;
    bool needed[menuart::pagecount]{};
    bool missing = false;
    unsigned required = 0;
    for (int i = 0; i < count; ++i) {
        visibility[i] = visible(commands[i]);
        if (commands[i].id < 0 || !visibility[i]) continue;
        const int page = menuart::sprites[commands[i].id].page;
        if (!needed[page]) required += bytes(page);
        needed[page] = true;
        touched[page] = frame;
        missing = missing || !textures[page];
    }
    if (required + reserved > 384 * 1024) {
        renderfault = required + reserved;
        nocashMessage("CTRD DS: menu working set exceeds texture VRAM");
        while (true) swiWaitForVBlank();
    }
    if (!missing) return;
    const unsigned savedbytes = stagedbytes, savedtransfers = transfercount;
    auto evict = [&]() {
        int oldest = -1;
        for (int candidate = 0; candidate < menuart::pagecount; ++candidate) {
            if (textures[candidate] && !needed[candidate] && (oldest < 0 || touched[candidate] < touched[oldest])) oldest = candidate;
        }
        if (oldest < 0) return false;
        DS_PROFILE_DO(if (touched[oldest] + 1 == frame) ++profiling::data[profiling::previousevictions]);
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
        glGenTextures(1, &textures[index]);
        glBindTexture(0, textures[index]);
        int width = 0, height = 0;
        for (int size = page.width; size > 8; size >>= 1) ++width;
        for (int size = page.height; size > 8; size >>= 1) ++height;
        while (!glTexImage2D(0, 0, page.direct ? GL_RGBA : page.alphabits == 5 ? GL_RGB8_A5 : GL_RGB32_A3, width, height, 0, TEXGEN_OFF, nullptr)) {
            if (!evict()) {
                // A/B/D are three separate 128 KiB banks. Enough free bytes
                // need not imply a contiguous allocation after locale changes.
                if (!repacked) {
                    stagedbytes = savedbytes; transfercount = savedtransfers;
                    repack(); upload(true); return;
                }
                renderfault = 0x10000000 | index;
                nocashMessage("CTRD DS: menu texture allocation failed");
                while (true) swiWaitForVBlank();
            }
            glBindTexture(0, textures[index]);
        }
        unsigned char* pixels = staging(bytes(index));
        const int colors = page.direct ? 0 : 1 << (8-page.alphabits);
        unsigned char* palette = staging(colors*2);
        unsigned remaining = page.packed, cursor = 0, available = 0;
        auto next = [&]() -> int {
            if (cursor == available) {
                DS_SCOPE(read);
                const unsigned size = std::min(remaining, static_cast<unsigned>(sizeof(compressed)));
                available = std::fread(compressed, 1, size, catalog);
                cursor = 0; remaining -= available;
                if (!available) return -1;
            }
            return compressed[cursor++];
        };
        {
            DS_SCOPE(decode);
            bool valid = !std::fseek(catalog, page.offset, SEEK_SET);
            for (int i=0;i<colors*2 && valid;++i) { const int value=next(); valid=value>=0; palette[i]=value; }
            if (!valid || !packed::stream(next, pixels, bytes(index))) {
                nocashMessage("CTRD DS: invalid packed menu texture");
                while (true) swiWaitForVBlank();
            }
        }
        stage(textures[index], pixels, bytes(index), palette, colors);
        DS_PROFILE_DO(++profiling::data[profiling::uploads]; profiling::data[profiling::uploadbytes] += bytes(index));
        occupied += bytes(index);
    }
    // Raw libnds uploads do not update gl2d's binding cache.
    gCurrentTexture = -1;
}

static void packs(const ui::controller& menu) {
    const clip strip{38, 0, 218, 192};
    const float zoom = menuart::boxzoom, step = 640 * menuart::fit * pixels * zoom;
    add(menuart::pack4, 45, 96);
    commands[count-1].vertical = zoom;
    add(menuart::pack4, 211, 96, {}, GL_FLIP_H | GL_FLIP_V);
    commands[count-1].vertical = zoom;
    for (int i = 0; i < menuart::boxcount; ++i) {
        const int center = std::lround(128 + (i - menu.packposition) * step);
        if (center + 45*zoom < strip.left || center - 45*zoom >= strip.right) continue;
        if (menu.packopen(i)) {
            static constexpr unsigned char colors[17][3] = {{70,37,0},{39,52,0},{44,45,54},{31,42,84},{69,31,50},{75,33,0},
                {84,22,0},{0,51,78},{98,0,0},{66,40,0},{0,47,90},{0,58,0},{63,42,0},{89,12,0},{56,45,0},{37,32,104},{55,38,62}};
            const clip hole{std::max(strip.left, center - static_cast<int>(16*zoom)), 96, std::min(strip.right, center + static_cast<int>(16*zoom)), static_cast<int>(std::lround(96+26*zoom))};
            if (hole.right > hole.left) {
                commands[count++] = {-1, 0, 0, 31, GL_FLIP_NONE, 0, 1, hole, static_cast<u16>(RGB15(colors[i][0] >> 3, colors[i][1] >> 3, colors[i][2] >> 3))};
                add(menuart::pack1, 128, 96, hole);
            }
        }
        const int first = count;
        add(menuart::boxes[i], center, 96, strip);
        label(menu, menuart::boxname0 + i, center, std::lround(96-20*zoom), strip);
        if (!menu.packopen(i)) {
            add(menuart::pack2, center, 96, strip);
            const int middle = std::lround(96 + 110 * menuart::fit * pixels * zoom);
            label(menu, menuart::required0 + i, center - std::lround(30 * menuart::fit * pixels * zoom), middle, strip);
            add(menuart::boxstar, center + std::lround(menuart::lockwidths[menu.locale][i] * .5f * menuart::fit * pixels * zoom), middle, strip);
            label(menu, menuart::hint0 + i, center, std::lround(96+47*zoom), strip);
        }
        if (i == menuart::boxcount - 1) {
            add(menuart::pack9, center + std::lround(18*zoom), std::lround(96+19*zoom), strip);
            add(menuart::labels[menu.locale][menuart::HARDEST_LABEL], center + std::lround(18*zoom), std::lround(96+19*zoom), strip);
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
    commands[count-1].vertical = zoom;
    add(menuart::pack5, 218, 96, {}, GL_FLIP_H | GL_FLIP_V);
    commands[count-1].vertical = zoom;
    const int text = menuart::labels[menu.locale][menuart::total0 + std::min(menuart::playableboxes * 75, menu.totalstars())];
    const auto& definition = menuart::sprites[text];
    add(text, 240 - definition.w / 2, 12);
    add(menuart::boxstar, 247, 11, {}, GL_FLIP_NONE, menuart::settingszoom/menuart::boxzoom);
}

static void options(const ui::controller& menu) {
    add(menuart::setting5, 101, 140, {}, GL_FLIP_NONE, .82f);
    add(menuart::setting6, 155, 140, {}, GL_FLIP_NONE, .82f);
    label(menu, menuart::DRAG_TO_CUT, 101, 166);
    label(menu, menuart::CLICK_TO_CUT, 155, 166);
    add(menuart::setting10, 99, 178, {}, GL_FLIP_NONE, .8f);
    add(menuart::setting7, 101, 176, {}, GL_FLIP_NONE, .8f);
    add(menuart::setting9, 153, 178, {}, GL_FLIP_NONE, .8f);
    if (menu.clickcut) add(menuart::setting8, 155, 176, {}, GL_FLIP_NONE, .8f);
    label(menu, menuart::unlockall, 125, 184);
    add(menu.unlockall() ? menuart::setting8 : menuart::setting9, 176, 186, {}, GL_FLIP_NONE, .65f);
}

static int animation(int index, float seconds, bool preview = false) {
    for (int limit = 0; limit < 64; ++limit) {
        const auto& item = menuart::animations[index];
        if (seconds < item.duration || item.followup < 0) {
            int frame = static_cast<int>(seconds * item.fps);
            if (frame >= item.count) frame = item.count - 1;
            if (frame < 0) frame = 0;
            return preview ? item.previewframes[frame] : item.frames[frame];
        }
        if (item.followup == index) seconds = std::fmod(seconds, item.duration);
        else { seconds -= item.duration; index = item.followup; }
    }
    return menuart::animations[index].frames[0];
}

static float unit(float value) { return std::clamp(value, 0.0f, 1.0f); }
static void gamelabel(const ui::controller& menu, int key, int px, int py, float alpha = 1, float width = 0) {
    const int id=menuart::gamelabels[menu.locale][key];
    const float scale=width>0?std::min(1.0f,width/menuart::sprites[id].w):1;
    add(id, px, py, {}, GL_FLIP_NONE, scale, 0, std::lround(unit(alpha) * 31));
}
static void digits(const ui::controller& menu, const char* value, int px, int py, bool score, float alpha = 1, bool result = false) {
    const auto* font = score ? menuart::scoredigits : result ? menuart::resultdigits[menu.locale] : menuart::digits[menu.locale];
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
static void doors(float progress, bool opening, bool loading, int box) {
    const float t = unit(progress), closed = opening ? 1 - t : t;
    const float base = -320 * pixels, width = 1293 * pixels, height = 192 * (1.1f - .1f * closed);
    const float side = (1 - closed) * 72 * pixels;
    piece(menuart::doorshade, (opening ? -t : t - 1) * 891 * 4 * pixels + base, 0, 891 * 4 * pixels, 400 * 4 * pixels);
    const float leftside = opening ? (1280 - 12) * (1 - t) - 25 * t : -13 * (1 - t) + (1293 - 16) * t;
    const float rightside = opening ? (1280 + 14) * (1 - t) + 2560 * t : (2560 - 40) * (1 - t) + (1280 + 20) * t;
    static constexpr int covers[] = {menuart::cover0, menuart::fabriccover0, menuart::boxcover3x0, menuart::boxcover4x0, menuart::boxcover5x0, menuart::boxcover6x0, menuart::boxcover7x0, menuart::boxcover8x0, menuart::boxcover9x0, menuart::boxcover10x0, menuart::boxcover11x0, menuart::boxcover12x0, menuart::boxcover13x0, menuart::boxcover14x0, menuart::boxcover15x0, menuart::boxcover16x0, menuart::boxcover17x0};
    static_assert(std::size(covers) == menuart::playableboxes, "Every playable box needs its authored flaps");
    const int cover = covers[box];
    piece(cover + 1, base + leftside * pixels, 0, side, 192 * (1 + .3f * closed));
    piece(cover + 1, base + rightside * pixels, 0, side, 192 * (1 + .3f * closed));
    piece(cover, base - 13 * pixels, (192 - height) / 2, width * closed, height, GL_FLIP_NONE, 1 - .15f * closed);
    piece(cover, base + (1280 + 1293) * pixels - width * closed, (192 - height) / 2, width * closed, height,
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
    if (!final) digits(menu, buffer, a[6][0], a[6][1], false, opacity * alpha, true);
    std::snprintf(buffer, sizeof(buffer), "%d", total);
    digits(menu, buffer, a[8][0], a[8][1], true, opacity * scorealpha);
    if (menu.improved && t > 3.8f) {
        const float f = unit((t - 3.8f) / .5f), eased = f * f;
        add(menuart::stamp17 + menuart::stamps[menu.locale] - 17, a[12][0], a[12][1], {}, GL_FLIP_NONE, 3 - 2 * eased, 0, std::lround(31 * eased * opacity));
    }
    for (int i = 0; i < 3; ++i) {
        const int slot = i == 0 ? 11 : i == 1 ? 10 : 9;
        const float alpha = opacity * (i == 1 && !menu.hasnext() ? .35f : 1);
        add(menu.pressed == i && !hiding ? menuart::resultdown : menuart::resultup, a[slot][0], a[slot][1], {}, GL_FLIP_NONE, 1, 0, std::lround(alpha * 31));
        gamelabel(menu, menuart::gameREPLAY + i, a[slot][0], a[slot][1], alpha, menuart::sprites[menuart::resultup].w-6);
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
    if (menu.mode == ui::view::playing || menu.mode == ui::view::paused || (menu.mode == ui::view::results && menu.age < 32)) {
        const auto& p = menuart::hudpositions[menu.locale];
        add(menuart::hud0, p[2], p[3], {}, GL_FLIP_NONE, 1, 0, menu.pressed == 0 ? 31 : 19);
        add(menuart::hud0 + menuart::hudquads[menu.locale], p[0], p[1], {}, GL_FLIP_NONE, 1, 0, menu.pressed == 1 ? 31 : 19);
        const int levelname = menuart::levelnames[menu.levelid()][menu.locale];
        const auto& name = menuart::sprites[levelname];
        const float time = game.ticks * .016f;
        const float alpha = time < 1 ? unit((time - .5f) / .5f) : time > 2 ? 1 - unit((time - 2) / .5f) : 1;
        const int inset = std::lround(40 * menuart::fit * pixels), bottom = menu.locale >= 10 ? 177 : 181;
        add(levelname, inset + name.w / 2, bottom, {}, GL_FLIP_NONE, 1, 0, std::lround(alpha * 31));
        add(menuart::levelwords[menu.locale], inset + menuart::sprites[menuart::levelwords[menu.locale]].w / 2, bottom - std::lround(9*menuart::hudzoom), {}, GL_FLIP_NONE, 1, 0, std::lround(alpha * 31));
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
    if (menu.mode == ui::view::results) { doors(menu.age * .016f / .5f, false, false, menu.pack); results(menu); }
    if (menu.door) doors(menu.doorframe * .016f / .5f, menu.door == 1, menu.door == 1, menu.pack);
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
    present();
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

static void pollen(const dx::simulation& game, int elapsed) {
    struct mote { dx::point position; unsigned seed; };
    static std::array<mote, 160> motes;
    static int level = -1, size = 0;
    const int id = game.definition.box * 25 + game.definition.index;
    if (level != id) {
        level = id; size = 0;
        unsigned seed = 0x74519u + id;
        auto random = [&]() { seed = seed * 1664525u + 1013904223u; return seed; };
        auto segment = [&](dx::point first, dx::point last) {
            const auto d = last - first;
            const float length = d.length();
            const auto direction = length > 0 ? d / length : dx::point{};
            for (int i = 0; i <= static_cast<int>(length / 44); ++i) {
                if (size >= static_cast<int>(motes.size())) { renderfault = 5; return; }
                const dx::point jitter{static_cast<float>(static_cast<int>(random()%5)-2),static_cast<float>(static_cast<int>(random()%5)-2)};
                motes[size++] = {first + direction * (i * 44.0f) + jitter, random()};
            }
        };
        for (int i = 0; i < game.definition.hookcount; ++i) {
            const auto& hook = game.definition.hooks[i];
            if (hook.route < 0 || hook.hidepath) continue;
            const auto& path = dx::routes[hook.route];
            for (int j = 0; j < path.count - 1; ++j) if (!path.circle || j % 3 == 0)
                segment(dx::routepoints[path.first+j], dx::routepoints[path.first+j+1]);
            if (path.count > 2) segment(dx::routepoints[path.first], dx::routepoints[path.first+path.count-1]);
        }
    }
    auto oscillate = [](float time, float initial, float low, float high) {
        const float first = std::abs(initial-low);
        if (time <= first) return initial + (low > initial ? time : -time);
        const float span = high-low, phase = std::fmod(time-first,span*2);
        return low + (phase < span ? phase : span*2-phase);
    };
    static constexpr float sizes[] = {.3f,.3f,.5f,.5f,.6f};
    for (int i = 0; i < size-1; ++i) {
        const auto& item = motes[i];
        const float phase = (item.seed & 65535) / 65535.0f;
        float lowx = sizes[(item.seed >> 16)%5], lowy = lowx;
        if (item.seed & 0x100000) lowx *= 1.1f; else lowy *= 1.1f;
        const float offset = std::min(1-lowx,1-lowy), highx = lowx+offset, highy = lowy+offset;
        const float sx = oscillate(elapsed*.016f,highx*phase,lowx,highx), sy = oscillate(elapsed*.016f,highy*phase,lowy,highy);
        const int alpha = std::lround(31*oscillate(elapsed*.016f,.3f+.7f*phase,.3f,1));
        const int before = count;
        add(menuart::pollen,std::lround(128+(item.position.x-1280)*pixels),std::lround((item.position.y-cameray)*pixels),{},GL_FLIP_NONE,sx,0,alpha);
        if (count > before) commands[count-1].vertical = sy;
    }
}

void preparegame(const ui::controller& menu, const dx::simulation& game, int elapsed, bool upper) {
    count = 0;
    groundend = starback = starfront = 0;
    overlaystart = -1;
    cameray = game.cameray - (upper ? 1440 : 0);
    auto wx = [](float value) { return std::lround(128 + (value - 1280) * pixels); };
    auto wy = [](float value) { return std::lround((value - cameray) * pixels); };
    auto world = [&](int sprite, dx::point position, int alpha = 31, float angle = 0, float scale = 1, int flip = GL_FLIP_NONE, float vertical = -1, int shade = 31) {
        const int before = count;
        add(sprite, wx(position.x), wy(position.y), {}, flip, scale, static_cast<int>(angle * 32768 / 360), alpha, RGB15(shade,shade,shade));
        if (vertical >= 0 && count > before) commands[count-1].vertical = vertical;
    };
    if (menu.pack == 7) {
        const float turn = std::min(1.0f, game.gravityage * .016f / .3f);
        const float angle = game.inverted ? 180 * turn : 180 * (1 - turn);
        for (int row = -1; row <= 3; ++row) world(menuart::gravity2, {1284,724.0f + row * 1440}, 31, angle);
    }
    pollen(game,elapsed);
    for (int i = 0; i < game.definition.switchcount; ++i)
        world(menuart::gravity0 + game.inverted, game.definition.switches[i]);
    gamevisuals::mouseholes(game,world);
    world(menuart::seat0 + menu.pack, game.definition.target);
    const bool sleeping = game.definition.night && !game.awake && game.state == dx::outcome::playing;
    const float sleepage = (elapsed-game.nightstart)*.016f;
    if (menu.skins[2] == 0) {
        int target = menuart::body0 + elapsed / 3 % 19;
        if (game.mouth) target = menuart::body19 + std::min(8, (game.ticks - game.mouthtick) / 3);
        if (game.state == dx::outcome::won) {
            const int since = elapsed - game.resultvisual;
            target = since < 12 ? menuart::body28 + since / 3 : menuart::body32 + (since - 12) / 3 % 9;
        }
        if (game.state == dx::outcome::lost) target = menuart::bodysad0 + std::min(12, (elapsed - game.resultvisual) / 3);
        if (sleeping) target = menuart::sleep0+std::min(6,static_cast<int>(sleepage/.05f));
        const float pulse = sleeping && sleepage >= .35f ? .95f+(std::sin(sleepage*2)+1)*.05f : 1;
        world(target, game.definition.target+dx::point{0,86*(1-pulse)},31,0,1,GL_FLIP_NONE,pulse);
    }
    if (menu.skins[2] > 0) {
        int state = 0, since = elapsed;
        const auto& states = menuart::costumes[menu.skins[2] - 1];
        if ((elapsed - game.excitement) * .016f < menuart::animations[states[1]].duration) { state = 1; since = elapsed - game.excitement; }
        if ((elapsed - game.greeting) * .016f < menuart::animations[states[6]].duration) { state = 6; since = elapsed - game.greeting; }
        if (game.mouth) { state = 2; since = game.ticks - game.mouthtick; }
        if (game.state == dx::outcome::won) { state = 4; since = elapsed - game.resultvisual; }
        if (game.state == dx::outcome::lost) { state = 3; since = elapsed - game.resultvisual; }
        if (sleeping) { state = game.nightwoken ? 8 : 7; since = elapsed-game.nightstart; }
        add(animation(menuart::costumes[menu.skins[2] - 1][state], since * .016f + (sleeping && game.nightwoken ? menuart::sleeptrim[menu.skins[2]-1] : 0)),
            wx(game.definition.target.x), wy(game.definition.target.y));
    }
    gamevisuals::sleep(game,world);
    const float time = elapsed * .016f;
    static int tutoriallevel = -1, tutorialframe = -1, tutorialstart[32];
    if (tutoriallevel != menu.levelid() * 12 + menu.locale || elapsed < tutorialframe || menu.reset) {
        std::fill(std::begin(tutorialstart), std::end(tutorialstart), -1);
        tutoriallevel = menu.levelid() * 12 + menu.locale;
    }
    tutorialframe = elapsed;
    const auto& span = menuart::tutorialspans[menu.levelid()][menu.locale];
    for (int i = 0; i < span[1] && i < 32; ++i) {
        const auto& item = menuart::tutorials[span[0] + i];
        if (tutorialstart[i] < 0 && item.trigger) {
            const auto p = game.candy().pos;
            const bool triggered = item.trigger == 1 ? game.bubble >= 0 : item.trigger == 2 ? game.captures > 0 : item.trigger == 3 ? game.steamevents > 0 : game.mousecaptures > 0;
            if (triggered && (!item.width || (p.x >= item.left && p.x < item.left + item.width && p.y >= item.top && p.y < item.top + item.height))) tutorialstart[i] = elapsed;
            else continue;
        }
        float t = item.trigger ? time - tutorialstart[i] * .016f : time;
        const float period = item.fadein + item.hold + item.fadeout;
        if (t >= period * item.repeat) continue;
        t = std::fmod(t, period);
        const float alpha = t < item.fadein ? unit(t / item.fadein) : t > item.fadein + item.hold ? 1 - unit((t - item.fadein - item.hold) / item.fadeout) : 1;
        dx::point position{item.x, item.y};
        if (item.speed > 0 && item.delay < 0) {
            const dx::point destination{item.firstx,item.firsty};
            const float distance=destination.length();
            if (distance>0) { const float phase=std::fmod(time*item.speed/distance,2.0f); position=position+destination*(phase<=1?phase:2-phase); }
        } else if (item.speed > 0 && t > item.delay) {
            const dx::point first{item.firstx, item.firsty}, last{item.lastx, item.lasty};
            const float firsttime = first.length() / item.speed, secondtime = (last - first).length() / item.speed;
            float f = unit((t - item.delay) / firsttime);
            if (t - item.delay <= firsttime) position = position + first * (f * f);
            else { f = unit((t - item.delay - firsttime) / secondtime); position = position + first + (last - first) * (1 - (1 - f) * (1 - f)); }
        }
        world(item.sprite, position, std::lround(alpha * 31), item.angle);
    }
    gamevisuals::discs(game,world);
    gamevisuals::conveyors(game,world);
    for (int i = 0; i < game.definition.bubblecount; ++i) {
        const auto* app = game.ghostapp(2,i);
        const int alpha = std::lround(game.ghostalpha(2,i)*31);
        if (app) world(menuart::bubble1+i%3,game.definition.bubbles[i],alpha);
        if (!game.bubblesused[i]) {
            if (!app) world(menuart::bubble1 + i % 3, game.definition.bubbles[i],31,0,game.beltscale(0,i));
            world(menuart::bubble0, game.definition.bubbles[i],alpha,0,game.beltscale(0,i));
            if (app) gamevisuals::clouds(game,*app,game.definition.bubbles[i],alpha,false,world);
        }
    }
    for (int i = 0; i < game.definition.pumpcount; ++i) {
        const auto& pump = game.definition.pumps[i];
        const int phase = game.pumpages[i] * .016f / .05f;
        world(menuart::pump0 + 2 * (phase < 3 ? phase + 1 : 0), pump.position, 31, pump.angle,game.beltscale(5,i));
    }
    for (int i = 0; i < game.definition.spikecount; ++i) {
        const auto& spike = game.definition.spikes[i];
        const int sprite = spike.size == 5 ? menuart::electro0 + (game.electric[i] ? 1 + elapsed / 3 % 4 : 0) :
            spike.group >= 0 ? menuart::tool0 + spike.size - 1 : menuart::spike0 + (spike.size - 1) * 2;
        const auto center = game.spikeposition(i);
        world(sprite, center, 31, game.spikeangle(i));
        if (spike.group > 0) add(menuart::tool4 + (spike.group-1)*2 + (game.dragspike==i), wx(center.x), wy(center.y), {},
            game.spikenormal[i] ? GL_FLIP_H : GL_FLIP_NONE, 1, static_cast<int>(game.spikeangle(i)*32768/360));
    }
    for (int i = 0; i < game.definition.bouncercount; ++i) {
        const auto& item = game.definition.bouncers[i];
        const int frame = game.bounceages[i] * .016f / .04f;
        const auto* app = game.ghostapp(8,i);
        const int alpha = std::lround(game.ghostalpha(8,i)*31);
        if (app) gamevisuals::clouds(game,*app,item.position,alpha,true,world);
        world(menuart::bouncer0 + (item.size - 1) * 5 + (frame < 5 ? frame : 0), item.position + item.path.at(elapsed * .016f), alpha, item.path.angle(item.angle, elapsed * .016f),game.beltscale(2,i));
        if (app) gamevisuals::clouds(game,*app,item.position,alpha,false,world);
    }
    gamevisuals::mice(game,world);
    for (int i = 0; i < game.definition.hatcount; ++i) {
        const auto& hat = game.definition.hats[i];
        const auto position = hat.position + hat.path.at(elapsed * .016f) + dx::point{0, -.5f};
        const float angle = hat.path.angle(hat.angle, elapsed * .016f, hat.resetangle);
        const float hatscale=game.beltscale(3,i), size=hatscale==1?1:hatscale/.7f;
        world(menuart::hat0 + hat.group % 2, position, 31, angle,size);
        if (game.hatages[i] * .016f < .2f) world(menuart::hat2 + std::min(2, static_cast<int>(game.hatages[i] * .016f / .05f)), position, 31, angle,size);
    }
    gamevisuals::steam(game,false,world);
    gamevisuals::lanterns(game,menu.skins[0],world);
    gamevisuals::ghosts(game,world);
    for (int i = 0; i < game.definition.hookcount; ++i)
        if (game.definition.hooks[i].wheel) world(menuart::wheel0, game.anchors[i]);
    for (int i = 0; i < game.definition.hookcount; ++i) {
        const auto& hook = game.definition.hooks[i];
        if (hook.rail <= 0) continue;
        const float angle = hook.vertical ? 90 : 0;
        for (const auto& rail : menuart::rails) if (rail.length == static_cast<int>(hook.rail)) {
            world(rail.sprite, hook.anchor + dx::rotate({hook.rail * .5f - hook.offset - 3, 0}, angle), 31, angle);
            break;
        }
    }
    for (int i = 0; i < game.definition.hookcount; ++i) {
        const auto& rope = game.ropes[i];
        const float radius = game.definition.hooks[i].radius;
        const float alpha = (rope.attached < 0 ? 1 : 1-(elapsed-rope.attached)*.016f*1.5f)*game.ghostalpha(4,i);
        if (radius < 0 || alpha <= 0) continue;
        for (const auto& ring : menuart::circles) if (ring.length == static_cast<int>(radius)) {
            world(ring.sprite,game.anchors[i],std::max(1,static_cast<int>(alpha*31))); break;
        }
    }
    for (int i = 0; i < game.definition.hookcount; ++i) if (game.ghostapp(4,i))
        world(menuart::ghosthook0,game.anchors[i],std::lround(game.ghostalpha(4,i)*31));
    groundend = count;
    for (int i = 0; i < game.definition.hookcount; ++i) if (const auto* app = game.ghostapp(4,i)) {
        const int alpha = std::lround(game.ghostalpha(4,i)*31);
        world(menuart::ghosthook1,game.anchors[i],alpha);
        gamevisuals::clouds(game,*app,game.anchors[i],alpha,false,world);
    }
    for (int i = 0; i < game.definition.hookcount; ++i) if (game.definition.hooks[i].wheel) {
        const int angle = static_cast<int>(game.wheelangles[i] * 32768 / 360);
        add(menuart::wheel1, wx(game.anchors[i].x), wy(game.anchors[i].y), {}, GL_FLIP_NONE, game.wheelscale(i), angle);
        world(menuart::wheel0 + (game.dragwheel == i ? 2 : 3), game.anchors[i], 31, game.wheelangles[i]);
    }
    for (int i = 0; i < game.definition.hookcount; ++i) if (game.definition.hooks[i].rail > 0) {
        world(menuart::rail4, game.anchors[i], 31, game.definition.hooks[i].vertical ? 90 : 0);
        if (game.draghook == i) world(menuart::rail3, game.anchors[i], 31, game.definition.hooks[i].vertical ? 90 : 0);
    }
    for (int i = 0; i < game.definition.hookcount; ++i) {
        if (game.definition.hooks[i].route >= 0) {
            static constexpr int wings[] = {2,3,4,3};
            world(menuart::bee1,game.anchors[i],31,game.beeangles[i]);
            world(menuart::bee1 + wings[(static_cast<int>(elapsed*.016f/.03f)+i)%4]-1,game.anchors[i],31,game.beeangles[i]);
        }
    }
    for (int i = 0; i < 3; ++i) {
        const float timeout = game.definition.timeouts[i];
        if (timeout <= 0 || game.stars[i] || game.expired[i]) continue;
        world(menuart::timedstar20, game.starpositions[i]);
        const int phase = std::clamp(static_cast<int>(std::ceil((1 - game.ticks * .016f / timeout) * 32)), 1, 32);
        world(menuart::ring1 + phase - 1, game.starpositions[i]);
    }
    gamevisuals::light(game,false,world);
    if (game.definition.night) for (int i=0;i<3;++i) if (!game.stars[i] && !game.expired[i])
        world(menuart::nightstar0,game.starpositions[i],std::lround(game.lightalpha[i]*31));
    starback = count;
    if (game.definition.night) for (int i=0;i<3;++i) if (!game.stars[i] && !game.expired[i]) {
        world(menuart::nightstar1+(elapsed/3+i*5)%18,game.starpositions[i],std::lround((1-game.lightalpha[i])*31));
        const float age = (elapsed-game.lightchange[i])*.016f;
        if (game.lightchange[i]>1 && age<.25f) world((game.starlit[i]?menuart::nightstar25:menuart::nightstar19)+std::min(5,static_cast<int>(age/.05f)),game.starpositions[i]);
    }
    for (int i = 0; i < 3; ++i) {
        if (game.stars[i]) {
            const int frame = static_cast<int>((elapsed - game.collectedat[i]) * .016f / .05f);
            if (frame >= 0 && frame < 13) world(menuart::starburst0 + frame, game.starpositions[i]);
        }
    }
    starfront = count;
    if (game.split && game.failreason != 3) {
        for (int i = 0; i < 2; ++i) if (game.halfalive[i]) world(menuart::gamehalves[menu.skins[0]][i], game.bodies[i + 1].pos);
    }
    if (!game.split && !game.hidden() && menu.skins[0] > 0 && game.state != dx::outcome::won && game.failreason != 2 && game.failreason != 3) {
        const int px = wx(game.candy().pos.x), py = wy(game.candy().pos.y);
        for (int id : menuart::gamecandies[menu.skins[0]]) add(id, px, py);
    }
    if (game.mergeage * .016f < .25f) world(menuart::merge0 + static_cast<int>(game.mergeage * .016f / .05f), game.candy().pos);
    if (game.inlantern && game.captureage < .1f) {
        const float t = game.captureage/.1f;
        for (int id : menuart::gamecandies[menu.skins[0]]) world(id,game.candydraw,std::lround((1-t)*31),0,1-(1-.3f/.71f)*t);
    }
    gamevisuals::light(game,true,world);
    for (int part = 0; part < game.activecount(); ++part) {
        const int id = game.activeid(part);
        if (!game.available(id)) continue;
        if (game.bubblefor(id) >= 0) {
            world(menuart::bubble4 + static_cast<int>(elapsed * .016f / .05f) % 13, game.bodies[id].pos);
            if (const auto* app = game.ghostapp(2,game.bubblefor(id))) gamevisuals::clouds(game,*app,game.bodies[id].pos,31,false,world);
        }
    }
    if (game.popage * .016f < .6f) world(menuart::bubble18 + std::min(11, static_cast<int>(game.popage * .016f / .05f)), game.popposition);
    gamevisuals::steam(game,true,world);
    for (int i = 0; i < game.definition.hookcount; ++i) {
        const auto& rope = game.ropes[i];
        if (!game.definition.hooks[i].spider) continue;
        if (rope.spiderstate) {
            const float age = (elapsed-rope.spiderfall)*.016f;
            if (age > 1.3f) continue;
            const bool won = rope.spiderstate == 2;
            const float hop = won ? 70 : 50, direction = rope.spiderup ? -1 : 1;
            const float t = std::min(1.0f,age/.3f), fall = std::max(0.0f,age-.3f);
            auto position = rope.spiderorigin;
            const float first = won ? -10 : 0, peak = -direction*hop;
            position.y += first + (peak-first)*(1-(1-t)*(1-t)) + (direction*1440-peak)*fall*fall;
            world(menuart::spider11 + won,position,31,won?0:rope.spiderturn*std::min(1.0f,age));
            if (won) {
                position.y -= 5;
                if (game.split) world(menuart::gamehalves[menu.skins[0]][rope.candy-1],position);
                else for (int id : menuart::gamecandies[menu.skins[0]]) world(id,position);
            }
            continue;
        }
        if (rope.cut) continue;
        const float time = rope.attached < 0 ? 0 : (elapsed - rope.attached) * .016f;
        const int frame = time < .75f ? std::min(6, time < .25f ? static_cast<int>(time / .05f) : time < .65f ? 5 : 6) : 7 + static_cast<int>((time - .75f) / .1f) % 4;
        world(menuart::spider0 + frame, rope.spiderpos, 31, rope.spiderangle);
    }

    const auto& trail = trace::trail;
    auto px = [](float value) { return std::lround(128 + (value - 1280) * pixels); };
    auto py = [](float value) { return std::lround((value - cameray) * pixels); };
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
    // prepareoverlay adds the HUD/flaps before one combined cache update.
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
        points[i] = {128 + (work[0].x - 1280) * pixels, (work[0].y - cameray) * pixels};
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
    groundend = starback = starfront = 0;
    overlaystart = -1;
    add(menu.mode == ui::view::home ? menuart::titleback : menu.mode == ui::view::levels ? menuart::levelbacks[menu.pack] : menu.mode == ui::view::skins ? menuart::skinback : menuart::menuback, 128, 96);
    if (menu.mode != ui::view::skins) add(menuart::shadow, 128, 96, {}, GL_FLIP_NONE, (1781 * 2 * pixels) / 256, 4096 + (frame % 4500) * 32768 / 4500);
    switch (menu.mode) {
    case ui::view::home: {
        const auto& p=menuart::titlepositions;
        add(menuart::titlelogo,p[0][0],p[0][1]);
        add(menuart::titlecandies[menu.skins[0]],p[1][0],p[1][1]);
        if (menu.candyhint) add(menuart::titlehand,p[2][0]+std::lround(10*std::cos(menu.age*.087266f)*pixels*menuart::mainfit*menuart::titlezoom),p[2][1]);
        break;
    }
    case ui::view::packs: packs(menu); break;
    case ui::view::options: options(menu); break;
    case ui::view::skins: skins(menu); break;
    case ui::view::resetmenu: label(menu, menuart::RESET_TEXT, 128, 60); break;
    case ui::view::credits: {
        const auto& bounds = menuart::creditbounds;
        const int first = std::max(0, static_cast<int>(menu.creditoffset) / 96);
        const int last = std::min(static_cast<int>(std::size(menuart::credits[0])) - 1, static_cast<int>(menu.creditoffset + bounds[3]-bounds[1]) / 96);
        for (int i = first; i <= last; ++i) add(menuart::credits[menu.locale][i], bounds[0], bounds[1] + i * 96 - static_cast<int>(menu.creditoffset), {bounds[0], bounds[1], bounds[2], bounds[3]});
        break;
    }
    case ui::view::levels:
        for (int row = 0; row < 5; ++row) {
            for (int column = 0; column < 5; ++column) {
                const int px = x(824 + column * 228), py = y(203.5f + row * 258);
                const bool unlocked = menu.levelopen(row * 5 + column);
                add(unlocked ? menuart::level0 : menuart::level1, px, py);
                if (unlocked) {
                    add(menuart::level2 + menu.saves.active().levels[menu.pack * 25 + row * 5 + column].stars, px, py);
                    label(menu, menuart::number1 + row * 5 + column, px, py - 1);
                }
            }
        }
        label(menu, menuart::count0 + menu.totalstars(menu.pack), 231, 10);
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
        const float factor = menu.mode == ui::view::options && item.action != ui::action::back ? .85f : 1;
        add(pressed ? item.down : item.up, item.x, item.y, {}, item.action == ui::action::nextpack ? GL_FLIP_H : GL_FLIP_NONE, factor);
        if (item.label >= 0) {
            const int id=menuart::labels[menu.locale][item.label];
            const float scale=menu.mode==ui::view::languages?std::min(1.0f,(menuart::sprites[item.up].w-4.0f)/menuart::sprites[id].w):1;
            add(id,item.x,item.y,{},GL_FLIP_NONE,scale);
        }
        if (item.action == ui::action::music || item.action == ui::action::effects) {
            const bool enabled = item.action == ui::action::music ? menu.music : menu.effects;
            add(menuart::setting0 + item.argument, item.x, item.y, {}, GL_FLIP_NONE, factor, 0, enabled ? 31 : 16, enabled ? RGB15(31,31,31) : RGB15(15,15,15));
            if (!enabled) add(menuart::setting4, item.x + std::lround((item.argument == 2 ? 10 : 7)*menuart::settingszoom*factor), item.y + 6, {}, GL_FLIP_NONE, factor);
        }
        ++index;
    }
    upload();
    glBegin2D();
    render();
    glEnd2D();
    present();
}

void uppermenu(const ui::controller& menu) {
    upper::cutout(true);
    if (menu.mode!=ui::view::skins)
        upper::sprite(menuart::shadow,128,96,(1781*2*pixels)/256,(1781*2*pixels)/256,
                      4096+(frame%4500)*32768/4500);
    upper::cutout(false);
}

void paintupper(bool ground,int stars) {
    const int first=ground?0:stars==1?groundend:stars==2?starback:starfront;
    const int last=ground?groundend:stars==1?starback:stars==2?starfront:count;
    for (int i=first;i<last;++i) {
        const auto& item=commands[i];
        const upper::clip bounds{item.bounds.left,item.bounds.top,item.bounds.right,item.bounds.bottom};
        if (item.id<0) upper::rect(bounds,item.color,item.alpha);
        else upper::sprite(item.id,item.x,item.y,item.scale,item.vertical,item.angle,item.flip,item.alpha,item.color,bounds);
    }
}

void upperoverlay(const ui::controller& menu,const dx::simulation& game) {
    upper::shade(31);
    upper::transient(menu.door || menu.mode==ui::view::results);
    if (menu.mode==ui::view::playing || menu.mode==ui::view::paused || (menu.mode==ui::view::results && menu.age<32)) {
        for (int i=0;i<3;++i) {
            const int frame=menu.starage[i]<0?0:std::min(10,1+menu.starage[i]/3);
            upper::sprite(menuart::hud1+frame,80+i*48,82,2.5f,2.5f);
        }
        char value[24]; std::snprintf(value,sizeof(value),"%d",ui::controller::points(game.count,game.ticks));
        constexpr float zoom=1.65f;
        float width=0;
        for (const char* p=value;*p;++p) width+=menuart::scoredigits[*p-'0'].advance*zoom;
        for (int pass=0;pass<5;++pass) {
            float left=128-width/2;
            const int dx=pass==0?-1:pass==1?1:0, dy=pass==2?-1:pass==3?1:0;
            for (const char* p=value;*p;++p) {
                const auto& glyph=menuart::scoredigits[*p-'0'];
                upper::sprite(glyph.sprite,std::lround(left+glyph.advance*zoom/2)+dx,120+dy,zoom,zoom,0,0,31,pass==4?0xffff:0x8000);
                left+=glyph.advance*zoom;
            }
        }
    }
    count=groundend=starback=starfront=0;
    overlaystart=-1;
    if (menu.mode==ui::view::results) doors(menu.age*.016f/.5f,false,false,menu.pack);
    if (menu.door) doors(menu.doorframe*.016f/.5f,menu.door==1,false,menu.pack);
    paintupper();
    if (menu.white()>0) upper::rect({},RGB15(31,31,31),std::max(1,static_cast<int>(std::lround(menu.white()*31))));
}

void render(bool overlay, bool ground, int stars) {
    DS_SCOPE(render);
    const int first = ground ? 0 : overlay ? overlaystart : stars == 1 ? groundend : stars == 2 ? starback : starfront;
    const int last = ground ? groundend : stars == 1 ? starback : stars == 2 ? starfront : !overlay && overlaystart >= 0 ? overlaystart : count;
    for (int i = first; i < last; ++i) {
        const command& item = commands[i];
        if (!visibility[i]) continue;
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
            glPushMatrix();
            glTranslatef32(item.x, item.y, 0);
            glRotateZi(item.angle);
            glSpriteScaleXY(std::lround(source.ox * item.scale), std::lround(source.oy * item.vertical),
                floattof32(item.scale), floattof32(item.vertical), item.flip, &image);
            glPopMatrix(1);
        } else {
            int px = item.x + std::lround(source.ox * item.scale), py = item.y + std::lround(source.oy * item.vertical);
            if (px >= item.bounds.left && py >= item.bounds.top &&
                px + source.w * item.scale <= item.bounds.right && py + source.h * item.vertical <= item.bounds.bottom) {
                if (item.scale == 1 && item.vertical == 1) glSprite(px,py,item.flip,&image);
                else glSpriteScaleXY(px,py,floattof32(item.scale),floattof32(item.vertical),item.flip,&image);
                continue;
            }
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
