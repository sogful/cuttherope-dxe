#include "simulation.hpp"
#include <algorithm>

namespace dx {
static constexpr float delta = .016f, radians = 3.14159265f / 180;
static point rotate(point p, float angle) {
    const float s = std::sin(angle * radians), c = std::cos(angle * radians);
    return {p.x * c - p.y * s, p.x * s + p.y * c};
}
point motion::at(float time) const {
    const float length = offset.length();
    if (length == 0 || speed <= 0) return {};
    const float phase = std::fmod(time * speed / length, 2.0f);
    return offset * (phase <= 1 ? phase : 2 - phase);
}
void simulation::animate() {
    ++visuals;
    ++popage;
    for (int& age : pumpages) age = std::min(100, age + 1);
    for (int i = 0; i < 3; ++i) starpositions[i] = definition.stars[i] + definition.starmotions[i].at(visuals * delta);
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
void simulation::burst() {
    if (bubble < 0) return;
    bubble = -1;
    popposition = candy().pos;
    popage = 0;
    ++pops;
}
bool simulation::interact(point position) {
    if (state != outcome::playing || introduction) return false;
    const auto difference = position - candy().pos;
    if (bubble >= 0 && difference.x >= -60 && difference.x < 60 && difference.y >= -60 && difference.y < 60) {
        burst();
        return true;
    }
    for (int i = 0; i < definition.pumpcount; ++i) {
        const auto& pump = definition.pumps[i];
        const auto local = rotate(position - pump.position, -pump.angle);
        if (std::abs(local.x) > 87.5f || std::abs(local.y) > 87.5f) continue;
        pumpages[i] = 0;
        ++pumpevents;
        const auto target = rotate(candy().pos - pump.position, -pump.angle);
        if (target.y < 0 && target.y > -711.5f && std::abs(target.x) < 175) {
            bodies[0].pos = bodies[0].pos + rotate({0, -2 * (624 + target.y)}, pump.angle) * delta;
        }
        return true;
    }
    return false;
}
void simulation::fail(int reason) {
    if (state != outcome::playing) return;
    state = outcome::lost;
    failreason = reason;
    resulttick = ticks;
    bodies[0].pin = bodies[0].pos;
    bodies[0].pinned = true;
    burst();
}
static bool segment(point a, point b, point c, point d) {
    auto cross = [](point p, point q) { return p.x * q.y - p.y * q.x; };
    const auto v = b - a, w = d - c;
    const float denominator = cross(v, w);
    if (std::abs(denominator) < .0001f) return false;
    const float t = cross(c - a, w) / denominator, u = cross(c - a, v) / denominator;
    return t >= 0 && t <= 1 && u >= 0 && u <= 1;
}
static bool linebox(point a, point b, point center) {
    a = a - center; b = b - center;
    if (std::abs(a.x) <= 15 && std::abs(a.y) <= 15) return true;
    if (std::abs(b.x) <= 15 && std::abs(b.y) <= 15) return true;
    const point corners[] = {{-15,-15},{15,-15},{15,15},{-15,15}};
    for (int i = 0; i < 4; ++i) if (segment(a, b, corners[i], corners[(i + 1) % 4])) return true;
    return false;
}
void simulation::hazards() {
    static constexpr float widths[] = {212,333,453,566};
    for (int i = 0; i < definition.spikecount; ++i) {
        const auto& spike = definition.spikes[i];
        const auto center = spike.anchor + spike.path.at(visuals * delta);
        const float angle = spike.angle + spike.path.rotation * visuals * delta;
        for (int side : {-1, 1}) {
            const auto a = center + rotate({-widths[spike.size - 1] / 2, side * 5.0f}, angle);
            const auto b = center + rotate({widths[spike.size - 1] / 2, side * 5.0f}, angle);
            if (linebox(a, b, candy().pos) || segment(a, b, candy().previous, candy().pos)) { fail(2); return; }
        }
    }
}
void simulation::spiders() {
    for (int i = 0; i < definition.hookcount; ++i) {
        auto& rope = ropes[i];
        if (!definition.hooks[i].spider || rope.count == 0 || rope.cut) continue;
        if ((visuals - rope.attached) * delta < .75f) continue;
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
                if (j == size - 1) fail(3);
                break;
            }
            passed += length;
        }
    }
}
}
