#pragma once
#include <array>
#include <cstdint>

namespace progress {
struct record { std::uint32_t score = 0, stars = 0; };
struct profile { std::array<record, 425> levels{}; };
struct settings {
    std::uint32_t effects = 1, music = 1, locale = 0, clickcut = 0;
    std::array<std::uint32_t, 4> skins{};
};
class store {
public:
    profile normal{}, sandbox{};
    settings preferences{};
    bool unlocked = false, writable = false, failed = false;
    bool initialize(const char* directory);
    bool save();
    void toggle();
    void clear();
    void complete(int level, unsigned score, unsigned stars);
    profile& active() { return unlocked ? sandbox : normal; }
    const profile& active() const { return unlocked ? sandbox : normal; }
private:
    char directory[192]{};
    bool dirty[3]{}, sandboxready = false;
    unsigned generations[3]{};
    settings savedsettings{};
};
}
