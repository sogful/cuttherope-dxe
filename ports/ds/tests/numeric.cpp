#include "numeric.hpp"
#include <cstdio>
#include <cmath>
#include <initializer_list>

int main() {
    unsigned random = 0x4583a671;
    auto next = [&]() { random ^= random << 13; random ^= random >> 17; random ^= random << 5; return random; };
    auto check = [&](float a, float b) {
        const float actual = numeric::subtract(a, b), expected = a - b;
        if (numeric::bits(actual) != numeric::bits(expected) && !(std::isnan(actual) && std::isnan(expected))) {
            std::printf("Mismatch: %08x %08x -> %08x != %08x\n", numeric::bits(a), numeric::bits(b), numeric::bits(actual), numeric::bits(expected));
            return false;
        }
        return true;
    };
    for (unsigned i = 0; i < 2000000; ++i) {
        const auto a = next(), b = next();
        if (!check(numeric::value(a), numeric::value(b))) return 1;
        if (!check(numeric::value(a), numeric::value((a & 0xff800000) | (b & 0x7fffff)))) return 2;
    }
    for (unsigned a : {0u, 0x80000000u, 1u, 0x7fffffu, 0x800000u, 0x3f800000u, 0xbf800000u, 0x7f7fffffu, 0x7f800000u, 0xff800000u, 0x7fc00000u})
        for (unsigned b : {0u, 0x80000000u, 1u, 0x7fffffu, 0x800000u, 0x3f800000u, 0x7f7fffffu, 0x7f800000u})
            if (!check(numeric::value(a), numeric::value(b))) return 3;
    std::puts("PASS: 4,000,088 numeric pairs including normal, subnormal, zero, infinity and NaN cases");
}
