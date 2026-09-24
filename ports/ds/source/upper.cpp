#include "upper.hpp"
#include "upperassets.hpp"
#include "frontend.hpp"
#include "menuassets.hpp"
#include "assets.hpp"
#include "packed.hpp"
#include "assetio.hpp"
#include "paged.hpp"
#include "upperbgstore.hpp"
#include "profiling.hpp"
#include "gamelog.hpp"
#include <nds.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>

#ifdef __NDS__
#define DS_HOT ITCM_CODE
#else
#define DS_HOT
#endif

namespace upper {
alignas(32) static unsigned char backdrop[256*208];
alignas(32) static unsigned char savedframe[256*192];
static unsigned char* lookup;
static unsigned lookupversion=~0u;
alignas(32) static std::uint16_t palette[256];
static FILE *backgroundfile, *palettefile, *menufile, *photofile, *hudfile, *motionfile;
static int backgroundid = -1, backgroundtop = -1, paletteid = -1, brightness = 31;
static unsigned version = 0, cursor = 0, age = 0, completed = 0, readbytes = 0, error = 0;
#ifdef __NDS__
static volatile bool pending = false;
#endif
static bool palettechanged = false;
static bool photograph = false;
static bool moving = false;
static bool mirrored = false;
static bool starcovered=false, starcachevalid=false;
static bool blendvalid[2]{},hudvalid=false;
static int scrolltop=0;
static constexpr clip starbounds{58,60,198,104};
static_assert([] {
    for (int i=0;i<11;++i) {
        const auto& glyph=upperart::hud[i];
        if (glyph.ox < -22 || glyph.ox+glyph.width > 22 || glyph.oy < -22 || glyph.oy+glyph.height > 22) return false;
    }
    return true;
}(),"Star cache bounds must match the final-size HUD bake");
static bool overstars(int left,int top,int right,int bottom) {
    return left<starbounds.right && right>starbounds.left && top<starbounds.bottom && bottom>starbounds.top;
}
static constexpr unsigned cachestart = 262144, capacity = 163840;
struct entry {
    int id = -1;
    unsigned start = 0, size = 0, touched = 0;
    std::uint16_t colors[32]{};
};
static std::array<entry,24> cache;
alignas(32) static unsigned char scratch[1024];

unsigned fault() { return error; }
unsigned updates() { return completed; }
unsigned reads() { return readbytes; }
const unsigned char* pixels() { return frontend::workspace(); }
const std::uint16_t* colors() { return palette; }
void shade(int value) { brightness = std::clamp(value,0,31); }
void transient(bool enabled) { moving=enabled; }
void cutout(bool enabled) { photograph=enabled; }
void mirror(bool enabled) { mirrored=enabled; }
void cacheframe() { std::memcpy(savedframe,frontend::workspace(),sizeof(savedframe)); }
void restoreframe() { std::memcpy(frontend::workspace(),savedframe,sizeof(savedframe)); }
static void fail(unsigned value) { error = value; nocashMessage("CTRD DS: upper-screen asset error"); gamelog::event("upper.error code=%u",value); }
static bool read(FILE* file, unsigned offset, void* destination, unsigned bytes) {
    readbytes += bytes;
    DS_PROFILE_DO(profiling::data[profiling::upperreads] += bytes);
    if (!assetio::seek(file,offset,"upper") || assetio::read(file,destination,bytes,"upper")!=bytes) { fail(1); return false; }
    return true;
}
static bool backgroundread(unsigned offset,void* destination,unsigned bytes) {
    return paged::read(backgroundstore::upperbgpages,backgroundstore::upperbgshift,offset,destination,bytes,
        [](unsigned physical,void* target,unsigned size) { return read(backgroundfile,physical,target,size); });
}
static bool keyframe(unsigned position, unsigned char* destination) {
    if (!assetio::seek(motionfile,position,"shadow.key")) { fail(9); return false; }
    unsigned offset=0,available=0;
    auto next=[&]() -> int {
        if (offset==available) {
            available=assetio::read(motionfile,scratch,sizeof(scratch),"shadow.key"); offset=0;
            readbytes+=available;
            DS_PROFILE_DO(profiling::data[profiling::upperreads]+=available);
            if (!available) return -1;
        }
        return scratch[offset++];
    };
    if (!assetio::decode(next,destination,256*192,motionfile,"shadow.key",position)) { fail(10); return false; }
    return true;
}

void initialize(const char* prefix) {
    gamelog::event("upper.initialize.begin");
    // The final-size score no longer needs a third 64 KiB font blend table.
    // Reuse that upload workspace for the palette LUT, saving 32 KiB of RAM.
    lookup=frontend::workspace()+196608;
    lookupversion=~0u;
    auto open = [prefix](const char* name) {
        char path[512]; std::snprintf(path,sizeof(path),"%s%s",prefix,name);
        return std::fopen(path,"rb");
    };
    backgroundfile = open("upperbg.bin"); palettefile = open("upperpal.bin");
    menufile = open("menu.bin"); photofile = open("upperphoto.bin");
    hudfile = open("upperhud.bin"); motionfile = open("uppermotion.bin");
    if (!backgroundfile || !palettefile || !menufile || !photofile || !hudfile || !motionfile) fail(2);
    for (auto& item : cache) item.id = -1;
    backgroundid = backgroundtop = paletteid = -1;
    gamelog::event("upper.initialize.end error=%u",error);
}

void begin(int id, int top) {
    const auto& background = upperart::backgrounds[id];
    if (paletteid != background.palette) {
        const unsigned offset = background.palette*(512+32768);
        if (!read(palettefile,offset,palette,512)) return;
        paletteid = background.palette;
        palettechanged = true;
        lookupversion=~0u;
    }
    if (lookupversion!=frontend::workgeneration(196608)) {
        if (!read(palettefile,paletteid*(512+32768)+512,lookup,32768)) return;
        lookupversion=frontend::workgeneration(196608);
    }
    top = std::clamp(top,0,background.height-192);
    scrolltop=top;
    if (id != backgroundid || top < backgroundtop || top+192 > backgroundtop+208) {
        backgroundtop = top/16*16;
        const int rows = std::min(208,background.height-backgroundtop);
        if (!backgroundread(background.offset+backgroundtop*256,backdrop,rows*256)) return;
        backgroundid = id;
    }
    std::memcpy(frontend::workspace(),backdrop+(top-backgroundtop)*256,256*192);
    if (version != frontend::workgeneration()) {
        for (auto& item : cache) item.id = -1;
        version = frontend::workgeneration();
        cursor = 0;
    }
    brightness = 31;
    photograph = false;
    moving = false;
    mirrored = false;
    starcovered=false;
    ++age;
}

static entry* load(int id,unsigned size);
static constexpr int motionbase=menuart::pagecount+21;
static constexpr unsigned motioncache=256*192+upperart::motiontablebytes;

static DS_HOT void remap(unsigned char* destination,const unsigned char* source,const unsigned char* codes,const unsigned char* table,unsigned size) {
    for (unsigned i=0;i<size;++i) destination[i]=table[(source[i]<<5)|codes[i]];
}

struct playback {
    int frame=-1;
    unsigned bytes=0,consumed=0,fetched=0,offset=0,available=0,position=0,remaining=0,source=0;
    const unsigned char *base=nullptr,*table=nullptr;
    bool done=false;
};
static playback movie;
static bool motionbroken=false, motionfallback=false;

static bool patchfailure(const char* reason,unsigned code=8) {
    if (error!=code) gamelog::event("shadow.patch.failed reason=%s frame=%d source=%u bytes=%u consumed=%u fetched=%u cursor=%u available=%u position=%u remaining=%u",
        reason,movie.frame,movie.source,movie.bytes,movie.consumed,movie.fetched,movie.offset,movie.available,movie.position,movie.remaining);
    if (movie.base) std::memcpy(backdrop,movie.base,256*192);
    movie.done=true;
    motionbroken=motionfallback=true;
    fail(code);
    return false;
}
static bool startpatch(int frame) {
    const auto* index=reinterpret_cast<const unsigned*>(backdrop+256*192);
    movie.frame=frame; movie.done=false;
    movie.consumed=movie.fetched=movie.offset=movie.available=movie.remaining=0;
    movie.source=index[frame];
    if (!read(motionfile,movie.source,&movie.bytes,4)) return false;
    if (movie.bytes<2 || movie.bytes>256*192*5+2) return patchfailure("size");
    return true;
}

static DS_HOT bool advancepatch(unsigned budget) {
    const unsigned limit=std::min(movie.bytes,movie.consumed+budget);
    auto* input=frontend::streambuffer();
    movie.fetched=movie.consumed;
    movie.offset=movie.available=movie.remaining=0;
    auto next=[]() -> int {
        if (movie.offset==movie.available) {
            if (!assetio::seek(motionfile,movie.source+4+movie.fetched,"shadow.patch")) {
                patchfailure("seek",11);
                return -1;
            }
            movie.available=assetio::read(motionfile,frontend::streambuffer(),
                std::min(frontend::streamcapacity(),movie.bytes-movie.fetched),"shadow.patch");
            movie.offset=0; movie.fetched+=movie.available; readbytes+=movie.available;
            DS_PROFILE_DO(profiling::data[profiling::upperreads]+=movie.available);
            if (!movie.available) { patchfailure("eof",7); return -1; }
        }
        ++movie.consumed;
        return frontend::streambuffer()[movie.offset++];
    };
    while (!movie.done && movie.consumed<limit) {
        if (!movie.remaining) {
            const int low=next(), high=next();
            if (low<0 || high<0) return false;
            movie.position=low|(high<<8);
            if (movie.position==65535) { movie.done=true; break; }
            const int first=next(), second=next();
            if (first<0 || second<0) return false;
            movie.remaining=first|(second<<8);
            if (!movie.remaining || movie.position+movie.remaining>256*192 || movie.remaining>movie.bytes-movie.consumed) return patchfailure("range");
        }
        while (movie.remaining) {
            if (movie.offset==movie.available) {
                const int code=next();
                if (code<0) return false;
                backdrop[movie.position]=movie.table[(movie.base[movie.position]<<5)|code];
                ++movie.position; --movie.remaining;
            }
            const unsigned amount=std::min(movie.remaining,movie.available-movie.offset);
            remap(backdrop+movie.position,movie.base+movie.position,input+movie.offset,movie.table,amount);
            movie.position+=amount; movie.remaining-=amount; movie.offset+=amount; movie.consumed+=amount;
        }
        if (error) return false;
    }
    return true;
}

bool menu(int id,unsigned frame) {
    static int previous=-1;
    const bool animated=upperart::motion[id]>=0 && !motionbroken;
    const int step=animated?(frame/upperart::motioninterval)%upperart::motionsteps:0;
    const bool changed=id!=backgroundid || version!=frontend::workgeneration();
    if (motionfallback) {
        motionfallback=false;
        std::memcpy(frontend::workspace(),backdrop,256*192);
        movie.frame=-1; previous=step;
        return true;
    }
    if (!changed && previous==step) {
        if (animated) {
            if (movie.frame<0 && !startpatch((step+1)%upperart::motionsteps)) return false;
            if (!movie.done) advancepatch((movie.bytes+3)/4);
        }
        return false;
    }
    if (changed) movie.frame=-1;
    begin(id);
    if (animated) {
        // The scrolling background's spare sixteen rows hold the on-disk index.
        constexpr int entries=upperart::motionsteps+upperart::motionsteps/upperart::motionkey;
        static_assert(entries*4<=256*16);
        auto* index=reinterpret_cast<unsigned*>(backdrop+256*192);
        if (changed && !read(motionfile,0,index,entries*4)) return false;
        auto* cached=load(motionbase+id,motioncache);
        if (!cached) return false;
        const auto* base=frontend::workspace()+cachestart+cached->start;
        const auto* table=base+256*192;
        movie.base=base; movie.table=table;
        int first=previous+1;
        if (!changed && previous==upperart::motionsteps-1 && step==0) first=0;
        else if (changed || step<previous || step-previous>=upperart::motionkey) {
            const int key=step/upperart::motionkey;
            auto* codes=frontend::workspace();
            if (!keyframe(index[upperart::motionsteps+key],codes)) return false;
            remap(backdrop,base,codes,table,256*192);
            first=key*upperart::motionkey+1;
            movie.frame=-1;
        }
        for (int current=first;current<=step;++current) {
            if (movie.frame!=current && !startpatch(current)) return false;
            if (!movie.done && !advancepatch(movie.bytes)) return false;
        }
        std::memcpy(frontend::workspace(),backdrop,256*192);
    }
    movie.frame=-1;
    previous=step;
    return true;
}

static entry* load(int id, unsigned size) {
    for (auto& item : cache) if (item.id==id) { item.touched=age; return &item; }
    gamelog::trace("upper.cachemiss id=%d bytes=%u",id,size);
    gamelog::mark("upper.read",id);
    if (size>capacity) { fail(3); return nullptr; }
    size = (size+31)&~31u;
    if (cursor+size>capacity) cursor=0;
    for (auto& item : cache)
        if (item.id>=0 && item.start<cursor+size && cursor<item.start+item.size) item.id=-1;
    auto* target = &cache[0];
    for (auto& item : cache) {
        if (item.id<0) { target=&item; break; }
        if (item.touched<target->touched) target=&item;
    }
    target->id=id; target->start=cursor; target->size=size; target->touched=age;
    cursor += size;
    auto* destination = frontend::workspace()+cachestart+target->start;
    if (id>=motionbase) {
        const int background=id-motionbase;
        if (!backgroundread(upperart::backgrounds[background].offset,destination,256*192) ||
            !read(motionfile,upperart::motion[background],destination+256*192,upperart::motiontablebytes)) return nullptr;
        return target;
    }
    if (id==menuart::pagecount) {
        if (!read(photofile,0,destination,upperart::photowidth*upperart::photoheight*2)) return nullptr;
        return target;
    }
    if (id>menuart::pagecount) {
        if (!read(hudfile,(id-menuart::pagecount-1)*(upperart::hudbytes+upperart::hudtablebytes),destination,upperart::hudbytes)) return nullptr;
        return target;
    }
    const auto& page = menuart::pages[id];
    const unsigned palettebytes = page.direct ? 0 : 2u<<(8-page.alphabits);
    if (palettebytes && !read(menufile,page.offset,target->colors,palettebytes)) return nullptr;
    if (!assetio::seek(menufile,page.offset+palettebytes,"upper.menu")) { fail(4); return nullptr; }
    unsigned remaining=page.packed-palettebytes, offset=0, available=0;
    auto next = [&]() -> int {
        if (offset==available) {
            available=assetio::read(menufile,scratch,std::min(remaining,static_cast<unsigned>(sizeof(scratch))),"upper.menu");
            offset=0; remaining-=available; readbytes+=available;
            DS_PROFILE_DO(profiling::data[profiling::upperreads] += available);
            if (!available) return -1;
        }
        return scratch[offset++];
    };
    if (!assetio::decode(next,destination,size,menufile,"upper.menu",id)) { fail(5); return nullptr; }
    return target;
}

static unsigned tint(unsigned rgb, unsigned color) {
    if (color&0x8000) rgb=color&0x7fff;
    else if (color!=0x7fff) rgb = (((rgb&31)*(color&31)+15)/31) |
               (((((rgb>>5)&31)*((color>>5)&31)+15)/31)<<5) |
               (((((rgb>>10)&31)*((color>>10)&31)+15)/31)<<10);
    if (brightness==31) return rgb;
    return ((rgb&31)*brightness/31) | ((((rgb>>5)&31)*brightness/31)<<5) | ((((rgb>>10)&31)*brightness/31)<<10);
}
static unsigned blend(unsigned source, unsigned destination, unsigned alpha) {
    const unsigned weight=alpha+1, rest=32-weight;
    return ((((source&0x7c1f)*weight+(destination&0x7c1f)*rest)>>5)&0x7c1f) |
           ((((source&0x03e0)*weight+(destination&0x03e0)*rest)>>5)&0x03e0);
}

struct texture {
    const unsigned char* data;
    const std::uint16_t* palette;
    int stride, left, top, width, height, ox, oy, bits;
    bool direct;
};
struct transform {
    int left,top,right,bottom,xx,xy,yx,yy,originx,originy;
};
static DS_HOT void aligned(const texture& source,const transform& t,int flip,const unsigned* values,const unsigned char* table) {
    if (!flip && t.xx==65536 && t.yy==65536) {
        const int first=(t.originx+t.left*65536)>>16;
        const int columns=t.right-t.left;
        const unsigned mask=source.bits==3?0xe0e0e0e0u:0xf8f8f8f8u;
        const int firstrow=(t.originy+t.top*65536)>>16;
        if (first>=0 && first+columns<=source.width && firstrow>=0 && firstrow+t.bottom-t.top<=source.height) {
            for (int y=t.top;y<t.bottom;++y) {
                const int row=(t.originy+y*65536)>>16;
                const auto* pixel=source.data+(source.top+row)*source.stride+source.left+first;
                auto* target=frontend::workspace()+(mirrored?191-y:y)*256+t.left;
                for (int x=0;x<columns;) {
                    // Rings and character cutouts contain mostly transparent runs.
                    // Only aligned words may be loaded on the ARM9.
                    if (x+4<=columns && !(reinterpret_cast<std::uintptr_t>(pixel)&3)) {
                        std::uint32_t word;
                        std::memcpy(&word,__builtin_assume_aligned(pixel,4),4);
                        if (!(word&mask)) { pixel+=4; target+=4; x+=4; continue; }
                    }
                    const unsigned raw=*pixel++;
                    if (table) *target=table[(raw<<8)|*target];
                    else if (raw>>(8-source.bits)) {
                        const unsigned value=values[raw],opacity=(value>>16)&31;
                        if (opacity==31) *target=value>>24;
                        else if (opacity) *target=lookup[blend(value&0x7fff,palette[*target],opacity)];
                    }
                    ++target; ++x;
                }
            }
            return;
        }
    }
    int columns[256];
    for (int x=t.left;x<t.right;++x) {
        int column=(t.originx+x*t.xx)>>16;
        columns[x]=column<0 || column>=source.width ? -1 : source.left+((flip&1)?source.width-1-column:column);
    }
    auto* frame=frontend::workspace();
    for (int y=t.top;y<t.bottom;++y) {
        int row=(t.originy+y*t.yy)>>16;
        if (row<0 || row>=source.height) continue;
        if (flip&2) row=source.height-1-row;
        const auto* pixels=source.data+(source.top+row)*source.stride;
        auto* target=frame+(mirrored?191-y:y)*256;
        if (table) {
            for (int x=t.left;x<t.right;++x) if (columns[x]>=0)
                target[x]=table[(pixels[columns[x]]<<8)|target[x]];
        } else {
            for (int x=t.left;x<t.right;++x) {
                if (columns[x]<0) continue;
                const unsigned pixel=values[pixels[columns[x]]];
                const unsigned opacity=(pixel>>16)&31;
                if (opacity==31) target[x]=pixel>>24;
                else if (opacity) target[x]=lookup[blend(pixel&0x7fff,palette[target[x]],opacity)];
            }
        }
    }
}

static const unsigned char* blendtable(const std::uint16_t* colors,int bits,int alpha,unsigned color,int id,int slot=0) {
    if (!slot) starcachevalid=false;
    struct key { unsigned stamp=~0u, ink=0; int profile=-1,page=-1,light=-1,opacity=-1; };
    static key keys[2];
    auto& key=keys[slot];
    auto* table=frontend::workspace()+65536*(slot+1);
    if (!blendvalid[slot] || key.profile!=paletteid || key.stamp!=frontend::workgeneration(65536) || key.page!=id || key.light!=brightness || key.ink!=color || key.opacity!=alpha) {
        if (!slot) hudvalid=false;
        const unsigned mask=(1u<<(8-bits))-1, maximum=(1u<<bits)-1;
        for (unsigned pixel=0;pixel<256;++pixel) {
            auto* row=table+(pixel<<8);
            if ((color&0x8000) && (pixel&mask)) {
                std::memcpy(row,table+((pixel&~mask)<<8),256);
                continue;
            }
            const unsigned rgb=tint(colors[pixel&mask],color);
            const unsigned amount=((pixel>>(8-bits))*alpha+maximum/2)/maximum;
            if (amount==31) { std::memset(row,lookup[rgb],256); continue; }
            for (unsigned destination=0;destination<256;++destination)
                row[destination]=amount?lookup[blend(rgb,palette[destination],amount)]:destination;
        }
        key={frontend::workgeneration(65536),color,paletteid,id,brightness,alpha};
        blendvalid[slot]=true;
    }
    return table;
}
static bool placement(int width,int height,int ox,int oy,int x,int y,float sx,float sy,int angle,clip bounds,transform& t) {
    DS_SCOPE(upperplace);
    if (sx<=.001f || sy<=.001f) return false;
    const int offsetx=std::lround(ox*sx), offsety=std::lround(oy*sy);
    if (!angle) {
        t.left=std::max({0,bounds.left,x+offsetx});
        t.top=std::max({0,bounds.top,y+offsety});
        t.right=std::min({256,bounds.right,x+offsetx+static_cast<int>(std::ceil(width*sx))});
        t.bottom=std::min({192,bounds.bottom,y+offsety+static_cast<int>(std::ceil(height*sy))});
        if (t.left>=t.right || t.top>=t.bottom) return false;
        t.xx=std::lround(65536/sx); t.yy=std::lround(65536/sy); t.xy=t.yx=0;
        t.originx=(-x-offsetx)*t.xx+t.xx/2;
        t.originy=(-y-offsety)*t.yy+t.yy/2;
        return true;
    }
    const int radius=static_cast<int>(std::ceil(std::max(std::abs(ox),std::abs(ox+width))*sx+
        std::max(std::abs(oy),std::abs(oy+height))*sy))+2;
    if (x+radius<std::max(0,bounds.left) || x-radius>=std::min(256,bounds.right) ||
        y+radius<std::max(0,bounds.top) || y-radius>=std::min(192,bounds.bottom)) return false;
    const float radians=angle*(6.28318530718f/32768);
    const float cosine=std::cos(radians), sine=std::sin(radians);
    float left=1e9f,top=1e9f,right=-1e9f,bottom=-1e9f;
    for (int i=0;i<4;++i) {
        const float a=offsetx+(i&1 ? width*sx : 0), b=offsety+(i&2 ? height*sy : 0);
        const float px=x+a*cosine-b*sine, py=y+a*sine+b*cosine;
        left=std::min(left,px); top=std::min(top,py); right=std::max(right,px); bottom=std::max(bottom,py);
    }
    t.left=std::max({0,bounds.left,static_cast<int>(std::floor(left))});
    t.top=std::max({0,bounds.top,static_cast<int>(std::floor(top))});
    t.right=std::min({256,bounds.right,static_cast<int>(std::ceil(right))});
    t.bottom=std::min({192,bounds.bottom,static_cast<int>(std::ceil(bottom))});
    if (t.left>=t.right || t.top>=t.bottom) return false;
    t.xx=std::lround(cosine/sx*65536); t.xy=std::lround(sine/sx*65536);
    t.yx=std::lround(-sine/sy*65536); t.yy=std::lround(cosine/sy*65536);
    t.originx=std::lround((-x*cosine-y*sine-offsetx)/sx*65536)+(t.xx+t.xy)/2;
    t.originy=std::lround((x*sine-y*cosine-offsety)/sy*65536)+(t.yx+t.yy)/2;
    return true;
}

static DS_HOT void blit(const texture& source,const transform& t,int flip,int alpha,unsigned color,const unsigned char* table=nullptr) {
    DS_SCOPE(upperblit);
    if (table && !source.direct && !t.xy && !t.yx && !photograph) {
        aligned(source,t,flip,nullptr,table);
        return;
    }
    struct colorset {
        unsigned values[256]{},ink=0,stamp=0;
        std::uint16_t palette[32]{};
        int profile=-1,bits=0,alpha=-1,light=-1;
    };
    static colorset sets[8];
    static unsigned stamp=0;
    unsigned* values=nullptr;
    if (!source.direct) {
        const unsigned bits=8-source.bits, mask=(1u<<bits)-1;
        colorset* selected=nullptr;
        for (auto& entry:sets) if (entry.profile==paletteid && entry.bits==source.bits && entry.alpha==alpha &&
            entry.light==brightness && entry.ink==color && !std::memcmp(entry.palette,source.palette,(mask+1)*2)) {
            selected=&entry; break;
        }
        if (!selected) {
        selected=&sets[0];
        for (auto& entry:sets) if (entry.stamp<selected->stamp) selected=&entry;
        selected->profile=paletteid; selected->bits=source.bits; selected->alpha=alpha; selected->light=brightness; selected->ink=color;
        std::memcpy(selected->palette,source.palette,(mask+1)*2);
        values=selected->values;
        unsigned pigments[32];
        for (unsigned i=0;i<=mask;++i) {
            const unsigned rgb=tint(source.palette[i],color);
            pigments[i]=rgb|(static_cast<unsigned>(lookup[rgb])<<24);
        }
        for (int i=0;i<256;++i) {
            const unsigned opacity=source.bits==3?((i>>5)*alpha+3)/7:((i>>3)*alpha+15)/31;
            values[i]=pigments[i&mask]|(opacity<<16);
        }
        }
        selected->stamp=++stamp; values=selected->values;
    }
    if (!source.direct && !t.xy && !t.yx && !photograph) {
        aligned(source,t,flip,values,table);
        return;
    }
    auto* frame=frontend::workspace();
    for (int y=t.top;y<t.bottom;++y) {
        int u=t.originx+t.left*t.xx+y*t.xy, v=t.originy+t.left*t.yx+y*t.yy;
        auto* destination=frame+(mirrored?191-y:y)*256+t.left;
        for (int x=t.left;x<t.right;++x,++destination,u+=t.xx,v+=t.yx) {
            if (photograph && x>=upperart::photospans[y][0] && x<upperart::photospans[y][1]) continue;
            int px=u>>16, py=v>>16;
            if (px<0 || py<0 || px>=source.width || py>=source.height) continue;
            if (flip&1) px=source.width-1-px;
            if (flip&2) py=source.height-1-py;
            const int index=(source.top+py)*source.stride+source.left+px;
            unsigned rgb, opacity, opaque;
            if (source.direct) {
                const unsigned pixel=reinterpret_cast<const std::uint16_t*>(source.data)[index];
                if (!(pixel&0x8000)) continue;
                rgb=brightness==31 && color==0x7fff ? pixel&0x7fff : tint(pixel&0x7fff,color);
                opacity=alpha; opaque=lookup[rgb];
            } else {
                const unsigned pixel=values[source.data[index]];
                opacity=(pixel>>16)&31;
                if (!opacity) continue;
                rgb=pixel&0x7fff; opaque=pixel>>24;
            }
            *destination=opacity==31 ? opaque : lookup[blend(rgb,palette[*destination],opacity)];
        }
    }
}

static DS_HOT void shadowpixels(const unsigned char* source,const unsigned char* table,const transform& t) {
    auto* frame=frontend::workspace();
    for (int y=t.top;y<t.bottom;++y) {
        const int left=upperart::photospans[y][0], right=upperart::photospans[y][1];
        for (int part=0;part<2;++part) {
            const int first=part?std::max(t.left,right):t.left;
            const int last=part?t.right:std::min(t.right,left);
            int u=t.originx+first*t.xx+y*t.xy, v=t.originy+first*t.yx+y*t.yy;
            auto* pixel=frame+y*256+first;
            for (int x=first;x<last;++x,++pixel,u+=t.xx,v+=t.yx)
                *pixel=table[(source[((v>>8)&0xff00)|(u>>16)]<<8)|*pixel];
        }
    }
}

static bool shadow(const unsigned char* source,const std::uint16_t* colors,const transform& t,int id) {
    for (int i=0;i<4;++i) {
        const int x=i&1?t.right-1:t.left, y=i&2?t.bottom-1:t.top;
        const int u=t.originx+x*t.xx+y*t.xy, v=t.originy+x*t.yx+y*t.yy;
        if (u<0 || v<0 || u>=(256<<16) || v>=(256<<16)) return false;
    }
    const auto* table=blendtable(colors,5,31,0x7fff,id);
    shadowpixels(source,table,t);
    return true;
}

void sprite(int id,int x,int y,float scale,float vertical,int angle,int flip,int alpha,unsigned color,clip bounds) {
    if (id<0 || alpha<=0) return;
    const auto& source=menuart::sprites[id];
    transform t;
    if (!placement(source.w,source.h,source.ox,source.oy,x,y,scale,vertical,angle,bounds,t)) return;
    starcovered|=overstars(t.left,t.top,t.right,t.bottom);
    const auto& page=menuart::pages[source.page];
    auto* cached=load(source.page,page.width*page.height*(page.direct?2:1));
    if (!cached) return;
    if (id==menuart::shadow && photograph && brightness==31 && !flip && alpha==31 && color==0x7fff &&
        shadow(frontend::workspace()+cachestart+cached->start,cached->colors,t,source.page)) return;
    const bool hud=id>=menuart::hud1 && id<=menuart::hud1+10;
    const auto* table=(id==menuart::doorshade || hud)?blendtable(cached->colors,page.alphabits,alpha,color,source.page,id==menuart::doorshade?1:0):nullptr;
    blit({frontend::workspace()+cachestart+cached->start,cached->colors,page.width,source.x,source.y,
          source.w,source.h,source.ox,source.oy,page.alphabits,static_cast<bool>(page.direct)},t,flip,alpha,color,table);
}
void immediate(int id,int x,int y,int alpha,float scale) {
    if (alpha<=0) return;
    const auto& source=art::sprites[id];
    transform t;
    if (!placement(source.w,source.h,source.ox,source.oy,x,y,scale,scale,0,{},t)) return;
    starcovered|=overstars(t.left,t.top,t.right,t.bottom);
    const auto& page=art::textures[source.page];
    blit({page.pixels,reinterpret_cast<const std::uint16_t*>(page.palette),page.width,source.x,source.y,
          source.w,source.h,source.ox,source.oy,3,false},t,0,alpha,0x7fff);
}
void DS_HOT hud(int id,int x,int y) {
    auto* cached=load(menuart::pagecount+1+paletteid,upperart::hudbytes);
    if (!cached) return;
    const auto& glyph=upperart::hud[id];
    static int profile=-1;
    static unsigned stamp=~0u;
    static_assert(upperart::hudtablebytes<=65536-8192);
    auto* table=frontend::workspace()+65536+8192;
    if (!hudvalid || profile!=paletteid || stamp!=frontend::workgeneration(65536)) {
        if (!read(hudfile,paletteid*(upperart::hudbytes+upperart::hudtablebytes)+upperart::hudbytes,table,upperart::hudtablebytes)) return;
        profile=paletteid; stamp=frontend::workgeneration(65536); hudvalid=true; blendvalid[0]=false;
    }
    const auto* source=frontend::workspace()+cachestart+cached->start+glyph.offset;
    x+=glyph.ox; y+=glyph.oy;
    for (int row=std::max(0,-y);row<std::min(glyph.height,192-y);++row) {
        auto* target=frontend::workspace()+(y+row)*256;
        const auto* line=source+row*glyph.width;
        for (int column=std::max(0,-x);column<std::min(glyph.width,256-x);++column) {
            const unsigned pixel=line[column];
            if (pixel) target[x+column]=table[(pixel<<8)|target[x+column]];
        }
    }
}
void stars(const int* frames) {
    static int previous[3]={-1,-1,-1}, background=-1, top=-1;
    static unsigned stamp=~0u;
    constexpr int left=starbounds.left, first=starbounds.top, width=starbounds.right-left, height=starbounds.bottom-first;
    auto* cache=frontend::workspace()+65536;
    const bool same=starcachevalid && !starcovered && background==backgroundid && top==scrolltop &&
        stamp==frontend::workgeneration(65536) && std::equal(frames,frames+3,previous);
    if (same) {
        for (int row=0;row<height;++row)
            std::memcpy(frontend::workspace()+(first+row)*256+left,cache+row*width,width);
        return;
    }
    for (int i=0;i<3;++i) hud(frames[i],80+i*48,82);
    if (starcovered) return;
    // An unobstructed star region has the same authored backdrop every frame.
    // Cache their already-composited pixels; never cache across visible world
    // objects in that region, camera moves, pickups or overwritten uploads.
    for (int row=0;row<height;++row)
        std::memcpy(cache+row*width,frontend::workspace()+(first+row)*256+left,width);
    std::copy(frames,frames+3,previous);
    background=backgroundid; top=scrolltop; stamp=frontend::workgeneration(65536);
    starcachevalid=true;
    blendvalid[0]=false;
}
void photo() {
    auto* cached=load(menuart::pagecount,upperart::photowidth*upperart::photoheight*2);
    if (!cached) return;
    transform t;
    placement(upperart::photowidth,upperart::photoheight,-upperart::photowidth/2,-upperart::photoheight/2,128,96,1,1,0,{},t);
    blit({frontend::workspace()+cachestart+cached->start,nullptr,upperart::photowidth,0,0,
          upperart::photowidth,upperart::photoheight,0,0,0,true},t,0,31,0x7fff);
}
void rect(clip bounds,unsigned color,int alpha) {
    if (alpha<=0) return;
    starcovered|=overstars(bounds.left,bounds.top,bounds.right,bounds.bottom);
    unsigned char table[256];
    color=tint(color,0x7fff);
    for (int i=0;i<256;++i) table[i]=lookup[alpha==31?color:blend(color,palette[i],alpha)];
    for (int y=std::max(0,bounds.top);y<std::min(192,bounds.bottom);++y) {
        auto* line=frontend::workspace()+y*256;
        for (int x=std::max(0,bounds.left);x<std::min(256,bounds.right);++x) line[x]=table[line[x]];
    }
}
void line(int x,int y,int endx,int endy,unsigned color,int alpha) {
    if ((y<0 && endy<0) || (y>=192 && endy>=192) || (x<0 && endx<0) || (x>=256 && endx>=256) || alpha<=0) return;
    starcovered|=overstars(std::min(x,endx),std::min(y,endy),std::max(x,endx)+1,std::max(y,endy)+1);
    color=tint(color,0x7fff);
    const int dx=std::abs(endx-x), sx=x<endx?1:-1, dy=-std::abs(endy-y), sy=y<endy?1:-1;
    int delta=dx+dy;
    for (int limit=0;limit<4096;++limit) {
        if (x>=0 && x<256 && y>=0 && y<192) {
            auto& pixel=frontend::workspace()[y*256+x];
            pixel=lookup[alpha==31?color:blend(color,palette[pixel],alpha)];
        }
        if (x==endx && y==endy) break;
        const int twice=delta*2;
        if (twice>=dy) { delta+=dy; x+=sx; }
        if (twice<=dx) { delta+=dx; y+=sy; }
    }
}
void finish() {
#ifdef __NDS__
    DC_FlushRange(frontend::workspace(),256*192);
    if (palettechanged) DC_FlushRange(palette,sizeof(palette));
    const int lock=enterCriticalSection();
    frontend::submit();
    pending=true;
    leaveCriticalSection(lock);
#else
    frontend::submit();
    ++completed;
#endif
}
void acquire() {
#ifdef __NDS__
    DS_SCOPE(wait);
    const unsigned waiting=gamelog::now();
    while (pending) { gamelog::checkwait(waiting); swiWaitForVBlank(); }
#endif
}
void vblank() {
#ifdef __NDS__
    if (!pending) return;
    dmaCopyWords(3,frontend::workspace(),BG_GFX_SUB,256*192);
    if (palettechanged) dmaCopyWords(3,palette,BG_PALETTE_SUB,sizeof(palette));
    palettechanged=false;
    pending=false;
    ++completed;
#endif
}
}
