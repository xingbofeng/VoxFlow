// AOSP-inspired trie engine for Dictus. Apache 2.0.
#include "dictus_scorer.h"
#include "dictus_trie.h"
#include "dictus_trie_format.h"
#include "dictus_proximity.h"

#include <algorithm>
#include <cstring>

namespace dictus {

// --- Accent cost tables ---

static uint16_t accentBase(uint16_t c) {
    switch (c) {
        case 0x00E9: case 0x00E8: case 0x00EA: case 0x00EB: return 'e';
        case 0x00E0: case 0x00E2: return 'a';
        case 0x00F9: case 0x00FB: return 'u';
        case 0x00F4: return 'o';
        case 0x00EE: case 0x00EF: return 'i';
        case 0x00E7: return 'c';
        default: return 0;
    }
}

float Scorer::accentCost(uint16_t from, uint16_t to) {
    if (from == to) return 0.0f;

    uint16_t baseFrom = accentBase(from);
    uint16_t baseTo = accentBase(to);

    // Base letter to its accent variant = 0.15
    if (baseFrom == 0 && from >= 'a' && from <= 'z' && baseTo == from) return 0.15f;
    if (baseTo == 0 && to >= 'a' && to <= 'z' && baseFrom == to) return 0.15f;

    // Accent to different accent of same base = 0.2
    if (baseFrom != 0 && baseTo != 0 && baseFrom == baseTo) return 0.2f;

    return -1.0f;
}

// --- UTF-16 to UTF-8 ---

static void utf16ToUtf8(const uint16_t* src, int srcLen, char* dst, int dstSize) {
    int j = 0;
    for (int i = 0; i < srcLen && j < dstSize - 1; i++) {
        uint16_t c = src[i];
        if (c < 0x80) {
            dst[j++] = static_cast<char>(c);
        } else if (c < 0x800) {
            if (j + 2 > dstSize - 1) break;
            dst[j++] = static_cast<char>(0xC0 | (c >> 6));
            dst[j++] = static_cast<char>(0x80 | (c & 0x3F));
        } else {
            if (j + 3 > dstSize - 1) break;
            dst[j++] = static_cast<char>(0xE0 | (c >> 12));
            dst[j++] = static_cast<char>(0x80 | ((c >> 6) & 0x3F));
            dst[j++] = static_cast<char>(0x80 | (c & 0x3F));
        }
    }
    dst[j] = '\0';
}

// --- Scorer ---

Scorer::Scorer() : proximityMap_(nullptr) {}

void Scorer::setProximityMap(const ProximityMap* map) {
    proximityMap_ = map;
}

// Compute node byte size for sibling iteration.
static uint32_t computeNodeSize(const TrieNode& node) {
    uint32_t sz = 1; // flags
    if (node.flags & FLAG_MULTI_CHAR) sz += 1;
    sz += node.charCount * 2;
    if (node.flags & FLAG_TERMINAL) sz += 2;
    int ptrSize = childrenPtrSize(node.flags);
    if (ptrSize > 0) sz += 1 + ptrSize;
    return sz;
}

// Insert candidate maintaining sorted order (descending by score).
static void insertCandidate(std::vector<Candidate>& results, const Candidate& c, int maxResults) {
    auto it = std::lower_bound(results.begin(), results.end(), c,
        [](const Candidate& a, const Candidate& b) { return a.score > b.score; });
    if (static_cast<int>(results.size()) >= maxResults && it == results.end()) return;
    results.insert(it, c);
    if (static_cast<int>(results.size()) > maxResults) results.pop_back();
}

// Get substitution cost between two characters.
static float substitutionCost(uint16_t from, uint16_t to, const ProximityMap* proxMap) {
    float ac = Scorer::accentCost(from, to);
    if (ac >= 0.0f) return ac;
    if (proxMap) return std::max(0.2f, proxMap->cost(from, to));
    return 1.0f;
}

// Recursive search: explore all edit operations at each trie node.
// This function processes one trie node's characters against input,
// then recurses into children.
static void searchRecursive(const Trie& trie,
                            const TrieNode& node,
                            const uint16_t* input, int inputLen, int inputPos,
                            uint16_t* wordBuf, int wordLen,
                            float cost, float maxEditDist,
                            std::vector<Candidate>& results, int maxResults,
                            const ProximityMap* proxMap,
                            int nodeCharPos) {
    if (cost > maxEditDist) return;

    // We process characters of this node one at a time (nodeCharPos tracks position).
    // For patricia nodes with multiple chars, we must match/edit each char.

    if (nodeCharPos < node.charCount) {
        uint16_t trieChar;
        std::memcpy(&trieChar, &node.chars[nodeCharPos], 2);

        // 1. MATCH: input char == trie char
        if (inputPos < inputLen && input[inputPos] == trieChar) {
            wordBuf[wordLen] = trieChar;
            searchRecursive(trie, node, input, inputLen, inputPos + 1,
                            wordBuf, wordLen + 1, cost, maxEditDist,
                            results, maxResults, proxMap, nodeCharPos + 1);
        }

        // 2. SUBSTITUTION: input char != trie char
        if (inputPos < inputLen && input[inputPos] != trieChar) {
            float sc = substitutionCost(input[inputPos], trieChar, proxMap);
            if (cost + sc <= maxEditDist) {
                wordBuf[wordLen] = trieChar;
                searchRecursive(trie, node, input, inputLen, inputPos + 1,
                                wordBuf, wordLen + 1, cost + sc, maxEditDist,
                                results, maxResults, proxMap, nodeCharPos + 1);
            }
        }

        // 3. INSERTION: extra char in input (skip input char, stay on trie)
        if (inputPos < inputLen) {
            float ic = 1.0f;
            if (cost + ic <= maxEditDist) {
                searchRecursive(trie, node, input, inputLen, inputPos + 1,
                                wordBuf, wordLen, cost + ic, maxEditDist,
                                results, maxResults, proxMap, nodeCharPos);
            }
        }

        // 4. DELETION: missing char in input (advance trie, skip input)
        {
            float dc = 1.0f;
            if (cost + dc <= maxEditDist) {
                wordBuf[wordLen] = trieChar;
                searchRecursive(trie, node, input, inputLen, inputPos,
                                wordBuf, wordLen + 1, cost + dc, maxEditDist,
                                results, maxResults, proxMap, nodeCharPos + 1);
            }
        }

        // 5. TRANSPOSITION: swap of adjacent chars in input
        if (inputPos + 1 < inputLen && nodeCharPos + 1 < node.charCount) {
            uint16_t nextTrieChar;
            std::memcpy(&nextTrieChar, &node.chars[nodeCharPos + 1], 2);
            if (input[inputPos] == nextTrieChar && input[inputPos + 1] == trieChar) {
                float tc = 0.7f;
                if (cost + tc <= maxEditDist) {
                    wordBuf[wordLen] = trieChar;
                    wordBuf[wordLen + 1] = nextTrieChar;
                    searchRecursive(trie, node, input, inputLen, inputPos + 2,
                                    wordBuf, wordLen + 2, cost + tc, maxEditDist,
                                    results, maxResults, proxMap, nodeCharPos + 2);
                }
            }
        }

        return;
    }

    // All characters of this node have been consumed.
    // If terminal, compute score and possibly record candidate.
    if (node.flags & FLAG_TERMINAL) {
        // Remaining input chars would need to be inserted (extra chars)
        float remainCost = cost + static_cast<float>(inputLen - inputPos) * 1.0f;
        if (remainCost <= maxEditDist) {
            float maxFreqF = static_cast<float>(trie.maxFreq());
            float freqNorm = (maxFreqF > 0) ? static_cast<float>(node.frequency) / 65535.0f : 0.0f;
            float score = freqNorm * (1.0f - remainCost / maxEditDist);

            Candidate c;
            utf16ToUtf8(wordBuf, wordLen, c.word, sizeof(c.word));
            c.score = score;
            c.frequency = node.frequency;
            insertCandidate(results, c, maxResults);
        }
    }

    // Recurse into children
    int ptrSize = childrenPtrSize(node.flags);
    if (ptrSize > 0 && node.childCount > 0) {
        uint32_t childOff = node.childrenOffset;
        for (int ci = 0; ci < node.childCount; ci++) {
            if (childOff >= trie.fileSize()) break;
            TrieNode child = trie.readNode(childOff);
            if (child.charCount == 0) break;

            searchRecursive(trie, child, input, inputLen, inputPos,
                            wordBuf, wordLen, cost, maxEditDist,
                            results, maxResults, proxMap, 0);

            childOff += computeNodeSize(child);
        }
    }
}

std::vector<Candidate> Scorer::correct(const Trie& trie,
                                        const uint16_t* input, int inputLen,
                                        float maxEditDist,
                                        int maxResults) const {
    std::vector<Candidate> results;
    if (inputLen <= 0 || !trie.rootData()) return results;

    uint16_t wordBuf[128];

    // Root children start at HEADER_SIZE with known count from header.
    uint32_t offset = HEADER_SIZE;
    int rootCount = static_cast<int>(trie.rootChildCount());
    for (int ri = 0; ri < rootCount && offset < trie.fileSize(); ri++) {
        TrieNode node = trie.readNode(offset);
        if (node.charCount == 0) break;

        searchRecursive(trie, node, input, inputLen, 0,
                        wordBuf, 0, 0.0f, maxEditDist,
                        results, maxResults, proximityMap_, 0);

        offset += computeNodeSize(node);
    }

    return results;
}

// Note: the search() private method declared in the header is implemented via
// the correct() method above which uses the static searchRecursive function.
// The header declaration is kept for API compatibility but the recursive
// approach uses a static function instead.

void Scorer::search(const Trie& /*trie*/,
                    uint32_t /*nodeOffset*/, int /*childIndex*/, int /*childCount*/,
                    const uint16_t* /*input*/, int /*inputLen*/, int /*inputPos*/,
                    uint16_t* /*wordBuf*/, int /*wordLen*/,
                    float /*cost*/, float /*maxEditDist*/,
                    std::vector<Candidate>& /*results*/, int /*maxResults*/) const {
    // Implemented via searchRecursive static function called from correct().
}

} // namespace dictus
