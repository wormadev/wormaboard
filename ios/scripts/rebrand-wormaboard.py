# Fork rebrand: shows "WormaBoard" instead of "Hex" in the iPhone app's user-facing text. Rerun after each upstream merge.
"""Idempotent. Rewrites only text a person sees or hears: Swift string literals (comments and
code untouched), the String Catalogs (keys and every translation, so Swift literals and keys
keep matching), and the privacy usage strings. Tests are rewritten only where they quote a
product string this run changed. Usage: python3 ios/scripts/rebrand-wormaboard.py [--dry-run]
"""

import json
import re
import sys
from pathlib import Path

IOS = Path(__file__).resolve().parent.parent
NEW = "WormaBoard"
HEX = re.compile(r"(?<![A-Za-z0-9_])Hex(?![A-Za-z0-9_])")

SWIFT_DIRS = ["HEXMobile", "HEXKeyboard", "HEXShared", "HEXWidgets", "HEXActivity"]
TEST_DIRS = ["HEXMobileTests"]
CATALOGS = ["HEXMobile/Localizable.xcstrings", "HEXWidgets/Localizable.xcstrings"]
USAGE_FILES = ["project.yml", "HEXMobile/Info.plist", "HEXKeyboard/Info.plist"]
STRINGS_FILES = ["HEXMobile/zh-Hans.lproj/InfoPlist.strings"]

# A literal on a line containing one of these is never seen: debug labels, logs, assertion names.
DENY_LINE = re.compile(r"\.label = |BackgroundAssertion\(name:|log\.write\(|KeyboardProbeLog")
# Literals naming Hex for Mac or the website stay as they are. Matched against the literal's text.
DENY_TEXT = re.compile(r"\bMac\b|anoma\.ly|\bdesktop\b|opens Hex$|<script>")
# Test files whose "Hex" is data (a vocabulary word), not the app's name.
DENY_TEST_FILES = {"CustomVocabularyTests.swift", "DictationLearningTests.swift"}
# Whole literals reworded instead, where the longer name would overflow (the strip's 40 characters).
REWORD = {"iOS 18 translates only with Hex open": "On iOS 18, open WormaBoard to translate"}


def rename(text):
    return REWORD.get(text) or HEX.sub(NEW, text)


def literals(src):
    """Yields (template, segments) per string literal; segments are (start, end) of literal
    text outside interpolations, template is the text with each interpolation as %@."""
    out = []
    i, n = 0, len(src)

    def scan_string(i, hashes):
        multi = src.startswith('"""', i)
        quote = '"""' if multi else '"'
        i += len(quote)
        close = quote + "#" * hashes
        segs, parts, seg_start = [], [], i
        while i < n:
            if src.startswith(close, i):
                segs.append((seg_start, i))
                parts.append(src[seg_start:i])
                out.append(("%@".join(parts), segs))
                return i + len(close)
            if src[i] == "\\" and src.startswith("#" * hashes + "(", i + 1):
                segs.append((seg_start, i))
                parts.append(src[seg_start:i])
                i = scan_code(i + 2 + hashes, depth=1)
                seg_start = i
                continue
            if src[i] == "\\":
                i += 2
                continue
            if not multi and src[i] == "\n":
                break
            i += 1
        return i

    def scan_code(i, depth=0):
        while i < n:
            c = src[i]
            if src.startswith("//", i):
                j = src.find("\n", i)
                i = n if j < 0 else j
            elif src.startswith("/*", i):
                j = src.find("*/", i)
                i = n if j < 0 else j + 2
            elif c == "#" and re.match(r'#+"', src[i:]):
                hashes = len(re.match(r"#+", src[i:]).group())
                i = scan_string(i + hashes, hashes)
            elif c == '"':
                i = scan_string(i, 0)
            elif c == "(":
                depth += 1 if depth else 0
                i += 1
            elif c == ")" and depth:
                depth -= 1
                i += 1
                if depth == 0:
                    return i
            else:
                i += 1
        return i

    scan_code(0)
    return out


def line_of(src, pos):
    start = src.rfind("\n", 0, pos) + 1
    end = src.find("\n", pos)
    return src[start:] if end < 0 else src[start:end]


def rewrite_swift(path, keep):
    src = path.read_text()
    edits, changed = [], []
    for template, segs in literals(src):
        if not HEX.search(template) or not keep(template, src, segs[0][0]):
            continue
        changed.append(template)
        edits.extend(segs)
    for start, end in sorted(edits, reverse=True):
        src = src[:start] + rename(src[start:end]) + src[end:]
    return src, changed


def product_keep(template, src, pos):
    return not DENY_LINE.search(line_of(src, pos)) and not DENY_TEXT.search(template)


def template_regex(template, prefix):
    pattern = ".*".join(re.escape(p) for p in template.split("%@"))
    return re.compile(pattern + (".*" if prefix else "") + r"\Z", re.S)


def rewrite_catalog(path):
    data = json.loads(path.read_text())
    strings, count = {}, 0
    for key, entry in data["strings"].items():
        if DENY_TEXT.search(key):
            strings[key] = entry
            continue
        text = json.dumps(entry, ensure_ascii=False)
        new_key, new_text = rename(key), HEX.sub(NEW, text)
        count += new_key != key or new_text != text
        strings[new_key] = json.loads(new_text)
    data["strings"] = strings
    # Xcode writes catalogs with " : " separators and two-space indents.
    return json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n", count


def rewrite_usage(path):
    lines = path.read_text().splitlines(keepends=True)
    out, after_key = [], False
    for line in lines:
        if "UsageDescription" in line and ":" in line and path.suffix == ".yml":
            line = HEX.sub(NEW, line)
        elif after_key and "<string>" in line:
            line = HEX.sub(NEW, line)
        after_key = "UsageDescription</key>" in line
        out.append(line)
    return "".join(out)


def rewrite_strings(path):
    return "".join(
        HEX.sub(NEW, l) if "UsageDescription" in l else l
        for l in path.read_text().splitlines(keepends=True)
    )


def main():
    dry = "--dry-run" in sys.argv
    writes, product_templates = {}, []

    for d in SWIFT_DIRS:
        for path in sorted((IOS / d).rglob("*.swift")):
            new, changed = rewrite_swift(path, product_keep)
            product_templates += changed
            if changed:
                writes[path] = new
                for t in changed:
                    print(f"{path.relative_to(IOS)}: {t!r}")

    full = [template_regex(t, False) for t in product_templates]
    prefix = [template_regex(t, True) for t in product_templates if len(t.split()) >= 3]

    def test_keep(template, src, pos):
        return any(r.match(template) for r in full + prefix)

    for d in TEST_DIRS:
        for path in sorted((IOS / d).rglob("*.swift")):
            if path.name in DENY_TEST_FILES:
                continue
            new, changed = rewrite_swift(path, test_keep)
            if changed:
                writes[path] = new
                for t in changed:
                    print(f"{path.relative_to(IOS)}: {t!r}")

    for rel in CATALOGS:
        new, count = rewrite_catalog(IOS / rel)
        print(f"{rel}: {count} entries")
        writes[IOS / rel] = new
    for rel in USAGE_FILES:
        writes[IOS / rel] = rewrite_usage(IOS / rel)
    for rel in STRINGS_FILES:
        writes[IOS / rel] = rewrite_strings(IOS / rel)

    print(f"{len(product_templates)} product literals")
    if dry:
        return
    for path, text in writes.items():
        if path.read_text() != text:
            path.write_text(text)


if __name__ == "__main__":
    main()
