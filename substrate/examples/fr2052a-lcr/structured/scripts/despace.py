"""
De-space text from FR 2052a appendix tables that pdftotext renders with
a stray space between most pairs of consecutive letters.

Heuristic: in the affected tables almost every word starts with a capital
letter. Walk tokens left to right; a capitalised token starts a new word,
and lowercase tokens get glued onto the preceding word UNLESS the run of
consecutive lowercase tokens (concatenated) matches a known connective
(`of`, `and`). In that case the connective is emitted as a separate word.

Numbers and tokens that contain non-letter characters are passed through
verbatim, so identifiers like `Sub-Product` and `Non-HQLA` survive.

Usage:
    python despace.py < input.txt > output.txt
    python despace.py path/to/_full.txt --range 3488 3527

The optional --range slices a line range from the input file.
"""

from __future__ import annotations

import argparse
import sys

# Common English connectives that appear as standalone lowercase tokens
# between capitalised words. When despace sees a lowercase run between two
# capitalised tokens, any prefix/infix matching one of these is emitted as
# its own word rather than glued to the preceding capitalised fragment.
# We deliberately omit single-letter words like "a"/"I" because their token
# form is too easily confused with the lowercase tail of a mangled word
# (e.g. "Federa l" → "Federal").
EXCEPTIONS = {
    "of", "and", "or", "on", "in", "the", "for", "to", "with", "by", "at",
    "be", "not", "than",
}


def despace_line(line: str) -> str:
    leading = len(line) - len(line.lstrip(" "))
    tokens = line.split()
    out: list[str] = []
    current = ""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t.isalpha() and t[0].isupper():
            if current:
                out.append(current)
            current = t
            i += 1
        elif t.isalpha() and t[0].islower():
            # Find the maximal run of lowercase alphabetic tokens.
            j = i
            while (j < len(tokens) and tokens[j].isalpha()
                   and tokens[j][0].islower()):
                j += 1
            run = tokens[i:j]
            # Find every exception that matches anywhere in the run, longest
            # match preferred at each starting position. This handles cases
            # like "Ba nk of Aus" where "of" sits between two word fragments
            # ("nk" must glue to preceding "Ba" → "Bank", "of" stands alone,
            # "Aus..." starts a new word).
            matches: list[tuple[int, int]] = []
            p = 0
            while p < len(run):
                hit = False
                for k in range(len(run) - p, 0, -1):
                    if "".join(run[p:p + k]) in EXCEPTIONS:
                        matches.append((p, p + k))
                        p += k
                        hit = True
                        break
                if not hit:
                    p += 1
            if not matches:
                if current:
                    # Glue the run onto the preceding capitalised word —
                    # this is the mangled-word case (e.g. "Federa l").
                    current += "".join(run)
                else:
                    # No preceding capital. Treat each lowercase token as a
                    # standalone word so that all-lowercase phrases like
                    # "(forward start fields not provided)" stay separated.
                    for tok in run:
                        out.append(tok)
            else:
                prev = 0
                for s_, e_ in matches:
                    if s_ > prev:
                        prefix = run[prev:s_]
                        # Distinguish mangled fragments (short tokens, e.g.
                        # "Federa l") from genuine separate words (longer
                        # tokens, e.g. "the following table"). If every
                        # prefix token is <= 3 chars long, treat as
                        # mangling and glue. Otherwise emit each prefix
                        # token as its own word.
                        if current and max(len(t) for t in prefix) <= 3:
                            current += "".join(prefix)
                        else:
                            if current:
                                out.append(current)
                                current = ""
                            for tok in prefix:
                                out.append(tok)
                    if current:
                        out.append(current)
                        current = ""
                    out.append("".join(run[s_:e_]))
                    prev = e_
                if prev < len(run):
                    if current:
                        # Trailing run glues onto an in-progress capital
                        # word that started before the lowercase run.
                        current = "".join(run[prev:])
                    else:
                        # No anchor — preserve each lowercase token as its
                        # own word (handles all-lowercase prose).
                        for tok in run[prev:]:
                            out.append(tok)
            i = j
        else:
            # Non-alpha or mixed-letter token — preserves things like
            # "Sub-Product", "Non-HQLA", "OTC", "2", "-".
            if current:
                out.append(current)
                current = ""
            out.append(t)
            i += 1
    if current:
        out.append(current)
    return " " * leading + " ".join(out)


def despace(text: str) -> str:
    return "\n".join(despace_line(ln) for ln in text.splitlines())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", help="input file (default: stdin)")
    ap.add_argument("--range", nargs=2, type=int, metavar=("START", "END"),
                    help="1-based inclusive line range to process")
    args = ap.parse_args()

    if args.path:
        text = open(args.path, encoding="utf-8", errors="replace").read()
    else:
        text = sys.stdin.read()

    if args.range:
        # Use split('\n') rather than splitlines() so form-feed characters
        # (\f) emitted by pdftotext between pages don't shift line numbers
        # away from what wc -l / grep report.
        lines = text.split("\n")
        s, e = args.range
        text = "\n".join(lines[s - 1:e])

    sys.stdout.write(despace(text) + "\n")


if __name__ == "__main__":
    main()
