#pragma once
#include "interface.hpp"

namespace audio {
void initialize();
void update(const ui::controller& menu);
void effect(const unsigned char* data, unsigned size);
}
