#pragma once
#include <array>
#include <cmath>
#include <cstdint>

namespace dx {
struct point {
    float x = 0, y = 0;
    point operator+(point b) const { return {x + b.x, y + b.y}; }
    point operator-(point b) const { return {x - b.x, y - b.y}; }
    point operator*(float n) const { return {x * n, y * n}; }
    point operator/(float n) const { return {x / n, y / n}; }
    float length() const { return std::sqrt(x * x + y * y); }
};
struct hook { point anchor; float length; };
struct level {
    point candy, target;
    std::array<point, 3> stars;
    std::array<hook, 8> hooks;
    int hookcount;
    float speed;
    float left, width, height;
};
struct constraint { int other = 0; float length = 0; bool active = false; };
struct body {
    point pos, previous, pin;
    float inverse = 50;
    bool initialized = false, pinned = false;
    std::array<constraint, 8> links{};
    int linkcount = 0;
};
struct rope {
    std::array<int, 32> bodies{};
    int count = 0, pending = -1, split = 0;
    bool cut = false;
    float remaining = 2;
};
enum class outcome { playing, won, lost };
class simulation {
public:
    void reset(const level& data);
    void tick();
    bool swipe(point start, point end);
    bool tap(point position);
    bool sever(int index, int segment);
    void samples(int index, int first, int count, point* output, int& size) const;
    const body& candy() const { return bodies[0]; }
    level definition{};
    std::array<body, 256> bodies{};
    std::array<rope, 8> ropes{};
    std::array<bool, 3> stars{};
    std::array<int, 3> collectedat{};
    int bodycount = 0, ticks = 0, count = 0, resulttick = 0;
    bool mouth = false;
    int mouthtick = 0;
    outcome state = outcome::playing;
private:
    int add(point position, float inverse, bool pinned);
    void integrate(body& item, float acceleration);
    void satisfy(body& item);
    void detach(rope& item);
};
}
