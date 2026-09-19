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
    std::puts("PASS: isolated normal/unlocked files, profile switching, reset isolation, settings reload, interrupted-write recovery, no-storage fallback");
}
