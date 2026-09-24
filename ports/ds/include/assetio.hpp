#pragma once
#include "gamelog.hpp"
#include "packed.hpp"
#include <cstdio>

namespace assetio {
constexpr unsigned padded(unsigned bytes) { return (bytes+31)&~31u; }
inline bool seek(FILE* file, unsigned offset, const char* name) {
    if (file && !std::fseek(file,offset,SEEK_SET)) return true;
    gamelog::event("asset.seek.failed name=%s offset=%u open=%d",name,offset,file!=nullptr);
    return false;
}
inline unsigned read(FILE* file, void* destination, unsigned bytes, const char* name) {
#ifdef DS_LOGGING
    const long position=file?std::ftell(file):-1;
#endif
    unsigned amount=0;
    for (int retry=0;file && amount<bytes;) {
        const unsigned received=std::fread(static_cast<unsigned char*>(destination)+amount,1,bytes-amount,file);
        amount+=received;
        if (received) continue;
        if (retry++>=2) break;
        const long current=std::ftell(file);
        std::clearerr(file);
        if (current<0 || std::fseek(file,current,SEEK_SET)) break;
    }
#ifdef DS_LOGGING
    if (amount!=bytes) gamelog::event("asset.read.short name=%s offset=%ld wanted=%u got=%u eof=%d error=%d",
        name,position,bytes,amount,file?std::feof(file):0,file?std::ferror(file):0);
#else
    (void)name;
#endif
    return amount;
}
template<class reader>
bool decode(reader& next, unsigned char* output, unsigned capacity, FILE* file, const char* name, unsigned id) {
#ifdef DS_LOGGING
    packed::diagnosis report;
    const bool valid=packed::stream<true>(next,output,capacity,&report);
    if (!valid) gamelog::event("asset.decode.failed name=%s id=%u reason=%s header=%08x consumed=%u produced=%u declared=%u capacity=%u length=%u distance=%u hash=%08x filepos=%ld eof=%d error=%d",
        name,id,report.reason,report.header,report.consumed,report.produced,report.declared,capacity,
        report.length,report.distance,report.hash,file?std::ftell(file):-1,file?std::feof(file):0,file?std::ferror(file):0);
    return valid;
#else
    (void)file; (void)name; (void)id;
    return packed::stream(next,output,capacity);
#endif
}
}
