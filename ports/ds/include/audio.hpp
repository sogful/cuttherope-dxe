#pragma once
#include "interface.hpp"

namespace audio {
enum class voice { open, close, chewing, sad, excited, greeting };
void initialize();
void update(const ui::controller& menu);
void world(const ui::controller& menu, const dx::simulation& game);
void effect(const unsigned char* data, unsigned size);
bool speak(int costume, voice kind);
unsigned voices();
unsigned lastvoice();
}
