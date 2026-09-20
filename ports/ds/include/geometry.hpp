#pragma once
#include "simulation.hpp"
namespace dx {
point rotate(point value, float angle);
bool segment(point a, point b, point c, point d);
bool linebox(point a, point b, point center, float radius = 15);
}
