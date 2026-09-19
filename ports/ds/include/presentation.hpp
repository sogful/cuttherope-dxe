#pragma once
#include "simulation.hpp"

namespace display {
void initialize();
void draw(const dx::simulation& game, int frame, bool paused, bool touching, dx::point finger);
void status(const dx::simulation& game, bool paused, unsigned micros, unsigned peak, int frames, int misses);
dx::point world(int x, int y);
bool retry(int x, int y);
}
