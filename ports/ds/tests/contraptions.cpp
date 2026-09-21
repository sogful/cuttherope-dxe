#include "simulation.hpp"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <vector>
struct action { int tick, kind, index; float x, y; };
static dx::simulation game;
int main(int argc, char** argv) {
    if (argc == 1) {
        auto level = dx::loadlevel(275); level.hookcount = level.bouncercount = level.bubblecount = level.spikecount = 0;
        level.ghostcount = 4; level.candy = {1200,600};
        for (int i = 0; i < 4; ++i) level.ghosts[i] = {{1200.0f+i*10,450},180,0,15};
        game.reset(level);
        for (int tick = 0; tick < 10000; ++tick) {
            game.bodies[0].pos = game.bodies[0].previous = level.candy;
            if (tick%2==0) {
                const int i = tick/2%4;
                game.ghostform(i,game.ghosts[i].form==4?8:4);
            }
            game.tick(true);
            assert(game.bodycount < 128 && game.bodies[0].linkcount < 24);
            assert(game.definition.hookcount < 16 && game.definition.bouncercount < 16);
        }
        for (int i = 0; i < 4; ++i) game.ghostform(i,1);
        for (int tick = 0; tick < 25; ++tick) game.tick(true);
        assert(game.definition.hookcount==0 && game.definition.bouncercount==0 && game.bodies[0].linkcount==0);
        // Captured forms do not cycle. A merged pair releases both ghost bubbles.
        game.reset(level); game.bodies[0].pos = game.bodies[0].previous = level.ghosts[0].position;
        game.ghostform(0,2); game.tick(true);
        assert(game.bubble>=0 && !game.ghosttap(0));
        game.burst(); assert(game.ghosts[0].form==1);
        game.reset(level);
        game.ghostform(0,2); game.ghostform(1,2);
        for (auto& app : game.apparitions) if (app.form==2) app.owner=0;
        game.bubble=0; game.burst();
        assert(game.ghosts[0].form==1 && game.ghosts[1].form==1);
        game.reset(dx::loadlevel(250));
        const auto handle=game.dischandle(0,true);
        assert(game.interact(handle) && game.dragdisc==0 && !game.swipe({0,0},{2560,1440}));
        game.drag(handle,false); assert(game.dragdisc<0 && !game.tap(handle));
        level = dx::loadlevel(275); level.split = true; level.bubblecount = level.spikecount = level.bouncercount = level.ghostcount = 0;
        level.hookcount = 2; level.halves = {{{1000,2000},{1500,600}}};
        level.hooks[0] = {{1000,1900},105,-1,false,0,0,false,0};
        level.hooks[1] = {{1500,500},105,-1,false,0,0,false,1};
        game.reset(level);
        for (int id : {1,2}) {
            if (id==2) for (int i=0; i<game.ropes[1].count; ++i) {
                auto& body = game.bodies[game.ropes[1].bodies[i]];
                body.pos.y += 1400; body.previous.y += 1400; body.pin.y += 1400;
            }
            game.tick();
            assert(!game.halfalive[id-1] && game.ropes[id-1].cut && game.ropes[id-1].hidetail);
        }
        assert(game.activecount()==0 && game.state==dx::outcome::lost);
        std::puts("PASS: 5000 rapid ghost morphs reuse bounded bodies/constraints; captured/merged ownership and disc gesture capture");
        return 0;
    }
    assert(argc == 4);
    const int box = std::atoi(argv[1]), level = std::atoi(argv[2]), duration = std::atoi(argv[3]);
    game.reset(dx::loadlevel((box-1)*25+level-1));
    while (game.introduction) game.tick();
    std::vector<action> actions;
    action a;
    while (std::scanf("%d %d %d %f %f",&a.tick,&a.kind,&a.index,&a.x,&a.y)==5) actions.push_back(a);
    for (int tick = 1; tick <= duration; ++tick) {
        for (const auto& a : actions) if (a.tick == tick) {
            if (a.kind == 0) game.pressdisc({a.x,a.y});
            if (a.kind == 1 && game.dragdisc >= 0) game.rotatedisc({a.x,a.y});
            if (a.kind == 2) game.drag({},false);
            if (a.kind == 3) game.ghosttap(a.index-1);
            if (a.kind == 4) for (int i = 0; i < game.definition.hookcount; ++i) game.sever(i,0);
            if (a.kind == 5) game.burst(game.activeid(a.index-1));
        }
        game.tick();
        std::printf("{\"tick\":%d,\"bodies\":[",tick);
        for (int i = 0; i < game.activecount(); ++i) {
            const int id = game.activeid(i); const auto p = game.bodies[id].pos;
            std::printf("%s[%.8f,%.8f,%s,%s]",i?",":"",p.x,p.y,game.bubblefor(id)>=0?"true":"false",game.ghostapp(2,game.bubblefor(id))?"true":"false");
        }
        std::printf("],\"grabs\":[");
        for (int i = 0; i < game.definition.hookcount; ++i)
            std::printf("%s[%.8f,%.8f,%d]",i?",":"",game.anchors[i].x,game.anchors[i].y,game.ropes[i].count);
        std::printf("],\"discs\":[");
        for (int i = 0; i < game.definition.disccount; ++i) {
            const auto l = game.dischandle(i,false), r = game.dischandle(i,true);
            std::printf("%s[%.8f,%.8f,%.8f,%.8f,%.8f]",i?",":"",game.definition.discs[i].angle,l.x,l.y,r.x,r.y);
        }
        std::printf("],\"bubbles\":[");
        for (int i = 0; i < game.definition.bubblecount; ++i)
            std::printf("%s[%.8f,%.8f]",i?",":"",game.definition.bubbles[i].x,game.definition.bubbles[i].y);
        std::printf("],\"pumps\":[");
        for (int i = 0; i < game.definition.pumpcount; ++i)
            std::printf("%s[%.8f,%.8f,%.8f]",i?",":"",game.definition.pumps[i].position.x,game.definition.pumps[i].position.y,game.definition.pumps[i].angle);
        std::printf("],\"ghosts\":[");
        for (int i = 0; i < game.definition.ghostcount; ++i) {
            const auto g = game.ghosts[i];
            std::printf("%s[%d,%d]",i?",":"",g.form,g.form==4?game.ropes[game.apparitions[g.app].index].count:0);
        }
        std::printf("],\"counts\":[%d,%d,%d],\"state\":%d,\"bodypool\":%d}\n",game.definition.hookcount,game.definition.bouncercount,game.definition.bubblecount,static_cast<int>(game.state),game.bodycount);
    }
}
