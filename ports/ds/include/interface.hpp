#pragma once
#include "simulation.hpp"
#include "scroller.hpp"
#include "progress.hpp"
#include <algorithm>

namespace ui {
enum class view { playing, paused, results, failure, levels, home, packs, options, languages, credits, resetmenu, skins };
enum class action { none, pause, resume, restart, skip, levels, home, effects, music, play, back, next,
                    packs, options, languages, credits, resetmenu, erase, clickcut, language, previouspack, nextpack, openpack,
                    unlock, skinmenu, skintab, skin, unavailable };
enum key { accept = 1, cancel = 2, start = 4, previous = 8, following = 16 };
struct input { int x = 0, y = 0, keys = 0; bool touch = false; };
struct button {
    action id;
    int x, y, width, height;
    const char* label;
    bool enabled = true;
    int argument = 0;
    bool contains(int px, int py) const {
        return px >= x - width / 2 && px < x + (width + 1) / 2 &&
               py >= y - height / 2 && py < y + (height + 1) / 2;
    }
};
class controller {
public:
    view mode = view::home;
    bool effects = true, music = true, reset = false, clicked = false, gameTouch = false;
    int focus = 0, pressed = -1, age = 0, score = 0, bestscore = 0, beststars = 0;
    int starage[3] = {-1, -1, -1};
    int locale = 0, pack = 0, level = 0;
    float packposition = 0, creditoffset = 0;
    bool clickcut = false, keyboard = false, autoscroll = true;
    int settled = 100;
    progress::store saves;
    std::array<int, 4> skins{};
    std::array<float, 4> skinoffsets{};
    int skintab = 0, skinage = 0, notice = 0;
    float skinvelocity = 0;
    bool candyhint = true;
    int door = 0, doorframe = 0, elapsed = 0, resultstars = 0;
    int flash = 0, flashframe = 0;
    bool improved = false;
    bool replaypanel = false;
    int resulttime = 0;
    view destination = view::levels;
    bool blocked() const { return flash != 0 || door != 0 || (mode == view::results && age < 32); }
    float white() const { return flash == 1 ? std::min(1.0f, flashframe * .016f / .15f) : flash == 2 ? std::max(0.0f, 1 - flashframe * .016f / .15f) : 0; }
    bool unlockall() const { return saves.unlocked; }
    int levelid() const { return pack * 25 + level; }
    int totalstars(int box = -1) const;
    bool packopen(int box) const;
    bool levelopen(int index) const;
    bool hasnext() const { return levelid() < 149 && (level < 24 || packopen(pack + 1)); }
    void best();
    void initialize(const char* directory);
    void persist();
    void suspend(input current);
    int skinhit(int x, int y) const;
    int pressedskin() const;
    bool frontend() const { return mode == view::levels || mode >= view::home; }
    int buttons(button* output) const;
    void update(const dx::simulation& game, input current);
    void advance(const dx::simulation& game);
    static int points(int stars, int ticks);
private:
    bool held = false, captured = false;
    int armed = -1, resultage = 0;
    view returnview = view::paused;
    void enter(view target);
    void activate(action command, int argument = 0);
    void frontinput(input current);
    int originx = 0, originy = 0, lastx = 0, lasty = 0;
    bool dragging = false;
    scroller strip;
};
}
