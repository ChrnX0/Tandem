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
# Every shell file that can talk to a person. It listed only src/bin plus
# common.sh, so winedeps.sh - which holds the bitness dead end and the
# suspicious-DLL verdict, both printed straight to the owner by tandem-exe -
# was never even opened. Fifth time this measure was narrower than reality.
ALVOS = sorted(RAIZ.glob("src/bin/tandem*")) + sorted(RAIZ.glob("src/lib/*.sh"))

# Files whose migration is finished. Adding a name here IS the act of
# declaring it done, and --migrados then refuses to let it slip back.
# "tandem" and "common.sh" were on this list and had no business being there:
# 75 sentences between them, including the whole of "tandem doctor", the zenity
# panel's own prompt, the hardware-key advice and the longest message in the
# program. They were declared done on the word of a counter that could not see
# an "out+=" append or a printf whose prose is in the argument rather than the
# format. Declaring a file finished is a claim about the file, not about the
# tool, and the two got confused for two versions.
MIGRADOS = {
    "tandem-exe", "tandem-script", "tandem-snap", "tandem-rpm",
    "tandem-android", "tandem-deb", "tandem-apk", "tandem-flatpak",
    "tandem-jar", "tandem-appimage", "winedeps.sh",
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
    r"|saida|texto|aviso|motivo|faixa|dev|plano|lista|nomes)"
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
        # A backslash-escaped character is never structure. Without this, the
        # \) inside a sed script closed the $( that had not been opened by it,
        # and the rest of a shell command came out looking like a sentence -
        # which put "/proc/meminfo" on the list of messages to translate.
        if texto[i] == "\\":
            if not profundidade:
                fora.append(texto[i:i + 2])
            i += 2
            continue
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
    # A capture with an unbalanced ${ is not a value, it is the regex having
    # stopped at a quote that lives INSIDE a parameter expansion -
    # texto="${texto%"$nl"}" captures only '${texto%'. Reporting that as a
    # message sends somebody looking for prose in a string-trimming line.
    if argumento.count("${") != argumento.count("}"):
        return False
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
# Sixth: a printf inside an acao_* command was invisible too, because this was
# scoped to the t_texto_* helpers alone. acao_alternativas printed its heading
# that way and it survived a file reported as finished.
FUNCAO_MENSAGEM = re.compile(
    r"^((?:t_(?:texto|causa)_|acao_)[a-z_0-9]+|uso)\(\)\s*\{", re.M)
PRINTF = re.compile(r"printf\s+(?:--\s+)?'((?:[^'\\]|\\.)*)'")
# TENTH shape, found while fixing the ninth: printf's prose does not have to be
# in the format string. t_texto_vm writes
#
#     printf '%s' "Existe um caminho mais pesado, ..."
#
# and PRINTF above matched only the '%s', which has no letters in it - so a
# fifteen-line paragraph about running a real Windows in a virtual machine, the
# longest single message in the program, counted as zero. The lesson holds: every
# version of this measure built from the shapes in front of me has passed
# falsely, so this number is a FLOOR, not a total.
PRINTF_ARG = re.compile(r'printf\s+(?:--\s+)?(?:\'[^\']*\'|"[^"]*")\s+"((?:[^"\\]|\\.)*)"')
FORMATO = re.compile(r"%[-+ #0-9.]*[a-zA-Z]|\\[nt]")
# An octal escape means binary, not prose. The ELF magic the self-test writes to
# build a fake executable spells "ELF" in the middle of it.
BINARIO = re.compile(r"\\[0-7]{3}")


# And a SEVENTH shape, which was the worst of them: a heredoc. uso() is
# `cat <<'AJUDA'` followed by forty lines of help text - the single most-read
# screen in the whole program - and six versions of this counter scored it as
# zero, because it is neither a call nor an assignment nor a printf.
HEREDOC = re.compile(r"<<-?'?([A-Z_][A-Z_0-9]*)'?\s*\n(.*?)\n\1", re.S)


def heredocs_com_prosa(texto):
    """Heredoc bodies that read like sentences rather than like code.

    A heredoc is also how this project embeds shell scripts to run as root, so
    the test cannot be "does it contain words". A body whose lines mostly begin
    with a command, a brace or a pipe is code; one with several lines of plain
    running text is prose.
    """
    achados = []
    for m in HEREDOC.finditer(texto):
        corpo = m.group(2)
        linhas = [l for l in corpo.splitlines() if l.strip()]
        if not linhas:
            continue
        codigo = sum(1 for l in linhas if re.match(
            r"\s*(if|fi|then|else|elif|for|do|done|case|esac|while|echo|printf|"
            r"cat|cd|apt|apt-get|dpkg|python3|import|urllib|\.|\}|\{|\||>|#|\$)",
            l))
        if codigo > len(linhas) / 2:
            continue
        if sum(1 for l in linhas if re.search(r"[^\W\d_]{3,}", l, re.UNICODE)) >= 2:
            achados.append(corpo)
    return achados


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
        for padrao in (PRINTF, PRINTF_ARG):
            for m in padrao.finditer(corpo):
                if BINARIO.search(m.group(1)):
                    continue
                resto = FORMATO.sub("", m.group(1))
                resto = sem_expansoes(resto).strip()
                # Three letters in a row is a word. One or two are a unit, an
                # initial, or the tail of an escape.
                if re.search(r"[^\W\d_]{3,}", resto, re.UNICODE):
                    achados.append(m.group(1))
    return achados


# And an EIGHTH shape - ninth, counting the lowercase name that got away once -
# and it hid the second most-read screen in the program. acao_doctor does not
# printf and does not call t_erro: it appends its whole report, line by line,
# into a variable with
#
#     out+="SISTEMA\n"
#
# ATRIBUICAO above is a WHITELIST OF VARIABLE NAMES, and "out" was not on it, so
# forty-odd lines of Portuguese - the entire diagnostic an English-speaking user
# reads, and the thing "tandem socorro" ships to whoever is helping them - were
# scored as zero while this tool printed TOTAL 0 and the suite asserted that
# number. Found by installing the built package and reading the output, which is
# the only method that has ever caught this measure being wrong.
#
# So the whitelist stops here. Inside a body that exists to produce prose, EVERY
# assignment and append is examined, whatever it is called. The narrowing that
# keeps this usable is the body, not the name: t_texto_*, t_causa_*, acao_* and
# uso() are where sentences are assembled, and a string assignment in one of
# them is a message until proven otherwise.
ATRIBUICAO_QUALQUER = re.compile(
    r'\b[A-Za-z_][A-Za-z0-9_]*\+?=\s*"((?:[^"\\]|\\.)*)"')


def atribuicoes_com_prosa(texto):
    achados = []
    for _nome, corpo in corpos_de_mensagem(texto):
        for m in ATRIBUICAO_QUALQUER.finditer(corpo):
            bruto = m.group(1)
            if BINARIO.search(bruto):
                continue
            resto = FORMATO.sub("", bruto)
            resto = sem_expansoes(resto).strip()
            if not re.search(r"[^\W\d_]{3,}", resto, re.UNICODE):
                continue
            # A value with no whitespace that carries a slash or a dot is a
            # path, a filename, a MIME type or a version - not a sentence.
            # Without this the file paths every acao_* opens are all reported
            # as messages, and a report that is mostly noise gets ignored,
            # which is how a real one goes unread.
            if " " not in resto and re.search(r"[/.]", resto):
                continue
            if resto.startswith("-") and " " not in resto:
                continue
            achados.append(bruto)
    return achados


# Strings that are NOT prose and must never be translated, listed one by one
# with the reason. This is a list of decisions, not a rule about shapes: a rule
# is what let nine versions of this counter pass falsely, whereas an exact string
# that somebody had to add on purpose cannot quietly grow to cover new prose. If
# you find yourself adding a sentence here, you are doing it wrong.
EXCECOES = {
    # Vendor product names. The owner is told to fetch these FROM THE
    # MANUFACTURER, by the name the manufacturer uses; a translated product
    # name is a name that finds nothing.
    "Sentinel LDK Run-time Environment for Linux",
    "CodeMeter Runtime for Linux",
    "CodeMeter",
    # systemd unit names, queried with systemctl.
    "CodeMeter CodeMeterLin",
    # Windows serial-port labels. Wine counts the phantom ports too, so these
    # numbers have to match what Wine shows - and COM is not a word.
    "COM$n",
    "COM$n|$p",
    # An on-disk value, not prose. Rule: translating one breaks memory files
    # and recipes already written on somebody's machine.
    "sim",
}


def literais(caminho):
    texto = caminho.read_text(encoding="utf-8")
    achados = [m.group(1) for m in CHAMADA.finditer(texto)]
    achados += [m.group(1) for m in ATRIBUICAO.finditer(texto)]
    achados = [a for a in achados if e_literal(a)]
    todos = (achados + printfs_com_prosa(texto) + heredocs_com_prosa(texto)
             + atribuicoes_com_prosa(texto))
    return [a for a in todos if a.strip() not in EXCECOES]


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
