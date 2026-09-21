#include "interface.hpp"
#include <algorithm>
#include <cmath>
#include "menuassets.hpp"

namespace ui {
static constexpr int creditheight = menuart::creditbounds[3]-menuart::creditbounds[1];
void controller::initialize(const char* directory) {
    saves.initialize(directory);
    const auto& settings = saves.preferences;
    effects = settings.effects; music = settings.music; locale = settings.locale; clickcut = settings.clickcut;
    for (int i = 0; i < 4; ++i) skins[i] = settings.skins[i];
    candyhint = skins[0] == 0;
    best();
}
void controller::best() {
    const auto& saved = saves.active().levels[levelid()];
    bestscore = saved.score; beststars = saved.stars;
}
int controller::totalstars(int box) const {
    int total = 0;
    const int begin = box < 0 ? 0 : box * 25, end = box < 0 ? 425 : begin + 25;
    for (int i = begin; i < end; ++i) total += saves.active().levels[i].stars;
    return total;
}
bool controller::packopen(int box) const {
    return box >= 0 && box < menuart::boxcount && (unlockall() || totalstars() >= menuart::thresholds[box]);
}
bool controller::levelopen(int index) const {
    if (!packopen(pack) || index < 0 || index >= 25) return false;
    const auto& records = saves.active().levels;
    return unlockall() || index == 0 || records[pack * 25 + index].completed || (records[pack * 25 + index - 1].completed & 1);
}
bool controller::hasnext() const { return levelid() < menuart::playableboxes * 25 - 1 && (level < 24 || packopen(pack + 1)); }
void controller::persist() {
    auto& settings = saves.preferences;
    settings.effects = effects; settings.music = music; settings.locale = locale; settings.clickcut = clickcut;
    for (int i = 0; i < 4; ++i) settings.skins[i] = skins[i];
    saves.save();
}
void controller::suspend(input current) {
    reset = clicked = gameTouch = false;
    held = current.touch;
    captured = true;
    armed = pressed = -1;
}
int controller::skinhit(int px, int py) const {
    if (py < menuart::skintop || py >= menuart::skinbottom) return -1;
    const float x = px - menuart::skinleft, y = py - menuart::skintop + skinoffsets[skintab];
    if (x < 0 || y < 0) return -1;
    const int column = x / menuart::skinpitch, row = y / menuart::skinrow;
    const float offset = y - row * menuart::skinrow;
    const float center = (menuart::skinrow - 10 * menuart::fit * 192 / 1440) / 2;
    if (column > 3 || x - column * menuart::skinpitch >= menuart::skinwidth ||
        offset < center - menuart::skinheight / 2 || offset >= center + menuart::skinheight / 2) return -1;
    const int index = row * 4 + column;
    return index < menuart::skincounts[skintab] ? index : -1;
}
int controller::pressedskin() const {
    const int index = skinhit(lastx, lasty);
    return mode == view::skins && held && !dragging && index == skinhit(originx, originy) ? index : -1;
}
int controller::points(int stars, int ticks) {
    return static_cast<int>(std::ceil(stars * 1000.0f + std::max(0.0f, 30.0f - ticks * .016f) * 100.0f));
}

int controller::buttons(button* out) const {
    int count = 0;
    if (frontend()) {
        if (mode == view::levels) {
            for (int i = 0; i < 25; ++i) {
                const int px = std::lround(128 + (824 + (i % 5) * 228 - 1280) * menuart::fit * (192.0f / 1440));
                const int py = std::lround(96 + (203.5f + (i / 5) * 258 - 720) * menuart::fit * (192.0f / 1440));
                out[count++] = {pack < menuart::playableboxes ? action::play : action::unavailable, px, py, 29, 29, "", levelopen(i), i};
            }
        }
        for (const auto& item : menuart::controls) {
            if (item.view != mode) continue;
            const bool enabled = item.action != action::openpack || packopen(pack);
            out[count++] = {item.action, item.x, item.y, item.w, item.h, "", enabled, item.argument};
        }
        return count;
    }
    auto add = [&](action id, int x, int y, int w, int h, const char* label, bool enabled = true) {
        out[count++] = {id, x, y, w, h, label, enabled};
    };
    switch (mode) {
    case view::playing:
        add(action::restart, menuart::hudpositions[locale][2], menuart::hudpositions[locale][3], menuart::sprites[menuart::hud0].w+2, menuart::sprites[menuart::hud0].h+2, "");
        add(action::pause, menuart::hudpositions[locale][0], menuart::hudpositions[locale][1], menuart::sprites[menuart::hud0+menuart::hudquads[locale]].w+2, menuart::sprites[menuart::hud0+menuart::hudquads[locale]].h+2, "");
        break;
    case view::paused:
        for (int i = 0; i < 6; ++i) {
            static constexpr action actions[] = {action::resume, action::skip, action::levels, action::home, action::effects, action::music};
            add(actions[i], menuart::pausepositions[i][0], menuart::pausepositions[i][1], i < 4 ? 104 : 49, 26, "");
        }
        break;
    case view::results:
    case view::failure:
        add(action::restart, menuart::resultanchors[11][0], menuart::resultanchors[11][1], 54, 24, "");
        add(action::next, menuart::resultanchors[10][0], menuart::resultanchors[10][1], 54, 24, "", mode == view::results && hasnext());
        add(action::levels, menuart::resultanchors[9][0], menuart::resultanchors[9][1], 54, 24, "");
        break;
    default: break;
    }
    return count;
}

void controller::enter(view target) {
    if (mode == view::packs && strip.down) { strip.release(); strip.moveto(strip.selected); }
    mode = target;
    age = focus = 0;
    pressed = armed = -1;
    captured = true;
    gameTouch = false;
    keyboard = dragging = false;
    if (target == view::credits) { creditoffset = 0; autoscroll = true; }
}

void controller::activate(action command, int argument) {
    clicked = true;
    switch (command) {
    case action::pause: enter(view::paused); break;
    case action::resume: enter(view::playing); break;
    case action::skip:
        if (mode != view::paused) break;
        if (level == 24) { activate(action::levels); break; }
        saves.unlock(levelid() + 1);
        activate(action::next);
        door = doorframe = 0;
        break;
    case action::restart:
        if (mode != view::results) {
            flash = 1; flashframe = resultage = 0;
            replaypanel = false;
            enter(view::playing);
            break;
        }
        [[fallthrough]];
    case action::play:
    case action::next:
        if (command == action::next) {
            if (!hasnext()) break;
            if (++level == 25) { level = 0; ++pack; strip.moveto(pack); packposition = pack; }
        } else if (command == action::play) level = argument;
        best();
        replaypanel = mode == view::results;
        resulttime = age;
        door = command != action::restart || mode == view::results ? 1 : 0;
        doorframe = 0;
        reset = true;
        resultage = 0;
        flash = flashframe = 0;
        if (!replaypanel) score = 0;
        for (int& value : starage) value = -1;
        enter(view::playing);
        break;
    case action::levels:
        returnview = mode;
        if (!frontend() && mode != view::results) { door = 2; doorframe = 0; destination = view::levels; }
        else enter(view::levels);
        break;
    case action::home:
        if (!frontend()) { door = 2; doorframe = 0; destination = view::home; }
        else enter(view::home);
        break;
    case action::back:
        if (mode == view::packs || mode == view::options) enter(view::home);
        else if (mode == view::levels) enter(view::packs);
        else if (mode == view::skins) enter(view::home);
        else if (frontend()) enter(view::options);
        else enter(returnview);
        break;
    case action::effects: effects = !effects; break;
    case action::music: music = !music; break;
    case action::packs: enter(view::packs); break;
    case action::options: enter(view::options); break;
    case action::languages: enter(view::languages); break;
    case action::credits: enter(view::credits); break;
    case action::resetmenu: enter(view::resetmenu); break;
    case action::erase: saves.clear(); bestscore = beststars = 0; enter(view::options); break;
    case action::unlock:
        saves.toggle();
        best();
        break;
    case action::skinmenu: candyhint = false; enter(view::skins); break;
    case action::skintab: skintab = argument; skinage = 0; skinvelocity = 0; break;
    case action::skin: skins[skintab] = argument; skinage = 0; break;
    case action::unavailable: notice = 120; break;
    case action::clickcut: clickcut = !clickcut; break;
    case action::language: locale = argument; break;
    case action::previouspack: strip.moveto(pack - 1); pack = strip.selected; settled = 100; break;
    case action::nextpack: strip.moveto(pack + 1); pack = strip.selected; settled = 100; break;
    case action::openpack:
        if (packopen(pack) && !strip.moving) {
            if (std::abs(strip.x + pack * 640) < 1) enter(view::levels);
            else strip.moveto(pack);
        }
        break;
    default: clicked = false; break;
    }
}

void controller::update(const dx::simulation& game, input current) {
    reset = clicked = gameTouch = false;
    if (blocked()) { suspend(current); return; }
    if (frontend()) { frontinput(current); return; }
    button list[32];
    const int count = buttons(list);
    const bool ingame = mode == view::playing;
    const bool gameplay = ingame && game.state == dx::outcome::playing;
    if (current.touch && !held) {
        armed = -1;
        captured = !gameplay;
        for (int i = 0; i < count; ++i) {
            if (!list[i].contains(current.x, current.y)) continue;
            captured = true;
            if (list[i].enabled) focus = armed = i;
            break;
        }
    }
    pressed = current.touch && armed >= 0 && list[armed].contains(current.x, current.y) ? armed : -1;
    if (!current.touch && held) {
        const int selected = armed;
        armed = pressed = -1;
        if (selected >= 0 && list[selected].contains(current.x, current.y)) activate(list[selected].id);
    }
    if (!current.touch && !held) captured = false;
    held = current.touch;
    if (current.keys & start) {
        if (ingame) activate(action::pause);
        else if (mode == view::paused) activate(action::resume);
    } else if (current.keys & cancel) {
        if (mode == view::paused) activate(action::resume);
        else if (mode == view::levels) activate(action::back);
        else if (mode == view::results || mode == view::failure) activate(action::levels);
        else if (ingame) activate(action::pause);
    } else if (current.keys & (previous | following)) {
        if (mode != view::playing) {
            const int direction = current.keys & previous ? -1 : 1;
            do { focus = (focus + direction + count) % count; } while (!list[focus].enabled);
        }
    } else if (current.keys & accept) {
        if (ingame) activate(action::restart);
        else if (mode != view::playing) activate(list[focus].id);
    }
    gameTouch = current.touch && !captured && mode == view::playing && !reset && game.state == dx::outcome::playing;
}

void controller::frontinput(input current) {
    strip.count = menuart::boxcount;
    button list[32];
    const int count = buttons(list);
    if (current.touch && !held) {
        keyboard = dragging = false;
        originx = lastx = current.x;
        originy = lasty = current.y;
        armed = -1;
        if (mode == view::packs && current.x >= 38 && current.x < 218) strip.begin(current.x / (menuart::fit * (192.0f / 1440) * menuart::boxzoom));
        if (mode == view::credits) autoscroll = false;
        if (mode == view::skins) skinvelocity = 0;
        for (int i = 0; i < count; ++i) {
            if (list[i].enabled && list[i].contains(current.x, current.y)) {
                armed = focus = i;
                break;
            }
        }
    }
    if (current.touch && held) {
        const bool strip = mode == view::packs && originx >= 38 && originx < 218;
        const bool credits = mode == view::credits && originx >= menuart::creditbounds[0] && originx < menuart::creditbounds[2] && originy >= menuart::creditbounds[1] && originy < menuart::creditbounds[3];
        const bool skins = mode == view::skins && originy >= menuart::skintop && originy < menuart::skinbottom;
        if ((strip || credits || skins) && (std::abs(current.x - originx) > 3 || std::abs(current.y - originy) > 3)) dragging = true;
        if (dragging) {
            armed = -1;
            if (strip) this->strip.drag(current.x / (menuart::fit * (192.0f / 1440) * menuart::boxzoom));
            if (credits) creditoffset = std::clamp(creditoffset + lasty - current.y, 0.0f, std::max(0.0f, static_cast<float>(menuart::creditheights[locale] - creditheight)));
            if (skins) {
                skinvelocity = (lasty - current.y) * .5f + skinvelocity * .5f;
                skinoffsets[skintab] = std::clamp(skinoffsets[skintab] + lasty - current.y, 0.0f, menuart::skinmax[skintab]);
            }
        }
    }
    pressed = current.touch && armed >= 0 && list[armed].contains(current.x, current.y) ? armed : -1;
    if (!current.touch && held) {
        const int selected = armed;
        armed = pressed = -1;
        if (mode == view::packs && strip.down) {
            strip.release();
            pack = strip.selected;
        }
        if (dragging && mode == view::packs) settled = 100;
        else if (selected >= 0 && list[selected].contains(current.x, current.y)) activate(list[selected].id, list[selected].argument);
        else if (mode == view::skins && !dragging) {
            const int index = skinhit(current.x, current.y);
            if (index >= 0 && index == skinhit(originx, originy)) activate(action::skin, index);
        }
        else if (mode == view::packs && current.x >= 38 && current.x < 218 && std::abs(current.y-96) < 45*menuart::boxzoom) {
            strip.moveto(static_cast<int>(std::round(packposition + (current.x - 128) / (640 * menuart::fit * (192.0f / 1440) * menuart::boxzoom))));
            pack = strip.selected;
            settled = 100;
        }
        dragging = false;
    }
    held = current.touch;
    lastx = current.x;
    lasty = current.y;
    if (current.keys & cancel) {
        if (mode != view::home) activate(action::back);
    } else if (current.keys & (previous | following)) {
        keyboard = true;
        const int direction = current.keys & previous ? -1 : 1;
        if (mode == view::packs) activate(direction < 0 ? action::previouspack : action::nextpack);
        else if (mode == view::credits) {
            autoscroll = false;
            creditoffset = std::clamp(creditoffset + direction * 8.0f, 0.0f, std::max(0.0f, static_cast<float>(menuart::creditheights[locale] - creditheight)));
        } else if (mode == view::skins) {
            const int chosen = std::clamp(skins[skintab] + direction, 0, menuart::skincounts[skintab] - 1);
            activate(action::skin, chosen);
            skinoffsets[skintab] = std::clamp(chosen / 4 * menuart::skinrow, 0.0f, menuart::skinmax[skintab]);
        } else {
            do { focus = (focus + direction + count) % count; } while (!list[focus].enabled);
        }
    } else if (current.keys & accept) {
        if (mode == view::packs) activate(action::openpack);
        else activate(list[focus].id, list[focus].argument);
    }
}

void controller::advance(const dx::simulation& game) {
    if (flash) {
        if (++flashframe * .016f >= .15f) {
            if (flash == 1) {
                flash = 2; flashframe = 0; reset = true;
                resultage = age = score = 0;
                for (int& value : starage) value = -1;
            } else { flash = flashframe = 0; }
        }
        return;
    }
    if (door) {
        if (++doorframe >= 32) { const int previous = door; door = 0; if (previous == 2) enter(destination); }
        return;
    }
    ++age;
    ++skinage;
    if (notice > 0) --notice;
    if (mode == view::skins && !held) {
        skinoffsets[skintab] = std::clamp(skinoffsets[skintab] + skinvelocity, 0.0f, menuart::skinmax[skintab]);
        skinvelocity *= .88f;
        if (std::abs(skinvelocity) < .05f) skinvelocity = 0;
    }
    if (mode == view::packs) {
        if (strip.update(.016f)) settled = 0;
        else ++settled;
        packposition = -strip.x / 640;
    }
    if (mode == view::credits && autoscroll) creditoffset = std::min(creditoffset + .75f * (192.0f / 1440), std::max(0.0f, static_cast<float>(menuart::creditheights[locale] - creditheight)));
    if (mode != view::playing) return;
    for (int i = 0; i < 3; ++i) {
        if (game.stars[i]) starage[i] = std::min(starage[i] + 1, 30);
    }
    if (game.state == dx::outcome::playing) return;
    if (++resultage < (game.state == dx::outcome::won ? 125 : 63)) return;
    if (game.state == dx::outcome::lost) { activate(action::restart); return; }
    score = points(game.count, game.resulttick);
    elapsed = game.resulttick;
    resultstars = game.count;
    improved = (bestscore > 0 && score > bestscore) || (beststars > 0 && game.count > beststars);
    if (game.state == dx::outcome::won) {
        bestscore = std::max(bestscore, score);
        beststars = std::max(beststars, game.count);
        saves.complete(levelid(), bestscore, beststars);
    }
    enter(game.state == dx::outcome::won ? view::results : view::failure);
}
}
