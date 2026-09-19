#include "progress.hpp"
#include <algorithm>
#include <cstdio>
#include <cstring>

namespace progress {
static unsigned hash(const void* source, unsigned size) {
    unsigned value = 2166136261;
    const auto* bytes = static_cast<const unsigned char*>(source);
    while (size--) value = (value ^ *bytes++) * 16777619;
    return value;
}
struct header { unsigned magic, version, kind, size, generation, checksum; };
static const char* names[] = {"normal", "unlocked", "settings"};
static bool read(const char* path, int kind, void* output, unsigned size, unsigned& generation) {
    FILE* file = std::fopen(path, "rb");
    if (!file) return false;
    header info{};
    bool valid = std::fread(&info, sizeof(info), 1, file) == 1 && info.magic == 0x58524443 && info.version == 1 &&
        info.kind == static_cast<unsigned>(kind) && info.size == size && std::fread(output, size, 1, file) == 1 && std::fgetc(file) == EOF;
    std::fclose(file);
    valid = valid && hash(output, size) == info.checksum;
    if (valid) generation = info.generation;
    return valid;
}
bool store::initialize(const char* path) {
    if (!path || std::strlen(path) >= sizeof(directory)) return false;
    std::strcpy(directory, path);
    writable = true;
    for (int kind = 0; kind < 3; ++kind) {
        void* output = kind == 0 ? static_cast<void*>(&normal) : kind == 1 ? static_cast<void*>(&sandbox) : static_cast<void*>(&preferences);
        const unsigned size = kind < 2 ? sizeof(profile) : sizeof(settings);
        alignas(4) unsigned char buffer[sizeof(profile)];
        for (char slot : {'a', 'b'}) {
            char name[256];
            std::snprintf(name, sizeof(name), "%s/%s-%c.sav", directory, names[kind], slot);
            unsigned generation = 0;
            if (read(name, kind, buffer, size, generation) && generation >= generations[kind]) {
                std::memcpy(output, buffer, size);
                generations[kind] = generation;
                if (kind == 1) sandboxready = true;
            }
        }
    }
    for (profile* data : {&normal, &sandbox}) for (record& level : data->levels) {
        level.stars = std::min<std::uint32_t>(3, level.stars);
        level.score = std::min<std::uint32_t>(6000, level.score);
    }
    preferences.locale = std::min<std::uint32_t>(11, preferences.locale);
    const unsigned counts[] = {52, 9, 16, 11};
    for (int i = 0; i < 4; ++i) if (preferences.skins[i] >= counts[i]) preferences.skins[i] = 0;
    savedsettings = preferences;
    return true;
}
void store::toggle() {
    unlocked = !unlocked;
    if (unlocked && !sandboxready) { sandbox = normal; sandboxready = true; dirty[1] = true; }
}
void store::clear() { active() = {}; dirty[unlocked ? 1 : 0] = true; }
void store::complete(int level, unsigned score, unsigned stars) {
    if (level < 0 || level >= 425) return;
    record& value = active().levels[level];
    if (score > value.score || stars > value.stars) {
        value.score = std::max<std::uint32_t>(value.score, std::min(6000u, score));
        value.stars = std::max<std::uint32_t>(value.stars, std::min(3u, stars));
        dirty[unlocked ? 1 : 0] = true;
    }
}
bool store::save() {
    if (!writable) return false;
    // Settings share a journal, while results and resets only touch the active profile.
    dirty[2] = dirty[2] || std::memcmp(&preferences, &savedsettings, sizeof(settings));
    failed = false;
    for (int kind = 0; kind < 3; ++kind) {
        if (!dirty[kind]) continue;
        const void* input = kind == 0 ? static_cast<const void*>(&normal) : kind == 1 ? static_cast<const void*>(&sandbox) : static_cast<const void*>(&preferences);
        const unsigned size = kind < 2 ? sizeof(profile) : sizeof(settings);
        const unsigned generation = generations[kind] + 1;
        char name[256];
        std::snprintf(name, sizeof(name), "%s/%s-%c.sav", directory, names[kind], generation % 2 ? 'a' : 'b');
        FILE* file = std::fopen(name, "wb");
        if (!file) { failed = true; continue; }
        const header info{0x58524443, 1, static_cast<unsigned>(kind), size, generation, hash(input, size)};
        bool success = std::fwrite(&info, sizeof(info), 1, file) == 1 && std::fwrite(input, size, 1, file) == 1;
        success = std::fflush(file) == 0 && success;
        success = std::fclose(file) == 0 && success;
        if (success) {
            generations[kind] = generation; dirty[kind] = false;
            if (kind == 2) savedsettings = preferences;
        }
        else failed = true;
    }
    return !failed;
}
}
