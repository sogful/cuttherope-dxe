#include "../source/frontend.cpp"
#include "level.hpp"
#include <cassert>
namespace trace { system trail; }
int main(int argc, char** argv) {
    assert(argc==2 || argc==3);
    ui::controller menu;
    dx::simulation game;
    unsigned peak=0, cases=0, failed=0;
    bool peakpages[menuart::pagecount]{};
    int peaklevel=0, peakskin=0, peakage=0, peaklocale=0, peakphase=0;
    std::fill(std::begin(frontend::textures),std::end(frontend::textures),1);
    
    constexpr unsigned reserved = 144384;

    frontend::reserve(reserved);
    game.reset(dx::levels[0]);
    for (int mode = 0; mode < 3; ++mode) for (int door = 0; door < 3; ++door) {
        menu.mode = mode == 0 ? ui::view::playing : mode == 1 ? ui::view::paused : ui::view::results;
        menu.door = door; menu.doorframe = menu.age = 12; menu.replaypanel = true;
        frontend::preparegame(menu,game,0); frontend::prepareoverlay(menu,game);
        int hud = 0;
        for (int i = frontend::overlaystart; i < frontend::count; ++i) {
            const int sprite = frontend::commands[i].id;
            hud += sprite == menuart::hud0 || sprite == menuart::hud0 + menuart::hudquads[menu.locale];
        }
        assert(hud == 2);
    }
    std::puts("PASS: HUD retained through opening, replay, quit and result closing flaps");
    for(int locale=0; argc==2 && locale<12; ++locale) for(int level=0; level<static_cast<int>(dx::levels.size()); ++level) {
        menu.locale=locale;
        game.reset(dx::levels[level]); game.state=dx::outcome::won;
        game.resulttick=200; game.resultvisual=200; game.ticks=200;
        game.count=3; game.stars={true,true,true};
        menu.pack=level/25; menu.level=level%25; menu.resultstars=3;
        menu.score=5680; menu.elapsed=200; menu.improved=true;
        for(int skin=0; skin<16; ++skin) for(int phase=0; phase<4; ++phase) for(int mask=0; mask<8; ++mask) for(int age=0; age<320; age+=4) {
            if(phase>=2 && mask) break;
            if(age>=32 && (level%25 || phase)) break;
            if(age>=32 && mask!=7) break;
            game.count=0;
            for(int i=0;i<3;++i) { game.stars[i]=(mask & (1<<i))!=0; game.count+=game.stars[i]; }
            menu.resultstars=phase>=2 ? 3 : game.count;
            menu.skins[2]=skin; menu.mode=phase==1 ? ui::view::paused : phase>=2 ? ui::view::playing : ui::view::results;
            menu.door=phase>=2 ? 1 : 0; menu.doorframe=age; menu.replaypanel=phase>=2; menu.age=age;
            menu.resulttime=phase==3 ? 320 : 90;
            game.state=phase>=2 ? dx::outcome::playing : dx::outcome::won;
            game.visuals=game.resultvisual+125+age;
            try {
                if(age<32) { frontend::preparegame(menu,game,game.visuals); frontend::prepareoverlay(menu,game); }
                else frontend::drawresult(menu,game);
            } catch(const std::runtime_error&) { ++failed; }
            bool needed[menuart::pagecount]{};
            unsigned size=reserved;
            for(int i=0; i<frontend::count; ++i) {
                const int id=frontend::commands[i].id;
                if(id<0 || !frontend::visible(frontend::commands[i])) continue;
                const int page=menuart::sprites[id].page;
                if(!needed[page]) size+=frontend::bytes(page);
                needed[page]=true;
            }
            if(size>peak) { peak=size; peaklevel=level; peakskin=skin; peakage=age; peaklocale=locale; peakphase=phase; std::copy(std::begin(needed),std::end(needed),peakpages); }
            ++cases;
        }
    }
    for (int level=250; level<static_cast<int>(dx::levels.size()); ++level) {
        const auto& data=dx::levels[level];
        int combinations=1;
        for (int i=0; i<data.ghostcount; ++i) combinations*=3;
        if (data.disccount) combinations=data.disccount*4;
        if (data.tubecount || data.lanterncount) combinations=std::max(combinations,36);
        for (int combination=0; combination<combinations; ++combination) {
            game.reset(data); game.introduction=false;
            for (int i=0; i<data.tubecount; ++i) {
                game.valvetap(i); game.valvetap(i);
                if (combination%3==0) game.valvetap(i);
            }
            game.steamtime=.016f*(combination+2);
            for (int i=0; i<data.lanterncount; ++i) {
                game.lanterns[i].state=1;
                game.lanterns[i].phase=combination%2+1;
                game.lanterns[i].age=combination*.016f;
            }
            for (int i=0, value=combination; i<data.ghostcount; ++i,value/=3) {
                const int form=2<<(value%3);
                for (int old : {2,4,8}) if (old!=form && (data.ghosts[i].forms&old)) { game.ghostform(i,old); break; }
                if (data.ghosts[i].forms&form) game.ghostform(i,form);
                game.ghosts[i].age=.06f;
            }
            for (auto& app : game.apparitions) if (app.form) { app.age=.24f; if (app.retirement>=0) app.retirement=.08f; }
            if (data.disccount) {
                game.pressdisc(game.dischandle(combination%data.disccount,true));
                for (int i=0; i<game.disclayers; ++i) { game.discorder[i].fade=.2f; game.discorder[i].angle=(combination/data.disccount)*45; }
            }
            menu.pack=level/25; menu.level=level%25;
            for (int skin=0; skin<16; ++skin) for (int phase=0; phase<3; ++phase) for (int camera=0; camera<3; ++camera) {
                menu.skins[2]=skin; menu.locale=skin%12;
                menu.mode=phase==0?ui::view::playing:phase==1?ui::view::paused:ui::view::results;
                menu.door=0; menu.age=4; game.visuals=80; game.cameray=camera*(data.height-1440)/2;
                try { frontend::preparegame(menu,game,80); frontend::prepareoverlay(menu,game); }
                catch (const std::runtime_error&) { ++failed; }
                bool needed[menuart::pagecount]{}; unsigned size=reserved;
                for (int i=0; i<frontend::count; ++i) {
                    const auto& command=frontend::commands[i];
                    if(command.id<0 || !frontend::visible(command)) continue;
                    const int page=menuart::sprites[command.id].page;
                    if(!needed[page]) size+=frontend::bytes(page);
                    needed[page]=true;
                }
                if(size>peak) { peak=size; peaklevel=level; peakskin=skin; peakage=combination; peaklocale=menu.locale; peakphase=phase; std::copy(std::begin(needed),std::end(needed),peakpages); }
                ++cases;
            }
        }
    }
    std::printf("Working sets: %u cases, peak %u / 393216 bytes at %d-%d costume %d age %d locale %d phase %d; %u failures\n",cases,peak,peaklevel/25+1,peaklevel%25+1,peakskin,peakage,peaklocale,peakphase,failed);
    assert(!frontend::renderfault);
    if(failed) for(int i=0;i<menuart::pagecount;++i) if(peakpages[i]) std::printf("Page %d: %u bytes\n",i,frontend::bytes(i));
    frontend::reset(); frontend::reserve(reserved);
    frontend::catalog=std::fopen(argv[1],"rb"); assert(frontend::catalog);
    const int resets=textureresets;
    failedallocations=1;
    frontend::upload();
    assert(frontend::cacherepacks()==1 && textureresets==resets && frontend::reserved==reserved && gCurrentTexture==-1);
    std::fclose(frontend::catalog);
    std::puts("PASS: forced fragmented allocation recovers without resetting gameplay texture handles");
    return failed ? 1 : 0;
}
