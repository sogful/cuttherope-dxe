#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#ifdef __NDS__
#include <nds/arm9/math.h>
#endif

namespace dx {
struct point {
    float x = 0, y = 0;
    point operator+(point b) const { return {x + b.x, y + b.y}; }
    point operator-(point b) const { return {x - b.x, y - b.y}; }
    point operator*(float n) const { return {x * n, y * n}; }
    point operator/(float n) const { return {x / n, y / n}; }
    float length() const {
#ifdef __NDS__
        return hw_sqrtf(x * x + y * y);
#else
        return std::sqrt(x * x + y * y);
#endif
    }
};
struct motion { point offset{}; float speed = 0, rotation = 0; point at(float time) const; };
struct hook { point anchor; float length; float radius = -1; bool spider = false; };
struct spike { point anchor{}; motion path{}; float angle = 0; int size = 1; };
struct pump { point position{}; float angle = 0; };
struct level {
    point candy, target;
    std::array<point, 3> stars;
    std::array<hook, 8> hooks;
    int hookcount;
    float speed;
    float left, width, height;
    int box = 0, index = 0;
    std::array<float, 3> timeouts{{-1, -1, -1}};
    std::array<motion, 3> starmotions{};
    std::array<point, 24> bubbles{};
    std::array<spike, 8> spikes{};
    std::array<pump, 8> pumps{};
    int bubblecount = 0, spikecount = 0, pumpcount = 0;
};
struct constraint { int other = 0; float length = 0; bool active = false; };
struct body {
    point pos, previous, pin, velocity;
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
    int attached = -1;
    float spiderdistance = 0, spiderangle = 0;
    point spiderpos{};
};
enum class outcome { playing, won, lost };
class simulation {
public:
    void reset(const level& data);
    void tick();
    bool swipe(point start, point end);
    bool tap(point position);
    bool sever(int index, int segment);
    bool interact(point position);
    void animate();
    void camera();
    void samples(int index, int first, int count, point* output, int& size) const;
    const body& candy() const { return bodies[0]; }
    level definition{};
    std::array<body, 256> bodies{};
    std::array<rope, 8> ropes{};
    std::array<bool, 3> stars{};
    std::array<int, 3> collectedat{};
    std::array<point, 3> starpositions{};
    std::array<bool, 3> expired{};
    std::array<bool, 24> bubblesused{};
    std::array<int, 8> pumpages{};
    int bubble = -1, bubbleevents = 0, pumpevents = 0, ropeevents = 0, failreason = 0;
    int visuals = 0, pops = 0, popage = 100;
    point popposition{};
    float cameray = 0, cameraspeed = 20, cameradistance = 0;
    bool introduction = false;
    int bodycount = 0, ticks = 0, count = 0, resulttick = 0;
    bool mouth = false;
    int mouthtick = 0;
    outcome state = outcome::playing;
private:
    int add(point position, float inverse, bool pinned);
    void integrate(body& item, float acceleration);
    void satisfy(body& item);
    void detach(rope& item);
    void attach(int index, float length);
    void ropephysics();
    void hazards();
    void spiders();
    void fail(int reason);
    void burst();
};
}
