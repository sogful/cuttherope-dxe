#include "simulation.hpp"
#include <cassert>
#include <cstdio>

int main() {
    dx::simulation game;
    unsigned random=0x77653811;
    auto next=[&]() { random^=random<<13; random^=random>>17; random^=random<<5; return random; };
    float maximum=0;
    for (int count=3;count<=32;++count) for (int trial=0;trial<120;++trial) {
        auto& rope=game.ropes[0]; rope.count=count;
        for (int i=0;i<count;++i) {
            rope.bodies[i]=i;
            const float range=trial<100?6000.0f:trial<119?64000.0f:100000.0f;
            game.bodies[i].pos={(static_cast<int>(next()%200001)-100000)*(range/200000),
                (static_cast<int>(next()%200001)-100000)*(range/200000)};
        }
        dx::point original[125],fixed[125]; int a=0,b=0;
        game.samples(0,0,count,original,a); game.samples(0,0,count,fixed,b,true);
        assert(a==b);
        for (int i=0;i<a;++i) {
            const float error=(original[i]-fixed[i]).length();
            maximum=std::max(maximum,error);
            assert(error<.06f);
        }
    }
    std::printf("PASS: 3,600 visual curves, all 3-32 control counts, signed/boundary coordinates; max error %.6f world pixels (%.6f DS pixels)\n",maximum,maximum*192/1440);
}
