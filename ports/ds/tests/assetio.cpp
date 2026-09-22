#include "assetio.hpp"
#include <algorithm>
#include <array>
#include <cassert>
#include <cstring>
#include <vector>

static packed::diagnosis decode(const std::vector<unsigned char>& input,const char* reason,unsigned capacity=32) {
    std::array<unsigned char,34> output,plain;
    output.fill(0xcc); plain.fill(0xcc);
    unsigned cursor=0;
    auto next=[&]() -> int { return cursor<input.size()?input[cursor++]:-1; };
    packed::diagnosis report;
    const bool valid=packed::stream<true>(next,output.data()+1,capacity,&report);
    assert(valid==(reason==nullptr));
    assert(reason?report.reason && !std::strcmp(report.reason,reason):!report.reason);
    assert(report.consumed==cursor && output.front()==0xcc && output.back()==0xcc);
    assert(std::all_of(output.begin()+1+report.produced,output.end(),[](unsigned char value) { return value==0xcc; }));
    unsigned hash=2166136261u;
    for (unsigned i=0;i<cursor;++i) hash=(hash^input[i])*16777619u;
    assert(hash==report.hash);
    cursor=0;
    assert(packed::stream(next,plain.data()+1,capacity)==valid && plain==output);
    cursor=0;
    assert(assetio::decode(next,plain.data()+1,capacity,nullptr,"test",0)==valid);
    return report;
}

int main(int argc,char** argv) {
    assert(argc==3);
    gamelog::initialize(argv[1]);
    static_assert(assetio::padded(1)==32 && assetio::padded(32)==32 && assetio::padded(33)==64);
    const std::vector<unsigned char> valid{0x10,8,0,0,0x20,'a','b',0x30,1};
    const auto ok=decode(valid,nullptr);
    assert(ok.header==0x810 && ok.declared==8 && ok.produced==8);
    const char* reasons[]{"header.eof","header.eof","header.eof","header.eof","flags.eof","token.eof","token.eof","token.eof","match.eof"};
    for (unsigned length=0;length<valid.size();++length)
        decode(std::vector<unsigned char>(valid.begin(),valid.begin()+length),reasons[length]);
    decode({0x11,8,0,0},"header.kind");
    decode(valid,"output.capacity",7);
    auto distance=decode({0x10,3,0,0,0x80,0,0},"match.distance");
    assert(distance.produced==0 && distance.distance==1 && distance.length==3);
    auto length=decode({0x10,2,0,0,0x40,'a',0,0},"match.length");
    assert(length.produced==1 && length.distance==1 && length.length==3);
    decode({0x10,0,0,0},nullptr);
    FILE* file=std::fopen(argv[2],"w+b"); assert(file);
    assert(std::fwrite(valid.data(),1,valid.size(),file)==valid.size());
    assert(assetio::seek(file,0,"fixture"));
    unsigned char buffer[16]{};
    assert(assetio::read(file,buffer,sizeof(buffer),"fixture")==valid.size());
    assert(std::feof(file) && !std::memcmp(buffer,valid.data(),valid.size()));
    assert(assetio::seek(file,4,"fixture") && !std::feof(file));
    assert(assetio::read(file,buffer,1,"fixture")==1 && buffer[0]==0x20);
    assert(!assetio::seek(nullptr,0,"missing") && !assetio::read(nullptr,buffer,1,"missing"));
    std::fclose(file);
    std::puts("PASS: diagnostic and normal decoders agree; all rejection reasons, output guards, hashes and file errors verified");
}
