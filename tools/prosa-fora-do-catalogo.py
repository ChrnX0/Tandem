#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Runs Tandem in Chinese and reads what actually comes out.

    python3 tools/prosa-fora-do-catalogo.py [--verbose]

WHY THIS EXISTS, AND WHY IT IS NOT A WIDER conta-literais.py
------------------------------------------------------------
tools/conta-literais.py reads the SOURCE and asks "what shape of shell hides a
sentence?". Fifteen revisions of that question, fifteen misses, three published
zeros. The sixteenth miss was found by a human reading src/lib/winedeps.sh:
t_verbo_amigavel returned "Editor de texto rico", "Depurador do Windows" and
seven more, in Portuguese, to every user of every language, while the counter
printed TOTAL 0. It could not have been otherwise - that function's name matches
no prose-body pattern and it lives in a library rather than in a handler, so
every rule the counter has was inapplicable to it. Widening the counter a
sixteenth time would have found this one and missed the seventeenth.

So this asks a different question, of a different thing: **run the program and
look at the output**. That is the only method that has ever caught one of these
- CLAUDE.md says so in the section about the counter, and this file is that
sentence turned into a machine.

HOW IT WORKS
------------
Everything is rendered with TANDEM_IDIOMA_FORCADO=zh_CN. Chinese is the
instrument: it shares no letters with Portuguese or English, so any run of Latin
words in the output is either a name that must stay verbatim, or prose that
never reached the catalogue. Deciding between those two is a short, explicit,
auditable list (VERBATIM below) rather than a rule about shapes - the same
arrangement as EXCECOES in the counter, and for the same reason: a rule can
quietly grow to cover new prose, an exact string somebody had to add on purpose
cannot.

WHAT IT CANNOT SEE, said plainly because a measure that hides its blind spot is
the whole problem this file exists to fix:
  - anything that needs a graphical session. The zenity button labels are the
    clearest case: with no GUI t_pergunta returns "no" without drawing anything,
    so the pair of words on the buttons is invisible here. They are covered by
    a separate assertion in tests/run.sh instead.
  - anything behind a tool this machine does not have (a real Wine prefix, a
    running Waydroid). The probe is skipped, and skipped probes are REPORTED,
    never silently counted as clean.
  - a message that is wrong rather than untranslated. This checks language, not
    truth.
"""
import argparse
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(RAIZ, "src", "lib")
BIN = os.path.join(RAIZ, "src", "bin")

# Latin strings that are allowed to appear in Chinese output. Every entry is a
# decision somebody made on purpose, with the reason in the comment above it.
VERBATIM = [
    # Product and vendor names. Somebody searching the web for the component
    # Tandem is installing has to find the words the rest of the world uses.
    "Visual C++", "MFC", "GDI+", "MSXML", "PhysX", "DirectX", "DirectShow",
    "OpenAL", "Uniscribe", "Windows Media Player", "Windows Script Host",
    ".NET Framework", "Wine", "Waydroid", "Java", "FUSE", "AppImage",
    "Windows", "Android", "Linux", "Flatpak", "Snap", "Tandem", "GNOME",
    "Zorin", "Ubuntu", "Debian", "Fedora", "OpenSUSE", "GitHub", "Vercel",
    # Command names the user types. Portuguese on purpose and documented: a
    # command copied off a forum has to work on any machine.
    "tandem", "preparar", "programas", "desinstalar", "dados", "alternativas",
    "receita", "memoria", "esquecer", "socorro", "contribuir", "lista",
    "instalar", "doctor", "autoteste", "repair", "backup", "restore",
    "protect", "logs", "idioma", "portas", "identidade", "android",
    "importar", "atualizar", "enviar", "agora", "sim", "nao",
    # Tool and file names that are identifiers, not words.
    "winetricks", "wine", "wineboot", "wineserver", "winecfg", "adb", "apt",
    "dpkg", "flatpak", "snap", "zenity", "xdg-mime", "unsquashfs", "curl",
    "wget", "sudo", "pkexec", "systemd-inhibit", "sha256", "amd64", "arm64",
    "i386", "x86_64", "com", "COM", "http", "https",
    # A command the owner is told to paste, and the Unix group it names. These
    # are typed verbatim into a terminal; translating either one would produce
    # a line that does not work.
    "usermod", "gpasswd", "adduser", "dialout", "root",
    # The locale codes, and the ENGLISH gloss beside each language in the
    # picker. The gloss is deliberately English and deliberately never
    # translated: somebody whose machine came up in a script they cannot read
    # has to be able to find their own language in that list, and English is
    # the one label most likely to be recognised.
    "pt_BR", "zh_CN", "Chinese", "simplified", "Portuguese", "Brazil",
    "Spanish", "French", "Hindi", "Arabic", "English",
    # On-disk values. Format, not prose - CLAUDE.md lists these.
    "abriu", "confirmado", "so-abriu", "reprovado", "RESOLVERAM",
    # 4.11: the confidence level under the owner's word, and the three PROVA
    # levels beside it. On disk and in the record, never on the screen - the
    # screen gets them through t_resultado_amigavel.
    "entregue", "sem-alvo", "nao-chegou", "bitola-errada", "PROVA",
    "NAO_RESOLVERAM", "CONFIANCA", "alta", "baixa", "override", "titulo",
    "ambos", "nativo", "parecido", "IDENTIDADE", "PROGRAMA", "TANDEM_RECEITA",
    "ARQUITETURA", "RESULTADO", "VISTO_EM", "SEGUNDOS", "LIMITE", "PACOTE",
    "ORIGEM", "MODO", "MACHINEGUID",
]

# A word for the purposes of this tool: Latin letters, at least two of them.
PALAVRA = re.compile(r"[A-Za-z][A-Za-z'À-ɏ-]+")

# Things that are never prose and would otherwise dominate the noise.
LIXO = [
    re.compile(r"https?://\S+"),          # URLs
    re.compile(r"/[\w./~-]+"),            # absolute paths
    # File names AND bare extensions. The bare form is the one the help screen
    # uses (".exe .msi | .apk .xapk ..."), and requiring something before the
    # dot missed all of them - the first false positives this tool produced.
    re.compile(r"[\w.-]*\.(exe|msi|msix|dll|apk|xapk|apks|apkm|jar|deb|rpm|"
               r"snap|sh|run|tsv|txt|po|pot|log|desktop|xml|json|js|py|"
               r"AppImage|flatpakref|flatpakrepo)\b", re.I),
    re.compile(r"\b[A-Z_]{3,}=\S*"),      # KEY=VALUE state lines
    re.compile(r"--?[a-z][\w-]*"),        # command-line options
    re.compile(r"\b[0-9a-f]{16,}\b"),     # fingerprints
    re.compile(r"\{[0-9]\}"),             # unsubstituted placeholders
    # mktemp names. "tmp.nRh8tKj" survives the file-name rule (no known
    # extension) and its fragments read as three short Latin words.
    re.compile(r"\btmp\.?[A-Za-z0-9]{4,}\b"),
    # A RUN of shipped locale codes, which is how "tandem --help" lists the
    # languages. Only a run: a single "es", "fr" or "ar" is also an ordinary
    # word in three of the seven languages, and stripping those everywhere
    # would blind the tool to real prose containing them.
    re.compile(r"\b(?:pt_BR|zh_CN|en|es|fr|hi|ar)\b"
               r"(?:[\s,|/]+\b(?:pt_BR|zh_CN|en|es|fr|hi|ar)\b)+"),
]


def limpa(texto):
    """Strips everything that is legitimately Latin, leaving suspect prose.

    The word boundaries are not decoration. Without them "sim" - the Portuguese
    yes, on this list because it is an argument the user types - deleted itself
    out of the middle of "simplified" and left the fragment "plified", which
    then read as prose in the output of "tandem idioma". A tool that invents its
    own findings is worse than one that misses them, because somebody has to
    spend an afternoon proving each one is nothing.
    """
    for rx in LIXO:
        texto = rx.sub(" ", texto)
    # Longest first, so "Visual C++" is removed before "Visual" can match.
    for termo in sorted(VERBATIM, key=len, reverse=True):
        esq = r"\b" if termo[0].isalnum() else ""
        dir_ = r"\b" if termo[-1].isalnum() else ""
        texto = re.sub(esq + re.escape(termo) + dir_, " ", texto, flags=re.I)
    return texto


def suspeita(texto):
    """Runs of Latin words that look like a sentence rather than a name.

    Three or more words in a row, at least two of them lowercase. Product names
    are capitalised and short; prose is lowercase and long. This threshold is
    the whole difference between an instrument somebody reads and a wall of
    debris somebody learns to ignore - the counter's own history is explicit
    that a count which is mostly noise gets ignored, and that is how a real one
    goes unread.

    THE FIRST VERSION OF THIS FUNCTION DID NOT CATCH THE BUG THIS FILE WAS
    WRITTEN FOR. It required each word in the run to be three letters or more,
    so "Editor de texto rico" - one of the nine literals that started all this -
    was chopped at "de" into two runs of one and two words, and scored clean.
    That is the counter's entire history repeating itself inside its
    replacement, on the first attempt, and it was found only by putting the
    defect back and watching the tool stay silent. A word here is therefore any
    two letters or more; Portuguese, Spanish and French are full of two-letter
    function words and they are exactly what makes a string prose rather than a
    name. Do not raise this threshold to quieten the output - add the exact
    string to VERBATIM instead, where somebody can see the decision.
    """
    achados = []
    for linha in limpa(texto).splitlines():
        corrida = []
        for p in PALAVRA.findall(linha) + [""]:
            if p:
                corrida.append(p)
                continue
            if len(corrida) >= 3 and sum(1 for w in corrida if w[0].islower()) >= 2:
                achados.append(" ".join(corrida))
            corrida = []
    return achados


def roda(script, esconder=(), lang="zh_CN"):
    """Runs a bash snippet with the libraries sourced and Chinese forced.

    `esconder` names tools that must appear ABSENT for this probe. Several
    screens exist only to say a tool is missing - "tandem preparar" is the whole
    of one - and on a development machine where everything is installed they
    produce nothing at all, which reads as clean. The PATH is rebuilt with links
    to everything except the named tools, so the machine's own completeness
    stops hiding those screens.
    """
    env = dict(os.environ)
    env["TANDEM_LIB"] = LIB
    env["TANDEM_IDIOMA_FORCADO"] = lang
    env["TANDEM_VERBOS_TSV"] = os.path.join(LIB, "verbos.tsv")
    env["LC_ALL"] = "C.UTF-8"
    prep = ""
    if esconder:
        prep = (
            'export PATH_SANDBOX="$(mktemp -d)"\n'
            'for d in $(printf "%%s" "$PATH" | tr ":" " "); do\n'
            '  [ -d "$d" ] || continue\n'
            '  for f in "$d"/*; do\n'
            '    [ -x "$f" ] || continue\n'
            '    b="${f##*/}"\n'
            '    case " %s " in *" $b "*) continue ;; esac\n'
            '    [ -e "$PATH_SANDBOX/$b" ] || ln -s "$f" "$PATH_SANDBOX/$b" 2>/dev/null\n'
            '  done\n'
            'done\n'
            'PATH="$PATH_SANDBOX"\n' % " ".join(esconder)
        )
    cheio = '%s. "%s/common.sh"\n. "%s/winedeps.sh"\n%s' % (prep, LIB, LIB, script)
    try:
        p = subprocess.run(["bash", "-c", cheio], env=env,
                           capture_output=True, text=True, timeout=240)
    except (subprocess.TimeoutExpired, OSError) as e:
        return None, str(e)
    return (p.stdout or "") + (p.stderr or ""), None


def verbos_conhecidos():
    """Every verb t_verbo_amigavel could ever be handed."""
    nomes = set()
    tsv = os.path.join(LIB, "verbos.tsv")
    if os.path.exists(tsv):
        with open(tsv, encoding="utf-8") as f:
            for linha in f:
                if linha.startswith("#"):
                    continue
                partes = linha.rstrip("\n").split("\t")
                if len(partes) >= 2 and partes[1]:
                    nomes.add(partes[1])
    # The hand-written arm of the same function, which the index does not cover.
    with open(os.path.join(LIB, "winedeps.sh"), encoding="utf-8") as f:
        corpo = f.read()
    trecho = corpo.split("t_verbo_amigavel()", 1)[-1].split("\n}", 1)[0]
    for m in re.finditer(r"^\s*([a-z0-9_|]+)\)", trecho, re.M):
        for nome in m.group(1).split("|"):
            if nome and nome != "*":
                nomes.add(nome)
    return sorted(nomes)


def probes(rapido=False):
    """(name, bash, why it matters[, tools to hide]) - explicit, because a probe
    list that grows by accident is a coverage claim nobody checked.

    `rapido` keeps only the library probes, which need no Wine prefix and no
    real command run. That is what tests/run.sh uses, so the suite stays quick;
    CI runs the whole thing, handlers and commands included. A fast subset that
    silently became the only thing anybody ran would be the same failure as the
    counter, so ci.yml runs the full version and the suite says which it ran.
    """
    verbos = verbos_conhecidos()
    lista = [
        ("t_verbo_amigavel over every known verb",
         "\n".join('t_verbo_amigavel %s' % v for v in verbos),
         "the list of what Tandem is about to install - the screen the owner "
         "reads before agreeing to a half-hour download"),
        ("t_pecas_faltando",
         "t_pecas_faltando",
         "the whole of the 'tandem preparar' screen",
         ("wine", "winetricks", "adb", "java", "waydroid")),
        ("t_limite_do_log, hardware",
         "printf '0009:fixme:ntoskrnl:MmMapIoSpace stub: 1000 4096 0\\n' > $$.log\n"
         "t_limite_do_log $$.log; rm -f $$.log",
         "why a program opens and then misbehaves"),
        ("t_limite_do_log, driver",
         "printf '0009:err:winedevice:failed to load driver\\n' > $$.log\n"
         "t_limite_do_log $$.log; rm -f $$.log",
         "why a program that needs a system driver cannot work"),
        ("t_erro with a log attached",
         'LOG=/tmp/x.log; t_erro "$(t_msg falta_winetricks)"',
         "every failure ends in this window"),
        ("t_erro_do_leitor over every reader token",
         "\n".join('t_erro_do_leitor "%s"; printf "\\n"' % t
                   for t in tokens_dos_leitores()),
         "what the owner reads when a file cannot be understood"),
        ("t_confianca / memory field labels",
         'T=$(mktemp -d); export TANDEM_MEMORIA="$T"; F=$(mktemp)\n'
         'printf x > "$F"; t_memoria_grava "$F" RESULTADO abriu\n'
         'cat "$TANDEM_MEMORIA"/*.txt; rm -rf "$T" "$F"',
         "the memory file the owner is invited to read and send on"),
        # The group the six-lens audit found and this tool did not: forty-four
        # values written into the memory file, printed straight back to the
        # owner by "tandem memoria" and by the report "tandem socorro" tells
        # him to send. The static counter cannot see them because it exempts an
        # argument by its DESTINATION - anything handed to t_memoria_grava is
        # data by assumption - and the first version of this tool could not see
        # them either, because no probe ever seeded a memory file with a
        # failure in it. A probe list is a coverage claim; this is the line
        # that claim was missing.
        ("memory values as the owner reads them",
         'T=$(mktemp -d); export TANDEM_MEMORIA="$T"; F=$(mktemp)\n'
         'printf x > "$F"\n'
         'for v in "java antigo" "pasta sem permissao" "bitola errada" \\\n'
         '         "nao confirmou" "faltam dependencias" "fechou sozinho"; do\n'
         '  t_memoria_grava "$F" RESULTADO "$v"\n'
         '  t_resultado_amigavel "$v"; printf "\\n"\n'
         'done\n'
         'rm -rf "$T" "$F"',
         "the screen the owner opens to find out what happened, and the report "
         "he sends to whoever is helping him"),
        ("recipe header",
         'T=$(mktemp -d); export TANDEM_MEMORIA="$T"; F=$(mktemp)\n'
         'printf x > "$F"; t_memoria_grava "$F" RESOLVERAM vcrun2022\n'
         't_receita_exporta "$F"; rm -rf "$T" "$F"',
         "the file the owner hands to somebody else"),
    ]
    if rapido:
        return lista
    # The commands, run for real. This is the "install it and read what comes
    # out" method, which is the only one that has ever caught one of these.
    for cmd in ["--help", "version", "doctor", "lista", "idioma", "portas"]:
        lista.append(("tandem %s" % cmd,
                      'bash "%s/tandem" %s' % (BIN, cmd),
                      "a command the owner runs"))
    # Every handler, against a file it cannot possibly understand. No error
    # path may end in silence, and none of them may end in the wrong language.
    for h in ["exe", "apk", "appimage", "jar", "deb", "rpm", "flatpak",
              "snap", "script"]:
        lista.append(("tandem-%s on an unreadable file" % h,
                      'F=$(mktemp); printf "isto nao e um programa" > "$F"\n'
                      'bash "%s/tandem-%s" "$F" </dev/null; rm -f "$F"' % (BIN, h),
                      "the sentence a broken download produces"))
    return lista


def tokens_dos_leitores():
    """Every ERRO=<token> the six Python readers can emit."""
    toks = set()
    for nome in os.listdir(LIB):
        if not nome.endswith(".py"):
            continue
        with open(os.path.join(LIB, nome), encoding="utf-8") as f:
            corpo = f.read()
        for m in re.finditer(r'(?:raise\s+\w+|print)\(\s*["\']([A-Za-z_]+)'
                             r'(?:=([a-z_]+))?["\']', corpo):
            alvo = m.group(2) or m.group(1)
            if alvo and " " not in alvo and alvo.islower():
                toks.add(alvo)
    return sorted(toks) or ["cru"]


IDIOMAS = ["en", "pt_BR", "es", "fr", "zh_CN", "hi", "ar"]


def invariantes(script, esconder=()):
    """Lines that come out byte-identical in all seven languages.

    The Chinese probe above has a floor: it needs three words in a row, so a
    short phrase glued to a product name slips under it - "Depurador do
    Windows" becomes "Depurador do" once the name is stripped, and two words is
    not enough to accuse anybody. That is a real blind spot and this is the
    different question that covers it, rather than a lowered threshold that
    would flood the output.

    A sentence that came from the catalogue is nearly always different in
    Portuguese and in Hindi. A sentence written as a literal in the code is
    IDENTICAL in all seven, necessarily - that is what being a literal means.
    So identical-in-seven plus at least two Latin words that are not on the
    verbatim list is the signature, and it catches accent-free Portuguese,
    which is the hole the very first version of the static counter had.
    """
    porIdioma = []
    for lang in IDIOMAS:
        saida, erro = roda(script, esconder, lang)
        if erro is not None or saida is None:
            return []
        porIdioma.append(saida.splitlines())
    if len({len(x) for x in porIdioma}) != 1:
        return []          # different shapes: nothing to compare line by line
    achados = []
    for linhas in zip(*porIdioma):
        if len(set(linhas)) != 1:
            continue
        # A line with no space is a NAME, not a sentence, and it is supposed to
        # be identical everywhere - "cnc_ddraw" and "dxdiagn_feb2010" are verbs
        # falling through t_verbo_amigavel's default case, which is correct
        # behaviour. Splitting an identifier on its underscore made six of them
        # look like two-word prose, which is the tool inventing findings again.
        if " " not in linhas[0].strip():
            continue
        restante = PALAVRA.findall(limpa(linhas[0]))
        if len(restante) >= 2:
            achados.append(linhas[0].strip())
    return achados


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--rapido", action="store_true",
                    help="library probes only - no handler, no command")
    args = ap.parse_args()

    total = 0
    pulados = []
    for probe in probes(args.rapido):
        nome, script, porque = probe[0], probe[1], probe[2]
        esconder = probe[3] if len(probe) > 3 else ()
        saida, erro = roda(script, esconder)
        if erro is not None:
            pulados.append((nome, erro))
            continue
        if not (saida or "").strip():
            # Silence is a defect elsewhere in this project, but here it only
            # means the probe could not run - a handler that needs a tool this
            # machine lacks, for instance. Say so; never count it as clean.
            pulados.append((nome, "produced no output"))
            continue
        achados = suspeita(saida)
        mesmas = invariantes(script, esconder)
        for a in mesmas:
            if a not in achados:
                achados.append(a)
        if achados:
            total += len(achados)
            print("PROSE OUTSIDE THE CATALOGUE - %s" % nome)
            print("  (%s)" % porque)
            for a in sorted(set(achados)):
                print("    %s" % a)
        elif args.verbose:
            print("ok  %s" % nome)

    for nome, porque in pulados:
        print("skipped: %-46s %s" % (nome, porque))

    print("TOTAL %d" % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
