#include "simulation.hpp"
#include "level.hpp"
#include <cassert>
#include <cstdio>

int main() {
    dx::simulation game;
    std::printf("{\"traces\":[");
    int sequence = 0;
    for (int index : {0,5,6,9}) {
        game.reset(dx::levels[index]);
        std::printf("%s{\"level\":%d,\"samples\":[", sequence++ ? "," : "", index + 1);
        for (int i = 1; i <= 120; ++i) {
            if (index == 5 && i == 61) game.sever(0,0);
            game.tick();
            if (i == 1 || i % 15 == 0) std::printf("%s{\"tick\":%d,\"x\":%.8f,\"y\":%.8f}", i == 1 ? "" : ",", i, game.candy().pos.x, game.candy().pos.y);
        }
        std::printf("]}");
    }
    game.reset(dx::levels[6]);
    for (int frame = 1; frame <= 600 && game.state == dx::outcome::playing; ++frame) {
        if (frame == 61) for (int rope : {0,2,3}) game.sever(rope,0);
        if (frame == 96) for (int rope : {1,5}) game.sever(rope,0);
        game.tick();
    }
    assert(game.count == 3); // The original route test checks stars, not feeding Om Nom.
    for (const auto& level : dx::levels) {
        game.reset(level);
        for (int index = 0; index < level.hookcount; ++index) {
            const auto& rope = game.ropes[index];
            if (rope.count < 3) continue;
            dx::point curve[125]; int size;
            game.samples(index,0,rope.count,curve,size);
            for (int sample = 0; sample < size; ++sample) {
                dx::point work[32];
                for (int part = 0; part < rope.count; ++part) work[part] = game.bodies[rope.bodies[part]].pos;
                const float t = static_cast<float>(sample) / (size - 1);
                for (int degree = rope.count - 1; degree > 0; --degree)
                    for (int part = 0; part < degree; ++part) work[part] = work[part] * (1-t) + work[part+1] * t;
                assert((curve[sample] - work[0]).length() < .01f);
            }
        }
        for (int frame = 0; frame < 1200; ++frame) {
            if (frame == 600) for (int i = 0; i < level.hookcount; ++i) game.sever(i, 0);
            if (frame % 30 == 0 && !game.introduction) for (int i = 0; i < level.pumpcount; ++i) game.interact(level.pumps[i].position);
            game.tick();
            assert(std::isfinite(game.candy().pos.x) && std::isfinite(game.candy().pos.y));
            assert(game.bodycount <= 256 && game.candy().linkcount <= 8);
            assert(game.cameray >= 0 && game.cameray <= level.height - 1440);
        }
    }
    dx::level empty = dx::firstlevel;
    empty.hookcount = 0; empty.target = {3000, 1000};
    empty.stars = {{{100,100},{200,100},{300,100}}};
    empty.candy = {1280, 720};
    empty.bubblecount = 1; empty.bubbles[0] = empty.candy;
    game.reset(empty);
    game.tick();
    assert(game.bubble == 0 && game.bubblesused[0]);
    for (int i = 0; i < 60; ++i) game.tick();
    assert(game.candy().pos.y < 720);
    const float before = game.candy().pos.y;
    assert(game.interact(game.candy().pos) && game.bubble == -1 && game.pops == 1);
    for (int i = 0; i < 80; ++i) game.tick();
    assert(game.candy().pos.y > before);
    empty.bubblecount = 0;
    empty.pumpcount = 1; empty.pumps[0] = {{1000,720},90};
    game.reset(empty);
    assert(game.interact({1000,720}) && game.pumpevents == 1 && game.candy().pos.x > 1280);
    empty.pumpcount = 0;
    empty.spikecount = 1; empty.spikes[0] = {{1280,720},{},0,1};
    game.reset(empty); game.tick();
    assert(game.state == dx::outcome::lost && game.failreason == 2);
    empty.spikecount = 0;
    empty.hookcount = 1; empty.hooks[0] = {{1280,500},300,180,false};
    game.reset(empty);
    assert(game.ropes[0].count == 0);
    game.tick();
    assert(game.ropeevents == 1 && game.ropes[0].count > 0);
    assert(game.sever(0,0));
    for (int i = 0; i < 4; ++i) game.tick();
    assert(game.ropes[0].pending == -1);
    const int bodies = game.bodycount;
    for (int i = 0; i < 80; ++i) game.tick();
    assert(game.bodycount == bodies && game.ropeevents == 1);
    empty.hookcount = 0; empty.timeouts[0] = .1f;
    game.reset(empty);
    for (int i = 0; i < 8; ++i) game.tick();
    assert(game.expired[0] && !game.stars[0]);
    dx::motion movement{{0,100},40,0};
    assert(std::abs(movement.at(1).y - 40) < .001f && std::abs(movement.at(3).y - 80) < .001f);
    game.reset(dx::levels[14]);
    assert(game.introduction);
    for (int i = 0; i < 500 && game.introduction; ++i) game.tick();
    assert(!game.introduction && game.ticks <= 1);
    std::printf("],\"maps\":50,\"frames\":60000,\"passed\":true}\n");
}
