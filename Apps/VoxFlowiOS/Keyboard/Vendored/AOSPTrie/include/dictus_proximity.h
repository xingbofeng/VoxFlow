// AOSP-inspired trie engine for Dictus. Apache 2.0.
#ifndef DICTUS_PROXIMITY_H
#define DICTUS_PROXIMITY_H

#include <cstdint>

namespace dictus {

/// Keyboard proximity map for weighted edit distance scoring.
/// Precomputes pairwise distances between a-z keys based on physical layout.
class ProximityMap {
public:
    ProximityMap();

    /// Build AZERTY layout proximity distances.
    void buildAZERTY();

    /// Build QWERTY layout proximity distances.
    void buildQWERTY();

    /// Get proximity cost between two characters.
    /// Returns value in [0.0, 1.0]. Lower = closer on keyboard.
    /// For non-letter characters, returns 1.0.
    float cost(uint16_t a, uint16_t b) const;

private:
    float distances_[26][26];

    void computeDistances(const float positions[][2], int count, const int charMap[]);
};

} // namespace dictus

#endif // DICTUS_PROXIMITY_H
