// N-gram prediction engine for Dictus. Apache 2.0.
#include "dictus_ngram.h"
#include "dictus_ngram_format.h"

#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace dictus {

// --- Constructor / Destructor ---

NgramEngine::NgramEngine() : data_(nullptr), dataSize_(0), loaded_(false) {}

NgramEngine::~NgramEngine() {
    unload();
}

// --- Load / Unload ---

bool NgramEngine::load(const char* path) {
    unload();

    int fd = open(path, O_RDONLY);
    if (fd < 0) return false;

    struct stat st;
    if (fstat(fd, &st) != 0) {
        close(fd);
        return false;
    }

    size_t fileSize = static_cast<size_t>(st.st_size);
    if (fileSize < NGRM_HEADER_SIZE) {
        close(fd);
        return false;
    }

    void* mapped = mmap(nullptr, fileSize, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);

    if (mapped == MAP_FAILED) {
        return false;
    }

    madvise(mapped, fileSize, MADV_RANDOM);

    data_ = static_cast<uint8_t*>(mapped);
    dataSize_ = fileSize;

    // Validate header
    const auto* hdr = reinterpret_cast<const NgramHeader*>(data_);
    if (std::memcmp(hdr->magic, NGRM_MAGIC, 4) != 0) {
        unload();
        return false;
    }
    if (hdr->version != NGRM_VERSION) {
        unload();
        return false;
    }

    // Validate offsets are within file bounds
    if (hdr->bigram_offset > dataSize_ || hdr->trigram_offset > dataSize_ ||
        hdr->string_table_offset > dataSize_) {
        unload();
        return false;
    }

    // Build lookup indices
    if (hdr->bigram_count > 0 && hdr->bigram_offset < dataSize_) {
        buildIndex(data_ + hdr->bigram_offset, hdr->bigram_count, bigramIndex_);
    }
    if (hdr->trigram_count > 0 && hdr->trigram_offset < dataSize_) {
        buildIndex(data_ + hdr->trigram_offset, hdr->trigram_count, trigramIndex_);
    }

    loaded_ = true;
    return true;
}

void NgramEngine::unload() {
    bigramIndex_.clear();
    trigramIndex_.clear();

    if (data_) {
        munmap(data_, dataSize_);
        data_ = nullptr;
    }
    dataSize_ = 0;
    loaded_ = false;
}

bool NgramEngine::isLoaded() const {
    return loaded_;
}

// --- Index building ---

void NgramEngine::buildIndex(const uint8_t* section, uint32_t count,
                             std::vector<IndexEntry>& index) {
    index.clear();
    index.reserve(count);

    const uint8_t* p = section;
    const uint8_t* end = data_ + dataSize_;

    for (uint32_t i = 0; i < count; i++) {
        if (p + 5 > end) break;  // minimum: key_hash(4) + result_count(1)

        IndexEntry entry;
        std::memcpy(&entry.keyHash, p, 4);
        entry.ptr = p;
        index.push_back(entry);

        // Advance past this entry: key_hash(4) + result_count(1) + results
        uint8_t resultCount = p[4];
        size_t entrySize = 4 + 1 + static_cast<size_t>(resultCount) * NGRM_RESULT_ENTRY_SIZE;
        p += entrySize;
    }
}

// --- FNV-1a hash ---

uint32_t NgramEngine::fnv1a(const uint8_t* bytes, size_t len) {
    uint32_t h = 0x811c9dc5;
    for (size_t i = 0; i < len; i++) {
        h ^= bytes[i];
        h *= 0x01000193;
    }
    return h;
}

// --- Lowercase utility ---

size_t NgramEngine::toLower(const char* input, char* output, size_t maxLen) {
    size_t len = 0;
    while (input[len] != '\0' && len < maxLen - 1) {
        char c = input[len];
        // ASCII lowercase only (n-gram keys are already normalized in binary)
        if (c >= 'A' && c <= 'Z') {
            output[len] = c + ('a' - 'A');
        } else {
            output[len] = c;
        }
        len++;
    }
    output[len] = '\0';
    return len;
}

// --- Binary search ---

const uint8_t* NgramEngine::findEntry(uint32_t keyHash,
                                      const std::vector<IndexEntry>& index) const {
    if (index.empty()) return nullptr;

    // Binary search on sorted key_hash values
    size_t lo = 0;
    size_t hi = index.size();

    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (index[mid].keyHash < keyHash) {
            lo = mid + 1;
        } else if (index[mid].keyHash > keyHash) {
            hi = mid;
        } else {
            return index[mid].ptr;
        }
    }
    return nullptr;
}

// --- Parse results ---

std::vector<NgramResult> NgramEngine::parseResults(const uint8_t* entry,
                                                    size_t maxResults) const {
    std::vector<NgramResult> results;
    if (!entry) return results;

    // Entry layout: key_hash(4) + result_count(1) + results[](word_offset(4) + score(2))
    uint8_t resultCount = entry[4];
    if (resultCount > NGRM_MAX_RESULTS) resultCount = NGRM_MAX_RESULTS;

    const uint8_t* p = entry + 5;  // skip key_hash + result_count
    const uint8_t* end = data_ + dataSize_;

    size_t limit = std::min(static_cast<size_t>(resultCount), maxResults);
    results.reserve(limit);

    for (size_t i = 0; i < limit; i++) {
        if (p + NGRM_RESULT_ENTRY_SIZE > end) break;

        uint32_t wordOffset;
        uint16_t score;
        std::memcpy(&wordOffset, p, 4);
        std::memcpy(&score, p + 4, 2);
        p += NGRM_RESULT_ENTRY_SIZE;

        const char* str = getString(wordOffset);
        if (str) {
            NgramResult r;
            r.word = str;
            r.score = score;
            results.push_back(std::move(r));
        }
    }

    return results;
}

// --- String table access ---

const char* NgramEngine::getString(uint32_t offset) const {
    if (!data_) return nullptr;

    const auto* hdr = reinterpret_cast<const NgramHeader*>(data_);
    uint32_t absOffset = hdr->string_table_offset + offset;

    if (absOffset >= dataSize_) return nullptr;

    // Ensure string is null-terminated within bounds
    const char* str = reinterpret_cast<const char*>(data_ + absOffset);
    const char* end = reinterpret_cast<const char*>(data_ + dataSize_);

    // Quick bounds check: verify there's a null terminator before end of file
    const char* p = str;
    while (p < end && *p != '\0') p++;
    if (p >= end) return nullptr;

    return str;
}

// --- Prediction API ---

std::vector<NgramResult> NgramEngine::predictAfterWord(const char* word,
                                                        size_t maxResults) const {
    if (!loaded_ || !word) return {};

    // Lowercase the input word
    char lowBuf[256];
    size_t len = toLower(word, lowBuf, sizeof(lowBuf));
    if (len == 0) return {};

    // Hash and look up in bigram index
    uint32_t keyHash = fnv1a(reinterpret_cast<const uint8_t*>(lowBuf), len);
    const uint8_t* entry = findEntry(keyHash, bigramIndex_);

    return parseResults(entry, maxResults);
}

std::vector<NgramResult> NgramEngine::predictAfterWords(const char* word1,
                                                         const char* word2,
                                                         size_t maxResults) const {
    if (!loaded_ || !word1 || !word2) return {};

    // Lowercase both words
    char low1[256], low2[256];
    size_t len1 = toLower(word1, low1, sizeof(low1));
    size_t len2 = toLower(word2, low2, sizeof(low2));
    if (len1 == 0 || len2 == 0) return {};

    // Build trigram key: "word1\0word2" (null byte separator)
    char trigramKey[512];
    if (len1 + 1 + len2 > sizeof(trigramKey)) return {};
    std::memcpy(trigramKey, low1, len1);
    trigramKey[len1] = '\0';
    std::memcpy(trigramKey + len1 + 1, low2, len2);
    size_t trigramKeyLen = len1 + 1 + len2;

    uint32_t trigramHash = fnv1a(reinterpret_cast<const uint8_t*>(trigramKey), trigramKeyLen);
    const uint8_t* trigramEntry = findEntry(trigramHash, trigramIndex_);

    // Try bigram for word2 as well (for Stupid Backoff)
    uint32_t bigramHash = fnv1a(reinterpret_cast<const uint8_t*>(low2), len2);
    const uint8_t* bigramEntry = findEntry(bigramHash, bigramIndex_);

    if (trigramEntry && bigramEntry) {
        // Both found: merge trigram results with discounted bigram results
        auto trigramResults = parseResults(trigramEntry, NGRM_MAX_RESULTS);
        auto bigramResults = parseResults(bigramEntry, NGRM_MAX_RESULTS);

        // Apply Stupid Backoff discount (lambda = 0.4) to bigram scores
        for (auto& r : bigramResults) {
            r.score = static_cast<uint16_t>(static_cast<uint32_t>(r.score) * 4 / 10);
        }

        // Merge: trigram results take priority for same word
        std::vector<NgramResult> merged;
        merged.reserve(trigramResults.size() + bigramResults.size());
        merged.insert(merged.end(), trigramResults.begin(), trigramResults.end());

        // Add bigram results that don't duplicate trigram words
        for (const auto& br : bigramResults) {
            bool duplicate = false;
            for (const auto& tr : trigramResults) {
                if (tr.word == br.word) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) {
                merged.push_back(br);
            }
        }

        // Sort by score descending
        std::sort(merged.begin(), merged.end(),
                  [](const NgramResult& a, const NgramResult& b) {
                      return a.score > b.score;
                  });

        // Cap to maxResults
        if (merged.size() > maxResults) {
            merged.resize(maxResults);
        }
        return merged;

    } else if (trigramEntry) {
        // Only trigram found
        return parseResults(trigramEntry, maxResults);

    } else if (bigramEntry) {
        // Fallback to bigram with Stupid Backoff discount
        auto results = parseResults(bigramEntry, maxResults);
        for (auto& r : results) {
            r.score = static_cast<uint16_t>(static_cast<uint32_t>(r.score) * 4 / 10);
        }
        return results;

    }

    return {};
}

// --- Scoring API ---

uint16_t NgramEngine::bigramScore(const char* prevWord, const char* word) const {
    if (!loaded_ || !prevWord || !word) return 0;

    char lowPrev[256];
    size_t prevLen = toLower(prevWord, lowPrev, sizeof(lowPrev));
    if (prevLen == 0) return 0;

    uint32_t keyHash = fnv1a(reinterpret_cast<const uint8_t*>(lowPrev), prevLen);
    const uint8_t* entry = findEntry(keyHash, bigramIndex_);
    if (!entry) return 0;

    // Lowercase target word for comparison
    char lowWord[256];
    toLower(word, lowWord, sizeof(lowWord));

    // Scan results for matching word
    uint8_t resultCount = entry[4];
    if (resultCount > NGRM_MAX_RESULTS) resultCount = NGRM_MAX_RESULTS;

    const uint8_t* p = entry + 5;
    const uint8_t* end = data_ + dataSize_;

    for (uint8_t i = 0; i < resultCount; i++) {
        if (p + NGRM_RESULT_ENTRY_SIZE > end) break;

        uint32_t wordOffset;
        uint16_t score;
        std::memcpy(&wordOffset, p, 4);
        std::memcpy(&score, p + 4, 2);
        p += NGRM_RESULT_ENTRY_SIZE;

        const char* str = getString(wordOffset);
        if (str && std::strcmp(str, lowWord) == 0) {
            return score;
        }
    }

    return 0;
}

uint16_t NgramEngine::trigramScore(const char* word1, const char* word2,
                                    const char* word) const {
    if (!loaded_ || !word1 || !word2 || !word) return 0;

    char low1[256], low2[256];
    size_t len1 = toLower(word1, low1, sizeof(low1));
    size_t len2 = toLower(word2, low2, sizeof(low2));
    if (len1 == 0 || len2 == 0) return 0;

    // Build trigram key
    char trigramKey[512];
    if (len1 + 1 + len2 > sizeof(trigramKey)) return 0;
    std::memcpy(trigramKey, low1, len1);
    trigramKey[len1] = '\0';
    std::memcpy(trigramKey + len1 + 1, low2, len2);
    size_t trigramKeyLen = len1 + 1 + len2;

    uint32_t keyHash = fnv1a(reinterpret_cast<const uint8_t*>(trigramKey), trigramKeyLen);
    const uint8_t* entry = findEntry(keyHash, trigramIndex_);
    if (!entry) return 0;

    // Lowercase target word
    char lowWord[256];
    toLower(word, lowWord, sizeof(lowWord));

    // Scan results
    uint8_t resultCount = entry[4];
    if (resultCount > NGRM_MAX_RESULTS) resultCount = NGRM_MAX_RESULTS;

    const uint8_t* p = entry + 5;
    const uint8_t* end = data_ + dataSize_;

    for (uint8_t i = 0; i < resultCount; i++) {
        if (p + NGRM_RESULT_ENTRY_SIZE > end) break;

        uint32_t wordOffset;
        uint16_t score;
        std::memcpy(&wordOffset, p, 4);
        std::memcpy(&score, p + 4, 2);
        p += NGRM_RESULT_ENTRY_SIZE;

        const char* str = getString(wordOffset);
        if (str && std::strcmp(str, lowWord) == 0) {
            return score;
        }
    }

    return 0;
}

} // namespace dictus
