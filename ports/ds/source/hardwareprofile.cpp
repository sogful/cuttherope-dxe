#include "hardwareprofile.hpp"

#if defined(DS_LOGGING) && defined(DS_PROFILE)
#include "gamelog.hpp"
#include "profiling.hpp"
#include <nds.h>
#include <algorithm>
#include <cstdint>

namespace hardwareprofile {
namespace {
constexpr profiling::metric stages[] = {
    profiling::physics, profiling::samples, profiling::ropes, profiling::scene,
    profiling::upload, profiling::read, profiling::decode, profiling::wait,
    profiling::transfer, profiling::render, profiling::upperdraw,
    profiling::upperplace, profiling::upperblit, profiling::upperworld,
    profiling::upperhud
};

struct slowframe {
    unsigned frame = 0, micros = 0, crossed = 0;
    unsigned physics = 0, ropes = 0, render = 0, upper = 0, upload = 0, wait = 0;
    unsigned segments = 0, polygons = 0, commands = 0;
};

struct window {
    unsigned frames = 0, firstframe = 0, lastframe = 0, firstblank = 0, lastblank = 0;
    int view = 0, level = 0, state = 0, cameramin = 0, cameramax = 0;
    std::uint64_t total = 0, stagesums[sizeof(stages)/sizeof(stages[0])]{};
    unsigned maximum = 0, stagemax[sizeof(stages)/sizeof(stages[0])]{};
    unsigned bins[8]{}, crossed = 0, maxcrossed = 0, cadence = 0, maxcadence = 0;
    unsigned maxweights = 0, maxsegments = 0, maxbodies = 0, maxhooks = 0;
    unsigned maxpolygons = 0, maxvertices = 0, maxcommands = 0, maxtextures = 0;
    unsigned uploads = 0, uploadbytes = 0, upperreads = 0, evictions = 0;
    unsigned visibleuploads = 0, holds = 0, gpuerrors = 0;
    unsigned firstrepacks = 0, lastrepacks = 0, firstupper = 0, lastupper = 0;
    unsigned transitions = 0, introductions = 0, doors = 0, renderfaults = 0, upperfaults = 0;
    slowframe slow[2]{};
};

window current;
unsigned previousstart = 0;

unsigned usec(std::uint64_t ticks) {
    return timerTicks2usec(static_cast<unsigned>(ticks));
}

slowframe snapshot(const hardwareframe& frame,unsigned crossed) {
    return {frame.frame,frame.micros,crossed,
        profiling::data[profiling::physics],profiling::data[profiling::ropes],
        profiling::data[profiling::render],profiling::data[profiling::upperdraw],
        profiling::data[profiling::upload],profiling::data[profiling::wait],
        profiling::data[profiling::segments],profiling::data[profiling::polygons],
        profiling::data[profiling::commands]};
}

void flush() {
    if (!current.frames) return;
    const unsigned span=current.lastblank-current.firstblank+1;
    gamelog::event("PERF window frames=%u range=%u-%u context=%d/%d/%d frame_us=%u/%u vblank_span=%u crossed=%u/%u cadence=%u/%u bins=%u,%u,%u,%u,%u,%u,%u,%u",
        current.frames,current.firstframe,current.lastframe,current.view,current.level,current.state,
        static_cast<unsigned>(current.total/current.frames),current.maximum,span,current.crossed,current.maxcrossed,current.cadence,current.maxcadence,
        current.bins[0],current.bins[1],current.bins[2],current.bins[3],current.bins[4],current.bins[5],current.bins[6],current.bins[7]);
    gamelog::event("PERF stages_us avg/max physics=%u/%u samples=%u/%u ropes=%u/%u scene=%u/%u upload=%u/%u read=%u/%u decode=%u/%u wait=%u/%u transfer=%u/%u render=%u/%u upper=%u/%u place=%u/%u blit=%u/%u world=%u/%u hud=%u/%u",
        usec(current.stagesums[0]/current.frames),usec(current.stagemax[0]),
        usec(current.stagesums[1]/current.frames),usec(current.stagemax[1]),
        usec(current.stagesums[2]/current.frames),usec(current.stagemax[2]),
        usec(current.stagesums[3]/current.frames),usec(current.stagemax[3]),
        usec(current.stagesums[4]/current.frames),usec(current.stagemax[4]),
        usec(current.stagesums[5]/current.frames),usec(current.stagemax[5]),
        usec(current.stagesums[6]/current.frames),usec(current.stagemax[6]),
        usec(current.stagesums[7]/current.frames),usec(current.stagemax[7]),
        usec(current.stagesums[8]/current.frames),usec(current.stagemax[8]),
        usec(current.stagesums[9]/current.frames),usec(current.stagemax[9]),
        usec(current.stagesums[10]/current.frames),usec(current.stagemax[10]),
        usec(current.stagesums[11]/current.frames),usec(current.stagemax[11]),
        usec(current.stagesums[12]/current.frames),usec(current.stagemax[12]),
        usec(current.stagesums[13]/current.frames),usec(current.stagemax[13]),
        usec(current.stagesums[14]/current.frames),usec(current.stagemax[14]));
    gamelog::event("PERF load max weights=%u segments=%u bodies=%u hooks=%u polys=%u verts=%u commands=%u textures=%u events upload=%u/%u reads=%u evict=%u visible=%u holds=%u gpu=%x repacks=%u upperframes=%u flags transition=%u intro=%u door=%u faults=%u/%u camera=%d..%d",
        current.maxweights,current.maxsegments,current.maxbodies,current.maxhooks,current.maxpolygons,
        current.maxvertices,current.maxcommands,current.maxtextures,current.uploads,current.uploadbytes,
        current.upperreads,current.evictions,current.visibleuploads,current.holds,current.gpuerrors,
        current.lastrepacks-current.firstrepacks,current.lastupper-current.firstupper,current.transitions,
        current.introductions,current.doors,current.renderfaults,current.upperfaults,current.cameramin,current.cameramax);
    for (unsigned rank=0;rank<2 && current.slow[rank].micros;++rank) {
        const slowframe& slow=current.slow[rank];
        gamelog::event("PERF slow rank=%u frame=%u total_us=%u crossed=%u stage_us physics=%u ropes=%u render=%u upper=%u upload=%u wait=%u load segments=%u polygons=%u commands=%u",
            rank+1,slow.frame,slow.micros,slow.crossed,usec(slow.physics),usec(slow.ropes),
            usec(slow.render),usec(slow.upper),usec(slow.upload),usec(slow.wait),
            slow.segments,slow.polygons,slow.commands);
    }
    current={};
}

void begin(const hardwareframe& frame) {
    current.firstframe=frame.frame;
    current.firstblank=frame.startblank;
    current.view=frame.view; current.level=frame.level; current.state=frame.state;
    current.cameramin=current.cameramax=frame.cameray;
    current.firstrepacks=current.lastrepacks=frame.repacks;
    current.firstupper=current.lastupper=frame.upperframes;
}
}

void record(const hardwareframe& frame) {
    if (current.frames && (frame.view!=current.view || frame.level!=current.level || frame.state!=current.state)) flush();
    if (!current.frames) begin(frame);
    ++current.frames;
    current.lastframe=frame.frame; current.lastblank=frame.endblank;
    current.total+=frame.micros; current.maximum=std::max(current.maximum,frame.micros);
    static constexpr unsigned limits[] = {8000,12000,16667,20000,25000,33334,50000};
    unsigned bin=0; while (bin<7 && frame.micros>=limits[bin]) ++bin; ++current.bins[bin];
    const unsigned crossed=frame.endblank-frame.startblank;
    current.crossed+=crossed; current.maxcrossed=std::max(current.maxcrossed,crossed);
    const unsigned cadence=previousstart ? frame.startblank-previousstart : 0;
    current.cadence+=cadence; current.maxcadence=std::max(current.maxcadence,cadence);
    previousstart=frame.startblank;
    for (unsigned index=0;index<sizeof(stages)/sizeof(stages[0]);++index) {
        const unsigned value=profiling::data[stages[index]];
        current.stagesums[index]+=value; current.stagemax[index]=std::max(current.stagemax[index],value);
    }
    current.maxweights=std::max(current.maxweights,profiling::data[profiling::weights]);
    current.maxsegments=std::max(current.maxsegments,profiling::data[profiling::segments]);
    current.maxbodies=std::max(current.maxbodies,profiling::data[profiling::bodies]);
    current.maxhooks=std::max(current.maxhooks,static_cast<unsigned>(std::max(frame.hooks,0)));
    current.maxpolygons=std::max(current.maxpolygons,profiling::data[profiling::polygons]);
    current.maxvertices=std::max(current.maxvertices,profiling::data[profiling::vertices]);
    current.maxcommands=std::max(current.maxcommands,profiling::data[profiling::commands]);
    current.maxtextures=std::max(current.maxtextures,frame.textures);
    current.uploads+=profiling::data[profiling::uploads]; current.uploadbytes+=profiling::data[profiling::uploadbytes];
    current.upperreads+=profiling::data[profiling::upperreads]; current.evictions+=profiling::data[profiling::previousevictions];
    current.visibleuploads+=profiling::data[profiling::visibleupload]; current.holds+=profiling::data[profiling::holds];
    current.gpuerrors|=profiling::data[profiling::gpuerrors];
    current.lastrepacks=frame.repacks; current.lastupper=frame.upperframes;
    current.cameramin=std::min(current.cameramin,frame.cameray); current.cameramax=std::max(current.cameramax,frame.cameray);
    current.transitions+=frame.transition; current.introductions+=frame.introduction; current.doors+=frame.door;
    current.renderfaults+=frame.renderfault!=0; current.upperfaults+=frame.upperfault!=0;
    const slowframe candidate=snapshot(frame,crossed);
    if (candidate.micros>current.slow[0].micros) { current.slow[1]=current.slow[0]; current.slow[0]=candidate; }
    else if (candidate.micros>current.slow[1].micros) current.slow[1]=candidate;
    if (current.frames>=600) flush();
}
}
#endif
