#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Propagates an English change to every translation. THE workflow for adding,
changing or removing a message.

    1. edit po/en.po        (the msgstr; the msgid is kept in step with it)
    2. tools/atualiza-po.py
    3. tools/po-para-catalogo.py
    4. bash tests/run.sh

What step 2 does, per language:

    - a NEW key arrives untranslated, and the loader falls back to English;
    - a key whose ENGLISH CHANGED is marked "#, fuzzy", and the compiler drops
      a fuzzy entry - so the reader gets English rather than a sentence that
      describes what Tandem used to do;
    - a key no longer in English is removed;
    - EVERY OTHER HEADER LINE IS KEPT VERBATIM.

That last one is not a detail. Last-Translator, PO-Revision-Date, Language-Team
and X-Generator are how a translator is credited and how Weblate keeps its
place. The first version of this pipeline rewrote headers from a template, which
would have deleted the name of every person who had worked on the file - the
exact thing that makes somebody not come back.

Pure Python, no msgmerge. gettext's own merge tool would do this and is not
used: the development machine for this project is Windows, where msgmerge is not
a given, and the maintainer should not need a toolchain to accept a translation.
"""
import io
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PO = os.path.join(RAIZ, "po")
PADRAO = "en"

import importlib.util

# The .po reader lives in the compiler, so there is exactly one parser in the
# tree. A second one would drift from it, and a parser that drifts is how a
# fuzzy mark gets lost.
_spec = importlib.util.spec_from_file_location(
    "compilador", os.path.join(RAIZ, "tools", "po-para-catalogo.py"))
compilador = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(compilador)


def cita(texto):
    if texto == "":
        return '""'
    corpo = texto.replace("\\", "\\\\").replace('"', '\\"')
    linhas = corpo.split("\n")
    if len(linhas) == 1:
        return '"%s"' % linhas[0]
    saida = ['""']
    for i, l in enumerate(linhas):
        saida.append('"%s%s"' % (l, "\\n" if i < len(linhas) - 1 else ""))
    return "\n".join(saida)



def linguas():
    caminho = os.path.join(PO, "LINGUAS")
    if os.path.exists(caminho):
        return [l.strip() for l in io.open(caminho, encoding="utf-8")
                if l.strip() and not l.startswith("#")]
    return [PADRAO]


def le_cru(caminho):
    """(header_lines, [(key, msgid, msgstr, fuzzy, comments)]) - keeps everything."""
    texto = io.open(caminho, encoding="utf-8").read()
    blocos = texto.split("\n\n")
    cabecalho, entradas = [], []
    for bloco in blocos:
        if not bloco.strip():
            continue
        linhas = bloco.split("\n")
        if any(l.startswith('msgctxt ') for l in linhas):
            entradas.append(linhas)
        elif cabecalho == [] and any(l.startswith("msgid ") for l in linhas):
            cabecalho = linhas
        elif cabecalho == []:
            cabecalho = linhas
    itens, _cab = compilador.le_po(caminho)
    por_chave = {}
    ids = {}
    # msgid per key, needed to notice that English changed
    chave = None
    campo = None
    partes = []
    for linha in texto.splitlines():
        crua = linha.strip()
        if crua.startswith("msgctxt "):
            chave = compilador.descita(
                [compilador.CITADA.match(crua[8:].strip()).group(1)])
            campo, partes = None, []
            continue
        if crua.startswith("msgid ") and chave is not None:
            campo, partes = "msgid", []
            m = compilador.CITADA.match(crua[6:].strip())
            if m and m.group(1):
                partes.append(m.group(1))
            continue
        if crua.startswith("msgstr ") and chave is not None:
            if campo == "msgid":
                ids[chave] = compilador.descita(partes)
            campo, partes = None, []
            continue
        m = compilador.CITADA.match(crua)
        if m is not None and campo == "msgid":
            partes.append(m.group(1))
    if chave is not None and campo == "msgid":
        ids[chave] = compilador.descita(partes)
    for k, t, f in itens:
        por_chave[k] = (ids.get(k, ""), t, f)
    return cabecalho, por_chave


def escreve_po(caminho, cabecalho, ordem, ingles, existente, lingua):
    saida = list(cabecalho)
    saida.append("")
    novas = difusas = mantidas = 0
    for chave in ordem:
        antes = existente.get(chave)
        if antes is None:
            traducao, fuzzy = "", False
            novas += 1
        else:
            id_antigo, traducao, fuzzy = antes
            if lingua == PADRAO:
                traducao = ingles[chave]      # the source language never drifts
            elif traducao and id_antigo != ingles[chave]:
                fuzzy = True
            if fuzzy and traducao:
                difusas += 1
            elif traducao:
                mantidas += 1
            else:
                novas += 1
        if fuzzy and traducao:
            saida.append("#, fuzzy")
        saida.append('msgctxt "%s"' % chave)
        saida.append("msgid %s" % cita(ingles[chave]))
        saida.append("msgstr %s" % cita(traducao))
        saida.append("")
    removidas = [k for k in existente if k not in ingles]
    io.open(caminho, "w", encoding="utf-8").write("\n".join(saida).rstrip("\n") + "\n")
    return mantidas, difusas, novas, len(removidas)


def main():
    fonte = os.path.join(PO, PADRAO + ".po")
    if not os.path.exists(fonte):
        print("po/%s.po is missing - it is where the English lives" % PADRAO)
        return 1
    cab_en, en = le_cru(fonte)
    ordem = list(en.keys())
    ingles = {k: v[1] for k, v in en.items()}

    faltando = [k for k in ordem if not ingles[k]]
    if faltando:
        print("po/%s.po has %d entries with an empty msgstr: %s"
              % (PADRAO, len(faltando), ", ".join(faltando[:5])))
        return 1

    pot = ["# Tandem message template.",
           "#",
           "# GENERATED by tools/atualiza-po.py from po/en.po - do not edit by hand.",
           "# Start a new language from it with:  msginit -i po/tandem.pot -l xx",
           "#", 'msgid ""', 'msgstr ""',
           '"Project-Id-Version: tandem\\n"',
           '"Report-Msgid-Bugs-To: https://github.com/ChrnX0/Tandem/issues\\n"',
           '"MIME-Version: 1.0\\n"',
           '"Content-Type: text/plain; charset=UTF-8\\n"',
           '"Content-Transfer-Encoding: 8bit\\n"',
           '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"', ""]
    for chave in ordem:
        pot += ['msgctxt "%s"' % chave, "msgid %s" % cita(ingles[chave]), 'msgstr ""', ""]
    io.open(os.path.join(PO, "tandem.pot"), "w", encoding="utf-8").write(
        "\n".join(pot).rstrip("\n") + "\n")
    print("po/tandem.pot  %d entries" % len(ordem))

    for lingua in linguas():
        caminho = os.path.join(PO, lingua + ".po")
        if not os.path.exists(caminho):
            print("%-6s no .po yet - start one with: "
                  "msginit -i po/tandem.pot -l %s -o po/%s.po" % (lingua, lingua, lingua))
            continue
        cab, existente = le_cru(caminho)
        m, f, n, r = escreve_po(caminho, cab, ordem, ingles, existente, lingua)
        partes = ["%d translated" % m]
        if f:
            partes.append("%d FUZZY (English changed - they need re-reading)" % f)
        if n:
            partes.append("%d untranslated" % n)
        if r:
            partes.append("%d removed" % r)
        print("%-6s %s" % (lingua, ", ".join(partes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
