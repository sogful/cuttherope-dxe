#include "simulation.hpp"
#include "level.hpp"
#include <cassert>
#include <cstdio>

int main() {
    dx::simulation game;
    game.reset(dx::firstlevel);
    std::printf("{\"samples\":[");
    for (int tick = 1; tick <= 120; ++tick) {
        game.tick();
        if (tick == 1 || tick % 15 == 0) {
            std::printf("%s{\"tick\":%d,\"x\":%.8f,\"y\":%.8f}", tick == 1 ? "" : ",", tick, game.candy().pos.x, game.candy().pos.y);
        }
    }
    assert(game.state == dx::outcome::playing && game.count == 0);
    assert(!game.swipe({900, 300}, {1000, 300}));
    assert(!game.swipe({1280, 300}, {1280, 300}));
    assert(game.swipe({1200, 300}, {1340, 300}));
    assert(!game.swipe({1200, 300}, {1340, 300}));
    assert(game.ropes[0].pending >= 0);
    game.tick();
    game.tick();
    assert(game.ropes[0].pending >= 0);
    game.tick();
    assert(game.ropes[0].pending == -1);
    for (int tick = 0; tick < 240; ++tick) game.tick();
    assert(game.state == dx::outcome::won && game.count == 3);
    assert(game.collectedat[0] < game.collectedat[1] && game.collectedat[1] < game.collectedat[2]);
    assert(game.collectedat[2] < game.resulttick);
    const dx::point won = game.candy().pos;
    const int wontick = game.resulttick;
    game.tick();
    assert(game.candy().pos.x == won.x && game.candy().pos.y == won.y);
    game.reset(dx::firstlevel);
    assert(game.count == 0 && game.state == dx::outcome::playing && !game.ropes[0].cut && game.ticks == 0);
    assert(game.swipe({1200, 300}, {1340, 300}));
    for (int tick = 0; tick < 180; ++tick) game.tick();
    assert(game.state == dx::outcome::won && game.count == 3);
    dx::level missing = dx::firstlevel;
    missing.target.x += 600;
    game.reset(missing);
    game.sever(0, 0);
    for (int tick = 0; tick < 300; ++tick) game.tick();
    assert(game.state == dx::outcome::lost);
    game.reset(dx::firstlevel);
    for (int tick = 0; tick < 3600; ++tick) game.tick();
    assert(game.state == dx::outcome::playing);
    assert(std::isfinite(game.candy().pos.x) && std::isfinite(game.candy().pos.y));
    assert(!game.tap({1400, 300}));
    assert(game.tap({1280, 300}));
    assert(!game.tap({1280, 300}));
    assert(game.ropes[0].pending >= 0);
    std::printf("],\"winTick\":%d,\"checks\":\"miss,zero stroke,cut,delayed detach,three stars,win,retry,loss,long idle,tap radius,tap cut\"}\n", wontick);
}
