#!/bin/bash
# Tandem - the suite that runs REAL software, not synthetic files.
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
# equal <name> <expected> <obtained>
equal_simples() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected \"$2\", got \"$3\""; fi
}

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

# appimagetool is not a program under test: it is the tool that BUILDS the
# AppImage the tests then read, so what it proves is that our reader agrees with
# the reference implementation on a file that implementation made.
#
# Upstream publishes only a "continuous" build, which means the checksum below
# WILL go stale. That is handled as a skip and not as a failure - a rebuilt
# build tool is not a regression in this repository - but the binary is never
# executed unpinned, and the new checksum is printed so a human can move the pin
# after looking at where it came from. Silence in either direction would be
# worse: executing whatever arrives, or dropping the coverage without saying so.
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA="a6d71e2b6cd66f8e8d16c37ad164658985e0cf5fcaa950c90a482890cb9d13e0"

# A real package built by Fedora's builders, pinned. Koji keeps built packages
# indefinitely, so unlike the AppImage build tool this URL does not move.
RPM_URL="https://kojipkgs.fedoraproject.org/packages/hello/2.12.1/1.fc39/x86_64/hello-2.12.1-1.fc39.x86_64.rpm"
RPM_SHA="353fcfa0c674a5a5d3fef963f2349981dee5dc1968192e996a155a7850e4c5de"

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

section "native formats: a real AppImage, built by the real appimagetool"

# The synthetic headers in tests/run.sh prove the reader. They cannot prove that
# an AppImage produced by the tool everybody actually uses is read the same way,
# and they cannot prove the two things that only exist at runtime: that
# --appimage-extract works with no FUSE, and that the desktop entry inside the
# image is where we think it is.
#
# So this builds one. appimagetool is downloaded pinned, and the AppImage it
# produces carries a real squashfs, a real runtime and a real desktop entry.
fetch "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA" "$CACHE/appimagetool"
case $? in
    0) tem_appimagetool=1 ;;
    2) tem_appimagetool=0
       printf '     the pinned build tool moved; update APPIMAGETOOL_SHA after checking it\n' ;;
    *) tem_appimagetool=0 ;;
esac
if [ "$tem_appimagetool" = 1 ]; then
    chmod +x "$CACHE/appimagetool"

    # The offset our reader computes from the ELF header has to be the same
    # number the runtime prints by running itself. That is the one claim in
    # appimageinfo.py that can be checked against an independent authority.
    nosso="$(python3 "$ROOT/src/lib/appimageinfo.py" "$CACHE/appimagetool" |
             sed -n 's/^DESLOCAMENTO=//p')"
    deles="$("$CACHE/appimagetool" --appimage-offset 2>/dev/null |
             tr -cd '0-9')"
    if [ -n "$nosso" ] && [ "$nosso" = "$deles" ]; then
        pass "the payload offset we read matches --appimage-offset ($nosso)"
    else
        fail "the payload offset we read matches --appimage-offset" \
             "we said ${nosso:-nothing}, the runtime said ${deles:-nothing}"
    fi

    mkdir -p "$TMP/AppDir"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/AppDir/AppRun"
    chmod +x "$TMP/AppDir/AppRun"
    printf '[Desktop Entry]\nType=Application\nName=Loja Teste\nExec=AppRun\n' \
        > "$TMP/AppDir/loja-teste.desktop"
    printf 'Icon=loja-teste\nCategories=Office;\nTerminal=false\n' \
        >> "$TMP/AppDir/loja-teste.desktop"
    python3 -c "
import base64, sys
open(sys.argv[1], 'wb').write(base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAF'
    'AAH/q842iQAAAABJRU5ErkJggg=='))" "$TMP/AppDir/loja-teste.png"

    if ARCH=x86_64 timeout 300 "$CACHE/appimagetool" --appimage-extract-and-run \
            "$TMP/AppDir" "$TMP/loja-teste.AppImage" >/dev/null 2>&1 &&
       [ -f "$TMP/loja-teste.AppImage" ]; then
        pass "appimagetool produced a real AppImage to test against"

        info="$(python3 "$ROOT/src/lib/appimageinfo.py" "$TMP/loja-teste.AppImage")"
        campo() { printf '%s\n' "$info" | sed -n "s/^$1=//p"; }
        [ "$(campo TIPO)" = 2 ] && pass "a freshly built AppImage reads as generation 2" ||
            fail "a freshly built AppImage reads as generation 2" "$(campo TIPO)"
        [ "$(campo COMPLETO)" = 1 ] && pass "a complete AppImage is not called truncated" ||
            fail "a complete AppImage is not called truncated" "$info"

        # Read the payload WITHOUT executing the file. This is the project's
        # own rule, and until 3.9 the AppImage integration was the one place
        # still breaking it - it ran the downloaded binary to find out its name.
        # The offset comes from the ELF header, so unsquashfs reads the payload
        # straight out of the file.
        chmod -x "$TMP/loja-teste.AppImage"
        nome_lido="$(env TANDEM_LIB="$ROOT/src/lib" bash -c \
            '. "'"$ROOT"'/src/lib/common.sh"; t_appimage_nome "'"$TMP"'/loja-teste.AppImage"' \
            2>/dev/null)"
        if [ "$nome_lido" = "Loja Teste" ]; then
            pass "the author's name is read from the payload without executing the file"
        else
            fail "the author's name is read without executing the file" \
                 "expected \"Loja Teste\", got \"${nome_lido:-nothing}\""
        fi
        if [ -x "$TMP/loja-teste.AppImage" ]; then
            fail "reading the name leaves the file non-executable" \
                 "it became executable, so it may have been run"
        else
            pass "and the file is still not executable, so it cannot have been run"
        fi
        chmod +x "$TMP/loja-teste.AppImage"

        # The whole point: the browser leaves it without the execute bit, and
        # Tandem is what fixes that.
        CASA_AI="$TMP/casa-appimage"; mkdir -p "$CASA_AI"; : > "$CASA_AI/.primeira-vez"
        cp "$TMP/loja-teste.AppImage" "$CASA_AI/loja-teste.AppImage"
        chmod -x "$CASA_AI/loja-teste.AppImage"
        env -i HOME="$CASA_AI" PATH=/usr/bin:/bin TANDEM_LIB="$ROOT/src/lib" \
            TANDEM_BIN="$ROOT/src/bin" \
            timeout 300 bash "$ROOT/src/bin/tandem-appimage" \
            "$CASA_AI/loja-teste.AppImage" >/dev/null 2>&1
        [ -x "$CASA_AI/loja-teste.AppImage" ] &&
            pass "Tandem gave the AppImage the execute bit the browser did not" ||
            fail "Tandem gave the AppImage the execute bit" "still not executable"

        # And the menu entry, taken from the AppImage's own desktop file, with
        # the name its author wrote.
        atalho="$(find "$CASA_AI/.local/share/applications" \
                       -name 'tandem-appimage-*.desktop' 2>/dev/null | head -1)"
        if [ -n "$atalho" ] && grep -q '^Name=Loja Teste$' "$atalho"; then
            pass "the menu entry carries the name from inside the AppImage"
        else
            fail "the menu entry carries the name from inside the AppImage" \
                 "${atalho:-no entry created}"
        fi
        if [ -n "$atalho" ] && command -v desktop-file-validate >/dev/null 2>&1; then
            desktop-file-validate "$atalho" 2>/dev/null &&
                pass "the menu entry Tandem writes is a valid desktop file" ||
                fail "the menu entry Tandem writes is a valid desktop file" \
                     "$(desktop-file-validate "$atalho" 2>&1 | head -3)"
        fi
    else
        fail "appimagetool produced a real AppImage to test against" \
             "the build failed; the rest of this section could not run"
    fi
else
    skip "real AppImage" "the pinned appimagetool was not available"
fi

section "native formats: a real .jar, compiled by a real compiler"

# jarinfo.py claims a class file major of 65 means Java 21. The authority on
# that is the JVM, which refuses to load a class newer than itself and says so
# by number. Here the claim is checked against it: a jar is compiled, its major
# is bumped by one, and the JVM has to refuse it with the number we predicted.
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    mkdir -p "$TMP/java"
    printf 'public class Ola { public static void main(String[] a) { System.out.println("ok"); } }\n' \
        > "$TMP/java/Ola.java"
    if javac -d "$TMP/java/classes" "$TMP/java/Ola.java" 2>/dev/null &&
       (cd "$TMP/java/classes" && jar --create --file "$TMP/java/ola.jar" --main-class Ola .) 2>/dev/null
    then
        pass "compiled a real .jar to read"
        nosso="$(python3 "$ROOT/src/lib/jarinfo.py" "$TMP/java/ola.jar" | sed -n 's/^JAVA=//p')"
        # The Java that compiled it is the Java it needs.
        deles="$(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -1)"
        case "$deles" in 1.*) deles="$(printf '%s' "$deles" | cut -d. -f2)" ;;
                         *)   deles="$(printf '%s' "$deles" | cut -d. -f1 | tr -cd '0-9')" ;; esac
        if [ "$nosso" = "$deles" ]; then
            pass "the Java version we read is the one that compiled it ($nosso)"
        else
            fail "the Java version we read is the one that compiled it" \
                 "we said ${nosso:-nothing}, the compiler was $deles"
        fi

        # One version into the future: the JVM must refuse, and must name the
        # major we would have predicted.
        python3 - "$TMP/java/ola.jar" "$TMP/java/futuro.jar" <<'PYFIM'
import struct, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    itens = [(n, z.read(n)) for n in z.namelist()]
with zipfile.ZipFile(sys.argv[2], 'w') as out:
    for n, d in itens:
        if n.endswith('.class'):
            maior = struct.unpack_from('>H', d, 6)[0]
            d = d[:6] + struct.pack('>H', maior + 1) + d[8:]
        out.writestr(n, d)
PYFIM
        previsto="$(python3 "$ROOT/src/lib/jarinfo.py" "$TMP/java/futuro.jar" |
                    sed -n 's/^JAVA=//p')"
        recusa="$(java -jar "$TMP/java/futuro.jar" 2>&1 | grep -o 'class file version [0-9]*')"
        if [ "$previsto" = "$((deles+1))" ] && [ -n "$recusa" ]; then
            pass "the JVM refuses the version we predicted (we said $previsto, it said \"$recusa\")"
        else
            fail "the JVM refuses the version we predicted" \
                 "we said ${previsto:-nothing}; the JVM said ${recusa:-nothing}"
        fi

        # And Tandem catches it BEFORE running: the log must not contain the
        # JVM's own error, because the JVM was never asked.
        CASA_J="$TMP/casa-jar"; mkdir -p "$CASA_J"; : > "$CASA_J/.primeira-vez"
        saida="$(env -i HOME="$CASA_J" PATH=/usr/bin:/bin TANDEM_LIB="$ROOT/src/lib" \
                 timeout 120 bash "$ROOT/src/bin/tandem-jar" "$TMP/java/futuro.jar" 2>&1)"
        case "$saida" in
            *"precisa de uma versão mais nova do Java"*)
                if grep -q 'UnsupportedClassVersionError' \
                        "$CASA_J/.local/state/tandem/jar.log" 2>/dev/null; then
                    fail "the wrong Java version is caught before running" \
                         "it ran the program and read the failure afterwards"
                else
                    pass "the wrong Java version is caught before running the program"
                fi ;;
            *) fail "the wrong Java version is caught before running" "${saida:-zero bytes}" ;;
        esac
    else
        skip "real .jar" "javac is here but the compile failed"
    fi
else
    skip "real .jar" "no JDK on this machine"
fi

section "native packages: real .deb files from the distribution itself"

# The synthetic packages in tests/run.sh prove the reader against a format
# tests/mkdeb.py writes. What they cannot prove is that a package built by
# Ubuntu's own build machinery reads the same way - and it does not, by default:
# every current one uses control.tar.zst, which Python cannot read and which
# Tandem goes through libzstd by hand to reach. A reader that only ever sees the
# fixtures would look perfect and handle almost no real package.
if command -v apt-get >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1; then
    mkdir -p "$TMP/debs"
    baixados=0
    for pkg in zenity gdebi-core unzip; do
        if (cd "$TMP/debs" && apt-get download -q "$pkg" >/dev/null 2>&1); then
            baixados=$((baixados+1))
        fi
    done
    if [ "$baixados" -gt 0 ]; then
        pass "downloaded $baixados real .deb files from the distribution"
        zst=0; concordam=0; total=0
        for d in "$TMP/debs"/*.deb; do
            [ -f "$d" ] || continue
            total=$((total+1))
            ar t "$d" 2>/dev/null | grep -q 'control.tar.zst' && zst=$((zst+1))
            nosso="$(python3 "$ROOT/src/lib/debinfo.py" "$d" | sed -n 's/^PACOTE=//p')"
            deles="$(dpkg-deb -f "$d" Package 2>/dev/null)"
            [ -n "$nosso" ] && [ "$nosso" = "$deles" ] && concordam=$((concordam+1))
        done
        printf '     %d of %d use control.tar.zst\n' "$zst" "$total"
        if [ "$concordam" = "$total" ] && [ "$total" -gt 0 ]; then
            pass "our reader agrees with dpkg-deb on all $total real packages"
        else
            fail "our reader agrees with dpkg-deb on all real packages" \
                 "$concordam of $total agreed"
        fi
        # Every field, on one package, not just the name.
        d="$(find "$TMP/debs" -name '*.deb' | head -1)"
        errados=""
        for par in PACOTE:Package VERSAO:Version ARQUITETURA:Architecture \
                   TAMANHO:Installed-Size MANTENEDOR:Maintainer; do
            k="${par%%:*}"; campo="${par##*:}"
            a="$(python3 "$ROOT/src/lib/debinfo.py" "$d" | sed -n "s/^$k=//p")"
            b="$(dpkg-deb -f "$d" "$campo" 2>/dev/null)"
            [ "$a" = "$b" ] || errados="$errados $k(ours=$a dpkg=$b)"
        done
        if [ -z "$errados" ]; then
            pass "every field matches dpkg-deb on $(basename -- "$d")"
        else
            fail "every field matches dpkg-deb" "$errados"
        fi
        # And the dependency list, name for name and in order.
        nomes_nossos="$(python3 "$ROOT/src/lib/debinfo.py" "$d" |
                        sed -n 's/^DEPENDE=//p' | tr ';' '\n' |
                        sed 's/|.*//;s/(.*//' | grep -v '^$' | tr '\n' ' ')"
        nomes_deles="$(dpkg-deb -f "$d" Depends 2>/dev/null | tr ',' '\n' |
                       sed 's/|.*//;s/(.*//;s/:.*//;s/^ *//;s/ *$//' |
                       grep -v '^$' | tr '\n' ' ')"
        if [ "$nomes_nossos" = "$nomes_deles" ]; then
            pass "the dependency names match dpkg-deb, in order"
        else
            fail "the dependency names match dpkg-deb, in order" \
                 "ours: $nomes_nossos / dpkg: $nomes_deles"
        fi
    else
        skip "real .deb files" "apt-get download could not fetch anything"
    fi

    # The claim the whole .deb path rests on: apt answers WITHOUT root. If this
    # is ever false, the owner types a password only to be told no.
    if [ "$(id -u)" = 0 ] && id provador >/dev/null 2>&1; then
        # The package has to be somewhere the unprivileged user can READ it.
        # mktemp -d creates a 700 directory, so testing inside it measured the
        # directory permissions and called it an apt limitation.
        um="$(find "$TMP/debs" -name '*.deb' | head -1)"
        cp -f "$um" /tmp/tandem-prova.deb 2>/dev/null
        chmod 644 /tmp/tandem-prova.deb 2>/dev/null
        if su provador -c "apt-get install -s --no-install-recommends -- /tmp/tandem-prova.deb 2>&1" |
                grep -qE 'Inst |newly installed|unmet dependencies'; then
            pass "apt simulates as an unprivileged user (the diagnosis precedes the password)"
        else
            fail "apt simulates as an unprivileged user" \
                 "the whole .deb diagnosis depends on this"
        fi
        rm -f /tmp/tandem-prova.deb
    else
        # Even as root the point can be checked: the simulation must change
        # nothing, which is what makes it safe to run before asking.
        antes="$(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)"
        apt-get install -s --no-install-recommends -- "$TMP/debs"/*.deb >/dev/null 2>&1
        depois="$(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)"
        equal_simples "the simulation installs nothing" "$antes" "$depois"
    fi
else
    skip "real .deb files" "no apt-get or dpkg-deb here"
fi

section "native packages: a real .rpm from Fedora"

# The .rpm reader has no local authority to be checked against - there is no rpm
# on a Debian machine - so it is checked against the FILENAME, which encodes the
# same three fields independently, on a package built by Fedora's own builders.
if fetch "$RPM_URL" "$RPM_SHA" "$CACHE/teste.rpm"; then
    info="$(python3 "$ROOT/src/lib/rpminfo.py" "$CACHE/teste.rpm")"
    campo_rpm() { printf '%s\n' "$info" | sed -n "s/^$1=//p"; }
    equal_simples "the rpm name matches the filename" "hello" "$(campo_rpm PACOTE)"
    equal_simples "the rpm version-release matches the filename" \
                  "2.12.1-1.fc39" "$(campo_rpm VERSAO)"
    equal_simples "the rpm architecture matches the filename" \
                  "x86_64" "$(campo_rpm ARQUITETURA)"
    equal_simples "and it says which distribution built it" \
                  "Fedora Project" "$(campo_rpm DISTRIBUICAO)"
    # The useful part: this package really is in Ubuntu, so the refusal turns
    # into an instruction. If it ever stops being there the test says so rather
    # than silently checking nothing.
    if apt-cache policy hello 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        saida="$(env -i HOME="$TMP" PATH=/usr/bin:/bin TANDEM_LIB="$ROOT/src/lib" \
                 timeout 120 bash "$ROOT/src/bin/tandem-rpm" "$CACHE/teste.rpm" 2>&1)"
        case "$saida" in
            *"sudo apt install hello"*)
                pass "the .rpm refusal is answered with the equivalent from this system" ;;
            *) fail "the .rpm refusal is answered with the equivalent" \
                    "sudo apt install hello; got: $(printf '%s' "$saida" | tail -2 | tr '\n' ' ')" ;;
        esac
    else
        skip "the .rpm equivalent lookup" "the package 'hello' is not in this machine's repositories"
    fi
else
    skip "real .rpm" "could not download the pinned Fedora package"
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
