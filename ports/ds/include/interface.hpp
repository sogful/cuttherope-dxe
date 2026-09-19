#pragma once
#include "simulation.hpp"

namespace ui {
enum class view { playing, paused, results, failure, levels, home };
enum class action { none, pause, resume, restart, skip, levels, home, effects, music, play, back, next };
enum key { accept = 1, cancel = 2, start = 4, previous = 8, following = 16 };
struct input { int x = 0, y = 0, keys = 0; bool touch = false; };
struct button {
    action id;
    int x, y, width, height;
    const char* label;
    bool enabled = true;
    bool contains(int px, int py) const {
        return px >= x - width / 2 && px < x + (width + 1) / 2 &&
               py >= y - height / 2 && py < y + (height + 1) / 2;
    }
};
class controller {
public:
    view mode = view::playing;
    bool effects = true, music = true, reset = false, clicked = false, gameTouch = false;
    int focus = 0, pressed = -1, age = 0, score = 0, bestscore = 0, beststars = 0;
    int starage[3] = {-1, -1, -1};
    int buttons(button* output) const;
    void update(const dx::simulation& game, input current);
    void advance(const dx::simulation& game);
    static int points(int stars, int ticks);
private:
    bool held = false, captured = false;
    int armed = -1, resultage = 0;
    view returnview = view::paused;
    void enter(view target);
    void activate(action command);
};
}
