#include "gamelog.hpp"
#ifdef DS_LOGGING
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <sys/stat.h>
#ifdef __NDS__
#include <nds.h>
#include <malloc.h>
#endif

extern "C" {
volatile unsigned logevents=0, logwrites=0, logfaults=0;
}
namespace gamelog {
static char path[256];
static const volatile unsigned* counter=nullptr;
static unsigned frames=0, written=0, detail=0;
static int view=-1, fade=-1, pack=-1, level=-1;
static const char* stage="startup";
static bool writing=false;
static constexpr unsigned limit=2*1024*1024;
unsigned now() { return counter?*counter:0; }
void clock(const volatile unsigned* value) { counter=value; }
void mark(const char* value,unsigned argument) { stage=value; detail=argument; }
void context(unsigned frame,int screen,int phase,int box,int map) {
    frames=frame; view=screen; fade=phase; pack=box; level=map;
}
static bool append(const char* text,unsigned size) {
    if (!path[0] || written+size>limit) return false;
    FILE* file=std::fopen(path,"ab");
    if (!file) return false;
    bool valid=std::fwrite(text,1,size,file)==size;
    valid=std::fflush(file)==0 && valid;
    valid=std::fclose(file)==0 && valid;
    if (valid) { written+=size; logwrites=logwrites+1; }
    return valid;
}
void event(const char* format,...) {
    if (writing) return;
    const int savederror=errno;
    writing=true;
    unsigned scanline=0,gpu=0,interrupts=0,enabled=0,bright=0,subbright=0,free=0;
#ifdef __NDS__
    scanline=REG_VCOUNT; gpu=GFX_STATUS; interrupts=REG_IME; enabled=REG_IE;
    bright=REG_MASTER_BRIGHT; subbright=REG_MASTER_BRIGHT_SUB;
    free=mallinfo().fordblks;
#endif
    char line[768];
    const int prefix=std::snprintf(line,sizeof(line),
        "%u f=%u vb=%u view=%d fade=%d box=%d level=%d stage=%s:%u y=%u gpu=%08x ime=%u ie=%08x bright=%04x/%04x heap=%u errno=%d ",
        static_cast<unsigned>(logevents),frames,now(),view,fade,pack,level,stage,detail,scanline,gpu,interrupts,enabled,bright,subbright,free,savederror);
    va_list arguments;
    va_start(arguments,format);
    if (prefix>0 && static_cast<unsigned>(prefix)<sizeof(line)-2)
        std::vsnprintf(line+prefix,sizeof(line)-prefix-1,format,arguments);
    va_end(arguments);
    const unsigned length=std::strlen(line);
    const unsigned size=length<sizeof(line)-2?length:sizeof(line)-2;
    line[size]='\n'; line[size+1]=0;
    logevents=logevents+1;
    if (path[0] && written<limit && !append(line,size+1)) {
        logfaults=logfaults+1;
        path[0]=0;
    }
#ifdef __NDS__
    if (!path[0] && prefix>0 && static_cast<unsigned>(prefix)<sizeof(line)-2) nocashMessage(line+prefix);
#endif
    writing=false;
    errno=savederror;
}
void initialize(const char* directory) {
    path[0]=0; written=0;
    if (directory) {
        for (unsigned index=1;index<=9999;++index) {
            const int size=std::snprintf(path,sizeof(path),"%s/game-%04u.log",directory,index);
            if (size<0 || static_cast<unsigned>(size)>=sizeof(path)) break;
            struct stat info{};
            if (stat(path,&info)==0) continue;
            if (errno!=ENOENT) break;
            FILE* file=std::fopen(path,"wb");
            if (!file) break;
            if (std::fclose(file)) break;
            event("SESSION build=" __DATE__ " " __TIME__ " log=%s",path);
            return;
        }
    }
    path[0]=0;
    logfaults=logfaults+1;
    event("LOG UNAVAILABLE; emulator messages only");
}
void fatal(const char* reason,unsigned value) {
    event("FATAL %s detail=%u",reason,value);
#ifdef __NDS__
    // No FAT or stdio calls from the hardware exception handler.
    char message[192];
    std::snprintf(message,sizeof(message),"%s\nStage: %s:%u\nSee /ctrdx/game-*.log",reason,stage,detail);
    libndsCrash(message);
#endif
}
void checkwait(unsigned started) {
    if (now()-started>600) fatal("Renderer wait exceeded ten seconds",detail);
}
}
#endif
