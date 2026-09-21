#include "gamelog.hpp"
#include <cassert>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>

extern "C" { extern volatile unsigned logevents,logwrites,logfaults; }
static std::string read(const std::string& path) {
    std::ifstream file(path);
    return {std::istreambuf_iterator<char>(file),std::istreambuf_iterator<char>()};
}
int main(int argc,char** argv) {
    assert(argc==2);
    const std::string directory=argv[1];
    volatile unsigned ticks=12;
    gamelog::clock(&ticks);
    gamelog::initialize(directory.c_str());
    gamelog::context(7,9,13,0,0);
    gamelog::mark("test.read",42);
    gamelog::event("checkpoint %s %d","persisted",123);
    const auto first=read(directory+"/game-0001.log");
    assert(first.find("SESSION")!=std::string::npos);
    assert(first.find("f=7 vb=12 view=9 fade=13")!=std::string::npos);
    assert(first.find("stage=test.read:42")!=std::string::npos);
    assert(first.find("checkpoint persisted 123")!=std::string::npos);
    gamelog::initialize(directory.c_str());
    gamelog::event("second session");
    assert(read(directory+"/game-0001.log")==first);
    assert(read(directory+"/game-0002.log").find("second session")!=std::string::npos);
    ticks=700;
    gamelog::checkwait(12);
    assert(read(directory+"/game-0002.log").find("FATAL Renderer wait")!=std::string::npos);
    std::string longtext(2048,'x');
    gamelog::event("%s",longtext.c_str());
    assert(read(directory+"/game-0002.log").back()=='\n');
    gamelog::initialize(nullptr);
    const unsigned writes=logwrites;
    gamelog::event("no storage");
    assert(logwrites==writes && logfaults>0 && logevents>logwrites);
    std::puts("PASS: persistent checkpoints, separate sessions, wait diagnostics, bounded records, no-storage fallback");
}
