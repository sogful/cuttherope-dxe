#pragma once
#include "interface.hpp"

namespace frontend {
void reset();
void initialize();
void reserve(unsigned bytes);
void stage(int texture, const void* pixels, unsigned bytes, const void* palette = nullptr, int colors = 0);
void present(bool synchronize = false);
void submit();
void capture();
unsigned char* workspace();
unsigned workgeneration(unsigned boundary = 262144);
int background(int box, int sections, int top, int texture = 0);
void draw(const ui::controller& menu);
void preparegame(const ui::controller& menu, const dx::simulation& game, int frame, bool upper = false);
void upperworld();
void render(bool overlay = false, bool ground = false, int stars = 0);
void ribbon();
void prepareoverlay(const ui::controller& menu, const dx::simulation& game);
void drawresult(const ui::controller& menu, const dx::simulation& game);
bool uppermenu(int background);
void upperoverlay(const ui::controller& menu, const dx::simulation& game);
void paintupper(bool ground = false, int stars = 0);
unsigned texturebytes();
unsigned cacherepacks();
unsigned cachefault();
}
