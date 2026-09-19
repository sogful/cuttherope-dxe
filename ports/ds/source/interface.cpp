#include "interface.hpp"
#include <algorithm>
#include <cmath>

namespace ui {
int controller::points(int stars, int ticks) {
    return static_cast<int>(std::ceil(stars * 1000.0f + std::max(0.0f, 30.0f - ticks * .016f) * 100.0f));
}

int controller::buttons(button* out) const {
    int count = 0;
    auto add = [&](action id, int x, int y, int w, int h, const char* label, bool enabled = true) {
        out[count++] = {id, x, y, w, h, label, enabled};
    };
    switch (mode) {
    case view::playing:
        add(action::restart, 178, 14, 28, 28, "");
        add(action::pause, 227, 14, 54, 28, "");
        break;
    case view::paused:
        add(action::resume, 128, 51, 112, 28, "Continue");
        add(action::restart, 65, 85, 112, 28, "Replay");
        add(action::skip, 191, 85, 112, 28, "Skip level", false);
        add(action::levels, 65, 118, 112, 28, "Level select");
        add(action::home, 191, 118, 112, 28, "Main menu");
        add(action::effects, 82, 157, 54, 28, "");
        add(action::music, 174, 157, 54, 28, "");
        break;
    case view::results:
    case view::failure:
        add(action::restart, 44, 160, 70, 30, "Replay");
        add(action::next, 128, 160, 70, 30, "Next", false);
        add(action::levels, 212, 160, 70, 30, "Menu");
        break;
    case view::levels:
        add(action::play, 128, 83, 68, 68, "1-1");
        add(action::back, 44, 166, 70, 30, "Back");
        add(action::home, 204, 166, 70, 30, "Home");
        break;
    case view::home:
        add(action::levels, 128, 76, 112, 28, "Play");
        add(action::effects, 82, 123, 54, 28, "");
        add(action::music, 174, 123, 54, 28, "");
        break;
    }
    return count;
}

void controller::enter(view target) {
    mode = target;
    age = focus = 0;
    pressed = armed = -1;
    captured = true;
    gameTouch = false;
}

void controller::activate(action command) {
    clicked = true;
    switch (command) {
    case action::pause: enter(view::paused); break;
    case action::resume: enter(view::playing); break;
    case action::restart:
    case action::play:
        reset = true;
        resultage = score = 0;
        for (int& value : starage) value = -1;
        enter(view::playing);
        break;
    case action::levels:
        returnview = mode;
        enter(view::levels);
        break;
    case action::home: enter(view::home); break;
    case action::back: enter(returnview); break;
    case action::effects: effects = !effects; break;
    case action::music: music = !music; break;
    default: clicked = false; break;
    }
}

void controller::update(const dx::simulation& game, input current) {
    reset = clicked = gameTouch = false;
    button list[8];
    const int count = buttons(list);
    const bool gameplay = mode == view::playing && game.state == dx::outcome::playing;
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
        if (gameplay) activate(action::pause);
        else if (mode == view::paused) activate(action::resume);
    } else if (current.keys & cancel) {
        if (mode == view::paused) activate(action::resume);
        else if (mode == view::levels) activate(action::back);
        else if (mode == view::results || mode == view::failure) activate(action::levels);
        else if (gameplay) activate(action::pause);
    } else if (current.keys & (previous | following)) {
        if (mode != view::playing) {
            const int direction = current.keys & previous ? -1 : 1;
            do { focus = (focus + direction + count) % count; } while (!list[focus].enabled);
        }
    } else if (current.keys & accept) {
        if (gameplay) activate(action::restart);
        else if (mode != view::playing) activate(list[focus].id);
    }
    gameTouch = current.touch && !captured && mode == view::playing && !reset && game.state == dx::outcome::playing;
}

void controller::advance(const dx::simulation& game) {
    ++age;
    if (mode != view::playing) return;
    for (int i = 0; i < 3; ++i) {
        if (game.stars[i]) starage[i] = std::min(starage[i] + 1, 30);
    }
    if (game.state == dx::outcome::playing) return;
    if (++resultage < 60) return;
    score = points(game.count, game.resulttick);
    if (game.state == dx::outcome::won) {
        bestscore = std::max(bestscore, score);
        beststars = std::max(beststars, game.count);
    }
    enter(game.state == dx::outcome::won ? view::results : view::failure);
}
}
