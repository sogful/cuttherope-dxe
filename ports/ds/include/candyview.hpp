#pragma once
#include "simulation.hpp"
#include <cmath>

namespace gamevisuals {
inline int candyalpha(dx::point position) {
    if (position.y>=-200) return 31;
    if (position.y<=-400) return 0;
    return std::lround((position.y+400)*(31.0f/200));
}
}
