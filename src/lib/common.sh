# shellcheck shell=bash
# Tandem - common library.
# Loaded by every executable. Never use "set -e" here:
# the wait loops depend on commands that fail on purpose.

# The version, in one place. It is here and not in src/bin/tandem because the
# first-run bookkeeping needs it, and that lives in this file: a version that
# learned to open a new format has to claim that format on a machine that was
# already running an older one.
TANDEM_VERSAO="4.3"

TANDEM_LIB="${TANDEM_LIB:-/usr/lib/tandem}"
# Where the sibling executables live. Overridable for the same reason
# TANDEM_LIB is: with the path nailed down, exercising the panel from a working
# copy silently ran the INSTALLED binaries instead - so a whole command could be
# broken in the repository and every test still pass.
TANDEM_BIN="${TANDEM_BIN:-/usr/bin}"
TANDEM_ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/tandem"
mkdir -p "$TANDEM_ESTADO" 2>/dev/null || TANDEM_ESTADO=""

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
    : >> "$LOG" 2>/dev/null || { LOG=/dev/null; return; }
    printf '\n===== %s | %s =====\n' "$(date '+%F %T')" "${*:2}" >> "$LOG"
}

t_diz() { printf '%s\n' "$*" >> "${LOG:-/dev/null}" 2>/dev/null; }

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

t_tem_gui() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
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

t_aviso() {
    t_diz "aviso: $1"
    if t_tem_gui && command -v notify-send >/dev/null 2>&1 &&
       notify-send -i "${2:-dialog-information}" -a Tandem "Tandem" "$1" 2>/dev/null; then
        return 0
    fi
    printf 'Tandem: %s\n' "$1" >&2
    command -v logger >/dev/null 2>&1 && logger -t tandem "$1"
    return 0
}

t_ok() {
    t_diz "ok: $1"
    if t_tem_gui && command -v notify-send >/dev/null 2>&1 &&
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
    local mostrou=0
    t_diz "ERRO: $1"
    if t_tem_gui; then
        command -v notify-send >/dev/null 2>&1 &&
            notify-send -u critical -i dialog-error -a Tandem "Tandem" "$1" 2>/dev/null &&
            mostrou=1
        if command -v zenity >/dev/null 2>&1 &&
           zenity --error --no-wrap --title="Tandem" \
                  --text="$1${LOG:+$'\n\n'Detalhes técnicos:$'\n'$LOG}" 2>/dev/null; then
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
    zenity --question --no-wrap --title="Tandem" --text="$1" \
           --ok-label="${2:-Sim}" --cancel-label="${3:-Não}" 2>/dev/null
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
t_prefixo_protegido() {
    local p="$1"
    if [ -f "$TANDEM_PROTEGIDOS" ] && grep -qxF -- "$p" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
        return 0
    fi
    [ "$p" = "$TANDEM_PREFIXO_PADRAO" ] && return 1
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
        {
            printf '# O que o Tandem aprendeu sobre este programa.\n'
            printf '# Pode ler, apagar e mandar para outra pessoa.\n'
            printf 'PROGRAMA=%s\n' "$(basename -- "$prog")"
        } > "$arq" 2>/dev/null || return 1
    fi
    tmp="$arq.novo"
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
    printf '# Receita do Tandem: o que este programa precisou para funcionar.\n'
    printf '# Pode ler, conferir e mandar para outra pessoa.\n'
    printf '# Para usar:  tandem receita --importar <este arquivo> <o programa>\n'
    printf 'TANDEM_RECEITA=1\n'
    printf 'IDENTIDADE=%s\n' "$(t_memoria_id "$prog")"
    printf 'ORIGEM=%s\n' "$( . /etc/os-release 2>/dev/null
                             printf '%s' "${PRETTY_NAME:-Linux}")"
    # Where the confidence of this lesson comes from. Without this line, "the
    # process exited 0" and "a person looked at the screen and said it was
    # right" arrived on the other side with exactly the same weight.
    printf 'CONFIANCA=%s\n' "$(t_confianca_da_licao "$prog")"
    grep -v '^#' "$arq"
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
            ARQUITETURA|LIMITE|RESULTADO|PROGRAMA) verbos="$verbos$chave=$valor"$'\n' ;;
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
    if grep -qE 'MmMapIoSpace|READ_PORT_|WRITE_PORT_|IoConnectInterrupt' "$log" 2>/dev/null; then
        printf 'driver|este programa tentou falar direto com o hardware, do jeito que só um driver de sistema pode. O Wine deixou ele começar e devolveu zeros, e é por isso que ele abre e depois se comporta de um jeito estranho'
        return 0
    fi
    if grep -qE 'ZwLoadDriver|err:winedevice|failed to load driver' "$log" 2>/dev/null; then
        printf 'driver|este programa tentou carregar um driver de sistema, e o Wine roda fora do núcleo do Linux'
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
    reg="$(printf '%s\t%s\t%s\t%s\t%s\t1\t%s\t-' \
        "$id" "${arch:--}" "${verbos:--}" "${reprovados:--}" "$conf" "$(date +%Y-%m)")"
    # A date with a DAY identifies; year and month do not. And the slash of a
    # path that slipped in by mistake takes the whole record down instead of
    # leaking.
    t_lista_vaza "$reg" && { t_diz "registro recusado: continha dado da maquina"; return 1; }
    printf '%s\n' "$reg"
}

# Reads the downloaded list and returns the known verbs for this program.
# It only answers when the lesson comes confirmed by people: that is the
# difference between spreading knowledge and spreading error with the same
# efficiency.
t_lista_consulta() {
    local prog="$1" id
    [ -f "$TANDEM_LISTA" ] || return 1
    id="$(t_memoria_id "$prog" 2>/dev/null)" || return 1
    [ -n "$id" ] || return 1
    awk -F'\t' -v alvo="$id" '
        /^#/ { next }
        $1 == alvo && $5 == "confirmado" && $3 != "-" { print $3; achou = 1; exit }
        END { exit !achou }' "$TANDEM_LISTA" | tr ',' ' '
}

t_lista_maquinas() {
    [ -f "$TANDEM_LISTA" ] || return 1
    awk -F'\t' -v alvo="$1" '/^#/ {next} $1 == alvo { print $6; exit }' "$TANDEM_LISTA"
}

# Downloads the list. A malformed file does NOT replace the good one already
# on disk: a broken list would silence the second opinion with nobody
# noticing.
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
        t_aviso "$(t_msg abriu_e_fechou_sozinho "$durou")"
    fi

    t_tem_gui || return 0
    command -v zenity >/dev/null 2>&1 || return 0
    if t_pergunta "$(t_msg funcionou_como_esperava)" "Sim, funcionou" "Não, algo saiu errado"; then
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
t_confianca_da_licao() {
    case "$(t_memoria_le "$1" CONFIRMADO 2>/dev/null)" in
        sim) printf 'confirmado' ;;
        nao) printf 'reprovado' ;;
        *)   printf 'so-abriu' ;;
    esac
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
    else printf '%s bytes' "$b"; fi
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
t_portas_seriais() {
    local fam p
    for fam in ttyS ttyUSB ttyACM; do
        for p in $(ls -1 -d /dev/${fam}[0-9]* 2>/dev/null | sort -V); do
            [ -c "$p" ] || continue
            printf '%s\n' "$p"
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

# Is anything LISTENING on this port? Read out of the kernel's socket table -
# no connection is opened, so nothing can hang and nothing is disturbed.
# Returns 2 for "cannot tell", which the message has to respect: answering
# "not running" when we could not look is the kind of confident wrongness this
# project treats as worse than silence.
t_porta_escutando() {
    command -v ss >/dev/null 2>&1 || return 2
    ss -H -ltn 2>/dev/null |
        awk -v p=":$1" '$4 ~ p "$" { achou = 1 } END { exit !achou }'
}

t_servico_vivo() {
    pgrep -x "$1" >/dev/null 2>&1 && return 0
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
    t_porta_escutando "$porta"
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
        printf '%s' "Uma coisa a seu favor: o serviço da chave $nome JÁ ESTÁ rodando nesta
  máquina. Então não é ele que falta. O que sobra para conferir é se a chave
  está espetada, e se o programa é de 64 bits — nesse caso existe uma falha
  conhecida em que ele acusa \"depurador detectado\" mesmo sem nenhum, e quem
  conserta é a empresa que fez o programa, não você e não o Tandem."
        return 0
    fi

    if [ "$porta" = '?' ] && [ "$servico" = nao ]; then
        printf '%s' "Não consegui conferir se o serviço da chave $nome está rodando aqui
  (falta a ferramenta \"ss\" nesta máquina). Se o programa reclamar de licença,
  é esse serviço que vale conferir primeiro."
        return 0
    fi

    printf '%s' "E encontrei o provável motivo: o serviço da chave $nome NÃO está
  rodando nesta máquina. É ele que conversa com a chave USB pelo lado do
  Linux — sem ele, o programa procura a licença e não acha nada, do mesmo
  jeito que aconteceria sem a chave espetada.

  Quem instala é um técnico, uma vez só, e é de graça: procure por
  \"$pacote\" no site do fabricante."
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
            cabe="Este computador tem o recurso, mas ele está DESLIGADO na BIOS. Ligar
  é entrar na BIOS ao ligar a máquina e procurar por \"virtualization\", \"VT-x\"
  ou \"SVM\". Não instala nada e não apaga nada." ;;
        apertado)
            cabe="Este computador aguenta, mas apertado: tem $(t_tamanho_amigavel "$((mem * 1024))") de memória
  e $(t_tamanho_amigavel "$((livre * 1024))") livres no disco. O Windows de dentro quer uns 4 GB de memória
  e 32 GB de disco só para ele." ;;
        *)
            cabe="Este computador aguenta: tem $(t_tamanho_amigavel "$((mem * 1024))") de memória e
  $(t_tamanho_amigavel "$((livre * 1024))") livres no disco." ;;
    esac

    printf '%s' "Existe um caminho mais pesado, e para um caso como este ele funciona:

  rodar um Windows DE VERDADE dentro do Linux, e deixar só a janela do
  programa aparecer aqui na tela, como se fosse um programa daqui. Os dois
  programas que fazem isso são o WinBoat e o WinApps, os dois de graça.
  Como é um Windows de verdade, driver de sistema funciona, e a chave USB de
  proteção pode ser entregue para ele.

  $cabe

  O que custa, e é bom saber antes: precisa de uma licença do Windows, e tem
  que ser a versão Pro — a Home não serve, porque ela não deixa a janela sair
  para fora. E o Windows de dentro ocupa disco e memória o tempo todo.

  O Tandem não instala isso e não vai instalar: é outro tipo de programa. Mas
  era desonesto dizer \"não tem jeito\" sem dizer que esse jeito existe."
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
            /dev/ttyACM*|/dev/ttyUSB*) saida="$saida$(t_linha_id "COM$n" "$p   (aparelho USB)  $(t_msg portas_seu_aparelho)")" ;;
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

    n=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        n=$((n + 1))
        saida="$saida$(t_linha_id "LPT$n" "$p")"
    done <<< "$(t_portas_paralelas)"

    usblp="$(ls -1 -d /dev/usblp[0-9]* 2>/dev/null | head -3)"
    if [ -n "$usblp" ]; then
        saida="$saida

  $(t_msg portas_impressora_usb "$(printf '%s' "$usblp" | tr '\n' ' ')" \
                                "$(printf '%s' "$usblp" | head -1)")"
    fi

    if [ -n "$alto" ]; then
        saida="$saida

  $(t_msg portas_aviso_alto "${alto#*|}" "${alto%%|*}")"
    fi

    if ! t_no_grupo dialout; then
        saida="$saida

  $(t_msg portas_aviso_dialout "$(id -un)")"
    fi

    if [ -d "$prefixo/drive_c" ]; then
        fixadas="$(t_reg_lista_valores "$prefixo" 'Software\\Wine\\Ports')"
        [ -n "$fixadas" ] && saida="$saida

  $(t_msg portas_ja_presas)
$(printf '%s' "$fixadas" | sed 's/^/    /')"
    fi

    printf '%s\n' "$saida"
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
t_pecas_faltando() {
    command -v wine >/dev/null 2>&1 ||
        echo "wine|Wine (roda os programas do Windows)"
    if command -v wine >/dev/null 2>&1 && ! t_tem_wine32; then
        echo "wine32|Suporte a programas antigos de 32 bits"
    fi
    command -v winetricks >/dev/null 2>&1 ||
        echo "winetricks|Instalador de componentes do Windows"
    command -v adb >/dev/null 2>&1 ||
        echo "adb|Instalador de pacotes Android divididos (.xapk)"
    command -v java >/dev/null 2>&1 ||
        echo "java|Java (roda os programas .jar)"
    # An AppImage without FUSE still opens - Tandem falls back to unpacking it -
    # but every launch pays for the unpacking. The library is a few hundred
    # kilobytes and it stopped being installed by default in Ubuntu 22.04.
    t_tem_fuse2 ||
        echo "fuse|Suporte para abrir AppImage direto (FUSE)"
    command -v waydroid >/dev/null 2>&1 ||
        echo "waydroid|Android (Waydroid) - baixa cerca de 1 GB"
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
        if t_pergunta "$(t_msg waydroid_falta_pergunta)" "Instalar" "Agora não"; then
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
        printf 'Comment=Instalado pelo Tandem a partir de %s\n' "$prog"
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
t_palavras_do_programa() {
    grep -v -e '^$' -e '^aviso: ' -e '^ok: ' -e '^ERRO: ' -e '^>>> ' -e '^===== ' \
         "$1" 2>/dev/null | tail -"${2:-4}"
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
        t_msg porque_relogio "$(date '+%d/%m/%Y')"; return 0
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
t_atalhos_do_sistema() {
    find /usr/share/applications /usr/local/share/applications \
         -maxdepth 1 -name '*.desktop' -type f 2>/dev/null | sort
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
# Where a contribution is posted. Empty in this build ON PURPOSE: an address
# means somebody hosts it, moderates it and answers for the data, and that is a
# decision with a cost attached rather than a line of code. Everything else is
# built, so the day there is an address this becomes one assignment - and the
# queue means the lines learned before that day are not lost.
TANDEM_LISTA_ENVIO="${TANDEM_LISTA_ENVIO:-}"
# A machine cannot become a firehose, whatever it decides to install.
TANDEM_ENVIO_POR_DIA="${TANDEM_ENVIO_POR_DIA:-20}"

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

t_config_grava() {
    local chave="$1" valor="$2" tmp
    mkdir -p "$(dirname -- "$TANDEM_CONFIG")" 2>/dev/null || return 1
    [ -f "$TANDEM_CONFIG" ] || {
        printf '# Configuração do Tandem. Pode ler, editar e apagar.\n' > "$TANDEM_CONFIG"; }
    tmp="$TANDEM_CONFIG.novo"
    {
        grep -E '^(#|[A-Z_]+=)' "$TANDEM_CONFIG" 2>/dev/null | grep -v "^$chave="
        printf '%s=%s\n' "$chave" "$valor"
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$TANDEM_CONFIG"
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

# Sends what is queued, best effort. Returns the number sent.
#
# Every line is put through the sieve again here. Checking only when the record
# was built would trust that nothing touched the queue in between, and a
# plain-text file in the state directory is exactly the kind of thing that gets
# edited by hand.
t_envio_envia() {
    local enviados=0 hoje contador reg resto
    t_envio_ligado || return 0
    [ -n "$TANDEM_LISTA_ENVIO" ] || return 0
    [ -s "$TANDEM_FILA" ] || return 0
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 0

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
        if [ "$contador" -ge "$TANDEM_ENVIO_POR_DIA" ]; then
            printf '%s\n' "$reg" >> "$resto"
            continue
        fi
        if t_envio_posta "$reg"; then
            enviados=$((enviados+1)); contador=$((contador+1))
        else
            printf '%s\n' "$reg" >> "$resto"
        fi
    done < "$TANDEM_FILA"
    mv -f "$resto" "$TANDEM_FILA" 2>/dev/null
    t_config_grava ENVIO_DIA "$hoje"
    t_config_grava ENVIO_HOJE "$contador"
    [ "$enviados" -gt 0 ] && t_diz "envio: $enviados linha(s) enviada(s)"
    printf '%s' "$enviados"
    return 0
}

t_envio_posta() {
    local reg="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 20 -X POST \
             -H 'Content-Type: text/plain' \
             -H "User-Agent: tandem/$TANDEM_VERSAO" \
             --data-binary "$reg" \
             "$TANDEM_LISTA_ENVIO" >>"${LOG:-/dev/null}" 2>&1 && return 0
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 20 -O /dev/null --header='Content-Type: text/plain' \
             --post-data="$reg" "$TANDEM_LISTA_ENVIO" >>"${LOG:-/dev/null}" 2>&1 && return 0
    fi
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
