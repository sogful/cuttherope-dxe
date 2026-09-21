#include "simulation.hpp"
#include "geometry.hpp"
#include "routes.hpp"
#include <algorithm>

namespace dx {
static constexpr float delta = .016f, radians = 3.14159265f / 180;
point rotate(point p, float angle) {
    // CTRMathHelper.FmSin/FmCos quantize to 1024 entries, truncating signed
    // angles before masking. Exact trig changes angled bouncer trajectories.
    const float rad = angle * 3.14159265f / 180;
    const int index = static_cast<int>(rad * 1024 / 6.2831853f) & 1023;
    const float quantized = index * 2 * 3.14159265f / 1024;
    const float s = std::sin(quantized), c = std::cos(quantized);
    return {p.x * c - p.y * s, p.x * s + p.y * c};
}
point motion::at(float time) const {
    if (route >= 0) {
        const auto& path = routes[route];
        float length = 0;
        for (int i = 0; i < path.count; ++i) length += (routepoints[path.first+(i+1)%path.count]-routepoints[path.first+i]).length();
        if (length <= 0) return {};
        float remaining = std::fmod(time*speed,length);
        for (int i = 0; i < path.count; ++i) {
            const auto a = routepoints[path.first+i], d = routepoints[path.first+(i+1)%path.count]-a;
            const float size = d.length();
            if (size > 0 && remaining < size) return a+d*(remaining/size);
            remaining -= size;
        }
        return routepoints[path.first];
    }
    if (circle != 0) {
        const float radius = std::abs(circle);
        const int count = static_cast<int>(radius) / 2;
        if (count < 2) return {};
        const float turn = 6.2831853f / count * (circle < 0 ? -1 : 1);
        const float chord = 2 * radius * std::sin(std::abs(turn) / 2);
        const float phase = time * speed / chord;
        const int index = static_cast<int>(std::floor(phase));
        const float amount = phase - index;
        const point a{std::cos((index % count) * turn),std::sin((index % count) * turn)};
        const point b{std::cos(((index + 1) % count) * turn),std::sin(((index + 1) % count) * turn)};
        return (a * (1 - amount) + b * amount) * radius;
    }
    const float length = offset.length();
    if (length == 0 || speed <= 0) return {};
    const float phase = std::fmod(time * speed / length, 2.0f);
    return offset * (phase <= 1 ? phase : 2 - phase);
}
float motion::angle(float base, float time, bool reset) const {
    if (reset && circle && speed > 0) {
        const float radius = std::abs(circle);
        const int count = static_cast<int>(radius) / 2;
        const float segmenttime = 2 * radius * std::sin(3.14159265f / count) / speed;
        const float duration = segmenttime * count;
        const int cycle = static_cast<int>(time / duration);
        const float phase = std::fmod(time, duration);
        if (phase >= segmenttime * (count - 1)) time = 0;
        else if (cycle) {
            // Mover resets on an update whose target is the first vertex, then
            // resumes with a *whole* .016 rotation step when crossing that vertex.
            // Subtracting fractional lap time loses that first partial frame.
            time = (std::lround(time / delta) - std::floor(cycle * duration / delta)) * delta;
        }
    }
    return base + rotation * time;
}
void simulation::animate() {
    ++visuals;
    advancedevices();
    updatediscs();
    for (int i = 0; i < definition.spikecount; ++i) spikeages[i] = std::min(spikeduration[i], spikeages[i] + delta);
    gravityage = std::min(100, gravityage + 1);
    ++popage;
    for (int& age : pumpages) age = std::min(100, age + 1);
    for (int& age : bounceages) age = std::min(100, age + 1);
    for (int& age : hatages) age = std::min(100, age + 1);
    ++mergeage;
    for (float& time : hattimers) time = std::max(0.0f, time - delta);
    for (int i = 0; i < definition.spikecount; ++i) if (definition.spikes[i].size == 5) {
        float& time = electrotimers[i];
        time += std::clamp(-time, -delta, delta);
        if (time == 0) { electric[i] = !electric[i]; time = electric[i] ? definition.spikes[i].on : definition.spikes[i].off; }
    }
    for (int i = 0; i < 3; ++i) if (!stars[i] && !expired[i] && !belted(1,i)) starpositions[i] = definition.stars[i] + definition.starmotions[i].at(visuals * delta);
}
void simulation::camera() {
    const float target = std::clamp(candy().pos.y - 720, 0.0f, std::max(0.0f, definition.height - 1440));
    const float difference = target - cameray, distance = std::abs(difference);
    if (introduction) {
        cameray += std::clamp(difference, -cameraspeed * delta, cameraspeed * delta);
        cameraspeed = distance > cameradistance / 2 ? std::min(1000.0f, cameraspeed + 800 * delta) : std::max(300.0f, cameraspeed - 400 * delta);
        if (std::abs(target - cameray) < 1) { cameray = target; introduction = false; }
    } else cameray += difference * 14 * delta;
}
void simulation::burst(int id, bool sound) {
    int& active = bubbleindex(id);
    if (active < 0) return;
    releaseghost(id);
    active = -1;
    popposition = bodies[id].pos;
    popage = 0;
    if (sound) ++pops;
}
bool simulation::interact(point position) {
    if (state != outcome::playing || introduction) return false;
    draghook = -1;
    dragwheel = dragswitch = dragspike = -1;
    dragdisc = -1;
    if (mousepress(position)) return true;
    for (int i = 0; i < definition.tubecount; ++i)
        if ((position-valvepoint(i)).length() < 40*definition.tubes[i].scale) return valvetap(i);
    for (int i = 0; i < definition.lanterncount; ++i)
        if ((position-lanterns[i].position).length() < 85 && lanterntap(i)) return true;
    if (pressdisc(position)) return true;
    for (int i = 0; i < definition.ghostcount; ++i)
        if ((position - definition.ghosts[i].position).length() < 80 && ghosttap(i)) return true;
    for (int i = 0; i < definition.spikecount; ++i) if (spikehit(i, position)) { dragspike = i; return true; }
    for (int i = 0; i < definition.switchcount; ++i) {
        const auto d = position - definition.switches[i];
        if (d.x >= -115.5f && d.x < 115.5f && d.y >= -116.5f && d.y < 116.5f) { dragswitch = i; return true; }
    }
    for (int part = 0; part < activecount(); ++part) {
        const int id = activeid(part);
        if (!available(id)) continue;
        const auto difference = position - bodies[id].pos;
        if (bubblefor(id) >= 0 && difference.x >= -60 && difference.x < 60 && difference.y >= -60 && difference.y < 60) {
            burst(id);
            return true;
        }
    }
    for (int i = 0; i < definition.hookcount; ++i) {
        const auto difference = position - anchors[i];
        if (definition.hooks[i].wheel && difference.x >= -110 && difference.x < 110 && difference.y >= -110 && difference.y < 110) {
            dragwheel = i; wheeltouch = position; return true;
        }
        if (definition.hooks[i].rail > 0 && std::abs(difference.x) <= 65 && std::abs(difference.y) <= 65) {
            draghook = i;
            return true;
        }
    }
    for (int i = 0; i < definition.pumpcount; ++i) {
        const auto& pump = definition.pumps[i];
        const auto local = rotate(position - pump.position, -pump.angle);
        if (std::abs(local.x) > 87.5f || std::abs(local.y) > 87.5f) continue;
        pumpages[i] = 0;
        ++pumpevents;
        for (int part = 0; part < activecount(); ++part) {
            if (!available(activeid(part))) continue;
            auto& body = bodies[activeid(part)];
            const auto target = rotate(body.pos - pump.position, -pump.angle);
            if (target.y < 0 && target.y > -711.5f && std::abs(target.x) < 175)
                body.pos = body.pos + rotate({0, -2 * (624 + target.y)}, pump.angle) * delta;
        }
        return true;
    }
    return pressbelt(position);
}
void simulation::retirehalf(int id, int reason) {
    if (suppressoutcome || !id || !halfalive[id-1]) return;
    releasecandy(id); burst(id,false); halfalive[id-1] = false;
    bodies[id].pin = bodies[id].pos; bodies[id].pinned = true;
    if (state == outcome::playing) { cancelbelts(); state = outcome::lost; failreason = reason; resulttick = ticks; resultvisual = visuals; }
}
void simulation::fail(int reason) {
    if (suppressoutcome || state != outcome::playing) return;
    removelantern();
    stopmice();
    cancelbelts();
    for (int part = 0; part < activecount(); ++part) releasecandy(activeid(part));
    state = outcome::lost;
    failreason = reason;
    resulttick = ticks;
    resultvisual = visuals;
    for (int part = 0; part < activecount(); ++part) {
        const int id = activeid(part);
        bodies[id].pin = bodies[id].pos; bodies[id].pinned = true; burst(id,false);
    }
}
bool segment(point a, point b, point c, point d) {
    auto cross = [](point p, point q) { return p.x * q.y - p.y * q.x; };
    const auto v = b - a, w = d - c;
    const float denominator = cross(v, w);
    if (std::abs(denominator) < .0001f) return false;
    const float t = cross(c - a, w) / denominator, u = cross(c - a, v) / denominator;
    return t >= 0 && t <= 1 && u >= 0 && u <= 1;
}
bool linebox(point a, point b, point center, float radius) {
    a = a - center; b = b - center;
    if (std::abs(a.x) <= radius && std::abs(a.y) <= radius) return true;
    if (std::abs(b.x) <= radius && std::abs(b.y) <= radius) return true;
    const point corners[] = {{-radius,-radius},{radius,-radius},{radius,radius},{-radius,radius}};
    for (int i = 0; i < 4; ++i) if (segment(a, b, corners[i], corners[(i + 1) % 4])) return true;
    return false;
}
void simulation::hazards() {
    if (hidden()) return;
    static constexpr float widths[] = {212,333,453,566,433};
    for (int i = 0; i < definition.spikecount; ++i) {
        const auto& spike = definition.spikes[i];
        if (spike.size == 5 && !electric[i]) continue;
        const auto center = spikeposition(i);
        const float angle = spikeangle(i);
        static constexpr float toggledwidths[] = {202,319,444,559};
        const float width = spike.group >= 0 && spike.size < 5 ? toggledwidths[spike.size - 1] : widths[spike.size - 1];
        for (int side : {-1, 1}) {
            const auto a = center + rotate({-width / 2, side * 5.0f}, angle);
            const auto b = center + rotate({width / 2, side * 5.0f}, angle);
            for (int part = 0; part < candycount(); ++part) {
                const auto& body = bodies[activeid(part)];
                if (linebox(a, b, body.pos) || segment(a, b, body.previous, body.pos)) {
                    if (split) retirehalf(activeid(part),2); else fail(2);
                    return;
                }
            }
        }
    }
}
void simulation::spiders() {
    for (int i = 0; i < definition.hookcount; ++i) {
        auto& rope = ropes[i];
        if (!definition.hooks[i].spider || rope.count == 0 || rope.cut || rope.spiderstate) continue;
        if ((visuals - rope.attached) * delta < .75f) continue;
        if ((visuals - rope.attached - 1) * delta < .75f) ++spideractivations;
        rope.spiderdistance += 117 * delta;
        point curve[125]; int size;
        samples(i, 0, rope.count, curve, size);
        float passed = 0;
        for (int j = 1; j < size; ++j) {
            const auto edge = curve[j] - curve[j - 1];
            const float length = std::max(70.0f, edge.length());
            if (rope.spiderdistance < passed + length || j == size - 1) {
                rope.spiderpos = curve[j - 1] + edge * ((rope.spiderdistance - passed) / length);
                rope.spiderangle = std::atan2(edge.y, edge.x) / radians + 270;
                if (j == size - 1 && !suppressoutcome) { dropspider(i, true); fail(3); }
                break;
            }
            passed += length;
        }
    }
}
}
