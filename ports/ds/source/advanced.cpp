#include "geometry.hpp"
#include <algorithm>

namespace dx {
bool simulation::drag(point position, bool held) {
    if (!held || state != outcome::playing || introduction) { draghook = -1; return false; }
    if (draghook < 0) return false;
    const auto& hook = definition.hooks[draghook];
    const float low = (hook.vertical ? hook.anchor.y : hook.anchor.x) - hook.offset;
    const float value = std::clamp(hook.vertical ? position.y : position.x, low, low + hook.rail);
    (hook.vertical ? anchors[draghook].y : anchors[draghook].x) = value;
    const auto& rope = ropes[draghook];
    if (rope.count) bodies[rope.bodies[0]].pin = bodies[rope.bodies[0]].pos = anchors[draghook];
    return true;
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
