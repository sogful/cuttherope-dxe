#pragma once
#include <algorithm>
#include <cmath>

namespace ui {
struct scroller {
    int count = 17, selected = 0, cursor = 0;
    float x = 0, target = 0, multiplier = .8f, last = 0, total = 0, pending = 0;
    float distances[5]{}, durations[5]{};
    bool moving = false, down = false, dragged = false;
    static float approach(float value, float target, float speed, float dt) {
        return value + std::copysign(std::min(std::abs(target - value), speed * dt), target - value);
    }
    void moveto(int index, float speed = .8f) {
        selected = std::clamp(index, 0, count - 1);
        target = -selected * 640.0f;
        multiplier = speed;
        moving = true;
    }
    void begin(float position) {
        down = true;
        moving = dragged = false;
        last = position;
        total = pending = 0;
        cursor = 0;
        std::fill(std::begin(distances), std::end(distances), 0);
        std::fill(std::begin(durations), std::end(durations), 0);
    }
    void drag(float position) {
        float delta = position - last;
        last = position;
        if (!down || std::abs(delta) > 640) return;
        total += delta;
        dragged = dragged || std::abs(total) > 5;
        const float minimum = -(680 + count * 640 + 1000 - 1320);
        if (x > 0 || x < minimum) delta *= .5f;
        x += delta;
        pending += delta;
    }
    bool release() {
        down = false;
        if (!dragged) return true;
        float distance = 0, duration = 0;
        for (int i = 0; i < 5; ++i) { distance += distances[i]; duration += durations[i]; }
        const float speed = duration > 0 ? distance / duration : 0;
        const int direction = std::abs(speed) > 5 ? (speed > 0 ? 1 : -1) : 0;
        int nearest = -1;
        float best = 1e9f;
        for (int i = 0; i < count; ++i) {
            const float offset = -i * 640 - x;
            if ((direction == 0 || offset == 0 || (offset > 0 ? 1 : -1) == direction) && std::abs(offset) < best) {
                nearest = i;
                best = std::abs(offset);
            }
        }
        if (nearest < 0) nearest = std::clamp(static_cast<int>(std::lround(-x / 640)), 0, count - 1);
        const float offset = -nearest * 640 - x;
        moveto(nearest, offset * speed > 0 ? std::max(1.0f, std::abs(speed) / 500) : .5f);
        return false;
    }
    bool update(float dt) {
        bool settled = false;
        const float minimum = -(680 + count * 640 + 1000 - 1320);
        if (!down) {
            if (x > 0) x = approach(x, 0, 50 + std::abs(x) * 5, dt);
            else if (x < minimum) x = approach(x, minimum, 50 + std::abs(minimum - x) * 5, dt);
        }
        if (moving) {
            x = approach(x, target, std::max(100.0f, std::abs(target - x) * 4 * multiplier), dt);
            if (x == target) { moving = false; settled = true; }
        }
        distances[cursor] = pending;
        durations[cursor] = dt;
        cursor = (cursor + 1) % 5;
        pending = 0;
        return settled;
    }
};
}
