#pragma once

namespace gamelog {
#ifdef DS_LOGGING
void initialize(const char* directory);
void clock(const volatile unsigned* counter);
void context(unsigned frame,int view,int fade,int pack,int level);
void event(const char* format,...) __attribute__((format(printf,1,2)));
#ifdef DS_PROFILE
template<typename... values> inline void trace(const char*,values...) {}
#else
template<typename... values> inline void trace(const char* format,values... arguments) { event(format,arguments...); }
#endif
void mark(const char* stage,unsigned detail=0);
void checkwait(unsigned started);
void fatal(const char* reason,unsigned detail=0);
unsigned now();
#else
inline void initialize(const char*) {}
inline void clock(const volatile unsigned*) {}
inline void context(unsigned,int,int,int,int) {}
inline void event(const char*,...) {}
template<typename... values> inline void trace(const char*,values...) {}
inline void mark(const char*,unsigned=0) {}
inline void checkwait(unsigned) {}
inline void fatal(const char*,unsigned=0) {}
inline unsigned now() { return 0; }
#endif
}
