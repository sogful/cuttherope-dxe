#include "simulation.hpp"
#include "profiling.hpp"
#include "numeric.hpp"
#include <algorithm>
#include <cstring>
#include <cassert>

#ifdef __NDS__
#define DS_HOT ITCM_CODE
#define DS_DATA DTCM_BSS
#else
#define DS_HOT
#define DS_DATA
#endif

namespace dx {
constexpr float delta = 0.016f;
#ifndef DS_REFERENCE_PHYSICS
static unsigned floatbits(float value) { unsigned bits; std::memcpy(&bits, &value, sizeof(bits)); return bits; }
static bool zero(point value) { return ((floatbits(value.x) | floatbits(value.y)) & 0x7fffffffu) == 0; }
static float distancefloor(float value) { return floatbits(value) < 0x3f800000u ? 1.0f : value; }
#endif

int simulation::add(point position, float inverse, bool pinned) {
    assert(freecount || bodycount < static_cast<int>(bodies.size()));
    const int index = freecount ? freebodies[--freecount] : bodycount++;
    body& item = bodies[index];
    item = {};
    item.pos = item.pin = position;
    item.inverse = inverse;
    item.pinned = pinned;
    return index;
}

void simulation::reset(const level& data) {
    definition = data;
    resetcontraptions();
    freecount = 0;
    inverted = false; gravityevents = wheelevents = 0; gravityage = 100;
    dragspike = -1; spikeevents = spiderfalls = spideractivations = 0; spikedirection = false;
    beetargets.fill(1); beeangles.fill(0); spikeages.fill(0); spikefirst.fill(0); spikelast.fill(0); spikeduration.fill(0); spikenormal.fill(false);
    dragwheel = dragswitch = -1; wheelangles.fill(0); wheeltouch = {};
    bodies = {};
    ropes = {};
    stars = {};
    collectedat = {};
    excitement = greeting = -1000;
    expired = {};
    bubblesused = {};
    pumpages.fill(100);
    bounceages.fill(100); hatages.fill(100); hattimers.fill(0); electric.fill(false);
    halfbubbles.fill(-1); halfdraw = data.halves;
    halfalive.fill(true);
    split = data.split; merging = false; mergedistance = exitspeed = 0;
    draghook = transit = -1; transitage = 0; mergeage = 100;
    bounceevents = teleportevents = mergeevents = 0;
    for (int i = 0; i < data.spikecount; ++i) electrotimers[i] = data.spikes[i].off + data.spikes[i].delay;
    bubble = -1;
    bubbleevents = pumpevents = ropeevents = failreason = visuals = pops = 0;
    popage = 100;
    breakposition = {};
    starpositions = data.stars;
    bodycount = ticks = count = resulttick = resultvisual = mouthtick = 0;
    suppressoutcome = false;
    mouth = false;
    mouthdelay = 0;
    state = outcome::playing;
    add(data.candy, 1, false);
    bodies[0].previous = data.candy;
    bodies[0].initialized = true;
    if (split) for (const point position : data.halves) {
        const int id = add(position, 1, false);
        bodies[id].previous = position; bodies[id].initialized = true;
    }
    if (data.bulbcount) {
        while (bodycount < 3) add(data.candy,1,true);
        add(data.bulbs[0].position,1,false);
    }
    introduction = data.height > 1440;
    cameray = introduction && data.candy.y < data.height / 2 ? data.height - 1440 : 0;
    cameraspeed = 20;
    cameradistance = std::abs(cameray - std::clamp(data.candy.y - 720, 0.0f, data.height - 1440));
    resetdevices();
    resetnocturnal();
    for (int index = 0; index < data.hookcount; ++index) {
        const hook& source = data.hooks[index];
        anchors[index] = source.anchor;
        ropes[index].spiderpos = source.anchor;
        if (source.radius < 0 && !inlantern) attach(index, source.length, source.bulb ? 3 : split ? 1 + source.part : 0);
    }
    resetbelts();
}

void simulation::attach(int index, float length, int candy) {
    rope& item = ropes[index];
    item.candy = candy;
    item.attached = visuals;
    item.bodies[item.count++] = add(anchors[index], 50, true);
    const int segments = static_cast<int>(std::ceil(length / 105.0f));
    const point offset = (bodies[candy].pos - anchors[index]) / std::floor(length / 105.0f + 2);
    for (int segment = 0; segment < segments; ++segment) {
        const int previous = item.bodies[item.count - 1];
        const int current = add(bodies[previous].pos + offset, 50, false);
        bodies[current].links[0] = {previous, 105, true};
        bodies[current].linkcount = 1;
        item.bodies[item.count++] = current;
    }
    auto& tail = bodies[candy];
    for (int i = 0; i < tail.linkcount;) {
        if (!tail.links[i].active) { for (int j = i; j < tail.linkcount-1; ++j) tail.links[j] = tail.links[j+1]; --tail.linkcount; }
        else ++i;
    }
    assert(tail.linkcount < static_cast<int>(tail.links.size()));
    tail.links[tail.linkcount++] = {item.bodies[item.count - 1], length + 105 - segments * 105, true};
    item.bodies[item.count++] = candy;
}

DS_HOT void simulation::integrate(body& item, float acceleration, float inverse) {
    if (!item.initialized) {
        item.previous = item.pos;
        item.initialized = true;
    }
    const float vertical = definition.gravity.y == 784 ? acceleration : definition.gravity.y * (acceleration / 784.0f);
    const point force{definition.gravity.x == 0 ? 0 : definition.gravity.x * (acceleration / 784.0f), inverted ? -vertical : vertical};
    const point displacement = item.pos - item.previous + force;
    if (inverse != 0) item.velocity = displacement * inverse;
    item.previous = item.pos;
    item.pos = item.pos + displacement;
}

DS_HOT void simulation::satisfy(body& item) {
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
        if (link.maximum && length <= link.length) continue;
        const float factor = (length - link.length) / (std::max(length, 1.0f) * (item.inverse + other.inverse));
        item.pos = item.pos + difference * (item.inverse * factor);
        if (!other.pinned) other.pos = other.pos - difference * (other.inverse * factor);
    }
}

struct operation {
    point* first;
    point* second;
    float length, inverse, otherinverse, sum;
    unsigned flags;
};
#ifndef DS_REFERENCE_PHYSICS
static DS_DATA point positions[256];
static DS_DATA operation operations[64];
static DS_DATA unsigned char residents[256];
#endif

DS_HOT void simulation::solve(const rope& item) {
#ifdef DS_REFERENCE_PHYSICS
    for (int iteration = 0; iteration < 30; ++iteration)
        for (int part = 0; part < item.count; ++part) satisfy(bodies[item.bodies[part]]);
#else
    // Shared candy constraints also touch the ends of other ropes. Gather every
    // referenced body, but do not copy the entire (large, strided) body pool for
    // each individual rope. Constraint order and all float operations stay exact.
    unsigned copied[8]{};
    int residentcount = 0;
    auto resident = [&](int id) {
        const unsigned mask = 1u << (id & 31);
        if (!(copied[id >> 5] & mask)) {
            copied[id >> 5] |= mask;
            residents[residentcount++] = static_cast<unsigned char>(id);
            positions[id] = bodies[id].pos;
        }
    };
    int count = 0;
    for (int part = 0; part < item.count; ++part) {
        const int id = item.bodies[part];
        const body& first = bodies[id];
        resident(id);
        if (first.pinned) {
            assert(count < static_cast<int>(std::size(operations)));
            operations[count++] = {positions + id, nullptr, 0, first.pin.x, first.pin.y, 0, 1};
            continue;
        }
        for (int i = 0; i < first.linkcount; ++i) {
            const auto& link = first.links[i];
            if (!link.active) continue;
            const body& second = bodies[link.other];
            resident(link.other);
            assert(count < static_cast<int>(std::size(operations)));
            operations[count++] = {positions + id, positions + link.other, link.length, first.inverse,
                second.inverse, first.inverse + second.inverse, (second.pinned ? 2u : 0u) | (link.maximum ? 4u : 0u) |
                (first.inverse==second.inverse ? 8u : 0u) | (first.inverse==1 ? 16u : 0u) |
                (first.inverse==50 ? 32u : 0u) | (second.inverse==50 ? 64u : 0u) |
                (first.inverse+second.inverse==100 ? 128u : first.inverse+second.inverse==51 ? 256u : 0u)};
        }
    }
    for (int iteration = 0; iteration < 30; ++iteration) for (int i = 0; i < count; ++i) {
        const auto& op = operations[i];
        if (op.flags & 1) { *op.first = {op.inverse, op.otherinverse}; continue; }
        point difference{numeric::subtract(op.second->x, op.first->x), numeric::subtract(op.second->y, op.first->y)};
        if (zero(difference)) {
            if (op.length == 0) continue;
            difference = {1, 1};
        }
        const float length = difference.length();
        if ((op.flags & 4) && length <= op.length) continue;
        const float floor=distancefloor(length);
        const float denominator=(op.flags&128)?numeric::scale<100>(floor):(op.flags&256)?numeric::scale<51>(floor):floor*op.sum;
        const float factor = numeric::subtract(length, op.length) / denominator;
        const point displacement=difference*((op.flags&16)?factor:(op.flags&32)?numeric::scale<50>(factor):op.inverse*factor);
        *op.first = *op.first + displacement;
        if (!(op.flags & 2)) *op.second = *op.second - ((op.flags&8)?displacement:difference*((op.flags&64)?numeric::scale<50>(factor):op.otherinverse*factor));
    }
    for (int i = 0; i < residentcount; ++i) bodies[residents[i]].pos = positions[residents[i]];
#endif
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
        if (item.bodies[index] >= bodybase()) bodies[item.bodies[index]].inverse = 100000;
    }
}

DS_HOT void simulation::ropephysics() {
    DS_SCOPE(physics);
    const float step = delta * definition.speed;
    for (int index = 0; index < definition.hookcount; ++index) {
        movebee(index);
        rope& item = ropes[index];
        if (item.count && definition.beltcount) bodies[item.bodies[0]].pin = bodies[item.bodies[0]].pos = anchors[index];
        if (item.count && (!item.cut || item.remaining > 0)) {
            DS_PROFILE_DO(profiling::data[profiling::bodies] += item.count * 30);
            if (item.cut) {
                item.remaining = std::max(0.0f, item.remaining - step);
                if (item.pending >= 0 && item.remaining < 1.95f) detach(item);
            }
            for (int part = 0; part < item.count; ++part) {
                const int id = item.bodies[part];
                if (id >= bodybase()) integrate(bodies[id], 784.0f * (step * delta));
            }
            solve(item);
        }
        const auto& hook = definition.hooks[index];
        for (int part = 0; part < activecount() && state == outcome::playing; ++part) {
            const int id = activeid(part);
            if (!available(id)) continue;
            if (ropes[index].count == 0 && hook.radius >= 0 && (bodies[id].pos - anchors[index]).length() <= hook.radius + 42) {
                attach(index, hook.radius + 42, id);
                ++ropeevents;
            }
        }
    }
}

void simulation::tick(bool suppress) {
    suppressoutcome = suppress;
    const bool panning = introduction;
    camera();
    if (panning) return;
    animate();
    advancelighttransport();
    advanceghosts(4);
    ropephysics();
    if (state != outcome::playing && failreason != 4 && !bulbalive && !(state == outcome::lost && split && activecount())) {
        updatebelts(); advanceghosts(2); advanceghosts(8); updateghosts(); updatedevices(); stopmice(); updatemice(); return;
    }
    ++ticks;
    const float step = delta * definition.speed;
    const point halfgap = halfdraw[0] - halfdraw[1];
    const bool touching = std::abs(halfgap.x) < 88 && std::abs(halfgap.y) < 76;
    for (int part = 0; part < activecount(); ++part) {
        const int id = activeid(part);
        if (id != 3 && state != outcome::playing && failreason != 4 && !split) continue;
        if (id == 3 ? bulbtransit >= 0 : transit >= 0) continue;
        auto& item = bodies[id];
        integrate(item, id == 0 && nogravity ? 0 : 784.0f * (step * step), 1.0f / step);
        if (split && id != 3) halfdraw[id-1] = item.pos;
    }
    collidelight();
    if (bulbalive) {
        const auto position = bodies[3].pos;
        if (position.y > definition.height+400 || position.y < -400 || position.x < -2560 || position.x > definition.width+2560) retirebulb();
    }
    candydraw = candy().pos;
    if (captureage < .1f) {
        captureage += delta;
        candydraw = capturefrom+(captureto-capturefrom)*std::min(1.0f,captureage/.1f);
    }
    if (split && activecount()==2) merge(touching);
    const point pos = candy().pos;
    const point distance = pos - definition.target;
    updatelight();
    updatebelts();
    if (state == outcome::playing && (!definition.night || awake)) {
        const bool nearby = !split && !hidden() && distance.length() < 200;
        if (!mouth && nearby) { mouth = true; mouthtick = ticks; mouthdelay = 1; }
        else if (mouth) {
            mouthdelay = std::max(0.0f,mouthdelay-delta);
            if (mouthdelay==0) { if (nearby) mouthdelay=1; else mouth=false; }
        }
    }
    for (int index = 0; index < 3; ++index) {
        const float timeout = definition.timeouts[index];
        if (timeout > 0 && ticks * delta >= timeout) { expired[index] = true; removebeltitem(1,index); }
        for (int part = 0; part < candycount() && (state == outcome::playing || failreason == 4) && !hidden() && (!definition.night || starlit[index]); ++part) {
            const point difference = bodies[activeid(part)].pos + (split ? point{-1,14} : point{}) - starpositions[index];
            if (!stars[index] && !expired[index] && std::abs(difference.x) < (split ? 98 : 97) && std::abs(difference.y) < (split ? 89 : 93)) {
                stars[index] = true;
                removebeltitem(1,index);
                collectedat[index] = visuals;
                ++count;
            }
        }
    }
    bool captured = false;
    advanceghosts(2);
    for (int i = 0; i < definition.bubblecount && !captured; ++i) {
        for (int part = 0; part < activecount(); ++part) {
            const int id = activeid(part);
            if (!available(id)) continue;
            const auto d = bodies[id].pos - definition.bubbles[i];
            if (!bubblesused[i] && d.x >= -85 && d.x < 85 && d.y >= -85 && d.y < 85) {
                if (bubblefor(id) >= 0) burst(id);
                bubbleindex(id) = i;
                bubblesused[i] = true;
                removebeltitem(0,i);
                for (auto& app : apparitions) if (app.form == 2 && app.index == i) app.owner = id;
                ++bubbleevents;
                captured = true;
                break;
            }
        }
    }
    updateghosts();
    updatedevices();
    updatemice();
    transports();
    hazards();
    advanceghosts(8);
    bounce();
    spiders();
    if (state != outcome::playing && failreason != 4 && !bulbalive && !(state == outcome::lost && split && activecount())) return;
    for (int part = 0; part < activecount(); ++part) {
        const int id = activeid(part);
        if (!available(id)) continue;
        if (bubblefor(id) >= 0) bodies[id].pos = bodies[id].pos + point{-bodies[id].velocity.x / 14,
            -bodies[id].velocity.y / 14 + (inverted ? 40.0f : -40.0f)} * delta;
    }
    if (!suppressoutcome && state == outcome::playing && !split && !hidden() && (!definition.night || awake) && mouth && distance.x > -113.5f && distance.x < 106.5f && distance.y > -22 && distance.y < 84) {
        releasecandy(0);
        state = outcome::won;
        cancelbelts();
        stopmice();
        resulttick = ticks;
        resultvisual = visuals;
        bodies[0].pin = bodies[0].pos;
        bodies[0].pinned = true;
        if (bubble >= 0) burst(0,false);
    } else for (int part = activecount()-1; part >= 0; --part) {
        const int id = activeid(part);
        if (!available(id)) continue;
        const auto position = bodies[id].pos;
        if (position.y > definition.height + 400 || position.y < -400 || position.x < -2560 || position.x > definition.width + 2560) {
            if (id == 3) retirebulb(); else if (split) retirehalf(id,1); else fail(1);
        }
    }
}

bool simulation::sever(int index, int segment) {
    if ((state != outcome::playing && failreason != 4) || index < 0 || index >= definition.hookcount) return false;
    rope& item = ropes[index];
    if (item.cut || segment < 0 || segment >= item.count - 1 || introduction) return false;
    item.cut = true;
    item.pending = segment;
    item.split = segment + 1;
    dropspider(index);
    return true;
}

static float cross(point a, point b) { return a.x * b.y - a.y * b.x; }
bool simulation::swipe(point start, point end) {
    if (dragdisc >= 0) return false;
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
                const auto hit = start + direction * t - anchors[index];
                if (definition.hooks[index].wheel && hit.x >= -110 && hit.x < 110 && hit.y >= -110 && hit.y < 110) continue;
                changed = sever(index, part) || changed;
                break;
            }
        }
    }
    return changed;
}

bool simulation::tap(point position) {
    if (state != outcome::playing) return false;
    for (int i = 0; i < definition.disccount; ++i)
        if ((position - dischandle(i,false)).length() < 90 || (position - dischandle(i,true)).length() < 90) return false;
    for (int i = 0; i < definition.hookcount; ++i) {
        const auto d = position - anchors[i];
        if (definition.hooks[i].wheel && d.x >= -110 && d.x < 110 && d.y >= -110 && d.y < 110) return false;
    }
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

DS_HOT void simulation::samples(int index, int first, int count, point* output, int& size, bool visual) const {
    DS_SCOPE(samples);
    size = 0;
    if (count < 3) return;
    const rope& item = ropes[index];
    const int steps = (count - 1) * 4;
    DS_PROFILE_DO(profiling::data[profiling::weights] += count * (steps + 1));
    // Bezier weights depend only on the segment count, not on the moving rope.
    // Cache the Bernstein basis instead of repeating de Casteljau's quadratic
    // interpolation for every vertex on every frame on the ARM9 soft-float CPU.
    static constexpr int capacity = [] { int total = 0; for (int n = 3; n <= 16; ++n) total += n * (4 * (n - 1) + 1); return total; }();
    static std::array<float, capacity> basis{};
    static bool ready[17]{};
    struct cache { int count = 0; unsigned stamp = 0; float weights[32 * 125]{}; };
    static cache large[2];
    static unsigned stamp = 0;
    float* weights;
    bool generate;
    if (count <= 16) {
        int offset = 0;
        for (int n = 3; n < count; ++n) offset += n * (4 * (n - 1) + 1);
        weights = basis.data() + offset;
        generate = !ready[count];
        ready[count] = true;
    } else {
        cache& entry = large[0].count == count ? large[0] : large[1].count == count ? large[1] :
            large[0].stamp < large[1].stamp ? large[0] : large[1];
        generate = entry.count != count;
        entry.count = count; entry.stamp = ++stamp;
        weights = entry.weights;
    }
    if (generate) {
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
    }
    std::int32_t xs[32],ys[32];
    if (visual) for (int part=0;part<count;++part) {
        const auto& p=bodies[item.bodies[first+part]].pos;
        if ((numeric::bits(p.x)&0x7fffffffu)>=0x47000000u || (numeric::bits(p.y)&0x7fffffffu)>=0x47000000u) { visual=false; break; }
        xs[part]=static_cast<std::int32_t>(p.x*65536); ys[part]=static_cast<std::int32_t>(p.y*65536);
    }
    if (visual) {
        for (int sample=0;sample<=steps;++sample) {
            std::int64_t x=0,y=0;
            for (int part=0;part<count;++part) {
                const unsigned bits=numeric::bits(weights[sample*count+part]);
                const int shift=126-static_cast<int>(bits>>23);
                if (shift>24) continue;
                const unsigned mantissa=(bits&0x7fffffu)|0x800000u;
                const unsigned weight=shift<0?mantissa<<1:mantissa>>shift;
                x+=static_cast<std::int64_t>(xs[part])*weight;
                y+=static_cast<std::int64_t>(ys[part])*weight;
            }
            output[size++]={static_cast<std::int32_t>(x>>24)*(1.0f/65536),static_cast<std::int32_t>(y>>24)*(1.0f/65536)};
        }
        return;
    }
    for (int sample = 0; sample <= steps; ++sample) {
        point position{};
        for (int part = 0; part < count; ++part) position = position + bodies[item.bodies[first + part]].pos * weights[sample * count + part];
        output[size++] = position;
    }
}
}
