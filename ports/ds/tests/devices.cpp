#include "simulation.hpp"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <vector>
struct action { int tick, kind, index, accepted; };
static dx::simulation game;
int main(int argc, char** argv) {
    assert(argc == 4);
    const int box = std::atoi(argv[1]), level = std::atoi(argv[2]), duration = std::atoi(argv[3]);
    game.reset(dx::loadlevel((box-1)*25+level-1));
    while (game.introduction) game.tick();
    std::vector<action> actions; action a;
    while (std::scanf("%d %d %d %d",&a.tick,&a.kind,&a.index,&a.accepted)==4) actions.push_back(a);
    for (int tick = 0; tick <= duration; ++tick) {
        bool matched = true;
        if (tick) {
            for (const auto& a : actions) if (a.tick == tick) {
                if (a.kind == 0) matched = matched && game.valvetap(a.index-1)==static_cast<bool>(a.accepted);
                if (a.kind == 1) matched = matched && game.interact(game.lanterns[a.index-1].position)==static_cast<bool>(a.accepted);
                if (a.kind == 2) for (int i = 0; i < game.definition.hookcount; ++i) game.sever(i,0);
                if (a.kind == 3) game.burst(game.activeid(a.index-1));
            }
            game.tick();
        }
        std::printf("{\"tick\":%d,\"input\":%s,\"bodies\":[",tick,matched?"true":"false");
        const int live = game.split || game.state == dx::outcome::playing ? game.activecount() : 0;
        for (int i = 0; i < live; ++i) {
            const int id = game.activeid(i); const auto& b = game.bodies[id];
            std::printf("%s[%.8f,%.8f,%.8f,%.8f,%s,%s]",i?",":"",b.pos.x,b.pos.y,b.previous.x,b.previous.y,game.bubblefor(id)>=0?"true":"false",game.nogravity?"true":"false");
        }
        std::printf("],\"occupied\":%s,\"shared\":%s,\"lanterns\":[",game.inlantern?"true":"false",game.sharedlantern?"true":"false");
        for (int i = 0; i < game.definition.lanterncount; ++i) {
            const auto& l = game.lanterns[i];
            std::printf("%s[%.8f,%.8f,%.8f,%d]",i?",":"",l.position.x,l.position.y,l.angle,l.state);
        }
        std::printf("],\"tubes\":[");
        for (int i = 0; i < game.definition.tubecount; ++i)
            std::printf("%s[%d,%.8f,%.8f]",i?",":"",game.tubes[i].state,game.steamheight(i),game.tubes[i].valve);
        std::printf("],\"state\":%d}\n",static_cast<int>(game.state));
    }
}
