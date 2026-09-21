#pragma once
#include "simulation.hpp"
#include "menuassets.hpp"
#include <algorithm>

namespace gamevisuals {
template<class draw> void conveyors(const dx::simulation& game, draw world) {
    auto order=game.beltorder;
    auto before=[&](int a,int b) {
        const bool manual=game.definition.belts[a].manual;
        if (manual!=game.definition.belts[b].manual) return manual;
        return manual && game.belts[a].activation<game.belts[b].activation;
    };
    for (int i=1;i<game.definition.beltcount;++i) for (int j=i;j>0 && before(order[j],order[j-1]);--j) std::swap(order[j],order[j-1]);
    constexpr float widths[]={144,67,144,67,235,66,235}, heights[]={79,79,83,83,63,35,24};
    for (int n=0;n<game.definition.beltcount;++n) {
        const int id=order[n]; const auto& b=game.definition.belts[id]; const auto& state=game.belts[id];
        const float w=b.width,h=b.length;
        auto piece=[&](int quad,float x,float y,float width,float height,int flip=0) {
            world(menuart::belt0+quad,game.beltworld(id,h-y,w*.5f-x),31,90-b.angle,width/widths[quad],flip,height/heights[quad]);
        };
        piece(2,w*.5f,h*.5f,w-10,h);
        piece(0,w*.5f,h+18-39.5f,w*.6f,79);
        piece(0,w*.5f,-18+39.5f,w*.6f,79);
        piece(3,33.5f,h*.5f,67,h-36,1);
        piece(3,w-33.5f,h*.5f,67,h-36);
        piece(1,w-33.5f,h+18-39.5f,67,79);
        piece(1,33.5f,h+18-39.5f,67,79,1);
        piece(1,33.5f,-18+39.5f,67,79,3);
        piece(1,w-33.5f,-18+39.5f,67,79,2);
        const float first=std::fmod(state.offset,63.0f);
        for (float y=0;y<h;) {
            const float size=std::min(h-y,y==0 && first>0?first:63);
            piece(4,w*.5f,y+size*.5f,w*.8f,size);
            if (!b.manual) piece(5,w*.5f,y+size*.5f,66*(w*.8f/235),35*(size/63),b.velocity>0?0:3);
            y+=size;
        }
        piece(6,w*.5f,h-12,w*.8f,24);
        piece(6,w*.5f,12,w*.8f,24,2);
    }
}
}
