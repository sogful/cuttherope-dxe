#include <nds.h>
#include <nds/arm9/dldi.h>
#include <fat.h>
#include <filesystem.h>
#include <sys/stat.h>
#include <cerrno>
#include <cstdio>
#include <cstdarg>
#include "bootassets.hpp"

extern "C" { volatile unsigned bootstate=0, bootfiles=0, booterror=0; }
static FILE* logfile=nullptr;
static unsigned char buffer[4096];

static void message(const char* format,...) {
    va_list arguments;
    va_start(arguments,format);
    std::vprintf(format,arguments);
    va_end(arguments);
    std::fflush(stdout);
    if (logfile) {
        va_start(arguments,format);
        std::vfprintf(logfile,format,arguments);
        va_end(arguments);
        std::fflush(logfile);
    }
}

static void stop(unsigned state,int error) {
    bootstate=state; booterror=error;
    message("\nSTOP %u, errno %d\nPhoto this screen.\n",state,error);
    if (logfile) { std::fclose(logfile); logfile=nullptr; }
    while (true) swiWaitForVBlank();
}

int main(int argc,char** argv) {
    defaultExceptionHandler();
    consoleDemoInit();
    bootstate=1;
    message("Cut the Rope DX boot probe\n\n1: main reached\nMode: %s\nargv: %s\nDLDI: %.48s\n",
        isDSiMode()?"DSi":"DS",argc>0?argv[0]:"missing",io_dldi_data->friendlyName);
    bootstate=2;
    message("2: mounting SD/FAT...\n");
    const bool storage=fatInitDefault();
    const int storageerror=errno;
    if (storage) {
        char path[192];
        std::snprintf(path,sizeof(path),"%sctrdx",fatGetDefaultDrive());
        mkdir(path,0777);
        std::snprintf(path,sizeof(path),"%sctrdx/boot.log",fatGetDefaultDrive());
        logfile=std::fopen(path,"ab");
        if (logfile) message("\nBoot probe: mode=%s\nargv=%s\nDLDI=%.48s\nLog: %s\n",
            isDSiMode()?"DSi":"DS",argc>0?argv[0]:"missing",io_dldi_data->friendlyName,path);
        else message("Log unavailable, errno %d\n",errno);
    } else message("SD/FAT unavailable, errno %d\n",storageerror);
    bootstate=3;
    message("3: mounting ROM NitroFS...\n");
    if (!nitroFSInit(nullptr)) stop(30,errno);
    message("NitroFS mounted.\n");
    bootstate=4;
    unsigned checks=0;
    for (const auto& sample:bootassets::samples) {
        consoleClear();
        message("4: reading ROM assets\n%s\noffset %u / %u\n",sample.name,sample.offset,sample.size);
        char path[96];
        std::snprintf(path,sizeof(path),"nitro:/%s",sample.name);
        FILE* file=std::fopen(path,"rb");
        if (!file) stop(40,errno);
        if (std::fseek(file,0,SEEK_END) || std::ftell(file)!=static_cast<long>(sample.size)) stop(41,errno);
        if (std::fseek(file,sample.offset,SEEK_SET) || std::fread(buffer,1,sample.count,file)!=sample.count) stop(42,errno);
        std::fclose(file);
        unsigned hash=2166136261u;
        for (unsigned i=0;i<sample.count;++i) hash=(hash^buffer[i])*16777619u;
        if (hash!=sample.hash) stop(43,0);
        bootfiles=++checks;
    }
    consoleClear();
    message("Cut the Rope DX boot probe\n\nPASS: loader + NitroFS\n%u asset samples match.\n\nThis does not test graphics,\nphysics, or full game memory.\n\n%s\nPhoto this screen.\n",
        checks,logfile?"Log: /ctrdx/boot.log":"No writable SD log.");
    if (logfile) { std::fclose(logfile); logfile=nullptr; }
    bootstate=5;
    while (true) swiWaitForVBlank();
}
