#include "simulation.hpp"
#include "level.hpp"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <vector>

int main(int argc, char** argv) {
    if (argc == 1) {
        dx::simulation game;
        game.reset(dx::levels[175]);
        const auto button = game.definition.switches[0];
        assert(game.interact(button) && !game.inverted);
        game.drag(button + dx::point{200,0}, true);
        game.drag(button + dx::point{200,0}, false);
        assert(!game.inverted);
        assert(game.interact(button)); game.drag(button, false);
        assert(game.inverted && game.gravityevents == 1);
        game.drag(button, false); assert(game.gravityevents == 1);
        game.reset(dx::levels[150]);
        const auto anchor = game.anchors[0];
        assert(game.interact(anchor + dx::point{90,0}) && game.dragwheel == 0);
        assert(!game.tap(anchor));
        int low = 32, high = 0;
        float angle = 0;
        for (int tick = 0; tick < 10000; ++tick) {
            angle += tick % 1000 < 500 ? -8 : 8;
            game.drag(anchor + dx::point{90 * std::cos(angle * .0174532925f),90 * std::sin(angle * .0174532925f)}, true);
            game.tick(true);
            low = std::min(low, game.ropes[0].count); high = std::max(high, game.ropes[0].count);
            assert(game.bodycount <= 40 && game.ropes[0].count >= 3 && std::isfinite(game.candy().pos.y));
        }
        assert(low == 3 && high >= 10);
        game.drag(anchor, false); assert(game.dragwheel == -1);
        game.reset(dx::levels[150]);
        assert(!game.inverted && !game.wheelevents && !game.gravityevents);
        std::puts("PASS: gravity release/cancel, wheel ownership, 10,000 reel/retract steps, recycled body pool, reset");
        return 0;
    }
    assert(argc == 5);
    dx::simulation game;
    game.reset(dx::levels[(std::atoi(argv[1]) - 1) * 25 + std::atoi(argv[2]) - 1]);
    while (game.introduction) game.tick();
    const int mode = std::atoi(argv[3]), duration = std::atoi(argv[4]);
    int wheel = -1;
    for (int i = 0; i < game.definition.hookcount; ++i) if (game.definition.hooks[i].wheel) { wheel = i; break; }
    if (mode == 1 && wheel >= 0) game.wheeltouch = game.anchors[wheel] + dx::point{90,0};
    struct action { int tick; dx::point position; };
    std::vector<action> actions;
    action next{};
    while (std::scanf("%d %f %f", &next.tick, &next.position.x, &next.position.y) == 3) actions.push_back(next);
    unsigned cursor = 0;
    for (int tick = 1; tick <= duration; ++tick) {
        if (cursor < actions.size() && actions[cursor].tick == tick) game.rotatewheel(wheel, actions[cursor++].position);
        if (mode == 2 && (tick == 31 || tick == 85 || tick == 120 || tick == 125)) game.togglegravity();
        game.tick();
        std::printf("{\"tick\":%d,\"x\":%.8f,\"y\":%.8f,\"bubble\":%s,\"state\":%d,\"ropes\":[",
            tick, game.candy().pos.x, game.candy().pos.y, game.bubble >= 0 ? "true" : "false", static_cast<int>(game.state));
        for (int i = 0; i < game.definition.hookcount; ++i) {
            const auto& rope = game.ropes[i];
            float rest = -1;
            if (rope.count >= 2) {
                const auto& tail = game.bodies[rope.bodies[rope.count - 1]];
                for (int j = 0; j < tail.linkcount; ++j)
                    if (tail.links[j].active && tail.links[j].other == rope.bodies[rope.count - 2]) rest = tail.links[j].length;
            }
            std::printf("%s[%d,%d,%.8f]", i ? "," : "", rope.count, game.ropelength(i), rest);
        }
        std::puts("]}");
    }
}
