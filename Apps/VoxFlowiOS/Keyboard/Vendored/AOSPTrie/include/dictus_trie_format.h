// AOSP-inspired trie engine for Dictus. Apache 2.0.
#ifndef DICTUS_TRIE_FORMAT_H
#define DICTUS_TRIE_FORMAT_H

#include <cstdint>

namespace dictus {

static constexpr char DICTUS_MAGIC[4] = {'D', 'T', 'R', 'I'};
static constexpr uint16_t DICTUS_VERSION = 1;
static constexpr uint32_t HEADER_SIZE = 32;

// Flag bit masks for trie node flags byte
static constexpr uint8_t FLAG_CHILDREN_SIZE_MASK = 0xC0; // bits 7-6: children pointer size
static constexpr uint8_t FLAG_MULTI_CHAR = 0x20;         // bit 5: has multiple characters
static constexpr uint8_t FLAG_TERMINAL = 0x10;            // bit 4: is terminal (word end)

// Children pointer size encoding (bits 7-6)
// 00 = no children (0 bytes), 01 = 2 bytes, 10 = 3 bytes, 11 = 4 bytes
static constexpr int childrenPtrSize(uint8_t flags) {
    static constexpr int sizes[] = {0, 2, 3, 4};
    return sizes[(flags & FLAG_CHILDREN_SIZE_MASK) >> 6];
}

#pragma pack(push, 1)
struct DictusHeader {
    char magic[4];          // "DTRI"
    uint16_t version;       // 1
    uint16_t flags;         // reserved
    uint32_t node_count;
    uint32_t word_count;
    uint32_t max_freq;
    uint8_t root_child_count; // number of top-level trie siblings
    uint8_t reserved[11];
};
#pragma pack(pop)

static_assert(sizeof(DictusHeader) == 32, "DictusHeader must be exactly 32 bytes");

} // namespace dictus

#endif // DICTUS_TRIE_FORMAT_H
