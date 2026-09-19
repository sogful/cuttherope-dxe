#pragma once
#include "simulation.hpp"
#include "interface.hpp"

namespace display {
void initialize();
bool busy();
void draw(const dx::simulation& game, int frame, const ui::controller& menu, bool touching, dx::point finger);
dx::point world(int x, int y);
}
