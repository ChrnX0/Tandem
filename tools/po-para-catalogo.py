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
PLURAL_N = re.compile(r'^msgstr\[(\d+)\]\s*(.*)$')

# How many plural forms each language has, and the gettext rule that produces
# them. THE RULE IS HERE FOR TRANSLATORS AND FOR VALIDATION ONLY - it is never
# evaluated, not here and not at runtime. The runtime rule is written as shell
# code in t_plural_indice, and t_plural_formas holds the same counts; a test
# asserts the two agree.
#
# That split is the whole security design and it is not negotiable. A gettext
# plural rule is a C expression, and evaluating one that arrived in a catalogue
# would put "$(( ))" around text from a stranger - undoing the property this
# format exists to have, which is that a message is data and can never be code.
# So the .po carries the rule as documentation for Poedit and Weblate, and the
# program carries it as code.
PLURAIS = {
    "en":    (2, "nplurals=2; plural=(n != 1);"),
    "es":    (2, "nplurals=2; plural=(n != 1);"),
    "hi":    (2, "nplurals=2; plural=(n != 1);"),
    # Portuguese and French count 0 as singular: "0 minuto", "0 minute".
    "pt_BR": (2, "nplurals=2; plural=(n > 1);"),
    "fr":    (2, "nplurals=2; plural=(n > 1);"),
    # Chinese has one form. Writing two here would ask a translator to invent a
    # distinction the language does not make.
    "zh_CN": (1, "nplurals=1; plural=0;"),
    "ar":    (6, "nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : "
                 "n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);"),
}


def tem_texto(valor):
    """Is anything actually translated here? A plural entry is a LIST."""
    if isinstance(valor, list):
        return any(f for f in valor)
    return bool(valor)


def formas(lingua):
    return PLURAIS.get(lingua, PLURAIS[PADRAO])[0]


def regra(lingua):
    return PLURAIS.get(lingua, PLURAIS[PADRAO])[1]


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

    A translation is a STRING for an ordinary entry and a LIST of forms for a
    plural one:

        msgctxt "progresso_ha_minutos"
        msgid "Still working. {1} minute so far."
        msgid_plural "Still working. {1} minutes so far."
        msgstr[0] "Ainda trabalhando. Ja vai {1} minuto."
        msgstr[1] "Ainda trabalhando. Ja vao {1} minutos."

    Until 4.15 neither of those last three lines matched anything in this
    parser: "msgstr[0] " does not start with "msgstr ", so the whole entry fell
    through and was DROPPED - no output, no warning, exit 0. Measured, not
    supposed: a probe entry appended to po/en.po compiled to a catalogue that
    did not contain it and the tool reported the same count as before.
    That is the worst shape a bug can have here, because the people it silently
    discards are exactly the volunteers this format was adopted to attract.

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
    plurais, indice = {}, None

    def guarda():
        """Bank the msgstr[N] chunk that was being read, if there was one."""
        nonlocal plurais, indice
        if campo == "msgstr_n" and indice is not None:
            plurais[indice] = descita(partes)
        indice = None

    def fecha():
        nonlocal ctx, partes, campo, fuzzy, plurais, indice
        guarda()
        if ctx is not None and plurais:
            # Dense, so form 3 of a six-form language cannot silently become
            # form 1 by being the second one anybody happened to fill in.
            valor = [plurais.get(i, "") for i in range(max(plurais) + 1)]
            itens.append((ctx, valor, fuzzy))
        elif campo == "msgstr" and ctx is not None:
            itens.append((ctx, descita(partes), fuzzy))
        ctx = None
        partes, campo, fuzzy = [], None, False
        plurais, indice = {}, None

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
        if crua.startswith("msgid_plural "):
            # Read and discarded: the English plural is authoring material for
            # the translator's tool. What ships is the msgstr forms. It still
            # has to be RECOGNISED, so its continuation lines do not get
            # appended to the msgid above it.
            campo, partes = "msgid_plural", []
            continue
        if crua.startswith("msgid "):
            campo, partes = "msgid", []
            m = CITADA.match(crua[6:].strip())
            if m and m.group(1):
                partes.append(m.group(1))
            continue
        mp = PLURAL_N.match(crua)
        if mp is not None:
            guarda()
            indice = int(mp.group(1))
            campo, partes = "msgstr_n", []
            m = CITADA.match(mp.group(2).strip())
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
        if isinstance(texto, list):
            # One key per plural form. The runtime picks the form with a rule
            # written in shell, and falls back form -> form 0 -> the plain key
            # -> English, so a language that has filled in none of them keeps
            # whatever single sentence it already had.
            for i, forma in enumerate(texto):
                if not forma:
                    continue
                saida.append("@%s#%d" % (chave, i))
                saida.append(forma)
                saida.append("")
            continue
        saida.append("@%s" % chave)
        saida.append(texto)
        saida.append("")
    return "\n".join(saida).rstrip("\n") + "\n"


def confere_plurais(lingua, itens, cabecalho):
    """Complains, out loud and with a non-zero exit, instead of dropping.

    The rule this enforces is not "the file is tidy". It is that NOTHING A
    TRANSLATOR WROTE MAY VANISH WITHOUT A WORD. A form numbered past the end of
    the language's own rule cannot be reached by any count, so shipping it
    quietly would spend somebody's afternoon and deliver nothing.
    """
    ruins = 0
    limite = formas(lingua)
    for chave, texto, _fuzzy in itens:
        if not isinstance(texto, list):
            continue
        if len(texto) > limite:
            print("po/%s.po: '%s' has %d plural forms and %s has %d - "
                  "form %d would never be shown to anybody"
                  % (lingua, chave, len(texto), lingua, limite, limite))
            ruins += 1
    declarada = cabecalho.get("Plural-Forms", "").strip()
    if declarada and declarada.rstrip(";") != regra(lingua).rstrip(";"):
        # Not cosmetic: this line is what Poedit and Weblate show a translator,
        # so a wrong one asks for the wrong number of boxes. Every .po in this
        # tree carried the English rule until 4.15, including Arabic's, which
        # needs six.
        print("po/%s.po: Plural-Forms says %r; %s is %r"
              % (lingua, declarada, lingua, regra(lingua)))
        ruins += 1
    return ruins


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
        problemas += confere_plurais(lingua, itens, cabecalho)
        novo = escreve_catalogo(lingua, itens, cabecalho)
        destino = os.path.join(IDIOMAS, lingua + ".txt")
        atual = io.open(destino, encoding="utf-8").read() if os.path.exists(destino) else None
        # tem_texto, not "if t": a plural entry nobody has touched parses to
        # ["", ""], which is a TRUE value in Python while meaning the opposite.
        # Written as "if t" this line would report a blank Arabic plural as
        # translated - a quietly wrong number, which is the kind this project
        # keeps finding in its own instruments.
        traduzidas = sum(1 for _, t, f in itens if tem_texto(t) and not f)
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
