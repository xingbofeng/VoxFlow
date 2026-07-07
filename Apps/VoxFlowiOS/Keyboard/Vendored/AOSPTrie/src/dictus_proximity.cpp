// AOSP-inspired trie engine for Dictus. Apache 2.0.
#include "dictus_proximity.h"

#include <cmath>
#include <cstring>

namespace dictus {

ProximityMap::ProximityMap() {
    // Initialize all distances to 1.0 (maximum)
    for (int i = 0; i < 26; i++) {
        for (int j = 0; j < 26; j++) {
            distances_[i][j] = (i == j) ? 0.0f : 1.0f;
        }
    }
}

void ProximityMap::buildAZERTY() {
    // AZERTY key positions: (x, y) where x is column offset, y is row
    // Row 0 (y=0): a z e r t y u i o p
    // Row 1 (y=1): q s d f g h j k l m  (offset 0.25)
    // Row 2 (y=2): w x c v b n          (offset 0.75)

    // Map: letter -> index in positions array
    // We store positions for all 26 letters

    float positions[26][2];
    std::memset(positions, 0, sizeof(positions));

    // Row 0: a(0) z(1) e(2) r(3) t(4) y(5) u(6) i(7) o(8) p(9)
    auto set = [&](char c, float x, float y) {
        positions[c - 'a'][0] = x;
        positions[c - 'a'][1] = y;
    };

    set('a', 0.0f, 0.0f);
    set('z', 1.0f, 0.0f);
    set('e', 2.0f, 0.0f);
    set('r', 3.0f, 0.0f);
    set('t', 4.0f, 0.0f);
    set('y', 5.0f, 0.0f);
    set('u', 6.0f, 0.0f);
    set('i', 7.0f, 0.0f);
    set('o', 8.0f, 0.0f);
    set('p', 9.0f, 0.0f);

    // Row 1: q s d f g h j k l m (offset 0.25)
    set('q', 0.25f, 1.0f);
    set('s', 1.25f, 1.0f);
    set('d', 2.25f, 1.0f);
    set('f', 3.25f, 1.0f);
    set('g', 4.25f, 1.0f);
    set('h', 5.25f, 1.0f);
    set('j', 6.25f, 1.0f);
    set('k', 7.25f, 1.0f);
    set('l', 8.25f, 1.0f);
    set('m', 9.25f, 1.0f);

    // Row 2: w x c v b n (offset 0.75)
    set('w', 0.75f, 2.0f);
    set('x', 1.75f, 2.0f);
    set('c', 2.75f, 2.0f);
    set('v', 3.75f, 2.0f);
    set('b', 4.75f, 2.0f);
    set('n', 5.75f, 2.0f);

    // Compute distances: min(1.0, euclidean / 2.5)
    for (int i = 0; i < 26; i++) {
        for (int j = i; j < 26; j++) {
            if (i == j) {
                distances_[i][j] = 0.0f;
                continue;
            }
            float dx = positions[i][0] - positions[j][0];
            float dy = positions[i][1] - positions[j][1];
            float dist = std::sqrt(dx * dx + dy * dy) / 2.5f;
            if (dist > 1.0f) dist = 1.0f;
            distances_[i][j] = dist;
            distances_[j][i] = dist;
        }
    }
}

void ProximityMap::buildQWERTY() {
    // QWERTY key positions
    // Row 0 (y=0): q w e r t y u i o p
    // Row 1 (y=1): a s d f g h j k l  (offset 0.25)
    // Row 2 (y=2): z x c v b n m      (offset 0.75)

    float positions[26][2];
    std::memset(positions, 0, sizeof(positions));

    auto set = [&](char c, float x, float y) {
        positions[c - 'a'][0] = x;
        positions[c - 'a'][1] = y;
    };

    // Row 0
    set('q', 0.0f, 0.0f);
    set('w', 1.0f, 0.0f);
    set('e', 2.0f, 0.0f);
    set('r', 3.0f, 0.0f);
    set('t', 4.0f, 0.0f);
    set('y', 5.0f, 0.0f);
    set('u', 6.0f, 0.0f);
    set('i', 7.0f, 0.0f);
    set('o', 8.0f, 0.0f);
    set('p', 9.0f, 0.0f);

    // Row 1 (offset 0.25)
    set('a', 0.25f, 1.0f);
    set('s', 1.25f, 1.0f);
    set('d', 2.25f, 1.0f);
    set('f', 3.25f, 1.0f);
    set('g', 4.25f, 1.0f);
    set('h', 5.25f, 1.0f);
    set('j', 6.25f, 1.0f);
    set('k', 7.25f, 1.0f);
    set('l', 8.25f, 1.0f);

    // Row 2 (offset 0.75)
    set('z', 0.75f, 2.0f);
    set('x', 1.75f, 2.0f);
    set('c', 2.75f, 2.0f);
    set('v', 3.75f, 2.0f);
    set('b', 4.75f, 2.0f);
    set('n', 5.75f, 2.0f);
    set('m', 6.75f, 2.0f);

    // Compute distances: min(1.0, euclidean / 2.5)
    for (int i = 0; i < 26; i++) {
        for (int j = i; j < 26; j++) {
            if (i == j) {
                distances_[i][j] = 0.0f;
                continue;
            }
            float dx = positions[i][0] - positions[j][0];
            float dy = positions[i][1] - positions[j][1];
            float dist = std::sqrt(dx * dx + dy * dy) / 2.5f;
            if (dist > 1.0f) dist = 1.0f;
            distances_[i][j] = dist;
            distances_[j][i] = dist;
        }
    }
}

float ProximityMap::cost(uint16_t a, uint16_t b) const {
    // Lowercase
    if (a >= 'A' && a <= 'Z') a = a - 'A' + 'a';
    if (b >= 'A' && b <= 'Z') b = b - 'A' + 'a';

    if (a >= 'a' && a <= 'z' && b >= 'a' && b <= 'z') {
        return distances_[a - 'a'][b - 'a'];
    }
    return 1.0f;
}

} // namespace dictus
