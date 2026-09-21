#pragma once
#include "simulation.hpp"
#include "geometry.hpp"
#include "menuassets.hpp"
#include <algorithm>

namespace gamevisuals {
template<class draw> void steam(const dx::simulation& game, bool front, draw world) {
    for (int i = 0; i < game.definition.tubecount; ++i) {
        const auto& source = game.definition.tubes[i]; const auto& tube = game.tubes[i];
        const auto axis = tube.forward;
        auto place = [&](int sprite, dx::point offset, float scale = 1, float spin = 0) {
            world(sprite,source.position+dx::point{offset.x*axis.x-offset.y*axis.y,offset.x*axis.y+offset.y*axis.x},31,source.angle+spin,scale);
        };
        const float size=game.beltscale(4,i);
        if (!front) {
            // SetTransporterScale affects both the parent and the pipe/valve children.
            place(menuart::pipe0,{.5f*size,84*size},size*size);
            place(menuart::pipe1,{0,(27*source.scale+.5f)*size},size*size,tube.valve);
        }
        for (const auto& p : tube.puffs) {
            const float age = game.steamtime-p.start;
            if (p.start == -100 || age < 0 || (p.stop >= 0 && game.steamtime >= p.stop) || front == (p.variant == 2)) continue;
            const float progress = std::fmod(age,.6f)/.6f, ease = 1-(1-progress)*(1-progress), scale = 1+.5f*progress;
            place(menuart::pipe2+p.variant*11+std::min(10,static_cast<int>(progress*11)),{p.horizontal*ease*size,(p.height*ease+.5f*scale)*size},scale*size);
        }
    }
}
template<class draw> void lanterns(const dx::simulation& game, int skin, draw world) {
    auto lerp = [](float a,float b,float t) { return a+(b-a)*std::clamp(t,0.0f,1.0f); };
    auto ease = [](float t) { return 1-(1-t)*(1-t); };
    for (int i = 0; i < game.definition.lanterncount; ++i) {
        const auto& o = game.lanterns[i]; const float age = o.age;
        const float active = o.phase == 1 ? std::min(1.0f,age/.3f) : o.phase == 2 ? std::max(0.0f,1-age/.3f) : 0;
        float sx = 1, sy = 1, y = -4, alpha = 0, brightness = 1, firex = 1.4f, firey = 1, firealpha = 0;
        if (o.phase == 1) {
            alpha = std::min(1.0f,age/.2f);
            if (age < .07f) sy = lerp(1,.8f,age/.07f);
            else if (age < .12f) { sx = lerp(1,.85f,(age-.07f)/.05f); sy = lerp(.8f,1.05f,(age-.07f)/.05f); }
            else { sx = lerp(.85f,1,(age-.12f)/.05f); sy = lerp(1.05f,1,(age-.12f)/.05f); }
            y = age < .1f ? lerp(-4,0,age/.1f) : lerp(0,-1,(age-.1f)/.05f);
            if (age >= o.idlestart) {
                const float phase = std::fmod(age-o.idlestart,1.4f); const int quarter = std::min(3,static_cast<int>(phase/.35f));
                const float t = (phase-quarter*.35f)/.35f; const float values[] = {1,.93f,.87f,.93f,1};
                sx = sy = lerp(values[quarter],values[quarter+1],quarter%2?ease(t):t*t);
            }
            firealpha = .7f;
            if (age >= o.firestart) {
                const float phase = std::fmod(age-o.firestart,1.0f), t = phase < .5f ? phase/.5f : (1-phase)/.5f;
                firex = lerp(1.4f,1.05f,ease(t)); firey = lerp(1,1.3f,ease(t)); firealpha = lerp(.7f,1,t);
            }
        } else if (o.phase == 2) {
            if (age < .06f) {
                const float t = age/.06f;
                alpha = lerp(1,.6f,t); sx = lerp(1,1.15f,t); sy = lerp(1,.8f,t); y = lerp(0,-4,ease(t));
            } else {
                const float t = std::min(1.0f,(age-.06f)/.04f);
                alpha = lerp(.6f,0,t); sx = lerp(1.15f,1,t); sy = lerp(.8f,1,t); y = lerp(-4,4,t*t);
            }
            brightness = alpha;
        }
        auto place = [&](int sprite,float y,float sx,float sy,float alpha,float tint = 1) {
            world(sprite,o.position+dx::rotate({0,y},o.angle),std::lround(alpha*31),o.angle,sx,0,sy,std::lround(tint*31));
        };
        place(menuart::lantern0,0,firex,firey,firealpha,firealpha);
        place(menuart::lantern2,0,1,1,1-active);
        place(menuart::lantern1,1,1,1,active);
        place(menuart::lanterncandy0+skin,y,sx,sy,alpha,brightness);
    }
}
}
