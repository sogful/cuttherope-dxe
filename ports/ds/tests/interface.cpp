#include "interface.hpp"
#include "level.hpp"
#include <cassert>
#include <cstdio>

int main() {
    dx::simulation game;
    game.reset(dx::firstlevel);
    ui::controller menu;
    auto pen = [&](int x, int y, bool held) { menu.update(game, {x, y, 0, held}); };
    auto tap = [&](int x, int y) { pen(x, y, true); pen(x, y, false); pen(x, y, false); };
    auto key = [&](int value) { menu.update(game, {0, 0, value, false}); };
    pen(227, 14, true);
    pen(100, 40, true);
    assert(!menu.gameTouch && menu.pressed == -1);
    pen(100, 40, false);
    assert(menu.mode == ui::view::playing);
    pen(100, 40, true);
    assert(menu.gameTouch);
    key(ui::start);
    assert(menu.mode == ui::view::paused && !menu.gameTouch);
    pen(128, 51, true);
    assert(menu.mode == ui::view::paused);
    pen(128, 51, false);
    assert(menu.mode == ui::view::playing && !menu.gameTouch);
    tap(227, 14);
    assert(menu.mode == ui::view::paused);
    tap(191, 85);
    assert(menu.mode == ui::view::paused && !menu.reset);
    tap(82, 157);
    tap(174, 157);
    assert(!menu.effects && !menu.music);
    key(ui::following);
    assert(menu.focus == 0);
    key(ui::following);
    assert(menu.focus == 1);
    key(ui::following);
    assert(menu.focus == 3);
    key(ui::accept);
    assert(menu.mode == ui::view::levels);
    key(ui::cancel);
    assert(menu.mode == ui::view::paused);
    tap(191, 118);
    assert(menu.mode == ui::view::home);
    key(ui::accept);
    assert(menu.mode == ui::view::levels);
    key(ui::accept);
    assert(menu.mode == ui::view::playing && menu.reset && !menu.effects && !menu.music);
    menu.update(game, {});
    assert(!menu.reset);
    game.state = dx::outcome::won;
    game.resulttick = 500;
    game.count = 3;
    game.stars = {true, true, true};
    for (int i = 0; i < 59; ++i) menu.advance(game);
    assert(menu.mode == ui::view::playing);
    menu.advance(game);
    assert(menu.mode == ui::view::results && menu.score == 5200 && menu.bestscore == 5200 && menu.beststars == 3);
    tap(128, 160);
    assert(menu.mode == ui::view::results);
    key(ui::following);
    assert(menu.focus == 2);
    key(ui::previous);
    assert(menu.focus == 0);
    key(ui::accept);
    assert(menu.reset && menu.mode == ui::view::playing && menu.starage[0] == -1 && menu.bestscore == 5200);
    game.reset(dx::firstlevel);
    game.state = dx::outcome::lost;
    for (int i = 0; i < 60; ++i) menu.advance(game);
    assert(menu.mode == ui::view::failure && menu.bestscore == 5200);
    key(ui::cancel);
    assert(menu.mode == ui::view::levels);
    assert(ui::controller::points(3, 0) == 6000);
    assert(ui::controller::points(2, 2000) == 2000);
    assert(ui::controller::points(0, 1875) == 0);
    std::puts("PASS: UI capture/cancel, pause/resume, disabled actions, audio toggles, focus, navigation, win/loss, scoring, session best");
}
