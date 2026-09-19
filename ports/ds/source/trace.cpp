#include "trace.hpp"
#include "menuassets.hpp"
#include <algorithm>

namespace trace {
system trail;
void system::reset() {
    count = length = cursor = samples = 0;
    down = false; burst = 0; direction = {};
    std::fill(std::begin(counters), std::end(counters), 0);
    std::fill(std::begin(history), std::end(history), dx::point{});
}
float system::random(float base, float variance) {
    seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
    return base + (static_cast<float>(seed & 65535) / 32767.5f - 1) * variance;
}
void system::spawn(int preset) {
    if (count == static_cast<int>(particles.size())) return;
    const auto& config = menuart::tracepresets[preset];
    const float heading = angle + random(180, config.anglevariancedegrees) * .0174532925f;
    const float speed = random(config.speed, config.speedvariance);
    const float life = std::max(.05f, random(config.life, config.lifevariance));
    const dx::point position = head + dx::point{random(0, config.spawnpositionvariance), random(0, config.spawnpositionvariance)};
    const float spin = random(config.spindegrees, config.spinvariancedegrees);
    const int quad = static_cast<int>(config.firstquad) + std::min(static_cast<int>(config.quadcount) - 1, static_cast<int>(random(.5f, .5f) * config.quadcount));
    particles[count++] = {position, position, {std::cos(heading) * speed, std::sin(heading) * speed}, life, life,
        random(config.startscale, config.startscalevariance), 0, config.spinistotaldegreesoverlife ? spin / life : spin, preset, quad};
}
void system::update(bool held, dx::point point, int skin) {
    constexpr float dt = .016f;
    if (held && !down) { reset(); mode = skin; previous = head = point; }
    if (held) {
        const dx::point delta = point - previous;
        const float distance = delta.length();
        if (distance > .01f) {
            if (length == static_cast<int>(segments.size())) { std::move(segments.begin() + 1, segments.end(), segments.begin()); --length; }
            const float life = mode == 0 ? .1f : mode == 2 ? std::clamp(distance * .007f + .05f, .01f, .25f) : .15f;
            segments[length++] = {previous, point, life};
            history[cursor] = delta; cursor = (cursor + 1) % 10; samples = std::min(10, samples + 1);
            head = previous = point; burst = .1f;
        }
    }
    down = held;
    burst = std::max(0.0f, burst - dt);
    for (int i = 0; i < length;) {
        segments[i].life -= dt;
        if (segments[i].life <= 0) { std::move(segments.begin() + i + 1, segments.begin() + length, segments.begin() + i); --length; }
        else ++i;
    }
    direction = {};
    for (auto point : history) direction = direction + point;
    angle = std::atan2(direction.y, direction.x);
    direction = direction / std::max(1, samples);
    const int first = mode <= 4 ? mode - 1 : mode == 5 ? 4 : mode;
    if (mode && burst > 0) for (int emitter = first; emitter < first + (mode == 5 ? 2 : 1); ++emitter) {
        const float interval = 1.0f / (mode == 1 ? 80 : mode == 5 ? 35 : 50);
        counters[emitter] += dt;
        while (counters[emitter] > interval) { counters[emitter] -= interval; spawn(emitter); }
    }
    for (int i = 0; i < count;) {
        auto& item = particles[i];
        item.life -= dt;
        if (item.life <= 0) { item = particles[--count]; continue; }
        const auto& config = menuart::tracepresets[item.preset];
        const auto radial = item.origin - item.position;
        const float distance = radial.length();
        if (distance > .0001f) item.velocity = item.velocity + radial * (config.radialacceleration * dt / distance);
        item.velocity.y += config.gravityy * dt;
        item.position = item.position + item.velocity * dt;
        item.rotation = config.rotatetovelocity ? std::atan2(item.velocity.y, item.velocity.x) * 57.2957795f + 90 : item.rotation + item.spin * dt;
        ++i;
    }
}
}
