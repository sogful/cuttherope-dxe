#pragma once
#include <cstdint>
#include <stdexcept>
using u16 = std::uint16_t;
inline void nocashMessage(const char* message) { throw std::runtime_error(message); }
inline void swiWaitForVBlank() {}
inline constexpr int REG_VCOUNT = 192;
inline constexpr int RGB15(int r, int g, int b) { return r | (g << 5) | (b << 10); }
inline constexpr int POLY_ALPHA(int a) { return a; }
inline constexpr int POLY_ID(int a) { return a; }
inline constexpr int POLY_CULL_NONE = 0;
inline int floattof32(float a) { return static_cast<int>(a * 4096); }
