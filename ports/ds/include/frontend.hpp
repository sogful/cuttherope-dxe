#pragma once
#include "interface.hpp"

namespace frontend {
void reset();
void initialize();
void reserve(unsigned bytes);
int background(int box);
void draw(const ui::controller& menu);
void preparegame(const ui::controller& menu, const dx::simulation& game, int frame);
void render(bool overlay = false, bool ground = false);
void ribbon();
void prepareoverlay(const ui::controller& menu, const dx::simulation& game);
void drawresult(const ui::controller& menu, const dx::simulation& game);
unsigned texturebytes();
}
