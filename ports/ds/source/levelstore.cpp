#include "simulation.hpp"
#include "leveldata.hpp"

namespace dx {
const level& loadlevel(int index) {
    static level data;
    data = {};
    if (index < 0 || index >= levelcount) index = 0;
    const float* cursor = leveldata + leveloffsets[index];
    auto scalar = [&]() { return *cursor++; };
    auto vector = [&]() { const float x = scalar(), y = scalar(); return point{x,y}; };
    auto mover = [&]() { motion item; item.offset = vector(); item.speed = scalar(); item.rotation = scalar(); item.circle = scalar(); return item; };
    data.left = scalar(); data.width = scalar(); data.height = scalar(); data.speed = scalar();
    data.box = scalar(); data.index = scalar(); data.candy = vector(); data.target = vector(); data.split = scalar();
    for (auto& half : data.halves) half = vector();
    for (int i = 0; i < 3; ++i) { data.stars[i] = vector(); data.timeouts[i] = scalar(); data.starmotions[i] = mover(); }
    data.hookcount = scalar();
    for (int i = 0; i < data.hookcount; ++i) {
        auto& item = data.hooks[i]; item.anchor = vector(); item.length = scalar(); item.radius = scalar(); item.spider = scalar();
        item.rail = scalar(); item.offset = scalar(); item.vertical = scalar(); item.part = scalar();
    }
    data.bubblecount = scalar();
    for (int i = 0; i < data.bubblecount; ++i) data.bubbles[i] = vector();
    data.spikecount = scalar();
    for (int i = 0; i < data.spikecount; ++i) {
        auto& item = data.spikes[i]; item.anchor = vector(); item.path = mover(); item.angle = scalar(); item.size = scalar();
        item.on = scalar(); item.off = scalar(); item.delay = scalar();
    }
    data.pumpcount = scalar();
    for (int i = 0; i < data.pumpcount; ++i) { data.pumps[i].position = vector(); data.pumps[i].angle = scalar(); }
    data.hatcount = scalar();
    for (int i = 0; i < data.hatcount; ++i) {
        auto& item = data.hats[i]; item.position = vector(); item.path = mover(); item.angle = scalar(); item.group = scalar(); item.resetangle = scalar();
    }
    data.bouncercount = scalar();
    for (int i = 0; i < data.bouncercount; ++i) {
        auto& item = data.bouncers[i]; item.position = vector(); item.path = mover(); item.angle = scalar(); item.size = scalar();
    }
    return data;
}
}
