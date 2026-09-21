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
struct motion { point offset{}; float speed = 0, rotation = 0, circle = 0; int route = -1; point at(float time) const; float angle(float base, float time, bool reset = false) const; };
struct hook { point anchor; float length; float radius = -1; bool spider = false; float rail = 0, offset = 0; bool vertical = false; int part = 0; bool wheel = false; int route = -1; float speed = 0; bool hidepath = false, bulb = false; };
struct mouse { point position{}; float angle = 0, radius = 240, duration = 3; int index = 1; };
struct mousestate { point offset{}; std::array<point,4> entry{}; std::array<point,3> exit{}; float elapsed = 0, age = 0, pathage = 0, bounce = -1, eyes = -1; int phase = 6, quad = 18, path = 0; bool active = false, retreat = false, grabbing = false, carry = false, container = false; };
struct lightbulb { point position{}; float radius = 225; };
struct conveyor { point position{}; float length = 0, width = 0, angle = 0, velocity = 0; bool manual = false; };
struct beltstate { float c = 1, s = 0, pc = 0, ps = -1, offset = 0, delta = 0, travel = 0; point last{}; int activation = 0, alignment = 0, count = 0; bool active = false, distributed = false; std::array<int,64> items{}; };
struct beltitem { int kind = 0, index = 0, belt = -1; float radius = 0, minimum = .5f, maximum = 1, scale = 1, position = 0; };
struct spike { point anchor{}; motion path{}; float angle = 0; int size = 1; float on = 0, off = 0, delay = 0; int group = -1; };
struct pump { point position{}; float angle = 0; };
struct hat { point position{}; motion path{}; float angle = 0; int group = 0; bool resetangle = false; };
struct bouncer { point position{}; motion path{}; float angle = 0; int size = 1; };
struct disc { point position{}; float size = 0, angle = 0; bool single = false; };
struct ghost { point position{}; float radius = -1, angle = 0; int forms = 1; };
struct tube { point position{}; float angle = 0, scale = 3; };
struct lantern { point position{}; motion path{}; bool captured = false; int route = -1; };
struct puff { float start = -100, stop = -1, height = 0; int variant = 0, horizontal = 0; };
struct tubestate { int state = 0, revision = 0; float phase = 0, valveage = .55f, valve = 0; bool reverse = false; std::array<puff, 42> puffs{}; point forward{}, backward{}; float angle = 1e9f, scale = 0, lift = 0; };
struct lanternstate { point position{}, previous{}; float age = 0, cooldown = -1, release = -1, firestart = 0, idlestart = 0, angle = 0; int state = 0, phase = 0, target = 1; };
struct apparition { int ghost = -1, form = 0, index = -1; float age = 0, retirement = -1; int owner = -1; };
struct ghoststate { int form = 1, app = -1, morphs = 0; float age = 0, idleage = 0; };
struct discstate { int index = 0; float angle = 0, fade = .216f; bool copy = false; };
struct discbaseline { point position{}; float angle = 0; int owner = -1; };
struct level {
    point candy, target;
    std::array<point, 3> stars;
    std::array<hook, 24> hooks;
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
    std::array<bouncer, 24> bouncers{};
    int hatcount = 0, bouncercount = 0;
    point gravity{0,784};
    std::array<point, 4> switches{};
    int switchcount = 0;
    std::array<disc, 4> discs{};
    std::array<ghost, 4> ghosts{};
    int disccount = 0, ghostcount = 0;
    std::array<tube, 7> tubes{};
    std::array<lantern, 6> lanterns{};
    int tubecount = 0, lanterncount = 0;
    std::array<mouse,5> mice{};
    std::array<lightbulb,1> bulbs{};
    int mousecount = 0, bulbcount = 0;
    bool night = false;
    std::array<conveyor,4> belts{};
    int beltcount = 0;
};
const level& loadlevel(int index);
struct constraint { int other = 0; float length = 0; bool active = false, maximum = false; };
struct body {
    point pos, previous, pin, velocity;
    float inverse = 50;
    bool initialized = false, pinned = false;
    std::array<constraint, 24> links{};
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
    bool pressdisc(point position);
    void rotatedisc(point position);
    point dischandle(int index, bool right) const;
    bool ghosttap(int index);
    bool valvetap(int index);
    bool lanterntap(int index);
    float steamheight(int index) const;
    point valvepoint(int index) const;
    std::array<tubestate, 7> tubes{};
    std::array<lanternstate, 6> lanterns{};
    int steamevents = 0, steamstate = 0, captures = 0, releases = 0, pendinglantern = -1;
    float steamtime = 0, capturetimer = -1, captureage = 1;
    bool inlantern = false, sharedlantern = false, nogravity = false;
    point capturefrom{}, captureto{}, candydraw{};
    std::array<float, 8> reveals{};
    void ghostform(int index, int form);
    void burst(int id = 0, bool sound = true);
    const apparition* ghostapp(int form, int index) const;
    float ghostalpha(int form, int index) const;
    std::array<ghoststate, 4> ghosts{};
    std::array<apparition, 24> apparitions{};
    std::array<discstate, 12> discorder{};
    int disclayers = 0, dragdisc = -1, discside = 0, discevents = 0, ghostevents = 0;
    bool discdirection = false;
    point disctouch{};
    void samples(int index, int first, int count, point* output, int& size) const;
    const body& candy() const { return bodies[0]; }
    int candycount() const { return split ? halfalive[0] + halfalive[1] : 1; }
    int activecount() const { return candycount() + (definition.bulbcount && bulbalive); }
    int activeid(int index) const { return index >= candycount() ? 3 : split ? halfalive[0] ? index + 1 : 2 : 0; }
    int bodybase() const { return definition.bulbcount ? 4 : definition.split ? 3 : 1; }
    int& bubbleindex(int id) { return id == 3 ? bulbbubble : id ? halfbubbles[id - 1] : bubble; }
    int bubblefor(int id) const { return id == 3 ? bulbbubble : id ? halfbubbles[id - 1] : bubble; }
    bool available(int id) const { return id == 3 ? bulbalive && bulbtransit < 0 : !hidden() && (state == outcome::playing || failreason == 4 || (split && id >= 1 && id <= 2 && halfalive[id-1])); }
    bool hidden() const { return transit >= 0 || inlantern; }
    bool mousepress(point position);
    bool illuminated(point position) const;
    bool pressbelt(point position);
    bool dragbelt(point position);
    void releasebelt(point position);
    void cancelbelts();
    point beltlocal(int index, point position) const;
    point beltworld(int index, float x, float y) const;
    point beltpoint(const beltitem& item) const;
    void removebeltitem(int kind, int index);
    float beltscale(int kind, int index) const;
    bool belted(int kind, int index) const;
    std::array<beltstate,4> belts{};
    std::array<beltitem,64> beltitems{};
    std::array<int,4> beltorder{};
    int beltitemsused = 0, heldbelt = -1, beltrevision = 0, beltwraps = 0, belthandoffs = 0, beltevents = 0, beltsound = 0;
    std::array<mousestate,5> mice{};
    int activemouse = -1, mousecaptures = 0, mousereleases = 0, mousehandoffs = 0, mouseevents = 0, mousesound = 0;
    bool micelocked = false;
    bool bulbalive = false, awake = false, nightwoken = false;
    int bulbbubble = -1, bulbtransit = -1, nightstart = 0, sleepevents = 0;
    float mouthdelay = 0;
    float bulbtime = 0, bulbspeed = 0, candytime = 0, sleeptime = 0;
    std::array<bool,3> starlit{}, pickuplit{};
    std::array<float,3> lightalpha{};
    std::array<float,3> lightedge{};
    std::array<int,3> lightchange{};
    level definition{};
    std::array<body, 256> bodies{};
    std::array<rope, 24> ropes{};
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
    std::array<point, 24> anchors{};
    std::array<float, 16> electrotimers{};
    std::array<bool, 16> electric{};
    std::array<int, 24> bounceages{};
    std::array<float, 8> hattimers{};
    std::array<int, 8> hatages{};
    std::array<int, 2> halfbubbles{{-1,-1}};
    std::array<bool, 2> halfalive{{true,true}};
    std::array<point, 2> halfdraw{};
    bool split = false, merging = false;
    float mergedistance = 0, exitspeed = 0;
    int draghook = -1, transit = -1, transitage = 0, mergeage = 100;
    int bounceevents = 0, teleportevents = 0, mergeevents = 0;
    bool inverted = false;
    int gravityevents = 0, wheelevents = 0, gravityage = 100, dragswitch = -1, dragwheel = -1;
    std::array<float, 24> wheelangles{};
    point wheeltouch{};
    std::array<int, 24> beetargets{};
    std::array<float, 24> beeangles{};
    std::array<float, 16> spikeages{}, spikefirst{}, spikelast{}, spikeduration{};
    std::array<bool, 16> spikenormal{};
    int dragspike = -1, spikeevents = 0, spiderfalls = 0, spideractivations = 0;
    bool spikedirection = false;
private:
    void resetbelts();
    void updatebelts();
    void sortbelts();
    void movebelt(int index, float delta);
    void alignbelt(int index);
    void bindbelt(int index, int item);
    void setbeltpoint(beltitem& item, point position);
    bool belthit(int index, point position, float radius) const;
    void resetnocturnal();
    void updatemice();
    void spawnmouse(int index, bool carry);
    void attachmouse(int index);
    void retreatmouse(int index);
    void dropmouse();
    void stopmice();
    void collidelight();
    void updatelight();
    void retirebulb();
    void advancelighttransport();
    void lighttransports();
    void resetdevices();
    void advancedevices();
    void updatedevices();
    void adjuststeam(int index);
    void cachetube(int index);
    void capturelantern(int index, int count);
    void removelantern();
    void resetcontraptions();
    void advanceghosts(int form);
    void updateghosts();
    void updatediscs();
    void retireghost(int index);
    void releaseghost(int id);
    void mergeghosts();
    std::array<discbaseline, 64> baselines{};
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
    void retirehalf(int id, int reason);
    bool suppressoutcome = false;
    void merge(bool touching);
    void transports();
    void bounce();
    void cutattached(int id);
    void reel(int index, float amount);
    std::array<int, 256> freebodies{};
    int freecount = 0;
};
}
