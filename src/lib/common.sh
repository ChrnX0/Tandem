# shellcheck shell=bash
# Tandem - common library.
# Loaded by every executable. Never use "set -e" here:
# the wait loops depend on commands that fail on purpose.

# The version, in one place. It is here and not in src/bin/tandem because the
# first-run bookkeeping needs it, and that lives in this file: a version that
# learned to open a new format has to claim that format on a machine that was
# already running an older one.
TANDEM_VERSAO="4.37"

TANDEM_LIB="${TANDEM_LIB:-/usr/lib/tandem}"
# Where the sibling executables live. Overridable for the same reason
# TANDEM_LIB is: with the path nailed down, exercising the panel from a working
# copy silently ran the INSTALLED binaries instead - so a whole command could be
# broken in the repository and every test still pass.
TANDEM_BIN="${TANDEM_BIN:-/usr/bin}"
TANDEM_ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/tandem"
# Where it WOULD have gone, kept even when it cannot be made: the line below
# empties TANDEM_ESTADO, and "free some space" is not an instruction until it
# says where.
TANDEM_ESTADO_QUERIDO="$TANDEM_ESTADO"
# THE SECOND DOOR to a silent /dev/null log, and it was found only after
# closing the first. t_log_init's own fallback records that the log was lost;
# this one emptied TANDEM_ESTADO and said nothing, so t_log_init took its
# `[ -z "$LOG" ]` shortcut and never reached the part that remembers. A full
# disk, a read-only home or a state path that is a file all arrive here, and
# what is lost is not only the log - the memory, the community list and the
# locks live in this folder too.
mkdir -p "$TANDEM_ESTADO" 2>/dev/null || { TANDEM_ESTADO=""; TANDEM_SEM_LOG=1; }

# Locks and progress pipes go to the user's runtime directory when it exists:
# it is local disk (on a home folder mounted over the network flock may simply
# not work), it is per boot session, and it is born owner-only.
# Two machines sharing the same home folder also stop colliding - the pipe
# name uses the PID, which repeats across machines.
if [ -n "${XDG_RUNTIME_DIR:-}" ] && mkdir -p "$XDG_RUNTIME_DIR/tandem" 2>/dev/null; then
    TANDEM_TRAVAS="$XDG_RUNTIME_DIR/tandem"
    chmod 700 "$TANDEM_TRAVAS" 2>/dev/null
else
    TANDEM_TRAVAS="${TANDEM_ESTADO:-/tmp}"
fi

# Default prefix for standalone Windows programs.
TANDEM_PREFIXO_PADRAO="${TANDEM_PREFIXO_PADRAO:-$HOME/.local/share/tandem/wine}"

# Prefixes the automation may NEVER modify (protects production systems).
# One line per path. Ex: ~/.wine-pdv
TANDEM_PROTEGIDOS="$HOME/.config/tandem/protegidos.txt"

# ------------------------------------------------------------------- log

t_log_init() {
    LOG="${TANDEM_ESTADO:+$TANDEM_ESTADO/$1.log}"
    [ -z "$LOG" ] && { LOG=/dev/null; return; }
    if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
        mv -f "$LOG" "$LOG.old" 2>/dev/null || true
    fi
    # A REAL BYTE. The probe here used to open the file for append and write
    # nothing, and on a FULL filesystem that SUCCEEDS - the open allocates no
    # blocks, so ENOSPC never fires. It answered "writable" while the very next
    # line, this same header, failed and leaked
    #
    #   common.sh: line 49: printf: write error: No space left on device
    #
    # as the FIRST thing the owner read, with a path and a line number in it.
    # Measured on a full 16k tmpfs: the empty append succeeds, one byte fails.
    # A check that prints the same thing whether the premise is right or wrong
    # has measured nothing - the rule this project wrote down after deleting
    # twenty-four tracked files on the strength of an empty `git status`.
    #
    # And the whole thing is inside a GROUP. Written as `printf ... >> "$LOG"
    # 2>/dev/null`, the 2>/dev/null silences printf - but the failure here is
    # the REDIRECTION, which bash reports itself, before that redirection is in
    # place. The message came out anyway. Redirecting the group means stderr is
    # already gone when the append is attempted.
    if ! { printf '\n===== %s | %s =====\n' "$(date '+%F %T')" "${*:2}" \
           >> "$LOG"; } 2>/dev/null; then
        LOG=/dev/null
        # And REMEMBER it, because every diagnosis in every handler is read
        # back out of this file: which DLL Wine asked for, whether the .exe is
        # a Windows program at all, whether the prefix is the wrong width, why
        # winetricks gave up. With the log gone they all come back empty and
        # the owner reads "the program closed with an error (code 53)" - the
        # entire point of the project, lost, with nothing on screen saying so.
        # Reached by the commonest failure there is, a full disk.
        TANDEM_SEM_LOG=1
    fi
}

# The sentence that has to accompany any verdict reached WITHOUT the log, and
# nothing at all when the log is fine - so a caller can append it without
# asking first. $1 is the folder, because "free some space" is not an
# instruction until it says where.
t_aviso_sem_log() {
    [ -n "${TANDEM_SEM_LOG:-}" ] || return 1
    t_msg sem_anotacoes "${TANDEM_ESTADO:-${TANDEM_ESTADO_QUERIDO:-?}}"
}

t_diz() { printf '%s\n' "$*" >> "${LOG:-/dev/null}" 2>/dev/null; }

# ---------------------------------------------------- slicing the log safely
#
# Everything that reads Wine's output back needs "the part written since I
# started this attempt", and the way to get it was MARCA=$(wc -l < "$LOG")
# followed by tail -n +$((MARCA+1)). That is only correct while this process is
# the ONLY writer, and it is not: one log file per handler, no PID in the name,
# and Tandem itself now spawns background work - the community-list fetch, the
# version check - that appends to the same file.
#
# Measured, not feared. Two runs of the identical commit in CI, one green and
# one red, on a test whose second pass suddenly failed to detect a DLL that was
# plainly in the log: a background writer had shifted the line numbers between
# the count and the slice, so the detector read the wrong window. The owner saw
# the same shape from the other side on his own machine the same day - lines
# from `tandem socorro` appearing under the heading of `tandem version`.
#
# A marker cannot drift. It is written INTO the stream it will be used to cut,
# so whatever else lands before or after it, the text after the marker is
# exactly the text written after the marker.
t_log_marca() {
    local m
    # Distinct per process AND per call: SECONDS moves, $$ does not, and two
    # attempts of the same run must not share a marker or the second slice
    # would start at the first attempt.
    m="---8<--- tandem $$ ${1:-0} ---8<---"
    printf '%s\n' "$m" >> "${LOG:-/dev/null}" 2>/dev/null
    printf '%s' "$m"
}

# Everything after that marker. Prints nothing if the marker is not there,
# which is honest: with no marker there is no "since", and guessing a line
# number is what this replaced.
t_log_desde() {
    local marca="$1"
    [ -n "$marca" ] || return 1
    [ -f "${LOG:-}" ] || return 1
    awk -v m="$marca" 'achou { print } $0 == m { achou = 1 }' "$LOG" 2>/dev/null
}

# -------------------------------------------------------------- messages
#
# Rule for this section: no message may be lost. Every message ALWAYS goes to
# the log; the screen and the terminal are only the visible destinations.
# If the window cannot be shown, the text comes out on the terminal - it never
# disappears.
#
# zenity and notify-send fail when there is no graphical session (plain
# terminal, SSH, TTY). Without this check they fail silently and the user is
# left with "nothing happened", which this project treats as a defect.

# ------------------------------------------------------------------- the look
#
# Tandem's own windows, and nobody else's. GTK_THEME applies to THIS PROCESS
# only, so no other program on the machine changes appearance - which is the
# whole reason this is an environment variable and not a setting written into
# the owner's GTK configuration.
#
# Measured, because the first three attempts failed in silence and each looked
# like "it cannot be done":
#   - zenity here is 4.0.1, linked against GTK4, so the file has to be in
#     gtk-4.0/. A gtk-3.0/ theme is ignored without a word. Both ship.
#   - GTK_THEME really is honoured (GTK_THEME=Adwaita:dark proves it in one
#     command, which is the test that separated "cannot" from "wrong folder").
#   - a theme in a private directory loads through XDG_DATA_DIRS, so nothing
#     has to be installed into /usr/share/themes, where it would appear in the
#     owner's theme picker as a thing he never asked for.
#
# DEFAULT IS THE SYSTEM'S. A shop machine set up in the light, running a
# Tandem that forces itself dark, is worse than plain: it looks broken. The
# owner opts in, the same way he opts into a language.
TANDEM_TEMAS="${TANDEM_TEMAS:-/usr/share/tandem/temas}"

# An icon by NAME, resolved to a PATH. zenity --imagelist takes a path and
# draws a broken placeholder for a name - measured, side by side in one window.
# Nothing found means nothing shown, which is the whole fallback: on a machine
# with no icon theme the panel is exactly the list it is today.
t_icone_caminho() {
    local nome="$1" dir achado
    [ -n "$nome" ] || return 1
    for dir in "${XDG_DATA_HOME:-$HOME/.local/share}/icons" \
               /usr/share/icons /usr/local/share/icons /usr/share/pixmaps; do
        [ -d "$dir" ] || continue
        achado="$(find "$dir" -name "$nome.svg" -o -name "$nome.png" 2>/dev/null | head -1)"
        [ -n "$achado" ] && { printf '%s' "$achado"; return 0; }
    done
    return 1
}

# One panel screen. Takes triples of token, sentence and icon name, and hands
# back the token the owner chose.
#
# The token column is LAST and hidden: it is what the code switches on, and a
# shop owner clicking a row should never have to decode "identidade" to read
# the sentence beside it. It is last rather than first because a hidden column
# in the middle still reserves its width and pushes the text away from its icon.
#
# With no icons on the machine the whole image column is dropped rather than
# filled with placeholders, so the screen degrades to plain text instead of to
# a row of broken squares.
t_painel_lista() {
    local pergunta="$1"; shift
    local -a linhas=() ; local tem_icone=0 caminho
    while [ $# -ge 3 ]; do
        caminho="$(t_icone_caminho "$3" 2>/dev/null)" && tem_icone=1 || caminho=""
        linhas+=("$caminho" "$2" "$1")
        shift 3
    done
    if [ "$tem_icone" = 1 ]; then
        zenity --list --imagelist --title="Tandem $TANDEM_VERSAO" \
               --width=680 --height=640 --text="$pergunta" \
               --column="" --column="$(t_msg pan_col_descricao)" \
               --column="$(t_msg pan_col_acao)" \
               --hide-column=3 --print-column=3 --hide-header \
               "${linhas[@]}" 2>/dev/null
    else
        local -a sem=() i=0
        for ((i = 1; i < ${#linhas[@]}; i += 3)); do
            sem+=("${linhas[i]}" "${linhas[i+1]}")
        done
        zenity --list --title="Tandem $TANDEM_VERSAO" \
               --width=560 --height=470 --text="$pergunta" \
               --column="$(t_msg pan_col_descricao)" \
               --column="$(t_msg pan_col_acao)" \
               --hide-column=2 --print-column=2 --hide-header \
               "${sem[@]}" 2>/dev/null
    fi
}

# The value stays on disk exactly as written; this turns it into a word when
# it is SHOWN. Same arrangement t_resultado_amigavel uses for the memory file,
# and for the same reason: translating an on-disk value breaks compatibility
# with settings already written on somebody's machine, while showing the raw
# value puts a keyword on a shopkeeper's screen.
t_tema_amigavel() {
    case "$1" in
        escuro) t_msg tema_nome_escuro ;;
        *)      t_msg tema_nome_sistema ;;
    esac
}

t_tema_escolhido() {
    local t="${TANDEM_TEMA_FORCADO:-}"
    [ -n "$t" ] || t="$(t_config_le TEMA 2>/dev/null)"
    printf '%s' "${t:-sistema}"
}

# Exports what zenity needs, or nothing at all. Called before every window;
# with no choice made, or with the theme missing from disk, it is a no-op and
# the dialogs look exactly as they do today.
t_tema_aplica() {
    local escolha; escolha="$(t_tema_escolhido)"
    case "$escolha" in
        escuro) : ;;
        *) return 0 ;;
    esac
    [ -d "$TANDEM_TEMAS/themes/TandemEscuro" ] || return 0
    export XDG_DATA_DIRS="$TANDEM_TEMAS:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    export GTK_THEME=TandemEscuro
    return 0
}

t_tem_gui() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || return 1
    # One chokepoint: every path that opens a window asks this first, so the
    # look is applied here instead of at twenty call sites where the twenty-first
    # would be forgotten. Idempotent - it only exports.
    t_tema_aplica 2>/dev/null
    return 0
}

# ---------------------------------------------------------------- locale
#
# zenity (through glib) refuses ANY argument with a non-ASCII character when
# the locale in effect was not generated on the system: glib falls back to
# ANSI_X3.4-1968 and answers "This option is not available", exit code 255.
# Since every message in this program has an accent, a missing locale makes
# all the windows disappear without a trace. That is why we never set a
# locale without first confirming that it exists.

# locale -a prints "pt_BR.utf8": no hyphen and lowercase. Normalize both sides
# before comparing, otherwise "pt_BR.UTF-8" never matches anything.
t_locale_existe() {
    local alvo
    alvo="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
    [ -n "$alvo" ] || return 1
    locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '-' |
        grep -qx -- "$alvo"
}

# The first candidate that actually exists. C.UTF-8 closes the list because it
# is built into glibc: it is present even with no locale generated.
t_locale_utf8() {
    local c
    for c in "$@" C.UTF-8; do
        [ -n "$c" ] || continue
        t_locale_existe "$c" && { printf '%s' "$c"; return 0; }
    done
    printf 'C.UTF-8'
}

# The language the SYSTEM asked for, captured before anything here touches it.
# The charmap fixup just below exports LC_ALL to keep zenity able to print an
# accent, and that overwrote the only evidence of what language the machine is
# in: on any computer without a pt_BR locale generated - which is most of them
# outside Brazil - the fixup fired first and every user looked like they had
# asked for C. Read it now, use it later.
TANDEM_LANG_SISTEMA="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"

if [ "$(locale charmap 2>/dev/null)" != "UTF-8" ]; then
    TANDEM_LOCALE="$(t_locale_utf8 pt_BR.UTF-8)"
    export LC_ALL="$TANDEM_LOCALE"
fi

# ============================================================= LANGUAGE
#
# Until 4.2 every sentence in this program was a Portuguese literal sitting
# inside the script that printed it. That was right while the product had one
# owner in one country, and it stops being right the moment somebody in
# another one installs it.
#
# THE MESSAGES ARE DATA, NOT CODE, and the format is built so that they cannot
# be anything else. A catalog is parsed by "read" and never evaluated, so a
# dollar sign, a backtick or a $(...) inside a translation is text and stays
# text. A translator is not a person who should have to know what a subshell
# is, and a translation file must not be able to run anything.
#
# Substitution is {1} {2} {3} and deliberately NOT printf's %s. This project
# has already been bitten by percent signs: paths and versions carry them, and
# a message built with a format string breaks on a folder called "50% off".
#
# The fallback is Portuguese, always. A key missing from a translation prints
# the Portuguese sentence - never the key name, never an empty string. That is
# rule number 2 applied to its own machinery: a half-translated program still
# has to say something a person can read.

TANDEM_IDIOMAS="en pt_BR es fr zh_CN hi ar"
# ENGLISH IS THE DEFAULT, and that is a deliberate reversal.
#
# It used to be Portuguese, on the reasoning that Portuguese was what this
# program spoke before it could speak anything else. That reasoning protected
# nobody: a machine set to Portuguese still resolves to Portuguese by locale,
# so the only people the old default ever reached were the ones whose language
# Tandem does not have a catalogue for - and to them, Portuguese is not a
# gentler fallback than English, it is a wall.
#
# It is also the base every catalogue falls back to when a key is missing, so
# the language that has to be complete first is this one.
TANDEM_IDIOMA_PADRAO=en
TANDEM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/tandem"

declare -gA T_MSG=()
declare -gA T_MSG_BASE=()

# The language a name belongs to, in that language, plus its English name so
# somebody who cannot read the script can still find their line.
t_idioma_nome() {
    case "$1" in
        pt_BR) printf 'Português (Brasil)' ;;
        en)    printf 'English' ;;
        es)    printf 'Español (Spanish)' ;;
        fr)    printf 'Français (French)' ;;
        zh_CN) printf '简体中文 (Chinese, simplified)' ;;
        hi)    printf 'हिन्दी (Hindi)' ;;
        ar)    printf 'العربية (Arabic)' ;;
        *)     printf '%s' "$1" ;;
    esac
}

# Arabic is written right to left. Every aligned report in this program pads a
# label to a fixed column, and padding runs the wrong way in a right-to-left
# script: the value ends up inside the label. So the reports ask before they
# align, and print a plain "label: value" instead.
t_idioma_rtl() {
    case "${TANDEM_IDIOMA:-}" in ar|fa|he|ur) return 0 ;; *) return 1 ;; esac
}

# Reads one catalog into the array named by $2. Pure "read": no eval anywhere
# on this path, on purpose.
#
# Format:
#   @key
#   the sentence, which may
#   run over as many lines as it needs
#   @next-key
#
# A line starting with "#" outside a message is a comment. To begin a message
# with a literal "@" or "#", the catalog writes "\@" or "\#".
t_catalogo_le() {
    local arq="$1" chave="" linha primeiro=1 nl=$'\n' 
    # A nameref, and not a dynamic "printf -v ${name}[key]": the dynamic form
    # worked, and it made shellcheck lose track of which variables are arrays
    # badly enough that it reported a bogus warning three hundred lines away.
    # Code that confuses the checker will confuse the next reader too.
    local -n catalogo_alvo="$2"
    [ -f "$arq" ] || return 1
    while IFS= read -r linha || [ -n "$linha" ]; do
        case "$linha" in
            '@'*)
                chave="${linha#@}"
                if [ -n "$chave" ]; then catalogo_alvo["$chave"]=""; primeiro=1; fi
                continue ;;
            # A "#" at the start of a line is ALWAYS a comment, including
            # between the lines of a message. Written the other way round -
            # "a comment only when no message is open" - the separator
            # comments in the middle of the catalogue were swallowed by
            # whatever entry came before them, and printed to the user.
            '#'*) continue ;;
            '\@'*|'\#'*) linha="${linha#\\}" ;;
        esac
        [ -n "$chave" ] || continue
        if [ "$primeiro" = 1 ]; then
            catalogo_alvo["$chave"]="$linha"
            primeiro=0
        else
            catalogo_alvo["$chave"]="${catalogo_alvo[$chave]}"$'\n'"$linha"
        fi
    done < "$arq"
    # The blank lines BETWEEN entries are what makes a catalogue readable, so
    # they are allowed and trimmed here, once, rather than at every lookup.
    # Blank lines INSIDE a message are paragraph breaks and survive: most of
    # these are three paragraphs written for somebody having a bad afternoon.
    local k
    for k in "${!catalogo_alvo[@]}"; do
        while [ -n "${catalogo_alvo[$k]}" ] &&
              [ "${catalogo_alvo[$k]: -1}" = "$nl" ]; do
            catalogo_alvo["$k"]="${catalogo_alvo[$k]%"$nl"}"
        done
    done
    return 0
}

# Which language to speak, in order of who gets to decide:
#   1. TANDEM_IDIOMA in the environment  - for tests, and for one-off runs
#   2. what the owner chose              - a file, written by "tandem idioma"
#   3. what the system is already set to - LC_ALL, LC_MESSAGES, LANG
#   4. Portuguese
#
# Number 3 matters more than it looks: a machine whose Linux is in Spanish
# should not have to be told twice. And number 4 is Portuguese rather than
# English on purpose - it is what this program did before it could speak
# anything else, and an unrecognised locale must not silently change the
# language on the people already using it.
t_idioma_escolhe() {
    local escolhido="" sistema base
    if [ -n "${TANDEM_IDIOMA_FORCADO:-}" ]; then
        escolhido="$TANDEM_IDIOMA_FORCADO"
    elif [ -r "$TANDEM_CONFIG/idioma" ]; then
        escolhido="$(tr -d '[:space:]' < "$TANDEM_CONFIG/idioma" 2>/dev/null)"
    fi
    if [ -z "$escolhido" ]; then
        sistema="$TANDEM_LANG_SISTEMA"
        sistema="${sistema%%.*}"; sistema="${sistema%%@*}"
        base="${sistema%%_*}"
        for c in $TANDEM_IDIOMAS; do
            [ "$c" = "$sistema" ] && { escolhido="$c"; break; }
        done
        # pt_PT, es_AR, zh_TW: the country is not the language. Falling back to
        # the base code is what makes this work outside the one country each
        # catalog was written in.
        if [ -z "$escolhido" ] && [ -n "$base" ]; then
            for c in $TANDEM_IDIOMAS; do
                [ "${c%%_*}" = "$base" ] && { escolhido="$c"; break; }
            done
        fi
    fi
    for c in $TANDEM_IDIOMAS; do
        [ "$c" = "$escolhido" ] && { printf '%s' "$c"; return 0; }
    done
    printf '%s' "$TANDEM_IDIOMA_PADRAO"
}

t_idioma_carrega() {
    local dir="${TANDEM_IDIOMAS_DIR:-$TANDEM_LIB/idiomas}"
    TANDEM_IDIOMA="$(t_idioma_escolhe)"
    # The default language first and always: it is the fallback for every key
    # a translation has not caught up with yet.
    t_catalogo_le "$dir/$TANDEM_IDIOMA_PADRAO.txt" T_MSG_BASE
    if [ "$TANDEM_IDIOMA" != "$TANDEM_IDIOMA_PADRAO" ]; then
        t_catalogo_le "$dir/$TANDEM_IDIOMA.txt" T_MSG
    fi
    return 0
}

# t_msg <key> [arg1 arg2 ...] - the sentence, with {1}..{9} replaced.
#
# An unknown key returns the key name ONLY as a last resort, and says so in the
# log. It cannot return nothing: a silent message is the one bug this whole
# program exists to prevent, and a translation catalog is exactly the kind of
# file where a line gets lost in an edit.
t_msg() {
    local chave="$1"; shift
    local texto="${T_MSG[$chave]:-}"
    [ -n "$texto" ] || texto="${T_MSG_BASE[$chave]:-}"
    if [ -z "$texto" ]; then
        t_diz "FALTA a mensagem '$chave' no catalogo"
        printf '%s' "$chave"
        return 1
    fi
    # Blank lines BETWEEN entries are what makes a catalog readable, so they
    # are allowed and then trimmed here. Blank lines INSIDE a message are
    # paragraph breaks and survive - most of these messages are three
    # paragraphs written for somebody who is having a bad afternoon.
    local nl=$'\n'
    while [ -n "$texto" ] && [ "${texto: -1}" = "$nl" ]; do texto="${texto%"$nl"}"; done
    local i=1 a
    for a in "$@"; do
        texto="${texto//\{$i\}/$a}"
        i=$((i + 1))
    done
    printf '%s' "$texto"
}

# Which plural form a count takes, 0-based, in the language now loaded.
#
# THE RULE IS CODE AND THE FORMS ARE DATA, and that split is deliberate. gettext
# ships its rule as a C expression inside the catalogue header, and honouring
# one here would mean putting $(( )) around text that arrived from a stranger -
# throwing away the property this whole format exists to have, which is that a
# message can never be code. There is a test that hands the loader a hostile
# catalogue and proves it cannot act; evaluating a plural rule would walk it
# straight back in through the header.
#
# So the counts live in tools/po-para-catalogo.py for the translator's tool and
# here for the program, and a test asserts the two agree. Duplication that a
# test pins is cheaper than an evaluator.
t_plural_indice() {
    local n="${1:-0}"
    # A count that is not a number is not worth a bash arithmetic error on the
    # owner's screen. Form 0 always exists, so it is the safe answer.
    case "$n" in ''|*[!0-9]*) printf '0'; return 0 ;; esac
    case "${TANDEM_IDIOMA:-$TANDEM_IDIOMA_PADRAO}" in
        # One form. Two would ask a translator to invent a distinction Chinese
        # does not make.
        zh_CN) printf '0' ;;
        # Portuguese and French count zero as singular: "0 minuto", "0 minute".
        pt_BR|fr)
            if [ "$n" -gt 1 ]; then printf '1'; else printf '0'; fi ;;
        ar)
            if   [ "$n" -eq 0 ]; then printf '0'
            elif [ "$n" -eq 1 ]; then printf '1'
            elif [ "$n" -eq 2 ]; then printf '2'
            elif [ $((n % 100)) -ge 3 ] && [ $((n % 100)) -le 10 ]; then printf '3'
            elif [ $((n % 100)) -ge 11 ]; then printf '4'
            else printf '5'; fi ;;
        *)
            if [ "$n" -eq 1 ]; then printf '0'; else printf '1'; fi ;;
    esac
}

# How many forms each language has. Kept beside the rule above so the two cannot
# drift, and asserted against the compiler's table by the suite.
t_plural_formas() {
    case "${1:-${TANDEM_IDIOMA:-$TANDEM_IDIOMA_PADRAO}}" in
        zh_CN) printf '1' ;;
        ar)    printf '6' ;;
        *)     printf '2' ;;
    esac
}

# t_msg_n <key> <count> [arg1 arg2 ...] - like t_msg, but picks a plural form.
#
# The count only CHOOSES the form; it is not substituted automatically, because
# it is not always {1}: "on this same file, {2} reports say" counts on the
# second slot. Pass it in the arguments as well, wherever it belongs.
#
# The fallback chain is the reason this is safe to adopt one message at a time:
#
#   this language's form N  ->  this language's form 0  ->  this language's
#   plain key  ->  and only then the same three in English
#
# So a language that has translated nothing plural keeps the single sentence it
# already had, in its own language. Reaching for English the moment a form is
# missing would have made every Arabic and Hindi count switch to English the
# day this arrived, which is a regression dressed as a feature.
t_msg_n() {
    local chave="$1" n="$2"; shift 2
    local i c alvo=""
    i="$(t_plural_indice "$n")"
    for c in "$chave#$i" "$chave#0" "$chave"; do
        if [ -n "${T_MSG[$c]:-}" ]; then alvo="$c"; break; fi
    done
    if [ -z "$alvo" ]; then
        for c in "$chave#$i" "$chave#0" "$chave"; do
            if [ -n "${T_MSG_BASE[$c]:-}" ]; then alvo="$c"; break; fi
        done
    fi
    t_msg "${alvo:-$chave}" "$@"
}

# Is this "program" actually a web page?
#
# A download that goes wrong rarely produces nothing: the site answers with an
# error page, a login wall or a "are you a robot" interstitial, and the browser
# saves that HTML under the name the link promised. The result is a file called
# programa.deb whose first bytes are <!DOCTYPE html>, and every reader in this
# project then reports its own local disappointment - "no ar signature", "not a
# zip", "bad ELF header" - which is true, useless, and sends the owner looking
# for a defect in the wrong place.
#
# Leading whitespace is skipped before looking, because a served error page
# often starts with a blank line or a byte-order mark.
t_parece_pagina_web() {
    local inicio
    inicio="$(head -c 512 -- "$1" 2>/dev/null | tr -d '\000' | tr '[:upper:]' '[:lower:]')"
    case "$inicio" in
        *'<!doctype html'*|*'<html'*|*'<head>'*|*'<title>'*) return 0 ;;
    esac
    return 1
}

# Does this machine have letters for that language at all?
#
# Same lesson as the zenity accents, one alphabet further out. Choosing a
# language whose script has no font installed does not fail: it draws a screen
# of empty boxes, which is a working program that cannot be read. fontconfig
# answers this directly, and answering "I cannot tell" (no fc-list here) has to
# mean "go ahead" - refusing on a machine we were unable to inspect would be
# worse than the boxes.
t_idioma_tem_letras() {
    local lang="$1"
    case "$lang" in pt_BR|en|es|fr) return 0 ;; esac   # Latin: always present
    command -v fc-list >/dev/null 2>&1 || return 0
    [ -n "$(fc-list ":lang=${lang%%_*}" 2>/dev/null | head -1)" ]
}

# Was this catalogue checked by somebody who speaks the language? The header
# carries REVISADO=sim/nao and the answer is shown to whoever picks it.
# Shipping a translation nobody has reviewed is defensible; shipping it
# without saying so is not.
t_idioma_revisado() {
    local dir="${TANDEM_IDIOMAS_DIR:-$TANDEM_LIB/idiomas}"
    grep -qi '^# *REVISADO=sim' "$dir/$1.txt" 2>/dev/null
}

t_idioma_grava() {
    mkdir -p "$TANDEM_CONFIG" 2>/dev/null || return 1
    printf '%s\n' "$1" > "$TANDEM_CONFIG/idioma" 2>/dev/null || return 1
    T_MSG=()
    t_idioma_carrega
}

t_idioma_carrega

# Is somebody looking at a terminal right now?
#
# THE DEFECT THIS EXISTS FOR, reported from the owner's own machine: he typed
# `tandem backup` at a prompt and the terminal "simplesmente nao retornou
# nada". The command had a perfectly good answer for him - there is no Windows
# environment yet - and t_erro handed it to notify-send, because a graphical
# session existed. The answer went into a bubble over his desktop while he sat
# looking at a silent prompt.
#
# That is the cardinal rule of this whole project broken from the inside: no
# path may end in silence, and this one ended in silence for every command
# typed at a terminal on a machine that has a desktop - which is every shop
# machine there is.
#
# t_texto has had the right rule since 3.4 and the other three never adopted
# it. Stated plainly: a notification is what you use when there is NOBODY at a
# terminal, which is the double-click case. When there is somebody, the
# terminal gets the message, because that is where they are looking.
#
# Both descriptors, because a caller may redirect either one: `tandem doctor >
# report.txt` still has a person at stderr, and `2>err.log` still has one at
# stdout.
t_tem_terminal() {
    [ -t 1 ] || [ -t 2 ]
}

t_aviso() {
    t_diz "aviso: $1"
    if ! t_tem_terminal && t_tem_gui && command -v notify-send >/dev/null 2>&1 &&
       notify-send -i "${2:-dialog-information}" -a Tandem "Tandem" "$1" 2>/dev/null; then
        return 0
    fi
    printf 'Tandem: %s\n' "$1" >&2
    command -v logger >/dev/null 2>&1 && logger -t tandem "$1"
    return 0
}

# Puts a string on the clipboard, whichever of the two systems this desktop
# runs. Returns 1 when there is no way to do it, so the caller can say so
# instead of silently promising a copy that never happened.
#
# Extracted from acao_contribuir in 4.11, where it was inline - and inline it
# could not be shared, which is why "tandem socorro" spent two versions ending
# in a ten-second toast while the command thirty lines above it already had
# both shortcuts written.
t_copia_para_area() {
    local texto="$1"
    t_tem_gui || return 1
    if command -v xclip >/dev/null 2>&1; then
        printf '%s' "$texto" | xclip -selection clipboard 2>/dev/null && return 0
    elif command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$texto" | wl-copy 2>/dev/null && return 0
    fi
    return 1
}

t_ok() {
    t_diz "ok: $1"
    if ! t_tem_terminal && t_tem_gui && command -v notify-send >/dev/null 2>&1 &&
       notify-send -i emblem-ok -t 10000 -a Tandem "Tandem" "$1" 2>/dev/null; then
        return 0
    fi
    printf 'Tandem: %s\n' "$1" >&2
    command -v logger >/dev/null 2>&1 && logger -t tandem "OK: $1"
    return 0
}

# Error the user MUST see: notification + window; terminal if there is neither
# one nor the other. The log always gets it, for the "it did not work"
# post-mortem.
t_erro() {
    local mostrou=0 extra=""
    t_diz "ERRO: $1"
    # The pointer to the log file used to carry a hard-coded "Detalhes
    # tecnicos:" - Portuguese, in the one window every failure ends in, in all
    # seven languages. It was assembled inside a ${LOG:+...} expansion, which is
    # neither a call, an assignment, a printf nor a bare argument, so
    # tools/conta-literais.py never saw it and read TOTAL 0 for two releases.
    [ -n "$LOG" ] && extra="$(printf '\n\n%s\n%s' "$(t_msg detalhes_tecnicos)" "$LOG")"
    # A terminal beats the desktop, and it beats it OUTRIGHT rather than as
    # well: opening a modal zenity dialog that blocks until somebody clicks it
    # is the wrong answer to a command typed at a prompt, and a critical
    # notification for it is the same alarm the self-test was told off for.
    # See t_tem_terminal for the report that produced this.
    if t_tem_terminal; then
        printf 'Tandem: %s\n' "$1" >&2
        command -v logger >/dev/null 2>&1 && logger -t tandem "ERRO: $1"
        return 0
    fi
    if t_tem_gui; then
        command -v notify-send >/dev/null 2>&1 &&
            notify-send -u critical -i dialog-error -a Tandem "Tandem" "$1" 2>/dev/null &&
            mostrou=1
        if command -v zenity >/dev/null 2>&1 &&
           zenity --error --no-wrap --title="Tandem" \
                  --text="$1$extra" 2>/dev/null; then
            mostrou=1
        fi
    fi
    [ "$mostrou" = 1 ] || printf 'Tandem: %s\n' "$1" >&2
    command -v logger >/dev/null 2>&1 && logger -t tandem "ERRO: $1"
    return 0
}

# Yes/no question. With no graphical interface there is no way to ask: returns
# 1 (= "no"), which every caller treats as a safe give-up.
t_pergunta() {
    t_tem_gui || return 1
    command -v zenity >/dev/null 2>&1 || return 1
    # The DEFAULT labels were literal Portuguese, so every caller that did not
    # pass its own pair showed "Sim" and "Nao" to a French or Chinese reader.
    # A default value is not a call, an assignment or a printf either: the
    # counter scored this line as clean while it was the most-clicked pair of
    # words in the program.
    zenity --question --no-wrap --title="Tandem" --text="$1" \
           --ok-label="${2:-$(t_msg botao_sim)}" \
           --cancel-label="${3:-$(t_msg botao_nao)}" 2>/dev/null
}

# Did the reader agree, in a terminal, in their own language?
#
# This existed as `case "$r" in s|S|sim|SIM)` copied into five handlers, while
# the prompt beside it came from the catalogue and says "[y/N]" in English and
# "[o/N]" in French. So an English owner did what the screen asked, typed "y",
# and was told the install was cancelled - a correctness defect wearing a
# translation defect's clothes, and the more dangerous half is that it appears
# on the .deb and .sh paths, where the alternative to installing is being told
# nothing happened when something should have.
#
# The language's own letter comes from the catalogue; "y" and "s" are always
# accepted on top of it, because a shop owner who learned "s" from a Brazilian
# forum should not be refused by a machine set to French.
t_confirmou() {
    local r="${1:-}" letra
    letra="$(t_msg resposta_sim 2>/dev/null)"
    case "${r,,}" in
        y|yes|s|sim) return 0 ;;
    esac
    [ -n "$letra" ] && [ "${r,,}" = "${letra,,}" ] && return 0
    return 1
}

# Shows a long text read from standard input.
#
# The window only makes sense when nobody is waiting for the text on standard
# output. Terminal, pipe and file are EXPLICIT requests for text:
#   tandem doctor                  -> terminal
#   tandem doctor | grep wine      -> the pipe receives the text
#   tandem doctor > relatorio.txt  -> the file receives the text
# Testing only "[ -t 1 ]" confused the last two with a double click and sent
# the diagnosis to a window, writing an empty file - exactly when the user is
# trying to send the diagnosis to somebody.
# What is left is the double click, where the output goes to /dev/null or to
# the journal: there the window is the only way for the person to see anything.
t_texto() {
    local titulo="${1:-Tandem}" conteudo
    # The content comes from STANDARD INPUT; the argument is only the window
    # title. Whoever forgets that and passes the text as an argument lands in
    # a "cat" that waits forever for a stdin nobody is going to close - the
    # command freezes in the middle of the double click, with no window and no
    # message. It already happened in five commands at once. With a terminal
    # on the input there is nothing piped in: we carry on without hanging.
    if [ -t 0 ]; then conteudo=""; else conteudo="$(cat)"; fi
    # And if even so nothing came in, the title shows up. Better a poor line
    # than a command that runs, exits 0 and prints nothing.
    [ -n "$conteudo" ] || conteudo="$titulo"
    if [ -t 1 ] || [ -p /dev/fd/1 ] || [ -f /dev/fd/1 ]; then
        printf '%s\n' "$conteudo"
        return 0
    fi
    if t_tem_gui && command -v zenity >/dev/null 2>&1 &&
       printf '%s\n' "$conteudo" | zenity --text-info --title="$titulo" \
            --width=720 --height=540 --font=monospace 2>/dev/null; then
        return 0
    fi
    printf '%s\n' "$conteudo"
}

# Indeterminate progress bar. Usage:
#   t_progresso_abre "$(t_msg instalando_generico)" ; ... ; t_progresso_fecha
t_progresso_abre() {
    t_tem_gui || return 0
    command -v zenity >/dev/null 2>&1 || return 0
    [ -n "$TANDEM_TRAVAS" ] || return 0
    TANDEM_FIFO="$TANDEM_TRAVAS/prog.$$"
    mkfifo "$TANDEM_FIFO" 2>/dev/null || { TANDEM_FIFO=""; return 0; }
    ( zenity --progress --pulsate --auto-close --no-cancel \
             --title="Tandem" --text="$1" --width=420 < "$TANDEM_FIFO" 2>/dev/null ) &
    TANDEM_PROG_PID=$!
    # Reading AND writing, on purpose. Opening for writing only, the pipe is
    # left with a single reader - zenity. When that reader goes away (the user
    # closes the window on the X, gnome-shell restarts, zenity refuses an
    # option), the next progress message gets SIGPIPE and KILLS the whole
    # Tandem: exit 141, nothing in the log, no window. In tandem-exe that
    # happens inside the winetricks loop, cutting an installation in half with
    # no receipt. By keeping descriptor 8 open for reading too, the pipe never
    # runs out of readers and the write never raises the signal.
    exec 8<> "$TANDEM_FIFO"
}

t_progresso_texto() {
    [ -n "${TANDEM_FIFO:-}" ] || return 0
    # Is the window still alive? If the user closed it, we record that and
    # stop writing - the work goes on, it just loses the progress bar.
    if [ -n "${TANDEM_PROG_PID:-}" ] && ! kill -0 "$TANDEM_PROG_PID" 2>/dev/null; then
        t_diz "janela de progresso fechada pelo usuario; seguindo sem ela"
        { exec 8>&-; } 2>/dev/null
        rm -f "$TANDEM_FIFO" 2>/dev/null
        TANDEM_FIFO=""
        return 0
    fi
    printf '# %s\n' "$1" >&8 2>/dev/null
    return 0
}

# Runs a command that takes a long time, and SAYS SOMETHING while it runs.
#
# Nothing in this program ever spoke during the wait. t_progresso_abre opens a
# pulsating bar with one static line of text and t_progresso_texto is called
# once per component - so `winetricks -q dotnet48`, which is half an hour,
# showed an identical unchanging bar for its whole duration. Behind a counter,
# "downloading slowly", "stuck on a dead mirror" and "finished three seconds
# ago" are the same picture, and the owner has a customer in front of him and
# no way to tell whether to wait or give up.
#
# What it can honestly say is not a percentage - winetricks does not give one -
# but two facts it does have: how long this has been going, and whether
# anything has been written recently. "Still working, 6 minutes" and "nothing
# new for 4 minutes" are different sentences, and the second is the one that
# tells him it is worth checking his internet.
#
# It NEVER aborts. Killing a slow-but-working dotnet48 is worse than the
# silence this replaces, so this only ever talks.
#
# The command runs in the BACKGROUND and this shell polls, rather than a
# watcher process updating the bar: the main shell keeps sole ownership of
# descriptor 8, so there is nothing to reap and no second writer to race with -
# which is the same class of bug the log marker was written for.
t_progresso_longo() {
    local base="$1"; shift
    local pid inicio agora decorrido tam_antes tam_agora parado=0
    "$@" &
    pid=$!
    inicio=$SECONDS
    tam_antes=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep "${TANDEM_PROGRESSO_PASSO:-5}"
        kill -0 "$pid" 2>/dev/null || break
        agora=$SECONDS
        decorrido=$(( (agora - inicio) / 60 ))
        tam_agora="$(stat -c%s "${LOG:-/dev/null}" 2>/dev/null || echo 0)"
        if [ "$tam_agora" != "$tam_antes" ]; then
            parado=0
            tam_antes="$tam_agora"
        else
            parado=$(( parado + ${TANDEM_PROGRESSO_PASSO:-5} ))
        fi
        # Only after a while, and only in whole minutes: a bar that changes
        # every five seconds is noise, and "nothing new for 10 seconds" is
        # normal for anything that downloads.
        if [ "$parado" -ge "${TANDEM_PROGRESSO_CALADO:-120}" ]; then
            # At least 1, never "nothing new for 0 minutes" - which is what a
            # tuned-down threshold produces and reads as a program that cannot
            # count.
            local mudo=$(( parado / 60 )); [ "$mudo" -lt 1 ] && mudo=1
            t_progresso_texto "$base
$(t_msg_n progresso_sem_novidade "$mudo" "$mudo")"
        elif [ $(( agora - inicio )) -ge "${TANDEM_PROGRESSO_FALA:-60}" ]; then
            [ "$decorrido" -lt 1 ] && decorrido=1
            t_progresso_texto "$base
$(t_msg_n progresso_ha_minutos "$decorrido" "$decorrido")"
        fi
    done
    wait "$pid"
}

t_progresso_fecha() {
    [ -n "${TANDEM_FIFO:-}" ] || return 0
    { exec 8>&-; } 2>/dev/null
    wait "$TANDEM_PROG_PID" 2>/dev/null
    rm -f "$TANDEM_FIFO" 2>/dev/null
    TANDEM_FIFO=""
    return 0
}

# ---------------------------------------------------------------- prefix

# Walks up the directory tree looking for the root of a Wine prefix.
# WHERE this file is being opened from, when the place itself is the problem.
#
# Every pre-flight in this project reads the file's CONTENTS. None of them can
# see its SITUATION, and one situation accounts for a whole class of "files it
# should have brought with it are missing": commercial software reaches a
# Brazilian shop as a zip over WhatsApp, and the owner double-clicks the .exe
# inside the archive-manager window. The manager extracts that ONE file to a
# temporary folder - without the .msi, the data folder and the DLLs beside it -
# and hands it to us. "Files are missing next to it" is true and tells him
# nothing he can act on.
#
# Answers a token, never a sentence, the same shape the readers use:
#   zip       - a temporary folder an archive manager unpacked into
#   portal    - handed over through the desktop portal, so the real folder is
#               not visible to us either
#   removivel - a pen drive or a phone, mounted under /media or /run/media
# Prints nothing when the place says nothing, which is the normal case.
#
# The temp-directory naming is a CONVENTION, not an interface, so this is
# additive only: a wrong guess costs an extra sentence, never a refusal.
t_origem_do_arquivo() {
    local f="${1:-}" d
    [ -n "$f" ] || return 1
    d="$(dirname -- "$f")"
    case "$d" in
        # file-roller unpacks to /tmp/.fr-XXXXXX; Ark and xarchiver use their
        # own names under the same temp root.
        # NOT /tmp/.mount_* : that is an AppImage's own FUSE mount, a
        # different thing entirely, and telling somebody to "save the
        # compressed folder first" about it would be confident wrong advice.
        /tmp/.fr-*|/tmp/.ark*|/tmp/xarchiver*|\
        /tmp/file-roller*|/tmp/engrampa*|/var/tmp/.fr-*)
            printf 'zip'; return 0 ;;
        # The document portal: the path is a per-application view, and the file
        # the owner can actually see lives somewhere else entirely.
        /run/user/*/doc/*|/run/user/*/gvfs/*|/run/flatpak/doc/*)
            printf 'portal'; return 0 ;;
        /media/*|/run/media/*|/mnt/*)
            printf 'removivel'; return 0 ;;
    esac
    return 1
}

t_prefixo_do_arquivo() {
    local d
    d="$(dirname -- "$1")"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        if [ -f "$d/system.reg" ] && [ -d "$d/drive_c" ]; then
            printf '%s' "$d"; return 0
        fi
        d="$(dirname -- "$d")"
    done
    return 1
}

# A prefix is protected if the user listed it, or if it is not our default one
# and was not created by Tandem (the .tandem-prefixo mark).
#
# The user's list is consulted FIRST, on purpose: whoever runs
# "tandem protect" on the default prefix itself is asking that not even Tandem
# touch it, and that decision has to outweigh the ownership mark.
# THE LIST IS A LIST OF PLACES, NOT OF SPELLINGS - and until 4.19 it was
# compared as text, which broke rule 1 for real. Measured end to end: with
# ~/.local/share/tandem/wine a SYMLINK to ~/.wine-pdv, Tandem registered the
# production prefix as protected, wrote "protegido: .../.wine-pdv" in its own
# log, and then installed a winetricks verb INTO IT, planted its receipt and
# its .tandem-assoc there. Every string comparison said "different path"; every
# one of them was about the same directory.
#
# That is not an exotic setup. Pointing the new tool at the Wine setup you
# already have is the first thing a person tries.
t_prefixo_protegido() {
    local p="$1" real alvo
    real="$(readlink -f -- "$p" 2>/dev/null)"
    [ -n "$real" ] || real="$p"
    if [ -f "$TANDEM_PROTEGIDOS" ]; then
        while IFS= read -r alvo; do
            [ -n "$alvo" ] || continue
            [ "$alvo" = "$p" ] && return 0
            [ "$(readlink -f -- "$alvo" 2>/dev/null)" = "$real" ] && return 0
        done < "$TANDEM_PROTEGIDOS"
    fi
    if [ "$p" = "$TANDEM_PREFIXO_PADRAO" ]; then
        # Our own default prefix by name. If that name leads somewhere else and
        # a working prefix is already sitting there, it is somebody else's -
        # the mark is what says whose it is, and this is the second layer under
        # the list, for a prefix the sweep never found.
        #
        # Narrowed to the case where the name really does lead elsewhere, so a
        # marker that failed to be written - a full disk, which is this
        # release's own subject - does not turn Tandem out of its own prefix.
        if [ "$real" != "$p" ] && [ -f "$real/system.reg" ] &&
           [ ! -f "$real/.tandem-prefixo" ]; then
            t_diz "prefixo padrao aponta para $real, que nao e nosso: tratando como protegido"
            return 0
        fi
        return 1
    fi
    [ -f "$p/.tandem-prefixo" ] && return 1
    return 0   # unknown = treat it as protected
}

# Registers a prefix in the untouchable list. Idempotent.
t_protege() {
    local p="$1" dir
    [ -n "$p" ] && [ -d "$p" ] || return 1
    dir="$(dirname -- "$TANDEM_PROTEGIDOS")"
    mkdir -p "$dir" 2>/dev/null || return 1
    grep -qxF -- "$p" "$TANDEM_PROTEGIDOS" 2>/dev/null && return 0
    printf '%s\n' "$p" >> "$TANDEM_PROTEGIDOS" 2>/dev/null || return 1
    t_diz "protegido: $p"
    return 0
}

# Looks for Wine prefixes that already existed and registers them all as
# protected.
#
# The known places first, then a shallow sweep of the home folder: a
# third-party installer (a point-of-sale system, for example) may have put the
# prefix in any corner. The -maxdepth limits the cost and the timeout makes
# sure a huge home folder does not stall the first run; if the sweep is cut
# short, the known places have already been covered.
t_procura_prefixos() {
    local p reg
    for p in "$HOME"/.wine*/ \
             "$HOME"/.local/share/wineprefixes/*/ \
             "$HOME"/.local/share/bottles/bottles/*/ \
             "$HOME"/.var/app/com.usebottles.bottles/data/bottles/bottles/*/ \
             "$HOME"/.PlayOnLinux/wineprefix/*/ \
             "$HOME"/Games/*/; do
        [ -f "${p}system.reg" ] || continue
        [ -f "${p}.tandem-prefixo" ] && continue
        t_protege "${p%/}"
    done

    timeout 20 find "$HOME" -maxdepth 4 -name system.reg -type f 2>/dev/null |
    while read -r reg; do
        p="$(dirname -- "$reg")"
        [ -d "$p/drive_c" ] || continue
        [ -f "$p/.tandem-prefixo" ] && continue
        [ "$p" = "$TANDEM_PREFIXO_PADRAO" ] && continue
        t_protege "$p"
    done
    return 0
}

# ------------------------------------------- the machine's identity
#
# Software that ties its licence to the machine mostly WORKS under Wine, which
# is the opposite of what this project used to say. Since Wine 3.13 the
# manufacturer, model, BIOS version, board, CPU, RAM and MAC that a program
# reads are the real ones, taken from /sys/class/dmi/id and /proc.
#
# What actually goes wrong is narrower and meaner: two of the identifiers live
# INSIDE the prefix and are invented at random when the prefix is made. The
# volume serial of C: and HKLM\...\Cryptography\MachineGuid change every time
# the environment is rebuilt - and the owner, who did nothing but ask for a
# repair, is told to activate again. The field reports describe losing an
# activation far more often than failing to get one.
#
# So Tandem freezes them, and freezes them to a value DERIVED FROM THIS
# MACHINE rather than to a random one. The difference matters: a derived value
# comes back identical after the prefix is destroyed and remade, which is
# exactly the case that was breaking. It is also the honest version - the
# identity is the machine's own, not one borrowed from somewhere else.
#
# What Tandem will NOT do, and the line is deliberate: it does not forge. It
# never invents a Windows ProductId (that is a Microsoft licence identifier),
# and it never fakes the DMI table. Faking DMI is possible - a bind-mount over
# /sys/class/dmi/id makes Wine report anything you like - and it is rejected in
# docs/IDEAS.md with the reason, because a tool that forges hardware identity
# is a licence-defeating tool no matter what it was written for.

# The seed. /var/lib/dbus/machine-id first because that is the file Wine
# itself reads to build the SMBIOS UUID, so an identity derived from it moves
# together with what the program already sees.
t_maquina_semente() {
    local s="" f
    for f in /var/lib/dbus/machine-id /etc/machine-id; do
        [ -r "$f" ] && s="$(tr -d '[:space:]' < "$f" 2>/dev/null)" && [ -n "$s" ] && break
        s=""
    done
    if [ -z "$s" ]; then
        # No machine-id at all: a container, or a system installed by hand.
        # Falling back to something is better than giving up, but it is worth
        # a log line, because a hostname change would then move the identity.
        s="$(hostname 2>/dev/null)-$(id -u 2>/dev/null)"
        t_diz "sem machine-id; identidade derivada do nome da maquina"
    fi
    printf '%s' "$s"
}

t_identidade_hash() {
    printf '%s:%s' "$1" "$(t_maquina_semente)" | sha256sum 2>/dev/null | cut -c1-32
}

# The volume serial of C:, as Wine wants it in .windows-serial: eight hex
# digits. Zero is avoided because a program that reads 00000000 usually treats
# it as "could not read".
t_identidade_serial() {
    local h; h="$(t_identidade_hash volume)"
    h="$(printf '%s' "$h" | cut -c1-8 | tr 'a-f' 'A-F')"
    case "$h" in ''|00000000) h="1A2B3C4D" ;; esac
    printf '%s' "$h"
}

t_identidade_guid() {
    local h; h="$(t_identidade_hash machineguid)"
    [ "${#h}" = 32 ] || { printf ''; return 1; }
    printf '%s-%s-%s-%s-%s' \
        "$(printf '%s' "$h" | cut -c1-8)"   "$(printf '%s' "$h" | cut -c9-12)" \
        "$(printf '%s' "$h" | cut -c13-16)" "$(printf '%s' "$h" | cut -c17-20)" \
        "$(printf '%s' "$h" | cut -c21-32)"
}

# Reads a registry value straight out of system.reg, without starting Wine.
# Fast, and it works on a prefix that is not running - which is what every
# report command here needs.
t_reg_valor() {
    local prefixo="$1" chave="$2" nome="$3"
    local arq="$prefixo/system.reg"
    [ -f "$arq" ] || return 1
    # The key name goes through the ENVIRONMENT and not through "awk -v",
    # which processes escape sequences in what it is given: registry paths in
    # system.reg carry doubled backslashes, and -v would eat exactly half of
    # them, so the key would never match and every value would read as absent.
    T_CHAVE="[$chave]" T_NOME="\"$nome\"=" awk '
        BEGIN { chave = ENVIRON["T_CHAVE"]; nome = ENVIRON["T_NOME"] }
        index($0, chave) == 1 { dentro = 1; next }
        substr($0, 1, 1) == "[" { dentro = 0 }
        dentro && index($0, nome) == 1 {
            v = substr($0, length(nome) + 1)
            sub(/^"/, "", v); sub(/"$/, "", v)
            print v; exit
        }' "$arq" 2>/dev/null
}

# win32 or win64, read out of the prefix and without starting Wine.
#
# Wine writes "#arch=" on the fourth line of system.reg, user.reg and
# userdef.reg when it creates the prefix - measured on Wine 9.0, and it is the
# same line wineserver refuses to start on when it disagrees with WINEARCH.
# Nothing in Tandem read it: "grep -rn '#arch' src/ tests/" returned zero. The
# consequence is not cosmetic. A 64-bit program simply cannot run in a 32-bit
# environment, and somebody else's old prefix is exactly where a 32-bit
# environment is found - so the one case that is decidable BEFORE running was
# the one case Tandem only ever diagnosed afterwards, by grepping English
# ("32-bit installation") out of Wine's log.
# The return code says WHERE the answer came from, and that distinction is the
# whole reason this is not a one-liner:
#
#   0 - Wine declared it, on the #arch= line. A fact.
#   2 - deduced from the folder layout, because that line is absent. A guess.
#   1 - no idea.
#
# A refusal may rest on 0 and never on 2. Turning a guess into "this program
# cannot run" is how a program that works stops opening, and it is the same
# rule the bitness check already follows: better not to condemn than to condemn
# by mistake.
t_prefixo_arquitetura() {
    local prefixo="$1" a=""
    [ -n "$prefixo" ] || return 1
    a="$(sed -n 's/^#arch=//p' "$prefixo/system.reg" 2>/dev/null | head -1)"
    case "$a" in
        win32|win64) printf '%s\n' "$a"; return 0 ;;
    esac
    # Wine did not always write that line, and a prefix made years ago on a
    # counter machine is exactly the kind that would not have it. The folder
    # layout answers the same question: syswow64 exists only in a 64-bit
    # prefix.
    if [ -d "$prefixo/drive_c/windows/syswow64" ]; then
        printf 'win64\n'; return 2
    fi
    [ -d "$prefixo/drive_c/windows/system32" ] && { printf 'win32\n'; return 2; }
    return 1
}

# Freezes the two identifiers, ONCE, in a prefix of ours. Never touches a
# prefix it has already stamped: a program may have activated against what is
# there, and changing it afterwards is precisely the loss this function exists
# to prevent.
#
# Callers must check t_prefixo_protegido first. Rule number 1 has no exception
# here just because the write is small.
t_identidade_fixa() {
    local prefixo="$1" serial guid marca vista escreveu="" faltou="" vistas ja
    [ -d "$prefixo/drive_c" ] || return 1
    # Rule number 1, spelled out here as well as in the caller. The write is
    # small, which is exactly why it would be the one to slip through.
    [ -f "$prefixo/.tandem-prefixo" ] || return 1
    marca="$prefixo/.tandem-identidade"

    serial="$(t_identidade_serial)"
    if [ ! -f "$prefixo/drive_c/.windows-serial" ] && [ -n "$serial" ]; then
        printf '%s\n' "$serial" > "$prefixo/drive_c/.windows-serial" 2>/dev/null &&
            t_diz "serial do volume C: fixado em $serial"
    fi

    # This half NEVER ONCE RAN, and it took real Wine to find out. The guard
    # used to be "the registry value is absent" - and measured on Wine 9.0,
    # wineboot writes a RANDOM MachineGuid into the 64-bit view while creating
    # the prefix, before Tandem gets a turn. So the value was always present,
    # the write was always skipped, and the mark file still recorded
    # MACHINEGUID=<the seed value> - a mark describing something that was not
    # in the prefix. Remake the environment and the program that tied its
    # licence to this machine sees a different machine: exactly the loss the
    # comment above claims to prevent.
    #
    # The RECORDED VALUE is the discriminator, not the file's existence - and
    # the difference is a defect all of its own, caught in review. Writing the
    # mark whatever happened, and then guarding on the mark, means a prefix
    # where one of the two registry views failed to accept the write is frozen
    # that way forever: 32-bit programs and 64-bit programs see different
    # machines, nothing ever retries, and the mark claims a GUID that only half
    # the prefix contains. That is the same lie this function was just fixed
    # for, one shape further out.
    #
    # So: an empty MACHINEGUID means "not stamped yet, try again", and a
    # non-empty one is never touched. A prefix stamped by an earlier version
    # carries a GUID that was never applied, and it stays untouched on purpose:
    # that prefix has been in use, something may have activated against Wine's
    # value, and correcting the record afterwards would cause the very
    # reactivation this function exists to avoid.
    ja="$(sed -n 's/^MACHINEGUID=//p' "$marca" 2>/dev/null | head -1)"
    guid="$(t_identidade_guid)"
    if [ -n "$guid" ] && [ -z "$ja" ]; then
        # Every view this prefix HAS, and each one named out loud. "wine reg"
        # here is a 32-bit process - Ubuntu's wine wrapper picks the 32-bit
        # loader when wine32 is present, the same reason "wine uninstaller
        # --list" enumerates the other view - so a write with no /reg: flag
        # lands in Wow6432Node while the read above looks at the 64-bit key.
        # Measured: with no flag the value appeared under
        # Software\Wow6432Node\Microsoft\Cryptography, with /reg:64 under
        # Software\Microsoft\Cryptography. A 32-bit program and a 64-bit one
        # must see the SAME machine, and 2 of 2 real installers surveyed here
        # are 32-bit, so the 32-bit view is not the afterthought.
        #
        # A win32 prefix has no second view to write, and demanding both there
        # would mean never stamping it at all.
        case "$(t_prefixo_arquitetura "$prefixo" 2>/dev/null)" in
            win32) vistas="32" ;;
            *)     vistas="64 32" ;;
        esac
        for vista in $vistas; do
            if WINEPREFIX="$prefixo" WINEDEBUG=-all wine reg add \
                 'HKLM\Software\Microsoft\Cryptography' /v MachineGuid /t REG_SZ \
                 /d "$guid" /f "/reg:$vista" >/dev/null 2>&1; then
                escreveu="${escreveu:+$escreveu }$vista"
            else
                faltou="${faltou:+$faltou }$vista"
            fi
        done
        if [ -n "$faltou" ]; then
            # Half a machine is worse than none: leave the value unrecorded so
            # the next run tries again. Writing the same GUID twice is
            # harmless - it is the same value from the same seed - and
            # "tandem identidade" shows the two views side by side, so a prefix
            # stuck like this is diagnosable rather than silently split.
            t_diz "MachineGuid nao entrou na(s) vista(s):$faltou; nao vou marcar, para tentar de novo"
            guid=""
        else
            t_diz "MachineGuid fixado em $guid (vistas: $escreveu)"
        fi
    else
        guid="$ja"
    fi

    # The seed goes on record. If an OS reinstall regenerates machine-id, both
    # identifiers move and nothing on screen explains why; with the old value
    # on file the reactivation becomes diagnosable instead of mysterious. This
    # is written even when the GUID did not land, because the seed and the
    # serial are worth recording on their own - the GUID line is simply left
    # empty, which is what tells the next run to try again.
    {
        printf 'SEMENTE=%s\n' "$(t_maquina_semente)"
        printf 'SERIAL=%s\n' "$serial"
        printf 'MACHINEGUID=%s\n' "$guid"
    } > "$marca" 2>/dev/null
    [ -n "$faltou" ] && return 1
    return 0
}

# Work that has to happen once per user, on the first run.
#
# This lives here, and not in the package postinst, because there the per-user
# work depends on guessing who installed it - SUDO_USER, PKEXEC_UID and
# logname. All three fail together when the .deb is installed by the graphical
# installer, which runs in a daemon with no sudo and no controlling terminal:
# the whole block is skipped and the user is left with no visible protection
# and no file association, with no warning at all. Here there is nothing to
# guess, we are already running as the owner of HOME - whether the package was
# installed by apt, by dpkg, by the graphical installer, or by a user created
# afterwards.
#
# The mark avoids repeating: whoever changes the association on purpose later
# does not want Tandem rewriting their choice on every double click.
#
# But the mark used to be empty, and "already run once" then meant "never again"
# - so a machine upgraded from a version that did not know .AppImage and .jar
# never claimed them, and the double click went on doing nothing. Measured on
# this container: after installing 3.7 over 3.6, the .jar still answered
# openjdk-21-java.desktop and the self-test said so.
#
# So the mark now records WHICH VERSION did the work. On an upgrade the prefix
# scan is not repeated - it already happened, and rerunning it would re-protect
# prefixes the owner may have deliberately unprotected - and the associations are
# reapplied in the narrow mode that only claims types this machine has never
# claimed. A type the owner has never seen Tandem own carries no choice of his to
# overwrite.
t_primeira_vez() {
    local dir marca visto
    dir="$(dirname -- "$TANDEM_PROTEGIDOS")"
    marca="$dir/.primeira-vez"
    visto="$(head -1 "$marca" 2>/dev/null)"
    [ "$visto" = "$TANDEM_VERSAO" ] && return 0
    mkdir -p "$dir" 2>/dev/null || return 0
    if [ -f "$marca" ]; then
        t_diz "atualizacao de ${visto:-uma versao anterior} para $TANDEM_VERSAO: conferindo tipos novos"
        if [ -x "$TANDEM_BIN/tandem-repair" ]; then
            TANDEM_SILENCIOSO=1 "$TANDEM_BIN"/tandem-repair --somente-novos \
                >>"${LOG:-/dev/null}" 2>&1
        fi
    else
        t_diz "primeira execucao deste usuario: procurando prefixos e aplicando associacoes"
        t_procura_prefixos
        if [ -x "$TANDEM_BIN/tandem-repair" ]; then
            TANDEM_SILENCIOSO=1 "$TANDEM_BIN"/tandem-repair >>"${LOG:-/dev/null}" 2>&1
        fi
    fi
    printf '%s\n' "$TANDEM_VERSAO" > "$marca" 2>/dev/null
    return 0
}

# -------------------------------------------------------- menu shortcuts
#
# When a Windows installer creates a Start Menu shortcut, winemenubuilder
# creates the corresponding .desktop in
# ~/.local/share/applications/wine/Programs.
# Two things need to happen after that, and neither one did:
#
# 1. Refresh the graphical environment's cache. Tandem already did that, but
#    BEFORE running the program - far too early to see a shortcut that did not
#    exist yet. The menu then ignores a subfolder that has just been born.
# 2. Tell the user where the program ended up. Without that the outcome is
#    "I installed it and it vanished": the program gets onto the machine and
#    the person has no way back. Silent success is as bad as silent failure.

t_atalhos_wine() {
    find "$HOME/.local/share/applications/wine" -name '*.desktop' 2>/dev/null | LC_ALL=C sort
}

# Only the shortcuts from our prefix. A shortcut from somebody else's prefix
# is in the same folder but belongs to its owner: we do not list it, we do not
# open it, we do not delete it.
t_atalhos_nossos() {
    local d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        grep -qF -- "$TANDEM_PREFIXO_PADRAO" "$d" 2>/dev/null && printf '%s\n' "$d"
    done <<< "$(t_atalhos_wine)"
    return 0
}

# Friendly name of a shortcut, to show to the user.
t_nome_do_atalho() {
    local n
    n="$(sed -n 's/^Name=//p' "$1" 2>/dev/null | head -1)"
    [ -n "$n" ] || n="$(basename -- "${1%.desktop}")"
    printf '%s' "$n"
}

# Compares with the earlier list and announces what showed up.
t_anuncia_atalhos() {
    local antes="$1" novos nomes
    novos="$(printf '%s\n' "$(t_atalhos_wine)" | grep -vxF -- "${antes:-__nada__}" 2>/dev/null)"
    [ -n "$novos" ] || return 0
    command -v update-desktop-database >/dev/null 2>&1 &&
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
    nomes="$(printf '%s\n' "$novos" | sed 's|.*/||; s|\.desktop$||' | sed 's/^/• /')"
    t_diz "atalhos novos: $(printf '%s' "$novos" | tr '\n' ' ')"
    t_ok "$(t_msg pronto_procure_no_menu "$nomes")"
    return 0
}

# --------------------------------------------- installed Windows programs
#
# Windows keeps the "Add or remove programs" list in the registry, under
# CurrentVersion\Uninstall. We read the prefix's system.reg and user.reg
# DIRECTLY, instead of asking "wine uninstaller", for a reason discovered on a
# real machine: a 32-bit installer writes the key into one view of the
# registry, and uninstaller.exe - which becomes a 32-bit process when wine32
# is present - enumerates the other one. Result: 7-Zip installed, key in the
# registry, and an empty list. By reading the file we see both views (native
# and Wow6432Node), we do not depend on the process architecture, and we do
# not even need Wine in order to list.
#
# Output, one line per program:
#     key|||name|||silent-uninstaller|||uninstaller
# Entries with no name or no uninstaller are not real programs (components,
# runtimes) and are left out, just like in Windows itself.
t_uninstall_dump() {
    local pref="${1:-$TANDEM_PREFIXO_PADRAO}" f
    for f in "$pref/system.reg" "$pref/user.reg"; do
        [ -f "$f" ] || continue
        awk '
        function valor(s) {
            sub(/^"[^"]*"="/, "", s); sub(/"$/, "", s)
            gsub(/\\\\/, "\x01", s); gsub(/\\"/, "\"", s); gsub(/\x01/, "\\", s)
            return s
        }
        function emite() {
            if (chave != "" && nome != "" && (un != "" || qun != "") && !sysc)
                printf "%s|||%s|||%s|||%s\n", chave, nome, qun, un
            chave = ""
        }
        /^\[Software\\\\(Wow6432Node\\\\)?Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\/ {
            emite()
            sec = $0
            sub(/^\[Software\\\\(Wow6432Node\\\\)?Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\/, "", sec)
            sub(/\].*$/, "", sec)
            chave = sec; nome = ""; un = ""; qun = ""; sysc = 0
            gsub(/\\\\/, "\\", chave)
            next
        }
        /^\[/ { emite(); next }
        chave != "" && /^"DisplayName"=/          { nome = valor($0) }
        chave != "" && /^"UninstallString"=/      { un = valor($0) }
        chave != "" && /^"QuietUninstallString"=/ { qun = valor($0) }
        chave != "" && /^"SystemComponent"=dword:00000001/ { sysc = 1 }
        END { emite() }
        ' "$f"
    done | awk -F'\\|\\|\\|' '!vistos[$1]++'
}

# Compatibility for whoever only wants "key|||name".
t_programas_instalados() {
    t_uninstall_dump "$@" | awk -F'\\|\\|\\|' '{ printf "%s|||%s\n", $1, $2 }'
}

# Splits a Windows command ("C:\...\Uninstall.exe" /S) into executable and
# arguments, and runs it in the current prefix. The path may come quoted (and
# almost always does, because of "Program Files").
t_executa_comando_windows() {
    local cmd="$1" exe resto
    case "$cmd" in
        '"'*)
            exe="${cmd#\"}"; exe="${exe%%\"*}"
            # Cut by length, never by pattern: the backslashes of a Windows
            # path turn into escapes in ${var#pattern} and the cut fails
            # silently, repeating the path as an argument.
            resto="${cmd:$(( ${#exe} + 2 ))}" ;;
        *)
            exe="${cmd%% *}"
            resto="${cmd:${#exe}}" ;;
    esac
    resto="${resto# }"
    [ -n "$exe" ] || return 1
    # The uninstaller arguments are separated by spaces on purpose.
    # shellcheck disable=SC2086
    wine "$exe" $resto
}

# Removes menu shortcuts that point to a program that no longer exists.
#
# After uninstalling, Wine usually leaves the shortcut behind. A shortcut that
# opens nothing is worse than no shortcut at all: the user clicks, nothing
# happens, and concludes that the computer is broken.
#
# We only touch a shortcut that mentions OUR prefix. A shortcut from somebody
# else's prefix belongs to its owner, even sitting in the same folder.
t_limpa_atalhos_orfaos() {
    local base d rel lnk n=0
    base="$HOME/.local/share/applications/wine/Programs"
    [ -d "$base" ] || return 0
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        grep -qF -- "$TANDEM_PREFIXO_PADRAO" "$d" 2>/dev/null || continue
        rel="${d#"$base/"}"; rel="${rel%.desktop}"
        # Wine mirrors the Start Menu tree when it creates the shortcut, so
        # the corresponding .lnk has the same relative path.
        for lnk in \
            "$TANDEM_PREFIXO_PADRAO/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/$rel.lnk" \
            "$TANDEM_PREFIXO_PADRAO"/drive_c/users/*/"Start Menu/Programs/$rel.lnk"; do
            [ -f "$lnk" ] && continue 2
        done
        rm -f -- "$d" && n=$((n+1)) && t_diz "atalho orfao removido: $d"
    done <<< "$(t_atalhos_wine)"
    if [ "$n" -gt 0 ]; then
        command -v update-desktop-database >/dev/null 2>&1 &&
            update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
        find "$base" -mindepth 1 -type d -empty -delete 2>/dev/null
    fi
    printf '%s' "$n"
    return 0
}

# Architecture of a PE executable: 32, 64, arm64 or "?"; fails if not a PE.
t_pe_arch() {
    local f="$1" off mach
    [ "$(od -An -c -N2 -- "$f" 2>/dev/null | tr -d ' ')" = "MZ" ] || return 1
    off=$(od -An -tu4 -j60 -N4 -- "$f" 2>/dev/null | tr -d ' ')
    case "$off" in ''|*[!0-9]*) return 1 ;; esac
    [ "$(od -An -c -j"$off" -N2 -- "$f" 2>/dev/null | tr -d ' ')" = "PE" ] || return 1
    mach=$(od -An -tx2 -j"$((off+4))" -N2 -- "$f" 2>/dev/null | tr -d ' ')
    case "$mach" in
        014c) echo 32 ;;
        8664) echo 64 ;;
        aa64) echo arm64 ;;
        *)    echo "?" ;;
    esac
}

# ---------------------------------------------------------- alternatives
#
# The best outcome for the owner is not always "your Windows program runs
# under Wine". Sometimes it is "you do not need Wine": many programs have an
# official Linux version, and running their Windows version under Wine is
# always worse - slower, without updates, and it breaks when Wine changes.
#
# Tandem never swaps anything and never suggests replacing a program that is
# working. This shows up in two situations: when the owner asks, and when the
# pre-flight recognized that that program is never going to work here - where
# keeping quiet would leave the owner with no way out at all.
#
# The table is local and auditable, not an internet search: Tandem works
# without a network and sends nothing anywhere. One new line is enough.

# The data tables carry prose too, and it reaches the owner: the "what changes"
# column of alternativas.tsv and the whole of limites.tsv are sentences, not
# codes. So they get the same treatment as the message catalogues - a
# per-language file, falling back to the Portuguese original when a translation
# of that table does not exist yet.
#
# The fallback is what makes this safe to ship half-done: a Spanish machine
# with no alternativas.es.tsv reads the Portuguese rows rather than reading
# nothing, exactly as a missing catalogue key falls back to Portuguese.
t_tabela_do_idioma() {
    local base="$1" dir
    dir="$(dirname -- "$base")"
    local nome; nome="$(basename -- "$base" .tsv)"
    if [ -n "${TANDEM_IDIOMA:-}" ] && [ "$TANDEM_IDIOMA" != "$TANDEM_IDIOMA_PADRAO" ] &&
       [ -f "$dir/$nome.$TANDEM_IDIOMA.tsv" ]; then
        printf '%s' "$dir/$nome.$TANDEM_IDIOMA.tsv"
    else
        printf '%s' "$base"
    fi
}

TANDEM_ALTERNATIVAS="${TANDEM_ALTERNATIVAS:-${TANDEM_LIB:-/usr/lib/tandem}/alternativas.tsv}"

# Looks up by name. Returns "class|name|how to install|what changes", one
# alternative per line.
t_alternativas_para() {
    local alvo padrao classe nome como muda
    alvo="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"
    [ -n "$alvo" ] || return 1
    local tabela; tabela="$(t_tabela_do_idioma "$TANDEM_ALTERNATIVAS")"
    [ -f "$tabela" ] || return 1
    local achou=1
    while IFS=$'\t' read -r padrao classe nome como muda; do
        case "$padrao" in ''|'#'*) continue ;; esac
        [ -n "$nome" ] || continue
        # shellcheck disable=SC2254
        case "$alvo" in
            $padrao) printf '%s|%s|%s|%s\n' "$classe" "$nome" "$como" "$muda"; achou=0 ;;
        esac
    done < "$tabela"
    return $achou
}

# Text ready to show to the owner, or empty if there is nothing.
t_texto_alternativas() {
    local linhas classe nome como muda saida=""
    linhas="$(t_alternativas_para "$1")" || return 1
    while IFS='|' read -r classe nome como muda; do
        [ -n "$nome" ] || continue
        if [ "$classe" = nativo ]; then
            saida="$saida
$(t_msg alternativa_nativa "$nome" "$muda" "$como")"
        else
            saida="$saida
$(t_msg alternativa_parecida "$nome" "$muda" "$como")"
        fi
    done <<< "$linhas"
    [ -n "$saida" ] || return 1
    printf '%s' "$saida"
}

# ---------------------------------------------------------------- memory
#
# Every time Tandem runs it discovers things - which components the program
# asked for, which one solved it, how long it took, whether it opened in the
# end. Until now that turned into one log line and died. The memory keeps what
# was learned PER PROGRAM, in a readable text file the owner can open, check
# and send to somebody else.
#
# Two rules the memory cannot break:
#
# 1. It never acts on its own. A recipe is a suggestion, not an order: Tandem
#    shows what it learned and asks. A wrong lesson learned silently would
#    repeat forever, and this program touches the machine where the owner
#    makes their money.
# 2. It is always readable and erasable. If the memory gets in the way,
#    "tandem esquecer" fixes it, and the owner can READ what was stored before
#    deciding.

TANDEM_MEMORIA="${TANDEM_MEMORIA:-$HOME/.local/share/tandem/memoria}"

# Stable identity of a program: size + start + end of the file.
#
# We do not use the path, which changes folder and machine, nor the name,
# which repeats ("setup.exe"). Reading the whole file would be slow on a
# half-gigabyte installer, and the ends plus the size already separate
# different versions of the same program - which is the only confusion that
# matters to avoid here.
t_memoria_id() {
    local f="$1" tam
    [ -f "$f" ] || return 1
    tam="$(stat -c%s -- "$f" 2>/dev/null)" || return 1
    command -v sha256sum >/dev/null 2>&1 || return 1
    {
        printf '%s\n' "$tam"
        head -c 1048576 -- "$f" 2>/dev/null
        tail -c 1048576 -- "$f" 2>/dev/null
    } | sha256sum | cut -c1-32
}

t_memoria_arquivo() {
    local id; id="$(t_memoria_id "$1")" || return 1
    [ -n "$id" ] || return 1
    printf '%s/%s.txt' "$TANDEM_MEMORIA" "$id"
}

t_memoria_le() {
    local arq valor; arq="$(t_memoria_arquivo "$1")" || return 1
    [ -f "$arq" ] || return 1
    valor="$(sed -n "s/^$2=//p" "$arq" | tail -1)"
    [ -n "$valor" ] || return 1
    # Undo the escaping t_memoria_grava applies to keep one value per line.
    printf '%b' "${valor//%/%%}"
    printf '\n'
}

# Writes a key, replacing the previous value. Creates the file the first time,
# with the program name at the top so the owner knows what it is about.
t_memoria_grava() {
    local prog="$1" chave="$2" valor="$3" arq tmp
    arq="$(t_memoria_arquivo "$prog")" || return 1
    mkdir -p "$TANDEM_MEMORIA" 2>/dev/null || return 1
    if [ ! -f "$arq" ]; then
        # These two comment lines are prose: the owner is invited, in the
        # product's own words, to read this file and send it to somebody. A
        # file the user is told to open is a screen, so it is translated.
        {
            printf '# %s\n' "$(t_msg arq_memoria_cab1)"
            printf '# %s\n' "$(t_msg arq_memoria_cab2)"
            printf 'PROGRAMA=%s\n' "$(basename -- "$prog")"
        } > "$arq" 2>/dev/null || return 1
    fi
    # A PER-PROCESS temp name AND a lock, the same fix t_config_grava got in
    # 4.22 - and the reason it belongs here too is the reason 4.22 existed:
    # this is a read-modify-write, "$arq.novo" was a FIXED name, and Tandem
    # writes several keys per run (RESOLVERAM, CONFIRMADO, SEGUNDOS, VISTO_EM,
    # PROVA...) while a detached background process may touch the same file.
    # Measured on this exact code before the fix: four concurrent writers of
    # thirty keys each lost two of the four keys entirely. The lock is
    # best-effort by the rule the prefix lock follows - a lock that cannot be
    # CREATED (full disk, read-only home) must not be taken for one that is
    # held, so the write proceeds unserialised rather than refusing to record
    # a lesson.
    tmp="$arq.novo.$$"
    local trava="${TANDEM_TRAVAS:-$TANDEM_MEMORIA}/memoria.lock"
    if { exec 7> "$trava"; } 2>/dev/null; then
        flock -w 10 7 2>/dev/null || :
    fi
    # The file format is one KEY=VALUE per line, so the value must be one line.
    # A multi-line value used to be written raw, and the rewrite filter
    # (grep -v "^KEY=") only removes the FIRST physical line - the continuation
    # lines survive as orphans and a fresh copy is appended on every run. Four
    # runs left twenty-two lines with three orphan blocks in them, and the
    # damage is permanent because nothing ever cleans it up. Escape on write,
    # unescape on read.
    valor="${valor//\\/\\\\}"
    valor="${valor//$'\n'/\\n}"
    {
        # Drop the old value AND any orphan continuation lines a previous
        # version may already have written: a line that is neither a comment
        # nor KEY=VALUE has no business in this file.
        grep -E '^(#|[A-Z_]+=)' "$arq" 2>/dev/null | grep -v "^$chave="
        printf '%s=%s\n' "$chave" "$valor"
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$arq" 2>/dev/null
    local c=$?
    rm -f "$tmp" 2>/dev/null
    { exec 7>&-; } 2>/dev/null
    return $c
}

# Appends an item to a space-separated list, without repeating it.
t_memoria_junta() {
    local prog="$1" chave="$2" item="$3" atual
    atual="$(t_memoria_le "$prog" "$chave" 2>/dev/null)"
    case " $atual " in *" $item "*) return 0 ;; esac
    t_memoria_grava "$prog" "$chave" "${atual:+$atual }$item"
}

# --------------------------------------------------------------- recipes
#
# A recipe is one program's memory in a small, readable file that the owner
# can check and send to somebody else. It is the atom of collective knowledge
# - and it works with no server at all.
#
# The direction is ALWAYS from the outside in: Tandem reads recipes, it never
# sends anything. Contributing is a human act, deliberate and visible. A
# program that sends data on its own would have no place on a point-of-sale
# machine, and a base written by just anybody would be attack surface.

# Acceptable verb name. This is the defense that matters: the verb of a recipe
# becomes an argument to "winetricks -q". Without this sieve, a recipe coming
# from outside could carry a command along with the name.
# A verb name that is safe to hand to "winetricks -q".
#
# The character set was right and the SHAPE was not, and the two holes it left
# are both live today through "tandem receita --importar" - a plain text file
# the recipe's own header tells the owner to accept from other people:
#
#   1. A leading dash was allowed, so "--self-update" and "-q" passed. Those are
#      not verbs, they are winetricks' own options: "winetricks -q
#      --self-update" makes winetricks overwrite itself from the internet.
#   2. A dot was allowed, and winetricks treats an argument matching *.verb as a
#      FILE TO SOURCE - read in the shipped winetricks at the command-line loop:
#      `case ${verb} in */*) . "${verb}" ;; *) . ./"${verb}" ;; esac`. So
#      "evil.verb" is sourced as a shell script, from the current directory -
#      and executar() does `cd -- "$(dirname -- "$PROG")"` outside a subshell,
#      so by the time winetricks runs the current directory is the folder the
#      owner double-clicked in. A zip carrying setup.exe plus evil.verb plus a
#      recipe naming that verb is arbitrary code, as the user.
#
# Rejecting the dot outright costs nothing: measured against the installed
# winetricks, ZERO of its 538 verb names contain one.
t_verbo_valido() {
    case "${1:-}" in
        ''|*[!a-zA-Z0-9_-]*) return 1 ;;
        # Must begin with a letter or a digit. This is the whole of the
        # option-injection fix and it is one line.
        [!a-zA-Z0-9]*) return 1 ;;
    esac
    [ "${#1}" -le 40 ] || return 1
    return 0
}

# Verbs that change a SETTING rather than install a dependency, which is not
# something a lesson from somebody else's machine may ever do.
#
# winetricks labels every verb with a category of its own - 315 dlls, 112
# settings, 62 apps, 41 fonts, 8 benchmarks - and "settings" is where the
# damage lives: "sandbox" and "isolate_home" REMOVE the prefix's links to
# $HOME, "remove_mono" takes .NET support out, "winxp" and "win95" move the
# Windows version under an installed program's feet. Every one of them passes
# every validity check, installs cleanly, and earns a permanent receipt under
# rule number 4.
#
# The authority is winetricks itself, so this keeps working as winetricks
# changes. When it cannot be read - not installed yet, at recipe-import time -
# fall back to naming the destructive ones, because refusing every outside verb
# on a machine that has no winetricks would reject a legitimate recipe for a
# reason that has nothing to do with the recipe.
t_verbo_de_fora_ok() {
    local verbo="${1:-}" wt
    t_verbo_valido "$verbo" || return 1
    wt="$(command -v winetricks 2>/dev/null)"
    if [ -n "$wt" ] && [ -r "$wt" ]; then
        grep -q "^w_metadata ${verbo} settings" "$wt" 2>/dev/null && return 1
        return 0
    fi
    case "$verbo" in
        sandbox|isolate_home|remove_mono|forcemono|nocrashdialog|alldlls|\
        win2k|win2k3|win7|win8|win81|win10|win11|win20|win30|win31|win95|\
        win98|winme|winnt40|winvista|winxp|winxp64|native_mdac|native_oleaut32)
            return 1 ;;
    esac
    return 0
}

t_receita_exporta() {
    local prog="$1" arq
    arq="$(t_memoria_arquivo "$prog" 2>/dev/null)" || return 1
    [ -f "$arq" ] || return 1
    # A recipe is written to be READ by a person and handed to another person,
    # which makes its header the most-read prose in the whole feature. The
    # importer skips every line starting with "#", so translating these three
    # cannot break a recipe that crosses a language border.
    printf '# %s\n' "$(t_msg arq_receita_cab1)"
    printf '# %s\n' "$(t_msg arq_receita_cab2)"
    printf '# %s\n' "$(t_msg arq_receita_cab3)"
    printf 'TANDEM_RECEITA=1\n'
    printf 'IDENTIDADE=%s\n' "$(t_memoria_id "$prog")"
    printf 'ORIGEM=%s\n' "$( . /etc/os-release 2>/dev/null
                             printf '%s' "${PRETTY_NAME:-Linux}")"
    # Where the confidence of this lesson comes from. Without this line, "the
    # process exited 0" and "a person looked at the screen and said it was
    # right" arrived on the other side with exactly the same weight.
    printf 'CONFIANCA=%s\n' "$(t_confianca_da_licao "$prog")"
    # PROCEDENCIA is a purely-local display throttle - which recognition line was
    # last shown on THIS machine, so a note fires only when the status changes.
    # It says nothing about the lesson and must not travel: on another machine
    # the recognition is computed fresh from that machine's own memory and list.
    # The importer already whitelists keys and would drop it, but a recipe is
    # read by a person, and a stray internal marker in it is noise.
    grep -v '^#' "$arq" | grep -v '^PROCEDENCIA='
}

# Reads a recipe and turns it into memory. Refuses anything it does not
# recognize: a recipe for another program, a verb with a strange character, a
# file that does not declare itself a recipe.
t_receita_importa() {
    local arq="$1" prog="$2" id_esperada chave valor verbos="" v
    [ -f "$arq" ] || return 1
    grep -q '^TANDEM_RECEITA=1$' "$arq" || return 2
    id_esperada="$(t_memoria_id "$prog" 2>/dev/null)" || return 1

    # Is the recipe from ANOTHER program? Applying it would teach the wrong
    # lesson.
    local id_receita
    id_receita="$(sed -n 's/^IDENTIDADE=//p' "$arq" | head -1)"
    [ -n "$id_receita" ] || return 3
    [ "$id_receita" = "$id_esperada" ] || return 3

    while IFS='=' read -r chave valor; do
        case "$chave" in
            RESOLVERAM|NAO_RESOLVERAM)
                for v in $valor; do
                    t_verbo_de_fora_ok "$v" || { t_diz "receita recusada: verbo suspeito ou que nao instala dependencia: '$v'"; return 4; }
                done
                verbos="$verbos$chave=$valor"$'\n' ;;
            # These four were copied VERBATIM, and the verb check above made
            # that look safer than it was: a recipe is the file whose own header
            # tells the owner to accept it from other people, and ARQUITETURA
            # goes straight into field 2 of a community-list record
            # (t_lista_registro). A TAB survives t_memoria_grava, so a value of
            # "64<TAB>vcrun2022<TAB>...<TAB>Padaria do Joao" spliced the
            # remaining fields INCLUDING THE NOTE - a way to write a shop's name
            # into a public list, and worse, a tagging primitive: a unique
            # string per victim, readable back off the list afterwards.
            #
            # A tab or a newline in any of them is refused outright, and
            # ARQUITETURA is held to the vocabulary the record allows.
            ARQUITETURA)
                case "$valor" in
                    32|64|arm64|-) ;;
                    *) t_diz "receita recusada: arquitetura invalida: '$valor'"; return 5 ;;
                esac
                verbos="$verbos$chave=$valor"$'\n' ;;
            LIMITE|RESULTADO|PROGRAMA)
                case "$valor" in
                    *"$(printf '\t')"*)
                        t_diz "receita recusada: $chave contem tabulacao"; return 5 ;;
                esac
                verbos="$verbos$chave=$valor"$'\n' ;;
        esac
    done < "$arq"

    while IFS='=' read -r chave valor; do
        [ -n "$chave" ] || continue
        t_memoria_grava "$prog" "$chave" "$valor"
    done <<< "$verbos"
    t_memoria_grava "$prog" ORIGEM_DA_RECEITA "$(basename -- "$arq")"
    return 0
}

t_memoria_esquece() {
    local arq; arq="$(t_memoria_arquivo "$1" 2>/dev/null)" || return 1
    [ -f "$arq" ] || return 1
    rm -f -- "$arq"
}

# ----------------------------------------------------- proof of delivery
#
# Did the installed component really deliver the file that was missing?
#
# Wine writes the names in lowercase and its log carries "MSVCP140.dll", hence
# -iname. Both views of system32 are consulted: a 32-bit installer in a win64
# prefix writes into syswow64.
# Did the DLL arrive where this program is able to load it?
#
#   0 = arrived in the right place
#   1 = did not arrive anywhere
#   2 = arrived, but in the wrong bitness - it exists in the prefix and this
#       program cannot use it
#
# The distinction between 1 and 2 is not fussiness: it showed up the first
# time the loop ran with a real winetricks. The mfc42 verb EXITED 0 and
# delivered the file - into syswow64, which is the 32-bit folder. The program
# was 64-bit, Wine kept saying "not found", and the proof of delivery (which
# looked at both folders) approved it and wrote a receipt. Result: the dead
# end all over again, with the cause intact, only now with a receipt on top.
# winetricks even warns about this in English in the middle of the log - "many
# verbs only install 32-bit versions of packages" - which is exactly the kind
# of notice the shop owner is never going to read.
#
# In a win64 prefix Wine follows the Windows convention: system32 holds the
# 64-bit DLLs and syswow64 the 32-bit ones. In a win32 prefix only system32
# exists, and it is 32-bit.
# Is this file Wine's own stub rather than the real library?
#
# It matters because "the file is in system32" was being read as proof of
# delivery, and Wine puts about 560 DLLs of its own into every prefix at
# creation. For the most expensive verb in the project that made the proof
# measure nothing at all: verbos.tsv maps dotnet48 -> mscoree.dll, and
# mscoree.dll is present in BOTH system32 and syswow64 of a prefix that has no
# .NET anywhere - measured on a virgin win64 prefix with no Microsoft.NET
# folder and zero "NET Framework Setup" registry keys. So a dotnet48 that
# exited 0 without installing anything got approved, the receipt was written,
# and under rule number 4 the receipt is permanent: on the next double click
# Tandem says "I already installed what this program was asking for" and gives
# up, half an hour of the owner's time spent on nothing. That is precisely the
# damage the proof of delivery was invented to prevent.
#
# Wine marks its own DLLs where it costs nothing to look. It replaces the DOS
# stub message ("This program cannot be run in DOS mode") with "Wine builtin
# DLL" at offset 64 of the file. Measured on the 560 DLLs of a fresh prefix:
# all 560 carry it, at exactly that offset. Sixteen bytes read, nothing run.
t_dll_builtin_wine() {
    local arq="$1" marca
    [ -f "$arq" ] || return 1
    marca="$(dd if="$arq" bs=1 skip=64 count=16 2>/dev/null | LC_ALL=C tr -d '\000')"
    [ "$marca" = "Wine builtin DLL" ]
}

t_dll_no_prefixo() {
    local dll="$1" arch="${2:-}" c s32 s64 tem32=1 tem64=1
    [ -n "$dll" ] && [ -n "${WINEPREFIX:-}" ] || return 1
    c="$WINEPREFIX/drive_c/windows"
    s64="$c/system32"; s32="$c/syswow64"
    # With no syswow64, the prefix is 32-bit: system32 holds the 32-bit ones.
    [ -d "$s32" ] || { s32="$c/system32"; s64=""; }

    _t_acha_dll() {
        local achou
        [ -n "$1" ] && [ -d "$1" ] || return 1
        achou="$(find "$1" -maxdepth 1 -iname "$dll" -print -quit 2>/dev/null)"
        [ -n "$achou" ] || return 1
        # Wine's own stub does not count as an arrival: it is what was already
        # failing. A DLL that came out of err:module:import_dll cannot be a
        # builtin anyway - Wine said it could not find it - so this only ever
        # changes the answer where the question came from the verb instead of
        # from the log, which is the shortcut taken by "memoria" and "lista".
        ! t_dll_builtin_wine "$achou"
    }
    _t_acha_dll "$s32" && tem32=0
    _t_acha_dll "$s64" && tem64=0
    unset -f _t_acha_dll

    case "$arch" in
        64) [ "$tem64" = 0 ] && return 0; [ "$tem32" = 0 ] && return 2 ;;
        32) [ "$tem32" = 0 ] && return 0; [ "$tem64" = 0 ] && return 2 ;;
        # Without knowing the program's architecture, any of them will do: it
        # is better not to condemn than to condemn by mistake.
        *)  { [ "$tem32" = 0 ] || [ "$tem64" = 0 ]; } && return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------- PE pre-flight
#
# Every Windows executable carries in the file itself the list of libraries it
# is going to ask for - the import table. Until now Tandem only found that out
# AFTER running and failing, by reading Wine's err:module:import_dll.
#
# The pre-flight does NOT decide what to install. It cannot: only Wine knows
# which DLLs it implements itself, and acting on its own would mean a useless
# installation - half an hour of the owner's time thrown away. The pre-flight
# is there for what reading alone proves: recognizing, BEFORE trying, a
# program that depends on something that is never going to work here, and
# having that ready to explain the failure afterwards.

t_pe_dlls() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "${TANDEM_LIB:-/usr/lib/tandem}/peinfo.py" "$1" 2>/dev/null |
        sed -n -e 's/^DLLS=//p' -e 's/^ATRASADAS=//p' | tr ',' '\n' | grep -v '^$'
}

# Classes with no way out. Everything NOT listed here has a fourth column in
# limites.tsv saying what to try, and gets a different message: the difference
# between "this has no fix" and "this has a fix and here it is" is the whole
# reason the table grew a fourth column. Getting this list wrong in the
# permissive direction promises something that does not exist; getting it wrong
# in the strict direction is what the 4.0 correction was about.
t_limite_sem_saida() {
    case "$1" in
        dongle|driver|anticheat|usb) return 0 ;;
        *) return 1 ;;
    esac
}

# Returns "class|sentence" of the first limit recognized, or nothing. When the
# row carries a way out, it comes after the sentence separated by a blank line,
# so everything downstream - the message, the memory, the recipe - keeps
# treating it as one block of text.
#
# The table lives in limites.tsv and grows without touching code.
t_limite_do_programa() {
    local tabela dll padrao classe frase saida
    tabela="$(t_tabela_do_idioma "${TANDEM_LIMITES:-${TANDEM_LIB:-/usr/lib/tandem}/limites.tsv}")"
    [ -f "$tabela" ] || return 1
    local dlls; dlls="$(t_pe_dlls "$1")"
    [ -n "$dlls" ] || return 1
    while IFS=$'\t' read -r padrao classe frase saida; do
        case "$padrao" in ''|'#'*) continue ;; esac
        [ -n "$frase" ] || continue
        while IFS= read -r dll; do
            # The pattern comes from the table and uses * on purpose, so it
            # cannot be quoted.
            # shellcheck disable=SC2254
            case "$dll" in
                $padrao)
                    printf '%s|%s' "$classe" "$frase"
                    [ -n "$saida" ] && printf '\n\n%s' "$saida"
                    return 0 ;;
            esac
        done <<< "$dlls"
    done < "$tabela"
    return 1
}

# The same verdict, but PROVEN instead of guessed - read out of the log after
# the program has already run and failed.
#
# limites.tsv guesses from the import table, which is honest but static: a
# program can import ntoskrnl.exe in a component it never loads. These lines
# are Wine telling us it actually happened. They matter most in the case the
# table cannot reach at all: a driver that LOADS - Wine's load_driver() takes
# any .sys with LoadLibraryExW into winedevice.exe, an ordinary user process -
# and then finds the hardware underneath is hollow. MmMapIoSpace is a stub
# returning NULL, the port I/O helpers return zeros and discard writes. So the
# program starts, reads zeros, and misbehaves in a way that looks like a bug in
# the program. That is the silent failure this project exists to catch, and the
# log is the only place it is visible.
t_limite_do_log() {
    local log="$1"
    [ -f "$log" ] || return 1
    # The verdict travels as "class|sentence", the same shape limites.tsv
    # produces - and limites.tsv has a translation per language while these two
    # sentences, the PROVEN half of the same diagnosis, were literal Portuguese.
    if grep -qE 'MmMapIoSpace|READ_PORT_|WRITE_PORT_|IoConnectInterrupt' "$log" 2>/dev/null; then
        printf 'driver|%s' "$(t_msg limite_log_hardware)"
        return 0
    fi
    if grep -qE 'ZwLoadDriver|err:winedevice|failed to load driver' "$log" 2>/dev/null; then
        printf 'driver|%s' "$(t_msg limite_log_driver)"
        return 0
    fi
    return 1
}

t_tem_wine32() {
    [ -d /usr/lib/wine/i386-unix ] || [ -d /usr/lib/i386-linux-gnu/wine ] ||
    [ -d /opt/wine-stable/lib/wine/i386-unix ]
}

# The normal case, and the one Tandem's prefix uses (WINEARCH=win64). It
# exists as a function of its own because the diagnosis needs to STATE that
# 64-bit works: talking only about 32, which is the exception, makes the
# reader conclude that 64 is not supported.
t_tem_wine64() {
    [ -d /usr/lib/wine/x86_64-unix ] || [ -d /usr/lib/x86_64-linux-gnu/wine ] ||
    [ -d /opt/wine-stable/lib/wine/x86_64-unix ]
}

# -------------------------------------------------- install what is missing
#
# Tandem knows how to diagnose what is missing (doctor); from here on it also
# fixes it. This cannot be done while the .deb itself is being installed: dpkg
# holds a lock while the postinst runs, and an "apt-get install" in there dies
# in a deadlock. The right moment is the first use - or the exact moment of
# the click where the piece was missing.

# Runs a script as root: directly if we are already root, sudo if there is a
# terminal, pkexec if there is a graphical session. The order puts the
# terminal first because there the user SEES apt working; pkexec shows only
# the password prompt.
# ==================================================== COMMUNITY LIST
#
# The model is that of ad-blocker filter lists: a static text file, fetched
# over HTTPS, that each installation reads and merges into what it already
# knows. That is why EasyList has survived for twenty years on a volunteer's
# budget and a service of our own would not - a static file has no server
# going down, no account, no database, no per-user cost, and anybody can
# mirror it.
#
# The two halves are ASYMMETRIC on purpose:
#   download - automatic when the owner turns it on; it is just a GET of a
#              public file
#   upload   - Tandem ASSEMBLES the record, the owner is the one who sends it
# Automatic contribution would be a production machine sending data out
# without anybody asking for it. It is rule number 1 applied to the network.
#
# The full format is in docs/LIST-FORMAT.md.

TANDEM_LISTA_URL="${TANDEM_LISTA_URL:-https://raw.githubusercontent.com/ChrnX0/Tandem/main/lista/lista.tsv}"
TANDEM_LISTA="${TANDEM_LISTA:-$TANDEM_ESTADO/lista.tsv}"
TANDEM_LISTA_VERSAO=1

# Fields that may never leave this machine. This is not a recommendation: it
# is the test the contribution generator runs against its own text before
# showing it.
# The first field is a 32-character hex fingerprint, and that is what broke this
# function. Matching the user name as a SUBSTRING of the whole record meant that
# a name which happens to be hex matched the fingerprint: measured here, a
# machine whose owner is called "a", "e" or "f" had 5 of 5 clean records refused,
# and "ed" 3 of 5. Those are ordinary Unix names. And a refused line is not
# parked, it is DELETED - t_envio_envia skips it without writing it to the file
# that replaces the queue - so the sieve was quietly destroying the lesson it was
# meant to be protecting.
#
# So the fingerprint is skipped and the rest is compared FIELD BY FIELD.
#
# Note what the parking fix above changes about the rest of this function. While
# a refusal DELETED the line, every over-broad rule cost the owner a lesson, so
# each one had to be argued for. Now that a refusal only holds the line back,
# erring toward refusal is cheap and erring toward sending is not - the record
# stays in the queue either way. That is why "works on 1.2.3.4" is refused even
# though it is plainly a version number and not an address: telling those two
# apart in free text is not reliably possible, the cost of guessing wrong in one
# direction is a line that waits, and in the other it is a shop's LAN address on
# a public list. Do not "fix" that refusal without first re-checking that a
# refused line is still parked.
t_lista_vaza() {
    local reg="$1" campo n=0 usuario maquina
    usuario="$(id -un 2>/dev/null)"
    maquina="${HOSTNAME:-$(hostname 2>/dev/null)}"

    # How a name is matched depends on how long it is, and the reason is the
    # fingerprint. A name of three characters or more is looked for ANYWHERE in a
    # field, so that "joao" is found inside "joaospc". A shorter one is looked for
    # only as a whole field or as a whole word, because one or two hex characters
    # are a substring of almost every record this program will ever build - and
    # this machine's own host name is "vm", which is exactly that case. Dropping
    # short names entirely would be simpler and would quietly abandon the promise
    # in docs/LIST-FORMAT.md that a record cannot carry a machine name.
    _t_acha_nome() {                   # $1 = field, $2 = name
        [ -n "$2" ] || return 1
        if [ "${#2}" -ge 3 ]; then
            case "$1" in *"$2"*) return 0 ;; esac
        else
            case " $1 " in *" $2 "*) return 0 ;; esac
            [ "$1" = "$2" ] && return 0
        fi
        return 1
    }

    # tr gets the escape directly. Written as nl="$(printf '\n')" the variable
    # is EMPTY - command substitution strips the trailing newline, which is the
    # only character there - so tr refused the whole translation and every field
    # arrived as one line. The sieve then let a full path, an e-mail address and
    # a MAC straight through, which is worse than the defect being fixed.
    while IFS= read -r campo; do
        n=$((n + 1))
        [ "$n" = 1 ] && continue        # the fingerprint: hex, and not a secret
        # Fields 9-11 are the stack versions and the dedup token: not free
        # text, generated here, and each constrained to its own charset by
        # t_versao_limpa and t_dedup_token. They are skipped for a specific
        # reason rather than for convenience - a Wine version with four numeric
        # components ("9.0.0.1") is indistinguishable from an IPv4 address to
        # the regex below, so leaving them in would park every honest record
        # from such a machine for ever. This sieve exists to guard FREE TEXT;
        # a machine-generated field with a fixed shape gets a shape check
        # instead, at the point it is built and again at the intake.
        [ "$n" -ge 9 ] && continue
        [ -n "$campo" ] || continue
        case "$campo" in
            # Anything with a path separator, a drive letter or a URL in it.
            # "*/*" already covers a URL, so there is no *://* here.
            */*|*'\'*|[A-Za-z]:*) return 0 ;;
        esac
        case "$campo" in
            *@*) return 0 ;;            # an address of any kind
        esac
        # A file name, which docs/LIST-FORMAT.md promises the record cannot
        # carry and which the old version let straight through: a note reading
        # "PDVSuperMax-4.2-setup.exe" names the shop's software in the clear.
        case "${campo,,}" in
            *.exe|*.exe\ *|*.msi|*.msi\ *|*.apk|*.jar|*.deb|*.rpm|*.appimage|\
            *.snap|*.sh|*.run|*.bat|*.lnk|*.zip|*.rar|*.log|*.txt) return 0 ;;
        esac
        _t_acha_nome "$campo" "$usuario" && { unset -f _t_acha_nome; return 0; }
        _t_acha_nome "$campo" "$maquina" && { unset -f _t_acha_nome; return 0; }
        [ -n "$HOME" ] && case "$campo" in *"$HOME"*) return 0 ;; esac
        # An IPv4 address, and a MAC, which the old version never looked for.
        printf '%s' "$campo" |
            grep -qE '(^|[^0-9])[0-9]{1,3}(\.[0-9]{1,3}){3}([^0-9]|$)' && return 0
        printf '%s' "$campo" |
            grep -qiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' && return 0
    done <<FIM
$(printf '%s' "$reg" | tr '\t' '\n')
FIM
    unset -f _t_acha_nome
    return 1
}

# ------------------------------------------------------------ the stack
#
# WineHQ's AppDB has one hard rule this project had not adopted: a test report
# is worthless unless you know exactly what produced it. Two shops can run the
# same program, need different verbs, and both be right - because one is on
# Wine 8 and the other on Wine 10. Merging those two reports produces an answer
# that was never true anywhere.
#
# Constrained to a version charset and capped, because these two fields are the
# reason t_lista_vaza has to skip them: see the note there.
# The version, and ONLY the version.
#
# The first version of this stripped everything that was not a version
# character and glued the rest together, so `wine --version`'s real output -
# "wine-9.0 (Ubuntu 9.0~repack-4build3)" - became "9.0Ubuntu9.0repack-4buil",
# truncated mid-word at 24 characters. Found by installing the built package and
# reading the field, which is the only method that has ever caught anything in
# this project.
#
# It matters beyond ugliness: the same Wine 9.0 packaged by Ubuntu, by Debian
# and built from source would have produced three DIFFERENT stack strings, and
# tools/monta-lista.py groups by the stack - so the list would have fragmented
# into three rows of one report each instead of one row of three, which is the
# exact opposite of what the stack field was added to do.
#
# So: take the FIRST whitespace-delimited token, which is where every tool of
# this kind puts the version, and only then constrain the charset.
t_versao_limpa() {
    local v="${1:-}"
    v="$(printf '%s' "$v" | awk '{print $1}' | tr -cd 'A-Za-z0-9._-' | cut -c1-24)"
    [ -n "$v" ] || v="-"
    printf '%s' "$v"
}

t_stack_wine() {
    local v
    v="$(wine --version 2>/dev/null | head -1 | sed 's/^wine-//')" || v=""
    t_versao_limpa "$v"
}

t_stack_winetricks() {
    local v
    v="$(winetricks --version 2>/dev/null | head -1 | awk '{print $1}')" || v=""
    t_versao_limpa "$v"
}

# Post-install breakage: did the Wine under a program change since it last opened
# cleanly? True ONLY when there is a recorded version, the current one is real
# (not the "-" t_stack_wine returns with no Wine), and the two differ - so it
# never fires on a first run, an unchanged system, or a machine with no Wine,
# and it never blames an update on a guess. Pure, so the decision has a test.
t_wine_mudou_desde() {
    local antes="${1:-}" agora="${2:-}"
    [ -n "$antes" ] || return 1
    [ -n "$agora" ] && [ "$agora" != "-" ] || return 1
    [ "$antes" != "$agora" ] || return 1
    return 0
}

# Is Wine held at its current version by apt, so an ordinary update cannot move
# it? Machine-only (apt-mark), like the Wine read itself; the decision that uses
# this is the pure function below. Returns 0 when wine is on the hold list.
t_wine_fixado() {
    command -v apt-mark >/dev/null 2>&1 || return 1
    apt-mark showhold 2>/dev/null | grep -qxF wine
}

# Should Tandem OFFER to pin Wine? Pinning protects a program that works under a
# known Wine from a distro upgrade swapping it - the 4.28 failure - but it also
# holds back Wine's own security updates, so it is never suggested without a
# reason and NEVER done automatically. The reason is a recorded working Wine;
# without one there is nothing to protect and no advice to give. Pure, so the
# decision is a truth table, not an accident of when the probe ran.
#   ja-fixado      Wine is already held           -> nothing to offer
#   sem-wine       no Wine on the system now       -> nothing to pin
#   sem-referencia no recorded working Wine        -> no cause to advise
#   pode-fixar     a recorded working Wine, a real current one, not held
#                  -> the command is worth offering, for the owner to run
# $1 recorded working Wine (VERSAO_WINE), $2 current Wine (t_stack_wine; "-" when
# none), $3 "sim" when Wine is held.
t_wine_pin_veredito() {
    local antes="${1:-}" agora="${2:-}" fixado="${3:-}"
    [ "$fixado" = sim ] && { printf 'ja-fixado'; return; }
    [ -n "$agora" ] && [ "$agora" != "-" ] || { printf 'sem-wine'; return; }
    [ -n "$antes" ] || { printf 'sem-referencia'; return; }
    printf 'pode-fixar'
}

# ------------------------------------------------- counting without keeping
#
# The list counts REPORTS, not machines, because counting machines honestly is
# impossible without keeping something that identifies the sender - and "we
# only store a hash" does not survive contact with a laptop. This is the narrow
# exception, and the shape of it is the whole argument:
#
#   token = HMAC-SHA256(secret that never leaves this machine, file identity)
#
# The receiving end can tell that two records about THE SAME PROGRAM came from
# the same machine, which is all deduplication needs. It cannot tell that two
# records about DIFFERENT programs came from the same machine, because without
# the secret the two tokens are unrelated values - so it is not a machine
# identifier and cannot become one by accumulation. That is strictly less than
# the per-machine pseudonym the prior-art sweep suggested, and it buys the same
# thing.
#
# The secret is 32 random bytes, mode 600, generated once, and never sent.
t_dedup_segredo() {
    local arq="$TANDEM_ESTADO/.envio-segredo"
    [ -n "${TANDEM_ESTADO:-}" ] || return 1
    if [ ! -s "$arq" ]; then
        mkdir -p "$TANDEM_ESTADO" 2>/dev/null || return 1
        ( umask 077
          head -c 32 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' > "$arq"
        ) || return 1
        chmod 600 "$arq" 2>/dev/null
    fi
    [ -s "$arq" ] || return 1
    cat "$arq"
}

t_dedup_token() {
    local ident="${1:-}" seg
    [ -n "$ident" ] || return 1
    seg="$(t_dedup_segredo 2>/dev/null)" || return 1
    [ -n "$seg" ] || return 1
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$ident" |
            openssl dgst -sha256 -hmac "$seg" 2>/dev/null |
            sed 's/.*= *//' | cut -c1-16
    else
        # No openssl: still one-way and still unlinkable across programs. The
        # secret goes on BOTH sides of the identity so that knowing one record
        # does not let a length-extension attack forge the next.
        printf '%s%s%s' "$seg" "$ident" "$seg" | sha256sum | cut -c1-16
    fi
}

# Assembles the standardized record for this program. Empty = there is nothing
# to contribute.
t_lista_registro() {
    local prog="$1" id arch verbos reprovados conf reg
    id="$(t_memoria_id "$prog" 2>/dev/null)" || return 1
    [ -n "$id" ] || return 1
    arch="$(t_memoria_le "$prog" ARQUITETURA 2>/dev/null)"
    verbos="$(t_memoria_le "$prog" RESOLVERAM 2>/dev/null | tr ' ' ',')"
    reprovados="$(t_memoria_le "$prog" NAO_RESOLVERAM 2>/dev/null | tr ' ' ',')"
    conf="$(t_confianca_da_licao "$prog")"
    # With no lesson at all, contributing would be just noise in other
    # people's list.
    [ -n "$verbos" ] || [ -n "$reprovados" ] || [ "$conf" = reprovado ] || return 1
    # Fields 9-11 are APPENDED, and the header still says TANDEM-LISTA 1 on
    # purpose. Every reader of this format indexes by column, so adding columns
    # at the end is compatible by construction: a 4.6 client in the field reads
    # fields 1-8 and ignores the rest, which is exactly its old behaviour.
    # Bumping the version instead would make those clients REJECT the whole
    # file and lose the list entirely, to gain nothing. The rule to keep is
    # therefore: append only, never reorder, never repurpose a column.
    # Field 12, appended under the same rule as 9-11: WHERE this lesson came
    # from. "proprio" is a shop that worked it out for itself; "aplicado" is a
    # shop that applied somebody else's and found it worked. They are different
    # evidence and the far end must never add them together, or four hundred
    # machines applying one suggestion read as eight hundred discovering it -
    # the list confirming itself out of its own output.
    local origem
    origem="$(t_memoria_le "$prog" ORIGEM_LICAO 2>/dev/null)"
    case "$origem" in aplicado) ;; *) origem=proprio ;; esac
    reg="$(printf '%s\t%s\t%s\t%s\t%s\t1\t%s\t-\t%s\t%s\t%s\t%s' \
        "$id" "${arch:--}" "${verbos:--}" "${reprovados:--}" "$conf" "$(date +%Y-%m)" \
        "$(t_stack_wine)" "$(t_stack_winetricks)" \
        "$(t_dedup_token "$id" 2>/dev/null || printf '-')" "$origem")"
    # A date with a DAY identifies; year and month do not. And the slash of a
    # path that slipped in by mistake takes the whole record down instead of
    # leaking.
    t_lista_vaza "$reg" && { t_diz "registro recusado: continha dado da maquina"; return 1; }
    printf '%s\n' "$reg"
}

# Resolves every row the list holds about ONE file into a single answer, and
# prints it as "verbs<TAB>machines". Both the query and the machine count read
# from here, and that is the point of the function existing.
#
# It is written this way because of three losses the first version had, all of
# them silent:
#
#  - it printed the FIRST confirmed row and exited, so whoever got into the
#    file earliest owned that program for ever. A later row reporting a better
#    lesson from more machines was dead text nobody would ever read;
#  - it never ADDED UP two rows carrying the same verbs. Merging reports is the
#    whole job of the machine count, and two rows saying "vcrun2022, 200
#    machines" answered 200, not 400;
#  - t_lista_maquinas did not filter by confidence at all, so on a file with a
#    rejected row above a confirmed one it answered with the count of a row the
#    verbs had NOT come from. The number the owner is shown to decide with
#    described a different lesson than the one being offered.
#
# The winner is the verb set the most machines CONFIRM, and a set is dropped
# when at least as many machines reported it rejected - a minority lesson does
# not get spread just because the majority happens to be bad news. Ties break
# on the most recent report, then on the fewest verbs (less to install for the
# same claimed result), then alphabetically, so the answer never depends on the
# order of the rows in the file.
# Since 4.9 it also weighs the STACK and the AGE of each report:
#
#  - a report produced on a different major version of Wine describes a
#    different machine, and merging it produces an answer that was never true
#    anywhere. It is not discarded - it is worth less. A row with no stack
#    recorded (every row written before 4.9) sits between the two, because
#    "unknown" is not the same as "wrong".
#  - a report decays with age: a lesson from a Wine three years gone is weaker
#    evidence about today's Wine than one from last month.
#
# THE DECAY IS DELIBERATELY MILD, and that is the load-bearing decision. Its
# floor is a quarter, so no amount of age lets ONE fresh report overturn a set
# four hundred machines confirmed. That is the "downgrade, do not overwrite"
# rule falling out of the arithmetic instead of being a rule of its own: a
# sudden verb-set flip on an established fingerprint loses on weight, and only
# starts winning once enough machines actually report it.
t_lista_linha() {
    local id="$1" wine_agora mes_agora
    [ -f "$TANDEM_LISTA" ] || return 1
    [ -n "$id" ] || return 1
    # The MAJOR version is what matters: 10.0 and 10.4 are the same generation,
    # 8.x and 10.x are not. awk knows no clock, so today goes in as a variable.
    wine_agora="$(t_stack_wine 2>/dev/null | cut -d. -f1)"
    mes_agora="$(date +%Y-%m)"
    awk -F'\t' -v alvo="$id" -v wine_agora="$wine_agora" -v mes_agora="$mes_agora" '
        function meses(a, b,   pa, pb) {
            if (a == "" || b == "") return 0
            split(a, pa, "-"); split(b, pb, "-")
            return (pb[1] - pa[1]) * 12 + (pb[2] - pa[2])
        }
        # A DATE IN THE FUTURE IS NOT FRESHNESS. The tie-break below is "the
        # most recently seen wins", so a row dated 2099-12 wins every tie for
        # ever - measured: ten reports this month lost to ten reports dated
        # 2099. It does not take an attacker, only a shop with a wrong clock,
        # and this project already detects wrong clocks from the certificate
        # errors Wine itself prints, because they happen.
        #
        # No apostrophe in this block: the whole awk program is inside single
        # quotes, and one in a COMMENT closes the string just as well as one in
        # code. It did, on the first attempt.
        #
        # api/lista.js REFUSES such a record on the way in, with a comment
        # saying exactly this. That guard covers half the problem: this file is
        # DOWNLOADED, and a reader that trusts it because the writer checked is
        # a reader with no check. Clamped to now, so a future row is worth
        # exactly as much as a row from this month and no more.
        function visto_ok(d) { return (d > mes_agora) ? mes_agora : d }
        # How much one report is worth: its stack against ours, and its age.
        function peso(w, visto,   p, m, pw) {
            p = 1
            if (wine_agora == "" || w == "" || w == "-") {
                p = 0.75           # unknown stack is not the same as wrong
            } else {
                split(w, pw, ".")
                if (pw[1] != wine_agora) p = 0.5
            }
            m = meses(visto, mes_agora)
            if (m > 12) p = p * 0.75
            if (m > 24) p = p * 0.66
            if (m > 48) p = p * 0.5
            return (p < 0.25) ? 0.25 : p
        }
        function ganha(v, c, s, n) {
            if (!achou) return 1
            if (c != bc) return (c > bc)
            if (s != bvisto) return (s > bvisto)
            if (n != bn) return (n < bn)
            return (v < bv)
        }
        /^#/ { next }
        $1 != alvo || $3 == "-" || $3 == "" { next }
        {
            # An unmerged record carries no count of its own: it is one
            # machine, which is exactly what it is worth.
            m = ($6 ~ /^[0-9]+$/) ? $6 + 0 : 1
            # Field 9 is the Wine version, absent on every row written before
            # 4.9 - which is why "absent" has a weight of its own.
            w = (NF >= 9) ? $9 : "-"
            # Field 12 is the ORIGIN, and a corroboration never SELECTS a
            # lesson. A shop that applied a suggestion from this very list and found
            # it worked is real evidence, and it is evidence downstream of the
            # list itself - letting it feed the count that chooses the answer
            # would be the list confirming itself out of its own output. It is
            # counted separately, by t_lista_corroboracoes, and shown as its
            # own number.
            if (NF >= 12 && $12 == "aplicado") next
            if ($5 == "confirmado") {
                conf[$3] += m * peso(w, visto_ok($7))
                bruto[$3] += m
                if (visto_ok($7) > visto[$3]) visto[$3] = visto_ok($7)
            } else if ($5 == "entregue") {
                # Half a report. Tandem verified the missing file arrived, in
                # the right bitness, and the owner never said whether the
                # PROGRAM works - so it is real evidence about the file and only
                # a hint about the question the list answers. Before 4.11 a run
                # like this contributed NOTHING: it was recorded as "so-abriu"
                # and the resolver ignores those entirely.
                conf[$3] += m * peso(w, visto_ok($7)) * 0.5
                bruto[$3] += m
                if (visto_ok($7) > visto[$3]) visto[$3] = visto_ok($7)
            } else if ($5 == "reprovado") {
                rep[$3] += m * peso(w, visto_ok($7))
            }
        }
        END {
            for (v in conf) {
                if (conf[v] <= rep[v]) continue
                n = split(v, _partes, ",")
                if (ganha(v, conf[v], visto[v], n)) {
                    achou = 1; bc = conf[v]; bvisto = visto[v]
                    bn = n; bv = v; bbruto = bruto[v]
                }
            }
            # The number SHOWN is the honest count of reports, not the internal
            # weight. Telling the owner "3.7 reports" would be a number nobody
            # can check against the file he can download and read.
            if (achou) printf "%s\t%d\n", bv, bbruto
            exit !achou
        }' "$TANDEM_LISTA"
}

# What other people installed on THIS file and found useless, as
# "verb<TAB>reports" lines, worst first.
#
# The list has carried this since 3.4 and nothing ever read it: t_lista_linha's
# awk touches fields 1, 3, 5, 6 and 7, and field 4 - the components that were
# installed and did NOT fix it - was written by every client, accepted by the
# intake, published by the rebuild, downloaded to every machine, and opened by
# nobody. So a shop could be about to spend half an hour on dotnet48 that sixty
# other shops had already burned on this exact installer without it helping,
# with that fact sitting on the disk.
#
# It NEVER blocks and never subtracts from a suggestion: a verb can fail on one
# machine and be exactly right on the next, which is why this returns a count
# and a sentence rather than a veto. The weighting is the resolver's, so an old
# report from a different Wine counts for less here too.
t_lista_inuteis() {
    local id="$1"
    [ -f "$TANDEM_LISTA" ] || return 1
    [ -n "$id" ] || return 1
    local wine_agora mes_agora
    wine_agora="$(t_stack_wine 2>/dev/null | cut -d. -f1)"
    mes_agora="$(date +%Y-%m)"
    awk -F'\t' -v alvo="$id" -v wine_agora="$wine_agora" -v mes_agora="$mes_agora" '
        function meses(a, b,   pa, pb) {
            if (a == "" || b == "") return 0
            split(a, pa, "-"); split(b, pb, "-")
            return (pb[1] - pa[1]) * 12 + (pb[2] - pa[2])
        }
        # A DATE IN THE FUTURE IS NOT FRESHNESS. The tie-break below is "the
        # most recently seen wins", so a row dated 2099-12 wins every tie for
        # ever - measured: ten reports this month lost to ten reports dated
        # 2099. It does not take an attacker, only a shop with a wrong clock,
        # and this project already detects wrong clocks from the certificate
        # errors Wine itself prints, because they happen.
        #
        # No apostrophe in this block: the whole awk program is inside single
        # quotes, and one in a COMMENT closes the string just as well as one in
        # code. It did, on the first attempt.
        #
        # api/lista.js REFUSES such a record on the way in, with a comment
        # saying exactly this. That guard covers half the problem: this file is
        # DOWNLOADED, and a reader that trusts it because the writer checked is
        # a reader with no check. Clamped to now, so a future row is worth
        # exactly as much as a row from this month and no more.
        function visto_ok(d) { return (d > mes_agora) ? mes_agora : d }
        function peso(w, visto,   p, m, pw) {
            p = 1
            if (wine_agora == "" || w == "" || w == "-") { p = 0.75 }
            else { split(w, pw, "."); if (pw[1] != wine_agora) p = 0.5 }
            m = meses(visto, mes_agora)
            if (m > 12) p = p * 0.75
            if (m > 24) p = p * 0.66
            if (m > 48) p = p * 0.5
            return (p < 0.25) ? 0.25 : p
        }
        /^#/ { next }
        $1 != alvo || $4 == "-" || $4 == "" { next }
        {
            m = ($6 ~ /^[0-9]+$/) ? $6 + 0 : 1
            w = (NF >= 9) ? $9 : "-"
            n = split($4, vs, ",")
            for (i = 1; i <= n; i++) {
                if (vs[i] == "") continue
                # The honest count of REPORTS is what gets shown, exactly as in
                # t_lista_linha - telling somebody "3.7 shops" is a number he
                # cannot check against the file he can download and read.
                bruto[vs[i]] += m
                peso_de[vs[i]] += m * peso(w, visto_ok($7))
            }
        }
        END {
            for (v in bruto) printf "%s\t%d\t%.3f\n", v, bruto[v], peso_de[v]
        }' "$TANDEM_LISTA" 2>/dev/null |
    sort -t"$(printf '\t')" -k3,3gr | cut -f1,2
}

# Has ANYBODY got this program working? A row whose verbs field is "-" is a
# machine saying "I tried and nothing I installed helped" - the record the
# intake goes out of its way to accept and the resolver drops on its first
# line, because it is looking for a lesson and this is the absence of one.
#
# Returns 0 and prints the report count when that is the ONLY thing the list
# knows about this file. Deliberately not when there is also a working lesson:
# one shop failing where four hundred succeeded is a fact about that shop.
t_lista_ninguem_conseguiu() {
    local id="$1" nada
    [ -f "$TANDEM_LISTA" ] || return 1
    [ -n "$id" ] || return 1
    t_lista_linha "$id" >/dev/null 2>&1 && return 1
    nada="$(awk -F'\t' -v alvo="$id" '
        /^#/ { next }
        $1 != alvo { next }
        ($3 == "-" || $3 == "") { n += ($6 ~ /^[0-9]+$/) ? $6 + 0 : 1 }
        END { print n + 0 }' "$TANDEM_LISTA" 2>/dev/null)"
    [ "${nada:-0}" -gt 0 ] || return 1
    printf '%s' "$nada"
}

# How many reports say "I applied this lesson and it worked", for a given verb
# set. Kept apart from the count that chooses the lesson on purpose - see the
# note in t_lista_linha. This is the number that answers "has anybody else
# actually got this to work using it?", which is a different and useful
# question from "how many shops discovered it".
t_lista_corroboracoes() {
    local id="$1" verbos="$2"
    [ -f "$TANDEM_LISTA" ] || return 1
    [ -n "$id" ] && [ -n "$verbos" ] || return 1
    awk -F'\t' -v alvo="$id" -v vs="$verbos" '
        /^#/ { next }
        $1 != alvo { next }
        NF < 12 || $12 != "aplicado" { next }
        $3 != vs { next }
        $5 == "confirmado" || $5 == "entregue" { n += ($6 ~ /^[0-9]+$/) ? $6 + 0 : 1 }
        END { if (n > 0) print n + 0 }' "$TANDEM_LISTA" 2>/dev/null
}

# Reads the downloaded list and returns the known verbs for this program.
# It only answers when the lesson comes confirmed by people: that is the
# difference between spreading knowledge and spreading error with the same
# efficiency.
# FOUR different silences, and until now they were one. "there is no list on
# this machine", "the list is here and has never heard of this program" and
# "it has heard of it and nobody confirmed the lesson" are three different
# facts about a shop, and answering 1 to all of them means whoever is helping
# cannot tell a machine that never downloaded the file from a program the
# world genuinely knows nothing about.
#
#   0  the verbs are on stdout
#   1  this file could not be fingerprinted at all
#   2  no list has been downloaded here
#   3  the list is here and does not know this program
#   4  it knows it, and no lesson in it is worth passing on
#
# The caller writes one log line per case; nothing new reaches the owner's
# screen, because on this path there is nothing for him to do about any of
# them - the run carries on into the normal detector loop either way.
t_lista_consulta() {
    local prog="$1" id linha
    id="$(t_memoria_id "$prog" 2>/dev/null)" || return 1
    [ -n "$id" ] || return 1
    [ -f "${TANDEM_LISTA:-}" ] || return 2
    # Exact field match rather than grep: the identity is field 1, and a
    # substring hit anywhere else in the row would answer "known" about the
    # wrong program.
    awk -F'\t' -v alvo="$id" '$1 == alvo { achou = 1 } END { exit !achou }' \
        "$TANDEM_LISTA" 2>/dev/null || return 3
    linha="$(t_lista_linha "$id")" || return 4
    printf '%s\n' "$linha" | cut -f1 | tr ',' ' '
}

# The same four, as a log line. Kept beside the codes so a new one cannot be
# added without a sentence - the shape this project keeps finding is a rich
# verdict whose caller keeps a boolean.
t_lista_porque_calou() {
    case "${1:-}" in
        2) printf 'lista: nenhuma copia baixada nesta maquina' ;;
        3) printf 'lista: baixada, e nao conhece este programa' ;;
        4) printf 'lista: conhece este programa, mas nenhuma licao confirmada' ;;
        1) printf 'lista: nao consegui identificar este arquivo' ;;
        *) printf 'lista: sem resposta (%s)' "${1:-?}" ;;
    esac
}

# How many machines agree with the lesson t_lista_consulta just gave - the
# same lesson, by construction, because both come out of t_lista_linha. It is
# a SUM over the rows carrying those verbs, so it may be larger than any
# single row in the file.
t_lista_maquinas() {
    local linha
    linha="$(t_lista_linha "$1")" || return 1
    printf '%s\n' "$linha" | cut -f2
}

# Is the downloaded list signed by the key this package trusts?
#
# Returns 0 for "fine" in three different situations, and they are not the same
# thing - the log says which, because "the list is unsigned" and "I cannot
# check signatures here" are different facts about a machine:
#   - there is no signature published yet (the rollout is not finished);
#   - this machine has no openssl, so nothing can be checked;
#   - the signature is present and good.
# It returns 1 only for a signature that is present and WRONG, which is the one
# case that means somebody changed the file after it was published.
t_lista_assinatura_ok() {
    local arq="$1" chave sig tmpsig
    chave="${TANDEM_LISTA_CHAVE:-${TANDEM_LIB:-/usr/lib/tandem}/lista-publica.pem}"
    [ -f "$chave" ] || { t_diz "lista: sem chave publica instalada; nao confiro"; return 0; }
    command -v openssl >/dev/null 2>&1 || {
        t_diz "lista: sem openssl nesta maquina; nao confiro a assinatura"; return 0; }
    tmpsig="$(mktemp)" || return 0
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 -o "$tmpsig" "$TANDEM_LISTA_URL.sig" 2>/dev/null
    else
        wget -q -T 30 -O "$tmpsig" "$TANDEM_LISTA_URL.sig" 2>/dev/null
    fi
    if [ ! -s "$tmpsig" ]; then
        rm -f "$tmpsig"
        t_diz "lista: nenhuma assinatura publicada ainda"
        return 0
    fi
    # base64 on the wire so the file survives being served as text.
    sig="$(mktemp)" || { rm -f "$tmpsig"; return 0; }
    base64 -d < "$tmpsig" > "$sig" 2>/dev/null || cp "$tmpsig" "$sig"
    if openssl pkeyutl -verify -pubin -inkey "$chave" -rawin -in "$arq" \
            -sigfile "$sig" >/dev/null 2>&1; then
        t_diz "lista: assinatura confere"
        rm -f "$tmpsig" "$sig"; return 0
    fi
    rm -f "$tmpsig" "$sig"
    return 1
}

# Downloads the list. A malformed file does NOT replace the good one already
# on disk: a broken list would silence the second opinion with nobody
# noticing.
# Is this machine allowed to RECEIVE the list? Default yes, and the default is
# the whole point of this function existing.
#
# Until 4.11 t_lista_atualiza had exactly ONE caller in the entire tree -
# `tandem lista atualizar`, typed by hand - so on a machine whose owner has
# never heard of that command the list file never existed, t_lista_consulta
# always returned nothing, and every merge rule 4.4, 4.9 and 4.11 added was
# unreachable code. Meanwhile SENDING is on by default. A machine that gives
# and does not take is the wrong way round.
#
# This reverses "Automatic sync on install - REJECTED" in docs/IDEAS.md, and
# the new argument is narrow: 4.2 already reversed that stance for the
# direction that actually carries data OUT. Receiving carries nothing out. What
# it costs is an HTTP GET, and what it buys is the half of the list that helps
# the shop rather than the project.
#
# The switch is named, so somebody can find and turn it off, and it is asked
# with the same shape as ENVIAR.
t_lista_receber_ligado() {
    case "$(t_config_le RECEBER 2>/dev/null)" in
        nao|não|no) return 1 ;;
        *) return 0 ;;
    esac
}

# Fetches the list if it is allowed and has not been fetched today, DETACHED.
#
# Detached, never blocking, and that is a deliberate trade rather than a
# convenience: the alternative is a double click waiting on a network round
# trip, and on a machine with no route to the address that is a stall on every
# unknown program. The cost of detaching is that the list helps from the NEXT
# run rather than this one - which is a real limitation and is still infinitely
# better than the current behaviour, where it helps on no run ever.
#
# Once a day, by the same stamp mechanism the send path uses. A shop machine
# that opens the same program forty times in a morning makes one request.
# ============================================ is there a newer Tandem?
#
# THE DECISION BEHIND THIS, because the shape of it is the whole point:
# Tandem does NOT update itself, and will not. Fetching the community list is
# data that only ever becomes a suggestion; a .deb is code that runs as root.
# The moment Tandem can replace its own binary from the internet, whoever
# controls the release address owns every shop machine at once - and the
# machine this was born on runs a point-of-sale system. That is rule №1 turned
# on Tandem itself.
#
# So this only ever LOOKS. It reads the version number of the newest published
# release and says so; installing stays a thing a person does, with a command
# he can read, on a package he can check the checksum of.
#
# The proper destination is an apt repository, where the update arrives through
# the same updater the owner already trusts and already gets asked about. That
# needs a signing key, which is a secret only he can make - so it waits for
# him, and this exists in the meantime rather than instead.
TANDEM_VERSAO_URL="${TANDEM_VERSAO_URL:-https://api.github.com/repos/ChrnX0/Tandem/releases/latest}"

t_versao_avisar_ligado() {
    case "$(t_config_le AVISAR_VERSAO 2>/dev/null)" in
        nao|não|no) return 1 ;;
        *) return 0 ;;
    esac
}

# Is A strictly newer than B? dpkg knows the rules for Debian version strings
# and this package is a .deb, so ask it rather than inventing a comparison.
# sort -V is the fallback, and "equal" must answer NO in both.
t_versao_mais_nova() {
    local nova="$1" atual="$2" topo
    [ -n "$nova" ] && [ -n "$atual" ] || return 1
    [ "$nova" = "$atual" ] && return 1
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --compare-versions "$nova" gt "$atual" && return 0
        return 1
    fi
    topo="$(printf '%s\n%s\n' "$nova" "$atual" | sort -V | tail -1)"
    [ "$topo" = "$nova" ]
}

# Reads the newest published version and remembers it. Runs in the BACKGROUND,
# so nothing here ever delays a command - the answer is used on the next run,
# exactly like the community list, and for the same reason.
t_versao_busca() {
    local corpo nova
    [ -n "$TANDEM_VERSAO_URL" ] || return 1
    if command -v curl >/dev/null 2>&1; then
        corpo="$(curl -fsSL --max-time 20 "$TANDEM_VERSAO_URL" 2>/dev/null)" || return 1
    elif command -v wget >/dev/null 2>&1; then
        corpo="$(wget -q -T 20 -O - "$TANDEM_VERSAO_URL" 2>/dev/null)" || return 1
    else
        return 1
    fi
    # One field out of the JSON, without a JSON parser and without eval: the
    # answer is somebody else's document, so it goes through t_versao_limpa
    # before it is stored or ever shown.
    nova="$(printf '%s' "$corpo" |
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' |
            head -1)"
    nova="$(t_versao_limpa "$nova")"
    [ "$nova" = "-" ] && return 1
    t_config_grava VERSAO_DISPONIVEL "$nova"
    t_diz "versao publicada mais recente: $nova (esta: $TANDEM_VERSAO)"
    return 0
}

t_versao_talvez_verifica() {
    local hoje
    t_versao_avisar_ligado || return 1
    [ -n "$TANDEM_ESTADO" ] || return 1
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 1
    hoje="$(date +%F)"
    [ "$(t_config_le VERSAO_DIA 2>/dev/null)" = "$hoje" ] && return 1
    # Stamped before the attempt, like the list: a machine with no route makes
    # one failed request a day, not one per command.
    t_config_grava VERSAO_DIA "$hoje"
    ( t_versao_busca >/dev/null 2>&1 & ) 2>/dev/null
    return 0
}

# The version to tell him about, or nothing. Reads only what a previous run
# stored, so it costs no network and cannot delay anything.
t_versao_nova_conhecida() {
    local nova
    # The switch is checked HERE and not only where the fetch happens, and that
    # is a defect found by running it: gating only the fetch left the value a
    # previous run had already stored, so "tandem versao nao-avisar" stopped
    # the network call and went on printing the notice for ever. An off switch
    # has to turn off the thing the owner can SEE, not the thing he cannot.
    t_versao_avisar_ligado || return 1
    nova="$(t_config_le VERSAO_DISPONIVEL 2>/dev/null)" || return 1
    t_versao_mais_nova "$nova" "$TANDEM_VERSAO" || return 1
    printf '%s' "$nova"
}

t_lista_talvez_atualiza() {
    local hoje
    t_lista_receber_ligado || { t_diz "lista: receber esta desligado"; return 1; }
    [ -n "$TANDEM_ESTADO" ] || return 1
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 1
    hoje="$(date +%F)"
    [ "$(t_config_le LISTA_DIA 2>/dev/null)" = "$hoje" ] && return 1
    # Stamped BEFORE the attempt, not after. A machine with no internet must
    # make one failed request a day, not one per double click - the same lesson
    # the send path learned when a cap that only counted successes turned out
    # not to be a cap at all.
    t_config_grava LISTA_DIA "$hoje"
    t_diz "lista: buscando a lista da comunidade em segundo plano"
    ( t_lista_atualiza >/dev/null 2>&1 & ) 2>/dev/null
    return 0
}

t_lista_atualiza() {
    local tmp rc
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 2
    [ -n "$TANDEM_ESTADO" ] || return 2
    tmp="$(mktemp)" || return 2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 -o "$tmp" "$TANDEM_LISTA_URL" 2>>"${LOG:-/dev/null}"
        rc=$?
        # 22 = the server answered with an error (404 is the common case: the
        # list has not been published yet). Sending the owner to check the
        # internet because of that is sending them to look for a defect in a
        # perfect machine.
        [ $rc -eq 22 ] && { rm -f "$tmp"; return 4; }
    else
        wget -q -T 30 -O "$tmp" "$TANDEM_LISTA_URL" 2>>"${LOG:-/dev/null}"
        rc=$?
        [ $rc -eq 8 ] && { rm -f "$tmp"; return 4; }
    fi
    if [ $rc -ne 0 ] || [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi
    if ! head -1 "$tmp" | grep -q "^# TANDEM-LISTA $TANDEM_LISTA_VERSAO\$"; then
        t_diz "lista baixada nao declara o formato esperado; descartada"
        rm -f "$tmp"; return 3
    fi
    # The signature, when there is one.
    #
    # HTTPS proves we talked to GitHub; it does not prove the bytes are what
    # was published. A bad row in this file is not a bad row on one machine -
    # it is a verb name that every Tandem on earth downloads and may be asked
    # to install, which is why the verb-safety gate and the pull-request
    # requirement exist. This is the third layer.
    #
    # ROLLED OUT IN THE ONLY ORDER THAT IS SAFE: a signature that is PRESENT
    # and WRONG rejects the file; a signature that is absent does not, yet.
    # Requiring it from day one would mean any hiccup in the signing step
    # silently cuts every machine off from the list, and the list going quiet
    # is indistinguishable from the list having nothing to say. When signed
    # lists have been published for a while, this becomes mandatory - the note
    # in docs/LIST-FORMAT.md carries the date to flip it.
    if ! t_lista_assinatura_ok "$tmp"; then
        t_diz "lista baixada tem assinatura invalida; descartada"
        rm -f "$tmp"; return 5
    fi
    mv -f "$tmp" "$TANDEM_LISTA" || { rm -f "$tmp"; return 2; }
    t_diz "lista atualizada: $(grep -vc '^#' "$TANDEM_LISTA") programas"
    return 0
}

# ================================================== SILENT SUCCESS
#
# See the long comment in tandem-exe. Here is the mechanism: ask once per
# program, store the answer, and - most importantly - never let "exited 0"
# pass for "it worked" when the time comes to export the lesson.

# A quick exit with nothing on the screen deserves suspicion. An installer
# takes time; a real program stays open while the person uses it. Closing by
# itself in a few seconds is the portrait of the executable that died quiet.
TANDEM_SEGUNDOS_SUSPEITO="${TANDEM_SEGUNDOS_SUSPEITO:-3}"

t_saida_suspeita() {
    [ "${1:-0}" -lt "$TANDEM_SEGUNDOS_SUSPEITO" ] 2>/dev/null
}

# Asks the owner whether it worked, and writes CONFIRMADO=sim|nao into the
# memory. With no window it asks nothing: making up an answer would be worse
# than not having one.
t_confirma_funcionou() {
    local prog="$1" durou="${2:-0}" ja
    ja="$(t_memoria_le "$prog" CONFIRMADO 2>/dev/null)"
    [ -n "$ja" ] && return 0

    if t_saida_suspeita "$durou"; then
        # Here there is nothing even to celebrate: the program closed by
        # itself before anybody could use it. Saying "it opened!" would be a
        # lie.
        t_memoria_grava "$prog" RESULTADO "fechou sozinho"
        t_aviso "$(t_msg_n abriu_e_fechou_sozinho "$durou" "$durou")"
    fi

    # Nobody to ask - no window, or no zenity to draw one. That used to be the
    # end of the lesson: with no answer there was no confidence, and with no
    # confidence there was nothing worth passing on. Since 4.11 there is a level
    # underneath his word: Tandem checked, on this machine, that what was
    # missing actually arrived. A lesson carrying that is worth offering even
    # though nobody clicked - and it goes out labelled "entregue", which says
    # exactly that nobody confirmed it, and the resolver weighs it at half a
    # report on the other side.
    #
    # It is offered HERE and not before the branch below, because the "yes"
    # branch offers too and calling both would queue the same lesson twice.
    if ! t_tem_gui || ! command -v zenity >/dev/null 2>&1; then
        [ "$(t_confianca_da_licao "$prog")" = entregue ] &&
            t_envio_oferece "$prog" >/dev/null 2>&1
        return 0
    fi
    if t_pergunta "$(t_msg funcionou_como_esperava)" \
           "$(t_msg botao_sim_funcionou)" "$(t_msg botao_nao_deu_errado)"; then
        t_memoria_grava "$prog" CONFIRMADO sim
        t_diz "o dono confirmou que funcionou"
        # The only moment in the whole program where a lesson is worth anything
        # to anybody else: it worked, and a person said so. Asking about sending
        # here means asking about a line that exists, on a program he just used,
        # instead of asking abstractly at install time about data he cannot see.
        t_envio_oferece "$prog" >/dev/null 2>&1
    else
        t_memoria_grava "$prog" CONFIRMADO nao
        t_diz "o dono disse que NAO funcionou direito"
        t_aviso "$(t_msg anotado_nao_exporto)"
    fi
    return 0
}

# The confidence level of a lesson, in a single word. It is what separates "a
# person looked and said it works" from "the process finished without error".
# How much this lesson is worth, and WHY - which are two different questions
# that were one answer until 4.11.
#
# The owner's word still outranks everything: he looked at the screen and said
# it works, or said it does not. Nothing a file check can do beats that.
#
# What was missing sat underneath. The delivery proof computes three distinct
# outcomes - the file arrived in the right bitness, it arrived in the wrong one,
# it is provably still missing - and NONE of them reached the lesson. So a run
# where Tandem verified the missing file had arrived, and the owner simply closed
# the window without answering, produced the same "so-abriu" as a run where
# there was nothing to verify at all. Those two travel to somebody else's
# machine, in a recipe and in a list record, as the same word.
#
# "entregue" is that middle level: not a human's word, but not a shrug either.
# The list weighs it at half a report, which is the honest arithmetic - it is
# evidence about the FILE, and the question the list answers is about the
# PROGRAM.
t_confianca_da_licao() {
    case "$(t_memoria_le "$1" CONFIRMADO 2>/dev/null)" in
        sim) printf 'confirmado' ;;
        nao) printf 'reprovado' ;;
        *)
            case "$(t_memoria_le "$1" PROVA 2>/dev/null)" in
                entregue) printf 'entregue' ;;
                *)        printf 'so-abriu' ;;
            esac ;;
    esac
}

# What Tandem RECOGNISES about a file the moment it is opened, in one token.
# This is the "is this program known?" signal - a calm line before the run, not
# an antivirus and not a gate: it explains, it never refuses, and every path
# below leads into the same normal open.
#
# It answers from the two things Tandem already keeps, in this order of trust:
#
#   $1 confirmado   the owner's own word on THIS machine (sim/nao/empty). His
#                   "it works" or "it does not" outranks anything a stranger's
#                   list can say, because it is about this exact counter.
#   $2 visto        a date, if this file has opened cleanly here before. Weaker
#                   than a confirmation - "it launched" is not "it works", the
#                   silent-success thesis - but it is still local truth.
#   $3 quantas      how many community reports confirm a way to run it. Second
#                   to local knowledge, because it is about other people's
#                   machines, but it is the one thing no forum has.
#   $4 ninguem      how many community reports say nobody got it working. The
#                   honest negative, and the reason the list keeps that field.
#
# Local always wins over community: a program that opens cleanly HERE is a
# program that works here, whatever a distant shop reported. The tokens are the
# on-disk vocabulary - never translated - and t_msg turns each into a sentence
# at the moment it is shown, the t_resultado_amigavel arrangement.
#
#   confirmado-aqui    reprovado-aqui    aberto-aqui
#   ninguem-conseguiu  comunidade-conhece    novo
#
# "novo" is the COMMON answer today, not the edge: the community list is empty
# for essentially everyone, so most programs are genuinely new here. It is
# worded as reassurance, not as an alarm.
t_procedencia() {
    local confirmado="${1:-}" visto="${2:-}" quantas="${3:-}" ninguem="${4:-}"
    case "$confirmado" in
        sim) printf 'confirmado-aqui'; return 0 ;;
        nao) printf 'reprovado-aqui';  return 0 ;;
    esac
    [ -n "$visto" ] && { printf 'aberto-aqui'; return 0; }
    [ -n "$ninguem" ] && [ "$ninguem" -gt 0 ] 2>/dev/null &&
        { printf 'ninguem-conseguiu'; return 0; }
    [ -n "$quantas" ] && [ "$quantas" -gt 0 ] 2>/dev/null &&
        { printf 'comunidade-conhece'; return 0; }
    printf 'novo'
}

# The recognition token turned into the sentence the owner reads. Two of them
# carry a number ($2) and go through the plural machinery; the rest are plain.
# An unknown token says nothing at all rather than printing a key name - the
# same posture t_erro_do_leitor takes with a token it does not recognise, and
# the reason this returns 1 in that case so the caller stays silent.
t_procedencia_frase() {
    local token="${1:-}" n="${2:-}"
    case "$token" in
        confirmado-aqui)   t_msg procedencia_confirmado ;;
        reprovado-aqui)    t_msg procedencia_reprovado ;;
        aberto-aqui)       t_msg procedencia_aberto "${2:-?}" ;;
        ninguem-conseguiu) t_msg_n procedencia_ninguem "${n:-0}" "${n:-0}" ;;
        comunidade-conhece) t_msg_n procedencia_comunidade "${n:-0}" "${n:-0}" ;;
        novo)              t_msg procedencia_novo ;;
        *) return 1 ;;
    esac
}

# The verdict a whole install run gives on ITS OWN delivery, out of the outcome
# of every DLL it checked. $1 is that list of outcomes, space-separated, in
# whatever order the loop produced them.
#
# Four levels, and their ORDER is the entire content of this function:
#
#   nao-chegou     something is provably still missing. It outranks everything
#                  else because one absent file is enough for the program to go
#                  on failing, however well the other verbs behaved.
#   bitola-errada  everything arrived and at least one arrived in a width this
#                  program cannot use - the dead end with a receipt on top.
#   entregue       at least one file was proven to arrive in the right width,
#                  and nothing was found wrong.
#   sem-alvo       nothing could be checked at all: half the winetricks verbs
#                  have no same-named DLL in the table. This is NOT the same as
#                  "nothing was wrong", and conflating those two is the whole
#                  defect this field exists to fix.
#
# It is a function, and not four lines inline in the install loop, for the
# reason t_causa_do_winetricks was extracted: inline, the only way to reach it
# is to make a real winetricks fail, so an ordering mistake here is invisible
# until it has reached somebody else's machine as a lesson. And an ordering
# mistake here is not hypothetical - the first version of this WAS inline, as a
# plain assignment, which let the LAST DLL of the LAST verb speak for the whole
# run. That is the same shape as the MARCA_WT defect 4.8 fixed one screen up.
t_prova_do_run() {
    local vistas=" ${1:-} " nivel
    for nivel in nao-chegou bitola-errada entregue; do
        case "$vistas" in *" $nivel "*) printf '%s' "$nivel"; return 0 ;; esac
    done
    printf 'sem-alvo'
}

# =============================================================== DATA
#
# The distinction the whole project was missing: the ENVIRONMENT rebuilds
# itself in twenty minutes - the prefix, Wine, the runtimes -, DATA never
# rebuilds. A seven-year customer database, NF-e XML (five years of mandatory
# retention by law), this month's takings. Until now three paths erased that
# with no copy: the rm -rf of the incomplete prefix in tandem-exe, "tandem
# restore" (which gives the environment back and takes the sales with it) and
# the program's own uninstaller.
#
# There is no way to ask the program where it keeps things. There is a way to
# look in two places with judgement: the personal folders of the Windows user,
# and the data files dumped inside the program's own folder - an .mdb or an
# .fdb inside Program Files is somebody's database, not part of the
# installation.

# Extensions that only exist because somebody typed something.
TANDEM_EXT_DADOS='mdb accdb fdb gdb dbf db sqlite sqlite3 db3 sdf
xls xlsx xlsm ods csv doc docx odt rtf txt pdf
bak backup qbw qbb'

# Windows personal folders that are worth carrying along.
TANDEM_PASTAS_DADOS='Documents Desktop Downloads Pictures AppData/Roaming'

t_tamanho_amigavel() {
    local b="${1:-0}"
    if   [ "$b" -ge 1073741824 ] 2>/dev/null; then awk -v b="$b" 'BEGIN{printf "%.1f GB", b/1073741824}'
    elif [ "$b" -ge 1048576 ]    2>/dev/null; then awk -v b="$b" 'BEGIN{printf "%.0f MB", b/1048576}'
    elif [ "$b" -ge 1024 ]       2>/dev/null; then awk -v b="$b" 'BEGIN{printf "%.0f KB", b/1024}'
    else t_msg unidade_bytes "$b"; fi
}

# Lists what counts as data inside a prefix:
# "type<TAB>path-within-drive_c<TAB>bytes".
# The paths are relative to drive_c on purpose: that is how tar manages to
# pack them and put them back in the right place, even on another machine.
t_dados_lista() {
    local pref="${1:-$TANDEM_PREFIXO_PADRAO}" c u sub rel bytes
    c="$pref/drive_c"
    [ -d "$c" ] || return 1

    for u in "$c"/users/*/; do
        [ -d "$u" ] || continue
        case "$(basename -- "${u%/}")" in
            Public|Default|Default\ User|All\ Users) continue ;;
        esac
        for sub in $TANDEM_PASTAS_DADOS; do
            [ -d "$u$sub" ] || continue
            # An existing empty folder is Wine decoration, not the owner's
            # data.
            find "$u$sub" -type f -print -quit 2>/dev/null | grep -q . || continue
            rel="${u#"$c"/}$sub"
            bytes="$(du -sb "$u$sub" 2>/dev/null | cut -f1)"
            printf 'pasta\t%s\t%s\n' "$rel" "${bytes:-0}"
        done
    done

    # Data files outside the personal folders: this is the case of the shop
    # system that keeps the database next to the executable, which is the rule
    # and not the exception in Brazilian commercial software.
    local args=() e primeiro=1
    for e in $TANDEM_EXT_DADOS; do
        [ "$primeiro" = 1 ] && primeiro=0 || args+=(-o)
        args+=(-iname "*.$e")
    done
    # The find writes to a temporary file instead of straight into the pipe,
    # because in a pipe its exit status is lost. A prefix big enough to hit the
    # 60 s timeout would then look exactly like a prefix with no data at all -
    # and the caller of this function is usually about to delete something.
    # Code 124 (timeout) is propagated as 3: "I could not finish looking".
    local achados rc
    achados="$(mktemp)" || return 1
    timeout 60 find "$c" -type f \( "${args[@]}" \) \
        -not -path "$c/windows/*" -not -path "$c/users/*" \
        -not -path "*/Temp/*" -not -path "*/Cache/*" \
        -size +0 -print0 > "$achados" 2>/dev/null
    rc=$?
    while IFS= read -r -d '' f; do
        printf 'arquivo\t%s\t%s\n' "${f#"$c"/}" "$(stat -c%s "$f" 2>/dev/null || echo 0)"
    done < "$achados"
    rm -f "$achados"
    [ "$rc" -eq 124 ] && { t_diz "a busca por dados em $c estourou o tempo"; return 3; }
    return 0
}

t_dados_total() {
    t_dados_lista "$1" 2>/dev/null | awk -F'\t' '{s += $3} END {print s + 0}'
}

# Packs exactly what t_dados_lista found. "There was nothing" is NOT a failure:
# a freshly created prefix has no data at all.
# 0 = copied, 2 = there was nothing to copy, 1 = there WAS data and the copy
# failed. Those three used to be a single "return 1", which meant a full disk
# and a fresh prefix were indistinguishable to the caller - and the caller is
# about to delete things.
t_dados_salva() {
    local pref="$1" destino="$2" c lista c_tar
    c="$pref/drive_c"
    [ -d "$c" ] || return 2
    lista="$(mktemp)" || return 1
    t_dados_lista "$pref" > "$lista.bruto"; local c_lista=$?
    cut -f2 "$lista.bruto" > "$lista"; rm -f "$lista.bruto"
    # Timeout is not "there is nothing here": treat it as a failed copy, which
    # is the outcome that makes the caller stop before deleting.
    if [ "$c_lista" -eq 3 ]; then rm -f "$lista"; return 1; fi
    if [ ! -s "$lista" ]; then rm -f "$lista"; return 2; fi
    tar -C "$c" -czf "$destino" --files-from "$lista" 2>>"${LOG:-/dev/null}"
    c_tar=$?
    rm -f "$lista"
    [ "$c_tar" -eq 0 ] || return 1
    return 0
}

# Rescue copy before a destructive path. Prints the path of the copy, if there
# was one.
#
# It used to say here that this never blocks the operation - that locking the
# owner up in the middle of a repair would be trading one problem for another.
# That was wrong, and it was wrong in the direction that loses data: the three
# destructive callers went ahead deleting whether the copy had worked or not.
# Same three outcomes as t_dados_salva, and the distinction is the whole point:
# "there was nothing to save" is normal and silent, while "there was data and I
# could not save it" has to stop the caller before it deletes anything. Merging
# the two meant a full disk looked exactly like an empty prefix, and the
# deletion went ahead either way.
t_dados_resgate() {
    local pref="$1" motivo="${2:-resgate}" destino c
    [ -d "$pref/drive_c" ] || return 2
    destino="$HOME/tandem-dados-$motivo-$(date +%F-%H%M%S).tar.gz"
    t_dados_salva "$pref" "$destino"; c=$?
    if [ "$c" -eq 0 ]; then
        t_diz "copia de resgate dos dados em $destino"
        printf '%s\n' "$destino"
        return 0
    fi
    rm -f "$destino" 2>/dev/null
    [ "$c" -eq 2 ] && { t_diz "nada do dono para resgatar em $pref"; return 2; }
    t_diz "FALHOU a copia de resgate de $pref"
    return 1
}

# The sentence the owner reads when the rescue copy failed and something is
# about to be deleted anyway. Separated out because all three destructive
# paths need exactly the same wording.
t_texto_resgate_falhou() {
    t_msg resgate_falhou
}

# ------------------------------------------- the identity, written out
#
# A shop owner whose program says "activate again" has no way at all to find
# out which of his machine's identifiers moved. This prints them side by side
# with a verdict on each: it comes from your real machine / it is a constant
# that every Wine install on Earth reports / it lives inside the environment
# and Tandem is holding it still.
#
# It is only reading. It changes nothing, needs no password, and does not even
# start Wine - every value here comes out of /sys, /proc or system.reg.

t_dmi() {
    local v=""
    [ -r "/sys/class/dmi/id/$1" ] && v="$(tr -d '\000' < "/sys/class/dmi/id/$1" 2>/dev/null | head -1)"
    printf '%s' "$v"
}

# The newline goes at the FRONT, not at the end. Several of these are pasted
# together inside one command substitution, and a substitution strips trailing
# newlines - written the other way round the whole report came out on a single
# line, with the labels padded neatly and nothing else right about it.
t_linha_id() {
    local v n pad
    v="$(printf '%s' "$2" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$v" ] || return 0
    # printf pads by BYTES, and half these labels are accented, so "memória"
    # counted as nine and came out two columns short of everything else. The
    # continuation bytes of a UTF-8 character all sit in 0x80-0xBF: drop them
    # and what is left is one byte per visible character.
    n="$(printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c)"
    pad=$(( 26 - n )); [ "$pad" -lt 1 ] && pad=1
    printf '\n    %s%*s%s' "$1" "$pad" "" "$v"
}

# The network adapters, and whether there is more than one - which is the
# quiet cause of half the lost activations. A program that hashes the MAC and
# a laptop whose Wi-Fi comes and goes are a bad pair, and the owner finds out
# months later.
t_placas_de_rede() {
    local d n
    for d in /sys/class/net/*/; do
        n="$(basename -- "${d%/}")"
        [ "$n" = lo ] && continue
        [ -r "$d/address" ] || continue
        printf '%s\t%s\n' "$n" "$(cat "$d/address" 2>/dev/null)"
    done
}

# ------------------------------------------- serial and parallel ports
#
# Wine reaches a pinpad, a scale, a non-fiscal printer and a serial barcode
# scanner without anything being installed: it maps /dev/ttyS*, /dev/ttyUSB*
# and /dev/ttyACM* to COM ports and /dev/lp* to LPT, by itself. This is not a
# limit of the project, it is one of the places where everything already works
# and nobody knows.
#
# Two things break it, both invisible, and both of them look to the owner like
# "the printer is not there":
#
#   1. The NUMBER. Wine hands out COM1, COM2, ... in the order it scans, and a
#      PC already has three or four /dev/ttyS* whether or not anything is
#      plugged into them. So the pinpad that arrived on /dev/ttyACM0 becomes
#      COM5 - and old point-of-sale software only accepts COM1 to COM4.
#   2. The PERMISSION. Without membership of the "dialout" group the device is
#      right there and simply refuses to open.
#
# Neither produces a message worth reading. This does.

# Is this /dev/ttyS* an actual piece of hardware?
#
# Written after a photograph of a real counter: the list showed COM1 to COM32
# and put the shop's one real device, a USB adapter, on COM33. The comment
# above used to say "a PC already has three or four /dev/ttyS*". It has
# THIRTY-TWO. The kernel's 8250 driver registers 32 lines whether or not any
# serial hardware exists, udev makes a node for each, and a modern PC has none
# of them - the port disappeared from motherboards years ago.
#
# So the list was telling a shopkeeper there were 32 places to plug a pinpad
# into, on a machine that has zero, and burying the one line that mattered
# under 32 that did not.
#
# serial_core exposes the UART type at /sys/class/tty/ttySN/type, mode 444, so
# no privilege is needed: 0 is PORT_UNKNOWN, which means the kernel probed
# that line and found nothing. Anything else is a real chip.
#
# Being UNABLE to tell means real. Hiding a port that exists would break the
# one thing this whole section is for, and that is a far worse failure than
# printing a line too many.
TANDEM_SYS="${TANDEM_SYS:-/sys}"
t_porta_fantasma() {
    local nome tipo
    case "$1" in /dev/ttyS[0-9]*) nome="${1#/dev/}" ;; *) return 1 ;; esac
    tipo="$(cat "$TANDEM_SYS/class/tty/$nome/type" 2>/dev/null)" || return 1
    [ "$tipo" = "0" ]
}

# In the exact order Wine scans, because that order is what decides the
# number each port gets. The phantom ones are LISTED and not skipped: Wine
# counts them too, so dropping them here would print a COM number that does
# not match the one the program will ask for. They are marked at display
# time instead - see t_texto_portas.
# The serial devices Wine will actually give a COM number to, IN WINE'S ORDER.
#
# This mirrors mountmgr's detect_devices(), which walks each family from index
# 0 and STOPS AT THE FIRST GAP - measured against the installed Wine, whose
# mountmgr.so contains exactly /dev/ttyS%u, /dev/ttyUSB%u, /dev/ttyACM%u and
# /dev/lp%u and nothing else. So a hole matters: with /dev/ttyUSB1 present and
# /dev/ttyUSB0 absent, a fresh wineboot creates com1 -> /dev/ttyS0 and NOTHING
# for the USB adapter.
#
# The old version listed every device that existed and t_texto_portas numbered
# them in sequence, so the owner was told his pinpad was on COM2 when Wine had
# created no COM2 at all - wrong in the invisible direction, inside the one
# command written to end exactly this confusion. A hole is not exotic: unplug
# and replug an adapter, or use a two-port converter, and you have one.
t_portas_seriais() {
    local fam i p
    for fam in ttyS ttyUSB ttyACM; do
        i=0
        while :; do
            p="/dev/${fam}${i}"
            [ -c "$p" ] || break
            printf '%s\n' "$p"
            i=$((i + 1))
        done
    done
}

# The devices that EXIST but that Wine skipped, because something before them
# in their family is missing. These are the ones "tandem portas fixar" was
# built for, and until 4.9 nothing ever pointed at them.
t_portas_invisiveis() {
    local fam i p visto
    for fam in ttyS ttyUSB ttyACM; do
        i=0; visto=1
        while [ "$i" -lt 64 ]; do
            p="/dev/${fam}${i}"
            if [ -c "$p" ]; then
                [ "$visto" = 1 ] || printf '%s\n' "$p"
            else
                visto=0
            fi
            i=$((i + 1))
        done
    done
}

t_portas_paralelas() {
    local p
    for p in $(ls -1 -d /dev/lp[0-9]* 2>/dev/null | sort -V); do
        [ -c "$p" ] && printf '%s\n' "$p"
    done
}

t_no_grupo() {
    id -nG 2>/dev/null | tr ' ' '\n' | grep -qxF "$1"
}

# ------------------------------------------------ the hardware key pre-flight
#
# The Sentinel route works because the key is never touched from the Windows
# side: a Linux daemon owns the USB key and the program's DLL reaches the
# licence manager over the machine's own network, on TCP 1947. CodeMeter is
# the same shape on 22350.
#
# Which means the single most useful thing Tandem can check is whether that
# daemon is here at all - and it can check it by reading, before anything is
# downloaded and before any password is asked, in the style of the
# "apt-get install -s" trick in tandem-deb. Without it, the owner meets this
# as "the program says I have no licence", which reads as a broken program and
# sends him to reinstall things. With it, the sentence is "the key's service
# is not installed on this machine, and that is the one thing missing".

# Is anything LISTENING on this port? Runs `ss` ITSELF and reads the kernel's
# socket table - no connection is opened, so nothing can hang and nothing is
# disturbed. Returns 2 for "cannot tell", which the message has to respect:
# answering "not running" when we could not look is the kind of confident
# wrongness this project treats as worse than silence.
#
# The name is t_porta_ouvindo_ss, NOT t_porta_escutando, and the distinction is
# load-bearing: the 4.26 web-service feature later defined a SECOND, different
# t_porta_escutando (a stdin parser fed from a pipe), and bash keeps the LAST
# definition of a name. That shadowed this one, so the dongle check below read
# the terminal's stdin and `tandem doctor`/`tandem socorro` hung with no output.
# Two functions must never share a name; there is a test that fails if any do.
t_porta_ouvindo_ss() {
    command -v ss >/dev/null 2>&1 || return 2
    ss -H -ltn 2>/dev/null |
        awk -v p=":$1" '$4 ~ p "$" { achou = 1 } END { exit !achou }'
}

# Who owns this MIME type, as the FILE MANAGER would answer it.
#
# `xdg-mime query default` is the wrong instrument and this repository already
# proved it: Nautilus uses GIO, and GIO resolves the MIME SUBCLASS CHAIN while
# xdg-mime does not. Re-measured here on a type Tandem never touches -
# `gio mime text/sgml` answers vim.desktop, `xdg-mime query default text/sgml`
# answers nothing.
#
# tandem-repair had it half right: it WRITES the association with both tools
# and then READS it back with xdg-mime alone. So the before/after report - the
# whole point of that command, the thing the owner reads to find out who held
# the type - could say "nobody" about a type a text editor really owns through
# text/plain. .flatpakref is declared sub-class-of text/plain, which is exactly
# the case where "nobody" is wrong AND worse than the truth: with Tandem's
# association gone, a double-clicked .flatpakref opens in a text editor rather
# than doing nothing.
t_dono_do_tipo() {
    local tipo="$1" dono=""
    if command -v gio >/dev/null 2>&1; then
        dono="$(gio mime "$tipo" 2>/dev/null |
                sed -n 's/^Default application for .*: *//p' | head -1)"
    fi
    # xdg-mime is the fallback rather than the authority, and it is kept
    # because a machine with no GIO is a machine where it is the only answer
    # available - not because its answer is as good.
    [ -n "$dono" ] || dono="$(xdg-mime query default "$tipo" 2>/dev/null | head -1)"
    printf '%s' "$dono"
}

# Is this service running? Asked of the process table first, then systemd.
#
# The exact match is what a service name deserves - "wine" must not match
# "winetricks". But Thales installs the Sentinel daemons as aksusbd_x86_64 and
# hasplmd_x86_64, so on a machine where the runtime was installed from the
# vendor's script rather than from a .deb, this answered "not running" about a
# daemon that is running - and the owner is then sent to fix something that is
# not broken. The suffix is matched explicitly rather than by loosening to a
# substring, because loose matching is how "wine" starts matching "winetricks".
t_servico_vivo() {
    pgrep -x "$1" >/dev/null 2>&1 && return 0
    case "$1" in
        *_x86_64|*_i386) ;;
        *) pgrep -x "${1}_x86_64" >/dev/null 2>&1 && return 0
           pgrep -x "${1}_i386"   >/dev/null 2>&1 && return 0 ;;
    esac
    command -v systemctl >/dev/null 2>&1 || return 1
    [ "$(systemctl is-active "$1" 2>/dev/null)" = active ]
}

# familia: sentinel | codemeter. Prints SERVICO= and PORTA=, each sim/nao/?.
t_chave_estado() {
    local servicos porta s r
    case "$1" in
        sentinel)  servicos="aksusbd hasplmd"; porta=1947 ;;
        codemeter) servicos="CodeMeter CodeMeterLin"; porta=22350 ;;
        *) return 1 ;;
    esac
    r=nao
    for s in $servicos; do t_servico_vivo "$s" && { r=sim; break; }; done
    printf 'SERVICO=%s\n' "$r"
    t_porta_ouvindo_ss "$porta"
    case $? in
        0) printf 'PORTA=sim\n' ;;
        2) printf 'PORTA=?\n' ;;
        *) printf 'PORTA=nao\n' ;;
    esac
}

# The sentence appended to a hardware-key verdict once the program has failed.
# It is the difference between a diagnosis and a shrug.
t_texto_chave() {
    local familia="$1" estado servico porta nome pacote
    estado="$(t_chave_estado "$familia")" || return 1
    servico="$(t_campo "$estado" SERVICO)"
    porta="$(t_campo "$estado" PORTA)"
    case "$familia" in
        sentinel)  nome="Sentinel/HASP"
                   pacote="Sentinel LDK Run-time Environment for Linux" ;;
        codemeter) nome="CodeMeter"
                   pacote="CodeMeter Runtime for Linux" ;;
        *) return 1 ;;
    esac

    if [ "$servico" = sim ] || [ "$porta" = sim ]; then
        printf '%s' "$(t_msg chave_ja_roda "$nome")"
        return 0
    fi

    if [ "$porta" = '?' ] && [ "$servico" = nao ]; then
        printf '%s' "$(t_msg chave_nao_sei "$nome")"
        return 0
    fi

    # The product name is passed through untranslated on purpose: the owner has
    # to search for it verbatim on the manufacturer's site.
    printf '%s' "$(t_msg chave_nao_roda "$nome" "$pacote")"
}


# --------------------------------------- the road that starts where Wine ends
#
# There is a second family of tools for running Windows software on Linux, and
# it is not a competitor to Wine - it is the answer to exactly the cases Wine
# cannot reach. WinApps and WinBoat boot a REAL Windows in QEMU/KVM (inside a
# Docker or Podman container, or under libvirt) and then use FreeRDP with the
# RemoteApp protocol to composite one application's window onto the Linux
# desktop, so it looks native without Wine being involved at any point.
#
# Why that matters here, and only here: a real Windows has a real kernel. A
# .sys driver loads for real, a HASP4 dongle is handed to the guest with
# QEMU's usb-host passthrough and speaks to its own driver, a serial pinpad
# can be passed through the same way. Those are the four dead ends this
# project has been declaring - and until now the message ended at "there is no
# fix", which is true of Wine and not true of the machine.
#
# What Tandem does NOT do is become that. This project is a thin layer of
# decision, translation and diagnosis; installing Windows in a container is
# none of those, and it needs a licence Tandem cannot supply. So Tandem points
# - exactly the way "tandem alternativas" points at a native Linux program -
# and it points HONESTLY, which means checking first whether this machine
# could even carry one, and saying the price out loud:
#
#   * a Windows licence, and it has to be Pro or Enterprise. Home cannot host
#     Remote Desktop at all, so the cheap OEM licence on a counter machine
#     does not serve. This is the detail that decides it for most shops and
#     the one every article leaves out.
#   * virtualisation turned on in the BIOS, which is off by default on plenty
#     of machines and is a reboot plus a menu, not a download.
#   * about 32 GB of disk and 4 GB of RAM that stop being yours.
#
# And one case where it is NOT the answer, so nobody is sent on that errand:
# kernel anti-cheat refuses virtual machines by design.

# Can this machine carry one at all? Answered by reading, like everything else
# here: no download, no password, nothing installed.
t_vm_possivel() {
    local flag=0 kvm=0 mem_kb livre_kb
    grep -qE '^flags.*[[:space:]](vmx|svm)[[:space:]]' /proc/cpuinfo 2>/dev/null && flag=1
    [ -e /dev/kvm ] && kvm=1
    mem_kb="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)"
    livre_kb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }')"

    if [ "$flag" = 0 ]; then printf 'nao|%s|%s' "${mem_kb:-0}" "${livre_kb:-0}"; return 0; fi
    if [ "$kvm" = 0 ]; then printf 'bios|%s|%s' "${mem_kb:-0}" "${livre_kb:-0}"; return 0; fi
    if [ "${mem_kb:-0}" -lt 8000000 ] 2>/dev/null ||
       [ "${livre_kb:-0}" -lt 40000000 ] 2>/dev/null; then
        printf 'apertado|%s|%s' "${mem_kb:-0}" "${livre_kb:-0}"; return 0
    fi
    printf 'sim|%s|%s' "${mem_kb:-0}" "${livre_kb:-0}"
}

# The paragraph appended to a dead-end verdict. It is deliberately the LAST
# thing said, after the explanation of why Wine cannot: offered first it would
# read as Tandem giving up early, which for most programs would be wrong
# advice.
t_texto_maquina_virtual() {
    local v mem livre cabe
    v="$(t_vm_possivel)"
    mem="$(printf '%s' "$v" | cut -d'|' -f2)"
    livre="$(printf '%s' "$v" | cut -d'|' -f3)"

    case "${v%%|*}" in
        nao)
            # The processor cannot do it at all. Describing a road that does
            # not leave from here would be padding a bad answer with a
            # paragraph, which is the opposite of the point.
            return 1 ;;
        bios)
            cabe="$(t_msg vm_cabe_bios)" ;;
        apertado)
            cabe="$(t_msg vm_cabe_apertado \
                     "$(t_tamanho_amigavel "$((mem * 1024))")" \
                     "$(t_tamanho_amigavel "$((livre * 1024))")")" ;;
        *)
            cabe="$(t_msg vm_cabe_bem \
                     "$(t_tamanho_amigavel "$((mem * 1024))")" \
                     "$(t_tamanho_amigavel "$((livre * 1024))")")" ;;
    esac

    printf '%s' "$(t_msg vm_texto "$cabe")"
}

t_texto_portas() {
    local prefixo="$1" saida n p alto="" fixadas="" usblp
    saida="$(t_msg portas_titulo)
"

    # A run of phantom ports collapses into ONE line. Printing 32 of them
    # buried the single line that mattered, and every one of the 32 was an
    # invitation to plug a pinpad into a socket this machine does not have.
    # The numbering still counts them, because Wine counts them.
    local f_ini="" f_fim="" f_dev_ini="" f_dev_fim="" fantasmas=0
    fecha_faixa() {
        [ -n "$f_ini" ] || return 0
        local faixa dev
        if [ "$f_ini" = "$f_fim" ]; then faixa="$f_ini"; dev="$f_dev_ini"
        else
            faixa="$(t_msg faixa_de_ate "$f_ini" "$f_fim")"
            dev="$(t_msg faixa_de_ate "$f_dev_ini" "$f_dev_fim")"
        fi
        saida="$saida
  $(t_msg portas_fantasma_faixa "$faixa" "$dev")"
        f_ini=""
    }
    n=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        n=$((n + 1))
        if t_porta_fantasma "$p"; then
            fantasmas=$((fantasmas + 1))
            [ -n "$f_ini" ] || { f_ini="COM$n"; f_dev_ini="$p"; }
            f_fim="COM$n"; f_dev_fim="$p"
            continue
        fi
        fecha_faixa
        case "$p" in
            /dev/ttyACM*|/dev/ttyUSB*) saida="$saida$(t_linha_id "COM$n" "$(t_msg portas_usb_rotulo "$p" "$(t_msg portas_seu_aparelho)")")" ;;
            *)                         saida="$saida$(t_linha_id "COM$n" "$p")" ;;
        esac
        [ "$n" -gt 4 ] && case "$p" in /dev/ttyACM*|/dev/ttyUSB*) alto="COM$n|$p" ;; esac
    done <<< "$(t_portas_seriais)"
    fecha_faixa
    unset -f fecha_faixa
    [ "$n" = 0 ] && saida="$saida
    $(t_msg portas_nenhuma)"
    # Every socket on the list turned out to be one the kernel invents. Saying
    # so is the whole point: otherwise the owner reads 32 lines as 32 places to
    # plug a pinpad into, on a machine that has none.
    [ "$n" -gt 0 ] && [ "$fantasmas" = "$n" ] && saida="$saida

  $(t_msg portas_nenhuma_real)"

    # Is there a serial port the owner could ACTUALLY open - a non-phantom one?
    # Captured now, because the parallel-port loop below reuses n and fantasmas.
    # The dialout warning is gated on this (plus invisible real devices, found
    # further down): warning about the dialout group on a machine whose only
    # serial "ports" are kernel phantoms - or that has none at all - contradicts
    # the "no serial port on this computer" line printed just above it.
    local serial_real=""
    { [ "$n" -gt 0 ] && [ "$fantasmas" != "$n" ]; } && serial_real=sim

    n=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        n=$((n + 1))
        saida="$saida$(t_linha_id "LPT$n" "$p")"
    done <<< "$(t_portas_paralelas)"

    # /dev/usb/lp0, not /dev/usblp0. The kernel's usblp driver registers the
    # class device as "lp%d" through a usblp_devnode() that PREPENDS "usb/", so
    # the node has always been /dev/usb/lp0 and this glob has never matched
    # anything on any machine. The message behind it - a complete sentence in
    # all seven languages naming the exact fix command - has therefore never
    # fired on Earth. The repository already contradicted itself about this:
    # alternativas.tsv says /dev/usb/lp0 correctly, in every language. The old
    # path is kept in the glob because a few systems with a local udev rule do
    # create it, and matching both costs nothing.
    # Devices that exist and that Wine skipped. Until 4.9 these were counted
    # into the COM numbering as if Wine had created them, so the owner was
    # given a number that pointed at nothing.
    local invis; invis="$(t_portas_invisiveis)"
    if [ -n "$invis" ]; then
        saida="$saida

  $(t_msg portas_invisiveis "$(printf '%s' "$invis" | tr '\n' ' ')" \
                            "$(printf '%s' "$invis" | head -1)")"
    fi

    usblp="$(ls -1 -d /dev/usb/lp[0-9]* /dev/usblp[0-9]* 2>/dev/null | head -3)"
    if [ -n "$usblp" ]; then
        saida="$saida

  $(t_msg portas_impressora_usb "$(printf '%s' "$usblp" | tr '\n' ' ')" \
                                "$(printf '%s' "$usblp" | head -1)")"
    fi

    if [ -n "$alto" ]; then
        saida="$saida

  $(t_msg portas_aviso_alto "${alto#*|}" "${alto%%|*}")"
    fi

    if { [ -n "$serial_real" ] || [ -n "$invis" ]; } && ! t_no_grupo dialout; then
        saida="$saida

  $(t_msg portas_aviso_dialout "$(id -un)")"
    fi

    # The printer's group is "lp", not "dialout" - a different device family, the
    # same silent failure: a printer plugged in that simply does not print. The
    # USB printer node (/dev/usb/lp*, found above and kept in $usblp) and a
    # parallel /dev/lp* both belong to group lp, so if one is present and the
    # owner is not in it, name the exact one-time fix, in the shape the dialout
    # warning already uses. Documented as the gap this fills; the report warned
    # about dialout for a serial pinpad and said nothing about lp for a printer.
    if { [ -n "$usblp" ] || [ -n "$(t_portas_paralelas)" ]; } && ! t_no_grupo lp; then
        saida="$saida

  $(t_msg portas_aviso_lp "$(id -un)")"
    fi

    if [ -d "$prefixo/drive_c" ]; then
        fixadas="$(t_reg_lista_valores "$prefixo" 'Software\\Wine\\Ports')"
        [ -n "$fixadas" ] && saida="$saida

  $(t_msg portas_ja_presas)
$(printf '%s' "$fixadas" | sed 's/^/    /')"
    fi

    printf '%s\n' "$saida"
}


# ------------------------------------------------------------- web services
#
# The tenth thing Tandem carries, and the first that is NOT a file you double
# click. A web service is a program that runs and STAYS running, answering on a
# port. On Linux that is a systemd unit; for a program that belongs to one
# person - which is every case on a counter - it is a systemd --user unit, so
# nothing here needs root and nothing here touches /etc. The three hard parts
# for a shopkeeper are the ones this layer owns: knowing WHAT the folder is,
# keeping it alive across a reboot, and saying in plain words WHY it is not
# answering.
#
# Everything below that TALKS to systemd or a live port is machine-only, exactly
# as the Wine loop is - this container has no user session bus. The logic that
# has tests is the part that decides: what runtime a folder is, the unit text,
# which port a line of `ss` reports, and which sentence a state deserves. None
# of that needs systemd to run.

TANDEM_SERVICOS="${TANDEM_SERVICOS:-${XDG_CONFIG_HOME:-$HOME/.config}/tandem/servicos}"
TANDEM_UNIDADES="${TANDEM_UNIDADES:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"

# A service name becomes a file name (tandem-<name>.service) and a systemctl
# argument, so it is held to the same narrow set the winetricks verb is: letters,
# digits, dash and underscore. A dot splits the unit name, a slash escapes the
# directory, a leading dash is an option to systemctl. Refusing costs nothing -
# the name comes from a folder and can always be sanitised first.
t_servico_nome_valido() {
    case "$1" in
        ""|-*|*.*|*/*) return 1 ;;
        *[!A-Za-z0-9_-]*) return 1 ;;
        *) return 0 ;;
    esac
}

# A folder's basename turned into a safe service name: anything outside the set
# becomes a dash, runs of dashes collapse, the ends are trimmed. A folder whose
# name is all punctuation yields "servico" rather than an empty unit name.
t_servico_nome_de_pasta() {
    local nome
    nome="$(basename -- "$1" 2>/dev/null | tr -c 'A-Za-z0-9_-' '-' | tr -s '-' |
            sed 's/^-*//;s/-*$//')"
    [ -n "$nome" ] || nome="servico"
    printf '%s' "$nome"
}

# The first token of a command resolved to an absolute path. systemd's ExecStart
# does not honour the caller's PATH - it searches a fixed short list that does
# NOT include /opt or /usr/local, where node and python often live - so a unit
# saying "node server.js" fails to start on exactly the machines where node was
# installed by hand. Resolving the binary here is what makes the unit actually
# run. A token that is already absolute, or cannot be found, is left as it is
# (the caller's diagnosis then reports the real failure rather than hiding it).
t_servico_absolutiza() {
    local comando="$1" prog resto abs
    prog="${comando%% *}"
    case "$comando" in *" "*) resto=" ${comando#* }" ;; *) resto="" ;; esac
    case "$prog" in
        /*) printf '%s' "$comando"; return 0 ;;
    esac
    abs="$(command -v -- "$prog" 2>/dev/null)"
    [ -n "$abs" ] || abs="$prog"
    printf '%s%s' "$abs" "$resto"
}

# What a folder that is meant to run actually IS, and the command that runs it.
# Answered by LOOKING, never by executing - the discipline peinfo.py holds for a
# .exe. Echoes RUNTIME= and COMANDO=, and PORTA= only where we get to choose the
# port; or ERRO=<token> when the folder does not say enough and the owner must
# give the command by hand. Order is specific-before-generic: a Node project is
# also a folder full of files, and a .jar is also a plain file.
#
# The port is woven into the command ONLY for the two runtimes where the owner
# cannot choose it any other way - PHP's built-in server and Django. For Node, a
# binary or a bare script the program picks its own port and we must be TOLD it
# (for the address and the reachability check), never guess it into the command.
t_servico_detecta() {
    local pasta="$1" porta="${2:-}" main c j
    [ -d "$pasta" ] || { printf 'ERRO=pasta_nao_existe\n'; return 1; }

    # Node - package.json is the declaration.
    if [ -f "$pasta/package.json" ]; then
        printf 'RUNTIME=node\n'
        if grep -q '"start"[[:space:]]*:' "$pasta/package.json" 2>/dev/null; then
            printf 'COMANDO=npm start\n'; return 0
        fi
        main="$(sed -n 's/.*"main"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                "$pasta/package.json" 2>/dev/null | head -1)"
        if [ -z "$main" ]; then
            for c in server.js app.js index.js; do
                [ -f "$pasta/$c" ] && { main="$c"; break; }
            done
        fi
        [ -n "$main" ] || { printf 'ERRO=node_sem_entrada\n'; return 1; }
        printf 'COMANDO=node %s\n' "$main"; return 0
    fi

    # Django - manage.py is unmistakable, and it is the one Python case where we
    # both know the command and must set the port ourselves.
    if [ -f "$pasta/manage.py" ]; then
        printf 'RUNTIME=python\n'
        if [ -n "$porta" ]; then
            printf 'PORTA=%s\n' "$porta"
            printf 'COMANDO=python3 manage.py runserver 0.0.0.0:%s\n' "$porta"
        else
            printf 'ERRO=precisa_porta\n'; return 1
        fi
        return 0
    fi

    # A launcher script the author already wrote is more trustworthy than any
    # guess of ours about the runtime behind it.
    for c in start.sh run.sh server.sh; do
        if [ -f "$pasta/$c" ]; then
            printf 'RUNTIME=script\nCOMANDO=bash %s\n' "$c"; return 0
        fi
    done

    # A single .jar - a servlet container or a Spring Boot fat jar.
    j="$(ls -1 "$pasta"/*.jar 2>/dev/null | head -2)"
    if [ -n "$j" ] && [ "$(printf '%s\n' "$j" | wc -l)" = 1 ]; then
        printf 'RUNTIME=java\nCOMANDO=java -jar %s\n' "$(basename -- "$j")"
        return 0
    fi

    # Generic Python entry points.
    for c in app.py wsgi.py main.py server.py; do
        if [ -f "$pasta/$c" ]; then
            printf 'RUNTIME=python\nCOMANDO=python3 %s\n' "$c"; return 0
        fi
    done

    # PHP - the built-in server, and we choose the port because nothing else can.
    if ls -1 "$pasta"/*.php >/dev/null 2>&1 || [ -f "$pasta/index.php" ]; then
        printf 'RUNTIME=php\n'
        if [ -n "$porta" ]; then
            printf 'PORTA=%s\n' "$porta"
            printf 'COMANDO=php -S 0.0.0.0:%s -t .\n' "$porta"
        else
            printf 'ERRO=precisa_porta\n'; return 1
        fi
        return 0
    fi

    # A Windows server .exe under Wine - the tie to Tandem's own core. A caller
    # must still check rule number 1 on the prefix; this only names the command.
    j="$(ls -1 "$pasta"/*.exe "$pasta"/*.EXE 2>/dev/null | head -2)"
    if [ -n "$j" ] && [ "$(printf '%s\n' "$j" | wc -l)" = 1 ]; then
        printf 'RUNTIME=wine\nCOMANDO=wine %s\n' "$(basename -- "$j")"
        return 0
    fi

    # A single executable ELF sitting in the folder - a Go or Rust server.
    j=""
    for c in "$pasta"/*; do
        [ -f "$c" ] && [ -x "$c" ] || continue
        if head -c4 -- "$c" 2>/dev/null | grep -q "$(printf '\177ELF')"; then
            j="$j $c"
        fi
    done
    set -- $j
    if [ "$#" = 1 ]; then
        printf 'RUNTIME=binario\nCOMANDO=./%s\n' "$(basename -- "$1")"; return 0
    fi

    printf 'ERRO=nao_reconheci\n'; return 1
}

# The systemd --user unit text. WantedBy=default.target is the user-session
# equivalent of multi-user.target; Restart=always is why a service that dies
# comes back without anybody watching. Kept as its own function so a test can
# read the text without a systemd anywhere.
t_servico_unit() {
    local nome="$1" pasta="$2" comando="$3"
    printf '[Unit]\n'
    printf 'Description=%s (Tandem)\n' "$nome"
    printf 'After=network.target\n\n'
    printf '[Service]\n'
    printf 'Type=simple\n'
    printf 'WorkingDirectory=%s\n' "$pasta"
    printf 'ExecStart=%s\n' "$comando"
    printf 'Restart=always\n'
    printf 'RestartSec=3\n\n'
    printf '[Install]\n'
    printf 'WantedBy=default.target\n'
}

# Is something listening on <porta>? Reads `ss -ltnH` style lines on stdin so
# the parsing has a test with no open socket anywhere. The local address column
# ends in ":<porta>"; a LISTEN socket's peer column is "0.0.0.0:*" or "*:*", so
# a bare numeric ":<porta>" only ever appears on the local side.
t_porta_escutando() {
    local porta="$1" linha campo
    while IFS= read -r linha; do
        for campo in $linha; do
            case "$campo" in
                *":$porta") return 0 ;;
            esac
        done
    done
    return 1
}

# The process name holding a port, out of one `ss -ltnpH` line's users:(...)
# field: users:(("nginx",pid=42,fd=6)) -> nginx. Empty when the field is absent.
t_nome_no_ss() {
    sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | head -1
}

# The plain-language verdict for a service, from three facts and nothing else:
# is the unit ACTIVE, is something LISTENING on its port, does it ANSWER. Pure,
# so the whole truth table is a test. The caller turns the token into a sentence
# and attaches the address, the log tail or the port's owner.
#   estado:   sem-systemd | nao-instalado | falhou | parado | ativo
#   escuta:   sim | nao
#   responde: sim | nao | ""(not checked / port unknown)
t_servico_veredito() {
    local estado="$1" escuta="$2" responde="$3"
    case "$estado" in
        sem-systemd)   printf 'sem-systemd\n'; return ;;
        nao-instalado) printf 'nao-instalado\n'; return ;;
        falhou)        printf 'falhou\n'; return ;;
        parado|inativo) printf 'parado\n'; return ;;
    esac
    # From here the unit is active (or still activating).
    case "$escuta" in
        sim)
            case "$responde" in
                sim) printf 'ok\n' ;;
                nao) printf 'escuta-mudo\n' ;;
                *)   printf 'rodando\n' ;;
            esac ;;
        *) printf 'subindo\n' ;;
    esac
}


# ---- the parts that need a live systemd/user session; machine-only ----
#
# None of the four below has a test that runs them, for the same reason the Wine
# loop does not: there is no user session bus in CI. What IS tested is the pure
# logic they feed - the port parser, the verdict table - so a wrong answer here
# shows up as a wrong SENTENCE there, where a test can see it.

# Is there a user systemd to talk to at all? On a headless box, a cron job or a
# container there is no session bus and every systemctl --user call answers
# "Failed to connect to bus". Being unable to reach it is not a thing to hide -
# it is the whole reason a service cannot be managed, and the owner is told.
t_servico_tem_systemd() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl --user show-environment >/dev/null 2>&1
}

# The unit's state, mapped to the words t_servico_veredito expects. "activating"
# counts as active - it is coming up, and the port check tells the rest.
t_servico_estado_unidade() {
    local nome="$1" est
    systemctl --user list-unit-files "tandem-$nome.service" >/dev/null 2>&1 || {
        printf 'nao-instalado\n'; return; }
    systemctl --user list-unit-files "tandem-$nome.service" 2>/dev/null |
        grep -q "^tandem-$nome.service" || { printf 'nao-instalado\n'; return; }
    est="$(systemctl --user is-active "tandem-$nome.service" 2>/dev/null)"
    case "$est" in
        active|activating) printf 'ativo\n' ;;
        failed)            printf 'falhou\n' ;;
        *)                 printf 'parado\n' ;;
    esac
}

# Is something listening on <porta>? The parser (t_porta_escutando) has the test;
# this only feeds it the live socket table.
t_servico_escuta() {
    local porta="$1"
    [ -n "$porta" ] || return 1
    ss -ltnH 2>/dev/null | t_porta_escutando "$porta"
}

# The process holding a port - ss first, lsof as the fallback. Used to name the
# culprit when a service could not bind because something else already has the
# port.
t_servico_dono_porta() {
    local porta="$1" nome=""
    [ -n "$porta" ] || return 1
    nome="$(ss -ltnpH "sport = :$porta" 2>/dev/null | t_nome_no_ss)"
    if [ -z "$nome" ] && command -v lsof >/dev/null 2>&1; then
        nome="$(lsof -iTCP:"$porta" -sTCP:LISTEN -Fc 2>/dev/null |
                sed -n 's/^c//p' | head -1)"
    fi
    printf '%s' "$nome"
}

# Does anything answer HTTP on <porta>? Any status code is an answer - a 500 is a
# working web server having a bad day, which is a different thing from silence.
# Returns 2 when we cannot even check (no port, no curl), so the caller can say
# "running" rather than claim it is or is not reachable.
t_servico_responde() {
    local porta="$1" code
    [ -n "$porta" ] || return 2
    command -v curl >/dev/null 2>&1 || return 2
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
            "http://localhost:$porta/" 2>/dev/null)"
    case "$code" in
        ""|000) return 1 ;;
        *) return 0 ;;
    esac
}

# ---- Tandem's own record of a service; the unit is systemd's, this is ours ----

# Kept so Tandem can report the address and check the port later, and so a name
# is held to the same narrow set before it becomes a directory.
t_servico_grava() {
    local nome="$1" pasta="$2" porta="$3" comando="$4" dir
    t_servico_nome_valido "$nome" || return 1
    dir="$TANDEM_SERVICOS/$nome"
    mkdir -p "$dir" 2>/dev/null || return 1
    { printf 'PASTA=%s\n' "$pasta"
      printf 'PORTA=%s\n' "$porta"
      printf 'COMANDO=%s\n' "$comando"
    } > "$dir/info" 2>/dev/null
}

t_servico_le() {   # <nome> <chave>
    local dir="$TANDEM_SERVICOS/$1"
    [ -f "$dir/info" ] || return 1
    sed -n "s/^$2=//p" "$dir/info" | head -1
}

t_servico_apaga() {
    local nome="$1"
    t_servico_nome_valido "$nome" || return 1
    rm -rf "${TANDEM_SERVICOS:?}/$nome" 2>/dev/null
}

# The names of every service Tandem manages, one per line, sorted.
t_servico_lista_nomes() {
    [ -d "$TANDEM_SERVICOS" ] || return 0
    local d n
    for d in "$TANDEM_SERVICOS"/*/; do
        [ -d "$d" ] || continue
        n="$(basename -- "$d")"
        [ -f "$TANDEM_SERVICOS/$n/info" ] && printf '%s\n' "$n"
    done | sort
}

# Every "name = value" of one registry key, straight out of system.reg.
t_reg_lista_valores() {
    local prefixo="$1" chave="$2"
    local arq="$prefixo/system.reg"
    [ -f "$arq" ] || return 1
    T_CHAVE="[$chave]" awk '
        BEGIN { chave = ENVIRON["T_CHAVE"] }
        index($0, chave) == 1 { dentro = 1; next }
        substr($0, 1, 1) == "[" { dentro = 0 }
        dentro && substr($0, 1, 1) == "\"" {
            linha = $0
            gsub(/"/, "", linha)
            sub(/=/, " = ", linha)
            print linha
        }' "$arq" 2>/dev/null
}

t_texto_identidade() {
    local prefixo="$1" saida="" guid guid32 pid serial semente marca
    local so_leitura="" placas conta n m f kb

    kb="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)"

    saida="$(t_msg id_titulo)

  $(t_msg id_vem_da_maquina)$(
      t_linha_id "$(t_msg id_fabricante)" "$(t_dmi sys_vendor)")$(
      t_linha_id "$(t_msg id_modelo)" "$(t_dmi product_name)")$(
      t_linha_id "$(t_msg id_placa_mae)" "$(t_dmi board_name)")$(
      t_linha_id "BIOS" "$(t_dmi bios_version) $(t_dmi bios_date)")$(
      t_linha_id "$(t_msg id_processador)" "$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1)")$(
      t_linha_id "$(t_msg id_memoria)" "${kb:+$(t_tamanho_amigavel "$(( kb * 1024 ))")}")"

    placas="$(t_placas_de_rede)"
    conta="$(printf '%s' "$placas" | awk 'END { print NR + 0 }')"
    while IFS=$'\t' read -r n m; do
        [ -n "$n" ] || continue
        saida="$saida$(t_linha_id "$(t_msg id_rede "$n")" "$m")"
    done <<< "$placas"

    # Three DMI fields the kernel keeps for root only. Wine cannot read them
    # either, and puts a stable substitute in their place - so this is not a
    # failure, it is a difference worth naming.
    for f in product_serial board_serial chassis_serial; do
        if [ -e "/sys/class/dmi/id/$f" ] && [ ! -r "/sys/class/dmi/id/$f" ]; then
            so_leitura="sim"
        fi
    done

    saida="$saida

  $(t_msg id_nao_vem "${so_leitura:+$(t_msg id_serial_de_fabrica)}")"

    if [ -d "$prefixo/drive_c" ]; then
        serial="$(cat "$prefixo/drive_c/.windows-serial" 2>/dev/null)"
        guid="$(t_reg_valor "$prefixo" 'Software\\Microsoft\\Cryptography' MachineGuid)"
        pid="$(t_reg_valor "$prefixo" 'Software\\Microsoft\\Windows NT\\CurrentVersion' ProductId)"
        marca="$prefixo/.tandem-identidade"
        semente=""
        [ -f "$marca" ] && semente="$(sed -n 's/^SEMENTE=//p' "$marca" 2>/dev/null)"

        saida="$saida

  $(t_msg id_fica_parado)$(
      t_linha_id "$(t_msg id_serial_disco_c)" "${serial:-$(t_msg id_wine_escolhe)}")$(
      t_linha_id "$(t_msg id_identificador_maquina)" "${guid:-$(t_msg id_ainda_nao_existe)}")$(
      t_linha_id "$(t_msg id_productid)" "$pid")"

        case "$pid" in
            12345-oem-0000001-54321)
                saida="$saida

  $(t_msg id_productid_de_fabrica)" ;;
        esac

        # The 32-bit view of the registry is a different place, and a program
        # reads whichever one matches its own bitness. This report used to show
        # only the 64-bit key, which is how a MachineGuid written into
        # Wow6432Node and read out of Software\Microsoft went unnoticed. If the
        # two disagree the owner has two machines as far as his programs are
        # concerned, and that deserves a sentence rather than a silent field.
        guid32="$(t_reg_valor "$prefixo" 'Software\\Wow6432Node\\Microsoft\\Cryptography' MachineGuid)"
        if [ -n "$guid32" ] && [ -n "$guid" ] && [ "$guid32" != "$guid" ]; then
            saida="$saida

  $(t_msg id_vistas_diferentes "$guid" "$guid32")"
        fi

        if [ -n "$semente" ] && [ "$semente" != "$(t_maquina_semente)" ]; then
            saida="$saida

  $(t_msg id_identidade_mudou)"
        fi
    fi

    if [ "${conta:-0}" -gt 1 ]; then
        saida="$saida

  $(t_msg id_varias_placas "$conta")"
    fi

    printf '%s\n' "$saida"
}

# Returns the command prefix that keeps the machine from suspending during a
# long installation - or nothing, if it does not work here.
#
# Checking with "command -v systemd-inhibit" is not enough, and the difference
# cost a whole installation on a real Ubuntu 24.04: the binary exists, but
# with no session D-Bus bus it exits 1 with "Failed to connect to bus" and
# takes the wrapped command down with it. winetricks never even got to run,
# and the owner was told to check the internet connection - which was perfect.
# It is the same old mistake: presence is not function. Here we exercise it.
t_inibidor() {
    command -v systemd-inhibit >/dev/null 2>&1 || return 0
    systemd-inhibit --what=idle --who=Tandem --why=teste \
        true >/dev/null 2>&1 || {
        t_diz "systemd-inhibit existe mas nao funciona aqui; seguindo sem ele"
        return 0
    }
    printf '%s' "systemd-inhibit --what=idle:sleep:shutdown --who=Tandem --why=Instalando_componentes_do_Windows --mode=block"
}

t_como_root() {
    local script="$1"
    if [ "$(id -u)" = 0 ]; then
        sh -c "$script"
    elif [ -t 0 ] && command -v sudo >/dev/null 2>&1; then
        sudo sh -c "$script"
    elif t_tem_gui && command -v pkexec >/dev/null 2>&1; then
        pkexec sh -c "$script"
    else
        return 127
    fi
}

# What is missing on this machine, one piece per line. Each line is
#     code|description for the user
# The description half of every line here was literal Portuguese, and this is
# the whole screen of "tandem preparar" - the command that exists because a
# dependency cannot be installed from postinst. Seven sentences, shown to every
# user in every language, and invisible to the counter for the same reason as
# t_verbo_amigavel: a helper whose name is not a prose-body pattern.
t_pecas_faltando() {
    command -v wine >/dev/null 2>&1 ||
        echo "wine|$(t_msg peca_wine)"
    if command -v wine >/dev/null 2>&1 && ! t_tem_wine32; then
        echo "wine32|$(t_msg peca_wine32)"
    fi
    command -v winetricks >/dev/null 2>&1 ||
        echo "winetricks|$(t_msg peca_winetricks)"
    command -v adb >/dev/null 2>&1 ||
        echo "adb|$(t_msg peca_adb)"
    command -v java >/dev/null 2>&1 ||
        echo "java|$(t_msg peca_java)"
    # An AppImage without FUSE still opens - Tandem falls back to unpacking it -
    # but every launch pays for the unpacking. The library is a few hundred
    # kilobytes and it stopped being installed by default in Ubuntu 22.04.
    t_tem_fuse2 ||
        echo "fuse|$(t_msg peca_fuse)"
    command -v waydroid >/dev/null 2>&1 ||
        echo "waydroid|$(t_msg peca_waydroid)"
    return 0
}

# Is libfuse2 there? Asked of the loader, not of dpkg: the package is called
# libfuse2 on some releases and libfuse2t64 on others, and the loader knows the
# library by the only name that never changed.
t_tem_fuse2() {
    # The whole pipeline inside the braces, not just ldconfig: with a stripped
    # PATH it is bash that complains about grep, and bash writes that to the
    # shell's stderr where a redirection on one element of the pipe cannot
    # reach it. The stray line showed up in the middle of a test listing.
    { ldconfig -p | grep -q 'libfuse\.so\.2'; } 2>/dev/null ||
    ls /usr/lib/*/libfuse.so.2 /lib/*/libfuse.so.2 >/dev/null 2>&1
}

# Assembles the installation script for the requested pieces (one per
# argument). Everything in a single script: one single password, one single
# run.
t_script_instalacao() {
    local peca n
    printf 'set -e\nexport DEBIAN_FRONTEND=noninteractive\n'
    for peca in "$@"; do
        case "$peca" in
            wine)       printf 'apt-get update -q\napt-get install -y wine winetricks\n' ;;
            wine32)     printf 'dpkg --add-architecture i386\napt-get update -q\napt-get install -y wine32:i386\n' ;;
            winetricks) printf 'apt-get install -y winetricks\n' ;;
            adb)        printf 'apt-get install -y adb\n' ;;
            java)       printf 'apt-get update -q\napt-get install -y default-jre\n' ;;
            # On demand only, and deliberately NOT in t_pecas_faltando. Java and
            # FUSE are needed to DIAGNOSE a file the owner is likely to have -
            # Brazilian fiscal and NFe tools are routinely .jar. A .flatpakref is
            # an artefact of the Linux enthusiast world; making every shop owner
            # download a store for a file he will probably never see would be
            # spending his connection on our tidiness.
            flatpak)    printf 'apt-get update -q\napt-get install -y flatpak\n' ;;
            java[0-9]*)
                # The version comes from a file read off the disk, so it never
                # reaches the script without being reduced to digits: this
                # string becomes part of a command running as root.
                n="${peca#java}"; n="$(printf '%s' "$n" | tr -cd '0-9')"
                [ -n "$n" ] || continue
                printf 'apt-get update -q\napt-get install -y openjdk-%s-jre || apt-get install -y default-jre\n' "$n"
                ;;
            fuse)
                # Renamed to libfuse2t64 in the 64-bit-time_t transition, so
                # both names are tried; and "set -e" is on, hence the || .
                printf 'apt-get install -y libfuse2t64 || apt-get install -y libfuse2\n' ;;
            waydroid)
                # Waydroid is not in the Ubuntu/Zorin repositories: it comes
                # from the project's official repository. We add the source
                # with a checked key, the way the project itself instructs.
                cat <<'FIM'
if ! command -v waydroid >/dev/null 2>&1; then
    python3 - <<'PY'
import urllib.request
urllib.request.urlretrieve("https://repo.waydro.id/waydroid.gpg",
                           "/usr/share/keyrings/waydroid.gpg")
PY
    . /etc/os-release
    echo "deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ ${UBUNTU_CODENAME:-$VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/waydroid.list
    apt-get update -q
    apt-get install -y waydroid
fi
if [ ! -f /var/lib/waydroid/waydroid.cfg ]; then
    waydroid init
fi
FIM
                ;;
        esac
    done
}

# -------------------------------------------------------------- waydroid

t_wd_sessao_ok() {
    waydroid status 2>>"${LOG:-/dev/null}" | grep -q "Session:[[:space:]]*RUNNING"
}

t_wd_pronto() {
    [ "$(waydroid prop get sys.boot_completed 2>/dev/null | tr -d '[:space:]')" = "1" ]
}

t_wd_sdk() {
    waydroid prop get ro.build.version.sdk 2>/dev/null | tr -d '[:space:]'
}

t_wd_ip() {
    waydroid status 2>/dev/null | awk -F'\t' '/^IP:/ {gsub(/ /,"",$NF); print $NF; exit}'
}

# Does this Waydroid declare that Android may see USB devices?
#
# The barrier is precise and it is not the one the README used to describe.
# Waydroid's LXC config carries no device-cgroup denial at all, so the container
# is not what blocks a USB device - AOSP is. UsbService only instantiates
# UsbHostManager when the platform declares android.hardware.usb.host, and the
# LineageOS image Waydroid ships does not declare it, so getDeviceList() returns
# an empty list no matter what exists under /dev.
#
# Waydroid bind-mounts a host directory over vendor/etc/host-permissions, which
# is where such a declaration can be dropped without touching the shipped image.
t_wd_usb_declarado() {
    ls /var/lib/waydroid/host-permissions/*usb.host*.xml >/dev/null 2>&1 && return 0
    waydroid shell -- sh -c 'ls /vendor/etc/permissions/android.hardware.usb.host.xml \
        /vendor/etc/host-permissions/android.hardware.usb.host.xml 2>/dev/null' 2>/dev/null |
        grep -q . && return 0
    return 1
}

# The property that lets the container's own ueventd create device nodes. It is
# a feature the Waydroid maintainer added ("allow android direct access to
# hotplugged devices"), and it is also the cause of the one bug an owner with a
# barcode scanner will actually hit.
t_wd_uevent() {
    waydroid prop get persist.waydroid.uevent 2>/dev/null | grep -qi true
}

t_wd_tem_arm() {
    waydroid shell -- sh -c 'ls /system/lib64/libhoudini.so /system/lib/libhoudini.so \
        /system/lib64/libndk_translation.so 2>/dev/null | head -1' 2>/dev/null | grep -q .
}

# Ensures container + session + completed boot. Returns 1 and already warns in
# case of failure.
t_wd_garantir() {
    local estado
    if ! command -v waydroid >/dev/null 2>&1; then
        if t_pergunta "$(t_msg waydroid_falta_pergunta)" \
            "$(t_msg botao_instalar)" "$(t_msg botao_agora_nao)"; then
            t_progresso_texto "$(t_msg waydroid_instalando)"
            t_como_root "$(t_script_instalacao waydroid)" >>"${LOG:-/dev/null}" 2>&1
        fi
        command -v waydroid >/dev/null 2>&1 || {
            t_erro "$(t_msg waydroid_falta_erro)"
            return 1; }
    fi

    estado="$(systemctl is-active waydroid-container 2>/dev/null)"
    if [ "$estado" = "activating" ]; then
        for _ in $(seq 1 30); do
            [ "$(systemctl is-active waydroid-container 2>/dev/null)" = "active" ] && break
            sleep 2
        done
    elif [ "$estado" != "active" ]; then
        t_progresso_texto "$(t_msg waydroid_ligando)"
        systemctl start waydroid-container >>"${LOG:-/dev/null}" 2>&1 ||
        pkexec systemctl start waydroid-container >>"${LOG:-/dev/null}" 2>&1 || {
            t_erro "$(t_msg waydroid_nao_ligou)"; return 1; }
    fi
    for _ in $(seq 1 30); do
        [ "$(systemctl is-active waydroid-container 2>/dev/null)" = "active" ] && break
        sleep 1
    done

    # The session may be coming up through autostart: give it some time before
    # competing with it.
    if ! t_wd_sessao_ok; then
        for _ in $(seq 1 10); do t_wd_sessao_ok && break; sleep 2; done
    fi
    if ! t_wd_sessao_ok; then
        t_progresso_texto "$(t_msg waydroid_iniciando_sessao)"
        setsid waydroid session start >>"${LOG:-/dev/null}" 2>&1 &
        for _ in $(seq 1 40); do t_wd_sessao_ok && break; sleep 2; done
    fi
    if ! t_wd_sessao_ok; then
        if grep -qi 'not initialized' "${LOG:-/dev/null}" 2>/dev/null; then
            t_erro "$(t_msg waydroid_sem_init)"
        else
            t_erro "$(t_msg waydroid_nao_iniciou)"
        fi
        return 1
    fi

    if ! t_wd_pronto; then
        t_progresso_texto "$(t_msg waydroid_aguardando)"
        for _ in $(seq 1 90); do t_wd_pronto && break; sleep 2; done
    fi
    t_wd_pronto || { t_erro "$(t_msg waydroid_nao_ficou_pronto)"; return 1; }
    return 0
}

# ------------------------------------------------------- native packages
#
# The formats Linux itself uses, and which fail on a double click for reasons
# that have nothing to do with Wine or Android. They are here for the same
# reason .exe is: the owner double-clicked something he downloaded, and
# "nothing happened" is a defect.
#
# Two are handled: .AppImage, whose failure is almost always the missing
# execute bit or a half-finished download, and .jar, whose failure is almost
# always a Java that is missing or older than the program. Both are diagnosed
# by reading the file, never by running it and guessing from the wreckage.

# The machine's architecture with the names an ELF header uses, so comparing an
# AppImage against the computer is a string comparison and not a table.
t_maquina_arch() {
    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64)   printf 'x86_64' ;;
        i?86)           printf 'i386' ;;
        aarch64|arm64)  printf 'aarch64' ;;
        armv7*|armhf)   printf 'armhf' ;;
        riscv64)        printf 'riscv64' ;;
        ppc64le)        printf 'ppc64le' ;;
        *)              printf '%s' "$(uname -m 2>/dev/null)" ;;
    esac
}

# An x86_64 machine runs an i386 AppImage as long as the 32-bit libraries are
# there; the reverse is never true. Everything else has to match.
t_arch_compativel() {
    local do_arquivo="$1" da_maquina="${2:-$(t_maquina_arch)}"
    # Not knowing is not a reason to block: an architecture we cannot read is
    # answered by trying, not by refusing.
    case "$do_arquivo" in ''|'?') return 0 ;; esac
    [ "$do_arquivo" = "$da_maquina" ] && return 0
    [ "$da_maquina" = x86_64 ] && [ "$do_arquivo" = i386 ] && return 0
    [ "$da_maquina" = aarch64 ] && [ "$do_arquivo" = armhf ] && return 0
    return 1
}

# One field out of a KEY=VALUE reader. The readers all answer in the same
# shape, so one function serves peinfo, apkinfo, appimageinfo and jarinfo.
t_campo() {
    printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1
}

# Turns the readers' ERRO field into a sentence in the owner's language.
#
# This function exists because of the fifteenth thing the literal counter could
# not see, and it was the worst of them in one respect: the six Python readers
# raised PORTUGUESE - "nao comeca com ELF", "o pacote nao traz um arquivo
# control", about thirty of them - and the handlers printed the field straight
# to the owner through t_msg nao_consegui_ler. So a third of a screen's worth of
# user-facing prose lived in files no translation tool in this tree had ever
# opened, and nothing measured it: ALVOS globs *.sh and src/bin only.
#
# Worse than untranslated: the catch-all branch is `print("ERRO=cru|%s" % e)`,
# an arbitrary Python exception - "[Errno 13] Permission denied" - which is
# English jargon whatever the owner's language is. That path now says what
# happened in words and puts the exception in the log, where the person helping
# will read it.
#
# An UNKNOWN token gets the generic sentence rather than nothing. A reader that
# learns a new failure tomorrow must not be able to produce silence, and the
# suite asserts that every token the readers can emit has a key - so an unknown
# one means somebody added a failure without a message, which is a bug in the
# commit rather than in the machine in front of the owner.
t_erro_do_leitor() {
    local bruto="$1" ficha dado
    [ -n "$bruto" ] || return 1
    # The whole field always goes to the log: the token, and the technical
    # detail if there is one. "We could not read it" on the screen and nothing
    # anywhere else would be a diagnosis nobody can follow up.
    t_diz "leitor: $bruto"
    ficha="${bruto%%|*}"
    dado="${bruto#*|}"
    [ "$dado" = "$bruto" ] && dado=""
    case "$ficha" in
        cru) t_msg leitor_cru ;;
        # A token is a name, and anything else came from somewhere it should
        # not have. Refusing it here keeps a reader's output from choosing a
        # message key.
        *[!a-z_0-9]*|"") t_msg leitor_desconhecido ;;
        *)
            # t_msg PRINTS THE KEY NAME when a key is missing everywhere, which
            # is right for a maintainer reading a log and wrong here: it would
            # put "leitor_xyz" on a shop owner's screen, which is exactly the
            # jargon rule 2 forbids. So the existence of the key is checked
            # first, and the generic sentence covers a reader that grew a
            # failure nobody wrote a message for.
            if [ -n "${T_MSG[leitor_$ficha]:-}${T_MSG_BASE[leitor_$ficha]:-}" ]; then
                t_msg "leitor_$ficha" "$dado"
            else
                t_diz "leitor: nao existe a mensagem 'leitor_$ficha'"
                t_msg leitor_desconhecido
            fi ;;
    esac
}

# A memory value turned into a sentence, for the moment it is SHOWN.
#
# The value stays on disk exactly as it was written - "java antigo", "so arm",
# "fechou sozinho". That is not sentiment: a recipe is a file the owner sends to
# somebody else, and rule after rule in this project depends on those strings
# being stable, so translating one would break every memory file and every
# recipe already written on a machine somewhere.
#
# What was wrong was the conclusion drawn from that. "It is on-disk format"
# became "so it never reaches a person", and it does: acao_memoria prints it,
# tandem socorro puts it in the report the owner sends to whoever is helping,
# and t_receita_exporta dumps the whole file into something whose own header
# invites a stranger to read it. Forty-four of those values are Portuguese
# sentences - "nao confirmou", "pasta sem permissao", "bitola errada", which is
# Brazilian slang no dictionary recovers - and the static counter is blind to
# all of them BY CONSTRUCTION, because it exempts an argument by where it goes.
#
# So: token on disk, sentence on screen, exactly as t_erro_do_leitor does for
# the readers. An unknown value prints itself rather than a key name - an old
# memory file written by a version that knew a value this one does not is the
# normal case, not an error.
# ------------------------------------------- one dependency install at a time
#
# The lock tandem-exe takes at the top is keyed to the FILE, and deliberately
# so: opening two different programs at once has to keep working. But both of
# those programs land in the same prefix by default, and both may decide they
# need components - so two "winetricks -q" runs can be writing into one
# WINEPREFIX at the same time. That is exactly what the file lock's own comment
# says corrupts a prefix, and the lock chosen to prevent it does not cover the
# case. The prefix lock existed already and wrapped only wineboot, which is the
# one moment two processes were never going to collide on anyway.
#
# Keyed per prefix, because somebody may be running a program that lives inside
# their own prefix while another installs into Tandem's.
t_trava_do_prefixo() {
    local pref="${1:-$WINEPREFIX}"
    printf '%s/prefixo-%s.lock' "$TANDEM_TRAVAS" \
        "$(printf '%s' "$pref" | cksum | tr -d ' ')"
}

# Takes it on fd 9. Returns 0 whether or not the lock was actually acquired: an
# impossible lock and a busy lock are different cases, and the first must not
# stop the program from opening - the same decision, and the same reason, as
# the file lock at the top of tandem-exe.
t_trava_prefixo_pega() {
    local arq; arq="$(t_trava_do_prefixo "${1:-$WINEPREFIX}")"
    { exec 9> "$arq"; } 2>/dev/null || {
        t_diz "prefixo: nao consegui criar a trava $arq; seguindo sem ela"
        return 0
    }
    flock -n 9 2>/dev/null && return 0
    # Somebody else really is installing. Say so rather than appearing frozen:
    # dotnet48 takes half an hour, and a silent wait that long is the failure
    # this project is named after.
    t_aviso "$(t_msg esperando_outra_instalacao)"
    flock -w 2400 9 2>/dev/null ||
        t_diz "prefixo: a trava nao veio em 40 min; seguindo mesmo assim"
    return 0
}

t_trava_prefixo_solta() {
    { flock -u 9; } 2>/dev/null
    { exec 9>&-; } 2>/dev/null
    return 0
}

# The LIMITE memory field, turned into a sentence at DISPLAY time. It is stored
# as "class|rest": the class is language-neutral on-disk format, and the rest is
# already a translated sentence for the paths that build one from t_msg (the
# bitness dead end) or from the per-language limites.tsv. Four handlers instead
# wrote hard-coded Portuguese into the rest - arquitetura, agente, biblioteca,
# outra-familia - and acao_memoria printed it verbatim, so a non-Portuguese
# owner met raw Portuguese on `tandem memoria` and inside `tandem socorro`.
# Same doctrine as t_resultado_amigavel: keep the token on disk, translate on
# the way to the screen. Translating by CLASS also fixes it for memory files
# ALREADY written with the Portuguese rest, and the fall-through prints the rest
# untouched for the paths that already store a translated sentence.
t_limite_amigavel() {
    local v="${1:-}" classe resto
    classe="${v%%|*}"; resto="${v#*|}"
    case "$classe" in
        arquitetura)   t_msg mem_limite_arquitetura ;;
        agente)        t_msg mem_limite_agente ;;
        biblioteca)    t_msg mem_limite_biblioteca ;;
        outra-familia) t_msg mem_limite_outra_familia ;;
        versao)        t_msg mem_limite_versao "${resto%%>*}" "${resto#*>}" ;;
        *)             printf '%s' "$resto" ;;
    esac
}

t_resultado_amigavel() {
    local valor="${1:-}" chave
    [ -n "$valor" ] || return 1
    chave="res_${valor// /_}"
    chave="${chave//-/_}"
    case "$chave" in *[!a-z_0-9]*) printf '%s' "$valor"; return 0 ;; esac
    if [ -n "${T_MSG[$chave]:-}${T_MSG_BASE[$chave]:-}" ]; then
        t_msg "$chave"
    else
        printf '%s' "$valor"
    fi
}

# Why winetricks failed, read from winetricks' own words.
#
# Extracted from tandem-exe so it can be exercised: it was twenty lines of elif
# inline in the install loop, and the only way to reach it was to make a real
# winetricks fail. That is why the scoping defect it had went unnoticed - the
# slice handed to it came from the LAST verb attempted rather than from the one
# that failed, so a program needing two components was told its internet had
# failed about a component whose real problem was something else, because a
# later component downloaded normally.
#
# $1 is a file holding ONLY the output of the verbs that failed.
#
# It reads the log ONCE and answers a TOKEN, because two callers need two
# different things out of the same reading. The failure path wants a sentence
# for the owner; the install loop wants only to know whether the MACHINE failed
# (disk, network, clock) or the translation table is wrong - and blaming the
# table for a full disk poisons the one work list that has already found six
# genuinely wrong mappings. Written as one table with two readers on top rather
# than as two grep chains: a copy drifts, and a drifted copy is a rule that
# fires on one path and not the other.
t_causa_token() {
    local resto="$1"
    [ -f "$resto" ] || { printf 'desconhecido'; return 0; }
    # The specific causes first: each one is a thing winetricks said outright,
    # and any of them outranks the guess below.
    if grep -qi 'Failed to connect to bus' "$resto" 2>/dev/null; then
        printf 'dbus'
    elif grep -qi 'No space left on device' "$resto" 2>/dev/null; then
        printf 'disco_cheio'
    elif grep -qi 'certificate\|SSL\|not yet valid\|has expired' "$resto" 2>/dev/null; then
        printf 'relogio'
    elif grep -qi 'Could not resolve host\|Network is unreachable\|Connection timed out' "$resto" 2>/dev/null; then
        printf 'sem_rede'
    elif grep -qi 'sha256sum mismatch\|checksum' "$resto" 2>/dev/null; then
        printf 'corrompido'
    elif grep -qi 'cabextract' "$resto" 2>/dev/null; then
        printf 'cabextract'
    # The most common cause is the internet, but claiming it without evidence
    # sends the owner looking for the defect in the wrong place - which is what
    # happened when systemd-inhibit brought the install down before it even
    # started. With no sign of a download having been ATTEMPTED, the honest
    # answer is not knowing.
    elif grep -qiE 'saved \[|wget|Downloading|HTTP request sent' "$resto" 2>/dev/null; then
        printf 'internet'
    else
        printf 'desconhecido'
    fi
}

# Is this a cause that belongs to the MACHINE rather than to our table? Only
# these hold back a suspicious-translation entry: "the internet was used" and
# "no idea" say nothing about whose fault it is.
t_causa_e_do_ambiente() {
    case "${1:-}" in disco_cheio|sem_rede|relogio|corrompido|dbus|cabextract) return 0 ;; esac
    return 1
}

# token -> sentence, so the token the install loop already computed can reach
# the owner without reading the log a second time. $2 is the log path and only
# the "no idea" sentence uses it: when Tandem cannot say why, it says where to
# look.
t_causa_por_token() {
    case "${1:-}" in
        dbus)        t_msg porque_dbus ;;
        disco_cheio) t_msg porque_disco_cheio ;;
        # %x, not a hard-coded dd/mm/yyyy. The sentence around this date is
        # translated into seven languages and the date order was Brazilian in
        # all of them.
        relogio)     t_msg porque_relogio "$(date +%x)" ;;
        sem_rede)    t_msg porque_sem_rede ;;
        corrompido)  t_msg porque_corrompido ;;
        cabextract)  t_msg porque_cabextract ;;
        internet)    t_msg porque_internet ;;
        *)           t_msg porque_desconhecido "${2:-${LOG:-}}" ;;
    esac
}

t_causa_do_winetricks() {
    t_causa_por_token "$(t_causa_token "$1")" "${2:-}"
}


# ------------------------------------------------------------- the clock
#
# A wrong system clock is the silent failure one step BEFORE the causes above
# name: it breaks TLS, software licensing and Brazilian fiscal software
# (NF-e/NFC-e) without a word, and the usual cause is a dead CMOS battery that
# resets the date on every boot. t_causa_token already RECOGNISES it after the
# fact, from the certificate error a program throws once it has already failed;
# this checks it BEFORE anything fails.
#
# The live read needs systemd/timedatectl (absent in CI, like Wine); the verdict
# is a pure function with its own test, and it never cries wolf on a correct
# clock - see t_relogio_veredito.

# The most recent date Tandem KNOWS about: its own release, read from the
# changelog it ships. "now" cannot honestly be earlier than this - you cannot be
# running a package that was not released yet - and that is the one clock signal
# that never fires on a correct clock. Echoes a Unix timestamp; empty (return 1)
# when no changelog can be read, and then the caller leans on NTP alone.
t_relogio_epoch_conhecido() {
    local linha data
    if [ -n "${TANDEM_CHANGELOG:-}" ] && [ -f "$TANDEM_CHANGELOG" ]; then
        linha="$(grep -m1 '^ -- ' "$TANDEM_CHANGELOG" 2>/dev/null)"
    elif [ -f /usr/share/doc/tandem/changelog.gz ]; then
        linha="$(zcat -- /usr/share/doc/tandem/changelog.gz 2>/dev/null | grep -m1 '^ -- ')"
    fi
    [ -n "$linha" ] || return 1
    # " -- Name <email>  Tue, 18 Aug 2026 20:15:00 +0000" -> the date after ">  "
    data="${linha##*>  }"
    [ -n "$data" ] && [ "$data" != "$linha" ] || return 1
    date -d "$data" +%s 2>/dev/null
}

# Whether network time (NTP) is switched ON, read from `timedatectl show` text on
# stdin. The key is NTP= (the service being enabled), not NTPSynchronized= (which
# is whether it has synced yet). Echoes yes/no or empty when the line is absent.
t_relogio_ntp() {
    sed -n 's/^NTP=//p' | head -1
}

# The whole judgement, pure so the truth table is a test: given "now", the
# release epoch and the NTP flag, name what is wrong - or that nothing is.
#   atrasado            : now is BEFORE this software's release  -> certainly wrong
#   adiantado           : now is absurdly far after it (>30y)    -> certainly wrong
#   sem_hora_automatica : date is plausible but NTP is off       -> advisory only
#   ok                  : plausible date and NTP on
# The two firm verdicts require the epoch; with no epoch only NTP can speak, and
# it can only ever ADVISE, never condemn - refusing to trust a clock on a guess
# would be worse than the defect, the same rule t_prefixo_arquitetura follows.
t_relogio_veredito() {
    local agora="${1:-}" epoch="${2:-}" ntp="${3:-}"
    local trinta_anos=$((30 * 365 * 24 * 3600))
    if [ -n "$agora" ] && [ -n "$epoch" ] &&
       [ "$agora" -eq "$agora" ] 2>/dev/null && [ "$epoch" -eq "$epoch" ] 2>/dev/null; then
        if [ "$agora" -lt "$epoch" ]; then printf 'atrasado\n'; return; fi
        if [ "$agora" -gt "$((epoch + trinta_anos))" ]; then printf 'adiantado\n'; return; fi
    fi
    case "$ntp" in
        no|nao|false|0|off) printf 'sem_hora_automatica\n'; return ;;
    esac
    printf 'ok\n'
}

# The live verdict token on this machine, or "sem_timedatectl" when there is no
# systemd time service to ask. Machine-only (timedatectl), like the Wine reads.
t_relogio_agora_veredito() {
    command -v timedatectl >/dev/null 2>&1 || { printf 'sem_timedatectl\n'; return; }
    timedatectl show >/dev/null 2>&1 || { printf 'sem_timedatectl\n'; return; }
    local agora epoch ntp
    agora="$(date +%s 2>/dev/null)"
    epoch="$(t_relogio_epoch_conhecido)"
    ntp="$(timedatectl show 2>/dev/null | t_relogio_ntp)"
    t_relogio_veredito "$agora" "$epoch" "$ntp"
}

# One line for tandem doctor: the clock, shown only when there is a time service
# to ask. Empty (the caller drops the line) when there is none - a diagnosis
# does not need a line saying it could not look. A firm-wrong verdict points at
# tandem relogio, where the fix lives; anything else is a calm reading.
t_doctor_relogio() {
    local tok
    tok="$(t_relogio_agora_veredito)"
    [ "$tok" = sem_timedatectl ] && return 0
    case "$tok" in
        atrasado|adiantado) t_msg doctor_relogio_errado "$(date '+%c' 2>/dev/null)" ;;
        *)                  t_msg doctor_relogio_ok "$(date '+%c' 2>/dev/null)" ;;
    esac
}

t_appimage_info() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "$TANDEM_LIB/appimageinfo.py" "$1" 2>/dev/null
}

t_jar_info() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "$TANDEM_LIB/jarinfo.py" "$1" 2>/dev/null
}

# The installed Java's feature version: 21, 17, 11, 8...
#
# Two shapes have to be read, because Java changed how it numbers itself in the
# middle: 1.8.0_412 is Java 8 and 21.0.10 is Java 21. Reading only the first
# number turns Java 8 into Java 1 - and then Tandem would announce that a
# program needing Java 8 cannot run on a machine that runs it perfectly well.
t_java_versao() {
    local bruto
    command -v java >/dev/null 2>&1 || return 1
    bruto="$(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$bruto" ] || return 1
    case "$bruto" in
        1.*) printf '%s' "$bruto" | cut -d. -f2 ;;
        *)   printf '%s' "$bruto" | cut -d. -f1 | tr -cd '0-9' ;;
    esac
}

# Does this failure look like the missing FUSE library?
#
# AppImages of the second generation mount themselves, and mounting needs
# libfuse. Ubuntu 22.04 dropped libfuse2 from the default install, so a
# freshly downloaded AppImage on a current Zorin fails with a dlopen message
# and nothing else - the single most common AppImage failure there is, and it
# has a fix that needs no installing at all.
t_falha_fuse() {
    grep -qiE 'libfuse\.so\.2|fusermount|dlopen\(\).*libfuse|/dev/fuse|AppImages? require FUSE|cannot mount' \
         "$1" 2>/dev/null
}

# Where Tandem keeps the menu entries of the AppImages it has run. Its own
# folder, so removing them never touches somebody else's shortcut.
TANDEM_ATALHOS_NATIVOS="$HOME/.local/share/applications"
TANDEM_ICONES_NATIVOS="$HOME/.local/share/icons/hicolor/256x256/apps"

# Puts an AppImage in the menu, by copying the desktop entry the AppImage
# itself carries.
#
# This exists for the same reason "tandem programas" exists: on Wayland, GNOME
# does not re-read the application list, and a program the owner cannot find
# again is a program he has not installed. The Exec line is rewritten to the
# absolute path of the file - the entry inside the AppImage points at a name
# that only exists while it is mounted.
#
# Runs the AppImage's own runtime to extract, which is fine: by this point we
# have already decided to run it, and it is the only way in - reading the
# squashfs would need unsquashfs, which is not installed on a normal machine.
# Extracts files out of an AppImage's payload WITHOUT EXECUTING IT.
#
# This is the project's own rule applied where it was still being broken. Every
# other reader here - peinfo, apkinfo, jarinfo, debinfo, rpminfo - answers by
# reading the file. The AppImage integration alone ran the downloaded binary in
# order to find out its name, which means that if the owner's answer had been
# "do not run this", it had already run.
#
# It costs nothing to do properly, because the offset is already computed from
# the ELF header: unsquashfs reads the payload straight out of the file at that
# offset. Borrowed from Gear Lever, which refuses to execute the payload for the
# same reason.
#
# Falls back to the runtime's own --appimage-extract when squashfs-tools is
# absent - that still works with no FUSE - and says in the log which route it
# took, because "we did not execute it" is a claim that has to be checkable.
t_appimage_extrai() {
    local prog="$1" destino="$2" padrao="$3" info off carga
    info="$(t_appimage_info "$prog")"
    off="$(t_campo "$info" DESLOCAMENTO)"
    carga="$(t_campo "$info" CARGA)"
    if command -v unsquashfs >/dev/null 2>&1 &&
       [ "$carga" = squashfs ] && [ -n "$off" ]; then
        if timeout 120 unsquashfs -o "$off" -d "$destino/lido" -n -q \
               "$prog" "$padrao" >/dev/null 2>&1; then
            t_diz "appimage lido sem executar (unsquashfs em $off): $padrao"
            return 0
        fi
        t_diz "unsquashfs falhou em $padrao; caindo para o runtime do proprio arquivo"
    fi
    [ -x "$prog" ] || return 1
    (
        cd "$destino" 2>/dev/null || exit 1
        # --appimage-extract does not mount anything - the runtime reads the
        # squashfs itself - so this path also works on a machine with no FUSE,
        # which is exactly the machine that most needs the menu entry.
        timeout 120 "$prog" --appimage-extract "$padrao" >/dev/null 2>&1
    )
    return 0
}

# The name the AppImage's author gave it, read without running anything. Used in
# every message about the file, so a failure says "Inkscape não abriu" instead of
# "Inkscape-1.2-x86_64.AppImage não abriu" - the shape appimaged uses, and the
# difference between a sentence about a program and a sentence about a filename.
t_appimage_nome() {
    local prog="$1" tmp dsk nome
    tmp="$(mktemp -d 2>/dev/null)" || return 1
    t_appimage_extrai "$prog" "$tmp" '*.desktop' >/dev/null 2>&1
    dsk="$(find "$tmp" -name '*.desktop' -type f 2>/dev/null | head -1)"
    [ -n "$dsk" ] && nome="$(sed -n 's/^Name=//p' "$dsk" | head -1)"
    rm -rf -- "$tmp"
    [ -n "$nome" ] || return 1
    printf '%s' "$nome"
}

t_integra_appimage() {
    local prog="$1" tmp dsk nome icone destino base
    base="$(basename -- "${prog%.*}")"
    destino="$TANDEM_ATALHOS_NATIVOS/tandem-appimage-$(printf '%s' "$prog" | cksum | tr -d ' ').desktop"
    tmp="$(mktemp -d 2>/dev/null)" || return 1
    t_appimage_extrai "$prog" "$tmp" '*.desktop' >/dev/null 2>&1
    t_appimage_extrai "$prog" "$tmp" '*.png' >/dev/null 2>&1
    t_appimage_extrai "$prog" "$tmp" '*.svg' >/dev/null 2>&1
    dsk="$(find "$tmp" -name '*.desktop' -type f 2>/dev/null | head -1)"
    if [ -z "$dsk" ]; then
        rm -rf -- "$tmp"
        return 1
    fi
    nome="$(sed -n 's/^Name=//p' "$dsk" | head -1)"
    [ -n "$nome" ] || nome="$base"
    icone="$(find "$tmp" -maxdepth 3 \( -name '*.png' -o -name '*.svg' \) -type f 2>/dev/null |
             head -1)"
    if [ -n "$icone" ]; then
        mkdir -p "$TANDEM_ICONES_NATIVOS" 2>/dev/null
        cp -f -- "$icone" "$TANDEM_ICONES_NATIVOS/tandem-$base.${icone##*.}" 2>/dev/null
    fi
    mkdir -p "$TANDEM_ATALHOS_NATIVOS" 2>/dev/null || { rm -rf -- "$tmp"; return 1; }
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "$nome"
        # The comment is the receipt: whoever finds this file later knows who
        # wrote it and which file it points at.
        printf 'Comment=%s\n' "$(t_msg appimage_comentario "$prog")"
        printf 'Exec=%s\n' "$(printf '%s' "$prog" | sed 's/ /\\ /g')"
        # An empty Icon= is not the same as no Icon=: desktop-file-validate
        # complains about the first and accepts the second.
        [ -n "$icone" ] && printf 'Icon=tandem-%s\n' "$base"
        printf 'Terminal=false\n'
        printf 'X-Tandem-AppImage=%s\n' "$prog"
        sed -n 's/^Categories=/Categories=/p' "$dsk" | head -1
        sed -n 's/^StartupWMClass=/StartupWMClass=/p' "$dsk" | head -1
    } > "$destino" 2>/dev/null || { rm -rf -- "$tmp"; return 1; }
    rm -rf -- "$tmp"
    command -v update-desktop-database >/dev/null 2>&1 &&
        update-desktop-database "$TANDEM_ATALHOS_NATIVOS" 2>/dev/null
    t_diz "atalho de AppImage criado: $destino -> $nome"
    printf '%s' "$nome"
    return 0
}

# The menu entries Tandem created for AppImages, one .desktop path per line -
# the same shape as t_atalhos_nossos, so "tandem programas" can list both
# without knowing the difference.
#
# An entry whose AppImage no longer exists is deleted on the way past: the owner
# moved or deleted the download, and a menu item that opens nothing is worse
# than no menu item. Only entries carrying our own X-Tandem-AppImage line are
# touched, so nobody else's shortcut is ever at risk.
t_atalhos_appimage() {
    local d prog
    [ -d "$TANDEM_ATALHOS_NATIVOS" ] || return 0
    for d in "$TANDEM_ATALHOS_NATIVOS"/tandem-appimage-*.desktop; do
        [ -f "$d" ] || continue
        prog="$(sed -n 's/^X-Tandem-AppImage=//p' "$d" | head -1)"
        if [ -z "$prog" ] || [ ! -f "$prog" ]; then
            rm -f -- "$d" 2>/dev/null
            t_diz "atalho de AppImage removido (arquivo sumiu): $d"
            continue
        fi
        printf '%s\n' "$d"
    done
    return 0
}

# The last lines the PROGRAM printed, with Tandem's own lines taken out.
#
# This is the only place in the project that shows raw log back to the owner, so
# it is the only place where the log's own bookkeeping becomes visible. The
# first version of it opened "this is what the program said" with a sentence
# Tandem itself had written one line earlier.
# ------------------------------------- the words of THIS run, and only this run
#
# A marker fixes where a slice STARTS. It cannot keep another process's lines
# out of the MIDDLE of one, and the log is shared: one file per handler, no PID
# in the name, so two .sh files double-clicked a second apart both write
# script.log.
#
# Measured, not feared, and the harm is the worst shape this project has: the
# installer that printed NOTHING AT ALL was reported to its owner as
# "this is what it said:" followed by the other program's progress lines. The
# silent-success guard - the entire point of 4.5 - was defeated at the same
# time, because a slice with somebody else's lines in it is never empty. So the
# owner of a shell installer that did nothing was congratulated, with another
# program's words as the evidence.
#
# The fix is not a better slice. The child's words go to a file of this run's
# own, and the log gets a copy afterwards, so the log stays complete and the
# sentence the owner reads comes from a file nobody else can write.
# Removed on the way out, whatever way out it is. The file this replaced was
# created only on the FAILURE path and deleted three lines later; this one is
# created before the program runs, so every success path became a leak - one
# stray file per double click, for ever. The handlers keep their own `rm` where
# they had one; this is the net under the exits that have none.
T_SAIDAS=""
t_saida_limpa() { [ -n "$T_SAIDAS" ] && rm -f $T_SAIDAS 2>/dev/null; return 0; }

# Register a working file so it goes even when this run does not reach its own
# `rm`. Measured by killing tandem-exe eight seconds into a winetricks: the
# receipt was correctly NOT written and no memory was poisoned - rule 4 held -
# but the working file stayed behind, one per interrupted double click, for
# ever. A shopkeeper who closes the window is not a corner case.
t_apaga_ao_sair() {
    [ -n "${1:-}" ] || return 1
    T_SAIDAS="$T_SAIDAS $1"
    # Only if nobody else owns EXIT. tandem-apk sets its own trap and undoing
    # it would leave a mounted image behind, which is worse than a stray file.
    case "$(trap -p EXIT)" in "") trap t_saida_limpa EXIT ;; esac
}

t_saida_abre() {
    local f
    f="$(mktemp -t tandem-saida-XXXXXX 2>/dev/null)" ||
        f="${TANDEM_TRAVAS:-/tmp}/saida-$$-$1"
    : > "$f" 2>/dev/null
    t_apaga_ao_sair "$f"
    printf '%s' "$f"
}

# Copy into the log and forget the file. Called even when the run failed: the
# log is where the technical detail lives, and losing it would trade one silence
# for another.
t_saida_fecha() {
    [ -f "${1:-}" ] || return 1
    cat "$1" >> "${LOG:-/dev/null}" 2>/dev/null
    return 0
}

# ---------------------------------------------- where the owner said to put it
#
# `tandem backup /media/pendrive/loja.tar.gz` DISCARDED the path in silence and
# wrote to $HOME. Getting the copy off this machine is the whole point of a
# backup, and the owner can unplug the drive believing it is on there. Its two
# siblings - `tandem dados salvar` and `tandem dados restaurar` - already took
# a path, and the second even prints "If you have the file, say where it is",
# so backup and restore were the odd ones out in their own file.
#
# An existing DIRECTORY gets a name of ours inside it, because `tandem backup
# /media/pendrive` is what a person types and tar cannot write over a folder.
# Fails (1) when the folder it would go in does not exist: "I could not save
# it" without saying why leaves a shopkeeper with an unplugged drive and
# nothing to do about it.
# Yes (0), said no (1), NOBODY TO ASK (2).
#
# t_pergunta is GUI-only by design - its first line is `t_tem_gui || return 1`
# - so it answers 1 both for "he clicked cancel" and for "there was no window",
# and CLAUDE.md records that distinction as the one that may never be silent.
# Every handler re-derives the terminal half inline; this is that half written
# once, with the third state handed back so each caller can say the right thing
# about its OWN command rather than share a vague sentence.
#
# The handlers are deliberately not converted here. Their fallbacks end in
# messages of their own - a shell installer that cannot be confirmed is refused,
# a .deb is not - and that is content, not duplication.
# Is the GUI not merely CONFIGURED but REACHABLE? t_tem_gui only asks whether
# DISPLAY/WAYLAND_DISPLAY is set, and a set-but-dead display is exactly how a
# window fails to appear: zenity then exits 1 with no stderr - byte for byte
# what a "No" click looks like - and treating that as "the owner said no" made
# tandem restore give up in silence on a destructive path. The X socket is a
# dependency-free discriminator: a live ":N" display has /tmp/.X11-unix/XN, a
# dead one does not. A "host:N" (remote/TCP) display cannot be probed this way,
# so it is assumed reachable rather than refused - being unable to check means
# going ahead, the same rule the prefix-architecture verdict follows.
t_gui_alcancavel() {
    local n
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        case "$WAYLAND_DISPLAY" in
            /*) [ -S "$WAYLAND_DISPLAY" ] && return 0 ;;
            *)  [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u 2>/dev/null)}/$WAYLAND_DISPLAY" ] && return 0 ;;
        esac
    fi
    if [ -n "${DISPLAY:-}" ]; then
        case "$DISPLAY" in
            :*) n="${DISPLAY#:}"; n="${n%%.*}"
                [ -S "/tmp/.X11-unix/X$n" ] && return 0 ;;
            *)  return 0 ;;
        esac
    fi
    return 1
}

t_pergunta_ou_terminal() {
    local texto="$1" sim="$2" nao="$3" prompt="$4" r
    # Decide UPFRONT whether there is a window to ask in, instead of asking and
    # then guessing what a failure meant. Only a GUI that is present, reachable
    # AND has zenity can carry a question - and only then is a non-yes a real
    # "no" that may be respected silently. Anything else is "nobody was asked",
    # which must fall to the terminal or be reported, never swallowed.
    if t_tem_gui && t_gui_alcancavel && command -v zenity >/dev/null 2>&1; then
        t_pergunta "$texto" "$sim" "$nao" && return 0
        return 1
    fi
    [ -t 0 ] || return 2
    printf '%s\n\n%s' "$texto" "$prompt"
    read -r r
    t_confirmou "$r" && return 0
    return 1
}

t_destino_arquivo() {
    local dest="${1:-}" nome="$2"
    [ -n "$dest" ] || { printf '%s/%s' "$HOME" "$nome"; return 0; }
    [ -d "$dest" ] && dest="${dest%/}/$nome"
    [ -d "$(dirname -- "$dest")" ] || return 1
    printf '%s' "$dest"
    return 0
}

# Is this really a Tandem backup, and is it whole?
#
#   0 = yes    2 = readable but not one of ours    1 = damaged or unreadable
#
# Asked BEFORE anything is deleted. `tandem restore` did `rm -rf` on the prefix
# and only then unpacked, so a truncated archive - a pen drive pulled mid-copy,
# which is how a backup on a pen drive most often ends up truncated - left the
# environment destroyed and half rebuilt. `tar -tzf` exits 2 on one, measured,
# so the damage was detectable the whole time. Allowing an arbitrary path made
# the second half matter too: an archive the owner named by mistake must not be
# unpacked over the environment.
t_backup_valido() {
    local arq="$1" primeiro
    [ -f "$arq" ] || return 1
    primeiro="$(tar -tzf "$arq" 2>/dev/null | head -1)" || return 1
    tar -tzf "$arq" >/dev/null 2>&1 || return 1
    [ -n "$primeiro" ] || return 1
    case "${primeiro%%/*}" in
        "$(basename -- "$TANDEM_PREFIXO_PADRAO")") return 0 ;;
    esac
    return 2
}

# The sha256 of a file, one field, or empty (return 1) when it cannot be taken.
# sha256sum is the one checksum tool this package can lean on - it is what the
# release pipeline proves the .deb with, and what t_memoria_id already uses to
# key the memory. A backup with a checksum beside it can be proven intact on a
# replacement machine after a disk dies; without one, "it opens as an archive"
# is the most that can honestly be said.
t_backup_soma() {
    local arq="$1"
    [ -f "$arq" ] || return 1
    command -v sha256sum >/dev/null 2>&1 || return 1
    sha256sum -- "$arq" 2>/dev/null | cut -d' ' -f1
}

# Verify a backup archive against the checksum written beside it, at "<arq>.sha256".
#
#   0  intacto          the sidecar's hash matches the archive, byte for byte
#   1  corrompido       a sidecar exists and the hash does NOT match - the file
#                       was truncated, altered, or damaged in transit
#   2  sem-soma         no sidecar to check against (a backup made before 4.30,
#                       or a file hand-copied without its checksum). NOT a
#                       failure: it is the honest "I can prove structure, not
#                       integrity", the same rule t_prefixo_arquitetura follows -
#                       a refusal must never rest on a guess.
#   3  sem-ferramenta   this machine has no sha256sum, so nothing can be checked
#
# It compares HASHES, not the filename recorded in the sidecar, so a backup that
# was moved to a pen drive or renamed still verifies - the guarantee is about
# the bytes, and the bytes travel with the file, the name does not.
t_backup_verifica() {
    local arq="$1" lado esperado atual
    [ -f "$arq" ] || return 2
    lado="$arq.sha256"
    [ -f "$lado" ] || return 2
    command -v sha256sum >/dev/null 2>&1 || return 3
    esperado="$(cut -d' ' -f1 < "$lado" 2>/dev/null | head -1)"
    [ -n "$esperado" ] || return 2
    atual="$(t_backup_soma "$arq")" || return 3
    [ "$atual" = "$esperado" ] && return 0
    return 1
}

t_palavras_do_programa() {
    grep -v -e '^$' -e '^aviso: ' -e '^ok: ' -e '^ERRO: ' -e '^>>> ' -e '^===== ' \
         "$1" 2>/dev/null | tail -"${2:-4}"
}

# Would this backup actually restore, checked WITHOUT touching anything - the
# recovery rehearsal. It runs the same pre-flight a real restore does before its
# destructive step, so "it passed here" means the same thing the restore will
# find: the file is there, it opens as a complete Tandem environment, and (since
# 4.30) it matches the checksum saved beside it. This is how a shop proves, the
# day it makes a backup, that the backup would come back on a replacement PC -
# instead of finding out the day the disk dies.
#   sem-arquivo   the file is not there
#   nao-e-backup  it opens, but it is not a Tandem environment
#   danificado    it does not open as an archive at all
#   corrompido    it opens but fails its checksum - it would not restore whole
#   ok            it would restore cleanly
# Structure before integrity, the order the restore itself uses: a checksum
# says nothing about a file that will not even open.
t_restauravel() {
    local arq="$1"
    [ -f "$arq" ] || { printf 'sem-arquivo'; return; }
    t_backup_valido "$arq"
    case $? in
        2) printf 'nao-e-backup'; return ;;
        1) printf 'danificado';   return ;;
    esac
    t_backup_verifica "$arq"
    [ $? -eq 1 ] && { printf 'corrompido'; return; }
    printf 'ok'
}

# ================================================ machine health, at a glance
#
# Tandem already computes a dozen verdicts about the counter - the clock, a
# newer version, disk space, Wine, a web service, a backup to fall back on - but
# each lives in its own command, and a shopkeeper who does not know to ask never
# sees any of them. `tandem saude` gathers them into one reading, worst-first.
#
# It is TRIAGE, not the doctor's dump: doctor prints what EXISTS, unconditionally;
# saude keeps only what needs acting on, and names the fix. The pieces below are
# the parts that can be pure (a verdict from a number), so the thresholds and the
# ordering are truth tables and not accidents of which probe ran first - the same
# discipline as t_relogio_veredito and t_prova_do_run. The live reads (df, the
# service probe) sit in acao_saude, machine-only like the rest.

# Two severities are all a shopkeeper can triage at a glance: something to DO
# now, and something worth KNOWING. acao_saude tags each finding with one as a
# leading number, so a plain numeric sort (t_saude_ordena) puts the urgent thing
# at the top; a healthy check adds no finding at all. The numbers live where they
# are used - in acao_saude - rather than as globals here that nothing in this
# library reads.

# Free disk, from the free-KB of $HOME. A counter that fills its disk cannot
# save a sale or finish an install, and ": >> file" even SUCCEEDS on a full
# disk (the log-probe lesson), so this is worth catching before it bites.
#   cheio     < ~500 MB free  -> a problem now
#   apertado  < ~2 GB free    -> worth knowing
#   ok        otherwise
# Pure: the number comes in, the verdict comes out.
t_saude_disco_veredito() {
    local kb="${1:-}"
    [ -n "$kb" ] && [ "$kb" -eq "$kb" ] 2>/dev/null || { printf 'desconhecido'; return; }
    [ "$kb" -lt 500000 ]  && { printf 'cheio';    return; }
    [ "$kb" -lt 2000000 ] && { printf 'apertado'; return; }
    printf 'ok'
}

# The recovery-readiness verdict, the one 4.30 made possible: is there a backup
# to come back from, is it recent, and does it still verify?
#   sem-backup   no backup has ever been made here    -> a problem (a dead disk
#                loses everything, and there is nothing to restore)
#   corrompido   the newest backup fails its checksum  -> a problem (it is there
#                but it will not restore)
#   velho        the newest backup is over ~30 days old -> worth knowing
#   ok           a recent backup that verifies
# Pure: newest-backup epoch (empty if none), "now", and t_backup_verifica's code.
t_saude_backup_veredito() {
    local novo="${1:-}" agora="${2:-}" estado="${3:-}"
    [ -n "$novo" ] || { printf 'sem-backup'; return; }
    # $estado is a t_restauravel token, not a bare checksum result: it condemns a
    # backup that would not actually come back - structurally broken (danificado /
    # nao-e-backup) OR checksum-mismatched (corrompido) - so a 0-byte or truncated
    # archive is caught even with no sidecar beside it. 'ok'/'sem-*' fall through:
    # a structurally sound backup with no checksum is not condemned, only unproven.
    case "$estado" in
        corrompido|danificado|nao-e-backup|sem-arquivo)
            printf 'corrompido'; return ;;
    esac
    if [ -n "$agora" ] && [ "$novo" -eq "$novo" ] 2>/dev/null &&
       [ "$agora" -eq "$agora" ] 2>/dev/null &&
       [ "$((agora - novo))" -gt "$((30 * 24 * 3600))" ]; then
        printf 'velho'; return
    fi
    printf 'ok'
}

# Order health findings worst-first, whatever order they were gathered in. Pure,
# so worst-first is a property a test pins rather than an accident of probe
# order - the same reason t_prova_do_run is a function and not four inline lines.
# stdin is "<rank><TAB><sentence>" lines; stdout is the sentences, worst first,
# rank stripped, stable within a rank.
t_saude_ordena() {
    sort -t "$(printf '\t')" -k1,1n -s | cut -f2-
}

# The newest Tandem backup in the home folder, as a Unix epoch, or empty
# (return 1) when there is none. The date is in the name
# (tandem-backup-YYYY-MM-DD-HHMM.tar.gz), which is what the owner reads and what
# survives a copy that resets the file's mtime; the mtime is the fallback for a
# renamed file. Machine-facing (it reads $HOME), so it lives beside the verdict
# rather than in it.
t_saude_backup_recente() {
    local arq nome data epoch
    arq="$(ls -1t "$HOME"/tandem-backup-*.tar.gz 2>/dev/null | head -1)"
    [ -n "$arq" ] || return 1
    nome="$(basename -- "$arq")"
    data="$(printf '%s\n' "$nome" | sed -n 's/^tandem-backup-\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p')"
    if [ -n "$data" ]; then
        epoch="$(date -d "$data" +%s 2>/dev/null)"
    fi
    [ -n "$epoch" ] || epoch="$(stat -c %Y -- "$arq" 2>/dev/null)"
    [ -n "$epoch" ] || return 1
    printf '%s\t%s\n' "$epoch" "$arq"
}

# Proactive breakage awareness: 4.28 records the Wine each program last opened
# cleanly under (VERSAO_WINE in its memory file) and names the change at the next
# FAILURE - which for a POS is a customer already waiting. This reads all those
# recorded versions and, if the CURRENT Wine differs from what a remembered
# program worked under, returns the one version worth naming, so saude can say it
# BEFORE the program is opened. Pure: the recorded working Wines arrive on stdin,
# one per line (blank lines and the "-" of no-Wine tolerated), the current Wine
# is $1, and it prints the first that genuinely differs - by the SAME guard 4.28
# uses (t_wine_mudou_desde), so "still the Wine it worked under" and "no Wine at
# all" both say nothing - or prints nothing and returns 1. No file I/O, so the
# decision is a truth table a test injects; the memory read stays in the caller,
# the split every other saude verdict follows.
t_saude_wine_citar() {
    local agora="${1:-}" antes
    while IFS= read -r antes; do
        if t_wine_mudou_desde "$antes" "$agora"; then
            printf '%s\n' "$antes"
            return 0
        fi
    done
    return 1
}

# --------------------------------------------------- messages, in Portuguese

t_texto_java_falta() {
    t_msg java_falta
}

t_texto_java_antigo() {
    t_msg java_antigo "$1" "$2"
}

t_texto_jar_biblioteca() {
    t_msg jar_e_biblioteca
}

t_texto_jar_agente() {
    t_msg jar_e_agente
}

t_texto_jar_javafx() {
    t_msg jar_precisa_javafx
}

t_texto_appimage_incompleto() {
    t_msg appimage_incompleto "$(basename -- "$1")"
}

t_texto_appimage_arch() {
    t_msg appimage_arch "$1" "$2"
}

t_texto_appimage_fuse() {
    t_msg appimage_fuse
}

# --------------------------------------------------- packages of the system
#
# The formats a Linux distribution uses to install software. They fail on a
# double click for a third set of reasons - not Wine, not the execute bit - and
# the reasons are all announced in the vocabulary of a package manager.
#
# The single most important fact here, established by measurement: "apt-get
# install -s" runs WITHOUT ROOT and gives apt's own authoritative verdict,
# including which dependency cannot be satisfied. So the whole diagnosis happens
# before the owner is ever asked for a password. Nothing else in this project
# gets to be that certain that early.

t_deb_info() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "$TANDEM_LIB/debinfo.py" "$1" 2>/dev/null
}

t_rpm_info() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "$TANDEM_LIB/rpminfo.py" "$1" 2>/dev/null
}

# This system's package architecture, in dpkg's vocabulary (amd64, arm64, i386).
t_arch_sistema() {
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --print-architecture 2>/dev/null && return 0
    fi
    case "$(uname -m 2>/dev/null)" in
        x86_64) printf 'amd64' ;;
        aarch64) printf 'arm64' ;;
        i?86) printf 'i386' ;;
        *) printf '%s' "$(uname -m 2>/dev/null)" ;;
    esac
}

# Can this machine install a package built for this architecture? "all" is
# architecture-independent; a foreign architecture counts only if dpkg was told
# about it, which is the same mechanism that makes 32-bit Wine possible.
t_deb_arch_serve() {
    local a="$1" minha
    [ -z "$a" ] && return 0
    [ "$a" = all ] && return 0
    minha="$(t_arch_sistema)"
    [ "$a" = "$minha" ] && return 0
    command -v dpkg >/dev/null 2>&1 &&
        dpkg --print-foreign-architectures 2>/dev/null | grep -qx -- "$a" && return 0
    return 1
}

# Is this package already installed, and in which version?
t_deb_instalado() {
    local nome="$1" estado
    command -v dpkg-query >/dev/null 2>&1 || return 1
    estado="$(dpkg-query -W -f='${db:Status-Status} ${Version}' -- "$nome" 2>/dev/null)"
    case "$estado" in
        installed\ *) printf '%s' "${estado#installed }"; return 0 ;;
    esac
    return 1
}

# apt's own simulation of installing this file, as the current user. No lock is
# taken and nothing is written, so this is safe to run before asking anything.
t_apt_simula() {
    command -v apt-get >/dev/null 2>&1 || return 1
    LC_ALL=C timeout 120 apt-get install -s --no-install-recommends -- "$1" 2>&1
}

# The dependency names apt says it cannot satisfy, one per line.
#
# Read out of apt's own words rather than resolved here: reimplementing
# dependency resolution in shell would be a second opinion that is wrong
# whenever it disagrees with the only one that matters.
t_deb_naoinstalaveis() {
    printf '%s\n' "$1" |
        sed -n 's/.*Depends: \([^ ]*\) but it is not installable.*/\1/p
                s/.*Depends: \([^ ]*\) but it is not going to be installed.*/\1/p' |
        sort -u | grep -v '^$'
}

# Does this name look like a library version welded to a distribution release?
#
# This is the difference between two verdicts that look identical in apt's
# output. "libssl1.1 is not installable" means the package was built for an
# older Ubuntu and will never install here; "acme-driver is not installable"
# means it needs a repository the machine does not have. The first has no fix
# and the second does, and telling the owner the wrong one wastes his afternoon.
t_versao_de_sistema() {
    case "$1" in
        libssl1.*|libssl0.*|libcrypto*|libicu[0-9]*|libpython3.[0-9]*|python3.[0-9]*)
            return 0 ;;
        libwebkit2gtk-4.[0-9]*|libwebkitgtk-*|libgtk[0-9]*|libqt[0-9]*|libboost*[0-9].[0-9]*)
            return 0 ;;
        libncurses[0-9]*|libreadline[0-9]*|libtinfo[0-9]*|libdb[0-9].[0-9]*)
            return 0 ;;
        # The general shape: a name that ends in a version number, which is how
        # a distribution pins an ABI. A plain program name does not look like
        # this, and the ones that do (libreoffice7.x) are still release-bound.
        lib*[0-9]) return 0 ;;
        lib*[0-9].[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Is there a package with this name in the machine's own repositories?
# Answers for virtual packages too, which are provided by another package and
# have no version of their own.
t_apt_candidato() {
    local nome="$1" c
    command -v apt-cache >/dev/null 2>&1 || return 1
    c="$(LC_ALL=C apt-cache policy -- "$nome" 2>/dev/null |
         sed -n 's/^  Candidate: //p' | head -1)"
    case "$c" in
        ''|'(none)') ;;
        *) printf '%s' "$c"; return 0 ;;
    esac
    LC_ALL=C apt-cache showpkg -- "$nome" 2>/dev/null |
        grep -q 'Reverse Provides' && { printf 'virtual'; return 0; }
    return 1
}

# Why did apt or dpkg fail? One sentence, in Portuguese, from their own words.
#
# Each line here is a message that was PRODUCED on a real machine and copied
# from the terminal, not one imagined from documentation. The order is most
# specific first: several of these appear together, and the first one is the
# cause while the rest are consequences.
t_causa_apt() {
    local log="$1"
    # The lock has to be tested FIRST: it shows up together with the broken
    # packages line, and it is the cause while the other is the consequence.
    if grep -qE 'Could not get lock|frontend lock was locked|is another process using it' \
            "$log" 2>/dev/null; then
        t_msg apt_trava; return 0
    fi
    if grep -q 'does not match system' "$log" 2>/dev/null; then
        t_msg apt_arch; return 0
    fi
    if grep -q 'No space left on device' "$log" 2>/dev/null; then
        t_msg porque_disco_cheio; return 0
    fi
    if grep -q 'trying to overwrite' "$log" 2>/dev/null; then
        t_msg apt_sobrescreve; return 0
    fi
    if grep -qE 'Temporary failure resolving|Could not resolve|Network is unreachable|Connection timed out' \
            "$log" 2>/dev/null; then
        t_msg apt_sem_internet; return 0
    fi
    if grep -qE 'is not valid yet|Release file.*not valid|certificate' "$log" 2>/dev/null; then
        # %x, not a hard-coded dd/mm/yyyy: the sentence around this date is
        # translated into seven languages and the date ORDER was Brazilian in
        # all of them, so an en, zh_CN, hi or ar reader got a translated
        # sentence ending in a date written the way only Brazil writes it.
        t_msg porque_relogio "$(date +%x)"; return 0
    fi
    if grep -qE 'NO_PUBKEY|not signed|GPG error' "$log" 2>/dev/null; then
        t_msg apt_sem_assinatura; return 0
    fi
    if grep -qE 'dependency problems|unmet dependencies|held broken packages' "$log" 2>/dev/null; then
        t_msg apt_faltam_componentes; return 0
    fi
    return 1
}

# The .desktop files the system offers, one path per line. Used before and after
# an install, to say WHERE the program went - the same service "tandem programas"
# provides for Windows software, and for the same reason: on Wayland the menu
# does not refresh, so a program the owner cannot find is a program he does not
# have.
#
# It looked in TWO directories until 4.11, and a snap and a flatpak land in
# neither - so the promise above has been quietly unkept for three of the four
# package managers since 3.8, and `tandem-snap`'s "look in the menu for" line
# had never once appeared on anybody's screen. snapd exports to
# /var/lib/snapd/desktop/applications; flatpak to
# /var/lib/flatpak/exports/share/applications for the system and to
# ~/.local/share/flatpak/exports/share/applications for the user.
#
# XDG_DATA_DIRS is asked first, because it is the right answer and it picks up
# whatever else a distribution invents. It is NOT enough on its own, and that
# is measured rather than assumed: in this session's own container both
# XDG_DATA_DIRS and XDG_DATA_HOME are EMPTY while all three directories above
# exist and hold files - which is exactly the shape of a program started from a
# file manager rather than a login shell. So the three are named explicitly as
# well, and the list is deduplicated because on a normal desktop they overlap.
t_atalhos_do_sistema() {
    local dirs="" d visto=""
    for d in ${XDG_DATA_DIRS:+${XDG_DATA_DIRS//:/ }} \
             "${XDG_DATA_HOME:-$HOME/.local/share}" \
             /usr/share /usr/local/share \
             /var/lib/snapd/desktop \
             /var/lib/flatpak/exports/share \
             "$HOME/.local/share/flatpak/exports/share"; do
        [ -n "$d" ] || continue
        d="${d%/}/applications"
        case " $visto " in *" $d "*) continue ;; esac
        visto="$visto $d"
        [ -d "$d" ] || continue
        dirs="$dirs $d"
    done
    [ -n "$dirs" ] || return 0
    # shellcheck disable=SC2086
    find $dirs -maxdepth 1 -name '*.desktop' -type f 2>/dev/null | sort
}

t_anuncia_atalhos_do_sistema() {
    local antes="$1" novos nomes
    novos="$(comm -13 <(printf '%s\n' "$antes") <(t_atalhos_do_sistema) 2>/dev/null)"
    [ -n "$novos" ] || return 1
    nomes="$(printf '%s\n' "$novos" | while IFS= read -r d; do
        [ -f "$d" ] || continue
        sed -n 's/^Name=//p' "$d" | head -1
    done | grep -v '^$' | head -8)"
    [ -n "$nomes" ] || return 1
    printf '%s' "$nomes"
    return 0
}

# A .flatpakref and a .flatpakrepo are both plain INI files. One field out of
# one, without needing flatpak installed to read it.
t_flatpak_campo() {
    local arq="$1" chave="$2"
    [ -f "$arq" ] || return 1
    sed -n "s/^[[:space:]]*${chave}[[:space:]]*=[[:space:]]*//p" "$arq" | head -1
}

# Does this shell script look like a program INSTALLER, or like a script?
#
# The distinction decides what to offer the owner. A self-extracting installer -
# makeself, shar, a vendor blob - is meant to be run, and running it is the
# whole point of the double click. A plain script is much more likely something
# he wants to LOOK at, and offering to execute it first would be teaching a
# habit that gets people's machines broken.
t_script_instalador() {
    local f="$1"
    head -c 8192 -- "$f" 2>/dev/null |
        grep -qE 'makeself|Makeself|_ARCHIVE|^# This script was generated|shar|sfx|self-extract' &&
        return 0
    # A tiny script is a script. A megabyte of "shell script" is a payload with
    # a shell header, which is exactly what a vendor installer is.
    [ "$(stat -c%s -- "$f" 2>/dev/null || echo 0)" -gt 262144 ] && return 0
    return 1
}

# ------------------------------------------- messages, in Portuguese

t_texto_deb_versao_errada() {
    t_msg deb_versao_errada "$(printf '%s
' "$1" | sed 's/^/  - /')"
}

t_texto_deb_falta_repositorio() {
    t_msg deb_falta_repositorio "$(printf '%s
' "$1" | sed 's/^/  - /')"
}

t_texto_deb_arch() {
    t_msg deb_arch "$1" "$2"
}

t_texto_rpm() {
    local nome="$1" dist="$2" equivalente="$3"
    t_msg rpm_outra_familia
    [ -n "$dist" ] && { printf '
'; t_msg rpm_feito_por "$dist"; }
    printf '

'
    t_msg rpm_nao_converte
    if [ -n "$equivalente" ]; then
        printf '

'; t_msg rpm_boa_noticia "$equivalente"
    elif [ -n "$nome" ]; then
        printf '

'; t_msg rpm_procure_deb "$(t_msg rpm_do_nome "$nome")"
    fi
    printf '
'
}

t_texto_script_perigo() {
    t_msg script_perigo "$(basename -- "$1")"
}

# ------------------------------------------------- sending, with permission
#
# Up to here the community list only ever pulled. That was the right default and
# it had one measurable consequence: lista/lista.tsv is EMPTY. The mechanism
# worked and collected nothing, because contributing meant reading a line off a
# screen, copying it, opening a browser, creating an account on a site the owner
# has never heard of, and pasting it into an issue. A shop owner does none of
# that, and the project's own queue lists "fill the community list" as item one.
#
# So sending is automated - and the reason it can be is that the expensive half
# was already built and tested. t_lista_registro produces eight fields and
# t_lista_vaza REFUSES to emit them if a filename, a path, a username, a machine
# name or an IP address appears anywhere in the line. There is nothing to
# anonymise at send time because there was never anything identifying in it.
#
# Three rules that do not bend:
#
#   Off until the owner says otherwise, once, in his own language, looking at the
#   actual line that would leave his machine. Not "anonymous usage data" - the
#   eight fields, printed.
#
#   The sieve runs AGAIN at send time. Checking once at build time would trust
#   that nothing touched the queue file in between, and a queue file is exactly
#   the kind of thing that gets edited by hand.
#
#   Nothing blocks a double click. Sending is best-effort, in the background, and
#   a machine with no internet queues the line and forgets about it.

TANDEM_CONFIG="$HOME/.config/tandem/configuracao.txt"
TANDEM_FILA="${TANDEM_FILA:-$TANDEM_ESTADO/enviar-fila.tsv}"
# Where a contribution is posted. This was empty for five versions because an
# address means somebody hosts it and answers for the data, which is a decision
# with a cost rather than a line of code. It has one now, and the receiving end
# is in THIS REPOSITORY - api/lista.js - so the code that takes a shop's data is
# as readable as the code that sends it.
#
# What arrives there is validated again from scratch, because a check that runs
# on the sender's machine protects the sender and promises nothing to anybody
# else. Nothing published itself: .github/workflows/lista.yml rebuilds the list
# and opens a pull request.
#
# The host name is Vercel's generated one. Renaming the project there would
# break this for every installed copy - not silently, because a name that does
# not resolve is not a 2xx and the line stays in the queue, but it would break.
# A custom domain is what fixes that, and it costs money nobody has spent.
# The default has NO colon before the dash on purpose. "${VAR-default}" fills in
# only when the variable is UNSET; an explicitly empty value stays empty. That is
# the difference between the shipped state (unset -> this address, sends) and an
# owner who exports TANDEM_LISTA_ENVIO="" to opt out by environment (empty ->
# stays empty, sends nowhere). With the colon form, empty would silently become
# the default and there would be no way to disable it by the variable at all.
TANDEM_LISTA_ENVIO="${TANDEM_LISTA_ENVIO-https://tandem-psi-ten.vercel.app/api/lista}"
# A machine cannot become a firehose, whatever it decides to install.
TANDEM_ENVIO_POR_DIA="${TANDEM_ENVIO_POR_DIA:-20}"
# ...and that cap only ever counted the lines that WENT. A failure cost
# nothing, so a machine with no route to the address retried every queued line
# on every run, for ever, twenty seconds of timeout each. A hundred queued
# lessons on a shop's broken connection is over half an hour of a background
# process that was never going to succeed, started again every time somebody
# opens a program. After this many refusals in a row the pass stops: the first
# failure already told it what the second one would say.
TANDEM_ENVIO_FALHAS="${TANDEM_ENVIO_FALHAS:-3}"
# And the queue then waits, rather than trying again on the next double click.
TANDEM_ENVIO_ESPERA="${TANDEM_ENVIO_ESPERA:-3600}"

# Percent-encoding, for putting a record into a prefilled form URL. The record
# is TAB separated and a raw tab in a URL is not a tab by the time it arrives.
t_url_escapa() {
    local b
    # A "for" over the unquoted substitution, not a "while read": the last line
    # of od's output has no trailing newline, so read returns non-zero on it and
    # the loop body never runs for the final byte. Measured - every escaped
    # string came out one character short.
    for b in $(printf '%s' "$1" | od -An -tx1 -v); do
        case "$b" in
            # Unreserved characters only: A-Z a-z 0-9 - . _ ~ . Everything else
            # is encoded, including the slash, which the record should never
            # carry anyway because t_lista_vaza refuses one.
            2[dDeE]|3[0-9]|4[1-9a-fA-F]|5[0-9aAfF]|6[1-9a-fA-F]|7[0-9aAeE])
                printf '%b' "\\x$b" ;;
            *) printf '%%%s' "$(printf '%s' "$b" | tr 'a-f' 'A-F')" ;;
        esac
    done
}

t_config_le() {
    [ -f "$TANDEM_CONFIG" ] || return 1
    local v; v="$(sed -n "s/^$1=//p" "$TANDEM_CONFIG" | tail -1)"
    [ -n "$v" ] || return 1
    printf '%s' "$v"
}

# ONE FILE, AND MORE THAN ONE WRITER. This is a read-modify-write on a file
# every command touches, and the temp file it went through was named
# "$TANDEM_CONFIG.novo" - FIXED, not per process. Two writers at once both
# truncate that same name and both move it over the config, so their output
# interleaves.
#
# Measured, four concurrent writers of sixty keys each: the file came out with
# CHAVE_A and CHAVE_C present TWICE, each holding a different value. And
# t_config_le takes `tail -1`, so the reader then picks whichever duplicate
# landed last - which in that run was the OLDER value.
#
# It is not a corner: t_lista_talvez_atualiza stamps LISTA_DIA from a DETACHED
# background process that tandem-exe spawns on the way to opening a program,
# while the foreground is free to write something else. Two double clicks make
# it likelier, not possible.
#
# What is in this file makes it worse than untidy. ENVIO_HOJE and
# ENVIO_ESPERA_ATE are the caps that stop a machine with no route retrying
# every queued line all day - the defect the changelog for 4.x calls "a cap on
# successes is not a cap". And RECEBER and ENVIAR are the owner's own on/off
# choice for the community list: a duplicate read from the wrong line can turn
# back on something he turned off, which is consent, not a setting.
#
# Per-process temp name AND a lock, because the temp name alone only stops the
# interleaving - two complete writes would still race on the move and one key
# would vanish. The lock is best-effort by the same rule the prefix lock
# follows: a lock that cannot be CREATED (full disk, read-only home) must not
# be mistaken for a lock that is taken. Without it the write goes ahead
# unserialised, which is what happens today and is better than refusing to
# save a setting.
t_config_grava() {
    local chave="$1" valor="$2" tmp trava
    mkdir -p "$(dirname -- "$TANDEM_CONFIG")" 2>/dev/null || return 1
    [ -f "$TANDEM_CONFIG" ] || {
        printf '# %s\n' "$(t_msg arq_config_cab)" > "$TANDEM_CONFIG"; }
    tmp="$TANDEM_CONFIG.novo.$$"
    trava="${TANDEM_TRAVAS:-$(dirname -- "$TANDEM_CONFIG")}/config.lock"
    if { exec 6> "$trava"; } 2>/dev/null; then
        flock -w 10 6 2>/dev/null || :
    fi
    {
        grep -E '^(#|[A-Z_]+=)' "$TANDEM_CONFIG" 2>/dev/null | grep -v "^$chave="
        printf '%s=%s\n' "$chave" "$valor"
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$TANDEM_CONFIG"
    local c=$?
    rm -f "$tmp" 2>/dev/null
    { exec 6>&-; } 2>/dev/null
    return $c
}

# Has the owner decided? "sim", "nao", or failure when he was never asked.
# ON BY DEFAULT since 4.2, and that is a reversal of the previous design.
#
# It was born off, and the owner decided once, looking at the whole line. That
# was the more careful arrangement and it had a measurable result: the list was
# EMPTY. A default nobody changes is a decision made by the default, so the
# choice here is between a list that does not exist and a transmission the owner
# did not initiate. The architect chose the second.
#
# What makes that defensible rather than merely convenient is the two things
# around it, and neither is optional:
#   - the line cannot carry anything personal. t_lista_vaza refuses to emit a
#     record holding a filename, a path, a user name, a machine name or an IP,
#     and it runs twice - when the line is built and again at send time.
#   - the owner is TOLD, twice: dpkg prints it at install, and the first run
#     says it in its own window. Notice is what turns a default into a choice.
# Turning it off is one command and it is in both messages.
t_envio_ligado() {
    case "$(t_config_le ENVIAR 2>/dev/null)" in
        sim) return 0 ;;
        nao) return 1 ;;
        *)   return 0 ;;   # undecided means on
    esac
}

t_envio_decidido() {
    case "$(t_config_le ENVIAR 2>/dev/null)" in sim|nao) return 0 ;; esac
    return 1
}

t_envio_define() {
    t_config_grava ENVIAR "$1"
    t_config_grava ENVIAR_DESDE "$(date +%F)"
    t_config_grava ENVIAR_VERSAO "$TANDEM_VERSAO"
    t_diz "envio automatico definido para: $1"
}

# The consent text. It shows the line, because a permission dialog that
# describes a payload instead of displaying it is asking to be trusted rather
# than asking a question.
t_texto_pedir_envio() {
    local reg="$1"
    t_msg pedir_envio "$reg"
    # If the machine has somebody else's Wine profile on it, it is plausibly a
    # work machine, and the person clicking may not be the person who decides
    # what leaves it. Saying so is not a veto - it is the information he needs.
    if [ -s "$TANDEM_PROTEGIDOS" ]; then
        printf '

'; t_msg pedir_envio_maquina_de_trabalho
    fi
    printf '
'
}

# Queues one record. Never sends from here: a double click is not the place to
# wait for a network.
t_envio_enfileira() {
    local reg="$1"
    [ -n "$reg" ] || return 1
    t_lista_vaza "$reg" && { t_diz "fila: registro recusado pelo filtro"; return 1; }
    mkdir -p "$(dirname -- "$TANDEM_FILA")" 2>/dev/null || return 1
    # The same lesson twice is one lesson.
    grep -qxF -- "$reg" "$TANDEM_FILA" 2>/dev/null && return 0
    printf '%s\n' "$reg" >> "$TANDEM_FILA" 2>/dev/null || return 1
    t_diz "fila: registro guardado para envio"
    return 0
}

t_envio_pendentes() {
    # awk and not "grep -c || echo 0": on an EMPTY file grep prints 0 and then
    # exits 1, so the fallback fires too and the count comes out as "0" followed
    # by "0". Which is what "tandem enviar" showed the owner.
    [ -f "$TANDEM_FILA" ] || { printf '0'; return 0; }
    awk 'END { print NR + 0 }' "$TANDEM_FILA" 2>/dev/null || printf '0'
}

# How many lines have actually LEFT this machine, ever. Same arithmetic, and
# the same trap: grep -c on an empty file prints 0 and exits 1.
t_envio_ja_enviados() {
    [ -f "$TANDEM_FILA.enviados" ] || { printf '0'; return 0; }
    awk 'END { print NR + 0 }' "$TANDEM_FILA.enviados" 2>/dev/null || printf '0'
}

# Sends what is queued, best effort. PRINTS the number sent, and RETURNS why:
# 0 nothing to report, 3 the server refused everything it was offered, 4 the
# queue is inside the wait after a failed pass, 5 another pass already has it.
# The count goes on stdout and the reason in the exit status because the caller
# reads this through a command substitution, which is a subshell - a variable
# set here would not survive it.
#
# "forcado" as the first argument skips the wait. The wait exists to stop
# AUTOMATIC retries on every double click; an owner who typed "tandem enviar
# agora" has asked, and answering a direct request with silence for an hour is
# the failure this project is built against.
#
# Every line is put through the sieve again here. Checking only when the record
# was built would trust that nothing touched the queue in between, and a
# plain-text file in the state directory is exactly the kind of thing that gets
# edited by hand.
#
# The argument really is passed - by "tandem enviar agora", which shellcheck
# lints as a separate file and therefore cannot see from here.
# shellcheck disable=SC2120
t_envio_envia() {
    local forcado="${1:-}" enviados=0 falhas=0 hoje contador reg resto resposta
    local agora espera trava
    t_envio_ligado || return 0
    [ -n "$TANDEM_LISTA_ENVIO" ] || return 0
    [ -s "$TANDEM_FILA" ] || return 0
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 0

    # One pass at a time. This is spawned detached every time a program is
    # confirmed, and "tandem enviar agora" starts one too - so two passes over
    # the same queue were entirely possible. Both truncate the same
    # ".resto" file and both then move it over the queue, which does not merely
    # send a line twice: the truncation lands in the middle of the other pass's
    # appends and the lines already written are gone. The queue is the only
    # copy of a lesson that has not left yet.
    # The braces around the exec are the lesson from tandem-exe, and so is
    # carrying on unlocked when the file cannot be created at all: an
    # impossible lock and a busy lock are different cases.
    trava="$TANDEM_TRAVAS/envio.lock"
    if { exec 6> "$trava"; } 2>/dev/null; then
        flock -n 6 || { t_diz "envio: outro envio ja esta em andamento"; return 5; }
    else
        t_diz "nao consegui criar a trava em $trava; seguindo sem ela"
    fi

    # A pass that failed does not get to try again on the next double click.
    agora="$(date +%s)"
    espera="$(t_config_le ENVIO_ESPERA_ATE 2>/dev/null)"
    case "$espera" in ''|*[!0-9]*) espera=0 ;; esac
    if [ "$agora" -lt "$espera" ] && [ "$forcado" != forcado ]; then
        t_diz "envio: a tentativa anterior falhou; esperando (faltam $((espera - agora))s)"
        { exec 6>&-; } 2>/dev/null
        return 4
    fi

    hoje="$(date +%F)"
    [ "$(t_config_le ENVIO_DIA 2>/dev/null)" = "$hoje" ] &&
        contador="$(t_config_le ENVIO_HOJE 2>/dev/null)" || contador=0
    case "$contador" in ''|*[!0-9]*) contador=0 ;; esac

    resto="$TANDEM_FILA.resto"
    : > "$resto" 2>/dev/null || return 0
    while IFS= read -r reg; do
        [ -n "$reg" ] || continue
        if t_lista_vaza "$reg"; then
            # PARKED, not deleted. This used to "continue" without writing the
            # line anywhere, and the file being written replaces the queue - so
            # a record the sieve refused was destroyed, with one log line, and
            # the lesson it carried went with it. The sieve exists to stop a
            # line LEAVING the machine, which is a different thing from being
            # allowed to erase it.
            printf '%s\n' "$reg" >> "$resto"
            t_diz "envio: linha retida pelo filtro (guardada, nao enviada)"
            continue
        fi
        if [ "$contador" -ge "$TANDEM_ENVIO_POR_DIA" ] ||
           [ "$falhas" -ge "$TANDEM_ENVIO_FALHAS" ]; then
            printf '%s\n' "$reg" >> "$resto"
            continue
        fi
        t_envio_posta "$reg"; resposta=$?
        if [ "$resposta" = 0 ]; then
            # WRITTEN DOWN. Until 4.11 this was the only branch of the three
            # that destroyed the line: the sieve refusal and the 4xx refusal
            # both park theirs under an explicit rule, and a line that actually
            # LEFT was the one thing the machine kept no record of.
            #
            # That is not tidiness, it is the rule section 3 of docs/IDEAS.md
            # rejected telemetry on - "nothing the owner cannot see and cannot
            # delete". Sending is on by default and defended by a notice; a
            # year later, "what has this machine sent about my shop?" had no
            # answer ON the machine, and that is the question a shopkeeper, or
            # whoever audits him, actually asks.
            #
            # The month and not the day, for the same reason the record itself
            # carries only the month: a date with a day identifies.
            printf '%s\t%s\n' "$(date +%Y-%m)" "$reg" \
                >> "$TANDEM_FILA.enviados" 2>/dev/null
            enviados=$((enviados+1)); contador=$((contador+1)); falhas=0
        elif [ "$resposta" = 2 ]; then
            # Refused for good. It leaves the queue so it cannot block the
            # lines behind it, and it is PARKED rather than deleted - the same
            # rule the sieve refusal follows. Stopping a line from leaving is a
            # different power from being allowed to destroy it, and a lesson
            # nobody can read afterwards is a lesson lost either way.
            printf '%s\n' "$reg" >> "$TANDEM_FILA.recusados" 2>/dev/null
            t_diz "envio: linha movida para $TANDEM_FILA.recusados"
        else
            falhas=$((falhas+1))
            printf '%s\n' "$reg" >> "$resto"
        fi
    done < "$TANDEM_FILA"
    mv -f "$resto" "$TANDEM_FILA" 2>/dev/null
    t_config_grava ENVIO_DIA "$hoje"
    t_config_grava ENVIO_HOJE "$contador"
    if [ "$falhas" -ge "$TANDEM_ENVIO_FALHAS" ]; then
        t_config_grava ENVIO_ESPERA_ATE "$((agora + TANDEM_ENVIO_ESPERA))"
        t_diz "envio: $falhas recusas seguidas; a fila espera ${TANDEM_ENVIO_ESPERA}s"
    elif [ "$enviados" -gt 0 ]; then
        # The route works. Whatever it was waiting for is over.
        t_config_grava ENVIO_ESPERA_ATE 0
        t_diz "envio: $enviados linha(s) enviada(s)"
    fi
    { exec 6>&-; } 2>/dev/null
    printf '%s' "$enviados"
    # "It refused" is only true if it was actually offered something. A pass
    # that sent nothing because the daily ceiling was already spent is not a
    # server problem, and saying so would send the owner looking for a defect
    # somewhere neither he nor anybody else can reach.
    [ "$enviados" = 0 ] && [ "$falhas" -gt 0 ] && return 3
    return 0
}

# Posts one line, and only counts it as sent when the server said so.
#
# The status code is read explicitly because of the one answer that used to be
# read backwards: a REDIRECT. curl with no -L does not follow one and exits 0,
# so a 301 or a 302 was ticked off as delivered - and the queue is rewritten
# from what did not go, which means the lesson was deleted from the only place
# it existed. An endpoint that has moved is exactly the shape of thing that
# answers 301, so this was not a theoretical case.
#
# The redirect is NOT followed, and that is a decision rather than an
# omission: the target of a redirect is chosen by whatever answered, not by
# anybody here. A record exists precisely because it carries nothing personal,
# and sending it to a host nobody picked would throw that away. If the address
# moves, the address in the build moves.
t_envio_posta() {
    local reg="$1" codigo
    if command -v curl >/dev/null 2>&1; then
        codigo="$(curl -sS --max-time 20 -X POST \
             -H 'Content-Type: text/plain' \
             -H "User-Agent: tandem/$TANDEM_VERSAO" \
             --data-binary "$reg" \
             -o /dev/null -w '%{http_code}' \
             "$TANDEM_LISTA_ENVIO" 2>>"${LOG:-/dev/null}")" || {
            t_diz "envio: nao consegui falar com o servidor"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        # --max-redirect=0 is the same decision. wget FOLLOWS redirects by
        # default and turns the POST into a GET on the way, so the record was
        # not posted at all while wget exited 0 - the same silent loss, by a
        # different mechanism.
        if wget -q -T 20 --max-redirect=0 -O /dev/null \
             --header='Content-Type: text/plain' \
             --header="User-Agent: tandem/$TANDEM_VERSAO" \
             --post-data="$reg" "$TANDEM_LISTA_ENVIO" 2>>"${LOG:-/dev/null}"; then
            return 0
        fi
        t_diz "envio: o servidor nao aceitou a linha (wget)"
        return 1
    else
        return 1
    fi
    # Three outcomes, not two, and the third is the one that matters once there
    # is an address to post to. A 4xx is the far end saying this LINE is wrong -
    # it will say the same thing for ever. Keeping it in the queue would retry it
    # on every pass, and each retry counts as a failure, so three permanently
    # refused lines would trip the hour-long wait and stop the GOOD lines from
    # leaving. One malformed record would poison the whole queue.
    #
    # 429 and 408 are the exceptions inside 4xx: too fast and too slow are about
    # the moment, not about the line.
    case "$codigo" in
        2??)      return 0 ;;
        429|408)  t_diz "envio: o servidor pediu para esperar ($codigo)" ;;
        4??)      t_diz "envio: o servidor recusou a linha ($codigo); nao adianta repetir"
                  return 2 ;;
        3??)      t_diz "envio: o servidor respondeu $codigo, um redirecionamento; a linha fica na fila" ;;
        '')       t_diz "envio: o servidor nao respondeu nada" ;;
        *)        t_diz "envio: o servidor respondeu $codigo; a linha fica na fila" ;;
    esac
    return 1
}

# Called after a program has worked and the owner has confirmed it. Asks once,
# ever, and only when there is genuinely something to send - the question is
# concrete then ("this line, about the program you just used") instead of
# abstract at install time, when the owner has nothing to look at.
t_envio_oferece() {
    local prog="$1" reg
    reg="$(t_lista_registro "$prog" 2>/dev/null)" || return 1
    [ -n "$reg" ] || return 1
    # Sending is on by default, so this is a NOTICE and not a question - but it
    # is shown before the first line ever leaves, and it shows the actual line
    # rather than a description of one. A notice that describes a payload is
    # asking to be trusted; a notice that displays it is telling the truth.
    #
    # It is offered once. If there is nobody to show it to, the line still goes
    # (the default is on and dpkg already printed the notice at install), and
    # the fact that nobody was told is written to the log.
    if ! t_envio_decidido && [ "$(t_config_le ENVIAR_AVISADO 2>/dev/null)" != sim ]; then
        if t_tem_gui || [ -t 0 ]; then
            t_config_grava ENVIAR_AVISADO sim
            if ! t_pergunta "$(t_msg envio_aviso_ligado)

$(t_msg envio_esta_linha)

$reg" "$(t_msg botao_deixar_ligado)" "$(t_msg botao_desligar_envio)"; then
                t_envio_define nao
                t_ok "$(t_msg envio_desligado_agora)"
                return 1
            fi
        else
            t_diz "envio ligado por padrao e ninguem para avisar; o aviso saiu no postinst"
        fi
    fi
    t_envio_ligado || return 1
    t_envio_enfileira "$reg" || return 1
    # In the background and detached: the owner closed his program, and he is not
    # going to wait for a network round trip to find out he is free to go.
    ( t_envio_envia >/dev/null 2>&1 & ) 2>/dev/null
    return 0
}
