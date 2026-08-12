#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compiles po/<lang>.po into src/lib/idiomas/<lang>.txt.

PURE PYTHON, ON PURPOSE. gettext's own msgfmt would be the obvious tool and it
is not used, because of inviolable rule 5: the packager must not depend on
outside tools and must run on any OS, Windows included. A .po parser is sixty
lines; requiring gettext at build time to get seven text files is not a trade
worth making.

Nor is the gettext RUNTIME used. Two reasons, and the first is the one that
matters:

  - The shipped catalogue is data that cannot execute. That property is tested,
    and it exists because these files will one day arrive from strangers. A .mo
    read through the C library would be fine too, but bash's $"..." form and
    eval-adjacent patterns around gettext are a footgun this project does not
    need to pick up.
  - Substitution stays {1} {2} rather than %1$s. Paths and versions carry
    percent signs; there is a test with a folder called "50% off".

So gettext is used where it is strong - authoring, interchange, msgmerge's fuzzy
marking, Weblate and Poedit - and not where it would cost something.

    tools/po-para-catalogo.py            # write the catalogues
    tools/po-para-catalogo.py --check     # fail if any is out of date
"""
import io
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PO = os.path.join(RAIZ, "po")
IDIOMAS = os.path.join(RAIZ, "src", "lib", "idiomas")
PADRAO = "en"
LINGUAS = ["en", "pt_BR", "es", "fr", "zh_CN", "hi", "ar"]

CITADA = re.compile(r'^"(.*)"\s*$')


def descita(linhas):
    """The .po string escapes, undone. Only the ones .po actually uses."""
    bruto = "".join(linhas)
    saida, i = [], 0
    while i < len(bruto):
        c = bruto[i]
        if c == "\\" and i + 1 < len(bruto):
            prox = bruto[i + 1]
            saida.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"'}.get(prox, prox))
            i += 2
            continue
        saida.append(c)
        i += 1
    return "".join(saida)


def le_po(caminho):
    """[(key, translation, fuzzy)] in file order, header entry excluded.

    The fuzzy flag is a COMMENT THAT PRECEDES the entry it belongs to:

        #, fuzzy
        msgctxt "sem_arquivo"
        msgid "No file was given at all."
        msgstr "Aucun fichier n'a ete indique."

    The first version of this parser closed the previous entry when it saw
    msgctxt, and closing reset the flag - so every fuzzy mark was wiped by the
    line immediately after it, and the reader reported none. It looked correct
    on files that had no fuzzy entries, which was all of them. Hence the flag
    living in "pendente" until an entry claims it.
    """
    itens = []
    ctx = None
    partes, campo, fuzzy, fuzzy_pendente = [], None, False, False
    cabecalho = {}

    def fecha():
        nonlocal ctx, partes, campo, fuzzy
        if campo == "msgstr" and ctx is not None:
            itens.append((ctx, descita(partes), fuzzy))
        ctx = None
        partes, campo, fuzzy = [], None, False

    for linha in io.open(caminho, encoding="utf-8").read().splitlines():
        crua = linha.strip()
        if crua.startswith("#,"):
            if "fuzzy" in crua:
                fuzzy_pendente = True
            continue
        if crua.startswith("#") or crua == "":
            if crua == "":
                fecha()
            continue
        if crua.startswith("msgctxt "):
            fecha()
            ctx = descita([CITADA.match(crua[8:].strip()).group(1)])
            campo = "msgctxt"
            fuzzy, fuzzy_pendente = fuzzy_pendente, False
            continue
        if crua.startswith("msgid "):
            campo, partes = "msgid", []
            m = CITADA.match(crua[6:].strip())
            if m and m.group(1):
                partes.append(m.group(1))
            continue
        if crua.startswith("msgstr "):
            campo, partes = "msgstr", []
            m = CITADA.match(crua[7:].strip())
            if m and m.group(1):
                partes.append(m.group(1))
            continue
        m = CITADA.match(crua)
        if m is not None and campo is not None:
            partes.append(m.group(1))
            if campo == "msgstr" and ctx is None:
                # the header entry: keep its fields, they carry the review flag
                texto = descita([m.group(1)])
                if ":" in texto:
                    k, v = texto.split(":", 1)
                    cabecalho[k.strip()] = v.strip().rstrip("\n")
    fecha()
    return itens, cabecalho


def escreve_catalogo(lingua, itens, cabecalho):
    revisado = "sim" if cabecalho.get("X-Reviewed-By-Speaker") == "yes" else "nao"
    saida = [
        "# Tandem - message catalogue, %s." % lingua,
        "#",
        "# GENERATED FROM po/%s.po - DO NOT EDIT BY HAND." % lingua,
        "# Edit the .po (Poedit, Weblate, or a text editor) and run",
        "# tools/po-para-catalogo.py. A test fails if the two drift apart.",
        "#",
        "# FORMAT",
        "#   @key          opens a message; everything until the next @key is the text",
        "#   {1} {2} {3}   where the variable parts go (a path, a name, a number)",
        "#   # at line start   a comment",
        "#",
        "# This file is NEVER executed. A dollar sign, a backtick or $(...) in here is",
        "# text and stays text.",
        "#",
        "# A key missing from this file falls back to the English original, so a",
        "# half-finished translation still says something readable.",
        "#",
        "# REVISADO=%s" % revisado,
        "",
    ]
    for chave, texto, fuzzy in itens:
        if not texto:
            continue          # untranslated: the loader falls back to English
        if fuzzy:
            continue          # stale: the English is better than a wrong answer
        saida.append("@%s" % chave)
        saida.append(texto)
        saida.append("")
    return "\n".join(saida).rstrip("\n") + "\n"


def main():
    checando = "--check" in sys.argv
    problemas = 0
    for lingua in LINGUAS:
        origem = os.path.join(PO, lingua + ".po")
        if not os.path.exists(origem):
            print("po/%s.po is missing" % lingua)
            problemas += 1
            continue
        itens, cabecalho = le_po(origem)
        novo = escreve_catalogo(lingua, itens, cabecalho)
        destino = os.path.join(IDIOMAS, lingua + ".txt")
        atual = io.open(destino, encoding="utf-8").read() if os.path.exists(destino) else None
        traduzidas = sum(1 for _, t, f in itens if t and not f)
        difusas = sum(1 for _, _, f in itens if f)
        if checando:
            if atual != novo:
                print("src/lib/idiomas/%s.txt is out of date with po/%s.po" % (lingua, lingua))
                problemas += 1
        else:
            if atual != novo:
                io.open(destino, "w", encoding="utf-8").write(novo)
            print("%-6s %4d translated%s" % (
                lingua, traduzidas, "  %d fuzzy (left to English)" % difusas if difusas else ""))
    if checando and not problemas:
        print("po/ and src/lib/idiomas/ agree")
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
