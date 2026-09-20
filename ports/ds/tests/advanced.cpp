#include "simulation.hpp"
#include "level.hpp"
#include <cassert>
#include <cstdio>
#include <cstdlib>

int main(int argc, char** argv) {
    dx::simulation game;
    if (argc == 1) {
        game.reset(dx::levels[200]);
        const auto center = game.spikeposition(0);
        assert(game.interact(center) && game.dragspike == 0);
        game.drag(center + dx::point{200,0}, true); game.drag(center, false);
        assert(game.spikeevents == 0);
        assert(game.interact(center)); game.drag(center,false); assert(game.spikeevents == 1);
        game.drag(center,false); assert(game.spikeevents == 1);
        for (int i = 0; i < 19; ++i) game.tick(true);
        assert(std::abs(game.spikeangle(0) - (game.definition.spikes[0].angle + 90)) < .001f);
        for (int reason = 0; reason < 4; ++reason) {
            auto level = dx::levels[0]; level.hooks[0].spider = true;
            game.reset(level);
            for (int i = 0; i < (reason == 3 ? 0 : 60); ++i) game.tick(true);
            if (reason == 1) game.sever(0,0);
            if (reason == 2) {
                game.definition.spikecount = 1;
                game.definition.spikes[0].anchor = game.candy().pos;
            } else game.definition.target = game.candy().pos;
            game.tick();
            assert(game.state != dx::outcome::playing && game.ropes[0].cut && game.ropes[0].spiderstate == 1);
            assert(game.spiderfalls == 1 && game.ropes[0].pending == -1 && game.ropes[0].hidetail);
            for (int i = 0; i < game.bodies[0].linkcount; ++i) assert(!game.bodies[0].links[i].active);
            const auto distance = game.ropes[0].spiderdistance;
            for (int i = 0; i < 120; ++i) game.tick();
            assert(game.spiderfalls == 1 && game.ropes[0].spiderdistance == distance);
        }
        auto level = dx::levels[0]; level.hookcount = 2; level.hooks[0].spider = true; level.hooks[1] = level.hooks[0];
        game.reset(level);
        for (int i = 0; i < 60; ++i) game.tick(true);
        game.ropes[0].spiderdistance = 100000;
        game.tick();
        assert(game.failreason == 3 && game.ropes[0].spiderstate == 2 && game.ropes[1].spiderstate == 1 && game.spiderfalls == 1);
        assert(game.ropes[0].cut && game.ropes[1].cut);
        std::puts("PASS: linked spike touch/cancel, retoggle timing, win/loss and already-cut spider retirement");
        return 0;
    }
    assert(argc == 5);
    game.reset(dx::levels[(std::atoi(argv[1])-1)*25 + std::atoi(argv[2])-1]);
    while (game.introduction) game.tick();
    const int mode = std::atoi(argv[3]), duration = std::atoi(argv[4]);
    for (int tick = 1; tick <= duration; ++tick) {
        if (mode && (tick == 10 || tick == 16 || tick == 60 || tick == 90 || tick == 150)) game.rotatespikes(1);
        if (mode && (tick == 40 || tick == 80)) game.rotatespikes(2);
        game.tick();
        std::printf("{\"tick\":%d,\"state\":%d,\"failure\":%d,\"spiderfalls\":%d,\"bodies\":[",tick,static_cast<int>(game.state),game.failreason,game.spiderfalls);
        for (int i = 0; i < game.activecount(); ++i) {
            const int id = game.activeid(i); const auto p = game.bodies[id].pos;
            std::printf("%s[%.8f,%.8f,%s]",i?",":"",p.x,p.y,game.bubblefor(id)>=0?"true":"false");
        }
        std::printf("],\"ropes\":[");
        for (int i = 0; i < game.definition.hookcount; ++i)
            std::printf("%s[%.8f,%.8f,%d]",i?",":"",game.anchors[i].x,game.anchors[i].y,game.ropes[i].cut?-1:game.ropes[i].count);
        std::printf("],\"spikes\":[");
        for (int i = 0; i < game.definition.spikecount; ++i) {
            const auto p = game.spikeposition(i); std::printf("%s[%.8f,%.8f,%.8f]",i?",":"",p.x,p.y,game.spikeangle(i));
        }
        std::puts("]}");
    }
}
