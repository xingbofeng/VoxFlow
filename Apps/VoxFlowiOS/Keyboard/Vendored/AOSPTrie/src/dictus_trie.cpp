// AOSP-inspired trie engine for Dictus. Apache 2.0.
#include "dictus_trie.h"
#include "dictus_trie_format.h"

#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace dictus {

Trie::Trie() : data_(nullptr), size_(0), fd_(-1) {}

Trie::~Trie() {
    unload();
}

bool Trie::loadMmap(const char* path) {
    unload();

    fd_ = open(path, O_RDONLY);
    if (fd_ < 0) return false;

    struct stat st;
    if (fstat(fd_, &st) != 0) {
        close(fd_);
        fd_ = -1;
        return false;
    }
    size_ = static_cast<size_t>(st.st_size);

    if (size_ < HEADER_SIZE) {
        close(fd_);
        fd_ = -1;
        size_ = 0;
        return false;
    }

    void* mapped = mmap(nullptr, size_, PROT_READ, MAP_PRIVATE, fd_, 0);
    if (mapped == MAP_FAILED) {
        close(fd_);
        fd_ = -1;
        size_ = 0;
        return false;
    }

    madvise(mapped, size_, MADV_RANDOM);
    data_ = static_cast<const uint8_t*>(mapped);

    // Validate header
    const auto* hdr = reinterpret_cast<const DictusHeader*>(data_);
    if (std::memcmp(hdr->magic, DICTUS_MAGIC, 4) != 0) {
        unload();
        return false;
    }
    if (hdr->version != DICTUS_VERSION) {
        unload();
        return false;
    }

    return true;
}

void Trie::unload() {
    if (data_) {
        munmap(const_cast<uint8_t*>(data_), size_);
        data_ = nullptr;
    }
    if (fd_ >= 0) {
        close(fd_);
        fd_ = -1;
    }
    size_ = 0;
}

bool Trie::wordExists(const uint16_t* chars, int len) const {
    return traverse(chars, len) > 0;
}

uint16_t Trie::getFrequency(const uint16_t* chars, int len) const {
    return traverse(chars, len);
}

const uint8_t* Trie::rootData() const {
    return data_ ? data_ + HEADER_SIZE : nullptr;
}

uint32_t Trie::maxFreq() const {
    if (!data_) return 0;
    return reinterpret_cast<const DictusHeader*>(data_)->max_freq;
}

uint32_t Trie::wordCount() const {
    if (!data_) return 0;
    return reinterpret_cast<const DictusHeader*>(data_)->word_count;
}

uint8_t Trie::rootChildCount() const {
    if (!data_) return 0;
    return reinterpret_cast<const DictusHeader*>(data_)->root_child_count;
}

size_t Trie::fileSize() const {
    return size_;
}

TrieNode Trie::readNode(uint32_t pos) const {
    TrieNode node;
    node.flags = 0;
    node.chars = nullptr;
    node.charCount = 0;
    node.frequency = 0;
    node.childrenOffset = 0;
    node.childCount = 0;

    if (!data_ || pos >= size_) return node;

    const uint8_t* p = data_ + pos;
    const uint8_t* end = data_ + size_;

    node.flags = *p++;

    // Character count
    bool multiChar = (node.flags & FLAG_MULTI_CHAR) != 0;
    if (multiChar) {
        if (p >= end) return node;
        node.charCount = *p++;
    } else {
        node.charCount = 1;
    }

    // Characters (UTF-16 LE)
    if (p + node.charCount * 2 > end) return node;
    node.chars = reinterpret_cast<const uint16_t*>(p);
    p += node.charCount * 2;

    // Frequency (only if terminal)
    if (node.flags & FLAG_TERMINAL) {
        if (p + 2 > end) return node;
        std::memcpy(&node.frequency, p, 2);
        p += 2;
    }

    // Children offset and count
    int ptrSize = childrenPtrSize(node.flags);
    if (ptrSize > 0) {
        if (p >= end) return node;
        node.childCount = *p++;

        if (p + ptrSize > end) return node;
        node.childrenOffset = 0;
        std::memcpy(&node.childrenOffset, p, ptrSize);
    }

    return node;
}

uint16_t Trie::traverse(const uint16_t* chars, int len) const {
    if (!data_ || len <= 0) return 0;

    // Root is virtual (not stored). Root child count is in header byte 20.
    // Children at each level are stored contiguously in the DFS layout.

    int inputPos = 0;
    uint32_t searchOffset = HEADER_SIZE;
    int siblingCount = static_cast<int>(rootChildCount());

    while (inputPos < len) {
        bool found = false;
        uint32_t offset = searchOffset;
        int siblingsChecked = 0;

        while (offset < size_ && siblingsChecked < siblingCount) {
            TrieNode node = readNode(offset);
            if (node.charCount == 0) break; // invalid

            // Check if this node's characters match input at inputPos
            bool matches = true;
            int matchLen = node.charCount;
            if (inputPos + matchLen > len) {
                // Input is shorter than this node's chars -- no match
                matches = false;
            } else {
                for (int i = 0; i < matchLen; i++) {
                    uint16_t nc;
                    std::memcpy(&nc, &node.chars[i], 2);
                    if (nc != chars[inputPos + i]) {
                        matches = false;
                        break;
                    }
                }
            }

            if (matches) {
                inputPos += matchLen;
                if (inputPos == len) {
                    // Consumed all input -- check if terminal
                    return (node.flags & FLAG_TERMINAL) ? node.frequency : 0;
                }
                // Continue into children
                int ptrSize = childrenPtrSize(node.flags);
                if (ptrSize == 0 || node.childCount == 0) {
                    return 0; // no children but input remaining
                }
                searchOffset = node.childrenOffset;
                siblingCount = node.childCount;
                found = true;
                break;
            }

            // Advance to next sibling -- compute this node's byte size
            uint32_t nodeSize = 1; // flags
            if (node.flags & FLAG_MULTI_CHAR) nodeSize += 1; // char_count
            nodeSize += node.charCount * 2;
            if (node.flags & FLAG_TERMINAL) nodeSize += 2;
            int ptrSize = childrenPtrSize(node.flags);
            if (ptrSize > 0) nodeSize += 1 + ptrSize; // child_count + ptr
            offset += nodeSize;
            siblingsChecked++;
        }

        if (!found) return 0;
    }

    return 0;
}

} // namespace dictus
