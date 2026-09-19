#pragma once
#include "simulation.hpp"
#include "scroller.hpp"
#include "progress.hpp"

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
    int locale = 0, pack = 0;
    float packposition = 0, creditoffset = 0;
    bool clickcut = false, keyboard = false, autoscroll = true;
    int settled = 100;
    progress::store saves;
    std::array<int, 4> skins{};
    std::array<float, 4> skinoffsets{};
    int skintab = 0, skinage = 0, notice = 0;
    float skinvelocity = 0;
    bool candyhint = true;
    bool unlockall() const { return saves.unlocked; }
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
