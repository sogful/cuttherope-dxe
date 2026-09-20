#pragma once
#include <cstdint>
#include <cstring>
#include <limits>

namespace numeric {
static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559 && std::numeric_limits<float>::digits == 24);
inline std::uint32_t bits(float value) { std::uint32_t result; std::memcpy(&result, &value, 4); return result; }
inline float value(std::uint32_t bits) { float result; std::memcpy(&result, &bits, 4); return result; }

inline float subtract(float a, float b) {
    // Equal sign/exponent cancels the implicit leading bits exactly; only normalize.
    const auto first = bits(a), second = bits(b);
    const unsigned exponent = (first >> 23) & 255;
    if (((first ^ second) & 0xff800000u) || !exponent || exponent == 255) return a - b;
    const int difference = static_cast<int>(first & 0x7fffff) - static_cast<int>(second & 0x7fffff);
    if (!difference) return 0;
    const unsigned sign = (first & 0x80000000u) ^ (difference < 0 ? 0x80000000u : 0);
    const unsigned magnitude = difference < 0 ? -difference : difference;
    const unsigned shift = __builtin_clz(magnitude) - 8;
    if (exponent <= shift) return value(sign | (magnitude << (exponent - 1)));
    return value(sign | ((exponent - shift) << 23) | ((magnitude << shift) & 0x7fffff));
}

}
