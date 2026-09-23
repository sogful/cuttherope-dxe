#pragma once

struct hardwareframe {
    unsigned frame = 0, micros = 0, startblank = 0, endblank = 0;
    int view = 0, level = 0, state = 0, hooks = 0, bodies = 0, cameray = 0;
    unsigned textures = 0, repacks = 0, upperframes = 0, renderfault = 0, upperfault = 0;
    bool transition = false, introduction = false, door = false;
};

namespace hardwareprofile {
#if defined(DS_LOGGING) && defined(DS_PROFILE)
void record(const hardwareframe& frame);
#else
inline void record(const hardwareframe&) {}
#endif
}
