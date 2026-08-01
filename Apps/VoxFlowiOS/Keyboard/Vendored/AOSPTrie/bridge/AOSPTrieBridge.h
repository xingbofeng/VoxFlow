// AOSP-inspired trie engine for Dictus. Apache 2.0.
// ObjC bridge header -- exposes C++ trie engine to Swift via bridging header.
// No C++ types leak into this header so it can be imported from Swift.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Result from spell check. nil means word is correctly spelled.
@interface AOSPTrieResult : NSObject
@property (nonatomic, copy) NSString *correction;
@property (nonatomic, copy) NSArray<NSString *> *alternatives;
@property (nonatomic) float score;
@end

@interface AOSPTrieBridge : NSObject

- (BOOL)loadDictionaryAtPath:(NSString *)path;
- (void)unloadDictionary;
- (BOOL)isLoaded;

/// Returns nil if word is correctly spelled or not found.
/// Returns AOSPTrieResult with best correction, up to 2 alternatives, and score.
- (nullable AOSPTrieResult *)spellCheck:(NSString *)word maxEditDistance:(float)maxDist;

/// Returns nearby words (edit distance candidates) excluding the input word itself.
/// Unlike spellCheck, this does NOT return nil for correctly-spelled words.
/// Used by n-gram context boosting to find alternatives for valid-but-rare words.
- (NSArray<NSString *> *)nearbyWords:(NSString *)word maxEditDistance:(float)maxDist maxResults:(NSUInteger)maxResults;

/// Check if word exists in dictionary.
- (BOOL)wordExists:(NSString *)word;

/// Get frequency of word (0 if not found).
- (NSInteger)getFrequency:(NSString *)word;

/// Word count from the loaded dictionary header.
- (NSUInteger)wordCount;

/// Set keyboard layout for proximity scoring.
- (void)setProximityMapAZERTY;
- (void)setProximityMapQWERTY;

// --- N-gram prediction methods ---

/// Load n-gram binary file for next-word prediction.
- (BOOL)loadNgramsAtPath:(NSString *)path;

/// Unload n-gram data and release mmap'd memory.
- (void)unloadNgrams;

/// Whether n-gram data is loaded and ready for predictions.
- (BOOL)ngramsLoaded;

/// Predict top-N next words given one previous word (bigram lookup).
/// Returns array of NSString, sorted by score descending.
- (NSArray<NSString *> *)predictAfterWord:(NSString *)word maxResults:(NSUInteger)max;

/// Predict top-N next words given two previous words (trigram + bigram backoff).
/// Returns array of NSString, sorted by score descending.
- (NSArray<NSString *> *)predictAfterWord1:(NSString *)word1 word2:(NSString *)word2 maxResults:(NSUInteger)max;

/// Get bigram score for a specific word following a previous word (for correction boosting).
/// Returns 0 if no n-gram match found.
- (uint16_t)bigramScoreForWord:(NSString *)word afterWord:(NSString *)prevWord;

@end

NS_ASSUME_NONNULL_END
