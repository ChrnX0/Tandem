#!/usr/bin/env python3
"""Counts user-facing messages still written as literals in the code.

This exists because the check used during the first migration pass was WRONG.
It was "does the file still contain an accented character", and on that basis
tandem-snap was declared finished while

    t_pergunta "Instalar \"$NOME\" a partir deste arquivo?

was still a literal: accent-free Portuguese walks straight through an accent
grep. Count call sites instead.

A call site is CLEAN when its first argument is a t_msg lookup, or a bare
variable whose text was assembled from t_msg calls, or a pass-through to a
t_texto_* function whose text lives in common.sh and is counted there.

    tools/conta-literais.py            # a count per file
    tools/conta-literais.py --migrados # nothing must be left in these
"""
import re
import sys
import pathlib

RAIZ = pathlib.Path(__file__).resolve().parent.parent
ALVOS = sorted(RAIZ.glob("src/bin/tandem*")) + [RAIZ / "src/lib/common.sh"]

# Files whose migration is finished. Adding a name here IS the act of
# declaring it done, and --migrados then refuses to let it slip back.
MIGRADOS = {
    "tandem-exe", "tandem-script", "tandem-snap", "tandem-rpm",
    "tandem-android", "tandem-deb", "tandem-apk", "tandem-flatpak",
}

CHAMADA = re.compile(
    r"t_(?:erro|aviso|ok|pergunta|texto|progresso_abre|progresso_texto)"
    r'\s+"((?:[^"\\]|\\.)*)"',
    re.S,
)
# A message does not always reach t_erro as a literal argument: half of them are
# assembled into a variable first and the variable is passed. Those assignments
# are invisible to the pattern above, and four of them survived a file that had
# just been declared finished - the same class of miss as the accent grep, one
# level of indirection further out.
ATRIBUICAO = re.compile(
    r"\b(?:PORQUE|QUAL|PERGUNTA|ACAO|RESSALVA|ORIGEM_LICAO|MOTIVO|AVISO|EXTRA)"
    r'=\s*"((?:[^"\\]|\\.)*)"',
    re.S,
)
VARIAVEL = re.compile(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*")
LETRA = re.compile(r"[^\W\d_]", re.UNICODE)


def sem_expansoes(texto):
    """The argument with every $(...) and $VAR taken out.

    Balanced, because these arguments nest - $(t_msg x "$(basename -- "$f")")
    is one expansion inside another, and a non-greedy regex cuts it in the
    wrong place and leaves half a command looking like prose.
    """
    fora = []
    # walk it once, counting depth
    profundidade = 0
    i = 0
    while i < len(texto):
        if texto.startswith("$(", i):
            profundidade += 1
            i += 2
            continue
        if profundidade and texto[i] == ")":
            profundidade -= 1
            i += 1
            continue
        if not profundidade:
            fora.append(texto[i])
        i += 1
    return VARIAVEL.sub("", "".join(fora))


def e_literal(argumento):
    """True when the argument carries prose of its own.

    An argument is CLEAN when everything a person reads comes from a t_msg
    lookup: the message may be assembled from several of them plus data, so
    what matters is not the shape of the whole argument but whether any letter
    survives once the expansions are removed.
    """
    return bool(LETRA.search(sem_expansoes(argumento)))


def literais(caminho):
    texto = caminho.read_text(encoding="utf-8")
    achados = [m.group(1) for m in CHAMADA.finditer(texto)]
    achados += [m.group(1) for m in ATRIBUICAO.finditer(texto)]
    return [a for a in achados if e_literal(a)]


def main():
    so_migrados = "--migrados" in sys.argv
    total = 0
    falhou = False
    for alvo in ALVOS:
        if so_migrados and alvo.name not in MIGRADOS:
            continue
        restantes = literais(alvo)
        if not restantes:
            continue
        total += len(restantes)
        if so_migrados:
            falhou = True
            print("%s: %d literal(s) left in a file declared migrated"
                  % (alvo.name, len(restantes)))
            for r in restantes:
                print("    %s" % r.replace("\n", "\\n")[:70])
        else:
            print("%-26s %3d" % (alvo.relative_to(RAIZ), len(restantes)))
    if not so_migrados:
        print("%-26s %3d" % ("TOTAL", total))
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
