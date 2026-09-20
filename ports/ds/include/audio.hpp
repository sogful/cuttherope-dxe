#pragma once
#include "interface.hpp"

namespace audio {
void initialize();
void update(const ui::controller& menu);
void world(const ui::controller& menu, const dx::simulation& game);
void effect(const unsigned char* data, unsigned size);
}
