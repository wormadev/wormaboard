#!/usr/bin/env python3
"""Builds the Arabic Spatial autocorrect model (HEXKeyboard/TypingModel/ar.hextm) from the
Leipzig Corpora Collection's Arabic corpora (CC BY 4.0; Goldhahn, Eckart and Quasthoff 2012)
and as many words again of OPUS OpenSubtitles 2018 Arabic (Lison and Tiedemann 2016), in the
format `build-typing-model.py` writes. Google Books Ngram has no Arabic. News and Wikipedia
alone suggested formal words ("انتشار" before "أنت"); the subtitles are how people talk.

    python3 scripts/build-arabic-typing-model.py <workdir> HEXKeyboard/TypingModel/ar.hextm

Downloads about 570 MB of Leipzig and the first 300 MB of the subtitles into <workdir>
(cached, so a rerun reads them again) and needs about 3 GB of memory for the word-pair counts.
Deterministic for the same inputs.

Spelling: each sentence is NFC-normalised (a decomposed alef and hamza becomes أ), its
tashkeel (fathatan to sukun, U+064B-U+065F), superscript alef (U+0670) and tatweel (U+0640)
are dropped, and a word is a run of the 36 letters U+0621-U+063A and U+0641-U+064A. Hamza
forms (أ إ آ ؤ ئ ء), ة and ه, and ى and ي stay distinct letters: they change words' meaning
(على "on" and علي "Ali"), so the model never conflates them; the decoder reaches أ إ آ from
ا, ؤ from و and ئ from ي as accented letters (the writer's base codes, by NFD). A token with
any other character (Latin, digits, Persian letters) is no word and breaks word pairs, as
punctuation does. One-letter words other than و are left out (abbreviations: م for ميلادي).
"""
import collections, importlib, os, re, subprocess, sys, tarfile, unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
builder = importlib.import_module("build-typing-model")

CORPORA = ["ara_news_2022_1M", "ara_news_2020_1M", "ara_wikipedia_2021_1M"]
URL = "https://downloads.wortschatz-leipzig.de/corpora/{}.tar.gz"
SUBTITLES = "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/mono/ar.txt.gz"
SUBTITLE_BYTES = 300_000_000
MAX_WORDS = 150_000
MIN_WORD = 3
MIN_PAIR = 3
MARKS = re.compile("[\u0640\u064B-\u065F\u0670]")
PUNCTUATION = "\\.,;:!?\"'()\\[\\]{}«»،؛؟…\\-–—/"
TOKENS = re.compile(f"[^\\s{PUNCTUATION}]+|[{PUNCTUATION}]")
WORD = re.compile("[\u0621-\u063A\u0641-\u064A]{1,24}")


def words(sentence):
    """The sentence's tokens: a word, or None where a pair can't span."""
    text = MARKS.sub("", unicodedata.normalize("NFC", sentence))
    for token in TOKENS.findall(text):
        yield token if WORD.fullmatch(token) and (len(token) > 1 or token == "و") else None


def news(work):
    for name in CORPORA:
        path = os.path.join(work, name + ".tar.gz")
        builder.fetch(URL.format(name), path)
        with tarfile.open(path) as tar:
            member = next(m for m in tar.getmembers() if m.name.endswith("-sentences.txt"))
            for line in tar.extractfile(member):
                yield line.decode("utf-8", "replace").rstrip("\n").split("\t", 1)[-1]


def subtitles(work):
    """The subtitle lines in the file's first SUBTITLE_BYTES, its last cut line left out."""
    path = os.path.join(work, "opensubtitles-ar-head.txt.gz")
    if not os.path.exists(path):
        subprocess.run(["curl", "-sSfL", "--retry", "8", "-r", f"0-{SUBTITLE_BYTES - 1}", "-o", path + ".part", SUBTITLES], check=True)
        os.replace(path + ".part", path)
    proc = subprocess.Popen(["gzip", "-dc", path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=1 << 20)
    previous = None
    for line in proc.stdout:
        if previous is not None:
            yield previous.decode("utf-8", "replace").rstrip("\n")
        previous = line
    proc.wait()


def sentences(work, news_words):
    """The news sentences, then subtitle lines until they hold as many words as the news."""
    yield from news(work)
    seen = 0
    for line in subtitles(work):
        if seen >= news_words:
            return
        seen += sum(1 for w in words(line) if w)
        yield line


def main(work, out_path):
    os.makedirs(work, exist_ok=True)
    news_words = sum(1 for sentence in news(work) for w in words(sentence) if w)
    counts = collections.Counter()
    total = 0
    for sentence in sentences(work, news_words):
        for w in words(sentence):
            total += 1
            if w:
                counts[w] += 1
    ranked = sorted((w for w, c in counts.items() if c >= MIN_WORD), key=lambda w: (-counts[w], w))
    vocab = {w: counts[w] for w in ranked[:MAX_WORDS]}
    index = {w: i for i, w in enumerate(vocab)}
    n = len(vocab)
    pair_counts = collections.Counter()
    for sentence in sentences(work, news_words):
        previous = None
        for w in words(sentence):
            i = index.get(w) if w else None
            if previous is not None and i is not None:
                pair_counts[previous * n + i] += 1
            previous = i
    listed = list(vocab)
    pairs = {f"{listed[k // n]} {listed[k % n]}".encode("utf-8"): c for k, c in pair_counts.items() if c >= MIN_PAIR}
    builder.write_model("ar", vocab, total, pairs, out_path, min_pair=MIN_PAIR)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
