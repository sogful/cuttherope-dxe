#pragma once
#include "interface.hpp"

namespace frontend {
void reset();
void initialize();
void reserve(unsigned bytes);
void draw(const ui::controller& menu);
void preparegame(const ui::controller& menu, const dx::simulation& game, int frame);
void render();
void ribbon();
unsigned texturebytes();
}
