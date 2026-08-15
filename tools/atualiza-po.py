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
    ids_plural = {}
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
        if crua.startswith("msgid_plural ") and chave is not None:
            if campo == "msgid":
                ids[chave] = compilador.descita(partes)
            campo, partes = "msgid_plural", []
            m = compilador.CITADA.match(crua[13:].strip())
            if m and m.group(1):
                partes.append(m.group(1))
            continue
        if crua.startswith("msgid ") and chave is not None:
            campo, partes = "msgid", []
            m = compilador.CITADA.match(crua[6:].strip())
            if m and m.group(1):
                partes.append(m.group(1))
            continue
        # "msgstr" and not "msgstr ": msgstr[0] closes the msgid above it just
        # as msgstr does, and reading only the spaced form is precisely how the
        # compiler used to lose a whole plural entry without saying so.
        if crua.startswith("msgstr") and chave is not None:
            if campo == "msgid":
                ids[chave] = compilador.descita(partes)
            elif campo == "msgid_plural":
                ids_plural[chave] = compilador.descita(partes)
            campo, partes = None, []
            continue
        m = compilador.CITADA.match(crua)
        if m is not None and campo in ("msgid", "msgid_plural"):
            partes.append(m.group(1))
    if chave is not None and campo == "msgid":
        ids[chave] = compilador.descita(partes)
    elif chave is not None and campo == "msgid_plural":
        ids_plural[chave] = compilador.descita(partes)
    for k, t, f in itens:
        if isinstance(t, list):
            por_chave[k] = ((ids.get(k, ""), ids_plural.get(k, "")), t, f)
        else:
            por_chave[k] = (ids.get(k, ""), t, f)
    return cabecalho, por_chave


# A plural entry is a LIST, and ["", ""] is a true value in Python while meaning
# "nobody has written a word of this". Asking "if traducao" would count an empty
# Arabic plural as translated, mark it fuzzy against the English, and report it
# as kept - three wrong answers from one truthiness test. It lives in the
# compiler for the same reason the parser does: one copy, so it cannot drift.
tem_texto = compilador.tem_texto


def fonte_id(valor):
    """What gets written as the msgid of a translation, for drift comparison.

    Singular: the English sentence. Plural: the (singular, plural) pair, so a
    change to EITHER English form marks the translations fuzzy. Comparing a
    tuple against a list would never match and would mark every plural entry
    fuzzy on every run - which drops it from the catalogue, silently, one step
    downstream.
    """
    if isinstance(valor, list):
        return (valor[0], valor[-1])
    return valor


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
            elif tem_texto(traducao) and id_antigo != fonte_id(ingles[chave]):
                fuzzy = True
            if fuzzy and tem_texto(traducao):
                difusas += 1
            elif tem_texto(traducao):
                mantidas += 1
            else:
                novas += 1
        if fuzzy and tem_texto(traducao):
            saida.append("#, fuzzy")
        saida.append('msgctxt "%s"' % chave)
        if isinstance(ingles[chave], list):
            # A plural entry is written with THIS language's number of forms,
            # not English's. That is the whole point of the exercise: Arabic
            # gets six boxes in Poedit and Chinese gets one, instead of the two
            # a template hard-coded for everybody.
            fontes = ingles[chave]
            saida.append("msgid %s" % cita(fontes[0]))
            saida.append("msgid_plural %s" % cita(fontes[-1]))
            # A translation that is still a single string belongs to an entry
            # whose English has just gained plural forms, so it is already
            # marked fuzzy above and its text is not carried over. Seeding the
            # forms from it was tried here and removed: the fuzzy mark drops the
            # entry anyway, so the code read as a safety net while being
            # unreachable - the shape this project keeps catching in its own
            # instruments. A message that becomes plural gets its forms written
            # in every language, by hand, in the same commit.
            tem = traducao if isinstance(traducao, list) else []
            for i in range(compilador.formas(lingua)):
                saida.append("msgstr[%d] %s"
                             % (i, cita(tem[i] if i < len(tem) else "")))
        else:
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

    faltando = [k for k in ordem if not tem_texto(ingles[k])]
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
           # A TEMPLATE has no language, so it cannot have a plural rule. The
           # placeholder is gettext's own convention and it is what makes
           # "msginit -l ar" fill in Arabic's six forms; the English rule sat
           # here until 4.15, which is a rule for exactly one of seven.
           '"Plural-Forms: nplurals=INTEGER; plural=EXPRESSION;\\n"', ""]
    for chave in ordem:
        pot += ['msgctxt "%s"' % chave]
        if isinstance(ingles[chave], list):
            pot += ["msgid %s" % cita(ingles[chave][0]),
                    "msgid_plural %s" % cita(ingles[chave][-1]),
                    'msgstr[0] ""', 'msgstr[1] ""', ""]
        else:
            pot += ["msgid %s" % cita(ingles[chave]), 'msgstr ""', ""]
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
