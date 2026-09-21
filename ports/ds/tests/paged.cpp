#include "paged.hpp"
#include "worldstore.hpp"
#include "upperbgstore.hpp"
#include <cassert>
#include <cstdio>
#include <string>
#include <vector>

template<std::size_t count>
void check(const char* current,const char* baseline,const char* name,const unsigned short (&pages)[count],unsigned shift,unsigned window) {
    FILE* original=std::fopen((std::string(baseline)+"/"+name+".bin").c_str(),"rb"); assert(original);
    std::fseek(original,0,SEEK_END); const unsigned size=std::ftell(original); std::rewind(original);
    std::vector<unsigned char> expected(size),output(window);
    assert(std::fread(expected.data(),1,size,original)==size); std::fclose(original);
    FILE* file=std::fopen((std::string(current)+"/"+name+".bin").c_str(),"rb"); assert(file);
    unsigned checks=0;
    auto read=[&](unsigned physical,void* target,unsigned bytes) {
        return !std::fseek(file,physical,SEEK_SET) && std::fread(target,1,bytes,file)==bytes;
    };
    for (unsigned offset=0;offset<size;offset+=4096) {
        const unsigned bytes=std::min(window,size-offset);
        assert(paged::read(pages,shift,offset,output.data(),bytes,read));
        assert(std::equal(output.begin(),output.begin()+bytes,expected.begin()+offset)); ++checks;
    }
    assert(!paged::read(pages,shift,count*(1u<<shift),output.data(),1,read));
    std::fclose(file);
    std::printf("PASS: %u %s scrolling windows match the retained raw backgrounds exactly\n",checks,name);
}
int main(int argc,char** argv) {
    assert(argc==3);
    check(argv[1],argv[2],"world",backgroundstore::worldpages,backgroundstore::worldshift,131072);
    check(argv[1],argv[2],"upperbg",backgroundstore::upperbgpages,backgroundstore::upperbgshift,256*208);
}
