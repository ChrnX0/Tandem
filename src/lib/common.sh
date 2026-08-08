# shellcheck shell=bash
# Tandem - common library.
# Loaded by every executable. Never use "set -e" here:
# the wait loops depend on commands that fail on purpose.

# The version, in one place. It is here and not in src/bin/tandem because the
# first-run bookkeeping needs it, and that lives in this file: a version that
# learned to open a new format has to claim that format on a machine that was
# already running an older one.
TANDEM_VERSAO="3.9"

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

if [ "$(locale charmap 2>/dev/null)" != "UTF-8" ]; then
    TANDEM_LOCALE="$(t_locale_utf8 pt_BR.UTF-8)"
    export LC_ALL="$TANDEM_LOCALE"
fi

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
#   t_progresso_abre "Instalando..." ; ... ; t_progresso_fecha
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
    t_ok "Pronto. Procure no menu de aplicativos por:

$nomes"
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

TANDEM_ALTERNATIVAS="${TANDEM_ALTERNATIVAS:-${TANDEM_LIB:-/usr/lib/tandem}/alternativas.tsv}"

# Looks up by name. Returns "class|name|how to install|what changes", one
# alternative per line.
t_alternativas_para() {
    local alvo padrao classe nome como muda
    alvo="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"
    [ -n "$alvo" ] || return 1
    [ -f "$TANDEM_ALTERNATIVAS" ] || return 1
    local achou=1
    while IFS=$'\t' read -r padrao classe nome como muda; do
        case "$padrao" in ''|'#'*) continue ;; esac
        [ -n "$nome" ] || continue
        # shellcheck disable=SC2254
        case "$alvo" in
            $padrao) printf '%s|%s|%s|%s\n' "$classe" "$nome" "$como" "$muda"; achou=0 ;;
        esac
    done < "$TANDEM_ALTERNATIVAS"
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
• $nome — feito para Linux
  $muda
  Como obter: $como"
        else
            saida="$saida
• $nome — faz um trabalho parecido
  Atenção: $muda
  Como obter: $como"
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
t_verbo_valido() {
    case "${1:-}" in
        ''|*[!a-zA-Z0-9_.-]*) return 1 ;;
    esac
    [ "${#1}" -le 40 ] || return 1
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
                    t_verbo_valido "$v" || { t_diz "receita recusada: verbo suspeito '$v'"; return 4; }
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
t_dll_no_prefixo() {
    local dll="$1" arch="${2:-}" c s32 s64 tem32=1 tem64=1
    [ -n "$dll" ] && [ -n "${WINEPREFIX:-}" ] || return 1
    c="$WINEPREFIX/drive_c/windows"
    s64="$c/system32"; s32="$c/syswow64"
    # With no syswow64, the prefix is 32-bit: system32 holds the 32-bit ones.
    [ -d "$s32" ] || { s32="$c/system32"; s64=""; }

    _t_acha_dll() {
        [ -n "$1" ] && [ -d "$1" ] || return 1
        find "$1" -maxdepth 1 -iname "$dll" -print -quit 2>/dev/null | grep -q .
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

# Returns "class|sentence" of the first permanent limit recognized, or nothing.
# The table lives in limites.tsv and grows without touching code.
t_limite_do_programa() {
    local tabela dll padrao classe frase
    tabela="${TANDEM_LIMITES:-${TANDEM_LIB:-/usr/lib/tandem}/limites.tsv}"
    [ -f "$tabela" ] || return 1
    local dlls; dlls="$(t_pe_dlls "$1")"
    [ -n "$dlls" ] || return 1
    while IFS=$'\t' read -r padrao classe frase; do
        case "$padrao" in ''|'#'*) continue ;; esac
        [ -n "$frase" ] || continue
        while IFS= read -r dll; do
            # The pattern comes from the table and uses * on purpose, so it
            # cannot be quoted.
            # shellcheck disable=SC2254
            case "$dll" in $padrao) printf '%s|%s' "$classe" "$frase"; return 0 ;; esac
        done <<< "$dlls"
    done < "$tabela"
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
t_lista_vaza() {
    local reg="$1"
    # Path, machine name, user, IP, and anything with a slash.
    case "$reg" in
        */*|*"$HOME"*|*"$(id -un)"*) return 0 ;;
    esac
    [ -n "${HOSTNAME:-}" ] && case "$reg" in *"$HOSTNAME"*) return 0 ;; esac
    printf '%s' "$reg" | grep -qE '[0-9]{1,3}(\.[0-9]{1,3}){3}' && return 0
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
        t_aviso "O programa abriu e fechou sozinho em $durou segundo(s), sem dar tempo de usar."
    fi

    t_tem_gui || return 0
    command -v zenity >/dev/null 2>&1 || return 0
    if t_pergunta "O programa funcionou como você esperava?

Se alguma coisa saiu errada - tela em branco, acento quebrado, relatório
vazio - responda Não. O Tandem guarda isso e para de recomendar este
caminho para outras pessoas." "Sim, funcionou" "Não, algo saiu errado"; then
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
        t_aviso "Anotado. Não vou exportar este caminho como se tivesse dado certo."
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
    printf 'Encontrei arquivos seus aqui dentro e NÃO consegui fazer uma cópia deles.

Isso costuma ser disco cheio ou pasta pessoal sem permissão de escrita.

Se continuar, esses arquivos vão ser apagados e não há como recuperar. O
mais seguro é parar, liberar espaço, e tentar de novo.'
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
        if t_pergunta "O Android (Waydroid) não está instalado nesta máquina.

Posso instalar agora? Baixa cerca de 1 GB e precisa da sua senha." "Instalar" "Agora não"; then
            t_progresso_texto "Instalando o Android. Vai demorar - não desligue o computador."
            t_como_root "$(t_script_instalacao waydroid)" >>"${LOG:-/dev/null}" 2>&1
        fi
        command -v waydroid >/dev/null 2>&1 || {
            t_erro "O Android (Waydroid) não está instalado nesta máquina.

Deixe o Tandem instalar tudo:  tandem preparar"
            return 1; }
    fi

    estado="$(systemctl is-active waydroid-container 2>/dev/null)"
    if [ "$estado" = "activating" ]; then
        for _ in $(seq 1 30); do
            [ "$(systemctl is-active waydroid-container 2>/dev/null)" = "active" ] && break
            sleep 2
        done
    elif [ "$estado" != "active" ]; then
        t_progresso_texto "Ligando o Android..."
        systemctl start waydroid-container >>"${LOG:-/dev/null}" 2>&1 ||
        pkexec systemctl start waydroid-container >>"${LOG:-/dev/null}" 2>&1 || {
            t_erro "Não consegui ligar o Android."; return 1; }
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
        t_progresso_texto "Iniciando a sessão Android..."
        setsid waydroid session start >>"${LOG:-/dev/null}" 2>&1 &
        for _ in $(seq 1 40); do t_wd_sessao_ok && break; sleep 2; done
    fi
    if ! t_wd_sessao_ok; then
        if grep -qi 'not initialized' "${LOG:-/dev/null}" 2>/dev/null; then
            t_erro "O Android nunca foi configurado nesta máquina.

Execute uma vez:  sudo waydroid init"
        else
            t_erro "O Android não iniciou. Reinicie o computador e tente de novo."
        fi
        return 1
    fi

    if ! t_wd_pronto; then
        t_progresso_texto "Aguardando o Android terminar de iniciar..."
        for _ in $(seq 1 90); do t_wd_pronto && break; sleep 2; done
    fi
    t_wd_pronto || { t_erro "O Android iniciou mas não ficou pronto a tempo."; return 1; }
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
t_integra_appimage() {
    local prog="$1" tmp dsk nome icone destino base
    [ -x "$prog" ] || return 1
    base="$(basename -- "${prog%.*}")"
    destino="$TANDEM_ATALHOS_NATIVOS/tandem-appimage-$(printf '%s' "$prog" | cksum | tr -d ' ').desktop"
    tmp="$(mktemp -d 2>/dev/null)" || return 1
    (
        cd "$tmp" 2>/dev/null || exit 1
        # --appimage-extract does not mount anything - the runtime reads the
        # squashfs itself - so this path also works on a machine with no FUSE,
        # which is exactly the machine that most needs the menu entry.
        timeout 120 "$prog" --appimage-extract '*.desktop' >/dev/null 2>&1
        timeout 120 "$prog" --appimage-extract '*.png' >/dev/null 2>&1
        timeout 120 "$prog" --appimage-extract '*.svg' >/dev/null 2>&1
    )
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
    printf 'Este programa é feito em Java, e o Java não está instalado.\n\n'
    printf 'Instale pela Central de Programas procurando por "Java", ou no Terminal:\n\n'
    printf 'sudo apt install default-jre\n\n'
    printf 'Ou deixe o Tandem instalar:  tandem preparar\n'
}

t_texto_java_antigo() {
    local pede="$1" tem="$2"
    printf 'Este programa precisa de uma versão mais nova do Java.\n\n'
    printf 'Ele pede o Java %s e o instalado aqui é o %s.\n\n' "$pede" "$tem"
    printf 'Para instalar a versão que ele pede:\n\n'
    printf 'sudo apt install openjdk-%s-jre\n\n' "$pede"
    printf 'Não é defeito da sua máquina nem do programa: o Java se recusa a abrir\n'
    printf 'um programa feito para uma versão posterior à dele.\n'
}

t_texto_jar_biblioteca() {
    printf 'Este arquivo é uma peça de um programa, não um programa.\n\n'
    printf 'Arquivos .jar servem para as duas coisas, e por fora são iguais. Este\n'
    printf 'aqui não tem ponto de partida: ele é feito para ser usado por outro\n'
    printf 'programa, não para abrir sozinho.\n\n'
    printf 'Se você esperava um programa, procure no site de onde baixou um arquivo\n'
    printf 'marcado como "executável", "runnable" ou "with dependencies".\n'
}

t_texto_jar_agente() {
    printf 'Este arquivo é um acessório de outro programa Java, e não abre sozinho.\n\n'
    printf 'Ele é feito para ser acoplado a um programa que já esteja rodando.\n'
}

t_texto_jar_javafx() {
    printf 'Este programa usa o JavaFX, que não vem junto com o Java.\n\n'
    printf 'Para instalar:\n\n'
    printf 'sudo apt install openjfx\n'
}

t_texto_appimage_incompleto() {
    local prog="$1"
    printf 'O download deste arquivo não terminou.\n\n'
    printf '%s\n\n' "$(basename -- "$prog")"
    printf 'O arquivo diz por dentro que deveria ser maior do que é. Não é defeito\n'
    printf 'do programa: a transferência foi cortada no meio.\n\n'
    printf 'Baixe de novo e tente outra vez.\n'
}

t_texto_appimage_arch() {
    local do_arquivo="$1" da_maquina="$2"
    printf 'Este programa foi feito para outro tipo de processador.\n\n'
    printf 'Ele é para %s e este computador é %s.\n\n' "$do_arquivo" "$da_maquina"
    printf 'Procure no site de onde você baixou a versão para %s.\n' "$da_maquina"
}

t_texto_appimage_fuse() {
    printf 'Este programa precisa de uma peça do sistema para se abrir (o FUSE),\n'
    printf 'e ela não está instalada.\n\n'
    printf 'O Tandem já contornou isso desta vez, abrindo o programa por outro\n'
    printf 'caminho - um pouco mais lento, mas funciona.\n\n'
    printf 'Para deixar rápido de vez:\n\n'
    printf 'sudo apt install libfuse2t64\n\n'
    printf '(em sistemas mais antigos o nome é libfuse2)\n'
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
    if grep -qE 'Could not get lock|frontend lock was locked|is another process using it' \
            "$log" 2>/dev/null; then
        printf 'O computador já está instalando ou atualizando outra coisa.\n\n'
        printf 'Espere um ou dois minutos e tente de novo. Não é defeito: dois programas\n'
        printf 'não podem instalar ao mesmo tempo, então este esperou a vez dele e desistiu.'
        return 0
    fi
    if grep -q 'does not match system' "$log" 2>/dev/null; then
        printf 'Este pacote foi feito para outro tipo de processador.'
        return 0
    fi
    if grep -q 'No space left on device' "$log" 2>/dev/null; then
        printf 'O disco está cheio.'
        return 0
    fi
    if grep -q 'trying to overwrite' "$log" 2>/dev/null; then
        printf 'Este pacote quer sobrescrever um arquivo que pertence a outro programa\n'
        printf 'já instalado. Instalar assim quebraria o outro, então não instalei.'
        return 0
    fi
    if grep -qE 'Temporary failure resolving|Could not resolve|Network is unreachable|Connection timed out' \
            "$log" 2>/dev/null; then
        printf 'O computador não conseguiu acessar a internet para baixar o que falta.'
        return 0
    fi
    if grep -qE 'is not valid yet|Release file.*not valid|certificate' "$log" 2>/dev/null; then
        printf 'A data do computador parece errada, e isso derruba os downloads.\n'
        printf 'Hoje o computador acha que é %s.' "$(date '+%d/%m/%Y')"
        return 0
    fi
    if grep -qE 'NO_PUBKEY|not signed|GPG error' "$log" 2>/dev/null; then
        printf 'Um dos repositórios desta máquina está sem a assinatura digital dele,\n'
        printf 'e o sistema se recusa a baixar de uma fonte que não pode conferir.'
        return 0
    fi
    if grep -qE 'dependency problems|unmet dependencies|held broken packages' "$log" 2>/dev/null; then
        printf 'Faltam componentes que este pacote precisa, e eles não estão disponíveis\n'
        printf 'nesta máquina.'
        return 0
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
    local faltando="$1"
    printf 'Este programa foi feito para uma versão diferente do seu sistema.\n\n'
    printf 'Ele precisa destes componentes, e nenhum deles existe nesta máquina:\n'
    printf '%s\n' "$(printf '%s\n' "$faltando" | sed 's/^/  - /')"
    printf '\nNão é defeito da sua máquina nem do programa. Quem distribui esse pacote\n'
    printf 'publicou uma versão para um sistema mais antigo (ou mais novo) que o seu.\n\n'
    printf 'No site de onde você baixou, procure a versão que combina com o seu sistema.\n'
}

t_texto_deb_falta_repositorio() {
    local faltando="$1"
    printf 'Falta um componente que não está nos repositórios desta máquina:\n'
    printf '%s\n' "$(printf '%s\n' "$faltando" | sed 's/^/  - /')"
    printf '\nIsso costuma querer dizer que o programa espera que você adicione antes o\n'
    printf 'repositório dele. Veja as instruções no site de onde você baixou o arquivo.\n'
}

t_texto_deb_arch() {
    local do_pacote="$1" da_maquina="$2"
    printf 'Este pacote foi feito para outro tipo de processador.\n\n'
    printf 'Ele é para %s e este computador é %s.\n\n' "$do_pacote" "$da_maquina"
    printf 'Procure no site de onde você baixou a versão para %s.\n' "$da_maquina"
}

t_texto_rpm() {
    local nome="$1" dist="$2" equivalente="$3"
    printf 'Este arquivo é um pacote de outra família de Linux.\n\n'
    printf 'Arquivos .rpm são do Fedora, do openSUSE e parecidos.\n'
    [ -n "$dist" ] && printf 'Este aqui foi feito por: %s\n' "$dist"
    printf '\nO seu sistema usa arquivos .deb. Instalar este aqui não funciona, e nem\n'
    printf 'convertendo: a conversão produz algo que parece instalado e não está.\n'
    if [ -n "$equivalente" ]; then
        printf '\nA boa notícia: o mesmo programa está no seu próprio sistema. Para instalar,\n'
        printf 'abra o Terminal e execute:\n\n'
        printf 'sudo apt install %s\n' "$equivalente"
    elif [ -n "$nome" ]; then
        printf '\nNo site de onde você baixou, procure o arquivo .deb%s.\n' \
               "${nome:+ do \"$nome\"}"
    fi
}

t_texto_script_perigo() {
    local f="$1"
    printf 'Este arquivo é um script: uma lista de comandos que o computador executa.\n\n'
    printf '%s\n\n' "$(basename -- "$f")"
    printf 'Um script pode fazer qualquer coisa que você pode fazer - inclusive apagar\n'
    printf 'os seus arquivos. Só execute se você confia em quem mandou.\n\n'
    printf 'Se você baixou de um site que não conhece, a resposta certa é não executar.\n'
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
t_envio_ligado() {
    [ "$(t_config_le ENVIAR 2>/dev/null)" = sim ]
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
    printf 'Posso mandar esta linha para a lista da comunidade?\n\n'
    printf '%s\n\n' "$reg"
    printf 'É isso, inteira. Não vai mais nada.\n\n'
    printf 'Para que serve: quando outra pessoa abrir este mesmo programa, o Tandem dela\n'
    printf 'já sabe o que ele precisa e não faz ela esperar para descobrir. Quanto mais\n'
    printf 'gente manda, menos cada um precisa descobrir sozinho.\n\n'
    printf 'NÃO vai daqui: nome de arquivo, pasta, seu nome de usuário, o nome do\n'
    printf 'computador, endereço de rede, nem uma linha de registro. A primeira coluna é\n'
    printf 'uma impressão digital do arquivo do programa, não sua nem da sua máquina, e\n'
    printf 'não dá para voltar dela para nada.\n\n'
    printf 'Você decide agora e pode mudar quando quiser:\n'
    printf '  tandem enviar sim     ou     tandem enviar nao\n'
    # If the machine has somebody else's Wine profile on it, it is plausibly a
    # work machine, and the person clicking may not be the person who decides
    # what leaves it. Saying so is not a veto - it is the information he needs.
    if [ -s "$TANDEM_PROTEGIDOS" ]; then
        printf '\nAtenção: este computador tem o ambiente de outro sistema instalado. Se ele\n'
        printf 'for máquina de trabalho, confirme com quem cuida dela antes de ligar isto.\n'
    fi
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
            t_diz "envio: linha descartada pelo filtro"
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
    if ! t_envio_decidido; then
        # With nobody to ask, the answer is no, and it is not recorded as a
        # decision: the owner has not decided anything yet.
        if ! t_tem_gui && [ ! -t 0 ]; then
            t_diz "envio: ninguem para perguntar; nada enviado e nada decidido"
            return 1
        fi
        if t_pergunta "$(t_texto_pedir_envio "$reg")" "Pode mandar" "Não mandar"; then
            t_envio_define sim
        else
            t_envio_define nao
            return 1
        fi
    fi
    t_envio_ligado || return 1
    t_envio_enfileira "$reg" || return 1
    # In the background and detached: the owner closed his program, and he is not
    # going to wait for a network round trip to find out he is free to go.
    ( t_envio_envia >/dev/null 2>&1 & ) 2>/dev/null
    return 0
}
