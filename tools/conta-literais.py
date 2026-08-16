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
# tandem-appimage and tandem-jar came off this list and are back on it, and the
# round trip is the point. They compared $ERRO against a Portuguese sentence,
# and $ERRO is a field the six Python readers produce and the handler prints
# verbatim - so those were real user-facing sentences living in files this tool
# had never opened, ALVOS globbing *.sh and src/bin only. The readers emit
# TOKENS now and the shell turns a token into a sentence, so what these two
# compare against is a name rather than prose. The suite reads the readers and
# demands a message for every token they can emit.
MIGRADOS = {
    "tandem-exe", "tandem-script", "tandem-snap", "tandem-rpm",
    "tandem-android", "tandem-deb", "tandem-apk", "tandem-flatpak",
    "tandem-jar", "tandem-appimage", "winedeps.sh",
}

# Exact strings this counter is told to ignore, each with the reason. A LIST OF
# DECISIONS, not a rule about shapes - a rule is what failed eleven times,
# whereas an exact string somebody had to add on purpose cannot quietly grow to
# cover new prose. Anything added here should be a name the owner has to see
# verbatim, or a value that lives on disk.
EXCECOES = {
    # Vendor product names. The owner searches for these on a manufacturer's
    # site, so a translated one is a dead end rather than a kindness.
    "Sentinel LDK Run-time Environment for Linux",
    "CodeMeter Runtime for Linux",
    "CodeMeter",
    # systemd unit and service names, matched against the running system.
    "waydroid-container",
    # An on-disk value, not prose. Rule: translating one of these breaks
    # compatibility with memory files already written on somebody's machine.
    "sim",
    # The product's own name, and the same name with its version beside it -
    # the first line of every report. Neither is prose: a translated product
    # name is a name that finds nothing.
    "Tandem",
    "Tandem $VERSAO\\n\\n",
    # The same pair again, as the PANEL's window title. 4.12 put the version
    # there because the owner asked the obvious question: the panel is the only
    # screen somebody who never opens a terminal ever sees, and finding out
    # which Tandem he was running meant opening one. Exempt for the reason
    # directly above - a product name is not prose, and translating it produces
    # a name that finds nothing.
    "Tandem $VERSAO",
    # THE COMMAND NAMES, which stay Portuguese forever - that is a standing
    # decision, not an oversight: a command copied off a forum has to work on
    # any machine, so these cannot move with the language. In the zenity panel
    # they are the machine-readable first column that `case "$esc" in` matches;
    # the human-readable second column beside each one IS counted, because that
    # is the part somebody reads.
    "instalar", "preparar", "programas", "remover", "android", "doctor",
    "autoteste", "dados", "portas", "identidade", "backup", "restore",
    "repair", "memoria", "lista", "enviar", "socorro", "logs",
    # Hardware and port labels. Windows calls them this, Wine counts them this
    # way, and a translated COM2 sends somebody looking for a port that does not
    # exist. COM$n is already handled by the same reasoning.
    "BIOS", "LPT$n", "COM$n",
    # A charmap name, compared against `locale charmap` output.
    "UTF-8",
    # The four the SIXTEENTH miss uncovered when printfs_com_prosa was finally
    # let into the handler executables. None is a sentence, and each is a
    # decision rather than a shape:
    #
    # The freedesktop section header of mimeapps.list. This is ON-DISK FORMAT,
    # written into the user's own file and grepped back out two lines later -
    # translating it would produce a file no desktop reads, which is the same
    # rule the memory-file values live under.
    "[Default Applications]\\n",
    "\\n[Default Applications]\\n",
    # A product name, and the fallback printed when `wine --version` says
    # nothing. A translated product name is a name that finds nothing.
    "Wine",
    # The command the owner COPIES. It is shown to him, but as something to
    # type rather than something to read, and winetricks does not accept a
    # translated verb or a translated flag.
    "winetricks -q %s\\n",
    # A systemd unit pair, queried with systemctl.
    "CodeMeter CodeMeterLin",
    # The port label with its device path, one field of a report line.
    "COM$n|$p",
    # The four PROVA levels, accumulated one per checked DLL and then resolved
    # by t_prova_do_run. On-disk values of exactly the kind the rule above
    # covers - they go into the memory file, into the recipe and into the list
    # record, and t_resultado_amigavel is what turns them into a sentence when
    # the owner is shown one. Translating one here would break every recipe
    # already written on somebody's machine, and would make the record
    # unreadable to api/lista.js and tools/monta-lista.py, which match the
    # literal word.
    "$PROVA_VISTAS entregue",
    "$PROVA_VISTAS bitola-errada",
    "$PROVA_VISTAS nao-chegou",
    # Two values of the FORMATO field the Android reader produces, compared
    # against and never shown - the handler answers each with a message of its
    # own. They read like Portuguese because the reader's output protocol was
    # written in Portuguese, and it is an on-disk-format decision of the same
    # kind as the memory files: changing one here changes it in apkinfo.py too,
    # or nothing matches. The ERRO field used to be the same shape of problem
    # and is not any more: the readers emit tokens and the shell translates
    # them, so nothing there is prose to begin with.
    "desconhecido", "apk",
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


def printfs_com_prosa(texto, tudo=False):
    """SIXTEENTH miss, and it is the thirteenth's twin left in the sibling.

    The thirteenth was that the prose-body rule keys off function names while
    the eleven handler executables define none, so both this rule and
    citadas_com_prosa were dead code inside them. Only citadas_com_prosa got
    the `tudo` fix; this one kept walking corpos_de_mensagem and stayed blind
    in exactly the files the fix was written for.

    What that left uncovered is narrow and real: citadas_com_prosa subsumes the
    double-quoted half, so the gap is a SINGLE-QUOTED printf format at the top
    level of a handler. Proven by injection rather than by reading - a
    `printf 'Associacoes reaplicadas com sucesso\\n'` put at the top of
    tandem-repair scored TOTAL 0.
    """
    achados = []
    corpos = ([("(arquivo)", texto)] if tudo
              else list(corpos_de_mensagem(texto)))
    for _nome, corpo in corpos:
        # The cleaning is what makes `tudo` safe, and leaving it out is how the
        # first version of this widening INVENTED twelve findings: a
        # mimeapps.list section header, eight .desktop filenames, a product
        # name and a winetricks command line. Scoped to a t_texto_*/acao_* body
        # every printf is prose by construction and no filter was needed; over
        # a whole handler it is not, because the same file also writes files
        # and runs commands. A tool that invents findings is worse than one
        # that misses them - somebody has to prove each one is nothing.
        if tudo:
            corpo = sem_destinos_nao_humanos(sem_linhas_de_log(corpo))
        for padrao in (PRINTF, PRINTF_ARG):
            for m in padrao.finditer(corpo):
                bruto = m.group(1)
                if tudo:
                    # Over a whole handler the crude test below is not enough:
                    # it reported a mimeapps.list section header, eight
                    # .desktop filenames, a product name and a winetricks
                    # command line. These are the SAME two gates
                    # citadas_com_prosa applies, and they have to be applied
                    # here for the same reason - the widened scope sees the
                    # file writes and the command lines too.
                    if bruto in EXCECOES or bruto.strip() in EXCECOES:
                        continue
                    if not _e_prosa(bruto):
                        continue
                    achados.append(bruto)
                    continue
                if BINARIO.search(bruto):
                    continue
                resto = FORMATO.sub("", bruto)
                resto = sem_expansoes(resto).strip()
                # Three letters in a row is a word. One or two are a unit, an
                # initial, or the tail of an escape.
                if re.search(r"[^\W\d_]{3,}", resto, re.UNICODE):
                    achados.append(bruto)
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
# ELEVENTH, and it hid the primary interface. acao_painel builds the whole
# zenity menu out of BARE ARGUMENTS:
#
#     "instalar"  "Instalar ou abrir um arquivo (.exe .apk .AppImage .jar .deb)"
#
# Eighteen rows of Portuguese, plus the window's own question and the file
# chooser's filter label - the first and only screen a shop owner who never
# opens a terminal ever sees - and they are neither an assignment nor a printf
# nor a heredoc nor a call to t_erro, so every previous version of this counter
# scored them as zero.
#
# The lesson has now cost eleven rounds, so the rule stops chasing shapes: in a
# body that exists to produce prose, EVERY double-quoted string is examined, no
# matter what syntax surrounds it. Assignment, append, printf argument, zenity
# argument, function argument - all the same. What keeps this usable is the
# EXCECOES list below, which is a set of exact strings somebody had to add on
# purpose, and a rule about non-prose shapes: a path, a flag, a MIME type.
#
# A rule about syntax is what failed eleven times. A rule about content, with
# named exceptions, cannot quietly grow to cover new prose.
# Finding those strings needs a walk, not a regex. A regex over shell matches
# the wrong quotes: it cuts a string in half at a quote that lives INSIDE a
# $(...) - "$(basename -- "$f") is here" has three of them - and reports the
# fragment as prose. The first version of this rule scored 271 that way, most of
# it shell pipeline debris like " | cut -d'|' -f2)", and a count that is mostly
# noise gets ignored, which is how a real one goes unread.
def citadas_do_topo(corpo):
    """Every double-quoted string a person could read, from a shell body.

    Two rules, and the difference between them is the whole function:

      - OUTSIDE a string, a $( ) is a command whose arguments may themselves be
        messages, so walk INTO it. The zenity panel is built entirely inside one
        - esc="$(zenity --list ... "instalar" "Instalar ou abrir um arquivo")" -
        so a walker that skipped command substitutions could not see the primary
        interface of this program. That was miss number eleven.
      - INSIDE a string, a $( ) does not contribute to THAT sentence - its own
        quotes must not end the string early, and its output is data, not prose:
        "$(basename -- "$f") is here" holds three quotes and one message. But it
        is still walked into, because the panel's whole menu lives inside a
        substitution that is itself the entire value of a string:
        esc="$(zenity --list ... "instalar" "Instalar ou abrir um arquivo")".
        Skipping it outright hid eighteen rows of Portuguese; treating its text
        as part of the outer sentence would invent a sentence nobody wrote.

    A regex cannot make that distinction, which is why this is a walk.
    """
    saida = []
    i = 0
    n = len(corpo)
    while i < n:
        c = corpo[i]
        if c == "\\":
            i += 2
            continue
        if c == "#" and (i == 0 or corpo[i - 1] in " \t\n"):
            j = corpo.find("\n", i)          # a comment, to end of line
            i = n if j < 0 else j + 1
            continue
        if c == "'":                          # no expansion inside single quotes
            j = corpo.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if corpo.startswith("${", i):         # a parameter expansion is data
            i = _fim_da_expansao(corpo, i)
            continue
        if corpo.startswith("$(", i):         # a command: its arguments count
            fim = _fim_da_expansao(corpo, i)
            saida.extend(citadas_do_topo(corpo[i + 2:max(i + 2, fim - 1)]))
            i = fim
            continue
        if c == '"':
            texto, i, aninhadas = _le_string(corpo, i)
            saida.append(texto)
            saida.extend(aninhadas)
            continue
        i += 1
    return saida


def _fim_da_expansao(corpo, i):
    """Index just past the $( ) or ${ } starting at i."""
    abre, fecha = corpo[i + 1], ")" if corpo[i + 1] == "(" else "}"
    profundidade = 1
    j = i + 2
    while j < len(corpo) and profundidade:
        if corpo[j] == "\\":
            j += 2
            continue
        if corpo[j] == abre:
            profundidade += 1
        elif corpo[j] == fecha:
            profundidade -= 1
        j += 1
    return j


def _le_string(corpo, i):
    """The double-quoted string at i: its own prose, where it ends, and any
    messages found inside the commands it interpolates.

    The two are kept apart on purpose. A $( ) inside a string does not belong to
    that string's sentence - gluing its text in would invent a sentence nobody
    wrote - but the command inside it may carry messages of its own, and one of
    them is the whole zenity panel.
    """
    pedacos = []
    aninhadas = []
    j = i + 1
    n = len(corpo)
    while j < n:
        if corpo[j] == "\\":
            pedacos.append(corpo[j:j + 2])
            j += 2
            continue
        if corpo[j] == '"':
            break
        if corpo.startswith("${", j):        # a parameter expansion is only data
            j = _fim_da_expansao(corpo, j)
            continue
        if corpo.startswith("$(", j):
            fim = _fim_da_expansao(corpo, j)
            aninhadas.extend(citadas_do_topo(corpo[j + 2:max(j + 2, fim - 1)]))
            j = fim
            continue
        pedacos.append(corpo[j])
        j += 1
    return "".join(pedacos), j + 1, aninhadas


def _e_prosa(bruto):
    """True when this quoted string is something a person reads."""
    if BINARIO.search(bruto):
        return False
    resto = FORMATO.sub("", bruto)
    resto = sem_expansoes(resto).strip()
    if not re.search(r"[^\W\d_]{3,}", resto, re.UNICODE):
        return False
    # No whitespace and a slash or a dot: a path, a filename, a MIME type, a
    # version, a glob. Without this every file the commands open is reported as
    # a message, and a report that is mostly noise is a report nobody reads.
    if " " not in resto and re.search(r"[/.]", resto):
        return False
    if resto.startswith("-"):
        return False
    # A zenity/getopt option written as one word with an equals sign, e.g.
    # --file-filter=..., survives the dash test once the value is data.
    if "=" in resto and " " not in resto.split("=")[0]:
        return False
    return True


# The log is a different audience with a documented exception, and this rule
# could not see the difference. t_diz writes to the log file that "tandem logs"
# shows and "tandem socorro" bundles up - read by whoever is helping, not by the
# shop owner - and by a decision recorded in CLAUDE.md those lines stay
# Portuguese. Every earlier version of the counter missed them for the wrong
# reason (they are not assignments); this one caught them for the wrong reason
# too (they are quoted strings inside an acao_* body).
#
# So a t_diz command is skipped by name. That is a rule about syntax, which is
# what failed twelve times, and it is defensible only because it is not a guess
# about SHAPE: t_diz cannot reach the user at all - it appends to a file - so a
# sentence there is a sentence for a maintainer by construction. If that ever
# stops being true, this is the line that has to go.
T_DIZ = re.compile(r"(?m)^[^\n]*?\bt_diz\s.*$")


def sem_linhas_de_log(corpo):
    return T_DIZ.sub("", corpo)


# Widening the scope to whole handler files brought in three kinds of string
# that no person ever reads, and they have to be excluded by DESTINATION rather
# than by looking like code - "it looks like code" is the guess that failed
# thirteen times, while "nothing human is at the other end of this argument" is
# checkable. Same footing as the t_diz exemption above.
#
#   t_memoria_grava / t_config_grava  the value goes into a state file, and
#       those values stay Portuguese by a standing decision - translating one
#       silently breaks memory files and recipes already on somebody's machine.
#   t_como_root / t_script_instalacao  the argument is a shell script that gets
#       EXECUTED. "apt-get install -y" is not a sentence.
#   grep / sed / awk  the argument is a program for another tool.
#
# The commands are blanked with spaces rather than deleted, so every offset in
# the file stays where it was and the comment and log rules keep working.
DESTINO_NAO_HUMANO = re.compile(
    r"(?:^|[\s;(){}&|])(t_memoria_grava|t_config_grava|t_como_root"
    r"|t_script_instalacao|grep|sed|awk)\s")


def sem_destinos_nao_humanos(corpo):
    pedacos = list(corpo)
    for m in DESTINO_NAO_HUMANO.finditer(corpo):
        for j in range(m.end(), _fim_do_comando(corpo, m.end())):
            if pedacos[j] != "\n":
                pedacos[j] = " "
    return "".join(pedacos)


def citadas_com_prosa(texto, tudo=False):
    """Every readable string in the prose-producing bodies - or in the whole
    file when `tudo`, which is what a handler executable needs.

    THIRTEENTH miss, and it is the largest scoping error this tool has had: the
    prose-body rule keys off function names (t_texto_*, t_causa_*, acao_*,
    uso), and **the eleven handler executables define no functions at all**.
    They are straight-line scripts. So in tandem-repair, tandem-deb,
    tandem-jar and the eight others, this rule and printfs_com_prosa were
    dead code - and what they missed was not a corner: the whole report of
    `tandem repair`, the command the README tells an owner to run when a
    double click opens the wrong program, printed "Associações reaplicadas",
    "antes:", "agora:", "nenhum" and a sentence telling them to log out and
    back in, in Portuguese, while this tool printed TOTAL 0.
    """
    achados = []
    corpos = ([("(arquivo)", texto)] if tudo
              else list(corpos_de_mensagem(texto)))
    for _nome, corpo in corpos:
        limpo = sem_destinos_nao_humanos(sem_linhas_de_log(corpo))
        for bruto in citadas_do_topo(limpo):
            if bruto in EXCECOES or bruto.strip() in EXCECOES:
                continue
            if _e_prosa(bruto):
                achados.append(bruto)
    return achados


# FOURTEENTH, found in the same reading and worth its own rule because it is a
# different shape: CHAMADA above captures the FIRST quoted argument of a
# message call and stops there. So
#
#     t_pergunta "$(t_msg funcionou_como_esperava)" "Sim, funcionou" "Não, algo saiu errado"
#
# read as clean - the first argument is a t_msg lookup with no prose of its own,
# and the two BUTTON LABELS were never looked at by anything. Those buttons are
# how the owner answers "did this program actually work?", the question the whole
# silent-success mechanism exists to ask, and they were Portuguese in a shipped
# release. Five more call sites had the same two words.
#
# The fix is to read the WHOLE command rather than one argument of it, which
# needs the same walk as everywhere else: a regex cannot find where a shell
# command ends when its arguments contain quotes, $( ) and escaped newlines.
MENSAGEIRO = re.compile(
    r"(?:^|[\s;(){}&|])(t_(?:erro|aviso|ok|pergunta|texto"
    r"|progresso_abre|progresso_texto))\s")


def _fim_do_comando(corpo, i):
    """Index just past the simple command whose arguments start at i.

    A backslash-newline continues the command, which is why the escape branch
    comes first: three of the calls this had to find are written across two
    lines.
    """
    n = len(corpo)
    while i < n:
        c = corpo[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = corpo.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            _texto, i, _aninhadas = _le_string(corpo, i)
            continue
        if corpo.startswith("$(", i) or corpo.startswith("${", i):
            i = _fim_da_expansao(corpo, i)
            continue
        if c in ";|&\n)}":
            return i
        i += 1
    return n


def _em_comentario(texto, pos):
    inicio = texto.rfind("\n", 0, pos) + 1
    return "#" in texto[inicio:pos]


def chamadas_com_prosa(texto):
    achados = []
    limpo = sem_destinos_nao_humanos(sem_linhas_de_log(texto))
    for m in MENSAGEIRO.finditer(limpo):
        # These same call shapes are quoted in the comments that explain them,
        # and a comment is not a message.
        if _em_comentario(limpo, m.start(1)):
            continue
        i = m.end()
        for bruto in citadas_do_topo(limpo[i:_fim_do_comando(limpo, i)]):
            if bruto in EXCECOES or bruto.strip() in EXCECOES:
                continue
            if _e_prosa(bruto):
                achados.append(bruto)
    return achados


def literais(caminho):
    texto = caminho.read_text(encoding="utf-8")
    achados = [m.group(1) for m in CHAMADA.finditer(texto)]
    achados += [m.group(1) for m in ATRIBUICAO.finditer(texto)]
    achados = [a for a in achados if e_literal(a)]
    # citadas_com_prosa subsumes the double-quoted half of printfs_com_prosa,
    # but not the single-quoted one - which is exactly how the t_texto_*
    # builders write their formats - so both still run. The dedup keeps a
    # string found by two routes from being counted twice.
    # A handler executable has no prose-named function to scope to, because it
    # has no functions: the file IS the body. That is a rule about which files,
    # not about which syntax - and syntax is what failed twelve times.
    tudo = caminho.name.startswith("tandem-")
    todos = (achados + printfs_com_prosa(texto, tudo=tudo)
             + heredocs_com_prosa(texto)
             + citadas_com_prosa(texto, tudo=tudo)
             + chamadas_com_prosa(texto))
    vistos = set()
    unicos = []
    for a in todos:
        if a.strip() in EXCECOES or a in vistos:
            continue
        vistos.add(a)
        unicos.append(a)
    return unicos


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
