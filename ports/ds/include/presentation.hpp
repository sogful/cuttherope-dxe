#pragma once
#include "simulation.hpp"

namespace display {
void initialize();
void draw(const dx::simulation& game, int frame, bool paused, bool touching, dx::point finger);
dx::point world(int x, int y);
bool retry(int x, int y);
}
