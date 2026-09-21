#include "../source/frontend.cpp"
#include "level.hpp"
#include <cassert>
#include <vector>
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

    unsigned menupeak=0, menucases=0, menufailed=0;
    auto checkmenu=[&]() {
        try { frontend::draw(menu); }
        catch (const std::runtime_error&) { ++menufailed; }
        bool needed[menuart::pagecount]{};
        unsigned bytes=0;
        for (int i=0;i<frontend::count;++i) {
            const auto& command=frontend::commands[i];
            if (command.id<0 || !frontend::visible(command)) continue;
            const int page=menuart::sprites[command.id].page;
            if (!needed[page]) bytes+=frontend::bytes(page);
            needed[page]=true;
        }
        menupeak=std::max(menupeak,bytes); ++menucases;
    };
    for (int locale=0;locale<12;++locale) for (int unlocked=0;unlocked<3;++unlocked) {
        menu={}; menu.locale=locale; menu.saves.unlocked=unlocked;
        if (unlocked==2) for (auto& level : menu.saves.active().levels) level.stars=3;
        menu.mode=ui::view::packs;
        for (int position=0;position<=16*4;++position) for (int age : {0,15,100}) {
            menu.packposition=position/4.0f; menu.pack=std::lround(menu.packposition); menu.settled=age;
            for (int pressed : {-1,0,1}) { menu.pressed=pressed; checkmenu(); }
        }
        menu.pack=16; menu.packposition=16;
        for (int phase : {1,2}) for (int age : {0,1,10,18,19,25,38,60}) {
            menu.popup=phase; menu.popupage=age;
            for (int pressed : {-1,0}) { menu.pressed=pressed; checkmenu(); }
        }
        menu.popup=0;
        for (auto view : {ui::view::home,ui::view::options,ui::view::languages,ui::view::resetmenu,ui::view::levels}) {
            menu.mode=view;
            for (int pressed=-1;pressed<12;++pressed) { menu.pressed=pressed; checkmenu(); }
        }
        menu.mode=ui::view::credits;
        for (int offset=0;offset<menuart::creditheights[locale];offset+=32) { menu.creditoffset=offset; checkmenu(); }
        menu.mode=ui::view::skins;
        for (int tab=0;tab<4;++tab) {
            menu.skintab=tab;
            for (int selected=0;selected<menuart::skincounts[tab];++selected) {
                menu.skins[tab]=selected;
                menu.skinoffsets[tab]=std::min((selected/4)*menuart::skinrow,menuart::skinmax[tab]);
                for (int age : {0,9,30,60,90}) { menu.skinage=age; checkmenu(); }
            }
        }
    }
    std::printf("Frontend working sets: %u cases, peak %u / 393216 bytes; %u failures\n",menucases,menupeak,menufailed);
    assert(!menufailed && !frontend::renderfault);
    menu={};
    frontend::reserve(reserved);
    for (int locale=0;locale<12;++locale) {
        for (auto view : {ui::view::home,ui::view::languages,ui::view::resetmenu,ui::view::results,ui::view::skins}) {
            menu={}; menu.locale=locale; menu.mode=view;
            ui::button items[32]; const int count=menu.buttons(items);
            for (int i=0;i<count;++i) {
                const auto& item=items[i];
                // The unchanged source Back button has one pixel of offscreen touch padding.
                if (item.id!=ui::action::back) {
                    assert(item.x-item.width/2>=0 && item.x+(item.width+1)/2<=256);
                    assert(item.y-item.height/2>=0 && item.y+(item.height+1)/2<=192);
                }
                for (int j=0;j<i;++j) {
                    const auto& other=items[j];
                    assert(item.x+(item.width+1)/2<=other.x-other.width/2 || other.x+(other.width+1)/2<=item.x-item.width/2 ||
                           item.y+(item.height+1)/2<=other.y-other.height/2 || other.y+(other.height+1)/2<=item.y-item.height/2);
                }
            }
        }
        menu={}; menu.locale=locale; menu.mode=ui::view::packs; menu.pack=16; menu.settled=100;
        for (float position : {15.2f,15.5f,16.0f,16.5f}) {
            menu.packposition=position; frontend::count=0; frontend::packs(menu);
            for (int i=0;i<frontend::count;++i) {
                const auto& command=frontend::commands[i];
                if (command.id==menuart::labels[locale][menuart::HARDEST_LABEL])
                    assert(command.angle==0 && command.bounds.left==38 && command.bounds.right==218);
            }
        }
        menu.mode=ui::view::playing;
        ui::button controls[8]; assert(menu.buttons(controls)==2);
        assert(controls[0].x+(controls[0].width+1)/2<=controls[1].x-controls[1].width/2);
        for (int i=0;i<2;++i) {
            const auto& sprite=menuart::sprites[menuart::hud0+(i?menuart::hudquads[locale]:0)];
            assert(controls[i].width>=sprite.w && controls[i].height>=sprite.h);
        }
    }
    for (int skin=0;skin<16;++skin) {
        menu={}; menu.mode=ui::view::playing; menu.pack=15; menu.skins[2]=skin;
        game.reset(dx::levels[375]);
        for (bool woken : {false,true}) for (int age : {0,1,12,30,100,240,600}) {
            game.nightwoken=woken;
            game.visuals=game.ticks=age; frontend::preparegame(menu,game,age);
            const int expected=skin?frontend::animation(menuart::costumes[skin-1][woken?8:7],age*.016f+(woken?menuart::sleeptrim[skin-1]:0)):menuart::sleep0+std::min(6,static_cast<int>(age*.016f/.05f));
            bool found=false;
            for (int i=0;i<frontend::groundend;++i) found |= frontend::commands[i].id==expected;
            assert(found);
        }
    }
    menu={};
    std::puts("PASS: all locales clip the Mechanical label, scaled HUD hitboxes fit, all costumes follow trimmed Pillow sleep timelines");
    {
        auto data=dx::levels[410]; data.tubecount=1; data.beltcount=0;
        game.reset(data); game.steamtime=.3f;
        struct piece { int sprite; dx::point position; float size; };
        std::vector<piece> normal, carried;
        auto record=[&](std::vector<piece>& pieces) {
            for (bool front : {false,true}) gamevisuals::steam(game,front,[&](int sprite,dx::point position,int,float,float size) {
                pieces.push_back({sprite,position,size});
            });
        };
        record(normal);
        game.beltitemsused=1; game.beltitems[0]={};
        game.beltitems[0].kind=4; game.beltitems[0].scale=.7f;
        record(carried);
        assert(normal.size()==carried.size() && normal.size()>2);
        for (unsigned i=0;i<normal.size();++i) {
            const auto& a=normal[i]; const auto& b=carried[i];
            const auto expected=data.tubes[0].position+(a.position-data.tubes[0].position)*.7f;
            assert(a.sprite==b.sprite && std::abs(expected.x-b.position.x)<.001f && std::abs(expected.y-b.position.y)<.001f);
            const float factor=a.sprite==menuart::pipe0 || a.sprite==menuart::pipe1?.49f:.7f;
            assert(std::abs(a.size*factor-b.size)<.00001f);
        }
        std::puts("PASS: conveyor-carried steam applies source parent/child scales without changing force height");
    }
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
    for (int skin=0;skin<16;++skin) for (int candy=0;candy<52;++candy) {
        menu={}; menu.mode=ui::view::playing; menu.skins[0]=candy; menu.skins[2]=skin;
        game.reset(dx::levels[0]); game.definition.hooks[0].spider=true;
        game.ropes[0].spiderpos=game.definition.target; game.bodies[0].pos=game.definition.target;
        game.stars[0]=true; game.collectedat[0]=0;
        frontend::preparegame(menu,game,1); frontend::prepareoverlay(menu,game);
        int target=-1, sweet=-1, spider=-1, burst=-1;
        for (int i=0;i<frontend::count;++i) {
            const int id=frontend::commands[i].id;
            if (id==(skin?frontend::animation(menuart::costumes[skin-1][0],.016f):menuart::body0)) target=i;
            if (id==menuart::gamecandies[candy][0]) sweet=i;
            if (id==menuart::spider0) spider=i;
            if (id==menuart::starburst0) burst=i;
        }
        assert(target>=0 && target<frontend::groundend);
        assert(burst>=frontend::starback && burst<frontend::starfront);
        assert(!candy || (sweet>=frontend::starfront && sweet<spider));
        assert(spider>=frontend::starfront && spider<frontend::overlaystart);
    }
    std::puts("PASS: all 16 costumes / 52 candies retain target, hook, star, candy, spider and HUD pass order");
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
        if (data.tubecount || data.lanterncount || data.mousecount || data.night || data.beltcount) combinations=std::max(combinations,36);
        for (int combination=0; combination<combinations; ++combination) {
            game.reset(data); game.introduction=false;
            for (int i=0;i<data.beltcount;++i) {
                game.belts[i].offset=combination*1.75f;
                game.belts[i].activation=(i+combination)%data.beltcount;
            }
            if (data.mousecount) {
                game.activemouse=combination%data.mousecount;
                auto& mouse=game.mice[game.activemouse]; mouse.phase=combination%7; mouse.quad=combination%29;
                mouse.eyes=.05f*(combination%9); mouse.bounce=.01f*(combination%15);
            }
            game.awake=combination%2; game.nightstart=80-combination*4;
            game.lightalpha.fill((combination%11)/10.0f); game.lightchange.fill(80-combination%16);
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
    if(failed) for(int i=0;i<menuart::pagecount;++i) if(peakpages[i]) std::printf("Page %d: %u bytes\n",i,frontend::bytes(i));
    assert(!frontend::renderfault);
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
