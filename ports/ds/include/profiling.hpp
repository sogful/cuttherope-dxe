#pragma once

#ifdef DS_PROFILE
#include <nds.h>

extern "C" { extern volatile unsigned profiledata[32]; extern volatile unsigned profilestress; }
namespace profiling {
enum metric { physics = 1, samples, ropes, scene, upload, read, decode, wait, transfer, render,
    weights, segments, bodies, uploads, uploadbytes, previousevictions, polygons, vertices,
    gpuerrors, uploadstart, uploadend, visibleupload, commands, holds, upperdraw, upperreads,
    upperplace, upperblit, upperworld, upperhud, menuupdate, sound, persist, levelsetup, count };
inline unsigned data[40]{};
inline void begin() {
    for (unsigned& item : data) item = 0;
}
inline void gpu() {
    if (GFX_POLYGON_RAM_USAGE > data[polygons]) data[polygons] = GFX_POLYGON_RAM_USAGE;
    if (GFX_VERTEX_RAM_USAGE > data[vertices]) data[vertices] = GFX_VERTEX_RAM_USAGE;
    data[gpuerrors] |= GFX_CONTROL & (GL_COLOR_UNDERFLOW | GL_POLY_OVERFLOW);
}
inline void finish(unsigned frame) {
    gpu();
    for (int i = 1; i < 32; ++i) profiledata[i] = data[i];
    profiledata[0] = frame;
}
struct scope {
    metric id;
    unsigned start;
    explicit scope(metric value) : id(value), start(cpuGetTiming()) {}
    ~scope() { data[id] += cpuGetTiming() - start; }
};
}
#define DS_JOIN_INNER(a, b) a##b
#define DS_JOIN(a, b) DS_JOIN_INNER(a, b)
#define DS_SCOPE(name) profiling::scope DS_JOIN(profilescope, __LINE__)(profiling::name)
#define DS_PROFILE_DO(...) do { __VA_ARGS__; } while (false)
#else
#define DS_SCOPE(name) do {} while (false)
#define DS_PROFILE_DO(...) do {} while (false)
#endif
