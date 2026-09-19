#include "packed.hpp"
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

int main(int argc, char** argv) {
    for (int index = 1; index < argc; ++index) {
        std::ifstream stream(argv[index], std::ios::binary);
        std::vector<unsigned char> source(std::istreambuf_iterator<char>{stream}, {});
        if (source.size() < 4) return 1;
        const unsigned size = source[1] | (source[2] << 8) | (source[3] << 16);
        if (size > 131072) return 2;
        std::vector<unsigned char> output(size);
        if (!packed::unpack(source.data(), output.data(), output.size())) return 3;
        std::uint32_t hash = 2166136261;
        for (unsigned char value : output) hash = (hash ^ value) * 16777619;
        std::printf("%u %u\n", size, hash);
    }
}
