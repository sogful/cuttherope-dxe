#pragma once
#include <cstdint>

namespace upper {
struct clip { int left = 0, top = 0, right = 256, bottom = 192; };
void initialize(const char* prefix = "nitro:/");
void begin(int background, int top = 0);
void shade(int brightness);
void transient(bool enabled);
void cutout(bool enabled);
void sprite(int id, int x, int y, float scale = 1, float vertical = 1, int angle = 0, int flip = 0,
            int alpha = 31, unsigned color = 0x7fff, clip bounds = {});
void immediate(int id, int x, int y, int alpha = 31, float scale = 1);
void photo();
void rect(clip bounds, unsigned color, int alpha);
void line(int x, int y, int endx, int endy, unsigned color, int alpha);
void finish();
void vblank();
const unsigned char* pixels();
const std::uint16_t* colors();
unsigned fault();
unsigned updates();
unsigned reads();
}
