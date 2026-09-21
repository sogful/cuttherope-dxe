#include "geometry.hpp"
#include "routes.hpp"
#include <algorithm>
#include <cassert>

namespace dx {
bool simulation::drag(point position, bool held) {
    if (state != outcome::playing || introduction) { draghook = dragwheel = dragswitch = dragspike = dragdisc = -1; cancelbelts(); return false; }
    if (!held) {
        releasebelt(position);
        if (dragspike >= 0 && spikehit(dragspike, position)) rotatespikes(definition.spikes[dragspike].group);
        if (dragswitch >= 0) {
            const auto d = position - definition.switches[dragswitch];
            if (d.x >= -115.5f && d.x < 115.5f && d.y >= -116.5f && d.y < 116.5f) togglegravity();
        }
        draghook = dragwheel = dragswitch = dragspike = dragdisc = -1;
        return false;
    }
    if (heldbelt >= 0) return dragbelt(position);
    if (dragdisc >= 0) { rotatedisc(position); return true; }
    if (dragspike >= 0) { if (!spikehit(dragspike, position)) dragspike = -1; return true; }
    if (dragswitch >= 0) return true;
    if (dragwheel >= 0) { rotatewheel(dragwheel, position); return true; }
    if (draghook < 0) return false;
    const auto& hook = definition.hooks[draghook];
    const float low = (hook.vertical ? hook.anchor.y : hook.anchor.x) - hook.offset;
    const float value = std::clamp(hook.vertical ? position.y : position.x, low, low + hook.rail);
    (hook.vertical ? anchors[draghook].y : anchors[draghook].x) = value;
    const auto& rope = ropes[draghook];
    if (rope.count) bodies[rope.bodies[0]].pin = bodies[rope.bodies[0]].pos = anchors[draghook];
    return true;
}

void simulation::togglegravity() { inverted = !inverted; ++gravityevents; gravityage = 0; }
int simulation::ropelength(int index) const {
    const auto& rope = ropes[index];
    int length = 0;
    for (int i = 1; i < rope.count; ++i) length += static_cast<int>((bodies[rope.bodies[i]].pos - bodies[rope.bodies[i - 1]].pos).length());
    return length;
}
float simulation::wheelscale(int index) const {
    const auto& rope = ropes[index];
    if (!rope.count || (rope.cut && rope.remaining <= 0)) return 0;
    const float length = ropelength(index) * .7f;
    return length == 0 ? 0 : std::clamp(1 - length / 700, 0.0f, 1.2f);
}
void simulation::rotatewheel(int index, point position) {
    if (position.x == wheeltouch.x && position.y == wheeltouch.y) return;
    const auto first = wheeltouch - anchors[index], last = position - anchors[index];
    float angle = (std::atan2(last.y, last.x) - std::atan2(first.y, first.x)) * 180 / 3.14159265f;
    if (angle > 180) angle -= 360;
    else if (angle < -180) angle += 360;
    wheelangles[index] += angle;
    ++wheelevents;
    const float amount = angle > 0 ? std::clamp(angle, 1.0f, 4.5f) : std::clamp(angle, -4.5f, -1.0f);
    const auto& rope = ropes[index];
    if (rope.count >= 3 && (!rope.cut || rope.remaining > 0)) {
        if (amount > 0 && ropelength(index) < 1650) reel(index, amount);
        else if (amount < 0 && rope.count > 3) reel(index, amount);
    }
    wheeltouch = position;
}
void simulation::reel(int index, float amount) {
    auto& rope = ropes[index];
    auto& tail = bodies[rope.bodies[rope.count - 1]];
    constraint* link = nullptr;
    for (int i = 0; i < tail.linkcount; ++i)
        if (tail.links[i].active && tail.links[i].other == rope.bodies[rope.count - 2]) { link = &tail.links[i]; break; }
    int rest = link ? static_cast<int>(link->length) : -1;
    const bool retract = amount < 0;
    amount = std::abs(amount);
    while (amount > 0) {
        if (amount >= 105) {
            const int previous = rope.bodies[rope.count - 2];
            if (retract) {
                if (rope.count <= 3) break;
                if (link) { link->other = rope.bodies[rope.count - 3]; link->length = rest; }
                rope.bodies[rope.count - 2] = rope.bodies[rope.count - 1];
                --rope.count;
                if (rope.cut && rope.split > rope.count - 1) rope.split = rope.count - 1;
                freebodies[freecount++] = previous;
                bodies[previous] = {};
            } else {
                assert(rope.count < static_cast<int>(rope.bodies.size()));
                const int current = add(bodies[previous].pos, 50, false);
                bodies[current].links[0] = {previous, 105, true}; bodies[current].linkcount = 1;
                rope.bodies[rope.count] = rope.bodies[rope.count - 1];
                rope.bodies[rope.count - 1] = current; ++rope.count;
                if (link) { link->other = current; link->length = rest; }
            }
            amount -= 105;
        } else {
            const int next = static_cast<int>(retract ? rest - amount : rest + amount);
            if (retract ? next < 1 : next > 105) { amount = 105; rest = retract ? 105 + next + 1 : next - 105; }
            else { if (link) link->length = next; amount = 0; }
        }
    }
    if (retract) for (int i = 0; i < tail.linkcount; ++i)
        if (tail.links[i].maximum) tail.links[i].length = (rope.count - 1) * 108;
}

void simulation::merge(bool touching) {
    auto& left = bodies[1]; auto& right = bodies[2]; auto& whole = bodies[0];
    whole.pos = (left.pos + right.pos) * .5f;
    if (merging) {
        for (int i = 0; i < 30; ++i) { satisfy(left); satisfy(right); }
        mergedistance = std::max(0.0f, mergedistance - 200 * .016f);
        if (mergedistance == 0) {
            whole.pos = left.pos;
            whole.previous = whole.pos - ((left.pos - left.previous) + (right.pos - right.previous)) * .5f;
            mergeghosts();
            for (int i = 0; i < definition.hookcount; ++i) {
                auto& rope = ropes[i];
                if (rope.count < 2 || !rope.candy || (rope.cut && rope.split == rope.count - 1)) continue;
                const int previous = rope.bodies[rope.count - 2];
                const auto& tail = bodies[rope.candy];
                for (int link = 0; link < tail.linkcount; ++link) if (tail.links[link].active && tail.links[link].other == previous) {
                    whole.links[whole.linkcount++] = {previous, static_cast<float>(static_cast<int>(tail.links[link].length)), true};
                    break;
                }
                rope.bodies[rope.count - 1] = rope.candy = 0;
            }
            split = merging = false; mergeage = 0; ++mergeevents;
        } else for (int id : {1,2}) for (int i = 0; i < bodies[id].linkcount; ++i)
            if (bodies[id].links[i].maximum) bodies[id].links[i].length = mergedistance;
    } else if (touching) {
        mergedistance = (left.pos - right.pos).length(); merging = true;
        left.links[left.linkcount++] = {2, mergedistance, true, true};
        right.links[right.linkcount++] = {1, mergedistance, true, true};
    }
}

void simulation::cutattached(int id) {
    releasecandy(id);
}

void simulation::dropspider(int index, bool won) {
    auto& rope = ropes[index];
    if (!definition.hooks[index].spider || !rope.count || rope.spiderstate) return;
    rope.spiderstate = won ? 2 : 1;
    rope.spiderfall = visuals;
    rope.spiderorigin = {static_cast<float>(static_cast<int>(rope.spiderpos.x)), static_cast<float>(static_cast<int>(rope.spiderpos.y))};
    rope.spiderup = inverted;
    rope.spiderturn = static_cast<float>((visuals * 73 + index * 47) % 241 - 120);
    if (!won) ++spiderfalls;
}

void simulation::releasecandy(int id) {
    for (int i = 0; i < definition.hookcount; ++i) {
        auto& rope = ropes[i];
        if (!rope.count || rope.candy != id) continue;
        if (!rope.cut) { rope.cut = true; rope.pending = rope.count - 2; rope.split = rope.count - 1; }
        if (rope.pending >= 0) detach(rope);
        rope.hidetail = true;
        dropspider(i);
    }
    for (int i = 0; i < bodies[id].linkcount; ++i) bodies[id].links[i].active = false;
}

point simulation::spikeposition(int index) const {
    const auto& spike = definition.spikes[index];
    return spike.anchor + spike.path.at(visuals * .016f);
}
float simulation::spikeangle(int index) const {
    const auto& spike = definition.spikes[index];
    if (spike.group < 0 || spike.path.speed || spike.path.rotation || !spikeevents)
        return spike.path.angle(spike.angle, visuals * .016f);
    if (spikeduration[index] == 0) return spikenormal[index] ? spike.angle + 90 : spike.angle;
    return spikefirst[index] + (spikelast[index] - spikefirst[index]) * (spikeages[index] / spikeduration[index]);
}
bool simulation::spikehit(int index, point position) const {
    if (definition.spikes[index].group <= 0) return false;
    const auto p = position - spikeposition(index);
    return p.x >= -99.5f && p.x < 106.5f && p.y >= -104 && p.y < 104;
}
void simulation::rotatespikes(int group) {
    for (int i = 0; i < definition.spikecount; ++i) if (definition.spikes[i].group == group) {
        const float start = spikeangle(i);
        spikenormal[i] = !spikenormal[i];
        const float target = definition.spikes[i].angle + (spikenormal[i] ? 90 : 0);
        spikefirst[i] = static_cast<int>(start); spikelast[i] = static_cast<int>(target);
        spikeduration[i] = std::abs(target - start) / 90 * .3f;
        spikeages[i] = 0; spikedirection = spikenormal[i];
    }
    ++spikeevents;
}
void simulation::movebee(int index) {
    const auto& hook = definition.hooks[index];
    if (hook.route < 0) return;
    const auto& path = routes[hook.route];
    auto& pos = anchors[index];
    auto& target = beetargets[index];
    if (visuals == 1) { pos = routepoints[path.first]; target %= path.count; }
    float remaining = .016f;
    int guard = 0;
    while (remaining > 0 && hook.speed > 0 && guard <= path.count) {
        const auto end = routepoints[path.first + target], d = end - pos;
        const float distance = d.length();
        if (distance == 0) { target = (target + 1) % path.count; ++guard; continue; }
        const float duration = distance / hook.speed;
        if (duration <= remaining) { pos = end; remaining -= duration; target = (target + 1) % path.count; ++guard; }
        else { pos = pos + d * (1 / distance) * (hook.speed * remaining); remaining = 0; }
    }
    const float x = routepoints[path.first + target].x - pos.x;
    const float tilt = std::abs(x) > 15 ? (x > 0 ? 10 : -10) : 0;
    beeangles[index] += std::clamp(tilt - beeangles[index], -.96f, .96f);
    auto& rope = ropes[index];
    if (rope.count) bodies[rope.bodies[0]].pin = bodies[rope.bodies[0]].pos = pos;
    if (rope.spiderdistance == 0) rope.spiderpos = pos;
}

void simulation::transports() {
    if (definition.bulbcount) { lighttransports(); return; }
    if (split || inlantern || state != outcome::playing) return;
    if (transit >= 0) {
        if (++transitage < 7) return;
        const auto& hat = definition.hats[transit];
        const float angle = hat.path.angle(hat.angle, visuals * .016f, hat.resetangle);
        auto& body = bodies[0];
        body.pos = hat.position + hat.path.at(visuals * .016f) + rotate({0,-16},angle);
        body.velocity = rotate({0,-exitspeed},angle);
        body.previous = body.pos - body.velocity / 60;
        hatages[transit] = 0; transit = -1;
        return;
    }
    for (int i = 0; i < definition.hatcount; ++i) {
        if (hattimers[i] > 0) continue;
        const auto& hat = definition.hats[i];
        const auto center = hat.position + hat.path.at(visuals * .016f);
        const float angle = hat.path.angle(hat.angle, visuals * .016f, hat.resetangle);
        if (rotate(candy().pos - candy().previous, -angle).y < 0) continue;
        bool hit = false;
        for (int side : {0,15}) {
            const auto a = center + rotate({-90,static_cast<float>(side)},angle);
            const auto b = center + rotate({50,static_cast<float>(side)},angle);
            hit = hit || linebox(a,b,candy().pos,20);
        }
        if (!hit) continue;
        for (int j = 0; j < definition.hatcount; ++j) if (j != i && definition.hats[j].group == hat.group) {
            exitspeed = candy().velocity.length() * .9f * 1.4f;
            dropmouse(); retreatmouse(activemouse); cutattached(0);
            transit = j; transitage = 0; hattimers[j] = .8f; hatages[i] = 0; ++teleportevents;
            return;
        }
    }
}

void simulation::bounce() {
    if ((hidden() && !definition.bulbcount) || (state != outcome::playing && failreason != 4 && !bulbalive && !(state == outcome::lost && split && activecount()))) return;
    for (int i = 0; i < definition.bouncercount; ++i) {
        const auto& item = definition.bouncers[i];
        const auto center = item.position + item.path.at(visuals * .016f);
        const float angle = item.path.angle(item.angle, visuals * .016f);
        const float width = item.size == 1 ? 194 : 302;
        for (int part = 0; part < activecount(); ++part) {
            if (!available(activeid(part))) continue;
            auto& body = bodies[activeid(part)];
            bool hit = false;
            for (int side : {-1,1}) {
                const auto a = center + rotate({-width / 2,side * 5.0f},angle);
                const auto b = center + rotate({width / 2,side * 5.0f},angle);
                hit = hit || linebox(a,b,body.pos,40) || segment(a,b,body.previous,body.pos);
            }
            if (!hit) continue;
            const auto position = center + rotate(body.pos - center,-angle);
            auto previous = center + rotate(body.previous - center,-angle);
            const float impulse = std::max((body.previous - body.pos).length() * 40,840.0f) * (previous.y >= center.y ? 1 : -1);
            previous.y = position.y;
            body.previous = center + rotate(previous - center,angle);
            body.pos = center + rotate(position - center,angle) + rotate({0,impulse},angle) * .016f;
            bounceages[i] = 0; ++bounceevents;
        }
    }
}
}
