#pragma once
#include "interface.hpp"

namespace audio {
enum class voice { open, close, chewing, sad, excited, greeting, sleep1, sleep2, sleep3 };
void initialize();
void update(const ui::controller& menu);
void world(const ui::controller& menu, const dx::simulation& game);
void effect(const unsigned char* data, unsigned size);
bool speak(int costume, voice kind);
bool stream(int index);
unsigned voices();
unsigned lastvoice();
}
