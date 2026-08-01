// AOSP-inspired trie engine for Dictus. Apache 2.0.
#ifndef DICTUS_SCORER_H
#define DICTUS_SCORER_H

#include <cstdint>
#include <vector>

namespace dictus {

class Trie;
class ProximityMap;

/// A spell correction candidate with score.
struct Candidate {
    char word[128];     // UTF-8, null-terminated (avoids std::string allocation)
    float score;
    uint16_t frequency;
};

/// Weighted edit distance scorer for spell correction.
/// Traverses the trie with edit operations, using keyboard proximity
/// and accent-aware costs for substitutions.
class Scorer {
public:
    Scorer();

    /// Set the active keyboard proximity map.
    void setProximityMap(const ProximityMap* map);

    /// Find spell corrections for the input word.
    /// input: UTF-16 code units, inputLen: number of code units.
    /// maxEditDist: maximum cumulative edit cost (default 2.0).
    /// maxResults: maximum candidates to return (default 5).
    /// Returns candidates sorted by score descending.
    std::vector<Candidate> correct(const Trie& trie,
                                   const uint16_t* input, int inputLen,
                                   float maxEditDist = 2.0f,
                                   int maxResults = 5) const;

    /// Accent substitution cost. Returns >= 0 if accent pair, -1.0 otherwise.
    static float accentCost(uint16_t from, uint16_t to);

private:
    const ProximityMap* proximityMap_;

    void search(const Trie& trie,
                uint32_t nodeOffset, int childIndex, int childCount,
                const uint16_t* input, int inputLen, int inputPos,
                uint16_t* wordBuf, int wordLen,
                float cost, float maxEditDist,
                std::vector<Candidate>& results, int maxResults) const;
};

} // namespace dictus

#endif // DICTUS_SCORER_H
