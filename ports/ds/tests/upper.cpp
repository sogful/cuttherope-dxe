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
    assert(argc==2 || argc==3);
    upper::initialize(argv[1]);
    if (argc==3) {
        FILE* file=std::fopen(argv[2],"rb"); assert(file);
        std::vector<std::uint16_t> original(upperart::hudbytes);
        for (int scene=0;scene<20;++scene) {
            assert(std::fread(original.data(),2,original.size(),file)==original.size());
            for (int id=0;id<21;++id) for (int left : {-10,128,260}) {
                upper::begin(scene);
                for (int i=0;i<256*192;++i) frontend::workspace()[i]=(i*71+i/256*13)&255;
                std::vector<unsigned char> expected(upper::pixels(),upper::pixels()+256*192);
                const auto& glyph=upperart::hud[id];
                const int x=left+glyph.ox,y=96+glyph.oy;
                for (int row=0;row<glyph.height;++row) for (int column=0;column<glyph.width;++column) {
                    const int px=x+column,py=y+row;
                    if (px<0 || px>=256 || py<0 || py>=192) continue;
                    const unsigned pixel=original[glyph.offset+row*glyph.width+column],alpha=pixel>>8;
                    auto& target=expected[py*256+px];
                    if (alpha==31) target=pixel;
                    else if (alpha) target=upper::lookup[upper::blend(upper::palette[pixel&255],upper::palette[target],alpha)];
                }
                upper::hud(id,left,96);
                assert(std::equal(expected.begin(),expected.end(),upper::pixels()));
            }
        }
        std::fclose(file);
        std::puts("PASS: all 21 native HUD glyphs / 20 palettes / clipped positions match retained RGBA compositing exactly");
    }
    ui::controller menu;
    dx::simulation game;
    game.reset(dx::levels[0]);
    const int submitted=submittedframes;
    frontend::present(true);
    assert(submittedframes==submitted);
    upper::finish();
    assert(submittedframes==submitted+1);
    upper::finish();
    assert(submittedframes==submitted+1);
    frontend::present();
    assert(submittedframes==submitted+2);
    static_assert(GL_FLIP_NONE==1 && GL_FLIP_H==4 && GL_FLIP_V==2,"Match the real DS gl2d flags");
    for (int angle : {0,4096}) for (int flip=0;flip<4;++flip) {
        const int sdkflags=flip?((flip&1?GL_FLIP_H:0)|(flip&2?GL_FLIP_V:0)):GL_FLIP_NONE;
        upper::begin(upperart::worlds[16][0]);
        upper::sprite(menuart::boxcover17x0,128,96,.5f,.5f,angle,flip);
        const unsigned expected=hash();
        upper::begin(upperart::worlds[16][0]);
        frontend::count=0;
        frontend::add(menuart::boxcover17x0,128,96,{},sdkflags,.5f,angle);
        frontend::paintupper();
        assert(hash()==expected);
    }
    int previousalpha=31;
    for (int y=0;y>=-500;--y) {
        const int alpha=gamevisuals::candyalpha({1280,static_cast<float>(y)});
        assert(alpha>=0 && alpha<=previousalpha);
        if (y>=-200) assert(alpha==31);
        if (y<=-400) assert(alpha==0);
        previousalpha=alpha;
    }
    for (int candy : {0,1,51}) for (int y : {-100,-300,-400,-450}) {
        menu.skins[0]=candy;
        game.bodies[0].pos={1280,static_cast<float>(y)};
        frontend::preparegame(menu,game,0);
        bool found=false;
        for (int i=0;i<frontend::count;++i) for (int id : menuart::gamecandies[candy])
            if (frontend::commands[i].id==id) {
                found=true;
                assert(y>-400 && frontend::commands[i].alpha==gamevisuals::candyalpha(game.candy().pos));
            }
        assert(found==(candy>0 && y>-400));
    }
    for (int candy : {0,1,51}) {
        game.reset(dx::levels[100]); menu.skins[0]=candy;
        assert(game.split);
        game.bodies[1].pos={1100,-300}; game.bodies[2].pos={1400,-450};
        frontend::preparegame(menu,game,0);
        bool found=false;
        for (int i=frontend::starfront;i<frontend::count;++i) {
            const auto& command=frontend::commands[i];
            if (command.id==menuart::gamehalves[candy][0]) { assert(command.alpha==16); found=true; }
            assert(command.id!=menuart::gamehalves[candy][1]);
        }
        assert(found);
    }
    for (bool split : {false,true}) for (int y : {-100,-300,-400,-450}) {
        game.reset(dx::levels[split?100:0]);
        for (int part=0;part<game.activecount();++part) {
            const int id=game.activeid(part);
            game.bodies[id].pos={1280,static_cast<float>(y)};
            game.bubbleindex(id)=0;
        }
        game.popage=0; game.popposition={1280,static_cast<float>(y)};
        frontend::preparegame(menu,game,0);
        int bubbles=0, pops=0;
        for (int i=0;i<frontend::count;++i) {
            const auto& command=frontend::commands[i];
            if (command.id==menuart::bubble4 || command.id==menuart::bubble18) {
                assert(command.alpha==gamevisuals::candyalpha(game.popposition));
                bubbles+=command.id==menuart::bubble4;
                pops+=command.id==menuart::bubble18;
            }
        }
        assert(bubbles==(y>-400?game.activecount():0) && pops==(y>-400?1:0));
    }
    for (int y : {-300,-450}) {
        game.reset(dx::levels[0]); game.bubble=0;
        game.definition.ghostcount=1; game.definition.bubblecount=1;
        game.bubblesused[0]=true;
        game.ghosts[0].form=2; game.ghosts[0].idleage=1;
        game.apparitions[0]={0,2,0,1,-1,0};
        game.bodies[0].pos={1280,static_cast<float>(y)};
        frontend::preparegame(menu,game,0);
        int clouds=0;
        for (int i=0;i<frontend::count;++i) {
            const auto& command=frontend::commands[i];
            if (command.id>=menuart::ghost2 && command.id<=menuart::ghost6) {
                ++clouds; assert(command.alpha==gamevisuals::candyalpha(game.candy().pos));
            }
        }
        assert(clouds==(y>-400?5:0));
    }
    game.reset(dx::levels[375]); game.bulbbubble=0; game.bodies[3].pos={1280,-300};
    frontend::preparegame(menu,game,0);
    bool bulbbubble=false;
    for (int i=0;i<frontend::count;++i) if (frontend::commands[i].id==menuart::bubble4) {
        assert(frontend::commands[i].alpha==31); bulbbubble=true;
    }
    assert(bulbbubble);
    menu={}; game.reset(dx::levels[0]);
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
    for (int id=0;id<20;++id) {
        upper::begin(upperart::worlds[0][0]);
        assert(upper::menu(id,0));
        const unsigned visible=hash();
        for (unsigned frame=1;frame<5;++frame) {
            assert(!upper::menu(id,frame));
            assert(hash()==visible);
        }
        if (id!=2) {
            assert(upper::menu(id,5));
            const unsigned finished=hash();
            upper::begin(upperart::worlds[0][0]);
            assert(upper::menu(id,5) && hash()==finished);
        }
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
    auto rejected=[](unsigned bytes,unsigned code) {
        bool failed=false;
        try { failed=!upper::advancepatch(bytes); }
        catch (const std::runtime_error& message) { failed=std::strcmp(message.what(),"CTRD DS: upper-screen asset error")==0; }
        return failed && upper::fault()==code;
    };
    // Malformed in-memory patches must stop before changing the frame.
    for (const std::vector<unsigned char>& patch : {std::vector<unsigned char>{0,0xc0,1,0,1}, {0,0,10,0,1}, {0,0xc0,0,0}}) {
        const unsigned before=hash();
        upper::error=0; upper::movie={};
        upper::movie.frame=1;
        upper::movie.bytes=upper::movie.fetched=upper::movie.available=patch.size();
        std::copy(patch.begin(),patch.end(),upper::input);
        assert(rejected(patch.size(),8) && hash()==before);
    }
    const unsigned before=hash();
    upper::error=0; upper::movie={};
    upper::movie.bytes=upper::movie.fetched=upper::movie.available=1;
    upper::input[0]=0;
    assert(rejected(1,7) && hash()==before);
    std::puts("PASS: malformed shadow ranges and truncated headers stop without framebuffer writes");
}
