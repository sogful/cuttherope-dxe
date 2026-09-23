#include "simulation.hpp"
#include "level.hpp"
#include <cassert>
#include <cstdio>

static void same(dx::point a, dx::point b) { assert(a.x == b.x && a.y == b.y); }
static void same(dx::motion a, dx::motion b) { same(a.offset,b.offset); assert(a.speed == b.speed && a.rotation == b.rotation && a.circle == b.circle && a.route == b.route); }
static void decoded(const dx::level& a, const dx::level& b) {
    same(a.candy,b.candy); same(a.target,b.target);
    same(a.gravity,b.gravity); assert(a.switchcount == b.switchcount);
    assert(a.disccount == b.disccount && a.ghostcount == b.ghostcount);
    assert(a.tubecount == b.tubecount && a.lanterncount == b.lanterncount);
    assert(a.mousecount == b.mousecount && a.bulbcount == b.bulbcount && a.night == b.night);
    assert(a.beltcount == b.beltcount);
    for (int i=0;i<a.beltcount;++i) {
        const auto& x=a.belts[i]; const auto& y=b.belts[i]; same(x.position,y.position);
        assert(x.length==y.length && x.width==y.width && x.angle==y.angle && x.velocity==y.velocity && x.manual==y.manual);
    }
    for (int i=0;i<a.mousecount;++i) {
        const auto& x=a.mice[i]; const auto& y=b.mice[i]; same(x.position,y.position);
        assert(x.angle==y.angle && x.radius==y.radius && x.duration==y.duration && x.index==y.index);
    }
    for (int i=0;i<a.bulbcount;++i) { same(a.bulbs[i].position,b.bulbs[i].position); assert(a.bulbs[i].radius==b.bulbs[i].radius); }
    for (int i=0;i<a.tubecount;++i) {
        const auto& x=a.tubes[i]; const auto& y=b.tubes[i]; same(x.position,y.position);
        assert(x.angle==y.angle && x.scale==y.scale);
    }
    for (int i=0;i<a.lanterncount;++i) {
        const auto& x=a.lanterns[i]; const auto& y=b.lanterns[i]; same(x.position,y.position); same(x.path,y.path);
        assert(x.captured==y.captured && x.route==y.route);
    }
    for (int i = 0; i < a.disccount; ++i) {
        const auto& x=a.discs[i]; const auto& y=b.discs[i]; same(x.position,y.position);
        assert(x.size==y.size && x.angle==y.angle && x.single==y.single);
    }
    for (int i = 0; i < a.ghostcount; ++i) {
        const auto& x=a.ghosts[i]; const auto& y=b.ghosts[i]; same(x.position,y.position);
        assert(x.radius==y.radius && x.angle==y.angle && x.forms==y.forms);
    }
    for (int i = 0; i < a.switchcount; ++i) same(a.switches[i],b.switches[i]);
    assert(a.box == b.box && a.index == b.index && a.split == b.split && a.speed == b.speed && a.left == b.left && a.width == b.width && a.height == b.height);
    for (int i = 0; i < 2; ++i) same(a.halves[i],b.halves[i]);
    for (int i = 0; i < 3; ++i) { same(a.stars[i],b.stars[i]); same(a.starmotions[i],b.starmotions[i]); assert(a.timeouts[i] == b.timeouts[i]); }
    assert(a.hookcount == b.hookcount && a.bubblecount == b.bubblecount && a.spikecount == b.spikecount && a.pumpcount == b.pumpcount && a.hatcount == b.hatcount && a.bouncercount == b.bouncercount);
    for (int i = 0; i < a.hookcount; ++i) {
        const auto& x = a.hooks[i]; const auto& y = b.hooks[i]; same(x.anchor,y.anchor);
        assert(x.length == y.length && x.radius == y.radius && x.spider == y.spider && x.rail == y.rail && x.offset == y.offset && x.vertical == y.vertical && x.part == y.part && x.wheel == y.wheel);
        assert(x.route == y.route && x.speed == y.speed && x.hidepath == y.hidepath && x.bulb==y.bulb);
    }
    for (int i = 0; i < a.bubblecount; ++i) same(a.bubbles[i],b.bubbles[i]);
    for (int i = 0; i < a.spikecount; ++i) {
        const auto& x = a.spikes[i]; const auto& y = b.spikes[i]; same(x.anchor,y.anchor); same(x.path,y.path);
        assert(x.angle == y.angle && x.size == y.size && x.on == y.on && x.off == y.off && x.delay == y.delay);
        assert(x.group == y.group);
    }
    for (int i = 0; i < a.pumpcount; ++i) { same(a.pumps[i].position,b.pumps[i].position); assert(a.pumps[i].angle == b.pumps[i].angle); }
    for (int i = 0; i < a.hatcount; ++i) {
        const auto& x = a.hats[i]; const auto& y = b.hats[i]; same(x.position,y.position); same(x.path,y.path);
        assert(x.angle == y.angle && x.group == y.group && x.resetangle == y.resetangle);
    }
    for (int i = 0; i < a.bouncercount; ++i) {
        const auto& x = a.bouncers[i]; const auto& y = b.bouncers[i]; same(x.position,y.position); same(x.path,y.path);
        assert(x.angle == y.angle && x.size == y.size);
    }
}

int main() {
    dx::simulation game;
    std::printf("{\"traces\":[");
    int sequence = 0;
    for (int index : {0,5,6,9}) {
        game.reset(dx::levels[index]);
        std::printf("%s{\"level\":%d,\"samples\":[", sequence++ ? "," : "", index + 1);
        for (int i = 1; i <= 120; ++i) {
            if (index == 5 && i == 61) game.sever(0,0);
            game.tick();
            if (i == 1 || i % 15 == 0) std::printf("%s{\"tick\":%d,\"x\":%.8f,\"y\":%.8f}", i == 1 ? "" : ",", i, game.candy().pos.x, game.candy().pos.y);
        }
        std::printf("]}");
    }
    game.reset(dx::levels[6]);
    for (int frame = 1; frame <= 600 && game.state == dx::outcome::playing; ++frame) {
        if (frame == 61) for (int rope : {0,2,3}) game.sever(rope,0);
        if (frame == 96) for (int rope : {1,5}) game.sever(rope,0);
        game.tick();
    }
    assert(game.count == 3); // The original route test checks stars, not feeding Om Nom.
    for (const auto& level : dx::levels) {
        decoded(level,dx::loadlevel(level.box * 25 + level.index));
        game.reset(dx::loadlevel(level.box * 25 + level.index));
        for (int index = 0; index < level.hookcount; ++index) {
            const auto& rope = game.ropes[index];
            if (rope.count < 3) continue;
            dx::point curve[125]; int size;
            game.samples(index,0,rope.count,curve,size);
            for (int sample = 0; sample < size; ++sample) {
                dx::point work[32];
                for (int part = 0; part < rope.count; ++part) work[part] = game.bodies[rope.bodies[part]].pos;
                const float t = static_cast<float>(sample) / (size - 1);
                for (int degree = rope.count - 1; degree > 0; --degree)
                    for (int part = 0; part < degree; ++part) work[part] = work[part] * (1-t) + work[part+1] * t;
                assert((curve[sample] - work[0]).length() < .01f);
            }
        }
        for (int frame = 0; frame < 1200; ++frame) {
            if (frame == 600) for (int i = 0; i < level.hookcount; ++i) game.sever(i, 0);
            if (frame % 30 == 0 && !game.introduction) for (int i = 0; i < level.pumpcount; ++i) game.interact(level.pumps[i].position);
            game.tick();
            assert(std::isfinite(game.candy().pos.x) && std::isfinite(game.candy().pos.y));
            if (game.state != dx::outcome::playing && game.failreason != 4) {
                for (int i = 0; i < level.hookcount; ++i) if (game.ropes[i].count) {
                    if (game.ropes[i].candy==3 && game.bulbalive) continue;
                    if (game.split && game.ropes[i].candy && game.halfalive[game.ropes[i].candy-1]) continue;
                    assert(game.ropes[i].cut && game.ropes[i].pending < 0);
                    if (level.hooks[i].spider) assert(game.ropes[i].spiderstate);
                }
            }
            assert(game.bodycount <= 256 && game.candy().linkcount <= 20);
            for (int part = 0; part < game.activecount(); ++part) {
                const auto& body = game.bodies[game.activeid(part)];
                assert(std::isfinite(body.pos.x) && std::isfinite(body.pos.y) && body.linkcount <= 20);
            }
            assert(game.cameray >= 0 && game.cameray <= level.height - 1440);
        }
    }
    dx::level empty = dx::firstlevel;
    empty.hookcount = 0; empty.target = {3000, 1000};
    empty.stars = {{{100,100},{200,100},{300,100}}};
    empty.candy = {1280, 720};
    empty.bubblecount = 1; empty.bubbles[0] = empty.candy;
    game.reset(empty);
    game.tick();
    assert(game.bubble == 0 && game.bubblesused[0]);
    for (int i = 0; i < 60; ++i) game.tick();
    assert(game.candy().pos.y < 720);
    const float before = game.candy().pos.y;
    assert(game.interact(game.candy().pos) && game.bubble == -1 && game.pops == 1);
    for (int i = 0; i < 80; ++i) game.tick();
    assert(game.candy().pos.y > before);
    empty.bubblecount = 0;
    empty.pumpcount = 1; empty.pumps[0] = {{1000,720},90};
    game.reset(empty);
    assert(game.interact({1000,720}) && game.pumpevents == 1 && game.candy().pos.x > 1280);
    empty.pumpcount = 0;
    empty.spikecount = 1; empty.spikes[0] = {{1280,720},{},0,1};
    game.reset(empty); game.tick();
    assert(game.state == dx::outcome::lost && game.failreason == 2);
    game.reset(empty); game.tick(true);
    assert(game.state == dx::outcome::playing && game.failreason == 0);
    game.tick(); assert(game.state == dx::outcome::lost);
    empty.spikecount = 0;
    empty.hookcount = 1; empty.hooks[0] = {{1280,500},300,180,false};
    game.reset(empty);
    assert(game.ropes[0].count == 0);
    game.tick();
    assert(game.ropeevents == 1 && game.ropes[0].count > 0);
    assert(game.sever(0,0));
    for (int i = 0; i < 4; ++i) game.tick();
    assert(game.ropes[0].pending == -1);
    const int bodies = game.bodycount;
    for (int i = 0; i < 80; ++i) game.tick();
    assert(game.bodycount == bodies && game.ropeevents == 1);
    empty.hookcount = 0; empty.timeouts[0] = .1f;
    game.reset(empty);
    for (int i = 0; i < 8; ++i) game.tick();
    assert(game.expired[0] && !game.stars[0]);
    dx::motion movement{{0,100},40,0};
    assert(std::abs(movement.at(1).y - 40) < .001f && std::abs(movement.at(3).y - 80) < .001f);
    game.reset(dx::levels[14]);
    assert(game.introduction);
    game.tick();
    const float normalspeed = game.cameraspeed;
    game.camerafast = true;
    game.tick();
    assert(game.cameraspeed > normalspeed * 1.4f);
    for (int i = 0; i < 500 && game.introduction; ++i) game.tick();
    assert(!game.introduction && game.ticks <= 1);
    // Foil: source rail range is anchor-offset .. anchor-offset+length.
    empty.hookcount = 1; empty.hooks[0] = {{1280,500},210,-1,false,400,100,false,0};
    game.reset(empty);
    assert(game.interact({1280,500}) && game.draghook == 0);
    assert(game.drag({900,900},true)); same(game.anchors[0],{1180,500});
    game.drag({2000,0},true); same(game.anchors[0],{1580,500});
    game.drag({},false); assert(game.draghook == -1);
    empty.hooks[0].vertical = true;
    game.reset(empty); game.interact({1280,500}); game.drag({0,2000},true); same(game.anchors[0],{1280,800});
    empty.hookcount = 0;
    empty.spikecount = 1; empty.spikes[0] = {{100,100},{},0,5,.032f,.032f,0};
    game.reset(empty); game.tick(); assert(!game.electric[0]);
    game.tick(); assert(game.electric[0]); game.tick(); game.tick(); assert(!game.electric[0]);
    empty.spikes[0].delay = -.064f;
    game.reset(empty); game.tick(); assert(!game.electric[0]); game.tick(); assert(game.electric[0]);
    empty.spikecount = 0;
    dx::motion circle{{},40,0,20};
    same(circle.at(0),{20,0});
    const float chord = 40 * std::sin(3.14159265f / 10);
    const auto vertex = circle.at(chord / 40);
    assert(std::abs(vertex.x - 20 * std::cos(6.2831853f / 10)) < .001f);
    assert(std::abs(vertex.y - 20 * std::sin(6.2831853f / 10)) < .001f);
    // Magic: only the front mouth catches; delayed exit follows the moving partner.
    empty.candy = {1280,700}; empty.hatcount = 2;
    empty.hats[0] = {{1280,720},{},0,0,false};
    empty.hats[1] = {{1600,800},{{100,0},50,0},90,0,false};
    game.reset(empty); game.bodies[0].previous.y = 690; game.tick();
    assert(game.hidden() && game.teleportevents == 1);
    for (int i = 0; i < 6; ++i) { game.tick(); assert(game.hidden()); }
    game.tick(); assert(!game.hidden());
    assert(game.candy().pos.x > 1616 && std::abs(game.candy().pos.y - 800) < .001f && game.candy().velocity.x > 0);
    assert(game.hattimers[1] > 0);
    game.reset(empty); game.bodies[0].previous.y = 710; game.tick(); assert(!game.hidden());
    // Valentine: merging inherits both active ropes and the surviving bubble.
    empty.hatcount = 0; empty.split = true; empty.halves = {{{1250,700},{1310,700}}};
    empty.hookcount = 2; empty.hooks[0] = {{1250,490},210,-1,false,0,0,false,0}; empty.hooks[1] = {{1310,490},210,-1,false,0,0,false,1};
    game.reset(empty); game.halfbubbles[1] = 0;
    assert(game.ropes[0].candy == 1 && game.ropes[1].candy == 2);
    for (int i = 0; i < 120 && game.split; ++i) game.tick();
    assert(!game.split && game.mergeevents == 1 && game.bubble == 0);
    assert(game.ropes[0].candy == 0 && game.ropes[1].candy == 0 && game.candy().linkcount == 2);
    assert(game.interact(game.candy().pos) && game.bubble == -1);
    // Toy: the bouncer removes normal-axis history and applies the source impulse.
    empty.split = false; empty.hookcount = 0; empty.bouncercount = 1;
    empty.candy = {1280,700}; empty.bouncers[0] = {{1280,720},{},0,1};
    game.reset(empty); game.bodies[0].previous.y = 690; game.tick();
    assert(game.bounceevents == 1 && game.bounceages[0] == 0);
    assert(std::abs((game.candy().pos.y - game.candy().previous.y) + 840 * .016f) < .001f);
    game.reset(dx::levels[75]);
    for (int i = 0; i < 120; ++i) game.tick();
    assert(game.swipe({900,330},{1040,330}));
    for (int i = 0; i < 600 && game.state == dx::outcome::playing; ++i) game.tick();
    assert(game.teleportevents == 1 && game.state == dx::outcome::won && game.count == 3);
    game.reset(dx::levels[100]);
    for (int i = 0; i < 120; ++i) game.tick();
    assert(game.swipe({1050,260},{1550,260}));
    for (int i = 0; i < 600 && game.split; ++i) game.tick();
    assert(game.mergeevents == 1 && !game.split && game.state == dx::outcome::playing);
    for (int i = 0; i < game.definition.hookcount; ++i) game.sever(i,0);
    for (int i = 0; i < 600 && game.state == dx::outcome::playing; ++i) game.tick();
    assert(game.state == dx::outcome::won && game.count == 3);
    std::printf("],\"movers\":[");
    int emitted = 0;
    for (const auto& level : dx::levels) {
        auto mover = [&](const char* kind, int index, dx::point origin, dx::motion motion, float angle, bool reset = false) {
            if (!motion.speed && !motion.rotation && !motion.circle && !motion.offset.length()) return;
            for (int tick : {0,1,15,60,180,360,600}) {
                const auto p = origin + motion.at(tick * .016f);
                std::printf("%s{\"level\":%d,\"kind\":\"%s\",\"index\":%d,\"tick\":%d,\"x\":%.7f,\"y\":%.7f,\"angle\":%.7f}",
                    emitted++ ? "," : "",level.box*25+level.index,kind,index,tick,p.x,p.y,motion.angle(angle,tick*.016f,reset));
            }
        };
        for (int i = 0; i < 3; ++i) mover("star",i,level.stars[i],level.starmotions[i],0);
        for (int i = 0; i < level.spikecount; ++i) { const auto& x = level.spikes[i]; mover("spike",i,x.anchor,x.path,x.angle); }
        for (int i = 0; i < level.hatcount; ++i) { const auto& x = level.hats[i]; mover("sock",i,x.position,x.path,x.angle,x.resetangle); }
        for (int i = 0; i < level.bouncercount; ++i) { const auto& x = level.bouncers[i]; mover("bouncer",i,x.position,x.path,x.angle); }
    }
    std::printf("],\"maps\":%zu,\"frames\":%zu,\"passed\":true}\n", dx::levels.size(), dx::levels.size() * 1200);
}
