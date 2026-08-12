#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One-time conversion: the flat catalogues become .po files.

Run once to bootstrap po/ from src/lib/idiomas/. After this, .po is the source
of truth and tools/po-para-catalogo.py regenerates the flat files.

Kept in the tree rather than deleted because it is also the round-trip test's
other half: catalogue -> po -> catalogue must be lossless, and a test asserts it.
"""
import io
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IDIOMAS = os.path.join(RAIZ, "src", "lib", "idiomas")
PO = os.path.join(RAIZ, "po")
PADRAO = "en"
LINGUAS = ["en", "pt_BR", "es", "fr", "zh_CN", "hi", "ar"]

# The plural rule of each language, in gettext's own notation, so the .po files
# are the real thing and Weblate/Poedit understand them. Arabic has six forms;
# Chinese has one. A format that cannot say that produces "1 linha(s)".
PLURAIS = {
    "en": "nplurals=2; plural=(n != 1);",
    "pt_BR": "nplurals=2; plural=(n > 1);",
    "es": "nplurals=2; plural=(n != 1);",
    "fr": "nplurals=2; plural=(n > 1);",
    "zh_CN": "nplurals=1; plural=0;",
    "hi": "nplurals=2; plural=(n != 1);",
    "ar": ("nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : "
           "n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);"),
}
# Which catalogues a speaker of the language has actually read.
REVISADO = {"en": True, "pt_BR": True}


def le_catalogo(caminho):
    """The flat format, in order, so the .po keeps the reading order."""
    itens, chave, corpo = [], None, []
    for linha in io.open(caminho, encoding="utf-8").read().splitlines():
        if linha.startswith("@"):
            if chave is not None:
                itens.append((chave, "\n".join(corpo).rstrip("\n")))
            chave, corpo = linha[1:], []
            continue
        if linha.startswith("#"):
            continue
        if chave is None:
            continue
        if linha.startswith("\\#") or linha.startswith("\\@"):
            linha = linha[1:]
        corpo.append(linha)
    if chave is not None:
        itens.append((chave, "\n".join(corpo).rstrip("\n")))
    return itens


def cita(texto):
    """A .po string, one msgid line per source line, the way gettext writes it."""
    if texto == "":
        return '""'
    corpo = texto.replace("\\", "\\\\").replace('"', '\\"')
    linhas = corpo.split("\n")
    if len(linhas) == 1:
        return '"%s"' % linhas[0]
    saida = ['""']
    for i, l in enumerate(linhas):
        fim = "\\n" if i < len(linhas) - 1 else ""
        saida.append('"%s%s"' % (l, fim))
    return "\n".join(saida)


def cabecalho(lingua):
    revisado = REVISADO.get(lingua, False)
    linhas = [
        "# Tandem message catalogue - %s." % lingua,
        "#",
        "# THIS FILE IS THE SOURCE OF TRUTH. src/lib/idiomas/%s.txt is generated" % lingua,
        "# from it by tools/po-para-catalogo.py; do not edit that file by hand.",
        "#",
        "# It is a normal gettext .po file, so Poedit, Weblate, Lokalize and",
        "# msgmerge all work on it. What matters most about that: when the English",
        "# msgid changes, msgmerge marks the affected entry #, fuzzy - which is the",
        "# one thing the old hand-rolled format could not do, and the reason a",
        "# translation could silently go stale.",
        "#",
        "# X-Reviewed-By-Speaker: %s" % ("yes" if revisado else "no - see CONTRIBUTING.md"),
        "#",
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: tandem\\n"',
        '"Report-Msgid-Bugs-To: https://github.com/ChrnX0/Tandem/issues\\n"',
        '"Language: %s\\n"' % lingua,
        '"Language-Team: %s\\n"' % lingua,
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        '"Plural-Forms: %s\\n"' % PLURAIS[lingua],
        '"X-Reviewed-By-Speaker: %s\\n"' % ("yes" if revisado else "no"),
        "",
    ]
    return linhas


def main():
    base = dict(le_catalogo(os.path.join(IDIOMAS, PADRAO + ".txt")))
    ordem = [k for k, _ in le_catalogo(os.path.join(IDIOMAS, PADRAO + ".txt"))]
    if not os.path.isdir(PO):
        os.makedirs(PO)

    # The template, for msginit/msgmerge and for a translator starting a new
    # language from nothing.
    pot = ["# Tandem message template. Generated - do not edit by hand.",
           "#", 'msgid ""', 'msgstr ""',
           '"Project-Id-Version: tandem\\n"',
           '"Report-Msgid-Bugs-To: https://github.com/ChrnX0/Tandem/issues\\n"',
           '"MIME-Version: 1.0\\n"',
           '"Content-Type: text/plain; charset=UTF-8\\n"',
           '"Content-Transfer-Encoding: 8bit\\n"',
           '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"', ""]
    for chave in ordem:
        pot += ['msgctxt "%s"' % chave, "msgid %s" % cita(base[chave]), 'msgstr ""', ""]
    io.open(os.path.join(PO, "tandem.pot"), "w", encoding="utf-8").write("\n".join(pot))

    for lingua in LINGUAS:
        alvo = dict(le_catalogo(os.path.join(IDIOMAS, lingua + ".txt")))
        saida = cabecalho(lingua)
        for chave in ordem:
            saida.append('msgctxt "%s"' % chave)
            saida.append("msgid %s" % cita(base[chave]))
            saida.append("msgstr %s" % cita(alvo.get(chave, "")))
            saida.append("")
        io.open(os.path.join(PO, lingua + ".po"), "w", encoding="utf-8").write(
            "\n".join(saida))
        faltando = [k for k in ordem if k not in alvo]
        print("po/%s.po: %d entries%s" % (
            lingua, len(ordem),
            "" if not faltando else "  (%d untranslated)" % len(faltando)))
    print("po/tandem.pot: %d entries" % len(ordem))
    return 0


if __name__ == "__main__":
    sys.exit(main())
