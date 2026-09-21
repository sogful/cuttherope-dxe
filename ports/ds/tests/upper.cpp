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
    }
    for (int box=0;box<17;++box) {
        const int background=upperart::worlds[box][0];
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
    assert(!upper::fault());
    std::puts("PASS: 425 upper-camera command maps, all background windows, clipped sprites, photo occlusion, HUD, shared-cache invalidation and decoded page reuse");
}
