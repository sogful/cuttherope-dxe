#pragma once
#include <cstddef>

namespace packed {
template<class reader> bool stream(reader& next, unsigned char* output, std::size_t capacity) {
    const int kind = next(), a = next(), b = next(), c = next();
    if (kind != 0x10 || a < 0 || b < 0 || c < 0) return false;
    const unsigned size = a | (b << 8) | (c << 16);
    if (size > capacity) return false;
    unsigned done = 0;
    while (done < size) {
        const int flags = next();
        if (flags < 0) return false;
        for (int mask = 128; mask && done < size; mask >>= 1) {
            const int first = next();
            if (first < 0) return false;
            if (!(flags & mask)) { output[done++] = first; continue; }
            const int second = next();
            if (second < 0) return false;
            unsigned length = (first >> 4) + 3;
            const unsigned distance = ((first & 15) << 8) + second + 1;
            if (distance > done || length > size - done) return false;
            while (length--) { output[done] = output[done - distance]; ++done; }
        }
    }
    return true;
}

inline bool unpack(const unsigned char* source, unsigned char* output, std::size_t capacity) {
    const unsigned size = source[1] | (source[2] << 8) | (source[3] << 16);
    if (source[0] != 0x10 || size > capacity) return false;
    source += 4;
    unsigned char* end = output + size;
    unsigned char* begin = output;
    while (output < end) {
        const unsigned flags = *source++;
        for (int mask = 128; mask && output < end; mask >>= 1) {
            if (!(flags & mask)) { *output++ = *source++; continue; }
            unsigned length = (source[0] >> 4) + 3;
            const unsigned distance = ((source[0] & 15) << 8) + source[1] + 1;
            source += 2;
            if (distance > static_cast<unsigned>(output - begin) || length > static_cast<unsigned>(end - output)) return false;
            const unsigned char* match = output - distance;
            while (length >= 4) {
                output[0] = match[0]; output[1] = match[1];
                output[2] = match[2]; output[3] = match[3];
                output += 4; match += 4; length -= 4;
            }
            while (length--) *output++ = *match++;
        }
    }
    return true;
}
}
