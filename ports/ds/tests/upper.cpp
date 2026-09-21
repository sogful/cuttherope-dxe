#include "../source/frontend.cpp"
#include "../source/upper.cpp"
#include "upperassets.hpp"
#include "level.hpp"
#include <cassert>
#include <cstring>
#include <vector>
namespace trace { system trail; }

static unsigned hash() {
    unsigned value=2166136261;
    for (int i=0;i<256*192;++i) value=(value^upper::pixels()[i])*16777619;
    return value;
}
static void reference(int id,int x,int y,float zoom,unsigned ink=0x7fff) {
    const auto& source=menuart::sprites[id];
    const auto& page=menuart::pages[source.page];
    auto* cached=upper::load(source.page,page.width*page.height*(page.direct?2:1));
    upper::transform transform;
    assert(upper::placement(source.w,source.h,source.ox,source.oy,x,y,zoom,zoom,0,{},transform));
    upper::blit({frontend::workspace()+upper::cachestart+cached->start,cached->colors,page.width,
        source.x,source.y,source.w,source.h,source.ox,source.oy,page.alphabits,static_cast<bool>(page.direct)},transform,0,31,ink);
}
int main(int argc,char** argv) {
    assert(argc==2);
    upper::initialize(argv[1]);
    ui::controller menu;
    dx::simulation game;
    game.reset(dx::levels[0]);
    for (int box=0;box<17;++box) for (int sections=0;sections<3;++sections) {
        const int id=upperart::worlds[box][sections];
        for (int top : {0,1,15,16,64,96,192}) {
            upper::begin(id,top);
            const unsigned before=hash();
            std::vector<unsigned char> background(upper::pixels(),upper::pixels()+256*192);
            upper::shade(17);
            upper::sprite(menuart::body0,128,-1000);
            assert(hash()==before);
            upper::rect({-100,-100,0,0},0,31);
            assert(hash()==before);
            upper::line(-100,-20,300,-20,0,31);
            assert(hash()==before);
            upper::sprite(menuart::body0,128,96,1,1,2048);
            assert(hash()!=before);
            const unsigned cached=hash(), reads=upper::reads();
            upper::begin(id,top); upper::shade(17);
            upper::sprite(menuart::body0,128,96,1,1,2048);
            assert(hash()==cached && upper::reads()==reads);
            ++frontend::workversion;
            std::memset(frontend::workspace()+262144,0,163840);
            upper::begin(id,top); upper::shade(17);
            upper::sprite(menuart::body0,128,96,1,1,2048);
            assert(hash()==cached && upper::reads()>reads);
            upper::finish();
        }
    }
    for (int id : upperart::menus) {
        upper::begin(id);
        std::vector<unsigned char> original(upper::pixels(),upper::pixels()+256*192);
        for (int angle : {0,4096,16384,29000}) {
            upper::begin(id);
            upper::sprite(menuart::shadow,128,96,1.86f,1.86f,angle);
            std::vector<unsigned char> reference(upper::pixels(),upper::pixels()+256*192);
            upper::begin(id); upper::cutout(true);
            upper::sprite(menuart::shadow,128,96,1.86f,1.86f,angle);
            upper::cutout(false);
            const unsigned expected=hash();
            for (int y=0;y<192;++y) for (int x=0;x<256;++x) {
                const bool photograph=x>=upperart::photospans[y][0] && x<upperart::photospans[y][1];
                assert((photograph?original:reference)[y*256+x]==upper::pixels()[y*256+x]);
            }
            ++frontend::blendversion;
            std::memset(frontend::workspace()+65536,0,65536);
            upper::begin(id); upper::cutout(true);
            upper::sprite(menuart::shadow,128,96,1.86f,1.86f,angle);
            upper::cutout(false);
            assert(hash()==expected);
        }
    }
    // Sparse playback must preserve the photo and agree with the original
    // software compositor, including seeks, wraparound and scene changes.
    for (int id=0;id<20;++id) for (unsigned frame : {0u,5u,10u,295u,300u,307u,2050u,4495u,0u}) {
        upper::begin(upperart::worlds[0][0]); // force a seek with a stale index
        assert(upper::menu(id,frame));
        std::vector<unsigned char> actual(upper::pixels(),upper::pixels()+256*192);
        assert(!upper::menu(id,frame));
        upper::begin(upperart::worlds[0][0]);
        upper::begin(id); upper::cutout(true);
        if (id!=2) upper::sprite(menuart::shadow,128,96,(1781*2*(192.0f/1440))/256,(1781*2*(192.0f/1440))/256,
            4096+(frame/5*5%4500)*32768/4500);
        unsigned difference=0;
        for (int i=0;i<256*192;++i) difference+=actual[i]!=upper::pixels()[i];
        // Python double vs ARM/host float can round one 16.16 edge differently.
        assert(difference<32);
    }
    upper::begin(upperart::worlds[0][0]);
    for (unsigned frame=0;frame<9000;frame+=5) {
        assert(upper::menu(0,frame));
        if (frame%300==0) {
            const unsigned expected=hash();
            upper::begin(upperart::worlds[0][0]);
            assert(upper::menu(0,frame));
            assert(hash()==expected);
        }
    }
    for (int level=0;level<425;++level) {
        game.reset(dx::levels[level]); menu.pack=level/25; menu.level=level%25;
        frontend::preparegame(menu,game,0);
        const int count=frontend::count;
        auto lower=frontend::commands;
        frontend::preparegame(menu,game,0,true);
        assert(frontend::count==count);
        for (int i=0;i<count;++i) {
            const auto& a=lower[i]; const auto& b=frontend::commands[i];
            assert(a.id==b.id && a.x==b.x && a.scale==b.scale && a.vertical==b.vertical && a.angle==b.angle && a.alpha==b.alpha);
            if (a.id>=0) assert(std::abs(b.y-a.y-192)<=1);
        }
        frontend::commands=lower;
        frontend::count=frontend::overlaystart=count;
        frontend::add(menuart::hud0,240,10);
        frontend::upperworld();
        assert(frontend::count==count && frontend::overlaystart==-1);
        for (int i=0;i<count;++i) {
            const auto& a=lower[i]; const auto& b=frontend::commands[i];
            assert(a.id==b.id && a.x==b.x && a.scale==b.scale && a.vertical==b.vertical && a.angle==b.angle && a.alpha==b.alpha);
            assert(b.y==a.y+(a.id>=0?192:0));
        }
    }
    for (int box=0;box<17;++box) {
        const int background=upperart::worlds[box][0];
        for (int frame=0;frame<=10;++frame) {
            int frames[]={frame,(frame+3)%11,(frame+6)%11};
            for (int objects : {0,0,1,0,2,0}) {
                upper::begin(background);
                const upper::clip bounds=objects==1?upper::clip{70,60,130,100}:upper::clip{0,140,256,192};
                if (objects) upper::rect(bounds,0,31);
                for (int i=0;i<3;++i) upper::hud(frames[i],80+i*48,82);
                const unsigned expected=hash();
                upper::begin(background);
                if (objects) upper::rect(bounds,0,31);
                upper::stars(frames);
                assert(hash()==expected);
            }
            ++frontend::blendversion;
            std::memset(frontend::workspace()+65536,0,65536);
            upper::begin(background); upper::stars(frames);
            const unsigned expected=hash();
            upper::begin(background);
            for (int i=0;i<3;++i) upper::hud(frames[i],80+i*48,82);
            assert(hash()==expected);
        }
        for (int id : {menuart::body0,menuart::hud1,menuart::belt0}) for (int x : {-5,0,128,255}) {
            const auto& source=menuart::sprites[id];
            const auto& page=menuart::pages[source.page];
            upper::begin(background); upper::shade(17);
            upper::sprite(id,x,96);
            const unsigned fast=hash();
            upper::begin(background); upper::shade(17);
            auto* cached=upper::load(source.page,page.width*page.height);
            upper::transform t;
            if (upper::placement(source.w,source.h,source.ox,source.oy,x,96,1,1,0,{},t)) {
                // Less than 1/256 pixel of shear selects the scalar reference
                // raster without moving any native pixel-center samples.
                t.xy=1;
                upper::blit({frontend::workspace()+upper::cachestart+cached->start,cached->colors,page.width,
                    source.x,source.y,source.w,source.h,source.ox,source.oy,page.alphabits,false},t,0,31,0x7fff);
            }
            assert(hash()==fast);
        }
        for (int frame=0;frame<=10;++frame) {
            upper::begin(background); upper::transient(true);
            reference(menuart::hud1+frame,80,82,2.5f);
            const unsigned expected=hash();
            upper::begin(background);
            upper::sprite(menuart::hud1+frame,80,82,2.5f,2.5f);
            assert(hash()==expected);
        }
        for (unsigned ink : {0x8000u,0xffffu}) {
            const int digit=menuart::scoredigits[8].sprite;
            upper::begin(background); upper::transient(true);
            reference(digit,128,120,1.65f,ink);
            const unsigned expected=hash();
            upper::begin(background);
            upper::sprite(digit,128,120,1.65f,1.65f,0,0,31,ink);
            assert(hash()==expected);
            ++frontend::blendversion;
            ++frontend::lookupversion;
            std::memset(frontend::workspace()+65536,0,196608);
            upper::begin(background);
            upper::sprite(digit,128,120,1.65f,1.65f,0,0,31,ink);
            assert(hash()==expected);
        }
    }
    upper::begin(upperart::worlds[0][0]);
    menu={}; menu.mode=ui::view::playing;
    game.reset(dx::levels[0]);
    const unsigned blank=hash();
    frontend::upperoverlay(menu,game);
    assert(hash()!=blank);
    const unsigned empty=hash();
    upper::begin(upperart::worlds[0][0]);
    menu.starage[0]=60; game.count=1;
    frontend::upperoverlay(menu,game);
    assert(hash()!=empty);
    const unsigned playing=hash();
    menu.mode=ui::view::results; menu.age=0;
    upper::begin(upperart::worlds[0][0]);
    frontend::upperoverlay(menu,game);
    assert(hash()==playing);
    menu.age=32;
    upper::begin(upperart::worlds[0][0]);
    frontend::upperoverlay(menu,game);
    assert(hash()!=playing);
    for (int box=0;box<17;++box) for (int step=0;step<=32;++step) {
        upper::begin(upperart::worlds[box][0]);
        std::memset(frontend::workspace(),42,256*192);
        frontend::count=frontend::groundend=frontend::starback=frontend::starfront=0;
        frontend::doors(step/32.0f,false,false,box);
        frontend::paintupper(false,0);
        std::vector<unsigned char> original(upper::pixels(),upper::pixels()+256*192);
        std::memset(frontend::workspace(),42,256*192);
        upper::mirror(true); frontend::paintupper(false,0); upper::mirror(false);
        for (int y=0;y<192;++y) for (int x=0;x<256;++x)
            assert(upper::pixels()[y*256+x]==original[(191-y)*256+x]);
    }
    assert(!upper::fault());
    std::puts("PASS: 425 reused camera-command maps, all backgrounds, native blits/HUD, sparse shadow playback/seeks, photo occlusion, all 17 mirrored flap pairs and cache invalidation");
}
