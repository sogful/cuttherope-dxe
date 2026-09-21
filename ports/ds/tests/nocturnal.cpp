#include "simulation.hpp"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <vector>
struct action { int tick, kind, index, accepted; };
static dx::simulation game;
int main(int argc, char** argv) {
    if (argc==1) {
        auto source=dx::loadlevel(375); source.hookcount=0; source.bubblecount=0; source.hatcount=0;
        game.reset(source); game.bodies[3].pos={1000,1000}; const float r=source.bulbs[0].radius;
        assert(game.illuminated({1000+r-.01f,1000}));
        assert(!game.illuminated({1000+r,1000}));
        assert(!game.illuminated({1000+r+.01f,1000}));
        game.bulbtransit=0; assert(!game.illuminated({1000,1000}));
        game.bulbtransit=-1; game.bulbalive=false; assert(!game.illuminated({1000,1000}));
        game.reset(source); game.bodies[0].pos=game.bodies[0].previous=source.target; game.bodies[3].pos=game.bodies[3].previous={-1000,0};
        game.tick(); assert(!game.awake && !game.nightwoken && !game.mouth && game.state==dx::outcome::playing);
        game.bodies[3].pos=game.bodies[3].previous=source.target+dx::point{150,0};
        game.tick(); assert(game.awake && game.state==dx::outcome::won);
        game.reset(source); game.bodies[3].pos=game.bodies[3].previous={1000,-401};
        game.tick(); assert(!game.bulbalive && game.failreason==4);
        const float y=game.candy().pos.y; game.tick(); assert(game.candy().pos.y>y);
        source.gravity={0,0}; game.reset(source); game.introduction=false;
        auto place=[&](int id,dx::point offset) {
            auto& body=game.bodies[id]; body.pos=body.previous=body.pin=source.target+offset; body.pinned=true;
        };
        place(3,{150,0}); place(0,{0,-500});
        for (int i=0;i<100;++i) { game.tick(); assert(game.awake && !game.mouth && game.state==dx::outcome::playing); }
        place(0,{0,-160}); game.tick(); assert(game.mouth);
        const int opened=game.mouthtick;
        for (int i=0;i<20;++i) {
            place(3,{1500,0}); game.tick(); assert(!game.awake && game.nightwoken && game.mouthtick==opened);
            place(3,{150,0}); game.tick(); assert(game.awake && game.mouth && game.mouthtick==opened);
        }
        game.mouthdelay=1; place(0,{0,-250});
        for (int i=0;i<62;++i) { game.tick(); assert(game.mouth && game.mouthtick==opened); }
        game.tick(); assert(!game.mouth);
        place(0,{0,-160}); game.tick(); assert(game.mouth && game.mouthtick>opened);
        assert(game.state==dx::outcome::playing);
        std::puts("PASS: bulb never opens mouth or feeds Om Nom; sleep/wake preserves feeding state; source one-second mouth-close delay");
        std::puts("PASS: strict light radius, hidden/dead emitters, asleep/awake eating, and surviving candy on lights-out");
        return 0;
    }
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
                if (a.kind == 0) matched = matched && game.interact(game.definition.mice[a.index-1].position)==static_cast<bool>(a.accepted);
                if (a.kind == 1) {
                    if (box == 15) for (int i = 0; i < game.definition.hookcount; ++i) game.sever(i,0);
                    else game.sever(a.index-1,0);
                }
                if (a.kind == 2) game.burst(box == 16 && a.index == 2 ? 3 : 0);
            }
            game.tick();
        }
        std::printf("{\"tick\":%d,\"input\":%s,\"bodies\":[",tick,matched?"true":"false");
        const int live = box == 16 ? 2 : game.state == dx::outcome::playing ? 1 : 0;
        for (int i = 0; i < live; ++i) {
            const int id = i ? 3 : 0; const auto& b = game.bodies[id];
            std::printf("%s[%.8f,%.8f,%.8f,%.8f,%s,%s,%s]",i?",":"",b.pos.x,b.pos.y,b.previous.x,b.previous.y,
                game.bubblefor(id)>=0?"true":"false", box == 15 ? (game.nogravity?"true":"false") : (game.available(id)?"true":"false"),
                (id ? game.bulbtransit >= 0 : game.hidden())?"true":"false");
        }
        std::printf("],\"active\":%d,\"mice\":[",game.activemouse < 0 ? 0 : game.definition.mice[game.activemouse].index);
        for (int i = 0; i < game.definition.mousecount; ++i) {
            const auto& m = game.mice[i];
            std::printf("%s[%s,%s,%s,%s,%.8f]",i?",":"",m.active?"true":"false",m.carry?"true":"false",m.retreat?"true":"false",m.grabbing?"true":"false",m.elapsed);
        }
        std::printf("],\"lit\":[%s,%s,%s],\"collected\":[%s,%s,%s],\"lightedge\":[",game.starlit[0]?"true":"false",game.starlit[1]?"true":"false",game.starlit[2]?"true":"false",game.stars[0]?"true":"false",game.stars[1]?"true":"false",game.stars[2]?"true":"false");
        for (int i=0;i<3;++i) std::printf("%s%.8f",i?",":"",game.lightedge[i]);
        std::printf("],\"state\":%d}\n",static_cast<int>(game.state));
    }
}
