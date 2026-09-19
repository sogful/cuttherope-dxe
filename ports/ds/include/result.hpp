#pragma once
#include <algorithm>
#include <cmath>

namespace ui {
struct resultframe {
    int score = 0, value = 0, row = 0;
    float alpha = 0, scorealpha = 0;
};
inline resultframe resultat(float time, int stars, int score, int ticks) {
    auto unit = [](float v) { return std::clamp(v, 0.0f, 1.0f); };
    resultframe state{};
    const int bonus = stars * 1000;
    state.value = bonus;
    state.alpha = state.scorealpha = unit((time - .8f) / .2f);
    if (time >= 1 && time < 2) { state.score = bonus * (time - 1); state.value = bonus * (2 - time); }
    else if (time >= 2 && time < 2.2f) { state.score = bonus; state.value = 0; state.alpha = 1 - (time - 2) / .2f; }
    else if (time >= 2.2f && time < 3.6f) {
        state.row = 1;
        const float ratio = unit(time - 2.4f);
        state.score = bonus + static_cast<int>((score - bonus) * ratio);
        state.value = std::lround(ticks * .016f * (1 - ratio));
        state.alpha = time < 2.4f ? (time - 2.2f) / .2f : time >= 3.4f ? 1 - (time - 3.4f) / .2f : 1;
    } else if (time >= 3.6f) { state.score = score; state.row = 2; state.alpha = unit((time - 3.6f) / .2f); }
    return state;
}
}
