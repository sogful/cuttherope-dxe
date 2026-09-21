#include "simulation.hpp"
#include "geometry.hpp"
#include <algorithm>

namespace dx {
static constexpr float delta = .016f;
// Mouse.cs shares one sprite container. Its old parent can retain a child
// reference, so authored hole order also determines same-frame handoffs.
static void sequence(mousestate& mouse, int phase) {
    static constexpr int first[] = {1,17,4,24,14,24,18};
    mouse.phase = phase; mouse.age = 0; mouse.quad = first[phase];
}
void simulation::attachmouse(int index) {
    auto& mouse = mice[index];
    mouse.carry = true; nogravity = true;
    bodies[0].velocity = {};
    bodies[0].pos = bodies[0].previous = definition.mice[index].position + mouse.entry[3];
    mouse.path = 1; mouse.pathage = 0; mouse.offset = mouse.entry[0]; mouse.grabbing = true;
}
void simulation::spawnmouse(int index, bool carry) {
    activemouse = index;
    auto& mouse = mice[index];
    mouse.container = true; mouse.carry = carry; mouse.active = mouse.retreat = mouse.grabbing = false;
    mouse.elapsed = 0; mouse.bounce = mouse.eyes = -1;
    sequence(mouse,carry ? 1 : 0);
    if (carry) attachmouse(index);
    mousesound = 0; ++mouseevents;
}
void simulation::retreatmouse(int index) {
    if (index < 0 || mice[index].retreat) return;
    auto& mouse = mice[index];
    if (!mouse.carry) mouse.eyes = -1;
    mouse.retreat = true; mouse.active = mouse.grabbing = false; mouse.elapsed = 0; mouse.bounce = -1;
    mouse.path = 2; mouse.pathage = 0; mouse.offset = mouse.exit[0];
    sequence(mouse,mouse.carry ? 5 : 4);
}
void simulation::dropmouse() {
    if (activemouse < 0 || !mice[activemouse].carry) return;
    mice[activemouse].carry = mice[activemouse].grabbing = false;
    nogravity = inlantern; bodies[0].previous = bodies[0].pos; ++mousereleases;
}
bool simulation::mousepress(point position) {
    if (activemouse < 0) return false;
    const auto& mouse = mice[activemouse]; const auto& source = definition.mice[activemouse];
    if (!mouse.active || mouse.retreat || !mouse.carry || (position-source.position).length() >= source.radius) return false;
    dropmouse(); retreatmouse(activemouse); mousesound = 2; ++mouseevents;
    return true;
}
void simulation::stopmice() {
    if (micelocked) return;
    dropmouse(); retreatmouse(activemouse); micelocked = true;
    if (activemouse >= 0) { mice[activemouse].active = false; mice[activemouse].retreat = true; }
}
void simulation::resetnocturnal() {
    mice = {}; activemouse = -1; micelocked = false;
    mousecaptures = mousereleases = mousehandoffs = mouseevents = mousesound = 0;
    for (int i = 0; i < definition.mousecount; ++i) {
        auto& mouse = mice[i];
        static constexpr float entry[] = {-4.4f,-61,-70,-66}, exit[] = {-36.4f,-43.2f,-9.2f};
        for (int j = 0; j < 4; ++j) mouse.entry[j] = rotate({0,entry[j]},definition.mice[i].angle);
        for (int j = 0; j < 3; ++j) mouse.exit[j] = rotate({0,exit[j]},definition.mice[i].angle);
        if (definition.mice[i].index == 1 || activemouse < 0) spawnmouse(i,false);
    }
    bulbalive = definition.bulbcount > 0; bulbbubble = bulbtransit = -1;
    bulbtime = bulbspeed = candytime = sleeptime = 0;
    awake = nightwoken = false; nightstart = sleepevents = 0;
    starlit.fill(false); pickuplit.fill(false); lightalpha.fill(0); lightchange.fill(-1000);
}
void simulation::updatemice() {
    static constexpr int quads[][4] = {{1,2,3,14},{17,19,21,24},{4,4,4,4},{24,24,24,24},{14,15,16,18},{24,26,28,18}};
    for (int i = 0; i < definition.mousecount; ++i) {
        auto& mouse = mice[i];
        if (mouse.container) {
            auto& owner = mice[activemouse];
            owner.age += delta;
            if (owner.phase == 0 || owner.phase == 1 || owner.phase == 4 || owner.phase == 5) {
                owner.quad = quads[owner.phase][std::min(3,static_cast<int>((owner.age+1e-7f)/.05f))];
                if (owner.age >= .15f-1e-6f) {
                    if (owner.phase < 2) {
                        const bool carry = owner.phase == 1;
                        owner.elapsed = 0; owner.active = true;
                        sequence(owner,carry ? 3 : 2);
                        if (!carry) owner.eyes = 0;
                    } else {
                        owner.phase = 6; owner.container = false;
                        if (!micelocked) {
                            int next = -1, first = 0;
                            for (int n = 0; n < definition.mousecount; ++n) {
                                if (definition.mice[n].index < definition.mice[first].index) first = n;
                                if (definition.mice[n].index > definition.mice[activemouse].index &&
                                    (next < 0 || definition.mice[n].index < definition.mice[next].index)) next = n;
                            }
                            const bool carry = owner.carry; owner.carry = false;
                            spawnmouse(next < 0 ? first : next,carry); ++mousehandoffs;
                        }
                    }
                }
            }
            auto& current = mice[activemouse];
            if (current.eyes >= 0) current.eyes += delta;
            if (current.bounce >= 0) { current.bounce += delta; if (current.bounce >= .15f-1e-6f) current.bounce = -1; }
        }
        if (mouse.path) {
            const point* offsets = mouse.path == 1 ? mouse.entry.data() : mouse.exit.data();
            const int end = mouse.path == 1 ? 3 : 2;
            mouse.pathage += delta;
            if (mouse.pathage >= end*.05f) { mouse.offset = offsets[end]; mouse.path = 0; mouse.grabbing = false; }
            else {
                const int index = static_cast<int>(mouse.pathage/.05f);
                const float start = index*.05f, finish = (index+1)*.05f;
                mouse.offset = offsets[index]+(offsets[index+1]-offsets[index])*((mouse.pathage-start)/(finish-start));
            }
        }
        if (mouse.carry) bodies[0].pos = bodies[0].previous = definition.mice[i].position+mouse.offset;
        if (mouse.active && !mouse.retreat && !mouse.grabbing) {
            mouse.elapsed += delta;
            if (mouse.elapsed >= definition.mice[i].duration && mouse.bounce < 0) retreatmouse(i);
        }
    }
    if (activemouse < 0 || micelocked || state != outcome::playing || split || hidden()) return;
    auto& mouse = mice[activemouse]; const auto& source = definition.mice[activemouse];
    if (mouse.active && !mouse.carry && (bodies[0].pos-source.position).length() < source.radius) {
        // ReleaseRopesForPoint cuts at the tail but retains the normal delayed
        // detachment. The carry's position is the only physics authority.
        for (int i = 0; i < definition.hookcount; ++i) if (ropes[i].count && ropes[i].candy == 0 && !ropes[i].cut) sever(i,ropes[i].count-2);
        attachmouse(activemouse); mouse.quad = 24; mouse.bounce = 0;
        ++mousecaptures; mousesound = 1; ++mouseevents;
    }
}
bool simulation::illuminated(point position) const {
    if (!bulbalive || bulbtransit >= 0) return false;
    const auto d = position-bodies[3].pos;
    return d.x*d.x+d.y*d.y < definition.bulbs[0].radius*definition.bulbs[0].radius;
}
void simulation::collidelight() {
    if (!definition.bulbcount || !bulbalive || bulbtransit >= 0 || !available(0)) return;
    for (int i = 0; i < candycount(); ++i) {
        auto& a = bodies[activeid(i)]; auto& b = bodies[3];
        auto d = a.pos-b.pos;
        constexpr float radius = 94.5f;
        if (d.x*d.x+d.y*d.y >= radius*radius) continue;
        const float distance = d.length(), penetration = radius-distance, half = penetration*.5f;
        const auto n = d*(distance > 0 ? 1/distance : 0);
        const float speed = a.velocity.length()+b.velocity.length();
        const bool full = speed > 0 && penetration >= 2000/speed;
        if (full) {
            const float x = -d.x, y = -d.y, c = x/radius, s = y/radius;
            const auto av = a.velocity, bv = b.velocity;
            const float t28 = x*av.x, t30 = y*av.x;
            const float t29 = (t28+y*av.y)/radius, t31 = (t30+x*bv.x)/radius;
            const float t32 = (x*av.y-t30)/radius, t35 = (t28-bv.x*y)/radius;
            a.velocity = {t31*c-t32*s,t32*c+t31*s}; b.velocity = {t29*c-t35*s,t35*c+t29*s};
        }
        a.pos = a.pos+n*half; b.pos = b.pos-n*half;
        if (full) { a.previous = a.pos-a.velocity/60; b.previous = b.pos-b.velocity/60; }
    }
}
void simulation::updatelight() {
    if (!definition.night) return;
    for (int i = 0; i < 3; ++i) {
        pickuplit[i] = starlit[i];
        lightedge[i] = (definition.stars[i]+definition.starmotions[i].at(std::max(0,visuals-1)*delta)-bodies[3].pos).length()-definition.bulbs[0].radius;
        if (!stars[i] && !expired[i]) {
            const bool lit = illuminated(definition.stars[i]+definition.starmotions[i].at(std::max(0,visuals-1)*delta));
            if (lit != starlit[i]) lightchange[i] = visuals;
            starlit[i] = lit;
        }
        lightalpha[i] = std::clamp(lightalpha[i]+(starlit[i]?.1f:-.1f),0.0f,1.0f);
    }
    const bool lit = illuminated(definition.target);
    if (state == outcome::playing && awake != lit) {
        awake = lit; nightstart = visuals; sleeptime = 0;
        if (lit) { excitement = visuals; nightwoken = true; }
    }
    if (!awake && state == outcome::playing) {
        sleeptime += delta;
        if (sleeptime >= 4) { sleeptime -= 4; ++sleepevents; }
    }
}
void simulation::retirebulb() {
    if (!bulbalive) return;
    releasecandy(3); burst(3,false); bulbalive = false;
    if (definition.night && state == outcome::playing) {
        state = outcome::lost; failreason = 4; resulttick = ticks; resultvisual = visuals;
        // Lights-out triggers GameLost, not candy removal. Keep its ropes,
        // bubble and motion alive throughout the restart delay.
    }
}
void simulation::advancelighttransport() {
    if (!definition.bulbcount) return;
    for (int id : {0,3}) {
        int& transport = id ? bulbtransit : transit;
        float& time = id ? bulbtime : candytime;
        if (transport < 0) continue;
        time -= delta;
        if (time > 0) continue;
        const auto& hat = definition.hats[transport];
        const float angle = hat.path.angle(hat.angle,(visuals-1)*delta,hat.resetangle);
        auto& body = bodies[id];
        body.pos = hat.position+hat.path.at((visuals-1)*delta)+rotate({0,-16},angle);
        body.velocity = rotate({0,-1},angle)*(id ? bulbspeed : exitspeed);
        body.previous = body.pos-body.velocity/60;
        hatages[transport] = 0; transport = -1;
    }
}
void simulation::lighttransports() {
    for (int i = 0; i < definition.hatcount; ++i) {
        if (hattimers[i] > 0) continue;
        const auto& hat = definition.hats[i];
        const auto center = hat.position+hat.path.at(visuals*delta);
        const float angle = hat.path.angle(hat.angle,visuals*delta,hat.resetangle);
        for (int id : {0,3}) {
            if (!available(id) || rotate(bodies[id].velocity,-angle).y < 0) continue;
            bool hit = false;
            for (int side : {0,15}) hit = hit || linebox(center+rotate({-90,static_cast<float>(side)},angle),center+rotate({50,static_cast<float>(side)},angle),bodies[id].pos,20);
            if (!hit) continue;
            for (int j = 0; j < definition.hatcount; ++j) if (j != i && definition.hats[j].group == hat.group) {
                (id ? bulbspeed : exitspeed) = (.9f*bodies[id].velocity.length())*1.4f;
                for (int r = 0; r < definition.hookcount; ++r) if (ropes[r].count && ropes[r].candy == id && !ropes[r].cut) sever(r,ropes[r].count-2);
                (id ? bulbtransit : transit) = j; (id ? bulbtime : candytime) = .1f;
                hattimers[j] = .8f; hatages[i] = 0; ++teleportevents;
                return;
            }
        }
    }
}
}
