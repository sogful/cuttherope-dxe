#include "geometry.hpp"
#include <algorithm>
#include <cassert>

namespace dx {
bool simulation::drag(point position, bool held) {
    if (state != outcome::playing || introduction) { draghook = dragwheel = dragswitch = -1; return false; }
    if (!held) {
        if (dragswitch >= 0) {
            const auto d = position - definition.switches[dragswitch];
            if (d.x >= -115.5f && d.x < 115.5f && d.y >= -116.5f && d.y < 116.5f) togglegravity();
        }
        draghook = dragwheel = dragswitch = -1;
        return false;
    }
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
            whole.velocity = (whole.pos - whole.previous) / (.016f * definition.speed);
            bubble = halfbubbles[0] >= 0 ? halfbubbles[0] : halfbubbles[1]; halfbubbles.fill(-1);
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
    for (int i = 0; i < definition.hookcount; ++i) {
        auto& rope = ropes[i];
        if (rope.count && rope.candy == id && !rope.cut) {
            sever(i, rope.count - 2);
            detach(rope);
        }
    }
}

void simulation::transports() {
    if (split || state != outcome::playing) return;
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
            cutattached(0); burst();
            transit = j; transitage = 0; hattimers[j] = .8f; hatages[i] = 0; ++teleportevents;
            return;
        }
    }
}

void simulation::bounce() {
    if (hidden() || state != outcome::playing) return;
    for (int i = 0; i < definition.bouncercount; ++i) {
        const auto& item = definition.bouncers[i];
        const auto center = item.position + item.path.at(visuals * .016f);
        const float angle = item.path.angle(item.angle, visuals * .016f);
        const float width = item.size == 1 ? 194 : 302;
        for (int part = 0; part < activecount(); ++part) {
            auto& body = bodies[activeid(part)];
            bool hit = false;
            for (int side : {-1,1}) {
                const auto a = center + rotate({-width / 2,side * 5.0f},angle);
                const auto b = center + rotate({width / 2,side * 5.0f},angle);
                hit = hit || linebox(a,b,body.pos,40) || segment(a,b,body.previous,body.pos);
            }
            if (!hit) continue;
            const auto position = rotate(body.pos - center,-angle);
            auto previous = rotate(body.previous - center,-angle);
            const float impulse = std::max((body.previous - body.pos).length() * 40,840.0f) * (previous.y >= 0 ? 1 : -1);
            previous.y = position.y;
            body.previous = center + rotate(previous,angle);
            body.pos = center + rotate(position,angle) + rotate({0,impulse},angle) * .016f;
            bounceages[i] = 0; ++bounceevents;
        }
    }
}
}
