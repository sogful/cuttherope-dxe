#include "progress.hpp"
#include <cassert>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

int main(int argc, char** argv) {
    assert(argc == 2);
    const std::string directory = argv[1];
    auto bytes = [&](const char* name) {
        std::ifstream file(directory + "/" + name, std::ios::binary);
        return std::vector<char>(std::istreambuf_iterator<char>(file), {});
    };
    progress::store data;
    assert(data.initialize(argv[1]));
    data.complete(0, 4200, 2);
    data.preferences.skins = {51, 8, 15, 10};
    assert(data.save());
    const auto original = bytes("normal-a.sav");
    assert(!original.empty());
    data.toggle();
    assert(data.active().levels[0].score == 4200);
    data.complete(0, 5999, 3);
    assert(data.save() && bytes("normal-a.sav") == original && bytes("normal-b.sav").empty());
    data.toggle();
    assert(data.active().levels[0].score == 4200 && data.active().levels[0].stars == 2);
    data.toggle();
    data.clear();
    assert(data.save() && bytes("normal-a.sav") == original);
    progress::store loaded;
    assert(loaded.initialize(argv[1]) && !loaded.unlocked && loaded.active().levels[0].score == 4200);
    assert(loaded.preferences.skins[0] == 51 && loaded.preferences.skins[2] == 15);
    loaded.toggle();
    assert(loaded.active().levels[0].score == 0);
    loaded.toggle();
    loaded.complete(0, 5000, 3);
    assert(loaded.save());
    FILE* interrupted = std::fopen((directory + "/normal-b.sav").c_str(), "wb");
    assert(interrupted);
    std::fputs("interrupted test save", interrupted);
    std::fclose(interrupted);
    progress::store recovered;
    assert(recovered.initialize(argv[1]) && recovered.active().levels[0].score == 4200);
    progress::store unavailable;
    unavailable.complete(0, 6000, 3);
    assert(!unavailable.save() && unavailable.active().levels[0].score == 6000);
    std::uint32_t legacy[425][2]{};
    legacy[5][0] = 5100; legacy[5][1] = 2;
    unsigned checksum = 2166136261;
    for (unsigned char byte : *reinterpret_cast<unsigned char(*)[sizeof(legacy)]>(legacy)) checksum = (checksum ^ byte) * 16777619;
    const unsigned header[] = {0x58524443,1,0,sizeof(legacy),99,checksum};
    FILE* oldsave = std::fopen((directory + "/normal-a.sav").c_str(), "wb");
    assert(oldsave);
    assert(std::fwrite(header, sizeof(header), 1, oldsave) == 1 && std::fwrite(legacy, sizeof(legacy), 1, oldsave) == 1);
    std::fclose(oldsave);
    const auto preserved = bytes("normal-a.sav");
    progress::store migrated;
    assert(migrated.initialize(argv[1]));
    assert(migrated.active().levels[5].score == 5100 && migrated.active().levels[5].completed == 1);
    migrated.complete(6, 0, 0);
    assert(migrated.save() && bytes("normal-a.sav") == preserved);
    progress::store zero;
    assert(zero.initialize(argv[1]) && zero.active().levels[6].completed == 1 && zero.active().levels[6].score == 0);
    zero.unlock(7); assert(zero.save());
    progress::store skipped;
    assert(skipped.initialize(argv[1]) && skipped.active().levels[7].completed==2 && skipped.active().levels[7].score==0);
    skipped.complete(7,0,0); assert(skipped.active().levels[7].completed==1);
    skipped.toggle(); skipped.unlock(9); assert(skipped.active().levels[9].completed==2);
    skipped.toggle(); assert(skipped.active().levels[9].completed==0);
    std::puts("PASS: isolated normal/unlocked files, profile switching, reset isolation, settings reload, interrupted-write recovery, no-storage fallback");
}
