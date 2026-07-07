// AOSP-inspired trie engine for Dictus. Apache 2.0.
// ObjC++ implementation -- bridges C++ trie engine to ObjC for Swift interop.

#import "AOSPTrieBridge.h"

#include "dictus_trie.h"
#include "dictus_scorer.h"
#include "dictus_proximity.h"
#include "dictus_ngram.h"

#include <vector>

// ---------- AOSPTrieResult ----------

@implementation AOSPTrieResult
@end

// ---------- AOSPTrieBridge ----------

@implementation AOSPTrieBridge {
    dictus::Trie _trie;
    dictus::Scorer _scorer;
    dictus::ProximityMap _proximityMap;
    BOOL _loaded;
    dictus::NgramEngine* _ngramEngine;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _loaded = NO;
        _ngramEngine = new dictus::NgramEngine();
    }
    return self;
}

- (void)dealloc {
    _trie.unload();
    delete _ngramEngine;
}

- (BOOL)loadDictionaryAtPath:(NSString *)path {
    _trie.unload();
    _loaded = NO;

    bool success = _trie.loadMmap([path UTF8String]);
    if (success) {
        _scorer.setProximityMap(&_proximityMap);
        _loaded = YES;
    }
    return success ? YES : NO;
}

- (void)unloadDictionary {
    _trie.unload();
    _loaded = NO;
}

- (BOOL)isLoaded {
    return _loaded;
}

/// Helper: convert NSString to uint16_t buffer.
/// Returns the number of UTF-16 code units written.
static int convertString(NSString *str, uint16_t *buffer, int bufferSize) {
    NSUInteger len = [str length];
    if ((int)len > bufferSize) len = bufferSize;
    [str getCharacters:buffer range:NSMakeRange(0, len)];
    return (int)len;
}

- (nullable AOSPTrieResult *)spellCheck:(NSString *)word maxEditDistance:(float)maxDist {
    if (!_loaded || [word length] == 0) return nil;

    // Convert input word to UTF-16 buffer
    uint16_t inputBuf[256];
    int inputLen = convertString(word, inputBuf, 256);
    if (inputLen == 0) return nil;

    // Run correction
    std::vector<dictus::Candidate> candidates = _scorer.correct(
        _trie, inputBuf, inputLen, maxDist, 5
    );

    if (candidates.empty()) return nil;

    // Check if first result matches the input (word is correct)
    NSString *firstWord = [NSString stringWithUTF8String:candidates[0].word];
    if ([firstWord isEqualToString:word]) return nil;

    // Build result
    AOSPTrieResult *result = [[AOSPTrieResult alloc] init];
    result.correction = firstWord;
    result.score = candidates[0].score;

    NSMutableArray<NSString *> *alts = [NSMutableArray array];
    for (size_t i = 1; i < candidates.size() && i <= 2; i++) {
        NSString *alt = [NSString stringWithUTF8String:candidates[i].word];
        [alts addObject:alt];
    }
    result.alternatives = [alts copy];

    return result;
}

- (NSArray<NSString *> *)nearbyWords:(NSString *)word maxEditDistance:(float)maxDist maxResults:(NSUInteger)maxResults {
    if (!_loaded || [word length] == 0) return @[];

    uint16_t inputBuf[256];
    int inputLen = convertString(word, inputBuf, 256);
    if (inputLen == 0) return @[];

    std::vector<dictus::Candidate> candidates = _scorer.correct(
        _trie, inputBuf, inputLen, maxDist, (int)maxResults + 1
    );

    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:candidates.size()];
    for (const auto& c : candidates) {
        NSString *w = [NSString stringWithUTF8String:c.word];
        // Skip exact match — caller already knows the input word
        if (![w isEqualToString:word]) {
            [result addObject:w];
        }
        if ([result count] >= maxResults) break;
    }
    return [result copy];
}

- (BOOL)wordExists:(NSString *)word {
    if (!_loaded || [word length] == 0) return NO;

    uint16_t buf[256];
    int len = convertString(word, buf, 256);
    return _trie.wordExists(buf, len) ? YES : NO;
}

- (NSInteger)getFrequency:(NSString *)word {
    if (!_loaded || [word length] == 0) return 0;

    uint16_t buf[256];
    int len = convertString(word, buf, 256);
    return (NSInteger)_trie.getFrequency(buf, len);
}

- (NSUInteger)wordCount {
    if (!_loaded) return 0;
    return (NSUInteger)_trie.wordCount();
}

- (void)setProximityMapAZERTY {
    _proximityMap.buildAZERTY();
    if (_loaded) {
        _scorer.setProximityMap(&_proximityMap);
    }
}

- (void)setProximityMapQWERTY {
    _proximityMap.buildQWERTY();
    if (_loaded) {
        _scorer.setProximityMap(&_proximityMap);
    }
}

// --- N-gram prediction methods ---

- (BOOL)loadNgramsAtPath:(NSString *)path {
    _ngramEngine->unload();
    return _ngramEngine->load([path UTF8String]) ? YES : NO;
}

- (void)unloadNgrams {
    _ngramEngine->unload();
}

- (BOOL)ngramsLoaded {
    return _ngramEngine->isLoaded() ? YES : NO;
}

- (NSArray<NSString *> *)predictAfterWord:(NSString *)word maxResults:(NSUInteger)max {
    if (!_ngramEngine->isLoaded() || [word length] == 0) return @[];

    auto results = _ngramEngine->predictAfterWord([word UTF8String], (size_t)max);

    NSMutableArray<NSString *> *predictions = [NSMutableArray arrayWithCapacity:results.size()];
    for (const auto& r : results) {
        [predictions addObject:[NSString stringWithUTF8String:r.word.c_str()]];
    }
    return [predictions copy];
}

- (NSArray<NSString *> *)predictAfterWord1:(NSString *)word1 word2:(NSString *)word2 maxResults:(NSUInteger)max {
    if (!_ngramEngine->isLoaded() || [word1 length] == 0 || [word2 length] == 0) return @[];

    auto results = _ngramEngine->predictAfterWords(
        [word1 UTF8String], [word2 UTF8String], (size_t)max
    );

    NSMutableArray<NSString *> *predictions = [NSMutableArray arrayWithCapacity:results.size()];
    for (const auto& r : results) {
        [predictions addObject:[NSString stringWithUTF8String:r.word.c_str()]];
    }
    return [predictions copy];
}

- (uint16_t)bigramScoreForWord:(NSString *)word afterWord:(NSString *)prevWord {
    if (!_ngramEngine->isLoaded() || [word length] == 0 || [prevWord length] == 0) return 0;
    return _ngramEngine->bigramScore([prevWord UTF8String], [word UTF8String]);
}

@end
