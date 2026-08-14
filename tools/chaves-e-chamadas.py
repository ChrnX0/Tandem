#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Checks the catalogue against the code, in BOTH directions, plus placeholders.

    python3 tools/chaves-e-chamadas.py [--verbose]

Three questions, and each one is a failure this project has already had or is
one edit away from having:

  1. **A key that is called and does not exist.** t_msg prints the KEY NAME when
     a key is missing everywhere - which is right for a maintainer reading a log
     and is jargon on a shop counter. Exactly the reason t_erro_do_leitor checks
     a key exists before calling t_msg.

  2. **A key that exists and is never called.** Not a defect on screen, but it is
     translator effort spent on a message nobody will ever read, in seven
     languages, and it is usually the fossil of a feature that was removed. Five
     catalogues carry X-Reviewed-By-Speaker: no, so asking a volunteer to review
     dead text is a real cost.

  3. **PLACEHOLDER PARITY, which is the one that puts nonsense on the screen.**
     A message reading "it needs Java {1} and this machine has {2}" called with
     one argument renders a literal "{2}" to the owner. The reverse - passing
     three arguments to a message that uses two - silently drops data the
     sentence was supposed to carry.

WHY IT COUNTS ARGUMENTS BY WALKING RATHER THAN BY REGEX: the arguments to t_msg
are shell, and shell arguments contain quotes, $( ) and escaped newlines. The
literal counter in this project learned this the expensive way - a regex over
shell chops a call into debris and reports the debris. So this walks the call
from the key to the end of the command, tracking quote state and parenthesis
depth, and counts the top-level words.

WHAT IT CANNOT SEE, stated because a measure that hides its blind spot is the
problem it is meant to solve:
  - a key built at runtime ("leitor_$ficha", "res_${valor// /_}"). Those are
    resolved by their own guards - t_erro_do_leitor and t_resultado_amigavel both
    check the key exists before printing - and they are listed as DINAMICAS below
    so the unused-key half does not report their targets;
  - a call whose arguments come from a variable holding several words;
  - a message read from a .tsv table rather than from po/.
"""
import argparse
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PO = os.path.join(RAIZ, "po", "en.po")

ALVOS = ["src/bin", "src/lib"]

# Key families built at runtime. The prefix is listed, not each key: a key that
# only exists to be reached this way is used, even though no call site names it.
DINAMICAS = ("leitor_", "res_", "verbo_", "peca_", "pan_", "at_")

CHAMADA = re.compile(r"\bt_msg\s+([a-z0-9_]+)")


def chaves_do_catalogo():
    """key -> the highest {n} the English message uses."""
    chaves = {}
    atual = None
    corpo = []
    dentro = False
    with open(PO, encoding="utf-8") as f:
        for linha in f:
            m = re.match(r'^msgctxt\s+"(.+)"\s*$', linha)
            if m:
                if atual:
                    chaves[atual] = maior_placeholder("".join(corpo))
                atual = m.group(1)
                corpo = []
                dentro = False
                continue
            if linha.startswith("msgid"):
                dentro = True
            if linha.startswith("msgstr"):
                dentro = False
            if dentro:
                corpo.append(linha)
    if atual:
        chaves[atual] = maior_placeholder("".join(corpo))
    return chaves


def maior_placeholder(texto):
    n = 0
    for m in re.finditer(r"\{(\d)\}", texto):
        n = max(n, int(m.group(1)))
    return n


def conta_argumentos(texto, pos):
    """Top-level arguments after the key, or None when it cannot be counted.

    THE FIRST VERSION OF THIS RETURNED A NUMBER FOR EVERYTHING and produced
    nine findings, all nine of them wrong: it counted the words INSIDE a
    "$(...)" argument, and it matched t_msg inside a comment. That is the
    failure this project fears most in an instrument - a count that is mostly
    noise gets ignored, and that is how a real finding goes unread.

    So it now refuses to guess. A call whose arguments nest a command
    substitution is NOT counted; it is returned as None and reported as
    unchecked. Shell nesting is not something a walker of this size gets right,
    and "I did not check this one" is worth more than a number that is wrong.
    """
    i = pos
    n = 0
    fim = len(texto)
    em_palavra = False
    while i < fim:
        c = texto[i]
        if c in " \t":
            em_palavra = False
            i += 1
            continue
        if c == "\\" and i + 1 < fim and texto[i + 1] == "\n":
            i += 2
            continue
        if c in "\n;|&":
            break
        if c == ")":
            break                       # closes the $( ) this call sits in
        if c == '"':
            # One argument. If it nests a substitution, give up on the whole
            # call rather than miscount it.
            j = i + 1
            while j < fim and texto[j] != '"':
                if texto[j] == "\\":
                    j += 2
                    continue
                if texto[j:j + 2] == "$(":
                    return None
                j += 1
            n += 1
            i = j + 1
            em_palavra = False
            continue
        if texto[i:i + 2] == "$(":
            return None
        if c == "'":
            j = texto.find("'", i + 1)
            if j < 0:
                return None
            n += 1
            i = j + 1
            em_palavra = False
            continue
        if not em_palavra:
            n += 1
            em_palavra = True
        i += 1
    return n


def sem_comentarios(texto):
    """Blanks out comment bodies so a call named in prose is not a call.

    The first version matched "t_msg nao_consegui_ler" inside a paragraph of
    CLAUDE.md-style commentary in common.sh and reported it as a defect. Line
    positions are preserved so the reported line numbers stay true.
    """
    fora = []
    for linha in texto.split("\n"):
        despido = linha.lstrip()
        if despido.startswith("#"):
            fora.append("")
        else:
            fora.append(linha)
    return "\n".join(fora)


def arquivos():
    fora = []
    for alvo in ALVOS:
        d = os.path.join(RAIZ, alvo)
        for nome in sorted(os.listdir(d)):
            p = os.path.join(d, nome)
            if os.path.isfile(p) and (nome.endswith(".sh") or "." not in nome):
                fora.append(p)
    return fora


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    catalogo = chaves_do_catalogo()
    usadas = set()
    problemas = []

    nao_conferidas = 0
    for caminho in arquivos():
        texto = sem_comentarios(open(caminho, encoding="utf-8").read())
        rel = os.path.relpath(caminho, RAIZ)
        for m in CHAMADA.finditer(texto):
            chave = m.group(1)
            usadas.add(chave)
            linha = texto.count("\n", 0, m.start()) + 1
            if chave not in catalogo:
                problemas.append((rel, linha, chave,
                                  "called but not in po/en.po - t_msg would print "
                                  "the key name on screen"))
                continue
            precisa = catalogo[chave]
            passou = conta_argumentos(texto, m.end())
            if passou is None:
                # Reported, never counted as clean.
                nao_conferidas += 1
                if args.verbose:
                    print("unchecked: %s:%d %s (arguments nest a substitution)"
                          % (rel, linha, chave))
                continue
            if passou < precisa:
                problemas.append((rel, linha, chave,
                                  "the message uses {%d} and the call passes %d "
                                  "argument(s) - the owner reads a literal "
                                  "placeholder" % (precisa, passou)))
            elif precisa and passou > precisa:
                problemas.append((rel, linha, chave,
                                  "the call passes %d argument(s) and the message "
                                  "uses only {%d} - the rest is dropped"
                                  % (passou, precisa)))

    orfas = [k for k in sorted(catalogo)
             if k not in usadas and not k.startswith(DINAMICAS)]

    for rel, linha, chave, porque in problemas:
        print("%s:%d  %s  %s" % (rel, linha, chave, porque))
    if args.verbose:
        for k in orfas:
            print("unused: %s" % k)
    print("NAO CONFERIDAS %d" % nao_conferidas)
    print("CHAMADAS %d" % len(problemas))
    print("ORFAS %d" % len(orfas))
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
