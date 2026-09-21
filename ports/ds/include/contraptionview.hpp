#pragma once
#include "geometry.hpp"
#include "menuassets.hpp"
#include <algorithm>

namespace gamevisuals {
inline dx::point turn(dx::point p, float degrees) {
    const float angle = degrees * 3.14159265f / 180, s = std::sin(angle), c = std::cos(angle);
    return {p.x*c-p.y*s,p.x*s+p.y*c};
}
template<class Draw> void discs(const dx::simulation& game, Draw draw) {
    std::uint64_t contained[4]{};
    bool shared[4]{};
    for (int i = 0; i < game.definition.disccount; ++i) {
        const auto& d = game.definition.discs[i];
        const float radius = 534*(d.size/167);
        for (int h = 0; h < game.definition.hookcount; ++h) {
            const auto& hook = game.definition.hooks[h];
            if (!hook.rail && hook.route < 0 && !game.ghostapp(4,h) && (game.anchors[h]-d.position).length() <= radius+15)
                contained[i] |= std::uint64_t{1} << h;
        }
        for (int b = 0; b < game.definition.bubblecount; ++b)
            if (!game.ghostapp(2,b) && (game.definition.bubbles[b]-d.position).length() <= radius+30) contained[i] |= std::uint64_t{1} << (24+b);
    }
    for (int i = 0; i < game.definition.disccount; ++i) for (int j = 0; j < game.definition.disccount; ++j) {
        const auto& a = game.definition.discs[i]; const auto& b = game.definition.discs[j];
        if ((a.position.x!=b.position.x || a.position.y!=b.position.y || a.size!=b.size) && (contained[i]&contained[j])) shared[i] = true;
    }
    for (int layer = 0; layer < game.disclayers; ++layer) {
        const auto& state = game.discorder[layer]; const auto& d = game.definition.discs[state.index];
        const float base = d.size/167, sticker = std::max(base,.4f), control = std::max(base,.75f);
        const int alpha = state.copy ? 31 : std::clamp(static_cast<int>(state.fade/.2f*31),0,31);
        const menuart::vinyl* art = nullptr;
        for (const auto& item : menuart::vinyls) if (item.size == static_cast<int>(d.size)) { art = &item; break; }
        if (!art) continue;
        const bool active = !state.copy && game.dragdisc == state.index;
        if (active) draw(art->ring,d.position,alpha,0,1,0);
        draw(art->face,d.position,alpha,0,1,0);
        for (int previous = 0; previous < layer; ++previous) {
            const int back = game.discorder[previous].index;
            if (!shared[back]) continue;
            for (const auto& contour : menuart::contours)
                if (contour.level==game.definition.index && contour.front==state.index && contour.back==back) draw(contour.sprite,d.position,31,0,1,0);
        }
        for (int side : {-1,1}) draw(art->shine,d.position+dx::point{side*267*base,248.5f*base},alpha,0,1,side>0?1:0);
        draw(menuart::vinyllabel,d.position+turn({-.5f,0},state.angle),31,state.angle,sticker,0);
        const float offset = 534*base-(67.5f-.089999996f*d.size)+(1-control)*92;
        if (!state.copy) for (int side : {-1,1}) {
            if (side<0 && d.single) continue;
            const auto center = d.position+turn({side*offset,0},state.angle);
            if (active && (game.discside & (side<0?1:2))) draw(menuart::vinyl4,center,31,state.angle-side*90,control,0);
            draw(menuart::vinyl5,center+turn({0,-side*.5f*control},state.angle),alpha,state.angle-side*90,control,0);
        }
        draw(menuart::vinyl3,d.position,31,0,1-(1-sticker)*.5f,0);
    }
}
inline float wave(float time, float duration, float a, float b, float c) {
    const float phase = std::fmod(time/duration,4);
    const int segment = static_cast<int>(phase);
    const float t = phase-segment, ease = segment%2 ? 1-(1-t)*(1-t) : t*t;
    const float points[] = {a,b,c,b,a};
    return points[segment]+(points[segment+1]-points[segment])*ease;
}
struct cloud { int quad; float x,y,a,b,c,duration,dx,dy,angle; };
template<class Draw> void clouds(const dx::simulation& game, const dx::apparition& app, dx::point position, int alpha, bool back, Draw draw) {
    static constexpr cloud bubbles[] = {{6,85,25,.8f,.78f,.76f,.48f,1,1,0},{5,65,55,.93f,.965f,1,.4f,1,1,0},
        {5,-90,15,.33f,.365f,.4f,.43f,1,1,0},{6,-75,45,.6f,.565f,.53f,.42f,-1,1,0},{2,-20,75,.93f,.965f,1,.47f,1,-1,350}};
    static constexpr cloud grabs[] = {{5,-60,2,.43f,.465f,.5f,.65f,-1,1,0},{4,58,18,.9f,.8f,.7f,.45f,1,1,0},{2,-15,45,1.1f,1,.9f,.5f,-1,1,0}};
    static constexpr cloud bouncers[] = {{3,60,55,1.1f,1,.9f,.45f,1,1,0},{2,-50,55,1.1f,1,.9f,.5f,-1,1,0}};
    if (back) {
        if (app.form!=8) return;
        for (int i = 0; i < 2; ++i) {
            const float duration = i ? .35f : .39f, angle = game.definition.ghosts[app.ghost].angle+(i?170:10);
            const auto p = position+turn({std::sqrt(9000.0f),0},angle);
            const float shift = wave(app.age,duration,1,0,-1);
            draw(menuart::ghost4,p+dx::point{shift,shift},31,0,wave(app.age,duration,i?.7f:.9f,i?.55f:.8f,i?.4f:.7f),0);
        }
        return;
    }
    const cloud* items = app.form==2 ? bubbles : app.form==4 ? grabs : bouncers;
    const int count = app.form==2 ? 5 : app.form==4 ? 3 : 2;
    const float time = app.form==2 && app.owner>=0 ? game.visuals*.016f : app.age;
    for (int i = 0; i < count; ++i) {
        const auto& d = items[i];
        const auto offset = dx::point{d.x+wave(time,d.duration,d.dx,0,-d.dx),d.y+wave(time,d.duration,d.dy,0,-d.dy)};
        draw(menuart::ghost0+d.quad,position+offset,alpha,d.angle,wave(time,d.duration,d.a,d.b,d.c),0);
    }
}
template<class Draw> void ghosts(const dx::simulation& game, Draw draw) {
    for (int i = 0; i < game.definition.ghostcount; ++i) {
        const auto& g = game.ghosts[i]; const auto& source = game.definition.ghosts[i];
        const float alpha = g.form==1 ? std::min(1.0f,g.idleage/.36f) : std::max(0.0f,1-g.idleage/.16f);
        for (int part = 0; part < 2; ++part) {
            const float amplitude = part ? 2 : 3, start = (i*173%997)/1000.0f+(part?.005f:0);
            const float time = game.visuals*.016f, phase = std::min(1.0f,time/std::max(.001f,start));
            const float y = time<start ? -amplitude*(1-(1-phase)*(1-phase)) : wave(std::max(0.0f,time-start),.38f,-amplitude,0,amplitude);
            draw(menuart::ghost0+part,source.position+dx::point{0,y},std::lround(alpha*31),0,1,0);
        }
        if (!g.morphs || g.age>.75f) continue;
        const float travel = .016f*(1-std::pow(.83f,g.age/.016f))/.17f;
        const float growth = std::pow(1.015f,g.age/.016f);
        for (int p = 0; p < 7; ++p) {
            const unsigned seed = (i*977+g.morphs*607+p*919)*1103515245u+12345;
            const float life = .45f+(seed%301)/1000.0f;
            if (g.age >= life) continue;
            const float angle = (seed%360)+p*360.0f/7, speed = 45+(seed%31);
            const float distance = speed*travel;
            const float scale = (.4f+(seed%801)/1000.0f)*growth;
            draw(menuart::ghost4+seed%3,source.position+turn({distance,0},angle),std::lround(std::min(1.0f,(life-g.age)/.42f)*31),
                (static_cast<int>(seed%61)-30)*g.age,scale,0);
        }
    }
}
}
