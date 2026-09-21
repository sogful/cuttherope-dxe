#pragma once
#include <algorithm>
#include <cstddef>

namespace paged {
template<std::size_t count,class reader>
bool read(const unsigned short (&pages)[count],unsigned shift,unsigned offset,void* destination,unsigned bytes,reader&& transfer) {
    const unsigned size=1u<<shift;
    if (offset>count*size || bytes>count*size-offset) return false;
    auto* output=static_cast<unsigned char*>(destination);
    while (bytes) {
        unsigned page=offset>>shift;
        const unsigned inside=offset&(size-1),physical=pages[page]*size+inside;
        unsigned amount=std::min(bytes,size-inside);
        while (amount<bytes && page+1<count && pages[page+1]==pages[page]+1) {
            amount+=std::min(bytes-amount,size); ++page;
        }
        if (!transfer(physical,output,amount)) return false;
        output+=amount; offset+=amount; bytes-=amount;
    }
    return true;
}
}
