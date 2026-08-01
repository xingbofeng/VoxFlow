// N-gram prediction engine for Dictus. Apache 2.0.
#ifndef DICTUS_NGRAM_H
#define DICTUS_NGRAM_H

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

namespace dictus {

/// Result from n-gram prediction: a word and its score.
struct NgramResult {
    std::string word;
    uint16_t score;
};

/// N-gram lookup engine using mmap'd binary data (NGRM format).
/// Supports bigram and trigram lookup with Stupid Backoff scoring.
class NgramEngine {
public:
    NgramEngine();
    ~NgramEngine();

    // Non-copyable
    NgramEngine(const NgramEngine&) = delete;
    NgramEngine& operator=(const NgramEngine&) = delete;

    /// Load n-gram binary file via mmap. Returns true on success.
    bool load(const char* path);

    /// Unload mmap'd data and release resources.
    void unload();

    /// Whether data is currently loaded.
    bool isLoaded() const;

    /// Predict top-N next words given one previous word (bigram lookup).
    /// Returns results sorted by score descending, up to maxResults.
    std::vector<NgramResult> predictAfterWord(const char* word, size_t maxResults) const;

    /// Predict top-N next words given two previous words (trigram + bigram backoff).
    /// Uses Stupid Backoff: try trigram first, then bigram with lambda=0.4 discount.
    /// Returns merged results sorted by score descending, up to maxResults.
    std::vector<NgramResult> predictAfterWords(const char* word1, const char* word2, size_t maxResults) const;

    /// Get n-gram score for a specific word following one previous word.
    /// Used for correction boosting. Returns 0 if no match.
    uint16_t bigramScore(const char* prevWord, const char* word) const;

    /// Get n-gram score for a specific word following two previous words.
    /// Returns 0 if no match.
    uint16_t trigramScore(const char* word1, const char* word2, const char* word) const;

private:
    uint8_t* data_;
    size_t dataSize_;
    bool loaded_;

    /// Index entry for fast binary search on entries.
    struct IndexEntry {
        uint32_t keyHash;
        const uint8_t* ptr;
    };

    /// Pre-built indices for bigram and trigram sections.
    std::vector<IndexEntry> bigramIndex_;
    std::vector<IndexEntry> trigramIndex_;

    /// Build index vectors by walking the bigram/trigram sections after mmap.
    void buildIndex(const uint8_t* section, uint32_t count, std::vector<IndexEntry>& index);

    /// FNV-1a 32-bit hash (must match Python implementation exactly).
    static uint32_t fnv1a(const uint8_t* bytes, size_t len);

    /// Lowercase a C string into a stack buffer. Returns length.
    static size_t toLower(const char* input, char* output, size_t maxLen);

    /// Binary search for a key_hash in a pre-built index.
    /// Returns pointer to the entry if found, nullptr otherwise.
    const uint8_t* findEntry(uint32_t keyHash, const std::vector<IndexEntry>& index) const;

    /// Parse results from an entry pointer into NgramResult vector.
    std::vector<NgramResult> parseResults(const uint8_t* entry, size_t maxResults) const;

    /// Get string from string table at given offset.
    const char* getString(uint32_t offset) const;
};

} // namespace dictus

#endif // DICTUS_NGRAM_H
