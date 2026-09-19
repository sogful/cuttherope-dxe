#pragma once
#include "simulation.hpp"

namespace trace {
struct segment { dx::point first, last; float life; };
struct particle {
    dx::point position, origin, velocity;
    float life, total, size, rotation, spin;
    int preset, quad;
};
class system {
public:
    std::array<particle, 200> particles{};
    std::array<segment, 20> segments{};
    int count = 0, length = 0, mode = 0;
    dx::point head{}, direction{};
    float angle = 0;
    void reset();
    void update(bool held, dx::point point, int skin);
private:
    bool down = false;
    float burst = 0, counters[11]{};
    dx::point previous{}, history[10]{};
    int cursor = 0, samples = 0;
    unsigned seed = 0x43545244;
    float random(float base, float variance);
    void spawn(int preset);
};
extern system trail;
}
