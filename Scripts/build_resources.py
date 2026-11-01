#!/usr/bin/env python3
"""Builds the AutoType dictionary resources from public corpora.

Sources (cached under Scripts/.cache):
  * persian-wikipedia.txt / rira-classic-poems.txt
        behnam/persian-words-frequency (MIT-ish community corpus)
        -> Persian words with corpus frequency counts.
  * /usr/share/dict/web2
        macOS system dictionary -> English word list.
  * Scripts/tech-terms.txt
        hand-maintained list of technical / product vocabulary that the
        system dictionary does not know about.

Outputs (Sources/AutoTypeCore/Resources):
  * persian-lexicon.tsv   "word\tfrequency" for every Persian word, frequency desc.
  * english-lexicon.txt   one lowercase English word per line.

Both outputs are sorted by UTF-8 byte order so the Swift loader can binary
search them without holding every word in memory as a Swift String.
"""

from __future__ import annotations

import os
import sys
import unicodedata
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "Scripts", ".cache")
OUT = os.path.join(ROOT, "Sources", "AutoTypeCore", "Resources")

# How many of the most frequent Persian words count as "common". These are the
# words that give a conversion decision strong positive evidence.
COMMON_PERSIAN_WORDS = 60000

ARABIC_YEH = "ي"       # ARABIC LETTER YEH
FARSI_YEH = "ی"        # FARSI YEH
ARABIC_KAF = "ك"       # ARABIC LETTER KAF
FARSI_KAF = "ک"        # KEHEH
TATWEEL = "ـ"          # ARABIC TATWEEL
ZWNJ = "‌"        # ZERO WIDTH NON-JOINER
ZWJ = "‍"         # ZERO WIDTH JOINER

PERSIAN_LETTERS = set("ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهیءأإآؤئٱٲٳٴٵى")

# Persian characters that may legitimately appear inside a word.
PERSIAN_EXTRA = set(ZWNJ)


def normalize_persian(word: str) -> str:
    """Canonicalises Persian orthography so lookups are stable."""
    word = word.replace(ARABIC_YEH, FARSI_YEH)
    word = word.replace(ARABIC_KAF, FARSI_KAF)
    word = word.replace(TATWEEL, "")
    word = word.replace(ZWJ, ZWNJ)
    # Arabic/Persian digit characters -> ASCII digits are not applied here;
    # digits are handled separately by the engine.
    return word


def is_persian_word(word: str) -> bool:
    if not word:
        return False
    for ch in word:
        if ch in PERSIAN_LETTERS or ch in PERSIAN_EXTRA:
            continue
        return False
    # Must contain at least one real letter.
    return any(ch in PERSIAN_LETTERS for ch in word)


def parse_frequency_file(path: str) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                continue
            word, raw = parts[0], parts[1]
            try:
                count = int(raw)
            except ValueError:
                continue
            word = normalize_persian(word.strip())
            if not is_persian_word(word):
                continue
            counts[word] += count
    return counts


def load_english() -> tuple[set[str], set[str]]:
    """Returns (all words, common words)."""
    words: set[str] = set()
    common: set[str] = set()
    source = "/usr/share/dict/web2"
    if os.path.exists(source):
        with open(source, "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                word = line.strip().lower()
                if not word or not word.isascii():
                    continue
                if not word.replace("'", "").replace("-", "").isalpha():
                    continue
                if not word.isalpha() and "'" not in word and "-" not in word:
                    continue
                words.add(word)
    tech = os.path.join(ROOT, "Scripts", "tech-terms.txt")
    if os.path.exists(tech):
        with open(tech, "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                word = line.strip().lower()
                if not word or word.startswith("#"):
                    continue
                if word.isascii() and word.isalpha():
                    words.add(word)
                    common.add(word)
    frequent = os.path.join(CACHE, "google-10000-english.txt")
    if os.path.exists(frequent):
        with open(frequent, "r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                word = line.strip().lower()
                if word and word.isascii() and word.isalpha():
                    words.add(word)
                    common.add(word)
    return words, common


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)

    # Wikipedia is a general-purpose corpus, so its counts drive the
    # "commonness" ranking. The poetry corpus only contributes vocabulary:
    # its counts are far too skewed to rank everyday words.
    wiki: dict[str, int] = defaultdict(int)
    for cache_name in ("persian-wikipedia.txt",):
        path = os.path.join(CACHE, cache_name)
        if not os.path.exists(path):
            print(f"missing cached source: {path}", file=sys.stderr)
            return 1
        for word, count in parse_frequency_file(path).items():
            wiki[word] += count

    vocabulary: dict[str, int] = defaultdict(int)
    for word, count in wiki.items():
        vocabulary[word] += count
    poems_path = os.path.join(CACHE, "rira-classic-poems.txt")
    if os.path.exists(poems_path):
        for word in parse_frequency_file(poems_path):
            vocabulary[word] += 0

    # Canonical form per ZWNJ-stripped key: keep the spelling with the highest
    # Wikipedia frequency so that "می رود" resolves to the correctly joined
    # "می‌رود".
    canonical: dict[str, tuple[str, int]] = {}
    for word, count in vocabulary.items():
        key = word.replace(ZWNJ, "")
        previous = canonical.get(key)
        if previous is None or count > previous[1]:
            canonical[key] = (word, count)

    # The "common" tier is the most frequent slice of the Wikipedia corpus.
    ranked = sorted(canonical.values(), key=lambda item: (-item[1], item[0]))
    common_cutoff = ranked[min(COMMON_PERSIAN_WORDS, len(ranked)) - 1][1] if ranked else 0

    # Output is sorted by the lookup key so the Swift loader can binary search.
    rows = sorted(
        ((key.replace(ZWNJ, ""), word, count) for key, (word, count) in canonical.items()),
        key=lambda item: item[0],
    )
    # Columns: lookup key, canonical spelling (only when it differs, i.e. when
    # it carries a ZWNJ), and a commonness flag.
    persian_path = os.path.join(OUT, "persian-lexicon.tsv")
    with open(persian_path, "w", encoding="utf-8") as handle:
        for key, word, count in rows:
            spelling = "" if word == key else word
            is_common = 1 if count >= common_cutoff and count > 0 else 0
            handle.write(f"{key}\t{spelling}\t{is_common}\n")

    english, english_common = load_english()
    english_path = os.path.join(OUT, "english-lexicon.txt")
    with open(english_path, "w", encoding="utf-8") as handle:
        for word in sorted(english):
            handle.write(word + "\n")

    common_path = os.path.join(OUT, "english-common.txt")
    with open(common_path, "w", encoding="utf-8") as handle:
        for word in sorted(english_common):
            handle.write(word + "\n")

    print(f"persian words: {len(rows):,} (common cutoff {common_cutoff:,}) -> {persian_path}")
    print(f"english words: {len(english):,} (common {len(english_common):,}) -> {english_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
