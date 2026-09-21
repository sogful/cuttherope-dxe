#include "geometry.hpp"
#include <algorithm>
#include <cassert>

namespace dx {
static constexpr float pi = 3.14159265f, tau = 6.2831853f, delta = .016f;
static float bound(float angle) { return angle > pi ? angle - tau : angle < -pi ? angle + tau : angle; }
static point around(point position, point center, float angle) {
    const int index = static_cast<int>(angle * 1024 / tau) & 1023;
    const float quantized = index * 2 * pi / 1024, s = std::sin(quantized), c = std::cos(quantized);
    const point p = position - center;
    return {p.x * c - p.y * s + center.x, p.x * s + p.y * c + center.y};
}
void simulation::resetcontraptions() {
    ghosts = {}; apparitions = {}; baselines = {}; discorder = {};
    disclayers = definition.disccount; dragdisc = -1; discside = discevents = ghostevents = 0;
    discdirection = false;
    for (int i = 0; i < disclayers; ++i) discorder[i] = {i, definition.discs[i].angle, .216f, false};
}
point simulation::dischandle(int index, bool right) const {
    const auto& d = definition.discs[index];
    return around(d.position + point{d.size * (right ? 3 : -3), 0}, d.position, bound(d.angle * pi / 180));
}
bool simulation::pressdisc(point position) {
    for (int i = 0; i < disclayers; ++i) {
        const auto layer = discorder[i];
        if (layer.copy) continue;
        const int index = layer.index;
        const auto& d = definition.discs[index];
        const bool left = (position - dischandle(index, false)).length() < 90;
        const bool right = (position - dischandle(index, true)).length() < 90;
        if (!(left && !d.single) && !right) continue;
        dragdisc = index; discside = (left ? 1 : 0) | (right ? 2 : 0); disctouch = position;
        bool nested = false, overlap = false;
        const float radius = 534 * (d.size / 167);
        for (int j = i + 1; j < disclayers; ++j) {
            const auto& other = definition.discs[discorder[j].index];
            const float distance = (d.position - other.position).length(), otheradius = 534 * (other.size / 167);
            nested = nested || distance + otheradius <= radius;
            overlap = overlap || distance <= radius + otheradius;
        }
        if (overlap && !nested && disclayers < static_cast<int>(discorder.size())) {
            discorder[i] = {index, d.angle, 0, true};
            discorder[disclayers++] = {index, d.angle, 0, false};
        }
        return true;
    }
    return false;
}
void simulation::rotatedisc(point position) {
    auto& d = definition.discs[dragdisc];
    const auto first = disctouch - d.position, last = position - d.position;
    const float turn = std::atan2(last.y,last.x) - std::atan2(first.y,first.x);
    const float before = d.angle * pi / 180, degrees = turn * 180 / pi;
    if (std::abs(turn) >= .07f && (!discevents || discdirection != (turn > 0))) { ++discevents; discdirection = turn > 0; }
    d.angle += degrees;
    const float radius = 534 * (d.size / 167);
    auto move = [&](point position, int index) {
        auto& base = baselines[index];
        if (base.owner != dragdisc) base = {position, before, dragdisc};
        return around(base.position, d.position, bound(d.angle * pi / 180 - base.angle));
    };
    for (int i = 0; i < definition.hookcount; ++i) {
        const auto& hook = definition.hooks[i];
        if (hook.route >= 0 || hook.rail || ghostapp(4,i) || (anchors[i] - d.position).length() > radius + 5) continue;
        anchors[i] = move(anchors[i],i);
        if (ropes[i].count) bodies[ropes[i].bodies[0]].pin = bodies[ropes[i].bodies[0]].pos = anchors[i];
    }
    for (int i = 0; i < definition.pumpcount; ++i) {
        auto& pump = definition.pumps[i];
        if ((pump.position - d.position).length() > radius + 5) continue;
        pump.position = move(pump.position,24+i); pump.angle += degrees;
    }
    for (int i = 0; i < definition.bubblecount; ++i) {
        auto& p = definition.bubbles[i];
        bool carried = bubble == i || halfbubbles[0] == i || halfbubbles[1] == i;
        if (!carried && !ghostapp(2,i) && (p - d.position).length() <= radius + 10) p = move(p,32+i);
    }
    const auto target = definition.target - d.position;
    if (target.x >= -d.size && target.x < d.size && target.y >= -d.size && target.y < d.size)
        definition.target = around(definition.target,d.position,turn);
    disctouch = position;
}
void simulation::updatediscs() {
    for (int i = 0; i < disclayers;) {
        auto& layer = discorder[i];
        layer.fade = std::min(.216f, layer.fade + delta);
        if (!layer.copy) layer.angle = definition.discs[layer.index].angle;
        if (layer.copy && layer.fade >= .216f) {
            for (int j = i; j < disclayers - 1; ++j) discorder[j] = discorder[j+1];
            --disclayers;
        } else ++i;
    }
}
const apparition* simulation::ghostapp(int form, int index) const {
    if (!definition.ghostcount) return nullptr;
    for (const auto& app : apparitions) if (app.form == form && app.index == index) return &app;
    return nullptr;
}
float simulation::ghostalpha(int form, int index) const {
    const auto* app = ghostapp(form,index);
    return !app ? 1 : app->retirement >= 0 ? std::max(0.0f,1-app->retirement/.16f) : std::min(1.0f,app->age/.36f);
}
bool simulation::ghosttap(int index) {
    const auto& source = definition.ghosts[index];
    auto& g = ghosts[index];
    if (g.app >= 0 && apparitions[g.app].owner >= 0) return false;
    if (!(source.forms & ~1)) return true;
    int form = g.form;
    do { form *= 2; if (form >= 16) form = 2; } while (!(source.forms & form));
    if (form != g.form) ghostform(index,form);
    return true;
}
void simulation::ghostform(int index, int form) {
    auto& g = ghosts[index];
    const auto& source = definition.ghosts[index];
    if (!(source.forms & form) || form == g.form) return;
    int slot = -1;
    if (form != 1) {
        for (int i = 0; i < static_cast<int>(apparitions.size()); ++i) if (!apparitions[i].form) { slot = i; break; }
        if (slot < 0 || (form == 2 && definition.bubblecount == static_cast<int>(definition.bubbles.size())) ||
            (form == 4 && definition.hookcount == static_cast<int>(definition.hooks.size())) ||
            (form == 8 && definition.bouncercount == static_cast<int>(definition.bouncers.size()))) return;
    }
    if (g.app >= 0) {
        auto& old = apparitions[g.app]; old.retirement = 0;
        if (old.form == 2) bubblesused[old.index] = true;
        if (old.form == 4 && ropes[old.index].count) {
            auto& rope = ropes[old.index];
            if (!rope.cut) { rope.cut = true; rope.pending = 0; rope.split = 1; }
            rope.remaining = .36f;
        }
    } else g.idleage = 0;
    g.form = form; g.app = slot; g.age = 0; ++g.morphs; ++ghostevents;
    if (form == 1) { g.idleage = 0; return; }
    auto& app = apparitions[slot];
    app = {index, form, -1, 0, -1, -1};
    if (form == 2) {
        app.index = definition.bubblecount++;
        definition.bubbles[app.index] = source.position; bubblesused[app.index] = false;
    } else if (form == 4) {
        const int i = app.index = definition.hookcount++;
        definition.hooks[i] = {source.position, 0, source.radius};
        anchors[i] = source.position; ropes[i] = {}; wheelangles[i] = beeangles[i] = 0; beetargets[i] = 1;
        if (source.radius < 0) {
            int id = activeid(0);
            if (split && (bodies[2].pos - source.position).length() < (bodies[1].pos - source.position).length()) id = 2;
            attach(i, std::max(1.0f,(bodies[id].pos-source.position).length()),id);
        }
    } else {
        app.index = definition.bouncercount++;
        definition.bouncers[app.index] = {source.position, {}, source.angle, 1}; bounceages[app.index] = 100;
    }
}
void simulation::advanceghosts(int form) {
    for (auto& app : apparitions) if (app.form == form) {
        app.age += delta;
        if (app.retirement >= 0) app.retirement += delta;
    }
}
void simulation::retireghost(int slot) {
    const auto retired = apparitions[slot];
    const int index = retired.index;
    if (retired.form == 4) {
        const auto rope = ropes[index];
        for (int i = 0; i < rope.count; ++i) {
            const int id = rope.bodies[i];
            if (id < (definition.split ? 3 : 1)) continue;
            for (int candy = 0; candy < (definition.split ? 3 : 1); ++candy) {
                auto& body = bodies[candy];
                for (int j = 0; j < body.linkcount;) {
                    if (body.links[j].other == id) {
                        for (int k = j; k < body.linkcount-1; ++k) body.links[k] = body.links[k+1];
                        --body.linkcount;
                    } else ++j;
                }
            }
            freebodies[freecount++] = id; bodies[id] = {};
        }
        --definition.hookcount;
        for (int i = index; i < definition.hookcount; ++i) {
            definition.hooks[i] = definition.hooks[i+1]; ropes[i] = ropes[i+1]; anchors[i] = anchors[i+1];
            beetargets[i] = beetargets[i+1]; beeangles[i] = beeangles[i+1]; wheelangles[i] = wheelangles[i+1];
        }
    } else if (retired.form == 2) {
        --definition.bubblecount;
        for (int i = index; i < definition.bubblecount; ++i) { definition.bubbles[i] = definition.bubbles[i+1]; bubblesused[i] = bubblesused[i+1]; }
        for (int* id : {&bubble, &halfbubbles[0], &halfbubbles[1]}) { if (*id == index) *id = -1; else if (*id > index) --*id; }
    } else if (retired.form == 8) {
        --definition.bouncercount;
        for (int i = index; i < definition.bouncercount; ++i) { definition.bouncers[i] = definition.bouncers[i+1]; bounceages[i] = bounceages[i+1]; }
    }
    apparitions[slot] = {};
    for (auto& app : apparitions) if (app.form == retired.form && app.index > index) --app.index;
}
void simulation::updateghosts() {
    for (int i = 0; i < static_cast<int>(apparitions.size()); ++i)
        if (apparitions[i].form && apparitions[i].retirement >= .16f) retireghost(i);
    for (int i = 0; i < definition.ghostcount; ++i) {
        auto& g = ghosts[i]; g.age += delta; g.idleage += delta;
        if (g.form == 4 && g.app >= 0 && ropes[apparitions[g.app].index].cut) ghostform(i,1);
    }
}
void simulation::releaseghost(int id) {
    for (int i = 0; i < definition.ghostcount; ++i) {
        const int slot = ghosts[i].app;
        if (slot >= 0 && apparitions[slot].form == 2 && apparitions[slot].owner == id) {
            apparitions[slot].owner = -1; ghostform(i,1);
        }
    }
}
void simulation::mergeghosts() {
    const auto* left = ghostapp(2,halfbubbles[0]);
    const auto* right = ghostapp(2,halfbubbles[1]);
    bubble = left ? halfbubbles[0] : right ? halfbubbles[1] : halfbubbles[0] >= 0 ? halfbubbles[0] : halfbubbles[1];
    for (auto& app : apparitions) if (app.form == 2 && app.retirement < 0 && app.owner > 0) app.owner = 0;
    halfbubbles.fill(-1);
}
}
