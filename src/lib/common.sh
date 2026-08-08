# shellcheck shell=bash
# Tandem - common library.
# Loaded by every executable. Never use "set -e" here:
# the wait loops depend on commands that fail on purpose.

TANDEM_LIB="${TANDEM_LIB:-/usr/lib/tandem}"
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
t_primeira_vez() {
    local dir marca
    dir="$(dirname -- "$TANDEM_PROTEGIDOS")"
    marca="$dir/.primeira-vez"
    [ -f "$marca" ] && return 0
    mkdir -p "$dir" 2>/dev/null || return 0
    t_diz "primeira execucao deste usuario: procurando prefixos e aplicando associacoes"
    t_procura_prefixos
    if [ -x /usr/bin/tandem-repair ]; then
        TANDEM_SILENCIOSO=1 /usr/bin/tandem-repair >>"${LOG:-/dev/null}" 2>&1
    fi
    : > "$marca" 2>/dev/null
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

# Packs exactly what t_dados_lista found. Returns 1 if there was nothing - and
# "there was nothing" is NOT a failure: a freshly created prefix has no data
# at all.
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

# Rescue copy before a destructive path. It never blocks the operation: if it
# cannot save, it warns and carries on - locking the owner up in the middle of
# a repair would be trading one problem for another. Prints the path of the
# copy, if there was one.
# Rescue copy before a destructive path. Same three outcomes as t_dados_salva,
# and the distinction is the whole point: "there was nothing to save" is normal
# and silent, while "there was data and I could not save it" has to stop the
# caller before it deletes anything. Merging the two meant a full disk looked
# exactly like an empty prefix, and the deletion went ahead either way.
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
    command -v waydroid >/dev/null 2>&1 ||
        echo "waydroid|Android (Waydroid) - baixa cerca de 1 GB"
    return 0
}

# Assembles the installation script for the requested pieces (one per
# argument). Everything in a single script: one single password, one single
# run.
t_script_instalacao() {
    local peca
    printf 'set -e\nexport DEBIAN_FRONTEND=noninteractive\n'
    for peca in "$@"; do
        case "$peca" in
            wine)       printf 'apt-get update -q\napt-get install -y wine winetricks\n' ;;
            wine32)     printf 'dpkg --add-architecture i386\napt-get update -q\napt-get install -y wine32:i386\n' ;;
            winetricks) printf 'apt-get install -y winetricks\n' ;;
            adb)        printf 'apt-get install -y adb\n' ;;
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
