#include "simulation.hpp"
#include <algorithm>

namespace dx {
constexpr float delta = 0.016f;

int simulation::add(point position, float inverse, bool pinned) {
    const int index = bodycount++;
    body& item = bodies[index];
    item = {};
    item.pos = item.pin = position;
    item.inverse = inverse;
    item.pinned = pinned;
    return index;
}

void simulation::reset(const level& data) {
    definition = data;
    bodies = {};
    ropes = {};
    stars = {};
    collectedat = {};
    bodycount = ticks = count = resulttick = mouthtick = 0;
    mouth = false;
    state = outcome::playing;
    add(data.candy, 1, false);
    bodies[0].previous = data.candy;
    bodies[0].initialized = true;
    for (int index = 0; index < data.hookcount; ++index) {
        const hook& source = data.hooks[index];
        rope& item = ropes[index];
        item.bodies[item.count++] = add(source.anchor, 50, true);
        const int segments = static_cast<int>(std::ceil(source.length / 105.0f));
        const point offset = (data.candy - source.anchor) / std::floor(source.length / 105.0f + 2);
        for (int segment = 0; segment < segments; ++segment) {
            const int previous = item.bodies[item.count - 1];
            const int current = add(bodies[previous].pos + offset, 50, false);
            bodies[current].links[0] = {previous, 105, true};
            bodies[current].linkcount = 1;
            item.bodies[item.count++] = current;
        }
        bodies[0].links[bodies[0].linkcount++] = {
            item.bodies[item.count - 1], source.length + 105 - segments * 105, true};
        item.bodies[item.count++] = 0;
    }
}

void simulation::integrate(body& item, float acceleration) {
    if (!item.initialized) {
        item.previous = item.pos;
        item.initialized = true;
    }
    const point displacement = item.pos - item.previous + point{0, acceleration};
    item.previous = item.pos;
    item.pos = item.pos + displacement;
}

void simulation::satisfy(body& item) {
    if (item.pinned) { item.pos = item.pin; return; }
    for (int index = 0; index < item.linkcount; ++index) {
        const constraint& link = item.links[index];
        if (!link.active) continue;
        body& other = bodies[link.other];
        point difference = other.pos - item.pos;
        if (difference.x == 0 && difference.y == 0) {
            if (link.length == 0) continue;
            difference = {1, 1};
        }
        const float length = difference.length();
        const float factor = (length - link.length) / (std::max(length, 1.0f) * (item.inverse + other.inverse));
        item.pos = item.pos + difference * (item.inverse * factor);
        if (!other.pinned) other.pos = other.pos - difference * (other.inverse * factor);
    }
}

void simulation::detach(rope& item) {
    const int segment = item.pending;
    item.pending = -1;
    const int previous = item.bodies[segment];
    body& next = bodies[item.bodies[segment + 1]];
    for (int link = 0; link < next.linkcount; ++link) {
        if (!next.links[link].active || next.links[link].other != previous) continue;
        next.links[link].active = false;
        const int tip = add(next.pos, 100000, false);
        bodies[tip].initialized = next.initialized;
        bodies[tip].previous = next.previous;
        bodies[tip].links[0] = {previous, 105, true};
        bodies[tip].linkcount = 1;
        for (int index = item.count; index > segment + 1; --index) item.bodies[index] = item.bodies[index - 1];
        item.bodies[segment + 1] = tip;
        ++item.count;
        item.split = segment + 2;
        break;
    }
    for (int index = 0; index < item.count; ++index) {
        if (item.bodies[index] != 0) bodies[item.bodies[index]].inverse = 100000;
    }
}

void simulation::tick() {
    if (state != outcome::playing) return;
    ++ticks;
    const float step = delta * definition.speed;
    for (int index = 0; index < definition.hookcount; ++index) {
        rope& item = ropes[index];
        if (item.cut && item.remaining <= 0) continue;
        if (item.cut) {
            item.remaining = std::max(0.0f, item.remaining - step);
            if (item.pending >= 0 && item.remaining < 1.95f) detach(item);
        }
        for (int part = 0; part < item.count; ++part) {
            const int id = item.bodies[part];
            if (id != 0) integrate(bodies[id], 784.0f * (step * delta));
        }
        for (int iteration = 0; iteration < 30; ++iteration) {
            for (int part = 0; part < item.count; ++part) satisfy(bodies[item.bodies[part]]);
        }
    }
    integrate(bodies[0], 784.0f * (step * step));
    const point pos = candy().pos;
    const point distance = pos - definition.target;
    if (!mouth && distance.length() < 200) { mouth = true; mouthtick = ticks; }
    for (int index = 0; index < 3; ++index) {
        const point difference = pos - definition.stars[index];
        if (!stars[index] && std::abs(difference.x) < 97 && std::abs(difference.y) < 93) {
            stars[index] = true;
            collectedat[index] = ticks;
            ++count;
        }
    }
    if (mouth && distance.x > -113.5f && distance.x < 106.5f && distance.y > -22 && distance.y < 84) {
        state = outcome::won;
        resulttick = ticks;
    } else if (pos.y > definition.height + 200 || pos.y < -400 ||
               pos.x < definition.left - 200 || pos.x > definition.left + definition.width + 200) {
        state = outcome::lost;
        resulttick = ticks;
    }
}

bool simulation::sever(int index, int segment) {
    if (state != outcome::playing || index < 0 || index >= definition.hookcount) return false;
    rope& item = ropes[index];
    if (item.cut || segment < 0 || segment >= item.count - 1) return false;
    item.cut = true;
    item.pending = segment;
    item.split = segment + 1;
    return true;
}

static float cross(point a, point b) { return a.x * b.y - a.y * b.x; }
bool simulation::swipe(point start, point end) {
    bool changed = false;
    for (int index = 0; index < definition.hookcount; ++index) {
        const rope& item = ropes[index];
        if (item.cut) continue;
        for (int part = 0; part < item.count - 1; ++part) {
            const point p = bodies[item.bodies[part]].pos;
            const point edge = bodies[item.bodies[part + 1]].pos - p;
            const point direction = end - start;
            const float denominator = cross(direction, edge);
            if (std::abs(denominator) <= .001f) continue;
            const float t = cross(p - start, edge) / denominator;
            const float u = cross(p - start, direction) / denominator;
            if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
                changed = sever(index, part) || changed;
                break;
            }
        }
    }
    return changed;
}

void simulation::samples(int index, int first, int count, point* output, int& size) const {
    size = 0;
    if (count < 3) return;
    const rope& item = ropes[index];
    const int steps = (count - 1) * 4;
    for (int sample = 0; sample <= steps; ++sample) {
        std::array<point, 32> work{};
        for (int part = 0; part < count; ++part) work[part] = bodies[item.bodies[first + part]].pos;
        const float t = static_cast<float>(sample) / steps;
        for (int level = count - 1; level > 0; --level) {
            for (int part = 0; part < level; ++part) work[part] = work[part] * (1 - t) + work[part + 1] * t;
        }
        output[size++] = work[0];
    }
}
}
