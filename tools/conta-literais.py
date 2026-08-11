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
    "tandem-android", "tandem-deb", "tandem-apk", "tandem-flatpak", "tandem-jar", "tandem-appimage",
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
#
# Then it happened a THIRD time. common.sh reported zero while 149 lines of
# Portuguese sat in the t_texto_* builders, because those assemble into a
# lowercase "saida" rather than into one of the names above. Every time this
# measure has been narrowed to what was in front of me, it has declared
# something finished that was not.
ATRIBUICAO = re.compile(
    r"\b(?:PORQUE|QUAL|PERGUNTA|ACAO|RESSALVA|ORIGEM_LICAO|MOTIVO|AVISO"
    r"|saida|texto|aviso|motivo)"
    r'\+?=\s*"((?:[^"\\]|\\.)*)"',
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
    resto = sem_expansoes(argumento).strip()
    # A single token starting with a dash is a command-line flag, not a
    # sentence: EXTRA="--appimage-extract-and-run" has letters in it and is
    # nobody's message.
    if resto.startswith("-") and " " not in resto:
        return False
    return bool(LETRA.search(resto))


# And a FOURTH shape, the largest of them. The t_texto_* and t_causa_* helpers
# in common.sh do not assign or pass anything: they printf their prose straight
# out, in single quotes, one line per printf. That is roughly 150 lines of
# Portuguese that three successive versions of this counter reported as zero.
#
# Only these builders are scanned this way. printf is the workhorse of the
# whole codebase - alignment, log lines, pure format strings - and treating
# every one of them as a message would drown the real ones.
FUNCAO_MENSAGEM = re.compile(r"^(t_(?:texto|causa)_[a-z_0-9]+)\(\)\s*\{", re.M)
PRINTF = re.compile(r"printf\s+(?:--\s+)?'((?:[^'\\]|\\.)*)'")
FORMATO = re.compile(r"%[-+ #0-9.]*[a-zA-Z]|\\[nt]")


def corpos_de_mensagem(texto):
    """Each t_texto_*/t_causa_* body, found by counting braces."""
    for m in FUNCAO_MENSAGEM.finditer(texto):
        i = texto.index("{", m.start())
        profundidade = 0
        for j in range(i, len(texto)):
            if texto[j] == "{":
                profundidade += 1
            elif texto[j] == "}":
                profundidade -= 1
                if profundidade == 0:
                    yield m.group(1), texto[i:j]
                    break


def printfs_com_prosa(texto):
    achados = []
    for _nome, corpo in corpos_de_mensagem(texto):
        for m in PRINTF.finditer(corpo):
            resto = FORMATO.sub("", m.group(1))
            # Three letters in a row is a word. One or two are a unit, an
            # initial, or the tail of an escape.
            if re.search(r"[^\W\d_]{3,}", resto, re.UNICODE):
                achados.append(m.group(1))
    return achados


def literais(caminho):
    texto = caminho.read_text(encoding="utf-8")
    achados = [m.group(1) for m in CHAMADA.finditer(texto)]
    achados += [m.group(1) for m in ATRIBUICAO.finditer(texto)]
    achados = [a for a in achados if e_literal(a)]
    return achados + printfs_com_prosa(texto)


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
