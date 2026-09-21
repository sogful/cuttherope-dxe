#include "simulation.hpp"
#include "level.hpp"
#include <cassert>
#include <cstdio>

int main() {
    dx::simulation game;
    auto data=dx::levels[0];
    data.hookcount=0; data.target={2000,1200}; data.candy={1000,600};
    auto attach=[&](int id,bool ghost=false) {
        game.definition.bubblecount=1; game.bubblesused[0]=true; game.bubbleindex(id)=0;
        if (ghost) {
            game.definition.ghostcount=1; game.definition.ghosts[0].forms=3;
            game.ghosts[0].form=2; game.ghosts[0].app=0;
            game.apparitions[0]={0,2,0,1,-1,id};
        }
    };
    for (bool ghost : {false,true}) for (int reason=0;reason<4;++reason) {
        game.reset(data); attach(0,ghost);
        if (reason==0) game.definition.target=game.candy().pos;
        else if (reason==1) {
            game.definition.spikecount=1; game.definition.spikes[0].anchor=game.candy().pos;
        } else game.bodies[0].pos=game.bodies[0].previous={1000,reason==2?-500.0f:2000.0f};
        game.tick();
        assert(game.state!=dx::outcome::playing && game.bubble==-1 && game.pops==0);
        if (ghost) assert(game.apparitions[0].owner==-1);
    }
    game.reset(data); attach(0);
    assert(game.interact(game.candy().pos) && game.bubble==-1 && game.pops==1);
    game.reset(data); attach(0);
    game.definition.bubblecount=2; game.definition.bubbles[1]=game.candy().pos;
    game.tick(); assert(game.bubble==1 && game.pops==1);
    auto split=dx::levels[100]; split.hookcount=0; split.spikecount=0;
    for (int id : {1,2}) {
        game.reset(split); attach(id);
        game.bodies[id].pos=game.bodies[id].previous={1000,-500};
        game.tick(); assert(!game.halfalive[id-1] && game.bubblefor(id)==-1 && game.pops==0);
    }
    for (int kind=0;kind<3;++kind) for (bool ghost : {false,true}) {
        auto hats=data;
        hats.hatcount=2; hats.hats[0].position=data.candy; hats.hats[1].position={1600,400};
        hats.bulbcount=kind?1:0; hats.bulbs[0].position={500,1000};
        game.reset(hats);
        const int id=kind==2?3:0;
        game.bodies[id].pos=data.candy; game.bodies[id].previous=data.candy-dx::point{0,2};
        if (id==3) game.bodies[0].pos=game.bodies[0].previous={500,1000};
        attach(id,ghost); game.tick();
        assert((id==3?game.bulbtransit:game.transit)==1);
        assert(game.bubblefor(id)==0 && game.pops==0 && game.popage>=100);
        if (ghost) assert(game.apparitions[0].owner==id && !game.ghosttap(0));
        for (int i=0;i<12;++i) game.tick();
        assert((id==3?game.bulbtransit:game.transit)==-1 && game.bodies[id].pos.x>1500);
        assert(game.bubblefor(id)==0 && game.pops==0);
        if (ghost) assert(game.apparitions[0].owner==id);
    }
    std::puts("PASS: silent eaten/hazard/bounds/split removal; audible taps/replacement; normal/ghost candy and bulb bubbles survive hat transit");
}
