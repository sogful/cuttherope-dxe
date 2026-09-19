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
    expired = {};
    bubblesused = {};
    pumpages.fill(100);
    bubble = -1;
    bubbleevents = pumpevents = ropeevents = failreason = visuals = pops = 0;
    popage = 100;
    starpositions = data.stars;
    bodycount = ticks = count = resulttick = mouthtick = 0;
    mouth = false;
    state = outcome::playing;
    add(data.candy, 1, false);
    bodies[0].previous = data.candy;
    bodies[0].initialized = true;
    introduction = data.height > 1440;
    cameray = introduction && data.candy.y < data.height / 2 ? data.height - 1440 : 0;
    cameraspeed = 20;
    cameradistance = std::abs(cameray - std::clamp(data.candy.y - 720, 0.0f, data.height - 1440));
    for (int index = 0; index < data.hookcount; ++index) {
        const hook& source = data.hooks[index];
        ropes[index].spiderpos = source.anchor;
        if (source.radius < 0) attach(index, source.length);
    }
}

void simulation::attach(int index, float length) {
    const auto& source = definition.hooks[index];
    rope& item = ropes[index];
    item.attached = visuals;
    item.bodies[item.count++] = add(source.anchor, 50, true);
    const int segments = static_cast<int>(std::ceil(length / 105.0f));
    const point offset = (candy().pos - source.anchor) / std::floor(length / 105.0f + 2);
    for (int segment = 0; segment < segments; ++segment) {
        const int previous = item.bodies[item.count - 1];
        const int current = add(bodies[previous].pos + offset, 50, false);
        bodies[current].links[0] = {previous, 105, true};
        bodies[current].linkcount = 1;
        item.bodies[item.count++] = current;
    }
    bodies[0].links[bodies[0].linkcount++] = {item.bodies[item.count - 1], length + 105 - segments * 105, true};
    item.bodies[item.count++] = 0;
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

void simulation::ropephysics() {
    const float step = delta * definition.speed;
    for (int index = 0; index < definition.hookcount; ++index) {
        rope& item = ropes[index];
        if (item.count == 0) continue;
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
}

void simulation::tick() {
    camera();
    if (introduction) return;
    animate();
    ropephysics();
    if (state != outcome::playing) return;
    ++ticks;
    const float step = delta * definition.speed;
    for (int index = 0; index < definition.hookcount; ++index) {
        const auto& hook = definition.hooks[index];
        if (ropes[index].count == 0 && hook.radius >= 0 && (candy().pos - hook.anchor).length() <= hook.radius + 42) {
            attach(index, hook.radius + 42);
            ++ropeevents;
        }
    }
    integrate(bodies[0], 784.0f * (step * step));
    bodies[0].velocity = (bodies[0].pos - bodies[0].previous) / step;
    const point pos = candy().pos;
    const point distance = pos - definition.target;
    if (!mouth && distance.length() < 200) { mouth = true; mouthtick = ticks; }
    else if (mouth && distance.length() >= 220) mouth = false;
    for (int index = 0; index < 3; ++index) {
        const float timeout = definition.timeouts[index];
        if (timeout > 0 && ticks * delta >= timeout) expired[index] = true;
        const point difference = pos - starpositions[index];
        if (!stars[index] && !expired[index] && std::abs(difference.x) < 97 && std::abs(difference.y) < 93) {
            stars[index] = true;
            collectedat[index] = ticks;
            ++count;
        }
    }
    for (int i = 0; i < definition.bubblecount; ++i) {
        const auto d = pos - definition.bubbles[i];
        if (!bubblesused[i] && d.x >= -85 && d.x < 85 && d.y >= -85 && d.y < 85) {
            if (bubble >= 0) burst();
            bubble = i;
            bubblesused[i] = true;
            ++bubbleevents;
            break;
        }
    }
    hazards();
    spiders();
    if (state != outcome::playing) return;
    if (bubble >= 0) bodies[0].pos = bodies[0].pos + (bodies[0].velocity * (-1.0f / 14) + point{0, -40}) * delta;
    if (mouth && distance.x > -113.5f && distance.x < 106.5f && distance.y > -22 && distance.y < 84) {
        state = outcome::won;
        resulttick = ticks;
        bodies[0].pin = bodies[0].pos;
        bodies[0].pinned = true;
        if (bubble >= 0) burst();
    } else if (pos.y > definition.height + 400 || pos.y < -400 || pos.x < -2560 || pos.x > definition.width + 2560) fail(1);
}

bool simulation::sever(int index, int segment) {
    if (state != outcome::playing || index < 0 || index >= definition.hookcount) return false;
    rope& item = ropes[index];
    if (item.cut || segment < 0 || segment >= item.count - 1 || introduction) return false;
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

bool simulation::tap(point position) {
    if (state != outcome::playing) return false;
    float nearest = 60;
    int chosen = -1;
    point sample{};
    for (int index = 0; index < definition.hookcount; ++index) {
        if (ropes[index].cut) continue;
        point points[125];
        int size = 0;
        samples(index, 0, ropes[index].count, points, size);
        for (int i = 0; i < size; ++i) {
            const float distance = (points[i] - position).length();
            if (distance < nearest) { nearest = distance; chosen = index; sample = points[i]; }
        }
    }
    if (chosen < 0) return false;
    int segment = 0;
    nearest = 1e9f;
    for (int i = 0; i < ropes[chosen].count - 1; ++i) {
        const float distance = (bodies[ropes[chosen].bodies[i]].pos - sample).length();
        if (distance < nearest) { nearest = distance; segment = i; }
    }
    return sever(chosen, segment);
}

void simulation::samples(int index, int first, int count, point* output, int& size) const {
    size = 0;
    if (count < 3) return;
    const rope& item = ropes[index];
    const int steps = (count - 1) * 4;
    // Bezier weights depend only on the segment count, not on the moving rope.
    // Cache the Bernstein basis instead of repeating de Casteljau's quadratic
    // interpolation for every vertex on every frame on the ARM9 soft-float CPU.
    static constexpr int capacity = [] { int total = 0; for (int n = 3; n <= 32; ++n) total += n * (4 * (n - 1) + 1); return total; }();
    static std::array<float, capacity> basis{};
    static bool ready[33]{};
    int offset = 0;
    for (int n = 3; n < count; ++n) offset += n * (4 * (n - 1) + 1);
    float* weights = basis.data() + offset;
    if (!ready[count]) {
        for (int sample = 0; sample <= steps; ++sample) {
            float* row = weights + sample * count;
            row[0] = 1;
            const float t = static_cast<float>(sample) / steps, u = 1 - t;
            for (int degree = 1; degree < count; ++degree) {
                row[degree] = row[degree - 1] * t;
                for (int part = degree - 1; part > 0; --part) row[part] = row[part] * u + row[part - 1] * t;
                row[0] *= u;
            }
        }
        ready[count] = true;
    }
    for (int sample = 0; sample <= steps; ++sample) {
        point position{};
        for (int part = 0; part < count; ++part) position = position + bodies[item.bodies[first + part]].pos * weights[sample * count + part];
        output[size++] = position;
    }
}
}
