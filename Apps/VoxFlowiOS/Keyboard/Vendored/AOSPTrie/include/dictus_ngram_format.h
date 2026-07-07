// N-gram binary format for Dictus next-word prediction. Apache 2.0.
#ifndef DICTUS_NGRAM_FORMAT_H
#define DICTUS_NGRAM_FORMAT_H

#include <cstdint>

namespace dictus {

/// Magic bytes identifying an NGRM binary file.
static constexpr char NGRM_MAGIC[4] = {'N', 'G', 'R', 'M'};

/// Current format version.
static constexpr uint16_t NGRM_VERSION = 1;

/// Maximum number of prediction results stored per n-gram key.
/// Increased from 8 to 16 to accommodate both formal Wikipedia pairs and
/// colloquial seed bigrams (e.g., "pas" has ~8 formal pairs from Wikipedia
/// plus ~13 colloquial seeds — "pas mal", "pas du", etc. — that need to
/// survive the cap to unlock split validation in the keyboard).
/// File size grows ~50% per key (from max 8×6=48 bytes to max 16×6=96 bytes
/// per entry), but overall .dict files remain under 6 MiB per language.
static constexpr uint8_t NGRM_MAX_RESULTS = 16;

/// Header size in bytes.
static constexpr uint32_t NGRM_HEADER_SIZE = 32;

/// NGRM binary file header (32 bytes).
///
/// Layout:
///   [0..3]   magic:              "NGRM"
///   [4..5]   version:            uint16 LE (currently 1)
///   [6..7]   flags:              uint16 LE (reserved, 0)
///   [8..11]  bigram_count:       uint32 LE (number of bigram entries)
///   [12..15] trigram_count:      uint32 LE (number of trigram entries)
///   [16..19] bigram_offset:      uint32 LE (absolute byte offset to bigram section)
///   [20..23] trigram_offset:     uint32 LE (absolute byte offset to trigram section)
///   [24..27] string_table_offset:uint32 LE (absolute byte offset to string table)
///   [28..31] string_table_size:  uint32 LE (total bytes in string table)
///
/// Bigram/trigram section entries (variable-length, sorted by key_hash ascending):
///   key_hash:     uint32 LE  (FNV-1a 32-bit hash of key)
///   result_count: uint8      (1..NGRM_MAX_RESULTS)
///   results[result_count]:
///     word_offset: uint32 LE (byte offset into string table)
///     score:       uint16 LE (log-scaled 0..65535)
///
/// Bigram key = lowercase previous word (UTF-8 bytes).
/// Trigram key = "word1\0word2" (null-separated, both lowercase, UTF-8 bytes).
///
/// String table: packed null-terminated UTF-8 strings (all predicted words).
#pragma pack(push, 1)
struct NgramHeader {
    char magic[4];              // "NGRM"
    uint16_t version;           // 1
    uint16_t flags;             // reserved (0)
    uint32_t bigram_count;      // number of bigram entries
    uint32_t trigram_count;     // number of trigram entries
    uint32_t bigram_offset;     // absolute byte offset to bigram section
    uint32_t trigram_offset;    // absolute byte offset to trigram section
    uint32_t string_table_offset; // absolute byte offset to string table
    uint32_t string_table_size;   // total bytes in string table
};
#pragma pack(pop)

static_assert(sizeof(NgramHeader) == 32, "NgramHeader must be exactly 32 bytes");

/// Size of a single result entry: word_offset (4) + score (2) = 6 bytes.
static constexpr uint32_t NGRM_RESULT_ENTRY_SIZE = 6;

} // namespace dictus

#endif // DICTUS_NGRAM_FORMAT_H
