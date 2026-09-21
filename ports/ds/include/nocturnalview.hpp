#pragma once
#include "simulation.hpp"
#include "geometry.hpp"
#include "menuassets.hpp"
#include <algorithm>

namespace gamevisuals {
template<class draw> void mouseholes(const dx::simulation& game, draw world) {
    for (int i = 0; i < game.definition.mousecount; ++i) world(menuart::mouse0,game.definition.mice[i].position);
}
template<class draw> void mice(const dx::simulation& game, draw world) {
    if (game.activemouse < 0) return;
    const auto& mouse = game.mice[game.activemouse]; const auto& source = game.definition.mice[game.activemouse];
    if (mouse.phase == 6) return;
    dx::point offset{};
    if (mouse.bounce >= 0) {
        auto out = dx::rotate({0,-142*.15f*.45f},source.angle), back = dx::rotate({0,142*.15f*.4f},source.angle);
        out = {static_cast<float>(static_cast<int>(out.x)),static_cast<float>(static_cast<int>(out.y))};
        back = {static_cast<float>(static_cast<int>(back.x)),static_cast<float>(static_cast<int>(back.y))};
        const float t = mouse.bounce/.05f;
        offset = t < 1 ? out*t : t < 2 ? out+(back-out)*(t-1) : back*(3-t);
    }
    world(menuart::mouse0+mouse.quad,source.position+offset,31,source.angle);
    if (mouse.eyes >= 0) world(menuart::mouse5+std::min(8,static_cast<int>(mouse.eyes/.05f)),source.position+offset,31,source.angle);
}
template<class draw> void sleep(const dx::simulation& game, draw world) {
    if (!game.definition.night || game.awake || game.state != dx::outcome::playing) return;
    static constexpr float rows[][7] = {{.4f,.61f,.8f,29,9,0,1},{.3f,.8f,.89f,9,-2,1,1},
        {.2f,.89f,.98f,-2,-13,1,1},{.5f,.98f,.59f,-13,-33,1,0},{.4f,0,0,0,0,0,0}};
    const float age = (game.visuals-game.nightstart)*.016f;
    for (int i = 0; i < 2; ++i) {
        float t = std::fmod(age+(i?1.4f:0),1.8f);
        const float* row = rows[4];
        for (const auto& candidate : rows) { if (t < candidate[0]) { row = candidate; break; } t -= candidate[0]; }
        const float f = t/row[0], scale = row[1]+(row[2]-row[1])*f, angle = row[3]+(row[4]-row[3])*f;
        const dx::point offset = i ? dx::point{100,-100} : dx::point{120,-120}, pivot{-160,0};
        world(menuart::zzz,game.definition.target+offset+pivot-dx::rotate(pivot,angle),std::lround((row[5]+(row[6]-row[5])*f)*31),angle,scale);
    }
}
template<class draw> void light(const dx::simulation& game, bool front, draw world) {
    if (!game.definition.bulbcount || !game.available(3)) return;
    const auto position = game.bodies[3].pos;
    if (!front) {
        // DS 3D has source-alpha blending, not SRC_ALPHA/ONE. A low-alpha
        // source halo preserves foreground ropes rather than covering them.
        world(menuart::lighter0,position,12,0,game.definition.bulbs[0].radius*3/405);
    } else {
        world(menuart::lighter1,position); world(menuart::lighter2,position);
        world(menuart::lighter3+std::min(39,static_cast<int>(std::fmod(game.visuals*.016f,1.95f)/.05f)),position);
    }
}
}
