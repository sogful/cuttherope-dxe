#include "simulation.hpp"
#include "level.hpp"
#include <cstdio>
#include <cstring>

int main() {
    dx::simulation game;
    for (const auto& level : dx::levels) {
        game.reset(level);
        for (int frame = 0; frame < 1200; ++frame) {
            if (frame == 600) for (int i = 0; i < level.hookcount; ++i) game.sever(i, 0);
            if (frame % 30 == 0 && !game.introduction)
                for (int i = 0; i < level.pumpcount; ++i) game.interact(level.pumps[i].position);
            game.tick();
            unsigned hash = 2166136261u;
            auto value = [&](float number) {
                unsigned bits;
                std::memcpy(&bits, &number, sizeof(bits));
                hash = (hash ^ bits) * 16777619u;
            };
            for (int i = 0; i < game.bodycount; ++i) {
                const auto& body = game.bodies[i];
                for (const auto point : {body.pos, body.previous, body.velocity, body.pin}) {
                    value(point.x); value(point.y);
                }
            }
            value(game.count); value(game.ticks); value(static_cast<int>(game.state));
            value(game.mergeevents); value(game.teleportevents); value(game.bounceevents);
            value(game.cameray); value(game.bubble); value(game.failreason);
            std::printf("%08x\n", hash);
        }
    }
}
