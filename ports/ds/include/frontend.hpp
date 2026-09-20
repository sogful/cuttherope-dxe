#pragma once
#include "interface.hpp"

namespace frontend {
void reset();
void initialize();
void reserve(unsigned bytes);
void stage(int texture, const void* pixels, unsigned bytes, const void* palette = nullptr, int colors = 0);
void present();
void capture();
int background(int box, int sections, int top, int texture = 0);
void draw(const ui::controller& menu);
void preparegame(const ui::controller& menu, const dx::simulation& game, int frame);
void render(bool overlay = false, bool ground = false);
void ribbon();
void prepareoverlay(const ui::controller& menu, const dx::simulation& game);
void drawresult(const ui::controller& menu, const dx::simulation& game);
unsigned texturebytes();
unsigned cacherepacks();
unsigned cachefault();
}
