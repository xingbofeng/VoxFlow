// DictusCore/Sources/DictusCore/Languages/English.swift
// English language profile. Mirrors the data previously hardcoded in
// AOSPTrieEngine and SupportedLanguage.
import Foundation

/// English (`en`).
public let englishProfile = LanguageProfile(
    code: "en",
    displayName: "English",
    shortCode: "EN",
    defaultLayout: .qwerty,
    spaceName: "space",
    returnName: "return",
    overrides: [
        // Only unambiguous contractions — words that are NOT valid English on their own.
        // Excluded: "were" (we're), "well" (we'll), "wed" (we'd), "ill" (I'll),
        // "id" (I'd), "hell" (he'll), "hed" (he'd), "shed" (she'd), "shell" (she'll),
        // "its" (it's), "lets" (let's), "wont" (won't) — all valid standalone words.
        "im": "i'm",
        "ive": "i've",
        "dont": "don't",
        "doesnt": "doesn't",
        "didnt": "didn't",
        "cant": "can't",
        "couldnt": "couldn't",
        "wouldnt": "wouldn't",
        "shouldnt": "shouldn't",
        "wasnt": "wasn't",
        "isnt": "isn't",
        "arent": "aren't",
        "werent": "weren't",
        "hasnt": "hasn't",
        "havent": "haven't",
        "hadnt": "hadn't",
        "youre": "you're",
        "youve": "you've",
        "youll": "you'll",
        "youd": "you'd",
        "theyre": "they're",
        "theyve": "they've",
        "theyll": "they'll",
        "theyd": "they'd",
        "weve": "we've",
        "hes": "he's",
        "shes": "she's",
        "itll": "it'll",
        "thats": "that's",
        "thatll": "that'll",
        "whats": "what's",
        "whos": "who's",
        "wholl": "who'll",
        "theres": "there's",
        "heres": "here's",
    ],
    accentMap: [:],         // English has no diacritics that AccentExpander handles.
    contractionPrefixes: [] // English contractions are handled via the override map.
)
