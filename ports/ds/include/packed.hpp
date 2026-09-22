#pragma once
#include <cstddef>

namespace packed {
struct diagnosis {
    const char* reason = nullptr;
    unsigned header = 0, consumed = 0, produced = 0, declared = 0, length = 0, distance = 0;
    unsigned hash = 2166136261u;
};
template<bool inspect = false, class reader>
bool stream(reader& next, unsigned char* output, std::size_t capacity, diagnosis* detail = nullptr) {
    diagnosis report;
    auto take = [&]() {
        const int value = next();
        if constexpr (inspect) if (value >= 0) {
            if (report.consumed < 4) report.header |= static_cast<unsigned>(value) << (report.consumed*8);
            ++report.consumed;
            report.hash = (report.hash ^ value)*16777619u;
        }
        return value;
    };
    auto finish = [&](const char* reason, unsigned produced = 0, unsigned length = 0, unsigned distance = 0) {
        if constexpr (inspect) {
            report.reason = reason; report.produced = produced; report.length = length; report.distance = distance;
            if (detail) *detail = report;
        } else {
            (void)produced; (void)length; (void)distance;
        }
        return reason == nullptr;
    };
    const int kind = take(), a = take(), b = take(), c = take();
    if (kind < 0 || a < 0 || b < 0 || c < 0) return finish("header.eof");
    if (kind != 0x10) return finish("header.kind");
    const unsigned size = a | (b << 8) | (c << 16);
    if constexpr (inspect) report.declared = size;
    if (size > capacity) return finish("output.capacity");
    unsigned done = 0;
    while (done < size) {
        const int flags = take();
        if (flags < 0) return finish("flags.eof",done);
        for (int mask = 128; mask && done < size; mask >>= 1) {
            const int first = take();
            if (first < 0) return finish("token.eof",done);
            if (!(flags & mask)) { output[done++] = first; continue; }
            const int second = take();
            if (second < 0) return finish("match.eof",done);
            unsigned length = (first >> 4) + 3;
            const unsigned distance = ((first & 15) << 8) + second + 1;
            if (distance > done) return finish("match.distance",done,length,distance);
            if (length > size - done) return finish("match.length",done,length,distance);
            while (length--) { output[done] = output[done - distance]; ++done; }
        }
    }
    return finish(nullptr,done);
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
