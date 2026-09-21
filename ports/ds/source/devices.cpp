#include "simulation.hpp"
#include "geometry.hpp"
#include "routes.hpp"
#include <algorithm>

namespace dx {
static constexpr float delta = .016f;
static constexpr float heights[] = {32.9f,94,141};
float simulation::steamheight(int index) const {
    return definition.tubes[index].scale * heights[tubes[index].state] + definition.tubes[index].scale * std::sin(6 * tubes[index].phase);
}
point simulation::valvepoint(int index) const {
    const auto& tube = definition.tubes[index];
    return tube.position + rotate({0,28*tube.scale},tube.angle);
}
void simulation::cachetube(int index) {
    auto& state = tubes[index]; const auto& tube = definition.tubes[index];
    if (state.angle == tube.angle && state.scale == tube.scale) return;
    state.angle = tube.angle; state.scale = tube.scale;
    state.forward = rotate({1,0},tube.angle); state.backward = rotate({1,0},-tube.angle);
    state.lift = -32*std::sqrt(tube.scale);
}
void simulation::adjuststeam(int index) {
    auto& tube = tubes[index];
    for (auto& p : tube.puffs) if (p.start > -100 && p.stop < 0)
        p.stop = p.start + std::max(1.0f,std::floor(std::max(0.0f,steamtime-p.start)/.6f)+1)*.6f;
    const int count = tube.state == 0 ? 7 : tube.state == 1 ? 14 : 20;
    for (int i = 0; i < count; ++i) {
        puff* slot = nullptr;
        for (auto& p : tube.puffs) if (p.start == -100 || (p.stop >= 0 && p.stop <= steamtime)) { slot = &p; break; }
        if (!slot) {
            slot = &tube.puffs[0];
            for (auto& p : tube.puffs) if (p.stop >= 0 && (slot->stop < 0 || p.stop < slot->stop)) slot = &p;
        }
        float height = -heights[tube.state]*definition.tubes[index].scale*(1+.1f*((i*73+index*31+tube.revision*19)%101/50.0f-1));
        if (i%3) height *= tube.state == 1 ? .95f : tube.state == 2 ? .94f : 1;
        *slot = {steamtime+.6f*i/count,-1,static_cast<float>(static_cast<int>(height)),2-i%3,i%3==0?0:i%3==1?tube.state:-tube.state};
    }
}
bool simulation::valvetap(int index) {
    if (index < 0 || index >= definition.tubecount) return false;
    auto& tube = tubes[index];
    const bool reverse = tube.state == 2;
    tube.state = (tube.state+1)%3; tube.phase = 0; ++tube.revision;
    if (tube.valveage >= .55f) { tube.valveage = 0; tube.valve = 0; tube.reverse = reverse; }
    steamstate = tube.state; ++steamevents;
    adjuststeam(index);
    return true;
}
void simulation::capturelantern(int index, int count) {
    sharedlantern = nogravity = true;
    bodies[0].pos = bodies[0].previous = lanterns[index].position;
    ++captures;
    for (int i = 0; i < count; ++i) {
        auto& item = lanterns[i];
        item.state = item.phase = 1; item.age = 0;
        item.cooldown = item.release = -1;
        item.firestart = .4f*((i*37+captures*13)%101)/100;
        item.idlestart = .2f+.2f*((i*53+captures*23)%101)/100;
    }
}
void simulation::resetdevices() {
    tubes = {}; lanterns = {}; reveals.fill(-1);
    steamevents = steamstate = captures = releases = 0;
    steamtime = 0; capturetimer = -1; pendinglantern = -1; captureage = 1;
    inlantern = sharedlantern = nogravity = false;
    for (int i = 0; i < definition.tubecount; ++i) { cachetube(i); adjuststeam(i); }
    for (int i = 0; i < definition.lanterncount; ++i) {
        auto& item = lanterns[i];
        item.position = item.previous = definition.lanterns[i].position;
        sharedlantern = false;
        if (definition.lanterns[i].captured) { inlantern = true; capturelantern(i,i+1); }
    }
    candydraw = bodies[0].pos;
}
bool simulation::lanterntap(int index) {
    if (index < 0 || index >= definition.lanterncount || lanterns[index].state != 1 || !sharedlantern) return false;
    for (int i = 0; i < definition.lanterncount; ++i) {
        auto& item = lanterns[i];
        item.phase = 2; item.age = 0; item.cooldown = .5f; item.release = -1;
    }
    lanterns[index].release = .01f;
    for (float& reveal : reveals) if (reveal < 0) { reveal = .1f; break; }
    ++releases;
    return true;
}
void simulation::advancedevices() {
    steamtime += delta;
    if (pendinglantern >= 0) {
        capturetimer -= delta;
        if (capturetimer <= 0) {
            if (inlantern && state == outcome::playing) capturelantern(pendinglantern,definition.lanterncount);
            pendinglantern = -1;
        }
    }
    for (float& reveal : reveals) if (reveal >= 0) {
        reveal -= delta;
        if (reveal <= 0) { reveal = -1; inlantern = false; captureage = 1; }
    }
    for (int i = 0; i < definition.tubecount; ++i) {
        cachetube(i);
        auto& tube = tubes[i]; tube.phase += delta;
        if (tube.valveage < .55f) {
            tube.valveage = std::min(.55f,tube.valveage+delta);
            tube.valve = (tube.reverse?-1:1)*180*tube.valveage/.55f;
        }
    }
}
void simulation::updatedevices() {
    for (int i = 0; i < definition.tubecount && (state == outcome::playing || (state == outcome::lost && split && activecount())) && !hidden(); ++i) {
        const auto& tube = definition.tubes[i];
        const float width = 10*tube.scale, radius = 17.5f*tube.scale, height = steamheight(i);
        const bool aligned = (tube.angle == 0 && !inverted) || (tube.angle == 180 && inverted);
        const float damping = aligned ? 5 : 75;
        const float compensation = tubes[i].lift/(aligned?1:(tube.angle==90 || tube.angle==270)?4:2);
        const auto forward = tubes[i].forward, backward = tubes[i].backward;
        auto transform = [](point p, point axis) { return point{p.x*axis.x-p.y*axis.y,p.x*axis.y+p.y*axis.x}; };
        for (int part = 0; part < activecount(); ++part) {
            auto& body = bodies[activeid(part)];
            const auto p = transform(body.pos-tube.position,backward)+tube.position;
            const auto v = transform(body.velocity,backward);
            if (p.x-radius>tube.position.x+width/2 || p.x+radius<tube.position.x-width/2 ||
                p.y-radius/2>tube.position.y-radius || p.y+radius<tube.position.y-height-tube.scale) continue;
            const float x = tube.position.x-p.x;
            const float horizontal = !aligned?0:std::abs(x)>width/4 ? -v.x/5+.25f*x:std::abs(v.x)<1?-v.x:-v.x/5;
            point impulse{horizontal,-v.y/damping+compensation};
            const float distance = tube.position.y-p.y;
            if (distance > height+radius) impulse = impulse*std::exp(-2*(distance-(height+radius)));
            body.pos = body.pos+transform(impulse,forward)*delta;
        }
    }
    for (int i = 0; i < definition.lanterncount; ++i) {
        auto& item = lanterns[i]; const auto& source = definition.lanterns[i];
        item.previous = item.position;
        if (source.route >= 0) {
            const auto& route = routes[source.route];
            if (visuals == 1) { item.position = routepoints[route.first]; item.target %= route.count; }
            float remaining = delta;
            for (int guard = 0; remaining > 0 && source.path.speed > 0 && guard <= route.count; ) {
                const auto end = routepoints[route.first+item.target], d = end-item.position;
                const float distance = d.length(), duration = distance/source.path.speed;
                if (duration <= remaining) { item.position = end; remaining -= duration; item.target = (item.target+1)%route.count; ++guard; }
                else { item.position = item.position+d*(1/distance)*(source.path.speed*remaining); remaining = 0; }
            }
            item.angle += source.path.rotation*delta;
        }
        item.age += delta;
        if (item.cooldown >= 0) { item.cooldown -= delta; if (item.cooldown <= 0) { item.state = 0; item.cooldown = -1; } }
        if (item.release >= 0) {
            item.release -= delta;
            if (item.release <= 0) {
                item.release = -1;
                if (sharedlantern) {
                    nogravity = false; bodies[0].pos = item.position; bodies[0].previous = item.previous; sharedlantern = false;
                }
            }
        }
        if (sharedlantern) { bodies[0].pos = bodies[0].previous = item.position; item.state = 1; }
        if (item.state == 0 && !hidden() && !split && state == outcome::playing && (bodies[0].pos-item.position).length() < 82) {
            inlantern = nogravity = true;
            capturefrom = {static_cast<float>(static_cast<int>(candydraw.x)),static_cast<float>(static_cast<int>(candydraw.y))};
            captureto = {static_cast<float>(static_cast<int>(item.position.x)),static_cast<float>(static_cast<int>(item.position.y))};
            captureage = 0;
            for (int r = 0; r < definition.hookcount; ++r) if (ropes[r].count && ropes[r].candy == 0) {
                if (!ropes[r].cut) sever(r,ropes[r].count-2); else ropes[r].hidetail = true;
            }
            burst(); pendinglantern = i; capturetimer = .05f;
        }
    }
}
void simulation::removelantern() {
    pendinglantern = -1; capturetimer = -1; captureage = 1; inlantern = nogravity = false; reveals.fill(-1);
    if (!sharedlantern) return;
    sharedlantern = false;
    for (auto& item : lanterns) { item.state = item.phase = 0; item.age = 0; item.release = item.cooldown = -1; }
}
}
