#include <nds.h>
#include <cstdio>
int main() {
    consoleDemoInit();
    std::printf("DS compiler and emulator probe\n");
    while (true) swiWaitForVBlank();
}
