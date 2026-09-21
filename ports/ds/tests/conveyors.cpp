#include "simulation.hpp"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <vector>
struct action { int tick,kind,index; dx::point position; };
static dx::simulation game;
int main(int argc,char** argv) {
    if (argc==1) {
        auto source=dx::loadlevel(400);
        source.hookcount=source.bubblecount=0;
        source.beltcount=1; source.belts[0]={{900,700},900,150,0,0,true};
        source.candy={1500,700}; source.target={2400,1300};
        source.stars={{{1100,700},{-5000,-5000},{-5000,-5000}}};
        game.reset(source);
        assert(game.belted(1,0) && game.pressbelt({1150,700}));
        assert(game.dragbelt({1550,700})); game.releasebelt({1550,700});
        game.tick(); assert(game.stars[0] && game.count==1 && !game.belted(1,0));
        assert(game.pressbelt({1200,700})); game.dragbelt({1210,700}); game.cancelbelts();
        assert(game.heldbelt<0 && game.belts[0].delta==0 && !game.belts[0].active);
        std::puts("PASS: carried-star pickup uses its live position, detaches ownership, and cancelled drags stop inertia");
        return 0;
    }
    assert(argc==3);
    auto source=dx::loadlevel(400+std::atoi(argv[1])-1);
    int initial; assert(std::scanf("%d",&initial)==1);
    for (int i=0;i<initial;++i) { int index; dx::point p; assert(std::scanf("%d %f %f",&index,&p.x,&p.y)==3); source.stars[index]=p; }
    game.reset(source);
    while (game.introduction) game.tick();
    std::vector<action> actions; action a;
    while (std::scanf("%d %d %d %f %f",&a.tick,&a.kind,&a.index,&a.position.x,&a.position.y)==5) actions.push_back(a);
    for (int tick=0;tick<=std::atoi(argv[2]);++tick) {
        if (tick) {
            for (const auto& a:actions) if (a.tick==tick) {
                if (a.kind==0) game.pressbelt(a.position);
                if (a.kind==1) game.dragbelt(a.position);
                if (a.kind==2) game.releasebelt(a.position);
                if (a.kind==3) game.sever(a.index,0);
            }
            // The C# exporter never draws, leaving star collision rectangles at
            // their initial positions. Replay its explicit removal input, as
            // MechanicalGoldenRunner does; the live pickup check is above.
            const auto collected=game.stars; game.stars.fill(true);
            game.tick(); game.stars=collected;
            for (const auto& a:actions) if (a.tick==tick && a.kind==4) {
                game.removebeltitem(1,a.index); game.stars[a.index]=true;
            }
        }
        std::printf("{\"tick\":%d,\"bodies\":[",tick);
        for (int i=0;i<game.candycount();++i) {
            const int id=game.activeid(i); const auto& b=game.bodies[id];
            std::printf("%s[%.8f,%.8f,%.8f,%.8f,%s]",i?",":"",b.pos.x,b.pos.y,b.previous.x,b.previous.y,game.bubblefor(id)>=0?"true":"false");
        }
        std::printf("],\"hooks\":[");
        for (int i=0;i<game.definition.hookcount;++i) {
            const auto& r=game.ropes[i]; const int cut=r.count?r.cut?(r.pending>=0?r.pending:r.split-2):-1:-2;
            std::printf("%s[%.8f,%.8f,%d]",i?",":"",game.anchors[i].x,game.anchors[i].y,cut);
        }
        std::printf("],\"items\":[");
        for (int i=0;i<game.beltitemsused;++i) {
            const auto& item=game.beltitems[i]; const auto p=game.beltpoint(item);
            std::printf("%s[%d,%d,%.8f,%.8f,%.8f,%.8f,%d]",i?",":"",item.kind,item.index,p.x,p.y,item.position,item.scale,item.belt+1);
        }
        std::printf("],\"wraps\":%d,\"handoffs\":%d}\n",game.beltwraps,game.belthandoffs);
    }
}
