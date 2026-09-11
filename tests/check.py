#!/usr/bin/env python3
"""
check.py -- conformance checks for a deck built with the Dublin theme.

    python3 tests/check.py path/to/out.pdf [path/to/out.tex] [path/to/out.log]

A slide template has no equivalent of a type specimen's waterfall, so this is
the substitute: assertions that catch the failures a theme actually has, none
of which are visible from a single screenshot.

    1  LaTeX errors
    2  content overflowing a frame            (a slide that silently runs past
                                               the footer still "compiles")
    3  dangling internal links                (a nav pill that goes nowhere)
    4  gaps in the Table / Figure sequence    (an uncaptioned exhibit still
                                               takes a number)
    5  tables left at body size               (a markdown table that escaped
                                               the restyling)
    6  colours outside the palette            (a stray default blue or red)
    7  captions not in Title Case

Exit status is the number of failures, so it drops straight into CI.
"""

import re
import sys
from collections import Counter

PALETTE = {
    (0x04, 0x20, 0x4C): "dgNavy",
    (0x00, 0x56, 0xA4): "dgBlue",
    (0x00, 0x3C, 0x77): "dgBlueDk",
    (0x9F, 0xC4, 0xE0): "dgBlueLt",
    (0x61, 0xB7, 0x7C): "dgGreen",
    (0x21, 0x25, 0x29): "dgInk",
    (0x6C, 0x75, 0x7D): "dgMuted",
    (0xD8, 0xE0, 0xE6): "dgRule",
    (0xF2, 0xF6, 0xF9): "dgWash",
    (0xFF, 0xFF, 0xFF): "white",
    (0x00, 0x00, 0x00): "black",
}

# Words that stay lower case inside a Title Case caption.
SMALL = {
    "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into",
    "nor", "of", "on", "or", "over", "than", "that", "the", "to", "up", "via",
    "with",
}

BODY_PT = 10.9        # \normalsize at 11pt base
TABLE_PT = 9.0        # \footnotesize


class Report:
    def __init__(self):
        self.failures = 0

    def ok(self, name, detail=""):
        print(f"  pass  {name}" + (f"  ({detail})" if detail else ""))

    def fail(self, name, detail):
        self.failures += 1
        print(f"  FAIL  {name}")
        for line in str(detail).splitlines():
            print(f"          {line}")

    def skip(self, name, why):
        print(f"  skip  {name}  ({why})")


def check_log(rep, log_text):
    if log_text is None:
        rep.skip("no LaTeX errors", "no .log given")
        rep.skip("nothing overflows a frame", "no .log given")
        return

    errors = [ln for ln in log_text.splitlines() if ln.startswith("! ")]
    if errors:
        rep.fail("no LaTeX errors", "\n".join(errors[:10]))
    else:
        rep.ok("no LaTeX errors")

    over = re.findall(r"Overfull \\vbox \(([\d.]+)pt too high\)[^\n]*", log_text)
    if over:
        rep.fail(
            "nothing overflows a frame",
            "\n".join(f"{pt}pt past the bottom of a frame" for pt in over[:10]),
        )
    else:
        rep.ok("nothing overflows a frame")


def check_links(rep, reader):
    dests = set(reader.named_destinations.keys())
    dangling, total = [], 0
    for i, page in enumerate(reader.pages, start=1):
        for annot in page.get("/Annots") or []:
            obj = annot.get_object()
            target = (obj.get("/A") or {}).get("/D")
            if isinstance(target, (str, bytes)):
                total += 1
                if str(target) not in dests:
                    dangling.append(f"slide {i} -> {target}")
    if dangling:
        rep.fail("every internal link resolves", "\n".join(dangling[:10]))
    else:
        rep.ok("every internal link resolves", f"{total} links")


def check_caption_sequence(rep, text):
    for kind in ("Table", "Figure"):
        found = [int(n) for n in re.findall(rf"{kind}\s*(\d+)\s*:", text)]
        if not found:
            rep.skip(f"{kind} numbering has no gaps", "none in the deck")
            continue
        expected = list(range(1, len(found) + 1))
        if found != expected:
            rep.fail(
                f"{kind} numbering has no gaps",
                f"saw {found}, expected {expected}. An uncaptioned "
                f"{kind.lower()} still takes a number.",
            )
        else:
            rep.ok(f"{kind} numbering has no gaps", f"1-{len(found)}")


def check_title_case(rep, text):
    bad = []
    for kind, caption in re.findall(r"(Table|Figure)\s*\d+\s*:\s*(.+)", text):
        words = re.findall(r"[A-Za-z][A-Za-z'-]*", caption)
        for i, word in enumerate(words):
            low = word.lower()
            if word[0].isupper():
                continue
            if i > 0 and low in SMALL:
                continue
            bad.append(f"{kind} caption: {caption}   ({word})")
            break
    if bad:
        rep.fail("captions are Title Case", "\n".join(bad[:10]))
    else:
        rep.ok("captions are Title Case")


def check_table_size(rep, pdf, tex_text):
    if tex_text is not None:
        left = tex_text.count(r"\begin{longtable}")
        if left:
            rep.fail(
                "every table is restyled",
                f"{left} table(s) still pandoc longtables, so they will not "
                f"match a hand-written dgtable",
            )
        else:
            rep.ok("every table is restyled")
    else:
        rep.skip("every table is restyled", "no .tex given")

    offenders = []
    for i, page in enumerate(pdf.pages, start=1):
        words = page.extract_text(x_tolerance=1.4) or ""
        if not re.search(r"Table\s*\d+\s*:", words):
            continue
        sizes = Counter(round(c["size"], 1) for c in page.chars)
        if sizes.get(TABLE_PT, 0) == 0:
            offenders.append(f"slide {i} has a table but no {TABLE_PT}pt text")
    if offenders:
        rep.fail("tables are set a size down", "\n".join(offenders))
    else:
        rep.ok("tables are set a size down", f"{TABLE_PT}pt")


GROUNDS = ((255, 255, 255), (0xF2, 0xF6, 0xF9), (0x04, 0x20, 0x4C))


def is_palette(rgb):
    """True for a palette colour, or any tint of one over a ground beamer
    actually paints on -- the section dividers fade the contents list by
    blending a palette colour towards the slide ground, and that blend is
    correct rather than a stray."""
    for p in PALETTE:
        if sum(abs(a - b) for a, b in zip(rgb, p)) <= 8:
            return True
    for p in PALETTE:
        for ground in GROUNDS:
            alphas = []
            for c, pc, gc in zip(rgb, p, ground):
                if pc == gc:
                    continue
                alphas.append((c - gc) / (pc - gc))
            if not alphas:
                continue
            if all(-0.03 <= a <= 1.03 for a in alphas) and \
               max(alphas) - min(alphas) <= 0.06:
                return True
    return False


def check_palette(rep, pdf):
    strays = Counter()
    for i, page in enumerate(pdf.pages, start=1):
        for obj in list(page.rects) + list(page.chars):
            for key in ("non_stroking_color", "stroking_color"):
                colour = obj.get(key)
                if not colour or len(colour) != 3:
                    continue
                rgb = tuple(int(round(c * 255)) for c in colour)
                if not is_palette(rgb):
                    strays[rgb] += 1
    if strays:
        listed = ", ".join(
            f"#{r:02X}{g:02X}{b:02X} ({n})"
            for (r, g, b), n in strays.most_common(6)
        )
        rep.fail("only palette colours are used", listed)
    else:
        rep.ok("only palette colours are used")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2

    pdf_path = argv[1]
    tex_path = argv[2] if len(argv) > 2 else None
    log_path = argv[3] if len(argv) > 3 else None

    try:
        import pdfplumber
        from pypdf import PdfReader
    except ImportError:
        print("needs pdfplumber and pypdf: pip install pdfplumber pypdf")
        return 2

    def read(path):
        if not path:
            return None
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()

    print(f"checking {pdf_path}")

    rep = Report()
    check_log(rep, read(log_path))
    check_links(rep, PdfReader(pdf_path))

    with pdfplumber.open(pdf_path) as pdf:
        text = "\n".join((p.extract_text(x_tolerance=1.4) or "")
                         for p in pdf.pages)
        check_caption_sequence(rep, text)
        check_title_case(rep, text)
        check_table_size(rep, pdf, read(tex_path))
        check_palette(rep, pdf)

    print()
    if rep.failures:
        print(f"{rep.failures} check(s) failed")
    else:
        print("all checks passed")
    return rep.failures


if __name__ == "__main__":
    sys.exit(main(sys.argv))
