#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#ifdef __NDS__
#include <nds/arm9/math.h>
#endif

namespace dx {
struct point {
    float x = 0, y = 0;
    point operator+(point b) const { return {x + b.x, y + b.y}; }
    point operator-(point b) const { return {x - b.x, y - b.y}; }
    point operator*(float n) const { return {x * n, y * n}; }
    point operator/(float n) const { return {x / n, y / n}; }
    float length() const {
#ifdef __NDS__
        return hw_sqrtf(x * x + y * y);
#else
        return std::sqrt(x * x + y * y);
#endif
    }
};
struct motion { point offset{}; float speed = 0, rotation = 0, circle = 0; point at(float time) const; float angle(float base, float time, bool reset = false) const; };
struct hook { point anchor; float length; float radius = -1; bool spider = false; float rail = 0, offset = 0; bool vertical = false; int part = 0; bool wheel = false; int route = -1; float speed = 0; bool hidepath = false; };
struct spike { point anchor{}; motion path{}; float angle = 0; int size = 1; float on = 0, off = 0, delay = 0; int group = -1; };
struct pump { point position{}; float angle = 0; };
struct hat { point position{}; motion path{}; float angle = 0; int group = 0; bool resetangle = false; };
struct bouncer { point position{}; motion path{}; float angle = 0; int size = 1; };
struct level {
    point candy, target;
    std::array<point, 3> stars;
    std::array<hook, 16> hooks;
    int hookcount;
    float speed;
    float left, width, height;
    int box = 0, index = 0;
    std::array<float, 3> timeouts{{-1, -1, -1}};
    std::array<motion, 3> starmotions{};
    std::array<point, 32> bubbles{};
    std::array<spike, 16> spikes{};
    std::array<pump, 8> pumps{};
    int bubblecount = 0, spikecount = 0, pumpcount = 0;
    bool split = false;
    std::array<point, 2> halves{};
    std::array<hat, 8> hats{};
    std::array<bouncer, 16> bouncers{};
    int hatcount = 0, bouncercount = 0;
    point gravity{0,784};
    std::array<point, 4> switches{};
    int switchcount = 0;
};
const level& loadlevel(int index);
struct constraint { int other = 0; float length = 0; bool active = false, maximum = false; };
struct body {
    point pos, previous, pin, velocity;
    float inverse = 50;
    bool initialized = false, pinned = false;
    std::array<constraint, 20> links{};
    int linkcount = 0;
};
struct rope {
    std::array<int, 32> bodies{};
    int count = 0, pending = -1, split = 0;
    bool cut = false;
    float remaining = 2;
    int attached = -1;
    float spiderdistance = 0, spiderangle = 0;
    point spiderpos{};
    int spiderstate = 0, spiderfall = -1;
    point spiderorigin{};
    float spiderturn = 0;
    bool spiderup = false, hidetail = false;
    int candy = 0;
};
enum class outcome { playing, won, lost };
class simulation {
public:
    void reset(const level& data);
    void tick(bool suppressoutcome = false);
    bool swipe(point start, point end);
    bool tap(point position);
    bool sever(int index, int segment);
    bool interact(point position);
    bool drag(point position, bool held);
    void animate();
    void togglegravity();
    void rotatewheel(int index, point position);
    void rotatespikes(int group);
    float spikeangle(int index) const;
    point spikeposition(int index) const;
    bool spikehit(int index, point position) const;
    int ropelength(int index) const;
    float wheelscale(int index) const;
    void camera();
    void samples(int index, int first, int count, point* output, int& size) const;
    const body& candy() const { return bodies[0]; }
    int activecount() const { return split ? 2 : 1; }
    int activeid(int index) const { return split ? index + 1 : 0; }
    int bubblefor(int id) const { return id ? halfbubbles[id - 1] : bubble; }
    bool hidden() const { return transit >= 0; }
    level definition{};
    std::array<body, 256> bodies{};
    std::array<rope, 16> ropes{};
    std::array<bool, 3> stars{};
    std::array<int, 3> collectedat{};
    int excitement = -1000, greeting = -1000;
    std::array<point, 3> starpositions{};
    std::array<bool, 3> expired{};
    std::array<bool, 32> bubblesused{};
    std::array<int, 8> pumpages{};
    int bubble = -1, bubbleevents = 0, pumpevents = 0, ropeevents = 0, failreason = 0;
    int visuals = 0, pops = 0, popage = 100;
    point popposition{};
    float cameray = 0, cameraspeed = 20, cameradistance = 0;
    bool introduction = false;
    int bodycount = 0, ticks = 0, count = 0, resulttick = 0, resultvisual = 0;
    bool mouth = false;
    int mouthtick = 0;
    outcome state = outcome::playing;
    std::array<point, 16> anchors{};
    std::array<float, 16> electrotimers{};
    std::array<bool, 16> electric{};
    std::array<int, 16> bounceages{};
    std::array<float, 8> hattimers{};
    std::array<int, 8> hatages{};
    std::array<int, 2> halfbubbles{{-1,-1}};
    std::array<point, 2> halfdraw{};
    bool split = false, merging = false;
    float mergedistance = 0, exitspeed = 0;
    int draghook = -1, transit = -1, transitage = 0, mergeage = 100;
    int bounceevents = 0, teleportevents = 0, mergeevents = 0;
    bool inverted = false;
    int gravityevents = 0, wheelevents = 0, gravityage = 100, dragswitch = -1, dragwheel = -1;
    std::array<float, 16> wheelangles{};
    point wheeltouch{};
    std::array<int, 16> beetargets{};
    std::array<float, 16> beeangles{}, spikeages{}, spikefirst{}, spikelast{}, spikeduration{};
    std::array<bool, 16> spikenormal{};
    int dragspike = -1, spikeevents = 0, spiderfalls = 0, spideractivations = 0;
    bool spikedirection = false;
private:
    void movebee(int index);
    void dropspider(int index, bool won = false);
    void releasecandy(int id);
    int add(point position, float inverse, bool pinned);
    void integrate(body& item, float acceleration, float inverse = 0);
    void satisfy(body& item);
    void solve(const rope& item);
    void detach(rope& item);
    void attach(int index, float length, int candy = 0);
    void ropephysics();
    void hazards();
    void spiders();
    void fail(int reason);
    bool suppressoutcome = false;
    void burst(int id = 0);
    void merge(bool touching);
    void transports();
    void bounce();
    void cutattached(int id);
    void reel(int index, float amount);
    std::array<int, 256> freebodies{};
    int freecount = 0;
};
}
