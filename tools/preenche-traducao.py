#!/usr/bin/env python3
"""Fill translated msgstr blocks into the catalogues, correctly.

This exists because the multi-line fill was re-derived by hand five times in one
session, and re-derived WRONG each time in the same place: `re.sub` processes
backslash escapes in a *string* replacement, so the literal ``\\n`` a PO msgstr
needs became a real newline INSIDE the quotes and corrupted the file. The fix is
a *callable* replacement, whose return value re.sub inserts verbatim - baked in
here once, with a self-test that puts the bug back and watches it caught.

Usage:
    python3 tools/preenche-traducao.py traducoes.json
        traducoes.json is {"<key>": {"pt_BR": "text", "es": "...", ...}, ...},
        where text carries REAL newlines. Each key is filled into po/<lang>.po
        for every language present, but only when that entry's msgstr is still
        empty (an already-translated entry is left alone, never clobbered).

    python3 tools/preenche-traducao.py --selftest
        round-trips a multi-line value and fails loudly if the escape bug is back.

It does NOT run atualiza-po.py or the catalogue compiler - the workflow is still
edit po/en.po -> atualiza-po.py (creates the empty entries) -> THIS -> the
compiler. Running atualiza-po.py AFTER this would re-serialise and is what has
mangled multi-line entries before; do it before, not after.
"""
import io
import json
import os
import re
import sys

LANGS = ["pt_BR", "es", "fr", "zh_CN", "hi", "ar"]


def po_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def render_msgstr(text):
    """A PO msgstr for `text` (real newlines), in the segmented form: an empty
    first line then one quoted C-string per line, each but the last ending with
    a literal \\n escape. A single-line value collapses to one quoted line."""
    parts = text.split("\n")
    out = ['msgstr ""']
    for i, seg in enumerate(parts):
        tail = "\\n" if i < len(parts) - 1 else ""
        out.append('"%s%s"' % (po_escape(seg), tail))
    return "\n".join(out)


def fill_entry(po_text, key, text):
    """Return po_text with the empty msgstr of `key` replaced by `text`.
    Raises if the key is absent, or if its msgstr is not empty (never clobber)."""
    m = re.search(r'msgctxt "%s"\n' % re.escape(key), po_text)
    if not m:
        raise KeyError("key not found: %s" % key)
    start = m.start()
    end = po_text.find("\n\n", start)
    if end == -1:
        end = len(po_text)
    block = po_text[start:end]
    if not block.rstrip().endswith('msgstr ""'):
        raise ValueError("msgstr for %s is not empty; refusing to clobber" % key)
    repl = render_msgstr(text)
    # CALLABLE replacement: re.sub does NOT process backslash escapes in the
    # value a function returns, so the \n in `repl` survive as escapes. A string
    # replacement would turn them into real newlines and corrupt the PO.
    block2 = re.sub(r'msgstr ""\s*$', lambda _m: repl, block)
    return po_text[:start] + block2 + po_text[end:]


def fill_file(path, entries):
    """entries: {key: text}. Fills each into the .po at `path`. Skips a key whose
    msgstr is already non-empty (idempotent). Returns how many were filled."""
    with io.open(path, encoding="utf-8") as f:
        t = f.read()
    n = 0
    for key, text in entries.items():
        try:
            t = fill_entry(t, key, text)
            n += 1
        except ValueError:
            pass  # already translated - leave it
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(t)
    return n


def run(spec_path):
    with io.open(spec_path, encoding="utf-8") as f:
        spec = json.load(f)
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    per_lang = {}
    for key, langs in spec.items():
        for lang, text in langs.items():
            per_lang.setdefault(lang, {})[key] = text
    for lang, entries in per_lang.items():
        path = os.path.join(base, "po", "%s.po" % lang)
        n = fill_file(path, entries)
        print("%-6s %d filled" % (lang, n))


def selftest():
    # An empty multi-line entry, exactly as atualiza-po.py leaves it.
    entry = (
        'msgctxt "probe"\n'
        'msgid ""\n'
        '"Line one {1}.\\n"\n'
        '"\\n"\n'
        '"Line three."\n'
        'msgstr ""'
    )
    doc = entry + "\n\n"
    value = "Um {1}.\n\nTrês."
    out = fill_entry(doc, "probe", value)
    # 1) no real newline may sit inside a quoted string (the escape bug).
    for line in out.splitlines():
        s = line.strip()
        if s.startswith('"'):
            assert s.endswith('"'), "a quoted line was split by a real newline: %r" % line
    # 2) the value must round-trip: joining the msgstr segments and turning the
    #    \n escapes back into newlines reproduces `value`.
    msgstr_part = out.split("\nmsgstr ")[1]
    segs = re.findall(r'"((?:[^"\\]|\\.)*)"', msgstr_part)
    joined = "".join(segs).replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
    assert joined == value, "round-trip mismatch:\n  got %r\n  want %r" % (joined, value)
    # 3) the bug, put back on purpose: a STRING replacement makes re.sub process
    #    the \n as a real newline, so a quoted line gets split. Prove the callable
    #    form (used above) is what avoids exactly this.
    bad = re.sub(r'msgstr ""\s*$', render_msgstr(value), doc)
    split_in_quotes = any(
        s.startswith('"') and not s.endswith('"')
        for s in (ln.strip() for ln in bad.splitlines())
    )
    assert split_in_quotes, "the string-replacement bug did not reproduce - test is vacuous"
    print("selftest ok")


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        selftest()
        return 0
    if len(argv) == 2:
        run(argv[1])
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
