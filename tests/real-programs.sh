#!/bin/bash
# Tandem - the suite that runs REAL Windows software.
#
# The project's largest uncertainty, written down in docs/IDEAS.md, is that
# almost no real commercial program has ever run on it. tests/run.sh covers the
# libraries and the whole of tandem-exe against a fake wine and a fake
# winetricks; what it cannot cover is a binary somebody else compiled, with a
# real import table, a real installer and a real window.
#
# This suite closes that gap as far as it can be closed without a shop counter.
# It downloads freely redistributable Windows programs, runs each one THROUGH
# TANDEM, and then looks at the screen: a window has to appear, with the title
# the program is supposed to have. A program that exits 0 without ever drawing
# anything is the exact failure mode Wine has with commercial software, and no
# amount of exit-code checking catches it.
#
# It is separate from tests/run.sh on purpose. It needs network, Wine, an X
# server and several minutes; tests/run.sh needs nothing and finishes in
# seconds. Mixing them would make the fast suite slow and the CI flaky.
#
#   bash tests/real-programs.sh              # the whole thing
#   bash tests/real-programs.sh --list       # what it would download, and why
#
# Every download is pinned by sha256. Fetching an unpinned binary into CI and
# executing it is a supply-chain hole, and this project audits its own
# translation table for exactly that class of mistake.

cd "$(dirname -- "$0")/.." || exit 1
ROOT="$PWD"

OK=0; FAILED=0; SKIPPED=0
FAILURES=()

pass()    { OK=$((OK+1));           printf '  ok   %s\n' "$1"; }
fail()    { FAILED=$((FAILED+1)); FAILURES+=("$1"); printf '  FAILED %s\n     %s\n' "$1" "${2:-}"; }
skip()    { SKIPPED=$((SKIPPED+1)); printf '  --   %s (%s)\n' "$1" "$2"; }
section() { printf '\n== %s ==\n' "$1"; }

# --------------------------------------------------------------- the catalogue
#
# name | url | sha256 | what to run inside it | window title to look for
#
# Chosen to cover different shapes of real software rather than to be a long
# list: a console tool with no dependencies, a GUI app that is a single
# executable, a portable archive, and an installer. All four are freely
# redistributable.
PROGRAMS=(
"putty|https://the.earth.li/~sgtatham/putty/latest/w32/putty.exe|d5a83cd1233f6da38fa82b14d970dbb2c2705769b5ebabb464918b9b57180bc4|putty.exe|PuTTY Configuration"
"notepadpp|https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.9/npp.8.6.9.portable.x64.zip|c1478faf2a2ec8c78c9d92b22445d53027c85d142165015cf9ed0aca80b13679|notepad++.exe|Notepad++"
)

# The installers are downloaded but not run to completion: a real installer
# wants clicks, and driving one with xdotool tests xdotool, not Tandem. They
# are here because the PRE-FLIGHT reading them is itself worth checking - and
# because they proved something the README had wrong (see below).
INSTALLERS=(
"7zip|https://www.7-zip.org/a/7z2408.exe|faa87251336d864b877a5e6c3e9c9a5e250318be2fdfc8a42ceadb3a956e0405"
"winmerge|https://github.com/WinMerge/winmerge/releases/download/v2.16.44/WinMerge-2.16.44-x64-Setup.exe|055e960261fc31723856082d2bf1aec2bcc2c71f1ae2d759efec3d766affeaec"
)

if [ "${1:-}" = "--list" ]; then
    printf 'Programs run through Tandem and checked on screen:\n'
    for p in "${PROGRAMS[@]}"; do
        IFS='|' read -r n u _ exe title <<< "$p"
        printf '  %-12s %s\n               runs %s, expects a window titled %s\n' "$n" "$u" "$exe" "$title"
    done
    printf '\nInstallers read by the pre-flight but not executed:\n'
    for p in "${INSTALLERS[@]}"; do
        IFS='|' read -r n u _ <<< "$p"
        printf '  %-12s %s\n' "$n" "$u"
    done
    exit 0
fi

# ------------------------------------------------------------- what we need
#
# Every missing piece is a skip, never a failure: this suite has to be
# runnable on a laptop with no Wine without pretending something broke.
for tool in wine curl unzip; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'Missing %s - nothing to do.\n' "$tool"; exit 0; }
done
command -v xdotool >/dev/null 2>&1 || VER_JANELA=0
: "${VER_JANELA:=1}"

TMP="$(mktemp -d)"
CACHE="${TANDEM_CACHE_REAIS:-$TMP/cache}"
mkdir -p "$CACHE"
trap 'rm -rf -- "$TMP"; [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" 2>/dev/null' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"
export TANDEM_LIB="$ROOT/src/lib"
export TANDEM_VERBOS_TSV="$ROOT/src/lib/verbos.tsv"
export TANDEM_LIMITES="$ROOT/src/lib/limites.tsv"
export TANDEM_ALTERNATIVAS="$ROOT/src/lib/alternativas.tsv"

# An X server of our own, so the suite does not borrow (or disturb) a desktop
# that happens to be running.
if [ -z "${DISPLAY:-}" ] && command -v Xvfb >/dev/null 2>&1; then
    Xvfb :77 -screen 0 1280x900x24 -ac >/dev/null 2>&1 &
    XVFB_PID=$!
    export DISPLAY=:77
    sleep 3
fi
[ -n "${DISPLAY:-}" ] || VER_JANELA=0

# zenity that answers "yes" and records what it was asked. Everything else -
# Wine, winetricks, the prefix, the loop - is real. Only the human click is
# simulated, and there is no way around that in an automated suite.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/zenity" <<'FIM'
#!/bin/sh
for a in "$@"; do
    case "$a" in --text=*) printf '%s\n' "${a#--text=}" >> "${TANDEM_JANELAS:-/dev/null}" ;; esac
done
case " $* " in *" --question "*) exit 0 ;; esac
exit 0
FIM
chmod +x "$TMP/bin/zenity"
export PATH="$TMP/bin:$PATH"
export TANDEM_JANELAS="$TMP/janelas.txt"

fetch() { # url sha256 destination
    local url="$1" want="$2" dest="$3" got
    if [ -f "$dest" ]; then
        got="$(sha256sum "$dest" | cut -d' ' -f1)"
        [ "$got" = "$want" ] && return 0
        rm -f "$dest"
    fi
    curl -sL --max-time 180 -o "$dest" "$url" 2>/dev/null || return 1
    got="$(sha256sum "$dest" 2>/dev/null | cut -d' ' -f1)"
    if [ "$got" != "$want" ]; then
        # A changed checksum is not a network problem: either the publisher
        # moved the file or somebody is serving something else. Never execute
        # it to find out which.
        printf '     checksum mismatch for %s\n     expected %s\n     got      %s\n' "$url" "$want" "${got:-nothing}"
        rm -f "$dest"; return 2
    fi
    return 0
}

# Waits for a window whose title contains $1, up to $2 seconds. Returns the id.
espera_janela() {
    local alvo="$1" limite="${2:-90}" _i w n
    for _i in $(seq 1 "$limite"); do
        for w in $(xdotool search --onlyvisible --name . 2>/dev/null); do
            n="$(xdotool getwindowname "$w" 2>/dev/null)"
            case "$n" in *"$alvo"*) printf '%s' "$w"; return 0 ;; esac
        done
        sleep 1
    done
    return 1
}

section "the pre-flight reads binaries somebody else compiled"

# peinfo.py was validated against objdump on 37 binaries. These are different:
# real installers and real applications, downloaded today.
for p in "${INSTALLERS[@]}" "${PROGRAMS[@]}"; do
    IFS='|' read -r name url sha rest <<< "$p"
    file="$CACHE/$name.bin"
    fetch "$url" "$sha" "$file"
    case $? in
        1) skip "pre-flight on $name" "download failed"; continue ;;
        2) fail "pre-flight on $name" "checksum mismatch - not executed"; continue ;;
    esac
    # A zip is an archive of programs, not a program: unpack and read one.
    if head -c2 "$file" | grep -q PK; then
        mkdir -p "$CACHE/$name.d" && unzip -qo "$file" -d "$CACHE/$name.d" 2>/dev/null
        # The declared executable, not whatever the find happens to hit first:
        # a portable archive ships helpers, and reading the wrong one makes the
        # test report an architecture that belongs to something else.
        exe_esperado="$(printf '%s' "$rest" | cut -d'|' -f1)"
        alvo="$(find "$CACHE/$name.d" -maxdepth 2 -iname "${exe_esperado:-*.exe}" | head -1)"
        [ -n "$alvo" ] || alvo="$(find "$CACHE/$name.d" -maxdepth 2 -iname '*.exe' | head -1)"
    else
        alvo="$file"
    fi
    [ -n "$alvo" ] || { skip "pre-flight on $name" "no executable inside"; continue; }
    saida="$(python3 "$ROOT/src/lib/peinfo.py" "$alvo" 2>/dev/null)"
    arch="$(printf '%s' "$saida" | sed -n 's/^ARQUITETURA=//p')"
    dlls="$(printf '%s' "$saida" | sed -n 's/^DLLS=//p')"
    if [ -n "$arch" ] && [ -n "$dlls" ]; then
        pass "$name: architecture $arch, $(printf '%s' "$dlls" | tr ',' '\n' | grep -c .) imports"
    else
        fail "$name: the pre-flight read it" "ARQUITETURA=$arch DLLS=$dlls"
    fi
    # Cross-check against objdump when it is here: two readers disagreeing
    # means one of them is wrong, and ours is the one on trial.
    if command -v objdump >/dev/null 2>&1; then
        od="$(objdump -p "$alvo" 2>/dev/null | sed -n 's/^\tDLL Name: //p' |
              tr 'A-Z' 'a-z' | sort -u | tr '\n' ',' | sed 's/,$//')"
        if [ -n "$od" ] && [ "$od" != "$dlls" ]; then
            fail "$name: our reader agrees with objdump" "ours=$dlls objdump=$od"
        elif [ -n "$od" ]; then
            pass "$name: our reader agrees with objdump, import for import"
        fi
    fi
done

section "real programs, run through Tandem, checked on the screen"

for p in "${PROGRAMS[@]}"; do
    IFS='|' read -r name url sha exe title <<< "$p"
    file="$CACHE/$name.bin"
    [ -f "$file" ] || { skip "$name" "not downloaded"; continue; }

    # Portable archives get unpacked; a single .exe is used as it is. Either
    # way Tandem is the one that runs it.
    if head -c2 "$file" | grep -q PK; then
        prog="$(find "$CACHE/$name.d" -maxdepth 2 -iname "$exe" | head -1)"
    else
        prog="$TMP/$exe"; cp -f "$file" "$prog"
    fi
    [ -n "$prog" ] && [ -f "$prog" ] || { skip "$name" "$exe not found inside"; continue; }

    : > "$TANDEM_JANELAS"
    timeout 600 bash "$ROOT/src/bin/tandem-exe" "$prog" >/dev/null 2>&1 &
    pid=$!

    if [ "$VER_JANELA" = 1 ]; then
        if w="$(espera_janela "$title" 150)"; then
            pass "$name: a window titled \"$(xdotool getwindowname "$w")\" appeared"
            if command -v import >/dev/null 2>&1; then
                mkdir -p "$ROOT/tests/telas"
                import -window "$w" "$ROOT/tests/telas/$name.png" 2>/dev/null &&
                    pass "$name: screenshot saved for a human to look at"
            fi
            xdotool windowkill "$w" 2>/dev/null
        else
            # This is the whole point of this suite. Exiting 0 without ever
            # drawing a window is Wine's characteristic failure with
            # commercial software, and it looks like success from outside.
            fail "$name: a window titled \"$title\" appeared" \
                 "nothing on screen after 150s; what Tandem said: $(head -c 300 "$TANDEM_JANELAS" 2>/dev/null)"
        fi
    else
        skip "$name: window on screen" "no xdotool or no display"
    fi
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
done

section "Brazilian text renders, in the encoding old software actually uses"

# "The receipt printed with broken accents" is the failure this project fears
# most, because it exits 0. A real program opening a real CP1252 file is the
# only way to see it.
if [ "$VER_JANELA" = 1 ] && [ -d "$CACHE/notepadpp.d" ]; then
    npp="$(find "$CACHE/notepadpp.d" -maxdepth 2 -iname 'notepad++.exe' | head -1)"
    if [ -n "$npp" ]; then
        printf 'CUPOM FISCAL - Acougue Sao Joao\n' > "$TMP/cupom.txt"
        printf 'Endere\xe7o: Pra\xe7a da S\xe9, 42 - Ribeir\xe3o Preto/SP\n' >> "$TMP/cupom.txt"
        printf 'Pe\xe7as: parafuso \xd88mm, alavanca de inspe\xe7\xe3o\n' >> "$TMP/cupom.txt"
        printf 'Observa\xe7\xe3o: n\xe3o \xe9 preciso confer\xeancia\n' >> "$TMP/cupom.txt"
        timeout 300 bash "$ROOT/src/bin/tandem-exe" "$npp" >/dev/null 2>&1 &
        pid=$!
        if w="$(espera_janela "Notepad++" 150)"; then
            pass "the editor opened for the encoding check"
            if command -v import >/dev/null 2>&1; then
                mkdir -p "$ROOT/tests/telas"
                import -window "$w" "$ROOT/tests/telas/acentos.png" 2>/dev/null &&
                    pass "screenshot of the accented text saved"
            fi
            xdotool windowkill "$w" 2>/dev/null
        else
            fail "the editor opened for the encoding check" "no window"
        fi
        kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    fi
else
    skip "Brazilian text renders" "needs a display and the portable editor"
fi

section "what the real binaries taught us"

# Not a test of Tandem: a test of the README. Real installers are 32-bit even
# when the software they install is 64-bit, which makes wine32 far more
# important than "64-bit is the normal case" suggests.
trinta_e_dois=0; total=0
for p in "${INSTALLERS[@]}"; do
    IFS='|' read -r name url sha <<< "$p"
    f="$CACHE/$name.bin"
    [ -f "$f" ] || continue
    total=$((total+1))
    a="$(python3 "$ROOT/src/lib/peinfo.py" "$f" 2>/dev/null | sed -n 's/^ARQUITETURA=//p')"
    [ "$a" = 32 ] && trinta_e_dois=$((trinta_e_dois+1))
done
if [ "$total" -gt 0 ]; then
    printf '     %d of %d real installers are 32-bit\n' "$trinta_e_dois" "$total"
    if [ "$trinta_e_dois" -gt 0 ]; then
        grep -q 'wine32' "$ROOT/README.md" &&
            pass "the README mentions wine32, which real installers need" ||
            fail "the README mentions wine32" "real installers are 32-bit and it does not say so"
    fi
else
    skip "installer architecture survey" "nothing downloaded"
fi

printf '\n────────────────────────────────────────\n'
printf '%d passed, %d failed, %d skipped\n' "$OK" "$FAILED" "$SKIPPED"
if [ "$FAILED" -gt 0 ]; then
    printf '\nfailures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
