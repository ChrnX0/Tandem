#!/bin/bash
# Tandem - test suite.
#
# Runs without Wine, without Waydroid and without installing the package: the
# libraries are loaded straight from src/lib and the Android packages are
# synthetic. The optional tools (shellcheck, dpkg-deb, lintian) are used when
# present and skipped when absent, without failing the suite.
#
# Usage: bash tests/run.sh
# Output: one line per test; exit code 1 if any of them fails.

# No "set -e": several tests expect commands that fail on purpose.
cd "$(dirname -- "$0")/.." || exit 1
ROOT="$PWD"

OK=0; FAILED=0; SKIPPED=0
FAILURES=()

pass()  { OK=$((OK+1));       printf '  ok   %s\n' "$1"; }
fail()  { FAILED=$((FAILED+1)); FAILURES+=("$1"); printf '  FAILED %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }
skip()   { SKIPPED=$((SKIPPED+1)); printf '  --   %s (%s)\n' "$1" "$2"; }
section()   { printf '\n== %s ==\n' "$1"; }

# equal <name> <expected> <obtained>
equal() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

# contem <name> <fragment> <text> - for the cases where the whole text is a
# paragraph written for a person and pinning it word for word would turn every
# wording fix into a test failure.
contem() {
    case "$3" in *"$2"*) pass "$1" ;; *) fail "$1" "...$2..." "$3" ;; esac
}
naocontem() {
    case "$3" in *"$2"*) fail "$1" "without \"$2\"" "$3" ;; *) pass "$1" ;; esac
}

# Isolated environment: nothing here may touch the HOME of whoever runs the tests.
TMPROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMPROOT"' EXIT
export HOME="$TMPROOT/casa"
mkdir -p "$HOME"
# No graphical session: this is how the tests exercise the terminal path.
unset DISPLAY WAYLAND_DISPLAY

# The suite tests the REPOSITORY, never the installed package. Without this the
# libraries resolved to /usr/lib/tandem whenever Tandem was installed on the
# machine, and the suite ended up checking the old version - a test that
# approves the wrong code is worse than no test at all.
export TANDEM_LIB="$ROOT/src/lib"
export TANDEM_VERBOS_TSV="$ROOT/src/lib/verbos.tsv"
export TANDEM_LIMITES="$ROOT/src/lib/limites.tsv"
export TANDEM_ALTERNATIVAS="$ROOT/src/lib/alternativas.tsv"

ARTIFACTS="$TMPROOT/artefatos"
python3 tests/mkapk.py "$ARTIFACTS" >/dev/null || { echo "could not generate the artifacts"; exit 1; }

# shellcheck source=../src/lib/common.sh
. "$ROOT/src/lib/common.sh"
# shellcheck source=../src/lib/winedeps.sh
. "$ROOT/src/lib/winedeps.sh"

# ----------------------------------------------------------------- syntax

# A test file translated or renamed in bulk can be damaged in a way that is
# invisible: if an EXPECTED value or a "case" pattern gets rewritten together
# with the prose around it, the test keeps passing while comparing the wrong
# thing. That happened here - a blanket rename turned the pattern
# *msvcr71.dll*continua\ faltando* into *...continua\ missing*, which no longer
# matches the message Tandem actually produces.
#
# These two lists are DATA, not prose: many of them are Portuguese strings the
# program under test emits, and rule number 2 keeps them Portuguese forever.
# Guard them with a checksum so the next bulk edit cannot touch them quietly.
section "the comparisons themselves did not drift"

# The guard excludes its own two lines: counting the checksum inside the thing
# it checksums makes the two values chase each other on every edit.
#
# Both halves read the file with its backslash continuations JOINED, and that is
# not a detail - it is the difference between a guard and the appearance of one.
# Measured: of 415 `equal` calls in this file, the line-based version saw 209.
# The other 206 are written across two lines, which is what you do as soon as an
# expected value is long - so exactly the values most likely to be rewritten by
# a bulk edit were the ones nothing was watching. Same class of mistake as the
# literal counter's twelve misses, and found the same way: by asking what the
# measure cannot see instead of reading the number it prints.
#
# The pattern half also allows one level of $( ) inside a pattern and a branch
# whose pass/fail sits on the next line: 93 of the 97 branches here, the other
# four being bare `*)` fallbacks with no data to guard.
# And the two lines below are dropped BEFORE the extraction, not after. That
# ordering is load-bearing now and it was not before: joined, this guard's own
# `equal` calls match the pattern, and `grep -oE` cuts the match off after the
# second argument - so a filter applied downstream never sees the
# "$soma_esperados" that identifies them, and the checksum ends up containing
# its own value. Two values chasing each other on every edit, which is a guard
# that can never be green.
juntado="$(sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}' "$0" |
           grep -v 'soma_esperados\|soma_padroes')"
soma_esperados="$(printf '%s\n' "$juntado" | grep -oE 'equal "[^"]*" +"[^"]*"' |
                  sed 's/.*" *"//;s/"$//' | cksum)"
soma_padroes="$(printf '%s\n' "$juntado" |
                grep -oE '^[[:space:]]+\*([^)]|\$\([^)]*\))*\)([[:space:]]*(pass|fail)|[[:space:]]*$)' |
                sed -E 's/[[:space:]]*(pass|fail)?[[:space:]]*$//' | cksum)"
equal "the expected values are the ones this suite was written with" \
      "2734912140 3409" "$soma_esperados"
equal "the case patterns still match the real messages" \
      "2376315265 2030" "$soma_padroes"

section "script syntax"
# The same set the evidence gate lints, tests/ included: a harness with a
# syntax error is a harness that passes by never running.
for f in src/bin/* src/lib/*.sh tests/*.sh debian/postinst debian/postrm; do
    if bash -n "$f" 2>/dev/null; then pass "bash -n $f"
    else fail "bash -n $f" "valid syntax" "syntax error"; fi
done

if command -v shellcheck >/dev/null 2>&1; then
    output="$(LC_ALL=C.UTF-8 shellcheck --shell=bash --exclude=SC1091,SC2123 \
             --severity=warning --format=gcc \
             src/bin/* src/lib/*.sh tests/*.sh debian/postinst debian/postrm 2>&1)"
    if [ -z "$output" ]; then pass "shellcheck with no warnings"
    else fail "shellcheck with no warnings" "(nothing)" "$output"; fi
else
    skip "shellcheck" "not installed"
fi

# ------------------------------------------------------- DLL detection

section "Wine dependency detection"

LOG_WINE="$TMPROOT/wine.log"
cat > "$LOG_WINE" <<'EOF'
0024:err:module:import_dll Library MSVCP140.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library VCRUNTIME140.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library VCRUNTIME140_1.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library kernel32.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library mscoree.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library d3dx9_43.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library MinhaLibPropria.dll (needed by Z:\p\a.exe) not found
EOF

equal "three VC++ DLLs become a single verb" \
      "d3dx9 dotnet48 vcrun2022" \
      "$(t_verbos_do_log "$LOG_WINE" | tr '\n' ' ' | sed 's/ $//')"

equal "a DLL that Wine itself implements is ignored" \
      "" \
      "$(t_verbos_do_log "$LOG_WINE" | grep -c kernel32 | sed 's/^0$//')"

equal "the program's own DLL does not become a system dependency" \
      "MinhaLibPropria.dll" \
      "$(t_dlls_sem_traducao "$LOG_WINE")"

equal "a missing log does not break anything" "" "$(t_verbos_do_log /nao/existe)"
equal "an empty log yields no verb" "" "$(: > "$TMPROOT/v.log"; t_verbos_do_log "$TMPROOT/v.log")"

equal "the friendly name translates the verb" \
      "Visual C++ 2015-2022" "$(t_verbo_amigavel vcrun2022)"
equal "an unknown verb shows up as-is" \
      "coisanova" "$(t_verbo_amigavel coisanova)"

# upper and lower case must not change the result
equal "translation is case-insensitive" \
      "vcrun2022 vcrun2022" \
      "$(t_dll_para_verbo MSVCP140.DLL) $(t_dll_para_verbo msvcp140.dll)"

# ATL comes from the Visual C++ runtime, not from atmlib (Adobe Type Manager).
# The mistake installed the wrong thing, wrote a receipt, and on the next run
# Tandem said "I already installed what this program asked for" and gave up.
equal "the six mappings the auditor fixed" \
      "amstream d3dcompiler_46 wmp11 xinput vcrun2003 vcrun2019" \
      "$(for d in amstream.dll d3dcompiler_46.dll wmasf.dll xinput1_3.dll msvcr71.dll atl140.dll; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d)"; done | sed 's/ $//')"
# And the neighbours that were RIGHT must not have been dragged along.
equal "the correct neighbours remain intact" \
      "quartz wmp9 xact d3dcompiler_47" \
      "$(for d in quartz.dll wmvcore.dll xaudio2_7.dll d3dcompiler_47.dll; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d)"; done | sed 's/ $//')"

equal "atl comes from the Visual C++ of the same year, not from Adobe Type Manager" \
      "vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013 vcrun2019" \
      "$(for d in atl80 atl90 atl100 atl110 atl120 atl140; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d.dll)"; done | sed 's/ $//')"

section "index generated from winetricks (second opinion)"

equal "the hand-written table takes precedence over the index" \
      "vcrun2022 dotnet48" \
      "$(t_dll_para_verbo msvcp140.dll) $(t_dll_para_verbo mscoree.dll)"

if [ -f "$ROOT/src/lib/verbos.tsv" ]; then
    n_ind="$(grep -vc '^#' "$ROOT/src/lib/verbos.tsv")"
    if [ "$n_ind" -gt 150 ]; then
        pass "the index covers $n_ind DLLs"
    else
        fail "the index covers more than 150 DLLs" ">150" "$n_ind"
    fi
    equal "the index answers for a DLL the hand-written table does not know" \
          "dsound" "$(t_dll_para_verbo dsound.dll)"
    equal "a DLL in neither of the two stays untranslated" \
          "" "$(t_dll_para_verbo MinhaLibPropria.dll)"
    # The tie-break has to understand versions with an omitted dot: dotnet48 is
    # 4.8, dotnet472 is 4.7.2. Comparing as integers would give 472 > 48.
    equal "the index tie-break picks the newest version" \
          "dotnet48" \
          "$(grep -m1 '^mscoree\.dll' "$ROOT/src/lib/verbos.tsv" | cut -f2)"
else
    skip "winetricks index" "verbos.tsv missing"
fi

# AUDITOR. Instead of the index answering in the table's place, it CHECKS the
# table: for every DLL both know, the verb promised by hand has to be among the
# ones winetricks says deliver that DLL. This test alone found six mapping
# errors - atl->atmlib (Adobe Type Manager!), msvcr71->vcrun6,
# amstream->quartz, d3dcompiler_46->_47, wmasf->wmp9 and xinput->xact - each of
# them installing the wrong thing and writing a receipt, which made Tandem give
# up on the next attempt.
#
# DELIBERATE divergences are declared here, with the reason. Without this list
# only two bad ways out were left: delete the test (and lose the auditor) or
# give in and swap in a worse translation. With it, the known divergence passes
# and any NEW divergence still fails.
#
#   mfc42.dll: the index only knows vcrun6, because the "mfc42" verb declares
#   the DLL in prose in its title ("...mfc42 library; part of vcrun6"), with no
#   parenthesised list for the generator to read. Picking vcrun6 would install
#   the whole Visual C++ 6 runtime just to deliver a file that the narrow verb
#   extracts on its own with cabextract.
EXCECOES_AUDITOR="mfc42.dll"

if [ -f "$ROOT/src/lib/verbos.tsv" ]; then
    suspects=""
    # The fifth column (source: override/title/both) has to be read, otherwise
    # "read" dumps it inside a_todos and the membership comparison fails for
    # EVERY line - the auditor starts accusing all 108 correct translations.
    while IFS=$'\t' read -r a_dll _ _ a_todos _; do
        case "$a_dll" in '#'*|'') continue ;; esac
        case " $EXCECOES_AUDITOR " in *" $a_dll "*) continue ;; esac
        a_mao="$(t_dll_para_verbo_tabela "$a_dll")"
        [ -n "$a_mao" ] || continue
        case ",$a_todos," in
            *",$a_mao,"*) ;;
            *) suspects="$suspects $a_dll->$a_mao(winetricks:$a_todos)" ;;
        esac
    done < "$ROOT/src/lib/verbos.tsv"
    if [ -z "$suspects" ]; then
        pass "the hand-written table only promises verbs winetricks confirms"
    else
        fail "the hand-written table only promises verbs winetricks confirms" \
               "(no suspects)" "$suspects"
    fi
fi

if command -v winetricks >/dev/null 2>&1; then
    if python3 tools/indice-winetricks.py --conferir >/dev/null 2>&1; then
        pass "the on-disk index matches the installed winetricks"
    else
        skip "on-disk index vs installed winetricks" "different winetricks versions"
    fi
else
    skip "regenerate the index" "winetricks not installed"
fi

section "Linux alternatives"

equal "recognizes a program that HAS an official Linux version" \
      "nativo" "$(t_alternativas_para teamviewer | head -1 | cut -d'|' -f1)"
equal "recognizes a program that only has a look-alike" \
      "parecido" "$(t_alternativas_para photoshop | head -1 | cut -d'|' -f1)"
equal "the search ignores case, spaces and hyphens" \
      "nativo nativo nativo" \
      "$(for n in TeamViewer 'team viewer' team-viewer; do
             printf '%s ' "$(t_alternativas_para "$n" | head -1 | cut -d"|" -f1)"; done | sed 's/ $//')"
t_alternativas_para "programa-que-ninguem-conhece" >/dev/null 2>&1
equal "an unknown program fails without making things up" "1" "$?"
t_alternativas_para "" >/dev/null 2>&1
equal "an empty name fails without breaking" "1" "$?"

# The difference between "nativo" and "parecido" is the heart of the honesty
# here: saying GIMP is Photoshop would be deceiving the owner.
texto_alt="$(t_texto_alternativas photoshop)"
case "$texto_alt" in
    *"does a similar job"*"Note:"*) pass "a look-alike alternative comes with the caveat" ;;
    *) fail "a look-alike alternative comes with the caveat" "does a similar job + Note" "$texto_alt" ;;
esac
texto_nat="$(t_texto_alternativas teamviewer)"
case "$texto_nat" in
    *"made for Linux"*) pass "a native alternative is presented as the same program" ;;
    *) fail "a native alternative is presented as the same program" "made for Linux" "$texto_nat" ;;
esac

# Every line of the table needs its five columns: a malformed line would show
# up as an empty suggestion right in the owner's face.
malformadas="$(awk -F"\t" '!/^#/ && NF>0 && (NF!=5 || $3=="")' "$TANDEM_ALTERNATIVAS" | wc -l)"
equal "every line of the table has all five columns" "0" "$malformadas"

section "memory: what Tandem learns"

MEM_A="$ARTIFACTS/imports64.exe"
MEM_B="$ARTIFACTS/importslimpo.exe"

id_a="$(t_memoria_id "$MEM_A")"
equal "the identity has a fixed length" "32" "${#id_a}"
equal "the same file always has the same identity" \
      "$id_a" "$(t_memoria_id "$MEM_A")"
if [ "$id_a" = "$(t_memoria_id "$MEM_B")" ]; then
    fail "different files have different identities" "different" "equal"
else
    pass "different files have different identities"
fi
# The identity follows the FILE, not the path: a recipe learned here has to
# still hold after the owner moves the program to another folder.
cp "$MEM_A" "$TMPROOT/mudou-de-pasta.exe"
equal "the identity survives a change of folder and name" \
      "$id_a" "$(t_memoria_id "$TMPROOT/mudou-de-pasta.exe")"
t_memoria_id /nao/existe >/dev/null 2>&1
equal "a missing file has no identity" "1" "$?"

t_memoria_grava "$MEM_A" RESULTADO abriu
equal "writes and reads back" "abriu" "$(t_memoria_le "$MEM_A" RESULTADO)"
t_memoria_grava "$MEM_A" RESULTADO "nao abriu"
equal "writing again replaces, does not duplicate" \
      "nao abriu" "$(t_memoria_le "$MEM_A" RESULTADO)"
equal "  and only one line is left" \
      "1" "$(grep -c '^RESULTADO=' "$(t_memoria_arquivo "$MEM_A")")"

t_memoria_junta "$MEM_A" RESOLVERAM vcrun2022
t_memoria_junta "$MEM_A" RESOLVERAM d3dx9
t_memoria_junta "$MEM_A" RESOLVERAM vcrun2022
equal "the list accumulates without repeating" \
      "vcrun2022 d3dx9" "$(t_memoria_le "$MEM_A" RESOLVERAM)"

equal "the file keeps the program name, so the owner recognizes it" \
      "imports64.exe" "$(t_memoria_le "$MEM_A" PROGRAMA)"
if grep -q '^#' "$(t_memoria_arquivo "$MEM_A")"; then
    pass "the file explains itself in readable text"
else
    fail "the file explains itself in readable text" "header with #" "missing"
fi

# One program's memory must not leak into another's.
equal "each program has its own memory" "" "$(t_memoria_le "$MEM_B" RESOLVERAM 2>/dev/null)"

section "evidence gate (proofgate)"

if [ -f "$ROOT/proofgate.json" ]; then
    pass "the repository declares its own stack to the gate"
    # Without this the gate goes green without running any test: the automatic
    # detection only knows ecosystems with a manifest, and shell has none.
    if grep -q '"test": *"bash tests/run.sh"' "$ROOT/proofgate.json"; then
        pass "the gate knows how to run this project's suite"
    else
        fail "the gate knows how to run this project's suite" "commands.test" "missing"
    fi
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$ROOT/proofgate.json" 2>/dev/null; then
        pass "proofgate.json is valid JSON"
    else
        fail "proofgate.json is valid JSON" "JSON" "malformed"
    fi
else
    skip "evidence gate" "proofgate.json missing"
fi

# The coupling declared in the gate has to be true: every command the program
# offers must be in the manual, otherwise the package documents one thing and
# does another.
# The command list is EXTRACTED from the main case, never written by hand: with
# a fixed list the test went green while four new commands (dados, lista,
# contribuir, socorro) were in no document at all. A test that only covers what
# someone remembered to add covers nothing.
#
# Only the FIRST name on each case line is required. The aliases (uninstall,
# diagnostico, meus-dados...) are deliberately undocumented surface; demanding
# documentation for them would fill the manual with synonyms.
COMANDOS="$(sed -n '/^case /,/^esac$/p' "$ROOT/src/bin/tandem" |
            sed -n 's/^    \([^ )]*\)).*/\1/p' | sed 's/|.*//' |
            grep -vxF -e '""' -e painel -e --primeira-vez -e version \
                     -e help -e '*' -e '' | sort -u)"
n_cmd="$(printf '%s\n' "$COMANDOS" | grep -c .)"
if [ "$n_cmd" -ge 15 ]; then pass "extracted $n_cmd commands from the main case"
else fail "extracted the commands from the main case" ">=15" "$n_cmd"; fi

for onde in man/tandem.1 README.md LEIAME.md; do
    missing=""
    for c in $COMANDOS; do
        grep -q "tandem $c" "$ROOT/$onde" || missing="$missing $c"
    done
    equal "every command shows up in $onde" "" "$missing"
done

# And the other way round: the manual must not promise a command that does not exist.
promete_demais=""
for c in $(grep -oE '^\.BI? "?tandem ([a-z]+)' "$ROOT/man/tandem.1" |
           awk '{print $NF}' | tr -d '"' | sort -u); do
    grep -q "^  tandem $c\b\|^    $c|" "$ROOT/src/bin/tandem" ||
        grep -qE "^    $c\||^    $c\)" "$ROOT/src/bin/tandem" ||
        promete_demais="$promete_demais $c"
done
equal "the manual does not promise a nonexistent command" "" "$promete_demais"

section "recipes: collective knowledge without a server"

t_memoria_grava "$MEM_A" RESULTADO abriu
t_memoria_grava "$MEM_A" RESOLVERAM "vcrun2022 msxml6"
REC="$TMPROOT/receita.txt"
t_receita_exporta "$MEM_A" > "$REC"

if grep -q '^TANDEM_RECEITA=1$' "$REC" && grep -q '^IDENTIDADE=' "$REC"; then
    pass "the recipe declares itself and carries the program identity"
else
    fail "the recipe declares itself and carries the program identity" \
           "TANDEM_RECEITA + IDENTIDADE" "$(cat "$REC")"
fi
# The header used to be a Portuguese literal, so this assertion could only ever
# be written against Portuguese - and it passed happily while a French owner
# exported a recipe whose explanation he could not read. Now it asserts the
# ENGLISH default and then asserts the same header comes out in French, which
# is what actually proves the header is wired to the catalogue rather than
# merely spelled differently.
if grep -q '^#.*send it to somebody else' "$REC"; then
    pass "the recipe explains itself to whoever receives it"
else
    fail "the recipe explains itself to whoever receives it" "explanatory header" "$(cat "$REC")"
fi
REC_FR="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=fr TANDEM_MEMORIA="$TANDEM_MEMORIA" \
    bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_receita_exporta "'"$MEM_A"'"' 2>/dev/null)"
contem "and it explains itself in the reader's own language" \
       "envoyer" "$REC_FR"

t_memoria_esquece "$MEM_A" 2>/dev/null
t_receita_importa "$REC" "$MEM_A"
equal "a legitimate recipe is accepted" "0" "$?"
equal "  and becomes memory" "vcrun2022 msxml6" "$(t_memoria_le "$MEM_A" RESOLVERAM)"

# A recipe belongs to the FILE, not to the name. Applying another program's
# recipe would teach the wrong lesson, and nobody would notice.
t_receita_importa "$REC" "$MEM_B" 2>/dev/null
equal "another program's recipe is refused" "3" "$?"
equal "  and does not contaminate the other one's memory" "" "$(t_memoria_le "$MEM_B" RESOLVERAM 2>/dev/null)"

# The defence that matters most: a recipe's verb becomes an argument to
# "winetricks -q". A recipe coming from outside must not carry a command.
for veneno in 'vcrun2022 ;curl|sh' 'a$(rm -rf /)' '../../etc/passwd' 'a b`id`' 'a/b' 'a b c;d'; do
    # Built with grep+printf, not with sed: the poison itself has | and $ and
    # would break sed's delimiter before ever reaching the code under test.
    { grep -v '^RESOLVERAM=' "$REC"; printf 'RESOLVERAM=%s\n' "$veneno"; } > "$TMPROOT/veneno.txt"
    t_memoria_esquece "$MEM_A" 2>/dev/null
    t_receita_importa "$TMPROOT/veneno.txt" "$MEM_A" 2>/dev/null
    if [ "$?" = 4 ] && [ -z "$(t_memoria_le "$MEM_A" RESOLVERAM 2>/dev/null)" ]; then
        pass "refuses a recipe with an embedded command: $veneno"
    else
        fail "refuses a recipe with an embedded command: $veneno" "code 4 and nothing written" \
               "$(t_memoria_le "$MEM_A" RESOLVERAM 2>/dev/null)"
    fi
done

printf 'isto nao e receita\n' > "$TMPROOT/naorec.txt"
t_receita_importa "$TMPROOT/naorec.txt" "$MEM_A" 2>/dev/null
equal "a file that does not declare itself a recipe is refused" "2" "$?"
t_receita_importa /nao/existe "$MEM_A" 2>/dev/null
equal "a missing recipe fails without breaking" "1" "$?"

t_verbo_valido vcrun2022; equal "an ordinary verb name is accepted" "0" "$?"
t_verbo_valido 'a;b';      equal "a name with a semicolon is refused" "1" "$?"
t_verbo_valido '';         equal "an empty name is refused" "1" "$?"
t_verbo_valido "$(printf 'a%.0s' $(seq 1 60))"
equal "an absurdly long name is refused" "1" "$?"

t_memoria_esquece "$MEM_A" 2>/dev/null
t_memoria_grava "$MEM_A" RESULTADO abriu

t_memoria_esquece "$MEM_A"
equal "forgetting really erases" "" "$(t_memoria_le "$MEM_A" RESULTADO 2>/dev/null)"
t_memoria_esquece "$MEM_A" 2>/dev/null
equal "forgetting what does not exist fails without breaking" "1" "$?"

# -------------------------------------------------------- PE pre-flight

section "pre-flight: reading the .exe without running it"

pecampo() { python3 src/lib/peinfo.py "$1" 2>/dev/null | grep "^$2=" | cut -d= -f2-; }

equal "reads the architecture of a 64-bit PE" \
      "64" "$(pecampo "$ARTIFACTS/imports64.exe" ARQUITETURA)"
equal "reads the architecture of a 32-bit PE" \
      "32" "$(pecampo "$ARTIFACTS/imports32.exe" ARQUITETURA)"
equal "reads the whole import table" \
      "kernel32.dll,msvcp140.dll,vcruntime140.dll" \
      "$(pecampo "$ARTIFACTS/imports64.exe" DLLS)"
equal "normalizes the names to lowercase" \
      "hasp_windows_x64.dll,kernel32.dll" \
      "$(pecampo "$ARTIFACTS/imports32.exe" DLLS)"
equal "a file that is not a PE degrades with a message" \
      "nao_e_mz" "$(pecampo "$ARTIFACTS/naoexe.exe" ERRO)"
equal "a missing file degrades with a message" \
      "sem_arquivo" "$(pecampo /nao/existe.exe ERRO)"
python3 src/lib/peinfo.py >/dev/null 2>&1
equal "no argument returns a usage error" "2" "$?"

# What the pre-flight can prove on its own: recognizing, BEFORE running, what
# the program depends on - and, since 4.0, whether that has a way out. Until
# then every signature here produced the same "this has no fix", including for
# the largest dongle family on the market, whose manufacturer publishes the
# recipe for the exact Wine version this project targets.
limite() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_LIMITES="$ROOT/src/lib/limites.tsv" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_limite_do_programa "'"$1"'"' 2>/dev/null
}
semsaida() {
    TANDEM_LIB="$ROOT/src/lib" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_limite_sem_saida "'"$1"'" && echo sim || echo nao' 2>/dev/null
}

LIM_SENTINEL="$(limite "$ARTIFACTS/imports32.exe")"
equal "a modern Sentinel key is recognized as Sentinel, not as impossible" \
      "dongle-sentinel" "${LIM_SENTINEL%%|*}"
contem "and the owner is told what to install for it" \
       "Run-time Environment" "$LIM_SENTINEL"
equal "a Sentinel verdict is NOT a dead end" "nao" "$(semsaida dongle-sentinel)"

LIM_LEGADO="$(limite "$ARTIFACTS/hasplegado.exe")"
equal "an old HASP4 key stays impossible, and is told apart" \
      "dongle" "${LIM_LEGADO%%|*}"
equal "a HASP4 verdict IS a dead end" "sim" "$(semsaida dongle)"
naocontem "and it offers no way out, because there is none" \
          "Run-time Environment" "$LIM_LEGADO"

LIM_DRIVER="$(limite "$ARTIFACTS/driver.exe")"
equal "a file that imports the Windows kernel is a driver" \
      "driver" "${LIM_DRIVER%%|*}"
equal "a driver verdict IS a dead end" "sim" "$(semsaida driver)"

LIM_TEF="$(limite "$ARTIFACTS/tef.exe")"
equal "Brazilian card middleware is recognized" "tef" "${LIM_TEF%%|*}"
contem "and answered with the native library, which is the real lever" \
       "Linux" "$LIM_TEF"
equal "a TEF verdict is NOT a dead end" "nao" "$(semsaida tef)"

equal "an unknown class is treated as having a way out, never as hopeless" \
      "nao" "$(semsaida classe-que-nao-existe)"

equal "an ordinary program gets no impossibility verdict" \
      "" "$(limite "$ARTIFACTS/importslimpo.exe")"

# The verdict PROVEN by the log outranks the one guessed from the file. It is
# also the only way to catch the worst case: a driver that loads into user
# space, reads zeros off hollow hardware APIs, and makes the program look
# merely buggy.
printf '0009:fixme:ntoskrnl:MmMapIoSpace stub: 1000 4096 0\n' > "$TMPROOT/drv.log"
LIM_LOG="$(TANDEM_LIB="$ROOT/src/lib" bash -c \
    '. "'"$ROOT"'/src/lib/common.sh"; t_limite_do_log "'"$TMPROOT"'/drv.log"' 2>/dev/null)"
equal "a stubbed hardware call in the log proves a driver" "driver" "${LIM_LOG%%|*}"
contem "and says why the program opens and then misbehaves" \
       "handed it zeros" "$LIM_LOG"
# The proven half of the driver diagnosis was two Portuguese paragraphs written
# straight into the function, while the GUESSED half (limites.tsv) has had a
# translation per language since 4.2. Asserting it in Spanish is what tells the
# two apart.
LIM_LOG_ES="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=es bash -c \
    '. "'"$ROOT"'/src/lib/common.sh"; t_limite_do_log "'"$TMPROOT"'/drv.log"' 2>/dev/null)"
contem "and it says it in the reader's own language" \
       "devolvió ceros" "$LIM_LOG_ES"
printf '0009:err:module:import_dll Library FOO.dll not found\n' > "$TMPROOT/nodrv.log"
equal "an ordinary log proves nothing about drivers" "" \
      "$(TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_limite_do_log "'"$TMPROOT"'/nodrv.log"' 2>/dev/null)"

# The channels those lines arrive on are switched OFF by the WINEDEBUG the
# runner sets, so they have to be switched back on by name. Getting this wrong
# makes every test above pass and the feature never fire on a real machine.
contem "the runner re-enables the two channels that carry the proof" \
       "fixme+ntoskrnl" "$(grep '^export WINEDEBUG' "$ROOT/src/bin/tandem-exe")"

# ------------------------------------------------------------ PE reading

section "PE executable architecture"
equal "32-bit PE"  "32"    "$(t_pe_arch "$ARTIFACTS/prog32.exe")"
equal "64-bit PE"  "64"    "$(t_pe_arch "$ARTIFACTS/prog64.exe")"
equal "ARM64 PE"   "arm64" "$(t_pe_arch "$ARTIFACTS/progarm.exe")"
t_pe_arch "$ARTIFACTS/naoexe.exe" >/dev/null 2>&1
equal "a file that is not a PE fails" "1" "$?"
t_pe_arch /nao/existe >/dev/null 2>&1
equal "a missing file fails" "1" "$?"

# ------------------------------------------------------- Wine prefixes

section "Wine prefix protection"

PREF_NOSSO="$HOME/.local/share/tandem/wine"
PREF_ALHEIO="$HOME/.wine-pdv"
PREF_MARCADO="$HOME/.wine-tandem"
mkdir -p "$PREF_NOSSO/drive_c" "$PREF_ALHEIO/drive_c" "$PREF_MARCADO/drive_c"
touch "$PREF_NOSSO/system.reg" "$PREF_ALHEIO/system.reg" "$PREF_MARCADO/system.reg"
: > "$PREF_MARCADO/.tandem-prefixo"

t_prefixo_protegido "$PREF_ALHEIO";  equal "someone else's prefix is protected" "0" "$?"
t_prefixo_protegido "$PREF_NOSSO";   equal "the default prefix is not protected" "1" "$?"
t_prefixo_protegido "$PREF_MARCADO"; equal "a prefix carrying our mark is not protected" "1" "$?"
t_prefixo_protegido "$HOME/.wine-que-nao-existe"
equal "an unknown prefix is protected" "0" "$?"

# The user's explicit list has to beat even the ownership mark.
mkdir -p "$(dirname -- "$TANDEM_PROTEGIDOS")"
printf '%s\n' "$PREF_MARCADO" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$PREF_MARCADO"
equal "tandem protect beats Tandem's own mark" "0" "$?"
printf '%s\n' "$PREF_NOSSO" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$PREF_NOSSO"
equal "tandem protect also applies to the default prefix" "0" "$?"
: > "$TANDEM_PROTEGIDOS"

# Walks up the tree until it finds the prefix root.
mkdir -p "$PREF_ALHEIO/drive_c/Programas/Sistema"
touch "$PREF_ALHEIO/drive_c/Programas/Sistema/pdv.exe"
equal "finds the prefix root from the file path" \
      "$PREF_ALHEIO" \
      "$(t_prefixo_do_arquivo "$PREF_ALHEIO/drive_c/Programas/Sistema/pdv.exe")"
t_prefixo_do_arquivo "$TMPROOT/solto.exe" >/dev/null 2>&1
equal "a file outside any prefix fails" "1" "$?"

section "first-run scan"

# The scenario that failed on the real machine: two prefixes under ~/.wine* and
# an empty protected list because postinst never found out who had installed.
: > "$TANDEM_PROTEGIDOS"
PREF_FUNDO="$HOME/Programas/PDV/prefixo"
mkdir -p "$PREF_FUNDO/drive_c"
touch "$PREF_FUNDO/system.reg"

t_procura_prefixos

for esperado in "$PREF_ALHEIO" "$PREF_FUNDO"; do
    if grep -qxF -- "$esperado" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
        pass "the scan found $esperado"
    else
        fail "the scan found $esperado" "on the list" "missing"
    fi
done

if grep -qxF -- "$PREF_NOSSO" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    fail "the scan ignores Tandem's default prefix" "missing" "on the list"
else
    pass "the scan ignores Tandem's default prefix"
fi
if grep -qxF -- "$PREF_MARCADO" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    fail "the scan ignores a prefix carrying Tandem's mark" "missing" "on the list"
else
    pass "the scan ignores a prefix carrying Tandem's mark"
fi

# A directory with system.reg but no drive_c is not a Wine prefix.
mkdir -p "$HOME/naoprefixo"; touch "$HOME/naoprefixo/system.reg"
t_procura_prefixos
if grep -qxF -- "$HOME/naoprefixo" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    fail "system.reg without drive_c does not count as a prefix" "missing" "on the list"
else
    pass "system.reg without drive_c does not count as a prefix"
fi

t_procura_prefixos
equal "running twice does not duplicate the list" \
      "0" "$(sort "$TANDEM_PROTEGIDOS" | uniq -d | wc -l)"

t_protege "$PREF_ALHEIO"; equal "t_protege is idempotent" "0" "$?"
t_protege "/caminho/que/nao/existe"; equal "t_protege refuses an invalid path" "1" "$?"

# The first-run marker has to prevent the repeat.
MARCA_PV="$(dirname -- "$TANDEM_PROTEGIDOS")/.primeira-vez"
rm -f "$MARCA_PV"
t_primeira_vez
equal "the first run leaves the marker" "0" "$([ -f "$MARCA_PV" ]; echo $?)"
: > "$TANDEM_PROTEGIDOS"
t_primeira_vez
equal "the second run does not scan again" "0" "$(wc -l < "$TANDEM_PROTEGIDOS")"
rm -f "$MARCA_PV"; : > "$TANDEM_PROTEGIDOS"

# ------------------------------------------------------------- messages

section "upgrading: a version that learned a new format has to claim it"

# The mark used to be an empty file, so "already run once" meant "never again".
# A machine upgraded from a version that did not know .AppImage and .jar
# therefore never claimed them, and the double click went on doing nothing.
# Measured on a real container: after installing 3.7 over 3.6, .jar still
# answered openjdk-21-java.desktop, and the self-test said so.
CASA_UP="$TMPROOT/upgrade"; mkdir -p "$CASA_UP/.config/tandem"
ESPIA_REP="$TMPROOT/espia-repair"; mkdir -p "$ESPIA_REP"
cat > "$ESPIA_REP/tandem-repair" <<'FIMR'
#!/bin/sh
printf '%s\n' "${1:-completo}" >> "$TANDEM_CHAMADAS"
FIMR
chmod +x "$ESPIA_REP/tandem-repair"

chamar_primeira_vez() {
    env HOME="$CASA_UP" TANDEM_BIN="$ESPIA_REP" TANDEM_CHAMADAS="$TMPROOT/chamadas.txt" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_primeira_vez' 2>/dev/null
}

# A genuine first run: the prefix scan happens and every type is claimed.
: > "$TMPROOT/chamadas.txt"
chamar_primeira_vez
equal "on a first run, the associations are applied in full" \
      "completo" "$(cat "$TMPROOT/chamadas.txt")"
equal "and the mark records which version did it" \
      "$(grep '^TANDEM_VERSAO=' "$ROOT/src/lib/common.sh" | cut -d'"' -f2)" \
      "$(cat "$CASA_UP/.config/tandem/.primeira-vez")"

# Running again with the same version does nothing at all: whoever changed an
# association on purpose does not want it rewritten on every double click.
: > "$TMPROOT/chamadas.txt"
chamar_primeira_vez
equal "running again on the same version does not touch the associations" \
      "" "$(cat "$TMPROOT/chamadas.txt")"

# An upgrade from an older version: the narrow mode, which claims only types
# this machine has never claimed.
printf '3.6\n' > "$CASA_UP/.config/tandem/.primeira-vez"
: > "$TMPROOT/chamadas.txt"
chamar_primeira_vez
equal "an upgrade claims only the types that are new" \
      "--somente-novos" "$(cat "$TMPROOT/chamadas.txt")"

# And the empty mark left by every version before this one counts as an upgrade,
# not as a first run - that is the case that was actually broken.
: > "$CASA_UP/.config/tandem/.primeira-vez"
: > "$TMPROOT/chamadas.txt"
chamar_primeira_vez
equal "the empty mark left by an old version counts as an upgrade" \
      "--somente-novos" "$(cat "$TMPROOT/chamadas.txt")"

# tandem-repair itself: --somente-novos must skip what is recorded and claim
# what is not, and the full run must claim everything.
CASA_REP="$TMPROOT/repair"; mkdir -p "$CASA_REP/.config/tandem"
correr_repair() {
    env -i HOME="$CASA_REP" PATH="/usr/bin:/bin" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_SILENCIOSO=1 bash "$ROOT/src/bin/tandem-repair" "$@" >/dev/null 2>&1
}
correr_repair
aplicados="$CASA_REP/.config/tandem/tipos-aplicados.txt"
if grep -qxF 'application/vnd.appimage' "$aplicados" 2>/dev/null &&
   grep -qxF 'application/java-archive' "$aplicados" 2>/dev/null &&
   grep -qxF 'application/x-ms-dos-executable' "$aplicados" 2>/dev/null; then
    pass "a full repair records every type it claimed"
else
    fail "a full repair records every type it claimed" \
         "exe, appimage and jar recorded" "$(tr '\n' ' ' < "$aplicados" 2>/dev/null)"
fi
antes="$(grep -c . "$aplicados")"
correr_repair --somente-novos
equal "a second narrow repair has nothing left to claim" \
      "$antes" "$(grep -c . "$aplicados")"
# Drop one line and the narrow mode has to notice exactly that one.
grep -vxF 'application/java-archive' "$aplicados" > "$aplicados.tmp"
mv "$aplicados.tmp" "$aplicados"
correr_repair --somente-novos
if grep -qxF 'application/java-archive' "$aplicados" 2>/dev/null; then
    pass "the narrow repair claims the one type that was missing"
else
    fail "the narrow repair claims the one type that was missing" \
         "application/java-archive recorded again" "still absent"
fi
# The .jar association written to mimeapps.list must name the jar handler and
# not some other one: the table that maps type to handler is easy to get wrong
# and impossible to notice by reading.
if grep -qxF 'application/java-archive=tandem-jar.desktop' \
        "$CASA_REP/.config/mimeapps.list" 2>/dev/null &&
   grep -qxF 'application/vnd.appimage=tandem-appimage.desktop' \
        "$CASA_REP/.config/mimeapps.list" 2>/dev/null; then
    pass "each type is pointed at its own handler"
else
    fail "each type is pointed at its own handler" \
         "jar->tandem-jar, appimage->tandem-appimage" \
         "$(grep -E 'java-archive|appimage' "$CASA_REP/.config/mimeapps.list" 2>/dev/null | tr '\n' ' ')"
fi

section "no message gets lost"

t_tem_gui; equal "without DISPLAY there is no graphical interface" "1" "$?"

t_log_init teste "suite"
equal "an error without a graphical interface goes to the terminal" \
      "Tandem: deu ruim" \
      "$(t_erro "deu ruim" 2>&1 1>/dev/null)"
equal "a warning without a graphical interface goes to the terminal" \
      "Tandem: atencao" \
      "$(t_aviso "atencao" 2>&1 1>/dev/null)"
equal "a success without a graphical interface goes to the terminal" \
      "Tandem: pronto" \
      "$(t_ok "pronto" 2>&1 1>/dev/null)"

t_erro "mensagem que precisa ficar registrada" >/dev/null 2>&1
if grep -q "ERRO: mensagem que precisa ficar registrada" "$LOG" 2>/dev/null; then
    pass "the error is recorded in the log for the post-mortem"
else
    fail "the error is recorded in the log for the post-mortem" "line in the log" "missing"
fi

t_pergunta "posso?" >/dev/null 2>&1
equal "a question without a graphical interface answers no" "1" "$?"

equal "long text falls back to standard output without a graphical interface" \
      "linha um" "$(printf 'linha um\n' | t_texto 'titulo')"

# With a graphical interface, pipes and files still receive the text: whoever
# writes "tandem doctor > relatorio.txt" wants the report, not a window.
equal "with a display, the pipe still receives the text" \
      "contents" \
      "$(DISPLAY=:0 bash -c '. "'"$ROOT"'/src/lib/common.sh"; printf "contents\n" | t_texto t' | cat)"
DISPLAY=:0 bash -c '. "'"$ROOT"'/src/lib/common.sh"; printf "contents\n" | t_texto t' > "$TMPROOT/redir.txt"
equal "with a display, the file still receives the text" \
      "contents" "$(cat "$TMPROOT/redir.txt")"

# the diagnostics printf must not interpret a % coming from a path
equal "a percent sign in text does not break the output" \
      "50% pronto" "$(printf '%b' "50% pronto")"

section "MIME types of split packages"

# Without these types a double click on a .xapk never reaches Tandem:
# freedesktop does not know the extension and the system sees only a generic ZIP.
equal "the MIME types file is valid XML" "ok" \
      "$(python3 -c 'import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print("ok")' \
         src/mime/tandem.xml 2>&1 | tail -1)"

for tipo in vnd.android.xapk vnd.android.apks vnd.android.apkm; do
    if grep -q "application/$tipo" src/mime/tandem.xml; then
        pass "declares application/$tipo"
    else
        fail "declares application/$tipo" "present" "missing"
    fi
    if grep -q "application/$tipo" src/applications/tandem-apk.desktop; then
        pass "  and the .desktop claims the type"
    else
        fail "  and the .desktop claims the type" "present" "missing"
    fi
    if grep -q "application/$tipo" src/bin/tandem-repair; then
        pass "  and repair reapplies the type"
    else
        fail "  and repair reapplies the type" "present" "missing"
    fi
done

# Being a subclass of zip is what makes the extension match beat content
# detection: without it the system insists the file is a ZIP.
if grep -q 'sub-class-of.*application/zip' src/mime/tandem.xml; then
    pass "the types are subclasses of application/zip"
else
    fail "the types are subclasses of application/zip" "sub-class-of zip" "missing"
fi

section "the progress bar must not kill Tandem"

# Panel finding, confirmed: with the pipe opened write-only, closing the
# progress window sent SIGPIPE and killed the whole process - exit 141, nothing
# in the log, no window. Inside the winetricks loop that cut a dependency
# installation in half.
FZ="$TMPROOT/fz"; mkdir -p "$FZ"
printf '#!/bin/sh\nhead -c1 >/dev/null 2>&1\nexit 0\n' > "$FZ/zenity"
chmod +x "$FZ/zenity"
cat > "$TMPROOT/prog.sh" <<FIM
export HOME="$HOME"
export PATH="$FZ:\$PATH"
export DISPLAY=:0
. "$ROOT/src/lib/common.sh"
t_log_init progteste x
t_progresso_abre "instalando"
sleep 0.4
t_progresso_texto "primeiro"
sleep 0.2
t_progresso_texto "segundo"
t_progresso_fecha
echo VIVO
FIM
saida_prog="$(bash "$TMPROOT/prog.sh" 2>/dev/null)"; rc_prog=$?
equal "the script survives the progress window being closed" "0" "$rc_prog"
equal "  and reaches the end" "VIVO" "$saida_prog"
if grep -q 'janela de progresso fechada' "$TANDEM_ESTADO/progteste.log" 2>/dev/null; then
    pass "  and records in the log that the window vanished"
else
    fail "  and records in the log that the window vanished" "line in the log" "missing"
fi

section "locks: being unable to create one is not the same as it being taken"

equal "locks live in the runtime directory when it exists" \
      "$TMPROOT/run/tandem" \
      "$(XDG_RUNTIME_DIR="$TMPROOT/run" bash -c '. "'"$ROOT"'/src/lib/common.sh"; printf %s "$TANDEM_TRAVAS"')"
equal "without a runtime directory, falls back to the state folder" \
      "$TANDEM_ESTADO" \
      "$(env -u XDG_RUNTIME_DIR bash -c '. "'"$ROOT"'/src/lib/common.sh"; printf %s "$TANDEM_TRAVAS"')"

# bash does NOT abort when an "exec N>" fails: without telling the two cases
# apart, a full home folder turned into "this program is already opening" and
# exit 0.
equal "exec with an invalid path fails without bringing the script down" \
      "seguiu" \
      "$(bash -c 'if exec 7> /nao/existe/x.lock; then echo travou; else echo seguiu; fi' 2>/dev/null)"

section "menu shortcuts after an installer"

APPS="$HOME/.local/share/applications/wine/Programs/Coisa"
mkdir -p "$APPS"
ANTES_AT="$(t_atalhos_wine)"
equal "with no shortcut at all, the list comes back empty" "" "$ANTES_AT"

equal "nothing new, nothing announced" \
      "" "$(t_anuncia_atalhos "$ANTES_AT" 2>&1 1>/dev/null)"

: > "$APPS/Coisa Legal.desktop"
saida_at="$(t_anuncia_atalhos "$ANTES_AT" 2>&1 1>/dev/null)"
case "$saida_at" in
    *"Coisa Legal"*) pass "a new shortcut is announced by name" ;;
    *) fail "a new shortcut is announced by name" "mentions 'Coisa Legal'" "$saida_at" ;;
esac

# Once announced, the same earlier list must not announce it again: the
# comparison has to be against the current state.
DEPOIS_AT="$(t_atalhos_wine)"
equal "an already known shortcut is not re-announced" \
      "" "$(t_anuncia_atalhos "$DEPOIS_AT" 2>&1 1>/dev/null)"

section "installed programs and uninstallation"

# A real prefix's registry, abridged: one entry in the native view, one in the
# 32-bit view (Wow6432Node - the 7-Zip case from the real machine), a system
# component that must not show up, and junk with no uninstaller.
cat > "$PREF_NOSSO/system.reg" <<'FIM'
WINE REGISTRY Version 2
;; All keys relative to \\Machine

[Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{GUID-MSI}] 1786062085
"DisplayName"="Programa MSI 1.0"
"UninstallString"="MsiExec.exe /X{GUID-MSI}"

[Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\SoRuntime] 1786062085
"DisplayName"="Runtime Oculto"
"SystemComponent"=dword:00000001
"UninstallString"="C:\\x.exe"

[Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\SemNada] 1786062085
"DisplayName"="Sem Desinstalador"

[Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\7-Zip] 1786062085
"DisplayName"="7-Zip 24.09 (x64)"
"QuietUninstallString"="\"C:\\Program Files\\7-Zip\\Uninstall.exe\" /S"
"UninstallString"="\"C:\\Program Files\\7-Zip\\Uninstall.exe\""
FIM

equal "reads BOTH registry views (native and 32-bit)" \
      "7-Zip 24.09 (x64) Programa MSI 1.0" \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '{print $2}' | sort | tr '\n' ' ' | sed 's/ $//')"

equal "a system component is left out" \
      "" "$(t_uninstall_dump "$PREF_NOSSO" | grep -c Oculto | sed 's/^0$//')"

equal "an entry with no uninstaller is left out" \
      "" "$(t_uninstall_dump "$PREF_NOSSO" | grep -c SemNada | sed 's/^0$//')"

equal "extracts the silent uninstaller with quotes and a real path" \
      '"C:\Program Files\7-Zip\Uninstall.exe" /S' \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '$1=="7-Zip"{print $3}')"

equal "extracts the key that identifies the program" \
      "{GUID-MSI}" \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '$2=="Programa MSI 1.0"{print $1}')"

equal "t_programas_instalados keeps the key|||name format" \
      "7-Zip|||7-Zip 24.09 (x64)" \
      "$(t_programas_instalados "$PREF_NOSSO" | grep '^7-Zip')"

# The Windows command separator: quoted path + argument.
FALSO="$TMPROOT/bin"; mkdir -p "$FALSO"
cat > "$FALSO/wine" <<'FIM'
#!/bin/sh
printf '%s\n' "exe=$1" "args=$*"
FIM
chmod +x "$FALSO/wine"
PATH="$FALSO:$PATH"

equal "runs an uninstaller with a quoted path" \
      'exe=C:\Program Files\7-Zip\Uninstall.exe' \
      "$(t_executa_comando_windows '"C:\Program Files\7-Zip\Uninstall.exe" /S' | head -1)"
equal "  and passes the arguments through" \
      'args=C:\Program Files\7-Zip\Uninstall.exe /S' \
      "$(t_executa_comando_windows '"C:\Program Files\7-Zip\Uninstall.exe" /S' | tail -1)"
equal "runs a command without quotes (MsiExec)" \
      'exe=MsiExec.exe' \
      "$(t_executa_comando_windows 'MsiExec.exe /X{GUID-MSI}' | head -1)"

section "preparar: Tandem installs what is missing"

# On an empty PATH nothing exists, so the list has to come back complete - that
# way the test does not depend on what is installed on the machine running the
# suite.
faltas="$(PATH=/nao/existe t_pecas_faltando | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')"
equal "with nothing installed, lists everything that is missing" \
      "wine winetricks adb java fuse waydroid" "$faltas"
# And with everything present, the list comes back empty. FUSE is not a command
# on the PATH, so it is answered by the stub of the function instead.
FINGE="$TMPROOT/finge"; mkdir -p "$FINGE"
for c in wine winetricks adb java waydroid; do printf '#!/bin/sh\n' > "$FINGE/$c"; chmod +x "$FINGE/$c"; done
t_tem_fuse2() { return 0; }
equal "with everything installed, there is nothing to prepare" \
      "" "$(PATH="$FINGE" t_pecas_faltando | grep -v '^wine32|' )"
unset -f t_tem_fuse2
. "$ROOT/src/lib/common.sh"

script="$(t_script_instalacao wine wine32 waydroid)"
case "$script" in
    *"apt-get install -y wine winetricks"*) pass "the plan installs wine and winetricks together" ;;
    *) fail "the plan installs wine and winetricks together" "apt-get install -y wine winetricks" "$script" ;;
esac
case "$script" in
    *"dpkg --add-architecture i386"*) pass "the plan enables 32-bit before wine32" ;;
    *) fail "the plan enables 32-bit before wine32" "dpkg --add-architecture i386" "(missing)" ;;
esac
case "$script" in
    *"repo.waydro.id"*signed-by*) pass "waydroid comes from the official repository with a key" ;;
    *) fail "waydroid comes from the official repository with a key" "repo.waydro.id + signed-by" "(missing)" ;;
esac
case "$script" in
    *"waydroid init"*) pass "the plan initializes Android after installing" ;;
    *) fail "the plan initializes Android after installing" "waydroid init" "(missing)" ;;
esac

# t_como_root: are we root in the tests? then run it directly.
if [ "$(id -u)" = 0 ]; then
    equal "as root, runs directly without asking for a password" \
          "funcionou" "$(t_como_root 'echo funcionou')"
else
    skip "as root runs directly" "suite running without root"
fi

# Shortcuts: only the ones in our prefix, and an orphan is one that lost its .lnk.
WP="$HOME/.local/share/applications/wine/Programs"
mkdir -p "$WP/7-Zip" "$WP/Alheio"
printf '[Desktop Entry]\nName=7-Zip File Manager\nExec=env WINEPREFIX="%s" wine x\n' \
       "$PREF_NOSSO" > "$WP/7-Zip/7-Zip File Manager.desktop"
printf '[Desktop Entry]\nName=Coisa Alheia\nExec=env WINEPREFIX="%s" wine x\n' \
       "$PREF_ALHEIO" > "$WP/Alheio/Coisa Alheia.desktop"

equal "lists only the shortcuts from our prefix" \
      "1" "$(t_atalhos_nossos | wc -l)"
equal "reads the friendly name of the shortcut" \
      "7-Zip File Manager" "$(t_nome_do_atalho "$WP/7-Zip/7-Zip File Manager.desktop")"

# With the .lnk present, the shortcut is valid and must not be removed.
LNKDIR="$PREF_NOSSO/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/7-Zip"
mkdir -p "$LNKDIR"; : > "$LNKDIR/7-Zip File Manager.lnk"
equal "a shortcut whose program is installed is not removed" "0" "$(t_limpa_atalhos_orfaos)"
equal "  and stays on disk" \
      "0" "$([ -f "$WP/7-Zip/7-Zip File Manager.desktop" ]; echo $?)"

# Without the .lnk it became a button that opens nothing: it has to go.
rm -f "$LNKDIR/7-Zip File Manager.lnk"
equal "an orphan shortcut is removed" "1" "$(t_limpa_atalhos_orfaos)"
equal "  and is gone from disk" \
      "1" "$([ -f "$WP/7-Zip/7-Zip File Manager.desktop" ]; echo $?)"
equal "  and someone else's shortcut was preserved" \
      "0" "$([ -f "$WP/Alheio/Coisa Alheia.desktop" ]; echo $?)"

# Without wine on the PATH the listing fails without breaking the caller.
equal "without wine, the listing degrades in controlled silence" \
      "" "$(PATH=/does/not/exist; export PATH; t_programas_instalados 2>/dev/null)"

section "Wine architecture"
t_tem_wine64; r64=$?
t_tem_wine32; r32=$?
case "$r64$r32" in
    [01][01]) pass "t_tem_wine64 and t_tem_wine32 return 0 or 1" ;;
    *) fail "t_tem_wine64 and t_tem_wine32 return 0 or 1" "0 or 1" "$r64$r32" ;;
esac

section "locale (zenity refuses accents on a nonexistent locale)"

t_locale_existe C.UTF-8;     equal "recognizes an existing locale despite the hyphen" "0" "$?"
t_locale_existe c.utf8;      equal "the comparison ignores case and hyphens" "0" "$?"
t_locale_existe zz_ZZ.UTF-8; equal "refuses a nonexistent locale" "1" "$?"
t_locale_existe "";          equal "refuses an empty locale" "1" "$?"

equal "picks the first candidate that exists" \
      "C.UTF-8" "$(t_locale_utf8 zz_ZZ.UTF-8 C.UTF-8)"
equal "falls back to C.UTF-8 when none exists" \
      "C.UTF-8" "$(t_locale_utf8 zz_ZZ.UTF-8 yy_YY.UTF-8)"
equal "with no candidate at all it still returns something usable" \
      "C.UTF-8" "$(t_locale_utf8)"
equal "an empty candidate does not disturb the choice" \
      "C.UTF-8" "$(t_locale_utf8 "" "" C.UTF-8)"

# What matters in the end: the chosen locale has to produce a UTF-8 charmap,
# because that is what decides whether zenity accepts or refuses accented text.
equal "the chosen locale produces a UTF-8 charmap" \
      "UTF-8" "$(LC_ALL="$(t_locale_utf8 zz_ZZ.UTF-8)" locale charmap 2>/dev/null)"

# -------------------------------------------------------------- apkinfo

section "Android package inspection"

campo() { python3 src/lib/apkinfo.py "$1" 2>/dev/null | grep "^$2=" | cut -d= -f2-; }

equal "plain apk: format"         "apk"                   "$(campo "$ARTIFACTS/universal.apk" FORMATO)"
equal "plain apk: package"        "com.exemplo.universal" "$(campo "$ARTIFACTS/universal.apk" PACOTE)"
equal "plain apk: minimum sdk"    "21"                    "$(campo "$ARTIFACTS/universal.apk" MINSDK)"
equal "universal apk: no ABI"     ""                      "$(campo "$ARTIFACTS/universal.apk" ABIS)"

equal "x86 apk: ABIs"             "x86,x86_64"            "$(campo "$ARTIFACTS/x86.apk" ABIS)"
equal "ARM-only apk: ABIs"        "arm64-v8a,armeabi-v7a" "$(campo "$ARTIFACTS/armonly.apk" ABIS)"
equal "demanding apk: minimum sdk" "99"                   "$(campo "$ARTIFACTS/futuro.apk" MINSDK)"

equal "xapk: format"              "xapk"                  "$(campo "$ARTIFACTS/jogo.xapk" FORMATO)"
equal "xapk: package comes from the base apk" "com.exemplo.jogo" "$(campo "$ARTIFACTS/jogo.xapk" PACOTE)"
equal "xapk: sdk comes from the base apk" "24"                  "$(campo "$ARTIFACTS/jogo.xapk" MINSDK)"
equal "xapk: counts the parts"    "2"                     "$(campo "$ARTIFACTS/jogo.xapk" SPLITS)"
equal "xapk: detects OBB"         "1"                     "$(campo "$ARTIFACTS/jogo.xapk" OBB)"

equal "apks: format"              "apks"                  "$(campo "$ARTIFACTS/app.apks" FORMATO)"
equal "apks: counts the parts"    "3"                     "$(campo "$ARTIFACTS/app.apks" SPLITS)"
equal "apks: no OBB"              "0"                     "$(campo "$ARTIFACTS/app.apks" OBB)"

equal "a corrupt file degrades with a message" \
      "apk_corrompido" \
      "$(campo "$ARTIFACTS/corrompido.apk" ERRO)"
equal "an empty file degrades with a message" \
      "apk_corrompido" \
      "$(campo "$ARTIFACTS/vazio.apk" ERRO)"
equal "a missing file degrades with a message" \
      "sem_arquivo" \
      "$(campo /nao/existe.apk ERRO)"

python3 src/lib/apkinfo.py >/dev/null 2>&1
equal "no argument returns a usage error" "2" "$?"

# ------------------------------------------------------------- package

section "no command comes out mute"

# t_texto reads the CONTENT from standard input and uses the argument as the
# TITLE. Five new commands passed the text as an argument and read an empty
# stdin: they ran, exited 0 and printed NOT ONE LINE. No test caught it because
# they all exercised library functions, never the whole command.
# Found by running "tandem dados" on a real Ubuntu.
CASA_C="$TMPROOT/cli"; mkdir -p "$CASA_C/.local/share/tandem/wine/drive_c/windows"
: > "$CASA_C/.local/share/tandem/wine/system.reg"
: > "$CASA_C/.local/share/tandem/wine/.tandem-prefixo"
: > "$CASA_C/.primeira-vez"
for cmd in "dados" "lista" "doctor" "identidade" "portas" "--help" "version"; do
    output="$(env -i HOME="$CASA_C" PATH="/usr/bin:/bin" TANDEM_LIB="$ROOT/src/lib" \
             bash "$ROOT/src/bin/tandem" $cmd 2>&1)"
    if [ -n "$output" ]; then pass "\"tandem $cmd\" prints something"
    else fail "\"tandem $cmd\" prints something" "any text" "zero bytes"; fi
done

# And wrong usage has to degrade, never come out mute: with nothing on the
# input, t_texto prints at least the title.
equal "t_texto with no content prints the title" \
      "Titulo qualquer" "$(t_texto "Titulo qualquer" < /dev/null)"
# The guard against freezing can only be exercised where a terminal exists.
if [ -c /dev/tty ] && (exec < /dev/tty) 2>/dev/null; then
    timeout 5 bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_texto "T" < /dev/tty' >/dev/null 2>&1
    equal "t_texto with a terminal on the input does not hang" "0" "$?"
else
    skip "t_texto with a terminal on the input" "the suite runs without a controlling terminal"
fi

section "the machine's identity, held still"

# Nothing here starts Wine. Every value is read out of /sys, /proc or
# system.reg, which is what makes the diagnosis instant and safe to run on a
# counter in the middle of a working day.

SER1="$(t_identidade_serial)"
SER2="$(t_identidade_serial)"
equal "the volume serial is eight hex digits" \
      "sim" "$(case "$SER1" in [0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]) echo sim ;; *) echo "nao ($SER1)" ;; esac)"
equal "and it is the same every time it is asked" "$SER1" "$SER2"
# The whole point: it is derived from the machine, not drawn at random. A
# prefix destroyed and remade has to come back as the same computer, because
# losing an activation on a rebuild is the failure people actually report.
naocontem "the serial is not the placeholder unless there is no seed" \
          "00000000" "$SER1"

GUID1="$(t_identidade_guid)"
equal "the machine identifier has the shape of a GUID" \
      "sim" "$(case "$GUID1" in
                 [0-9a-f]????????-????-????-????-???????????) echo nao ;;
                 ????????-????-????-????-????????????) echo sim ;;
                 *) echo "nao ($GUID1)" ;; esac)"
equal "and it is stable too" "$GUID1" "$(t_identidade_guid)"
equal "the two are not the same number wearing two hats" \
      "diferentes" "$(case "$GUID1" in "$SER1"*) echo iguais ;; *) echo diferentes ;; esac)"

# A synthetic system.reg in the shape Wine actually writes: keys carry DOUBLED
# backslashes. That detail is the whole test - passing the key through
# "awk -v" eats half of them, the key never matches, and every value reads as
# absent while the code looks correct.
PREF_ID="$TMPROOT/prefixo-id"
mkdir -p "$PREF_ID/drive_c"
cat > "$PREF_ID/system.reg" <<'REG'
WINE REGISTRY Version 2

[Software\\Microsoft\\Cryptography] 1700000000
#time=1d000000000
"MachineGuid"="11112222-3333-4444-5555-666677778888"

[Software\\Microsoft\\Windows NT\\CurrentVersion] 1700000000
"ProductId"="12345-oem-0000001-54321"
"ProductName"="Microsoft Windows 10"

[Software\\Wine\\Ports] 1700000000
"COM2"="/dev/ttyACM0"
REG
equal "reads a value out of system.reg without starting Wine" \
      "11112222-3333-4444-5555-666677778888" \
      "$(t_reg_valor "$PREF_ID" 'Software\\Microsoft\\Cryptography' MachineGuid)"
equal "and one from a key whose name has a space in it" \
      "12345-oem-0000001-54321" \
      "$(t_reg_valor "$PREF_ID" 'Software\\Microsoft\\Windows NT\\CurrentVersion' ProductId)"
equal "a value that is not there reads as empty, not as the next key's" \
      "" "$(t_reg_valor "$PREF_ID" 'Software\\Microsoft\\Cryptography' NaoExiste)"
equal "lists every value of one key" \
      "COM2 = /dev/ttyACM0" \
      "$(t_reg_lista_valores "$PREF_ID" 'Software\\Wine\\Ports')"

TEXTO_ID="$(t_texto_identidade "$PREF_ID")"
contem "the report names the constant every Wine install reports" \
       "identical" "$TEXTO_ID"
contem "and says the ProductId is Wine's own, not this machine's" \
       "does not invent another one" "$TEXTO_ID"
contem "and shows the frozen identifier" \
       "11112222-3333-4444-5555-666677778888" "$TEXTO_ID"

# Freezing is done ONCE, at creation. A prefix where something has already
# activated must not have its identity moved underneath it - that is the very
# loss the feature exists to prevent, and doing it late causes it.
PREF_FIX="$TMPROOT/prefixo-fixa"
mkdir -p "$PREF_FIX/drive_c"
# Our mark, because the function now refuses a prefix that does not carry it.
# Rule number 1 was documented in that function's comment and enforced only by
# its caller, which is one accident away from not being enforced at all.
: > "$PREF_FIX/.tandem-prefixo"
t_identidade_fixa "$PREF_FIX" >/dev/null 2>&1
equal "freezing writes the volume serial into the drive root" \
      "$SER1" "$(cat "$PREF_FIX/drive_c/.windows-serial" 2>/dev/null)"
contem "and records the seed, so a machine-id change becomes diagnosable" \
       "SEMENTE=" "$(cat "$PREF_FIX/.tandem-identidade" 2>/dev/null)"
printf 'DEADBEEF\n' > "$PREF_FIX/drive_c/.windows-serial"
t_identidade_fixa "$PREF_FIX" >/dev/null 2>&1
equal "a serial that already exists is never overwritten" \
      "DEADBEEF" "$(cat "$PREF_FIX/drive_c/.windows-serial" 2>/dev/null)"

section "serial ports: 32 sockets this machine does not have"

# From a photograph of a real counter. "tandem portas" listed COM1 through
# COM32 and put the shop's one real device - a USB adapter - on COM33. The
# comment in the source said "a PC already has three or four /dev/ttyS*". It
# has THIRTY-TWO: the kernel's 8250 driver registers 32 lines whether or not
# any serial hardware exists, and a modern PC has none of them.
#
# So the list told a shopkeeper there were 32 places to plug a pinpad into, on
# a machine with zero, and buried the one line that mattered under 32 that did
# not.

SYSFAKE="$TMPROOT/sysfake"
mkdir -p "$SYSFAKE/class/tty"
for i in $(seq 0 31); do
    mkdir -p "$SYSFAKE/class/tty/ttyS$i"
    printf '0\n' > "$SYSFAKE/class/tty/ttyS$i/type"      # PORT_UNKNOWN
done
mkdir -p "$SYSFAKE/class/tty/ttyS40"; printf '4\n' > "$SYSFAKE/class/tty/ttyS40/type"
mkdir -p "$SYSFAKE/class/tty/ttyS41"                       # no "type" at all

portas() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_SYS="$SYSFAKE" \
    TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_portas_seriais() { '"$1"'; }
        t_portas_paralelas() { :; }
        t_no_grupo() { return 0; }
        t_texto_portas ""' 2>/dev/null
}

equal "a kernel line with no UART behind it is a phantom" "0" \
      "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_SYS="$SYSFAKE" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_porta_fantasma /dev/ttyS0; echo $?')"
equal "a real 16550A is not a phantom" "1" \
      "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_SYS="$SYSFAKE" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_porta_fantasma /dev/ttyS40; echo $?')"
# Being unable to tell has to mean real. Hiding a port that exists breaks the
# only thing this section is for, which is worse than printing a line too many.
equal "a port we cannot inspect counts as real" "1" \
      "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_SYS="$SYSFAKE" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_porta_fantasma /dev/ttyS41; echo $?')"
equal "a USB adapter is never called a phantom" "1" \
      "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_SYS="$SYSFAKE" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_porta_fantasma /dev/ttyUSB0; echo $?')"

BALCAO='for i in $(seq 0 31); do echo /dev/ttyS$i; done; echo /dev/ttyUSB0'
saida_balcao="$(portas "$BALCAO")"

# The numbering must stay faithful to Wine, which counts the phantoms too.
# Renumbering the device to COM1 here would print a port the program will
# never be told about.
contem "the device keeps the number Wine will really give it" \
       "COM33" "$saida_balcao"
contem "and it is pointed at, so the eye lands on it" \
       "your device" "$saida_balcao"
contem "the 32 phantoms collapse into one range" \
       "COM1 to COM32" "$saida_balcao"
naocontem "so the middle of the run never reaches the screen" \
       "COM17" "$saida_balcao"
naocontem "nor does its device node" "/dev/ttyS16" "$saida_balcao"
contem "the advice that actually fixes it is still there" \
       "tandem portas fixar COM2 /dev/ttyUSB0" "$saida_balcao"

# 33 lines of ports became a handful. That compression IS the fix: the owner
# was reading a wall.
linhas_balcao="$(printf '%s\n' "$saida_balcao" | awk 'END { print NR }')"
if [ "$linhas_balcao" -lt 20 ]; then
    pass "the whole report fits on a screen ($linhas_balcao lines)"
else
    fail "the whole report fits on a screen" "under 20 lines" "$linhas_balcao"
fi

# A machine whose every socket is invented should be told so plainly,
# otherwise the range line reads as 32 places to plug something into.
saida_vazio="$(portas 'for i in $(seq 0 31); do echo /dev/ttyS$i; done')"
contem "a machine with only phantoms says it has no real port" \
       "No real serial port" "$saida_vazio"
contem "and points at the USB adapter as the way in" \
       "USB adapter" "$saida_vazio"

# The guard that matters most: a real port must never be swallowed by the
# phantom filter. A shop with a genuine COM1 has to keep seeing it.
saida_real="$(portas 'echo /dev/ttyS40; echo /dev/ttyUSB0')"
contem "a real serial port is still listed one by one" "/dev/ttyS40" "$saida_real"
naocontem "and is not folded into the phantom range" "always creates" "$saida_real"
naocontem "a machine with a real port is not told it has none" \
          "Nenhuma porta serial de verdade" "$saida_real"

section "install: name the right cause, or say nothing at all"

# All of this comes from one photograph of a real screen. The owner got a
# dialog saying "I did not recognise the type of this file" and went looking
# for a defect in Tandem's format support. There was no file: the word they
# typed was a mistyped command, and the case at the bottom of the script sends
# every unrecognised word to acao_install, which sniffed the contents of a
# path that does not exist with "head ... 2>/dev/null", failed every test in
# silence, and blamed the file type.
#
# Naming the WRONG cause is worse than naming none. These tests exist so that
# each of these mistakes keeps its own answer.

CASO="$TMPROOT/instalar"
mkdir -p "$CASO"
# The repository tracks src/bin as non-executable - build.py is what stamps
# 0755 into the package - so routing by extension, which is an "exec", needs a
# bin directory the kernel will actually run. Copy once, here.
BIN_EXEC="$TMPROOT/bin-exec"
mkdir -p "$BIN_EXEC"
cp "$ROOT"/src/bin/* "$BIN_EXEC"/ 2>/dev/null
chmod +x "$BIN_EXEC"/* 2>/dev/null
inst() {
    env HOME="$TMPROOT/h-inst" PATH="$PATH" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$BIN_EXEC" \
        bash "$ROOT/src/bin/tandem" install "$@" 2>&1
}

contem "a mistyped command is a mistyped command, not a file type" \
       "tandem --help" "$(env HOME="$TMPROOT/h-inst" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_BIN="$ROOT/src/bin" bash "$ROOT/src/bin/tandem" intalar 2>&1)"
naocontem "and it is not reported as an unrecognised file type" \
       "recognise the type" "$(env HOME="$TMPROOT/h-inst" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_BIN="$ROOT/src/bin" bash "$ROOT/src/bin/tandem" intalar 2>&1)"

# A path that does not exist is a missing file whether or not its name carries
# an extension Tandem knows. The extension-less case is the one that used to
# fall through to content sniffing.
contem "a missing .deb says the file is missing" \
       "File not found" "$(inst "$CASO/nao-existe.deb")"
contem "a missing file with no extension says the same" \
       "File not found" "$(inst "$CASO/nao-existe")"
naocontem "and neither blames the file type" \
       "recognise the type" "$(inst "$CASO/nao-existe")"

# A folder is not a half-readable file: say which mistake it is.
contem "a folder is reported as a folder" "folder" "$(inst "$CASO")"

# The download that goes wrong rarely produces nothing. The site answers with
# an error page or a login wall and the browser saves that HTML under the name
# the link promised - so the file really is called programa.deb and really does
# start with <!DOCTYPE html>. Every reader in this project would otherwise
# report its own local disappointment ("no ar signature"), which is true,
# useless, and sends the owner looking in the wrong place.
printf '<!DOCTYPE html>\n<html><head><title>404</title></head><body>x</body></html>\n' \
    > "$CASO/pagina.deb"
cp "$CASO/pagina.deb" "$CASO/pagina-sem-extensao"
contem "an error page saved as .deb is called a web page" \
       "web page" "$(inst "$CASO/pagina.deb")"
naocontem "and the ar jargon does not reach the owner" \
       "ar signature" "$(inst "$CASO/pagina.deb")"
contem "the same page with no extension is caught too" \
       "web page" "$(inst "$CASO/pagina-sem-extensao")"

# Uppercase, and a page that begins with a blank line, are the same page.
printf '\n\n<HTML><HEAD><TITLE>Login</TITLE></HEAD></HTML>\n' > "$CASO/maiuscula.deb"
contem "an uppercase page after blank lines is still a web page" \
       "web page" "$(inst "$CASO/maiuscula.deb")"

# And a real unknown type still says so - but now it says WHICH file, and what
# Tandem can actually open, so the sentence is actionable.
printf 'lixo\000\001\002binario' > "$CASO/estranho"
saida_estranho="$(inst "$CASO/estranho")"
contem "an unknown type still says it did not recognise the type" \
       "did not recognise the type" "$saida_estranho"
contem "and names the file it is talking about" "estranho" "$saida_estranho"
contem "and lists what Tandem does open" ".flatpakref" "$saida_estranho"

# The guard on the whole point: a real package must still be routed. If the
# new checks ever reject a good file, that is a far worse bug than the one
# they were written for.
deb_bom="$(ls -1 "$ROOT"/tandem_*_all.deb 2>/dev/null | head -1)"
if [ -z "$deb_bom" ]; then
    python3 "$ROOT/build.py" >/dev/null 2>&1
    deb_bom="$(ls -1 "$ROOT"/tandem_*_all.deb 2>/dev/null | head -1)"
fi
if true; then
    if [ -n "$deb_bom" ]; then
        naocontem "a real .deb is not mistaken for a web page" \
                  "web page" "$(inst "$deb_bom")"
        naocontem "a real .deb is not mistaken for an unknown type" \
                  "did not recognise the type" "$(inst "$deb_bom")"
    else
        skip "a real .deb still routes" "no package could be built here"
    fi
fi

section "language: the data tables translate too, and fall back"

# The catalogues were not the whole of it. alternativas.tsv and limites.tsv
# carry PROSE in their columns - "what changes" and "why it will never work" -
# and that prose reaches the owner through t_texto_alternativas and the limit
# verdicts. A per-language table sits beside the original, and the original is
# the fallback, exactly as a missing catalogue key falls back to English.

for tab in alternativas limites; do
  for tl in pt_BR es fr zh_CN hi ar; do
    if [ -f "$ROOT/src/lib/$tab.$tl.tsv" ]; then
        pass "$tab has a $tl table"
    else
        fail "$tab has a $tl table" "src/lib/$tab.$tl.tsv" "missing"
    fi
    # Same number of rows, or a row silently disappears from one language.
    # Blank lines are cosmetic; the invariant is the DATA rows. Counting the
    # blanks made this fail on a file that was in fact row-for-row correct.
    n_pt="$(grep -v '^#' "$ROOT/src/lib/$tab.tsv" | grep -c . | tr -d ' ')"
    n_tl="$(grep -v '^#' "$ROOT/src/lib/$tab.$tl.tsv" | grep -c . | tr -d ' ')"
    equal "$tab.$tl.tsv has the same number of rows as the original" "$n_pt" "$n_tl"
    # And the same keys in the same order, or a pattern matches the wrong row -
    # which would be worse than any wording.
    k_pt="$(grep -v '^#' "$ROOT/src/lib/$tab.tsv" | grep . | cut -f1 | cksum)"
    k_tl="$(grep -v '^#' "$ROOT/src/lib/$tab.$tl.tsv" | grep . | cut -f1 | cksum)"
    equal "$tab.$tl.tsv matches the original row for row" "$k_pt" "$k_tl"
    # The class column decides which message frames the row; a translated
    # "nativo" would silently pick the wrong frame.
    c_pt="$(grep -v '^#' "$ROOT/src/lib/$tab.tsv" | grep . | cut -f2 | cksum)"
    c_tl="$(grep -v '^#' "$ROOT/src/lib/$tab.$tl.tsv" | grep . | cut -f2 | cksum)"
    equal "$tab.$tl.tsv keeps the class column untranslated" "$c_pt" "$c_tl"
    # And no row may still be the Portuguese sentence: that is the whole point.
    if [ "$tab" = limites ] && [ "$tl" != pt_BR ]; then
        pt_sobrou="$(grep -v '^#' "$ROOT/src/lib/$tab.$tl.tsv" | grep -c 'núcleo do Linux' | tr -d ' ')"
        equal "$tab.$tl.tsv has no untranslated row left" "0" "$pt_sobrou"
    fi
  done
done

# COLUMN 4, which nothing above was looking at.
#
# The check just above greps for a phrase that lives in column 3, so it only
# ever proved column 3 had moved. Column 4 - the WAY OUT, the entire payload of
# the 4.0 correction, the paragraph that tells a dongle owner what a technician
# can actually do for him - was byte-identical Portuguese in all seven tables,
# the English DEFAULT included: 15 rows, one md5. So the product told a French
# shopkeeper his case had a way out and then handed him the instructions in a
# language he cannot read, and this repository's own notes claimed no row was
# left holding the Portuguese sentence.
#
# Asserting "differs from pt_BR" rather than pinning a wording: the wording is
# a translator's business and must be free to change, while "somebody actually
# translated this column" is the invariant. pt_BR is the source, so it is the
# one table this may not be asked of.
col4() {                                # $1 = table file
    grep -v '^#' "$1" | grep . | cut -f4 | grep . | cksum
}
c4_pt="$(col4 "$ROOT/src/lib/limites.pt_BR.tsv")"
n4_pt="$(grep -v '^#' "$ROOT/src/lib/limites.pt_BR.tsv" | grep . | cut -f4 | grep -c . | tr -d ' ')"
for tl in "" es fr zh_CN hi ar; do
    arq="$ROOT/src/lib/limites${tl:+.$tl}.tsv"
    nome="limites${tl:+.$tl}.tsv${tl:+}"
    [ -z "$tl" ] && nome="limites.tsv (the English default)"
    n4="$(grep -v '^#' "$arq" | grep . | cut -f4 | grep -c . | tr -d ' ')"
    equal "$nome offers a way out on the same rows as the original" "$n4_pt" "$n4"
    if [ "$(col4 "$arq")" = "$c4_pt" ]; then
        fail "$nome translates the way out, not just the verdict" \
             "column 4 different from the Portuguese source" \
             "byte-identical to limites.pt_BR.tsv - the reader is told there is a way out and then handed it in Portuguese"
    else
        pass "$nome translates the way out, not just the verdict"
    fi
done

tabela_para() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
    TANDEM_IDIOMA_FORCADO="$1" TANDEM_ALTERNATIVAS="$ROOT/src/lib/alternativas.tsv" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_alternativas_para photoshop' 2>/dev/null
}
contem "an English machine reads the English table" \
       "edits images" "$(tabela_para en)"
contem "a Portuguese machine reads the Portuguese table" \
       "edita imagem" "$(tabela_para pt_BR)"
contem "a Hindi machine reads the Hindi table" \
       "तस्वीरें संपादित" "$(tabela_para hi)"
# The unsuffixed table IS English, because English is the default: a language
# with no table of its own must land on it. That fallback is what makes a
# half-written table safe to ship.
contem "a language with no table of its own falls back to English" \
       "edits images" "$(tabela_para "fi")"

section "language: a migrated file stays migrated"

# The check used during the first migration pass was WRONG, and it is worth
# spelling out because it looked convincing. It was "does the file still hold
# an accented character", and on that basis tandem-snap was declared finished
# while
#
#     t_pergunta "Instalar \"$NOME\" a partir deste arquivo?
#
# was still a literal - accent-free Portuguese walks straight through an accent
# grep. tools/conta-literais.py counts CALL SITES instead, and a call site is
# clean when every letter a person reads comes out of a t_msg lookup.

if [ -f "$ROOT/tools/conta-literais.py" ]; then
    # This number was 0 for two versions and the 0 was WRONG - the NINTH time
    # this measure has been narrower than reality, and the worst of the nine.
    # ATRIBUICAO in the counter is a whitelist of variable names, and
    # acao_doctor assembles its whole report with
    #
    #     out+="SISTEMA\n"
    #
    # into a variable called "out", which was not on the list. So the entire
    # diagnostic - the second most-read screen in the program, and the thing
    # "tandem socorro" sends to whoever is helping - plus the zenity panel's own
    # "O que você quer fazer?" were scored as zero while this suite asserted
    # that zero. It was found by installing the built .deb and READING THE
    # OUTPUT, which is the only method that has ever caught this measure lying.
    #
    # Then it happened twice MORE, and the second of those hid the primary
    # interface. The number went 75 -> 107 -> 167 -> 145, and only the last step
    # is a reduction rather than a discovery: it is 22 named exceptions, the
    # command names the panel matches on and the hardware labels that must not
    # move with the language.
    #
    # ELEVENTH: acao_painel builds its whole menu out of BARE ARGUMENTS to
    # zenity - eighteen rows of Portuguese plus the window's own question and the
    # file chooser's filter - and those are neither an assignment nor a printf
    # nor a call to t_erro.
    # TWELFTH: the menu lives inside a command substitution which is itself the
    # entire value of a string, esc="$(zenity --list ... "instalar" "Instalar ou
    # abrir um arquivo")". A walker that skips substitutions cannot see it; a
    # regex over shell chops it into debris like " | cut -d'|' -f2)". The rule
    # that finally works is a walk that descends INTO a substitution while
    # refusing to glue its text into the sentence around it.
    #
    # (see the changelog line-length guard further down, added for the same
    # reason: the release found it, so the suite owns it now)
    #
    # 145 -> 121 was the zenity panel; 121 -> 63 is tandem doctor, the second
    # most-read screen and the one "tandem socorro" ships to whoever is helping.
    # Both keep their machine-readable halves literal: the panel's action names,
    # which "case $esc in" matches, and doctor's product-name line. What is left
    # is the autoteste report and the hardware-key advice.
    #
    # So the number is the measured truth and it is a RATCHET: it may fall,
    # never rise. A hard 0 that is wrong is worse than a true 145 that can only
    # shrink, because the 0 says the work is finished and the 145 says where it
    # is not. Lower this line when you migrate something; the test fails if you
    # add prose to the code, and fails if you leave this number stale after
    # removing some.
    # It reads 0 again, and the last time it read 0 the 0 WAS FALSE - that is
    # blind spots nine through twelve, and the whole comment above. What is
    # different this time is not the number, it is the instrument: this counter
    # has since been shown to catch a bare zenity argument inside a command
    # substitution inside a string, an "out+=" append into any variable name, a
    # printf whose prose is in the argument rather than the format, and a
    # heredoc - the four shapes that produced the previous false zeros - and
    # there is a bait test for the worst of them.
    #
    # Read the migration as finished only as far as the instrument can see. The
    # one method that has ever caught this measure lying is installing the
    # package and reading the output, and that is what was done for every screen
    # in this version: doctor, the panel, autoteste, the data screen and the two
    # list screens, in seven languages.
    #
    # AND THE 0 WAS FALSE AGAIN, twice over, and both were found by widening the
    # instrument rather than by reading its number:
    #
    #   THIRTEENTH: the prose-body rule keys off function NAMES, and the eleven
    #   handler executables define no functions at all - they are straight-line
    #   scripts. So in tandem-repair, tandem-deb, tandem-jar and eight others
    #   that rule and the printf rule were dead code, and what they missed was
    #   the entire report of "tandem repair" - the command the README tells an
    #   owner to run when a double click opens the wrong program.
    #   FOURTEENTH: only the FIRST argument of a message call was ever read, so
    #   the BUTTONS of "did this program actually work?" were Portuguese in a
    #   shipped release, at six call sites.
    #   FIFTEENTH: ALVOS globs *.sh and src/bin, so no version of this tool in
    #   fifteen revisions had ever opened a .py file - and the six Python
    #   readers RAISED PORTUGUESE, about thirty sentences, which the handlers
    #   printed straight to the owner. That one is fixed rather than counted:
    #   the readers emit tokens now and the shell turns a token into a sentence.
    #
    # So this reads 0 for the third time, and the two previous zeros were both
    # false. What is different is not the number and not this counter: it is
    # that the fifteenth miss was a whole FILE TYPE this tool cannot see, so a
    # second instrument now covers it - the section below reads the readers
    # themselves and demands a catalogue key for every token they can emit. A
    # measure that can only look at shell will never notice Portuguese in
    # Python, however many shapes it learns.
    TETO_LIT=0
    total_lit="$(cd "$ROOT" && python3 tools/conta-literais.py 2>&1 | awk '/^TOTAL/ { print $2 }')"
    if [ "${total_lit:-999}" -eq "$TETO_LIT" ] 2>/dev/null; then
        pass "the literals still in the code are the $TETO_LIT already known about"
    elif [ "${total_lit:-999}" -lt "$TETO_LIT" ] 2>/dev/null; then
        fail "the literals still in the code are the $TETO_LIT already known about" \
             "$total_lit — you migrated something, so lower TETO_LIT to $total_lit" \
             "the ceiling still says $TETO_LIT"
    else
        fail "the literals still in the code are the $TETO_LIT already known about" \
             "at most $TETO_LIT" \
             "$total_lit — new prose was added to the code instead of to po/en.po"
    fi
    # The ten files that ARE finished stay finished. "tandem" and "common.sh"
    # came off that list, because they never belonged on it.
    saida_lit="$(cd "$ROOT" && python3 tools/conta-literais.py --migrados 2>&1)"
    if [ -z "$saida_lit" ]; then
        pass "no file declared migrated has a Portuguese literal left"
    else
        fail "no file declared migrated has a Portuguese literal left" "" "$saida_lit"
    fi
    # And the counter has to actually catch one, or a green result means
    # nothing. Accent-free Portuguese is the exact case that fooled the old
    # check, so that is what gets fed to it.
    ISCA="$TMPROOT/isca.sh"
    printf 't_erro "Instalar este arquivo?"\n' > "$ISCA"
    achou="$(cd "$ROOT" && python3 - "$ISCA" <<'FIM'
import sys, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/conta-literais.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.literais(pathlib.Path(sys.argv[1]))))
FIM
)"
    equal "the counter catches accent-free Portuguese, which fooled the old check" \
          "1" "$achou"

    # The shape that hid the primary interface for twelve rounds, reduced to its
    # essentials: prose as a BARE ARGUMENT to zenity, inside a command
    # substitution, inside a string. Nothing about it is an assignment, a printf
    # or a call to t_erro, and every earlier version of this counter scored the
    # whole panel as zero. This is the test that makes the ratchet mean
    # something - without it, a green suite only says the counter agrees with
    # itself.
    #
    # It also pins the two halves apart: the row's command name is excepted on
    # purpose (a command copied off a forum has to work on any machine) and the
    # human-readable half beside it is not.
    cat > "$ISCA" <<'FIMP'
acao_painel() {
    esc="$(zenity --list --text="O que você quer fazer?" \
        "instalar"  "Instalar ou abrir um arquivo" \
        2>/dev/null)" || return 0
}
FIMP
    painel="$(cd "$ROOT" && python3 - "$ISCA" <<'FIM'
import sys, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/conta-literais.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
achados = m.literais(pathlib.Path(sys.argv[1]))
print("%d %s" % (len(achados), "|".join(sorted(achados))))
FIM
)"
    equal "the counter sees prose in a zenity argument inside a substitution" \
          "2 Instalar ou abrir um arquivo|O que você quer fazer?" "$painel"
    # Miss fourteen, reduced: the buttons of a message call. The first argument
    # is a clean t_msg lookup, so every earlier version read the whole line as
    # finished and never looked at the two words the owner actually clicks.
    printf 't_pergunta "$(t_msg funcionou)" "Sim, funcionou" "Não, algo saiu errado"\n' > "$ISCA"
    botoes="$(cd "$ROOT" && python3 - "$ISCA" <<'FIM'
import sys, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/conta-literais.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
achados = m.literais(pathlib.Path(sys.argv[1]))
print("%d %s" % (len(achados), "|".join(sorted(achados))))
FIM
)"
    equal "the counter sees the BUTTONS of a message call, not just its text" \
          "2 Não, algo saiu errado|Sim, funcionou" "$botoes"

    # Miss thirteen, reduced, and the assertion is in two halves because the
    # rule is about the FILE: the same bytes are prose in a handler executable
    # (which has no functions to scope to) and out of scope in a library file
    # (where the prose lives in named builders and everything else is plumbing).
    ISCA_H="$TMPROOT/tandem-isca"
    cat > "$ISCA_H" <<'FIMH'
RELATORIO="Associações reaplicadas."
zenity --info --text="$RELATORIO

Se ainda não funcionar com dois cliques, saia e entre novamente."
FIMH
    cp "$ISCA_H" "$TMPROOT/isca-lib.sh"
    conta_isca() {
        cd "$ROOT" && python3 - "$1" <<'FIM'
import sys, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/conta-literais.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.literais(pathlib.Path(sys.argv[1]))))
FIM
    }
    equal "in a handler executable, prose outside any function is counted" \
          "2" "$(conta_isca "$ISCA_H")"
    equal "and the same bytes in a library file are not, which is the rule" \
          "0" "$(conta_isca "$TMPROOT/isca-lib.sh")"

    # The destination rules, which are what keeps the widened scope usable: an
    # on-disk value and an executed script are not prose, and they are excluded
    # because of where the argument GOES, not because of what it looks like.
    cat > "$ISCA_H" <<'FIMD'
t_memoria_grava "$PROG" RESULTADO "nao abriu"
t_como_root "apt-get install -y -- '$PACOTE'"
t_erro "Isto o dono lê."
FIMD
    equal "a state-file value and a root script are not messages; the sentence is" \
          "1" "$(conta_isca "$ISCA_H")"

    # A composed message - several t_msg lookups plus data - must NOT be
    # reported. That is what a finished call site looks like.
    printf 't_erro "$(t_msg um)\n\n$(basename -- "$f")\n\n$(t_msg dois)"\n' > "$ISCA"
    limpo="$(cd "$ROOT" && python3 - "$ISCA" <<'FIM'
import sys, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/conta-literais.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.literais(pathlib.Path(sys.argv[1]))))
FIM
)"
    equal "a message assembled from several t_msg lookups is not a literal" \
          "0" "$limpo"
else
    skip "a migrated file stays migrated" "tools/conta-literais.py is missing"
fi

# ============================ THE SECOND INSTRUMENT, WHICH READS THE OUTPUT
#
# Everything above reads the SOURCE and asks "what shape of shell hides a
# sentence?". Sixteen misses say that question has a floor, and the sixteenth
# proves it cannot be raised by widening: t_verbo_amigavel in winedeps.sh
# returned nine Portuguese sentences - "Editor de texto rico", "Depurador do
# Windows", "Desenho de texto (Uniscribe)" - on the screen where the owner
# agrees to a half-hour download, in all seven languages, while the counter
# printed TOTAL 0. It could not have seen them: that function's name matches no
# prose-body pattern and it lives in a library rather than a handler, so every
# rule the counter has was inapplicable. Along with it went "Detalhes tecnicos:"
# in every error window, the Sim/Nao buttons, the seven lines of "tandem
# preparar", the two driver paragraphs and three file headers.
#
# tools/prosa-fora-do-catalogo.py asks a different question of a different
# thing: it RUNS the program and reads what comes out. Two angles, because the
# first one has a floor of its own:
#   - render in Chinese, and flag runs of Latin words that are not on an
#     explicit verbatim list;
#   - render in all seven and flag any line that comes out byte-identical,
#     because that is what a literal necessarily does and a catalogue lookup
#     almost never does. This is the angle that catches accent-free Portuguese,
#     which is the hole the very FIRST version of the static check had.
#
# The suite runs the library probes; ci.yml runs the whole thing, handlers and
# commands included.
if [ -f "$ROOT/tools/prosa-fora-do-catalogo.py" ]; then
    saida_prosa="$(cd "$ROOT" && python3 tools/prosa-fora-do-catalogo.py --rapido 2>&1)"
    total_prosa="$(printf '%s\n' "$saida_prosa" | awk '/^TOTAL/ { print $2 }')"
    if [ "${total_prosa:-999}" = "0" ]; then
        pass "nothing the libraries print is prose from outside the catalogue"
    else
        fail "nothing the libraries print is prose from outside the catalogue" \
             "TOTAL 0" "$saida_prosa"
    fi

    # And it has to actually catch one, or the zero above means exactly as much
    # as the counter's did. Both angles are exercised, with the two strings that
    # defeated the FIRST version of this tool written here:
    #   - "Editor de texto rico" got through because the first threshold wanted
    #     three words of three letters each, and "de" is two. Every Romance
    #     language is built out of two-letter words.
    #   - "Depurador do Windows" gets through the Chinese angle to this day,
    #     because once the product name is stripped two words is not enough to
    #     accuse anybody. It is the invariance angle that catches it.
    prova="$(cd "$ROOT" && python3 - <<'FIM'
import importlib.util
spec = importlib.util.spec_from_file_location("p", "tools/prosa-fora-do-catalogo.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
casos = [
    ("Editor de texto rico", 1),
    ("este programa tentou carregar um driver de sistema", 1),
    ("Android (Waydroid) - baixa cerca de 1 GB", 1),
    # Must NOT fire: a product name, a verb falling through the default case,
    # a path, and a bare list of extensions off the help screen.
    ("Visual C++ 2015-2022", 0),
    ("dxdiagn_feb2010", 0),
    ("/home/dono/.local/share/tandem/memoria", 0),
    (".exe .msi  |  .apk .xapk .apks .apkm  |  .AppImage .jar", 0),
]
print(" ".join("%d" % (1 if m.suspeita(t) else 0) for t, _ in casos))
print(" ".join("%d" % e for _, e in casos))
FIM
)"
    equal "the output instrument catches the sixteenth miss, and invents nothing" \
          "$(printf '%s\n' "$prova" | tail -1)" "$(printf '%s\n' "$prova" | head -1)"
else
    skip "the output instrument runs" "tools/prosa-fora-do-catalogo.py is missing"
fi

# ---- the memory value is format on disk and a sentence on screen
#
# Both halves matter and they pull against each other. Translating the value
# would break every recipe already written on somebody's machine; NOT
# translating it left forty-four Portuguese sentences on the one screen a shop
# owner opens to find out what went wrong, and in the report tandem socorro
# tells him to send to whoever is helping.
MEMV="$TMPROOT/memvalor"; mkdir -p "$MEMV"
memvalor() {                       # $1 = language, $2 = value
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO="$1" TANDEM_MEMORIA="$MEMV" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_resultado_amigavel "$1"' _ "$2"
}
equal "a memory value becomes a sentence in English" \
      "The folder it is in does not allow running programs." \
      "$(memvalor en 'pasta sem permissao')"
equal "and the same value becomes a sentence in Arabic" \
      "المجلد الذي يوجد فيه لا يسمح بتشغيل البرامج." \
      "$(memvalor ar 'pasta sem permissao')"
# "bitola" is Brazilian slang for gauge. It was on this screen, untranslated,
# in all seven languages - no dictionary recovers it.
contem "and Brazilian slang does not survive into another language" \
       "processor width" "$(memvalor en 'bitola errada')"
# The whole point of resolving at display time: what is written stays written.
MEMPROG="$TMPROOT/memprog.bin"; printf 'x' > "$MEMPROG"
TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=fr TANDEM_MEMORIA="$MEMV" \
    bash -c '. "'"$ROOT"'/src/lib/common.sh"
             t_memoria_grava "'"$MEMPROG"'" RESULTADO "pasta sem permissao"' 2>/dev/null
equal "but what lands on disk is still the value every recipe already carries" \
      "RESULTADO=pasta sem permissao" \
      "$(grep -h '^RESULTADO=' "$MEMV"/*.txt 2>/dev/null | tail -1)"
# An old memory file written by a version that knew a value this one does not
# is the ordinary case, not an error - and it must never show a key name.
equal "a value with no message prints itself, never a key name" \
      "algo que ninguem escreveu" \
      "$(memvalor en 'algo que ninguem escreveu')"

# ---- the terminal confirmation accepts the letter it asked for
#
# This was "case \$r in s|S|sim|SIM)" in five handlers while the prompt beside
# it came from the catalogue and reads [y/N] in English and [o/N] in French. An
# English owner did what the screen told him, typed y, and was told the install
# was cancelled. That is a correctness defect, and it sat on the .deb and .sh
# paths - the two where the alternative to installing is being told that
# nothing happened.
confirmou() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO="$1" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_confirmou "$1" && echo sim || echo nao' _ "$2"
}
equal "an English reader who types the y the prompt asked for is understood" \
      "sim" "$(confirmou en y)"
equal "a French reader who types the o the prompt asked for is understood" \
      "sim" "$(confirmou fr o)"
equal "and s still works everywhere, because forums are in Portuguese" \
      "sim" "$(confirmou fr s)"
equal "no still means no" "nao" "$(confirmou en n)"
equal "and an empty answer is not a yes" "nao" "$(confirmou en '')"
# The prompt and the accepted letter have to agree, or the fix is only half of
# one. Every language's [x/N] must offer a letter t_confirmou accepts.
descasado=""
for l in en pt_BR es fr zh_CN hi ar; do
    letra="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO="$l" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_msg resposta_sim')"
    [ "$(confirmou "$l" "$letra")" = "sim" ] || descasado="$descasado $l"
done
equal "every language's prompt letter is one the code accepts" "" "$descasado"

# tandem-apk was the only one of the nine that wrote NOTHING to memory - not
# even a RESULTADO. So "tandem memoria" knew nothing about an .apk, "tandem
# socorro" carried nothing about Android, and a second attempt at the same file
# learned nothing from the first. Structural rather than a run, because reaching
# those branches needs a live Waydroid; it catches the case that actually
# happens, which is somebody adding a tenth failure and forgetting.
#
# The exemptions are the point of the check rather than a hole in it. A verdict
# about the FILE is a lesson - it will still be true tomorrow. A verdict about
# THIS MACHINE is not, and recording one would be a real defect: install adb,
# and a memory saying the file failed would still be there, wrong. Writing the
# first version of this without that distinction reported seven "missing"
# records, four of which were genuinely missing and three of which must never
# exist.
SO_DA_MAQUINA="apk_falta_adb apk_sem_endereco apk_nao_conectou"
sem_memoria=""
while IFS= read -r n; do
    linha="$(sed -n "${n}p" "$ROOT/src/bin/tandem-apk")"
    pula=0
    for chave in $SO_DA_MAQUINA; do
        case "$linha" in *"$chave"*) pula=1 ;; esac
    done
    [ "$pula" = 1 ] && continue
    anterior="$(sed -n "$((n-1))p" "$ROOT/src/bin/tandem-apk")"
    case "$anterior" in
        *t_memoria_grava*) ;;
        *) sem_memoria="$sem_memoria $n" ;;
    esac
done <<FIMAPK
$(grep -n 't_erro "$(t_msg apk_' "$ROOT/src/bin/tandem-apk" | cut -d: -f1)
FIMAPK
if [ -z "$sem_memoria" ]; then
    pass "every verdict about the FILE in tandem-apk records it first"
else
    fail "every verdict about the FILE in tandem-apk records it first" \
         "a t_memoria_grava above each" "lines without one:$sem_memoria"
fi
# And the machine-state ones must NOT record, or a fixed machine would keep
# reading a failure about a file that was never the problem.
grava_maquina=""
for chave in $SO_DA_MAQUINA; do
    n="$(grep -n "$chave" "$ROOT/src/bin/tandem-apk" | head -1 | cut -d: -f1)"
    [ -n "$n" ] || continue
    case "$(sed -n "$((n-1))p" "$ROOT/src/bin/tandem-apk")" in
        *t_memoria_grava*) grava_maquina="$grava_maquina $chave" ;;
    esac
done
if [ -z "$grava_maquina" ]; then
    pass "and a failure of this machine is not remembered as a failure of the file"
else
    fail "and a failure of this machine is not remembered as a failure of the file" \
         "no record" "recorded:$grava_maquina"
fi

section "what gets published to everybody"

# tools/monta-lista.py turns the records the intake accepted into the file every
# Tandem downloads. It is the narrowest point in the whole project: one wrong
# row here reaches every machine at once, where a wrong row in one shop's memory
# reaches one machine that then asks its owner. So the three things it must get
# right are asserted against a synthetic intake rather than against whatever
# happens to be in the store today.
if [ -f "$ROOT/tools/monta-lista.py" ]; then
    saida_lista="$(cd "$ROOT" && python3 - <<'FIM'
import importlib.util
spec = importlib.util.spec_from_file_location("m", "tools/monta-lista.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
A, B, C = "a" * 32, "b" * 32, "c" * 32
entrada = "\n".join([
    "# TANDEM-ENTRADA 1",
    f"{A}\t64\tvcrun2022\t-\tconfirmado\t1\t2026-07\t-",
    f"{A}\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t-",
    f"{A}\t64\tvcrun2022\t-\tconfirmado\t1\t2026-06\t-",
    f"{A}\t64\tvcrun2022\t-\treprovado\t1\t2026-08\t-",
    f"{B}\t32\tdotnet48\t-\tconfirmado\t1\t2026-08\t-",
    f"{C}\t64\tsandbox\t-\tconfirmado\t1\t2026-08\t-",
    "3f376993b2da855c5e6e291da008d5d6\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t-",
    "isto nao e um registro",
])
linhas, recusadas = m.monta(entrada)
print("|".join(linhas))
print("|".join(sorted(r[0] for r in recusadas)))
FIM
)"
    linhas_lista="$(printf '%s\n' "$saida_lista" | sed -n 1p)"
    fora_lista="$(printf '%s\n' "$saida_lista" | sed -n 2p)"
    # Three reports of one lesson are one row counting three, carrying the most
    # recent month - not the first one seen.
    case "$linhas_lista" in
        *"vcrun2022	-	confirmado	3	2026-08"*)
            pass "reports of the same lesson are added up, with the newest month" ;;
        *) fail "reports of the same lesson are added up, with the newest month" \
                "one row counting 3, seen 2026-08" "$linhas_lista" ;;
    esac
    # The rejection survives as its own row. Folding it away here would delete
    # the evidence the client needs: t_lista_linha drops a verb set more
    # machines rejected than confirmed, and it cannot do that if the rejections
    # never reach the file.
    case "$linhas_lista" in
        *"vcrun2022	-	reprovado	1"*)
            pass "a rejection is published too, because it is the evidence" ;;
        *) fail "a rejection is published too, because it is the evidence" \
                "a reprovado row" "$linhas_lista" ;;
    esac
    # And the things that must never reach the file: the record posted by hand
    # while proving the intake worked, anything that is not a record, and a row
    # naming a winetricks SETTINGS verb - the AUR "Atomic Arch" threat in
    # miniature, a valid-looking row that would change a prefix on every Tandem
    # that acted on it.
    case "$linhas_lista" in
        *3f376993b2da855c5e6e291da008d5d6*)
            fail "the intake's own test record is never published" \
                 "excluded by name" "it is in the file" ;;
        *) pass "the intake's own test record is never published" ;;
    esac
    case "$linhas_lista" in
        *sandbox*)
            fail "a row naming a settings verb never reaches the published file" \
                 "refused" "sandbox is in the file" ;;
        *) pass "a row naming a settings verb never reaches the published file" ;;
    esac
    equal "and everything left out is reported, not dropped in silence" \
          "excluded: test record from the intake bring-up|malformed|unsafe verb: verb 'sandbox' changes a setting, not a dependency" \
          "$fora_lista"
else
    skip "what gets published" "tools/monta-lista.py is missing"
fi

section "the readers speak in tokens, and every token has a sentence"

# This is the guard the fifteenth blind spot deserved. The six Python readers
# used to raise PORTUGUESE - "nao comeca com ELF", "o pacote nao traz um arquivo
# control" - and the handlers printed the field straight to the owner, so about
# thirty user-facing sentences lived in files no translation tool here had ever
# opened: conta-literais.py globs *.sh and src/bin only, and no version of it in
# fifteen revisions looked at a .py.
#
# Counting them is not the fix - a count of a thing nothing checks goes stale.
# What closes it is this: every token a reader can emit must have a catalogue
# key, checked by reading the readers themselves. A reader that grows a new
# failure tomorrow and does not bring a message fails here, in the commit that
# adds it, instead of on a shop counter.
# TWO patterns, because a reader emits a token two ways and the first version of
# this check only knew one of them. `raise DebRuim("nao_e_deb")` goes through an
# exception; `print("ERRO=sem_arquivo")` is written straight out. Matching only
# the first found 21 of 25 and reported "missing: none" - a completeness check
# that was itself incomplete, on its first run, in exactly the way the literal
# counter has been fifteen times. Written down because catching it needed
# printing the list and counting it by hand, not reading the verdict.
FICHAS="$(
  { grep -rhoE 'raise [A-Za-z]+\("[a-z_0-9]+' "$ROOT"/src/lib/*.py | sed -E 's/.*"//'
    grep -rhoE '"ERRO=[a-z_0-9]+' "$ROOT"/src/lib/*.py | sed -E 's/.*=//'
  } | sort -u | grep -v '^$')"
if [ -z "$FICHAS" ]; then
    fail "the readers' tokens were found at all" "some tokens" "none"
else
    pass "the readers' tokens were found at all ($(printf '%s\n' "$FICHAS" | wc -l))"
    faltando=""
    for f in $FICHAS; do
        grep -q "^@leitor_$f\$" "$ROOT/src/lib/idiomas/en.txt" 2>/dev/null ||
            faltando="$faltando $f"
    done
    if [ -z "$faltando" ]; then
        pass "every token a reader can emit has a message in the catalogue"
    else
        fail "every token a reader can emit has a message in the catalogue" \
             "a leitor_* key for each" "missing:$faltando"
    fi
fi
# And no reader may go back to raising prose. A token is a name; a sentence has
# spaces in it, and that is the whole difference the protocol rests on.
prosa_py="$(grep -rhoE 'raise [A-Za-z]+\("[^"]*"' "$ROOT"/src/lib/*.py |
            grep -E '"[^"]* [^"]*"' || true)"
if [ -z "$prosa_py" ]; then
    pass "no reader raises a sentence instead of a token"
else
    fail "no reader raises a sentence instead of a token" "tokens only" "$prosa_py"
fi

# The shell half: a known token becomes a sentence, an unknown one becomes the
# generic sentence rather than the key name. t_msg prints the key when a key is
# missing, which is right for a log and would be jargon on a shop owner's
# screen.
equal "a known token becomes a sentence" "0" \
      "$(t_erro_do_leitor sem_marca_ai | grep -qi 'appimage'; echo $?)"
equal "a token carrying data puts the data in the sentence" "0" \
      "$(t_erro_do_leitor 'rpm_entradas|99999' | grep -q '99999'; echo $?)"
case "$(t_erro_do_leitor coisa_que_ninguem_escreveu)" in
    *leitor_*) fail "an unknown token does not put a key name on the screen" \
                    "a sentence" "the key name" ;;
    ?*) pass "an unknown token becomes the generic sentence, not a key name" ;;
    *) fail "an unknown token becomes the generic sentence, not a key name" \
            "a sentence" "zero bytes" ;;
esac
# A raw Python exception is English jargon whatever the owner's language is, so
# it goes to the log and the screen gets words.
case "$(t_erro_do_leitor 'cru|[Errno 13] Permission denied')" in
    *Errno*) fail "a raw Python exception does not reach the screen" \
                  "words" "the exception" ;;
    ?*) pass "a raw Python exception does not reach the screen" ;;
    *) fail "a raw Python exception does not reach the screen" "words" "zero bytes" ;;
esac
# A token cannot choose an arbitrary message key: the field comes out of a
# program, and a program's output is input. Compared against the generic
# sentence rather than pattern-matched for debris - the first version of this
# looked for "*rm*" in the output and failed on the word "format", which is a
# bad test rather than a bad fix, and it took reading the failure to see that.
equal "a token with a shell character gets the generic sentence" \
      "$(t_erro_do_leitor coisa_que_ninguem_escreveu)" \
      "$(t_erro_do_leitor 'sem_marca_ai; rm -rf /')"

section "language: .po is the source, and a stale translation cannot hide"

# The hand-rolled catalogue format could not do one thing, and it was the thing
# that mattered: when an English message CHANGES, the six translations keep the
# old text and nothing says so. Key-existence tests pass, the program runs, and
# somebody reads a sentence that describes behaviour Tandem no longer has.
#
# gettext solves exactly that, so po/ is the source of truth now and
# src/lib/idiomas/*.txt is generated from it. What gettext is NOT used for is
# the runtime: rule 5 says the packager depends on no outside tool, so the
# compiler is sixty lines of Python and there is no msgfmt in the build.

if [ -d "$ROOT/po" ]; then
    for pl in en pt_BR es fr zh_CN hi ar; do
        if [ -f "$ROOT/po/$pl.po" ]; then pass "po/$pl.po exists"
        else fail "po/$pl.po exists" "the file" "missing"; fi
    done
    if [ -f "$ROOT/po/tandem.pot" ]; then pass "the .pot template exists"
    else fail "the .pot template exists" "po/tandem.pot" "missing"; fi

    # The generated files must match their source, or somebody edited the
    # wrong one and the next regeneration silently reverts their work.
    saida_po="$(cd "$ROOT" && python3 tools/po-para-catalogo.py --check 2>&1)"
    if [ "$saida_po" = "po/ and src/lib/idiomas/ agree" ]; then
        pass "the generated catalogues match po/"
    else
        fail "the generated catalogues match po/" "agreement" "$saida_po"
    fi

    # gettext's own tools have to accept the files, because the whole reason to
    # be in this format is that Poedit, Weblate and msgmerge work on it. If
    # msgfmt is absent this is skipped, not failed - the build never needs it.
    if command -v msgfmt >/dev/null 2>&1; then
        for pl in en pt_BR es fr zh_CN hi ar; do
            if msgfmt --check-format --check-domain -o /dev/null \
                      "$ROOT/po/$pl.po" 2>/dev/null; then
                pass "msgfmt accepts po/$pl.po"
            else
                fail "msgfmt accepts po/$pl.po" "clean" \
                     "$(msgfmt --check-format -o /dev/null "$ROOT/po/$pl.po" 2>&1 | head -3)"
            fi
        done
    else
        skip "gettext accepts the .po files" "msgfmt is not installed here"
    fi

    # THE POINT OF ALL THIS, exercised: mark an entry fuzzy and the compiler
    # must drop it, so the reader gets English rather than a sentence that
    # describes what the program used to do.
    PO_FALSO="$TMPROOT/po-fuzzy"
    mkdir -p "$PO_FALSO"
    cp "$ROOT"/po/*.po "$PO_FALSO"/
    python3 - "$PO_FALSO/fr.po" <<'FIM'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
alvo = 'msgctxt "sem_arquivo"'
assert s.count(alvo) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(alvo, "#, fuzzy\n" + alvo, 1))
FIM
    resultado="$(cd "$ROOT" && python3 - "$PO_FALSO/fr.po" <<'FIM'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("c", "tools/po-para-catalogo.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
itens, cab = m.le_po(sys.argv[1])
saida = m.escreve_catalogo("fr", itens, cab)
print("%s %s %d" % (
    ",".join(k for k, t, f in itens if f),
    "omitida" if "@sem_arquivo\n" not in saida else "MANTIDA",
    saida.count("\n@")))
FIM
)"
    # One less entry than the catalogue has keys: the fuzzy one is dropped. The
    # number is computed rather than written down, because a hard number here
    # fails on the next message somebody adds and teaches them to edit the
    # expectation instead of reading the test.
    N_CHAVES="$(grep -c '^msgctxt ' "$ROOT/po/en.po")"
    equal "a fuzzy entry is seen, dropped, and the rest kept" \
          "sem_arquivo omitida $(( N_CHAVES - 1 ))" "$resultado"

    # That parser was wrong the first time it was written, in a way that made it
    # report NO fuzzy entries at all - the flag is a comment BEFORE the entry,
    # and closing the previous entry wiped it. It looked correct on every file
    # in the tree, because none of them had a fuzzy entry.
    naocontem "an untranslated entry is not written as an empty message" \
              "@sem_arquivo
@" "$(cat "$ROOT/src/lib/idiomas/fr.txt")"

    # Plural rules: the old format had none, and said "1 linha(s)". Arabic has
    # six forms and Chinese has one; a .po states that in its header.
    for pl in en pt_BR es fr zh_CN hi ar; do
        contem "po/$pl.po declares its plural rule" \
               "Plural-Forms:" "$(head -30 "$ROOT/po/$pl.po")"
    done
    contem "and Arabic declares six forms, which no hand-rolled format did" \
           "nplurals=6" "$(head -30 "$ROOT/po/ar.po")"
    contem "and Chinese declares one" \
           "nplurals=1" "$(head -30 "$ROOT/po/zh_CN.po")"

    # The review flag is a header field now, not a comment convention, so
    # Weblate and msgfmt both carry it.
    contem "en is marked reviewed by a speaker" \
           "X-Reviewed-By-Speaker: yes" "$(head -30 "$ROOT/po/en.po")"
    contem "and ar is marked as not reviewed" \
           "X-Reviewed-By-Speaker: no" "$(head -30 "$ROOT/po/ar.po")"
else
    skip "po/ is the source of truth" "po/ does not exist"
fi

section "sending: on by default, and the owner is told twice"

# This reverses the previous design, and the reversal has a reason with a
# measurement behind it: born off, the list was EMPTY. A default nobody changes
# is a decision made by the default, so the choice was between a list that does
# not exist and a transmission the owner did not initiate.
#
# What makes it defensible is not the default, it is the two things around it -
# the line cannot carry anything personal, and the owner is TOLD. These tests
# hold both of those, because the default without them would be indefensible.

CFG_ENV="$TMPROOT/envio"
env_le() {
    env HOME="$CFG_ENV" XDG_CONFIG_HOME="$CFG_ENV/.config" \
        TANDEM_LIB="$ROOT/src/lib" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        '"$1"'' 2>/dev/null
}
rm -rf "$CFG_ENV"; mkdir -p "$CFG_ENV"

equal "with nothing decided, sending is ON" "0" \
      "$(env_le 't_envio_ligado; echo $?')"
equal "and nothing has been decided yet, which is a different thing" "1" \
      "$(env_le 't_envio_decidido; echo $?')"

# Off has to STICK, or the default silently overrides the owner - which would be
# the worst version of this feature.
env_le 't_envio_define nao' >/dev/null
equal "once the owner says no, sending is off" "1" \
      "$(env_le 't_envio_ligado; echo $?')"
equal "and that counts as decided" "0" \
      "$(env_le 't_envio_decidido; echo $?')"
# And it survives, because a decision that resets on upgrade is not a decision.
equal "the refusal is written to the config, not held in memory" "nao" \
      "$(env_le 't_config_le ENVIAR')"
env_le 't_envio_define sim' >/dev/null
equal "and yes works the same way" "0" "$(env_le 't_envio_ligado; echo $?')"

# THE NOTICE. dpkg prints it at install; postinst reads it out of the installed
# catalogue in the machine's language, and never sources that file - it runs as
# root, and a file that will one day come from a translator must not execute
# there.
contem "postinst prints the sending notice" \
       "envio_aviso_ligado" "$(cat "$ROOT/debian/postinst")"
contem "and reads the catalogue with awk rather than sourcing it" \
       "awk" "$(sed -n '/^diz_msg()/,/^}/p' "$ROOT/debian/postinst")"
naocontem "postinst never sources a catalogue" \
          ". /usr/lib/tandem/idiomas" "$(cat "$ROOT/debian/postinst")"

# The notice has to say the one thing that makes it a notice and not an
# announcement: how to stop it. In every language.
for pl in en pt_BR es fr zh_CN hi ar; do
    contem "the $pl notice names the command that turns it off" \
           "tandem enviar nao" \
           "$(TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" TANDEM_LIB="$ROOT/src/lib" \
              TANDEM_IDIOMA_FORCADO="$pl" bash -c \
              '. "'"$ROOT"'/src/lib/common.sh"; t_msg envio_aviso_ligado')"
done

# And the sieve, which is the other half. A default-on transmission is only
# defensible if the payload CANNOT carry anything personal, so the sieve is
# tested here rather than taken on faith.
#
# t_lista_vaza answers "does this leak?", so 0 means it found something and the
# record is refused. The first version of this test had that backwards AND used
# a user name that is not this machine's, so two of its five cases were
# meaningless and it still went green on the three that were not.
vaza_ou_nao() {
    TANDEM_LIB="$ROOT/src/lib" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_lista_vaza "$1"; echo $?' _ "$1" 2>/dev/null
}
# The identity here is a REAL 32-character hex fingerprint, and that detail is
# the whole point. The fixture used to be "abc123", and a six-character stand-in
# is what hid the defect for two versions: the sieve matched the user name as a
# substring of the WHOLE record, so a name that happens to be hex matched the
# fingerprint. Measured on this machine before the fix: an owner called "a", "e"
# or "f" had 5 of 5 clean records refused, and "ed" 3 of 5. Those are ordinary
# Unix names, and a refused line was DELETED rather than parked.
IDENT="9f2a1b3c4d5e6f70819a2b3c4d5e6f70"
LIMPO="$IDENT	64	vcrun2022	-	confirmado	1	2026-08	-"
equal "a clean record passes the sieve" "1" "$(vaza_ou_nao "$LIMPO")"

for vaza in "/home/zero/programa.exe" "$(id -un)" \
            "$(hostname 2>/dev/null || echo maquina)" \
            "192.168.0.10" "/media/pendrive/x" "$HOME"; do
    [ -n "$vaza" ] || continue
    equal "a record carrying '$vaza' is refused" "0" \
          "$(vaza_ou_nao "$IDENT	64	vcrun2022	$vaza	sim	1	2026-08	-")"
done

# One case per bullet of docs/LIST-FORMAT.md, because the promise is made there
# and three of these were let straight through: a bare file name, a Windows path,
# an e-mail address and a MAC.
for vaza in "PDVSuperMax-4.2-setup.exe" "setup.EXE aqui" \
            'C:\Users\Joao\pdv.exe' "rockx0@gmail.com" \
            "a4:83:e7:11:22:33" "https://loja.example.com"; do
    equal "a note carrying '$vaza' is refused" "0" \
          "$(vaza_ou_nao "$IDENT	64	vcrun2022	-	confirmado	1	2026-08	$vaza")"
done

# A short user name must not disqualify the machine. The fingerprint is 32 hex
# characters, so any one- or two-letter hex name is a substring of almost every
# record ever built here.
FZ_ID="$TMPROOT/finge-id"; mkdir -p "$FZ_ID"
for nome in a e f ed; do
    printf '#!/bin/sh\necho %s\n' "$nome" > "$FZ_ID/id"
    chmod +x "$FZ_ID/id"
    equal "an owner called '$nome' can still send a clean record" "1" \
          "$(PATH="$FZ_ID:$PATH" vaza_ou_nao "$LIMPO")"
done
rm -f "$FZ_ID/id"

# And the half that made the bug destructive rather than annoying: a refused
# line has to be HELD, not deleted. t_envio_envia writes the lines it keeps to a
# file that then REPLACES the queue, so "continue" without writing was an erase.
# The closing "fi" is anchored, and it has to be: written as /fi/ the range
# ended on the first line containing those two letters anywhere, and the word
# "file" in the comment just below closed it three lines early. Substring where
# a token was meant - the same mistake the sieve itself was making.
BLOCO_PENEIRA="$(sed -n '/^t_envio_envia()/,/^}/p' "$ROOT/src/lib/common.sh" |
                 sed -n '/if t_lista_vaza/,/^ *fi$/p')"
contem "a line the sieve refuses is written back to the queue, not dropped" \
       '$resto' "$BLOCO_PENEIRA"

# A recipe comes from another person - its own header says so - and four of its
# fields were copied verbatim while only the verbs were checked. ARQUITETURA goes
# into field 2 of a community-list record, and a TAB survives t_memoria_grava, so
# a hostile value spliced the remaining fields including the NOTE: a way to write
# a shop's name onto a public list, and a tagging primitive besides.
REC_DIR="$TMPROOT/receita-campos"; mkdir -p "$REC_DIR"
head -c 2100000 /dev/urandom > "$REC_DIR/prog.exe" 2>/dev/null
campos_receita() {
    TANDEM_LIB="$ROOT/src/lib" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        export TANDEM_ESTADO="$2/estado"; mkdir -p "$TANDEM_ESTADO"
        id="$(t_memoria_id "$2/prog.exe")"
        printf "TANDEM_RECEITA=1\nIDENTIDADE=%s\nRESOLVERAM=vcrun2022\n%s\n" \
            "$id" "$1" > "$2/r.receita"
        t_receita_importa "$2/r.receita" "$2/prog.exe" >/dev/null 2>&1
        echo $?' _ "$1" "$REC_DIR" 2>/dev/null
}
equal "a recipe splicing extra record fields through ARQUITETURA is refused" \
      "5" "$(campos_receita "ARQUITETURA=64$(printf '\t')vcrun2022$(printf '\t')Padaria do Joao")"
equal "an architecture that is not one of the four allowed is refused" \
      "5" "$(campos_receita "ARQUITETURA=x86_64")"
equal "a tab in RESULTADO is refused too" \
      "5" "$(campos_receita "RESULTADO=abriu$(printf '\t')mais coisa")"
equal "and an ordinary recipe still imports" \
      "0" "$(campos_receita "ARQUITETURA=64")"

# The counter skips t_diz lines, because the log is a different audience with a
# documented exception - and that skip is a whole-line one, so a line carrying
# BOTH a log call and a user-facing call would lose the user-facing half. No such
# line exists today; this is what notices if one appears.
ISCA_LOG="$TMPROOT/isca-log.sh"
cat > "$ISCA_LOG" <<'FIMLOG'
acao_x() {
    t_diz "isto vai para o registro tecnico"
    t_erro "isto a pessoa le na tela"
}
FIMLOG
conta_isca="$(cd "$ROOT" && python3 - "$ISCA_LOG" <<'FIM'
import sys, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/conta-literais.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.literais(pathlib.Path(sys.argv[1]))))
FIM
)"
equal "a log line is exempt and a message on the next line still counts" \
      "1" "$conta_isca"
# And the two on ONE line, which the whole-line skip would swallow.
cat > "$ISCA_LOG" <<'FIMLOG'
acao_x() {
    t_erro "isto a pessoa le na tela" && t_diz "isto vai para o registro"
}
FIMLOG
conta_junto="$(cd "$ROOT" && python3 - "$ISCA_LOG" <<'FIM'
import sys, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/conta-literais.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(len(m.literais(pathlib.Path(sys.argv[1]))))
FIM
)"
equal "a message sharing a line with a log call is still counted" \
      "1" "$conta_junto"
naocontem "and no such line exists in the tree, so the skip costs nothing today" \
          "t_diz" "$(grep -hE '(t_erro|t_aviso|t_ok|t_pergunta) .*t_diz' \
                         "$ROOT"/src/bin/* "$ROOT"/src/lib/*.sh || true)"

# The doctor report is the second most-read screen, and it is what "tandem
# socorro" sends to whoever is helping - so a Portuguese diagnostic reaching an
# English-speaking user costs two people an afternoon. Assert the rows come from
# the catalogue AND that they resolve: a key present in the code and missing from
# a catalogue falls back silently and looks right on the reference machine.
DOCTOR_CORPO="$(sed -n '/^acao_doctor()/,/^}/p' "$ROOT/src/bin/tandem")"
for chave in doc_sistema doc_kernel doc_prog_windows doc_bits64_nao \
             doc_apps_android doc_usb_nao doc_pacotes_linux doc_aparelhos \
             doc_portas doc_dialout_nao doc_vm_cabe doc_perfis_nenhum; do
    contem "doctor reads '$chave' from the catalogue" \
           "t_msg $chave" "$DOCTOR_CORPO"
done
for lang in en pt_BR es fr zh_CN hi ar; do
    linha="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO="$lang" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"; t_msg doc_bits64_nao' 2>/dev/null)"
    case "$linha" in
        doc_bits64_nao|"") fail "doctor's 32-bit-Wine line exists in $lang" \
                                "a translated sentence" "${linha:-nothing}" ;;
        *) pass "doctor's 32-bit-Wine line exists in $lang" ;;
    esac
done
# The report's own first line is the product name and its version, and it stays
# a literal on purpose - a translated product name is a name that finds nothing.
contem "the report still names the product without translating it" \
       'Tandem $VERSAO' "$DOCTOR_CORPO"

# The panel is the only screen a shop owner who never opens a terminal sees, and
# it was the last thing in the program hard-coded in Portuguese. Every row a
# person reads has to come from the catalogue in every language, while the action
# column - which "case $esc in" matches - has to stay Portuguese on every
# machine, or a command copied off a forum stops working.
PAINEL_CORPO="$(sed -n '/^acao_painel()/,/^}/p' "$ROOT/src/bin/tandem")"
for chave in pan_pergunta pan_instalar pan_doctor pan_portas pan_logs \
             pan_escolha_arquivo pan_filtro_programas pan_filtro_todos; do
    contem "the panel reads '$chave' from the catalogue" \
           "t_msg $chave" "$PAINEL_CORPO"
done
for nome in instalar preparar programas remover android doctor autoteste \
            dados portas identidade backup restore repair memoria lista \
            enviar socorro logs; do
    contem "the action name '$nome' is still literal, as it must be" \
           "\"$nome\"" "$PAINEL_CORPO"
done
# And the rows really resolve, in every language - a key present in the code and
# absent from a catalogue would fall back and go unnoticed.
for lang in en pt_BR es fr zh_CN hi ar; do
    linha="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO="$lang" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"; t_msg pan_instalar' 2>/dev/null)"
    case "$linha" in
        pan_instalar|"") fail "the panel's first row exists in $lang" \
                              "a translated sentence" "${linha:-nothing}" ;;
        *) pass "the panel's first row exists in $lang" ;;
    esac
done

# The form shortcut has to name the field the form actually has. GitHub prefills
# an issue form by FIELD ID, and a parameter matching nothing looks exactly like
# one matching something: the client sent "linha" while list.yml calls the field
# "record", so the one up-path that works opened an EMPTY form while README.md
# and LEIAME.md both promise "the form already filled in". Compare the two files
# rather than trusting either.
if [ -f "$ROOT/.github/ISSUE_TEMPLATE/list.yml" ]; then
    CAMPO_FORM="$(awk '/^ *id: /{ print $2; exit }' "$ROOT/.github/ISSUE_TEMPLATE/list.yml")"
    PARAM_FORM="$(sed -n 's/.*issues\/new?template=list\.yml&\([a-z_]*\)=.*/\1/p' \
                      "$ROOT/src/bin/tandem" | head -1)"
    equal "the prefilled form names the field the template declares" \
          "$CAMPO_FORM" "$PARAM_FORM"
fi

# And the offer cannot fail in silence. With no browser xdg-open exits non-zero
# and says why on stderr; backgrounded and redirected to /dev/null that status
# was unreachable, so the owner clicked "open the form" and nothing happened at
# all - the shape of failure this project treats as a defect, not a limitation.
BLOCO_FORM="$(sed -n '/xdg-open "\$URL_FORM"/,/^ *fi$/p' "$ROOT/src/bin/tandem")"
contem "a browser that will not open produces a sentence" \
       "t_erro" "$BLOCO_FORM"
naocontem "and the launcher is not backgrounded, which would discard its status" \
          "setsid" "$BLOCO_FORM"

# The whole record builder has to refuse too, not just the predicate - a sieve
# nobody calls is decoration.
contem "t_lista_registro runs the sieve before returning a record" \
       "t_lista_vaza" "$(sed -n '/^t_lista_registro()/,/^}/p' "$ROOT/src/lib/common.sh")"
contem "and t_envio_envia runs it AGAIN at send time" \
       "t_lista_vaza" "$(sed -n '/^t_envio_envia()/,/^}/p' "$ROOT/src/lib/common.sh")"

section "language: the path a translator actually walks"

# Having .po files is not the same as being contributable. These four things are
# what stands between a speaker of Spanish and a corrected catalogue, and each
# one was missing when the format changed.

if [ -d "$ROOT/po" ] && [ -f "$ROOT/tools/atualiza-po.py" ]; then
    contem "po/LINGUAS lists the languages, gettext's own convention" \
           "pt_BR" "$(cat "$ROOT/po/LINGUAS" 2>/dev/null)"

    # THE CREDIT. Last-Translator, PO-Revision-Date and X-Generator are how a
    # person is credited and how Weblate keeps its place. The first version of
    # this pipeline rewrote headers from a template, which would have deleted
    # the name of everybody who had ever worked on the file.
    PO_T="$TMPROOT/po-tradutor"
    mkdir -p "$PO_T" && cp -a "$ROOT/po" "$PO_T/po"
    python3 - "$PO_T/po/fr.po" <<'FIM'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
alvo = '"Language-Team: fr\\n"'
assert s.count(alvo) == 1, s.count(alvo)
io.open(p, "w", encoding="utf-8").write(s.replace(
    alvo,
    '"Last-Translator: Marie Dupont <marie@example.org>\\n"\n'
    '"PO-Revision-Date: 2026-08-10 14:22+0200\\n"\n'
    '"X-Generator: Weblate 5.4\\n"\n' + alvo, 1))
FIM
    # Run the updater against the copy by pointing it at a tree of its own.
    cp -a "$ROOT/tools" "$PO_T/tools"
    mkdir -p "$PO_T/src/lib/idiomas" && cp "$ROOT"/src/lib/idiomas/*.txt "$PO_T/src/lib/idiomas/"
    primeira="$( cd "$PO_T" && python3 tools/atualiza-po.py 2>&1 )"
    # Assert the tool RAN, or the credit checks below pass vacuously on a file
    # nothing ever touched - which is exactly what happened the first time.
    contem "the updater runs at all in the sandbox" "entries" "$primeira"
    for campo in "Marie Dupont" "X-Generator: Weblate" "PO-Revision-Date"; do
        contem "regenerating keeps $campo" "$campo" "$(cat "$PO_T/po/fr.po")"
    done

    # THE STALENESS. Change the English and every translation of that one entry
    # has to be marked, or somebody reads a sentence about behaviour that is
    # gone. This is the defect the hand-rolled format could not even detect.
    python3 - "$PO_T/po/en.po" <<'FIM'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
alvo = ('msgctxt "sem_arquivo"\nmsgid "No file was given."\n'
        'msgstr "No file was given."')
assert s.count(alvo) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(
    alvo,
    'msgctxt "sem_arquivo"\nmsgid "No file was given."\n'
    'msgstr "You did not name a file."', 1))
FIM
    relatorio="$( cd "$PO_T" && python3 tools/atualiza-po.py 2>&1 )"
    # Count rather than match the padding: %-6s makes the gap depend on the
    # length of the language code, and a test that breaks on alignment teaches
    # people to loosen tests.
    equal "changing one English message marks all six translations fuzzy" "6" \
          "$(printf '%s\n' "$relatorio" | grep -c 'FUZZY')"
    for pl in pt_BR es fr zh_CN hi ar; do
        contem "$pl is one of them" "$pl" \
               "$(printf '%s\n' "$relatorio" | grep 'FUZZY')"
    done
    naocontem "and English itself is never fuzzy - it is the source" \
              "en " "$(printf '%s\n' "$relatorio" | grep 'FUZZY')"
    # And the stale entry must LEAVE the shipped catalogue.
    ( cd "$PO_T" && python3 tools/po-para-catalogo.py >/dev/null 2>&1 )
    equal "the stale entry leaves the French catalogue, falling back to English" \
          "0" "$(grep -c '^@sem_arquivo' "$PO_T/src/lib/idiomas/fr.txt" || true)"
    equal "and stays in English, which is the fallback" \
          "1" "$(grep -c '^@sem_arquivo' "$PO_T/src/lib/idiomas/en.txt" || true)"

    # A NEW MESSAGE. It must arrive untranslated in all six rather than not
    # arriving at all, because untranslated falls back and absent does not.
    python3 - "$PO_T/po/en.po" <<'FIM'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(
    s.rstrip("\n") + '\n\nmsgctxt "chave_nova_de_teste"\n'
    'msgid "A brand new sentence."\nmsgstr "A brand new sentence."\n')
FIM
    relatorio2="$( cd "$PO_T" && python3 tools/atualiza-po.py 2>&1 )"
    contem "a new message arrives in every language as untranslated" \
           "1 untranslated" "$relatorio2"
    contem "the new key reaches the French .po" \
           "chave_nova_de_teste" "$(cat "$PO_T/po/fr.po")"
    contem "and the template, so a new language starts complete" \
           "chave_nova_de_teste" "$(cat "$PO_T/po/tandem.pot")"

    # THE SOURCE LANGUAGE cannot drift from itself: en.po's msgstr IS the
    # English, and its msgid must equal it, or "what is the English" has two
    # answers.
    desiguais="$(cd "$ROOT" && python3 - <<'FIM'
import importlib.util, io, re
spec = importlib.util.spec_from_file_location("c", "tools/po-para-catalogo.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
texto = io.open("po/en.po", encoding="utf-8").read()
itens, _ = m.le_po("po/en.po")
traducoes = {k: t for k, t, f in itens}
ruins = []
for bloco in texto.split("

"):
    if 'msgctxt "' not in bloco:
        continue
    chave = re.search(r'msgctxt "([^"]+)"', bloco).group(1)
    corpo = bloco[bloco.index("msgid "):]
    ident = corpo[:corpo.index("msgstr ")]
    linhas = [l for l in ident.splitlines()]
    linhas[0] = linhas[0][len("msgid "):]
    partes = [m.CITADA.match(l.strip()).group(1) for l in linhas
              if m.CITADA.match(l.strip())]
    if m.descita(partes) != traducoes.get(chave):
        ruins.append(chave)
print(" ".join(ruins[:5]))
FIM
)"
    equal "in po/en.po the msgid and the msgstr are the same text" "" "$desiguais"
else
    skip "the translator path" "po/ or tools/atualiza-po.py is missing"
fi

section "language: the messages are data, not code"

# Every sentence in this program used to be a Portuguese literal inside the
# script that printed it. That was right while the product had one owner in
# one country and stopped being right the moment somebody elsewhere installed
# it.

IDIOMAS_DIR="$ROOT/src/lib/idiomas"
LINGUAS="pt_BR en es fr zh_CN hi ar"

for l in $LINGUAS; do
    if [ -f "$IDIOMAS_DIR/$l.txt" ]; then pass "the $l catalogue exists"
    else fail "the $l catalogue exists" "$IDIOMAS_DIR/$l.txt" "missing"; fi
done

# The load path must never evaluate a catalogue. A translator is not somebody
# who should have to know what a subshell is, and a translation file must not
# be able to run anything: these files will one day arrive from strangers.
CAT_MAU="$TMPROOT/mau.txt"
printf '@perigo\nvalor $HOME e $(touch %s/EXECUTOU) e `id`\n' "$TMPROOT" > "$CAT_MAU"
declare -A T_TESTE_CAT=()
t_catalogo_le "$CAT_MAU" T_TESTE_CAT
equal "a dollar sign in a translation is text, not an expansion" \
      'valor $HOME e $(touch '"$TMPROOT"'/EXECUTOU) e `id`' "${T_TESTE_CAT[perigo]}"
if [ -e "$TMPROOT/EXECUTOU" ]; then
    fail "a catalogue cannot run anything" "no side effect" "the file was created"
else
    pass "a catalogue cannot run anything"
fi

# A comment between entries is a comment, not the tail of the entry above it.
# Written the other way round it printed the separator lines to the user.
printf '@um\ntexto um\n\n# separador\n\n@dois\ntexto dois\n' > "$TMPROOT/com.txt"
declare -A T_COM=(); t_catalogo_le "$TMPROOT/com.txt" T_COM
equal "a comment between entries does not leak into the message" \
      "texto um" "${T_COM[um]}"
equal "and the entry after it is intact" "texto dois" "${T_COM[dois]}"

# Blank lines BETWEEN entries are trimmed; blank lines INSIDE a message are
# paragraph breaks and must survive - most of these are three paragraphs
# written for somebody having a bad afternoon.
equal "a paragraph break inside a message survives" \
      "I could not read this file.

XPTO" "$(TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_msg nao_consegui_ler XPTO')"

# Every key in the original has to exist in every translation, or fall back to
# it. The fallback is what makes a half-finished translation safe; the test is
# what stops one from staying half-finished by accident.
CHAVES_PT="$(grep -c '^@' "$IDIOMAS_DIR/pt_BR.txt")"
for l in $LINGUAS; do
    faltando=""
    while IFS= read -r k; do
        grep -qxF "$k" "$IDIOMAS_DIR/$l.txt" || faltando="$faltando ${k#@}"
    done < <(grep '^@' "$IDIOMAS_DIR/pt_BR.txt")
    equal "$l has every key the original has ($CHAVES_PT)" "" "$faltando"
done

# An empty value is worse than a missing one: a missing key falls back to
# Portuguese, an empty one prints nothing at all.
for l in $LINGUAS; do
    vazias="$(TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_IDIOMA_FORCADO="$l" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        for k in "${!T_MSG_BASE[@]}"; do
            v="$(t_msg "$k")"
            [ -n "$v" ] || printf "%s " "$k"
        done' 2>/dev/null)"
    equal "$l has no empty message" "" "$vazias"
done

# The fallback itself, exercised: a key the translation does not carry has to
# come back in Portuguese - never blank, and never the key name.
printf '@sem_arquivo\nOnly this one is translated\n' > "$TMPROOT/meio.txt"
cp "$IDIOMAS_DIR/en.txt" "$TMPROOT/en.txt"
MEIO="$(TANDEM_IDIOMAS_DIR="$TMPROOT" TANDEM_LIB="$ROOT/src/lib" \
    TANDEM_IDIOMA_FORCADO=meio bash -c '
    . "'"$ROOT"'/src/lib/common.sh"; TANDEM_IDIOMAS="en meio"
    TANDEM_IDIOMA=meio; T_MSG=(); t_catalogo_le "'"$TMPROOT"'/meio.txt" T_MSG
    t_msg sem_arquivo; printf "|"; t_msg ja_instalando' 2>/dev/null)"
equal "a translated key uses the translation" \
      "Only this one is translated" "${MEIO%%|*}"
equal "a key the translation lacks falls back to English, not to blank" \
      "Another installation is already running." "${MEIO#*|}"

# An unknown key must not print nothing. A silent message is the one bug this
# whole program exists to prevent, and a catalogue is exactly the sort of file
# where a line goes missing in an edit.
equal "an unknown key returns something rather than nothing" \
      "chave_que_nao_existe" \
      "$(TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_msg chave_que_nao_existe' 2>/dev/null)"

# Substitution is {1} {2}, deliberately not printf's %s: paths and versions
# carry percent signs, and this project has been bitten by that before.
equal "a value with a percent sign in it survives substitution" \
      "File not found:
/mnt/50% off/x.exe" \
      "$(TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_msg arquivo_sumiu "/mnt/50% off/x.exe"')"

# Picking the language: the environment beats the file, the file beats the
# system, and anything unrecognised lands on Portuguese rather than changing
# language under the people already using it.
escolhe() {
    TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" TANDEM_LIB="$ROOT/src/lib" \
    XDG_CONFIG_HOME="$TMPROOT/cfg-idioma" LC_ALL="" LC_MESSAGES="" LANG="$1" \
    TANDEM_IDIOMA_FORCADO="${2:-}" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; printf "%s" "$TANDEM_IDIOMA"'
}
equal "a Spanish system gets Spanish"          "es"    "$(escolhe es_ES.UTF-8)"
equal "a Chinese system gets Chinese"          "zh_CN" "$(escolhe zh_CN.UTF-8)"
# pt_PT, es_AR, zh_TW: the country is not the language, and falling back to the
# base code is what makes each catalogue work outside the one country it was
# written in.
equal "Portugal gets the Portuguese catalogue" "pt_BR" "$(escolhe pt_PT.UTF-8)"
equal "Argentina gets the Spanish one"         "es"    "$(escolhe es_AR.UTF-8)"
# English is the default now, and this is the case the reversal was for: the
# only people the old Portuguese default ever reached were those whose language
# Tandem has no catalogue for, and to them Portuguese is a wall, not a mercy.
equal "an unknown locale lands on English"     "en"    "$(escolhe fi_FI.UTF-8)"
equal "no locale at all lands on English"      "en"    "$(escolhe "")"
equal "the environment overrides the system"   "fr"    "$(escolhe zh_CN.UTF-8 fr)"

# Latin scripts are always present; the guard is for the ones that are not.
# Refusing on a machine we could not inspect would be worse than the boxes.
for l in pt_BR en es fr; do
    equal "$l never needs a font check" "0" \
          "$(TANDEM_LIB="$ROOT/src/lib" bash -c \
             '. "'"$ROOT"'/src/lib/common.sh"; t_idioma_tem_letras '"$l"'; echo $?')"
done

# Which catalogues claim to have been reviewed by a speaker. Shipping one that
# has not is defensible; shipping it without saying so is not.
equal "the default language counts as reviewed" "0" \
      "$(TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_idioma_revisado pt_BR; echo $?')"
for l in es fr zh_CN hi ar; do
    equal "$l is marked as not yet reviewed by a speaker" "1" \
          "$(TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" TANDEM_LIB="$ROOT/src/lib" bash -c \
             '. "'"$ROOT"'/src/lib/common.sh"; t_idioma_revisado '"$l"'; echo $?')"
done

# And the whole point, end to end: the same error, in each language, out of
# the real executable.
for l in en es fr zh_CN hi ar; do
    saida="$(env -i HOME="$TMPROOT/cli-idioma" PATH="/usr/bin:/bin" \
             TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$IDIOMAS_DIR" \
             TANDEM_IDIOMA_FORCADO="$l" bash "$ROOT/src/bin/tandem-jar" 2>&1)"
    naocontem "tandem-jar with no argument answers in $l, not in Portuguese" \
              "Nenhum arquivo" "$saida"
done

section "the hardware key pre-flight"

# The Sentinel route works because a Linux daemon owns the USB key and the
# Windows program reaches it over TCP 1947. So the most useful thing to check
# is whether that daemon is here - by reading, before any download and before
# any password, the way tandem-deb reads apt's verdict.

CHAVE_S="$(t_chave_estado sentinel)"
contem "the state names the service" "SERVICO=" "$CHAVE_S"
contem "and the port" "PORTA=" "$CHAVE_S"
equal "an unknown family is refused rather than guessed at" \
      "1" "$(t_chave_estado sozinho >/dev/null 2>&1; echo $?)"

# "I could not look" is a third answer and must never be flattened into "it is
# not running". Answering confidently from a check that did not happen is the
# failure mode this project treats as worse than saying nothing.
NAO_SEI="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_servico_vivo() { return 1; }
    t_porta_escutando() { return 2; }
    t_texto_chave sentinel' 2>/dev/null)"
# These expectations are ENGLISH now, and that is not a slip. The prose moved
# from the code into po/, English is the default language, and the suite runs
# without a forced locale - so what comes back is the English catalogue. The
# thing being asserted is unchanged: that the sentence says "I could not check"
# rather than condemning the machine.
contem "not being able to check says so, instead of condemning" \
       "could not check" "$NAO_SEI"

PARADO="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_servico_vivo() { return 1; }
    t_porta_escutando() { return 1; }
    t_texto_chave sentinel' 2>/dev/null)"
contem "a daemon that is really absent gets the probable cause" \
       "is NOT running" "$PARADO"
contem "and the exact thing to look for" "Run-time Environment" "$PARADO"

RODANDO="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_servico_vivo() { return 0; }
    t_porta_escutando() { return 0; }
    t_texto_chave sentinel' 2>/dev/null)"
contem "a daemon that IS running rules itself out instead of being repeated" \
       "IS ALREADY running" "$RODANDO"
contem "and names the one thing the shop cannot fix itself" \
       "company that made the program" "$RODANDO"

# Two families, two runtimes. Pasting the Sentinel installer name into the
# CodeMeter message would send somebody to the wrong vendor's site.
CM="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_servico_vivo() { return 1; }
    t_porta_escutando() { return 1; }
    t_texto_chave codemeter' 2>/dev/null)"
contem "CodeMeter is sent to CodeMeter's runtime" "CodeMeter Runtime" "$CM"
naocontem "and never to Sentinel's" "Sentinel LDK" "$CM"

section "the road that starts where Wine ends"

# WinApps and WinBoat boot a real Windows in QEMU/KVM and composite one
# window onto the Linux desktop with FreeRDP RemoteApp. That reaches exactly
# what Wine cannot - a real kernel for a .sys, USB passthrough for a legacy
# dongle - so a dead-end verdict that does not mention it is not the whole
# truth. What Tandem must never do is promise it on a machine that cannot
# carry one, or on a case where it does not help.
VM_VEREDITO="$(t_vm_possivel)"
equal "the verdict is one of the four known answers" \
      "sim" "$(case "${VM_VEREDITO%%|*}" in sim|apertado|bios|nao) echo sim ;; *) echo "nao (${VM_VEREDITO%%|*})" ;; esac)"
equal "and it carries the memory and the free disk it judged on" \
      "3" "$(printf '%s' "$VM_VEREDITO" | awk -F'|' '{ print NF }')"

# A processor that cannot virtualise gets no paragraph at all. Describing a
# road that does not leave from here is padding a bad answer, not answering.
SEM_VM="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_vm_possivel() { printf "nao|16000000|90000000"; }
    t_texto_maquina_virtual' 2>/dev/null)"
equal "no virtualisation in the processor means no offer" "" "$SEM_VM"

COM_VM="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_vm_possivel() { printf "sim|16000000|90000000"; }
    t_texto_maquina_virtual' 2>/dev/null)"
contem "a machine that can carry one is told the two programs by name" \
       "WinBoat" "$COM_VM"
contem "and the licence cost, which is the detail that decides it" \
       "Pro" "$COM_VM"
contem "and that Tandem is not going to install it" \
       "does not install this" "$COM_VM"

BIOS_VM="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_vm_possivel() { printf "bios|16000000|90000000"; }
    t_texto_maquina_virtual' 2>/dev/null)"
contem "virtualisation switched off in the BIOS is named as such, not as a no" \
       "BIOS" "$BIOS_VM"

# Anti-cheat refuses virtual machines by design. Offering the route there
# would cost somebody an afternoon and a Windows licence for nothing.
naocontem "the dead-end branch excludes anti-cheat from the offer" \
          "t_texto_maquina_virtual" \
          "$(grep -A 1 'MAQUINA=""' "$ROOT/src/bin/tandem-exe" | head -1)"
contem "and does it by testing the class, not by hoping" \
       'anticheat' "$(grep -A 2 'MAQUINA=""' "$ROOT/src/bin/tandem-exe")"

section "ports: where the pinpad and the scale ended up"

TEXTO_PORTAS="$(t_texto_portas "$PREF_ID")"
contem "the report says what it is for, in the owner's words" \
       "pinpad" "$TEXTO_PORTAS"
contem "and shows what was already pinned in this environment" \
       "/dev/ttyACM0" "$TEXTO_PORTAS"
if t_no_grupo dialout; then
    skip "warns about the dialout group" "whoever runs the suite is in it"
else
    contem "warns about the dialout group, which is the silent killer" \
           "dialout" "$TEXTO_PORTAS"
fi

# Wine hands out COM1, COM2, ... in the order it scans, and it scans ttyS
# first. That order is not cosmetic: it is why a USB pinpad lands above COM4
# on a machine with four onboard serial ports, and why old point-of-sale
# software then says the device is not there.
ORDEM="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_portas_seriais() { printf "/dev/ttyS0\n/dev/ttyS1\n/dev/ttyS2\n/dev/ttyS3\n/dev/ttyACM0\n"; }
    t_portas_paralelas() { :; }
    t_no_grupo() { return 0; }
    t_texto_portas /naoexiste' 2>/dev/null)"
contem "the fifth port is COM5, which is the whole problem" \
       "COM5" "$ORDEM"
contem "and the USB device above COM4 gets a warning of its own" \
       "accepts COM1 to COM4" "$ORDEM"
contem "with the exact command that moves it" \
       "tandem portas fixar COM2 /dev/ttyACM0" "$ORDEM"

section "native packages: AppImage"

# A header written here and now. The twenty bytes that decide everything are
# ELF + the AI mark + the generation + the machine, and the reader is not
# allowed to need anything else.
cabecalho_appimage() {
    local destino="$1" geracao="${2:-2}" maquina="${3:-\076\000}" shoff="${4:-}"
    {
        printf '\177ELF\002\001\001\000AI'
        printf "\\$(printf '%03o' "$geracao")"
        printf '\000\000\000\000\000\003\000'
        printf "$maquina"
        # e_version, e_entry, e_phoff: 4 + 8 + 8 bytes of zeros up to e_shoff
        head -c 20 /dev/zero
        if [ -n "$shoff" ]; then printf "$shoff"; else head -c 8 /dev/zero; fi
        head -c 16 /dev/zero          # e_flags, e_ehsize, e_phentsize, e_phnum
    } > "$destino"
    head -c $((64 - $(stat -c%s "$destino"))) /dev/zero >> "$destino"
}

AI_OK="$TMPROOT/ok.AppImage"
cabecalho_appimage "$AI_OK"
equal "the AppImage header is exactly 64 bytes" "64" "$(stat -c%s "$AI_OK")"
info_ai="$(t_appimage_info "$AI_OK")"
equal "reads the AppImage generation" "2" "$(t_campo "$info_ai" TIPO)"
equal "reads the processor it was built for" "x86_64" "$(t_campo "$info_ai" ARQUITETURA)"

# An ARM AppImage on this machine: the answer has to be that it does not run,
# and the reason has to be the processor.
AI_ARM="$TMPROOT/arm.AppImage"
cabecalho_appimage "$AI_ARM" 2 '\267\000'
equal "recognizes an ARM AppImage" "aarch64" \
      "$(t_campo "$(t_appimage_info "$AI_ARM")" ARQUITETURA)"

# A .AppImage that is only an ELF: an ordinary Linux program with a misleading
# name. Blocking it would be right and useless - the owner needs to be told it
# can still be run.
AI_ELF="$TMPROOT/so-elf.AppImage"
{ printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000'; head -c 48 /dev/zero; } > "$AI_ELF"
equal "an ELF with no AI mark is not taken for an AppImage" \
      "sem_marca_ai" "$(t_campo "$(t_appimage_info "$AI_ELF")" ERRO)"
printf 'nao sou um ELF nenhum, so texto\n' > "$TMPROOT/texto.AppImage"
equal "a text file is not taken for an AppImage" \
      "nao_e_elf" "$(t_campo "$(t_appimage_info "$TMPROOT/texto.AppImage")" ERRO)"

# The verdict that is worth the most, and the one no other program gives: the
# download was cut in the middle. The payload says how big it should be, and
# the file is shorter than that.
AI_CORTADO="$TMPROOT/cortado.AppImage"
python3 - "$AI_CORTADO" <<'PYFIM'
import struct, sys
# A 64-byte ELF header whose section table ends at 64, then a squashfs
# superblock declaring a filesystem far bigger than what follows it.
cab = bytearray(64)
cab[0:4] = b'\x7fELF'; cab[4] = 2; cab[5] = 1; cab[6] = 1
cab[8:10] = b'AI'; cab[10] = 2
struct.pack_into('<H', cab, 16, 3)          # e_type
struct.pack_into('<H', cab, 18, 0x3E)       # e_machine = x86_64
struct.pack_into('<Q', cab, 0x28, 64)       # e_shoff
struct.pack_into('<H', cab, 0x3A, 0)        # e_shentsize
struct.pack_into('<H', cab, 0x3C, 1)        # e_shnum -> payload starts at 64
sb = bytearray(96)
sb[0:4] = b'hsqs'
struct.pack_into('<Q', sb, 40, 10 * 1024 * 1024)   # says it is 10 MiB
open(sys.argv[1], 'wb').write(bytes(cab) + bytes(sb))
PYFIM
info_cortado="$(t_appimage_info "$AI_CORTADO")"
equal "the payload offset comes out of the header, with nothing run" \
      "64" "$(t_campo "$info_cortado" DESLOCAMENTO)"
equal "recognizes the payload as squashfs" "squashfs" "$(t_campo "$info_cortado" CARGA)"
equal "an interrupted download is recognized as interrupted" \
      "0" "$(t_campo "$info_cortado" COMPLETO)"

# Architecture: an x86_64 machine runs a 32-bit AppImage, and never the reverse.
t_arch_compativel x86_64 x86_64 && pass "x86_64 runs on x86_64" \
    || fail "x86_64 runs on x86_64" "compatible" "refused"
t_arch_compativel i386 x86_64 && pass "a 32-bit AppImage runs on a 64-bit machine" \
    || fail "a 32-bit AppImage runs on a 64-bit machine" "compatible" "refused"
t_arch_compativel x86_64 i386 && fail "a 64-bit AppImage does not run on a 32-bit machine" \
    "refused" "accepted" || pass "a 64-bit AppImage does not run on a 32-bit machine"
t_arch_compativel aarch64 x86_64 && fail "an ARM AppImage does not run on a PC" \
    "refused" "accepted" || pass "an ARM AppImage does not run on a PC"
# Not knowing is not a reason to refuse: an unreadable architecture is answered
# by trying, the same rule the proof of delivery follows.
t_arch_compativel '?' x86_64 && pass "an unknown architecture is not blocked" \
    || fail "an unknown architecture is not blocked" "compatible" "refused"

# FUSE. The text below is the real output of a real AppImage measured with
# /dev/fuse removed - not a sentence invented to match the pattern.
printf 'fuse: device not found, try '"'"'modprobe fuse'"'"' first\n\nCannot mount AppImage, please check your FUSE setup.\n' \
    > "$TMPROOT/fuse.log"
t_falha_fuse "$TMPROOT/fuse.log" && pass "recognizes the real FUSE failure" \
    || fail "recognizes the real FUSE failure" "recognized" "not recognized"
printf 'Segmentation fault\nsome other problem entirely\n' > "$TMPROOT/outro.log"
t_falha_fuse "$TMPROOT/outro.log" && fail "does not see FUSE where there is none" \
    "not recognized" "recognized" || pass "does not see FUSE where there is none"

# Reading the payload WITHOUT executing the file. The synthetic headers above
# carry no real squashfs, so what is checkable here is the CONTRACT: a file that
# cannot be read yields nothing rather than something wrong, and nothing is
# executed on the way. The real read is exercised against a genuine AppImage in
# tests/real-programs.sh.
t_appimage_nome "$AI_OK" >/dev/null 2>&1 &&
    fail "a header with no payload yields no name" "nothing" "a name" ||
    pass "a header with no payload yields no name, rather than a wrong one"
t_appimage_nome "$TMPROOT/texto.AppImage" >/dev/null 2>&1 &&
    fail "a text file yields no name" "nothing" "a name" ||
    pass "a text file yields no name"
# And the guard that matters: a file with no execute bit must never be run in
# order to read it. If the extraction ever falls back to the runtime for a file
# it cannot execute, this is where it shows up.
chmod -x "$AI_OK" 2>/dev/null
t_appimage_nome "$AI_OK" >/dev/null 2>&1
equal "reading a name never marks the file executable" "" \
      "$(find "$AI_OK" -perm -u+x 2>/dev/null)"

# Menu entries: ours are pruned when the file disappears, and nobody else's is
# ever touched.
APPS="$HOME/.local/share/applications"; mkdir -p "$APPS"
printf 'x' > "$TMPROOT/existe.AppImage"
printf '[Desktop Entry]\nName=Existe\nX-Tandem-AppImage=%s\n' "$TMPROOT/existe.AppImage" \
    > "$APPS/tandem-appimage-111.desktop"
printf '[Desktop Entry]\nName=Sumiu\nX-Tandem-AppImage=%s\n' "$TMPROOT/nao-existe.AppImage" \
    > "$APPS/tandem-appimage-222.desktop"
printf '[Desktop Entry]\nName=De Outra Pessoa\nExec=outracoisa\n' \
    > "$APPS/appimage-de-outro.desktop"
listados="$(t_atalhos_appimage)"
equal "only the AppImage that still exists is listed" \
      "$APPS/tandem-appimage-111.desktop" "$listados"
[ -f "$APPS/tandem-appimage-222.desktop" ] &&
    fail "the entry whose file vanished is removed" "removed" "still there" ||
    pass "the entry whose file vanished is removed"
[ -f "$APPS/appimage-de-outro.desktop" ] &&
    pass "somebody else's shortcut is preserved" ||
    fail "somebody else's shortcut is preserved" "preserved" "removed"

section "native packages: Java"

# Real jars, built here: python3 is already a dependency of the package, so the
# suite does not need a JDK to have something authentic to read.
JARS="$TMPROOT/jars"; mkdir -p "$JARS"
python3 - "$JARS" <<'PYFIM'
import os, struct, sys, zipfile

destino = sys.argv[1]

def classe(major, corpo=b''):
    return b'\xca\xfe\xba\xbe' + struct.pack('>HH', 0, major) + corpo

def jar(nome, manifesto, entradas):
    with zipfile.ZipFile(os.path.join(destino, nome), 'w') as z:
        z.writestr('META-INF/MANIFEST.MF', manifesto)
        for n, d in entradas:
            z.writestr(n, d)

# Java 21 (major 65) and a Main-Class: a program.
jar('programa.jar', b'Manifest-Version: 1.0\r\nMain-Class: Ola\r\n\r\n',
    [('Ola.class', classe(65))])
# The same classes with no Main-Class: a library, and a double click on it gets
# "no main manifest attribute" from Java.
jar('biblioteca.jar', b'Manifest-Version: 1.0\r\n\r\n', [('Ola.class', classe(65))])
# A java agent: not run by double clicking either, but for another reason.
jar('agente.jar', b'Manifest-Version: 1.0\r\nPremain-Class: Ola\r\n\r\n',
    [('Ola.class', classe(65))])
# Multi-release: the class under versions/ is there so a NEWER Java picks it up.
# Counting it would demand a Java the program does not require.
jar('multi.jar', b'Manifest-Version: 1.0\r\nMain-Class: Ola\r\nMulti-Release: true\r\n\r\n',
    [('Ola.class', classe(65)), ('META-INF/versions/30/Ola.class', classe(74))])
# A Class-Path folded at 72 bytes, the way the real manifest writer folds it:
# the file name is split down the middle.
jar('dobrado.jar',
    b'Manifest-Version: 1.0\r\nMain-Class: Ola\r\n'
    b'Class-Path: uma-biblioteca-de-nome-bem-comprido.jar outra-bibl\r\n'
    b' ioteca-javafx-comprida.jar\r\n\r\n',
    [('Ola.class', classe(65))])
# JavaFX named in the constant pool of the main class, and carried nowhere.
jar('fx.jar', b'Manifest-Version: 1.0\r\nMain-Class: Fx\r\n\r\n',
    [('Fx.class', classe(52, b'javafx/application/Application'))])
# An interrupted download: the index of a zip is at the END of the file.
with open(os.path.join(destino, 'programa.jar'), 'rb') as f:
    inteiro = f.read()
open(os.path.join(destino, 'cortado.jar'), 'wb').write(inteiro[:len(inteiro) // 2])
PYFIM

info_jar="$(t_jar_info "$JARS/programa.jar")"
equal "reads the Main-Class of a program" "Ola" "$(t_campo "$info_jar" PRINCIPAL)"
equal "translates class file version 65 into Java 21" "21" "$(t_campo "$info_jar" JAVA)"
equal "keeps the raw major version for the log" "65" "$(t_campo "$info_jar" MAIOR)"
equal "a library has no Main-Class" "" \
      "$(t_campo "$(t_jar_info "$JARS/biblioteca.jar")" PRINCIPAL)"
equal "an agent is recognized as an agent" "1" \
      "$(t_campo "$(t_jar_info "$JARS/agente.jar")" AGENTE)"
equal "a library is not mistaken for an agent" "0" \
      "$(t_campo "$(t_jar_info "$JARS/biblioteca.jar")" AGENTE)"
# The one that matters: a class marked for a Java that does not exist yet sits
# under versions/ precisely so it is ignored by older ones. Counting it would
# announce "needs Java 30" for a program that runs on 21.
info_multi="$(t_jar_info "$JARS/multi.jar")"
equal "multi-release is recognized" "1" "$(t_campo "$info_multi" MULTI)"
equal "a class under versions/ does not raise the required Java" \
      "21" "$(t_campo "$info_multi" JAVA)"
# A Class-Path split in the middle of a file name has to come back whole,
# otherwise Tandem looks for a file that does not exist and blames the folder.
equal "a folded Class-Path is put back together" \
      "uma-biblioteca-de-nome-bem-comprido.jar,outra-biblioteca-javafx-comprida.jar" \
      "$(t_campo "$(t_jar_info "$JARS/dobrado.jar")" DEPENDENCIAS)"
equal "JavaFX is found in the constant pool" "1" \
      "$(t_campo "$(t_jar_info "$JARS/fx.jar")" JAVAFX)"
equal "an interrupted download is not reported as a broken program" \
      "zip_invalido" "$(t_campo "$(t_jar_info "$JARS/cortado.jar")" ERRO)"
equal "a file that is not a zip at all" \
      "zip_invalido" "$(t_campo "$(t_jar_info "$TMPROOT/texto.AppImage")" ERRO)"

# The installed Java's version, written two different ways by Java itself.
# Reading only the first number turns Java 8 into Java 1 - and then Tandem
# would refuse a program on a machine that runs it perfectly well.
FINGE_J="$TMPROOT/finge-java"; mkdir -p "$FINGE_J"
cat > "$FINGE_J/java" <<'FIMJ'
#!/bin/sh
echo 'openjdk version "1.8.0_412"' >&2
FIMJ
chmod +x "$FINGE_J/java"
equal "Java 1.8.0_412 is Java 8" "8" "$(PATH="$FINGE_J:$PATH" t_java_versao)"
cat > "$FINGE_J/java" <<'FIMJ'
#!/bin/sh
echo 'openjdk version "21.0.10" 2026-01-20' >&2
FIMJ
chmod +x "$FINGE_J/java"
equal "Java 21.0.10 is Java 21" "21" "$(PATH="$FINGE_J:$PATH" t_java_versao)"
cat > "$FINGE_J/java" <<'FIMJ'
#!/bin/sh
echo 'java version "17.0.9" 2023-10-17 LTS' >&2
FIMJ
chmod +x "$FINGE_J/java"
equal "the Oracle wording is read the same way" "17" "$(PATH="$FINGE_J:$PATH" t_java_versao)"

# A version number read off a file becomes part of a command that runs as root.
plano_j="$(t_script_instalacao java21)"
case "$plano_j" in
    *"openjdk-21-jre"*) pass "the plan installs the Java version the program asks for" ;;
    *) fail "the plan installs the Java version the program asks for" "openjdk-21-jre" "$plano_j" ;;
esac
plano_j="$(t_script_instalacao 'java21; rm -rf /')"
case "$plano_j" in
    *"rm -rf"*) fail "a poisoned Java version does not reach the root command" \
                     "only digits" "$plano_j" ;;
    *"openjdk-21-jre"*) pass "a poisoned Java version does not reach the root command" ;;
    *) fail "a poisoned Java version does not reach the root command" "openjdk-21-jre" "$plano_j" ;;
esac
plano_j="$(t_script_instalacao fuse)"
case "$plano_j" in
    *libfuse2t64*libfuse2*) pass "FUSE is tried under both names it has had" ;;
    *) fail "FUSE is tried under both names it has had" "libfuse2t64 || libfuse2" "$plano_j" ;;
esac

section "native packages: the whole command, end to end"

# The libraries were right and five commands still printed nothing, because no
# test had ever run a command. These run the two new executables whole, with no
# Wine, no Java and no network - and demand a sentence, in Portuguese, on the
# way out.
CASA_N="$TMPROOT/casa-nativos"; mkdir -p "$CASA_N"
: > "$CASA_N/.primeira-vez"
correr_nativo() {
    env -i HOME="$CASA_N" PATH="/usr/bin:/bin" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ROOT/src/bin" \
        bash "$ROOT/src/bin/$1" "$2" 2>&1
}

saida_n="$(correr_nativo tandem-jar "$JARS/biblioteca.jar")"
case "$saida_n" in
    *"a piece of a program"*) pass "a library .jar is explained, not reported as broken" ;;
    *) fail "a library .jar is explained, not reported as broken" \
            "the sentence about being a piece of a program" "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-jar "$JARS/cortado.jar")"
case "$saida_n" in
    *"incomplete"*|*"cut off halfway"*) pass "an interrupted .jar download says so" ;;
    *) fail "an interrupted .jar download says so" "the sentence about the download" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-jar "$JARS/agente.jar")"
case "$saida_n" in
    *"add-on for another Java program"*) pass "a java agent is explained" ;;
    *) fail "a java agent is explained" "the sentence about being an accessory" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$AI_CORTADO")"
case "$saida_n" in
    *"did not finish"*|*"cut off halfway"*) pass "an interrupted AppImage download says so" ;;
    *) fail "an interrupted AppImage download says so" "the sentence about the download" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$AI_ARM")"
case "$saida_n" in
    *"different kind of processor"*) pass "an ARM AppImage says it is the processor" ;;
    *) fail "an ARM AppImage says it is the processor" "the sentence about the processor" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$AI_ELF")"
case "$saida_n" in
    *"ordinary Linux program"*) pass "an ELF named .AppImage is told how to run anyway" ;;
    *) fail "an ELF named .AppImage is told how to run anyway" \
            "the sentence about an ordinary Linux program" "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$TMPROOT/nao-existe.AppImage")"
case "$saida_n" in
    *"not found"*) pass "a missing file is reported by both new commands" ;;
    *) fail "a missing file is reported by both new commands" "a sentence about the file" \
            "${saida_n:-zero bytes}" ;;
esac

# Dispatch: "tandem install" has to reach the right executable. TANDEM_BIN
# exists for exactly this - with the path nailed down the test would have been
# exercising the INSTALLED package.
ESPIAO="$TMPROOT/espiao"; mkdir -p "$ESPIAO"
for b in tandem-exe tandem-apk tandem-appimage tandem-jar; do
    printf '#!/bin/sh\necho "CHAMOU %s"\n' "$b" > "$ESPIAO/$b"
    chmod +x "$ESPIAO/$b"
done
despachar() {
    env -i HOME="$CASA_N" PATH="/usr/bin:/bin" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ESPIAO" \
        bash "$ROOT/src/bin/tandem" install "$1" 2>&1
}
equal "a .AppImage goes to tandem-appimage" "CHAMOU tandem-appimage" "$(despachar "$AI_OK")"
equal "a .jar goes to tandem-jar" "CHAMOU tandem-jar" "$(despachar "$JARS/programa.jar")"
# With no extension the decision is by content, and the specific mark comes
# before the generic one: every AppImage is an ELF and every jar is a zip.
cp "$AI_OK" "$TMPROOT/sem-extensao"
equal "with no extension, an AppImage is recognized by its header" \
      "CHAMOU tandem-appimage" "$(despachar "$TMPROOT/sem-extensao")"
cp "$JARS/programa.jar" "$TMPROOT/sem-extensao-jar"
equal "with no extension, a runnable jar is recognized by its manifest" \
      "CHAMOU tandem-jar" "$(despachar "$TMPROOT/sem-extensao-jar")"
# And a zip that is NOT a jar stays with Android, which is what it was before.
cp "$JARS/biblioteca.jar" "$TMPROOT/so-zip"
equal "a zip with no Main-Class stays with Android" \
      "CHAMOU tandem-apk" "$(despachar "$TMPROOT/so-zip")"

section ".apkm: declared since 3.0 and never once exercised"

# CLAUDE.md said it plainly: ".apkm support is declared but only .xapk/.apks were
# tested." A format the package registers a MIME type for, and whose name appears
# in the reader's own table, with no fixture behind it - which is a promise, not a
# feature.
info_apkm="$(python3 "$TANDEM_LIB/apkinfo.py" "$ARTIFACTS/mirror.apkm")"
equal "an .apkm is recognised as its own format" "apkm" "$(t_campo "$info_apkm" FORMATO)"
equal "the package name comes out of the base apk inside it" "com.exemplo.apkm" \
      "$(t_campo "$info_apkm" PACOTE)"
equal "the minimum Android version is read" "26" "$(t_campo "$info_apkm" MINSDK)"
equal "the parts are counted" "3" "$(t_campo "$info_apkm" SPLITS)"
equal "and the ABIs come from the split names" "arm64-v8a,armeabi-v7a" \
      "$(t_campo "$info_apkm" ABIS)"

# Some .apkm files are encrypted by the site that distributes them, and only that
# site's own installer opens one. Before this, the reader walked into z.read() and
# came back with a Python exception in English about a missing password - the exact
# shape of failure this project treats as a defect.
info_trancado="$(python3 "$TANDEM_LIB/apkinfo.py" "$ARTIFACTS/trancado.apkm")"
equal "an encrypted .apkm is recognised as encrypted" "1" \
      "$(t_campo "$info_trancado" CIFRADO)"
equal "and it does not come back as a Python exception" "" \
      "$(t_campo "$info_trancado" ERRO)"
equal "the format is still named, from the file name" "apkm" \
      "$(t_campo "$info_trancado" FORMATO)"
equal "an ordinary package is not called encrypted" "0" \
      "$(t_campo "$(python3 "$TANDEM_LIB/apkinfo.py" "$ARTIFACTS/jogo.xapk")" CIFRADO)"

# And the whole command, with nobody to ask: it has to say so in Portuguese
# rather than fail at extraction.
saida_apkm="$(env -i HOME="$TMPROOT/casa-apkm" PATH="/usr/bin:/bin" \
             TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ROOT/src/bin" \
             timeout 60 bash "$ROOT/src/bin/tandem-apk" "$ARTIFACTS/trancado.apkm" 2>&1)"
case "$saida_apkm" in
    *"protected by the site"*) pass "tandem-apk explains an encrypted .apkm" ;;
    *) fail "tandem-apk explains an encrypted .apkm" \
            "the sentence about the site protecting it" "${saida_apkm:-zero bytes}" ;;
esac

section "native packages: reading .deb and .rpm without installing"

# Real ar archives with real gzipped control tarballs, written by tests/mkdeb.py
# for the same reason tests/mkapk.py writes real binary manifests: a fixture that
# only looks like the format proves nothing about the reader.
DEBS="$TMPROOT/debs"; mkdir -p "$DEBS"
python3 "$ROOT/tests/mkdeb.py" "$DEBS/simples.deb" >/dev/null
python3 "$ROOT/tests/mkdeb.py" "$DEBS/velho.deb" Package=programa-antigo \
        Depends='libssl1.1, libicu70, libc6 (>= 2.34)' >/dev/null
python3 "$ROOT/tests/mkdeb.py" "$DEBS/arm.deb" Package=so-arm Architecture=arm64 >/dev/null
python3 "$ROOT/tests/mkdeb.py" "$DEBS/xz.deb" Package=com-xz --compressao=xz >/dev/null
python3 "$ROOT/tests/mkdeb.py" "$DEBS/alternativas.deb" Package=alt \
        Depends='curl | wget, python3:any | python3.12, foo [amd64] <!nocheck>' >/dev/null

info_deb="$(t_deb_info "$DEBS/simples.deb")"
equal "reads the package name" "teste" "$(t_campo "$info_deb" PACOTE)"
equal "reads the version" "1.0" "$(t_campo "$info_deb" VERSAO)"
equal "reads the architecture" "all" "$(t_campo "$info_deb" ARQUITETURA)"
equal "reads the short description without the long one leaking in" \
      "pacote sintetico para teste" "$(t_campo "$info_deb" DESCRICAO)"
equal "control.tar.xz is read the same as .gz" "com-xz" \
      "$(t_campo "$(t_deb_info "$DEBS/xz.deb")" PACOTE)"

# Debian dependency syntax reduced to something a shell can split, with the
# architecture qualifier, the architecture restriction and the build profile all
# dropped: they qualify WHICH BUILD needs the dependency, and by the time
# somebody is double-clicking that question is already answered.
equal "dependencies come out normalised, alternatives kept" \
      "curl|wget;python3|python3.12;foo" \
      "$(t_campo "$(t_deb_info "$DEBS/alternativas.deb")" DEPENDE)"
equal "a version constraint stays attached to its name" \
      "libssl1.1;libicu70;libc6(>= 2.34)" \
      "$(t_campo "$(t_deb_info "$DEBS/velho.deb")" DEPENDE)"

# A .deb whose ar header claims more bytes than the file has. Same verdict as a
# truncated AppImage, same cause, and it is the reading that establishes it.
#
# Cut 20 bytes off the end rather than at a fixed offset: a cut that happens to
# land on a member boundary leaves an archive that parses cleanly, and the first
# version of this test passed for exactly that reason while proving nothing. The
# reader now also refuses a package with no data member, so both shapes of
# truncation are caught.
head -c "$(( $(stat -c%s "$DEBS/simples.deb") - 20 ))" \
     "$DEBS/simples.deb" > "$DEBS/cortado.deb"
# And the other shape: cut exactly where the data member begins, so every header
# that IS there is perfectly consistent and nothing looks wrong.
python3 - "$DEBS/simples.deb" "$DEBS/cortado-limpo.deb" <<'PYCORTE'
import sys
d = open(sys.argv[1], "rb").read()
p = 8
while p + 60 <= len(d):
    nome = d[p:p + 16].decode().strip().rstrip("/")
    tam = int(d[p + 48:p + 58].decode().strip())
    if nome.startswith("data.tar"):
        open(sys.argv[2], "wb").write(d[:p])
        break
    p += 60 + tam + (tam % 2)
PYCORTE
case "$(t_campo "$(t_deb_info "$DEBS/cortado.deb")" ERRO)" in
    pacote_incompleto|pacote_sem_dados) pass "an interrupted .deb download is recognised as interrupted" ;;
    *) fail "an interrupted .deb download is recognised as interrupted" \
            "a truncation token" "$(t_campo "$(t_deb_info "$DEBS/cortado.deb")" ERRO)" ;;
esac
case "$(t_campo "$(t_deb_info "$DEBS/cortado-limpo.deb")" ERRO)" in
    pacote_incompleto|pacote_sem_dados)
        pass "a .deb cut on a member boundary is still recognised as incomplete" ;;
    *) fail "a .deb cut on a member boundary is still recognised as incomplete" \
            "a truncation token" \
            "$(t_campo "$(t_deb_info "$DEBS/cortado-limpo.deb")" ERRO)" ;;
esac
printf 'nao sou um pacote\n' > "$DEBS/texto.deb"
case "$(t_campo "$(t_deb_info "$DEBS/texto.deb")" ERRO)" in
    nao_e_deb) pass "a text file is not taken for a package" ;;
    *) fail "a text file is not taken for a package" "nao_e_deb" \
            "$(t_campo "$(t_deb_info "$DEBS/texto.deb")" ERRO)" ;;
esac

# dpkg-deb has to accept what mkdeb.py writes. Without this the fixtures could
# drift into a shape only our own reader understands, and the agreement between
# the two would be an agreement about nothing.
if command -v dpkg-deb >/dev/null 2>&1; then
    for d in simples velho arm xz; do
        equal "dpkg-deb agrees about $d.deb" \
              "$(dpkg-deb -f "$DEBS/$d.deb" Package 2>/dev/null)" \
              "$(t_campo "$(t_deb_info "$DEBS/$d.deb")" PACOTE)"
    done
else
    skip "agreement with dpkg-deb" "dpkg-deb not installed"
fi

# Architecture. "all" fits anywhere; a foreign one counts only when dpkg was
# told about it, which is the same switch that makes 32-bit Wine possible.
t_deb_arch_serve all && pass "an architecture-independent package fits" \
    || fail "an architecture-independent package fits" "serve" "recusado"
t_deb_arch_serve "$(t_arch_sistema)" && pass "this machine's own architecture fits" \
    || fail "this machine's own architecture fits" "serve" "recusado"
t_deb_arch_serve arquitetura-que-nao-existe &&
    fail "an unknown architecture is refused" "recusado" "aceito" ||
    pass "an unknown architecture is refused"

# The heuristic that separates two verdicts apt writes identically: a library
# with a release welded to its name will never install here, while a plain
# program name is a repository the machine has not been told about. Getting this
# backwards sends the owner looking for a fix that does not exist.
for n in libssl1.1 libicu70 libwebkit2gtk-4.0-37 libpython3.10 python3.10 libboost1.74.0; do
    t_versao_de_sistema "$n" && pass "$n reads as welded to a release" \
        || fail "$n reads as welded to a release" "sim" "nao"
done
for n in acme-driver zenity curl meu-programa-da-loja; do
    t_versao_de_sistema "$n" && fail "$n does not read as a library version" "nao" "sim" \
        || pass "$n does not read as a library version"
done

# apt's own words, parsed rather than re-derived. Reimplementing dependency
# resolution in shell would be a second opinion that is wrong precisely when it
# disagrees with the only one that counts.
saida_apt="programa-antigo : Depends: libssl1.1 but it is not installable
                   Depends: libicu70 but it is not installable
E: Unable to correct problems, you have held broken packages."
equal "the unsatisfiable names come out of apt's own output" \
      "libicu70 libssl1.1" "$(t_deb_naoinstalaveis "$saida_apt" | tr '\n' ' ' | sed 's/ $//')"

# The .rpm reader, on a header written here. The lead is 96 bytes, then a
# signature header padded to an 8-byte boundary, then the real one - and that
# padding is the step that turns a perfectly good file into "unrecognised
# header" when it is skipped wrong.
python3 - "$TMPROOT/teste.rpm" <<'PYFIM'
import struct, sys

def cabecalho(entradas, loja):
    fora = b"\x8e\xad\xe8\x01" + b"\0" * 4
    fora += struct.pack(">II", len(entradas), len(loja))
    for tag, tipo, off, cont in entradas:
        fora += struct.pack(">iiii", tag, tipo, off, cont)
    return fora + loja

loja = b""
entradas = []
def texto(tag, valor, tipo=6):
    global loja, entradas
    entradas.append((tag, tipo, len(loja), 1))
    loja += valor.encode() + b"\0"

texto(1000, "hello")            # NAME
texto(1001, "2.12.1")           # VERSION
texto(1002, "1.fc39")           # RELEASE
texto(1004, "Prints a greeting", 9)   # SUMMARY, I18NSTRING
texto(1010, "Fedora Project")   # DISTRIBUTION
texto(1022, "x86_64")           # ARCH

lead = b"\xed\xab\xee\xdb" + b"\x03\x00" + b"\0" * 90
assinatura = cabecalho([], b"")
pad = b"\0" * ((8 - (len(lead) + len(assinatura)) % 8) % 8)
open(sys.argv[1], "wb").write(lead + assinatura + pad + cabecalho(entradas, loja))
PYFIM
info_rpm="$(t_rpm_info "$TMPROOT/teste.rpm")"
equal "reads the rpm package name" "hello" "$(t_campo "$info_rpm" PACOTE)"
equal "joins version and release the way rpm names them" "2.12.1-1.fc39" \
      "$(t_campo "$info_rpm" VERSAO)"
equal "reads the rpm architecture" "x86_64" "$(t_campo "$info_rpm" ARQUITETURA)"
equal "reads which distribution built it" "Fedora Project" \
      "$(t_campo "$info_rpm" DISTRIBUICAO)"
equal "reads the summary out of an I18NSTRING" "Prints a greeting" \
      "$(t_campo "$info_rpm" DESCRICAO)"
head -c 120 "$TMPROOT/teste.rpm" > "$TMPROOT/curto.rpm"
case "$(t_campo "$(t_rpm_info "$TMPROOT/curto.rpm")" ERRO)" in
    rpm_cabecalho_curto|pacote_incompleto) pass "a truncated .rpm is recognised as truncated" ;;
    *) fail "a truncated .rpm is recognised as truncated" "a truncation token" \
            "$(t_campo "$(t_rpm_info "$TMPROOT/curto.rpm")" ERRO)" ;;
esac
equal "a .deb is not taken for an .rpm" "nao_e_rpm" \
      "$(t_campo "$(t_rpm_info "$DEBS/simples.deb")" ERRO)"

# Flatpak reference files are INI, and the two kinds mean different things: one
# installs a program, the other changes where the machine gets programs from.
cat > "$TMPROOT/prog.flatpakref" <<'FIMREF'
[Flatpak Ref]
Name=org.gnome.gedit
Branch=stable
Title=org.gnome.gedit from flathub
Url=https://dl.flathub.org/repo/
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
FIMREF
equal "reads the program name out of a .flatpakref" "org.gnome.gedit" \
      "$(t_flatpak_campo "$TMPROOT/prog.flatpakref" Name)"
equal "reads the runtime repository, which the install needs first" \
      "https://dl.flathub.org/repo/flathub.flatpakrepo" \
      "$(t_flatpak_campo "$TMPROOT/prog.flatpakref" RuntimeRepo)"
equal "a key that is not there comes back empty, not wrong" "" \
      "$(t_flatpak_campo "$TMPROOT/prog.flatpakref" NaoExiste)"

# A script that is a payload behind a shell header is meant to be run; a small
# plain script is far more likely something to look at first.
printf '#!/bin/sh\necho ola\n' > "$TMPROOT/pequeno.sh"
t_script_instalador "$TMPROOT/pequeno.sh" &&
    fail "a small script is not treated as an installer" "nao" "sim" ||
    pass "a small script is not treated as an installer"
printf '#!/bin/sh\n# This script was generated using Makeself 2.4.5\n_ARCHIVE=1\n' \
    > "$TMPROOT/makeself.sh"
t_script_instalador "$TMPROOT/makeself.sh" &&
    pass "a makeself installer is recognised" ||
    fail "a makeself installer is recognised" "sim" "nao"
{ printf '#!/bin/sh\n'; head -c 300000 /dev/zero | tr '\0' 'x'; } > "$TMPROOT/gordo.sh"
t_script_instalador "$TMPROOT/gordo.sh" &&
    pass "a megabyte of payload behind a shell header is an installer" ||
    fail "a megabyte of payload behind a shell header is an installer" "sim" "nao"

# apt and dpkg failures, translated from messages COPIED off a real terminal.
# Every one of these was produced on purpose on an Ubuntu 24.04 and pasted here;
# none was written from documentation.
verifica_causa() {
    printf '%s\n' "$2" > "$TMPROOT/causa.log"
    local dito; dito="$(t_causa_apt "$TMPROOT/causa.log")"
    case "$dito" in
        *"$3"*) pass "$1" ;;
        *) fail "$1" "something with \"$3\"" "${dito:-nothing}" ;;
    esac
}
verifica_causa "the dpkg lock becomes a sentence about waiting" \
  'E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 16003 (python3)' \
  'already installing'
verifica_causa "dpkg's own wording for the lock is recognised too" \
  'dpkg: error: dpkg frontend lock was locked by another process with pid 16003' \
  'already installing'
verifica_causa "the architecture mismatch is recognised" \
  ' package architecture (arm64) does not match system (amd64)' \
  'different kind of processor'
verifica_causa "held broken packages becomes a sentence about missing pieces" \
  'E: Unable to correct problems, you have held broken packages.' \
  'Components this package needs are missing'
verifica_causa "a full disk says the disk is full" \
  'dpkg: unrecoverable fatal error: No space left on device' \
  'disk is full'
verifica_causa "a file conflict names the risk to the other program" \
  "dpkg: error processing archive: trying to overwrite '/usr/bin/foo', which is also in package outro" \
  'overwrite'
verifica_causa "no internet says no internet" \
  'Err:1 http://archive.ubuntu.com/ubuntu noble InRelease
  Temporary failure resolving archive.ubuntu.com' \
  'internet'
# The lock has to win over the broken-packages line when both appear, because it
# is the cause and the other is the consequence.
verifica_causa "the lock wins over the consequence when both appear" \
  'E: Could not get lock /var/lib/dpkg/lock-frontend
E: Unable to correct problems, you have held broken packages.' \
  'already installing'
printf 'nada de especial aqui\n' > "$TMPROOT/causa.log"
t_causa_apt "$TMPROOT/causa.log" >/dev/null &&
    fail "an unrecognised failure does not invent a cause" "nao reconhece" "inventou" ||
    pass "an unrecognised failure does not invent a cause"

# Declaring a MIME type is not neutral: with no explicit default recorded, the
# desktop database picks a handler FROM the declarations, so naming a type takes
# it. tandem-script must therefore name none - the decision not to steal
# application/x-shellscript from a text editor lives in the absence of one line,
# and an absence is exactly what somebody tidies up later.
if grep -q '^MimeType=' "$ROOT/src/applications/tandem-script.desktop"; then
    fail "tandem-script claims no MIME type" \
         "no MimeType= line: declaring the type takes it" \
         "$(grep '^MimeType=' "$ROOT/src/applications/tandem-script.desktop")"
else
    pass "tandem-script claims no MIME type, so .sh stays with the text editor"
fi
# And the reason has to stay written next to it, or the line comes back.
if grep -q 'Open with' "$ROOT/src/applications/tandem-script.desktop"; then
    pass "and the reason is written in the file"
else
    fail "and the reason is written in the file" "the explanation" "missing"
fi
# tandem-repair must not claim it either, from the other direction.
if grep -q 'TIPOS_SCRIPT\|x-shellscript' "$ROOT/src/bin/tandem-repair"; then
    grep -q 'application/x-shellscript is deliberately NOT' "$ROOT/src/bin/tandem-repair" &&
        pass "tandem-repair mentions x-shellscript only to say it is left alone" ||
        fail "tandem-repair mentions x-shellscript only to say it is left alone" \
             "only the comment" "it appears in a claimed list"
else
    fail "tandem-repair records why x-shellscript is left alone" "the comment" "nothing"
fi

# --------------------------------------------------------------------
# "It finished with no error" was the whole verdict for a shell installer, and a
# shell installer is the one format with no database to ask afterwards. These two
# run the real handler through a pty, because it refuses to run anything without
# a confirmation and a pipe is not a terminal.
if command -v script >/dev/null 2>&1; then
    roda_script() {                     # <file> -> what the owner sees
        local casa="$TMPROOT/casa-sh-$2"
        rm -rf "$casa"; mkdir -p "$casa"
        printf 's\n' | env -i HOME="$casa" PATH="/usr/bin:/bin" \
            TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ROOT/src/bin" \
            TANDEM_IDIOMA_FORCADO=en \
            script -qec "bash $ROOT/src/bin/tandem-script $1" /dev/null 2>&1
    }
    printf '#!/bin/sh\nexit 0\n' > "$TMPROOT/mudo.sh"; chmod +x "$TMPROOT/mudo.sh"
    printf '#!/bin/sh\necho "Installing FooApp 1.0..."\nexit 0\n' > "$TMPROOT/falante.sh"
    chmod +x "$TMPROOT/falante.sh"

    saida_mudo="$(roda_script "$TMPROOT/mudo.sh" mudo)"
    case "$saida_mudo" in
        *"said nothing"*) pass "an installer that exits 0 instantly and silently is not called a success" ;;
        *) fail "an installer that exits 0 instantly and silently is not called a success" \
                "the warning about saying nothing" "$saida_mudo" ;;
    esac
    # And the guard must not fire on an installer that did something. Without
    # this half, "warn always" would pass the test above and be worse than the
    # defect: a real install answered with a warning teaches the owner to ignore
    # warnings.
    saida_falante="$(roda_script "$TMPROOT/falante.sh" falante)"
    case "$saida_falante" in
        *"said nothing"*) fail "an installer that printed something is still called a success" \
                               "no warning" "the warning fired anyway" ;;
        *"Installing FooApp"*) pass "an installer that printed something is still called a success" ;;
        *) fail "an installer that printed something is still called a success" \
                "its own words" "$saida_falante" ;;
    esac
    # The heading "this is what it said" has to be followed by what the SCRIPT
    # said. It used to read the whole log, so it showed Tandem's own internal
    # lines - in Portuguese - and that is also why the guard above could never
    # have fired: a log carrying Tandem's lines is never empty.
    case "$saida_falante" in
        *reconhecido*|*"como script comum"*)
            fail "the script's words are its own, not Tandem's log" \
                 "only the script's output" "Tandem's log lines were shown" ;;
        *) pass "the script's words are its own, not Tandem's log" ;;
    esac
else
    skip "the shell-installer verdict" "no script(1) to make a terminal with"
fi

# tandem-flatpak asks flatpak whether the program is there, rather than trusting
# the exit code - the same rule tandem-deb applies to dpkg. It had the check and
# used it as a fallback to the code, which is the opposite.
if grep -q 'INSTALOU=1' "$ROOT/src/bin/tandem-flatpak" &&
   ! grep -q 'CODIGO" -eq 0 \] || {' "$ROOT/src/bin/tandem-flatpak"; then
    pass "tandem-flatpak decides on flatpak's answer, not on the exit code"
else
    fail "tandem-flatpak decides on flatpak's answer, not on the exit code" \
         "the authority decides" "the exit code is still enough on its own"
fi
# An error message followed by exit 0 tells the desktop the double click worked.
if grep -q 'CODIGO" -eq 0 \] && CODIGO=1' "$ROOT/src/bin/tandem-flatpak"; then
    pass "and a 0 with the program absent becomes a failure code"
else
    fail "and a 0 with the program absent becomes a failure code" \
         "CODIGO forced to 1" "it would exit 0 after an error"
fi

# Every format Tandem DOES claim needs a handler, and every handler it ships
# needs to be reachable. A .desktop naming a type with no binary behind it is an
# association that opens nothing.
for d in "$ROOT"/src/applications/tandem-*.desktop; do
    exe="$(sed -n 's/^Exec=//p' "$d" | head -1 | awk '{print $1}')"
    base="$(basename -- "$exe")"
    if [ -f "$ROOT/src/bin/$base" ]; then
        pass "$(basename -- "$d") points at a binary that exists"
    else
        fail "$(basename -- "$d") points at a binary that exists" "src/bin/$base" "missing"
    fi
done

section "native packages: every handler, every path, with nobody to ask"

# The rule this section exists for: a refusal because the OWNER said no may be
# silent; a refusal because THERE WAS NOBODY TO ASK may not. t_pergunta cannot
# tell them apart, so every handler has to check t_tem_gui - and one of them did
# not. A .flatpakrepo with no graphical session and no terminal exited 0 with
# ZERO BYTES of output, which is the defect this project treats as the worst
# kind. It was found by running exactly this, and nothing else would have.
CASA_P="$TMPROOT/casa-pacotes"; mkdir -p "$CASA_P"
: > "$CASA_P/.primeira-vez"
sem_ninguem() {
    env -i HOME="$CASA_P" PATH="/usr/bin:/bin" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ROOT/src/bin" \
        timeout 120 bash "$ROOT/src/bin/$1" "$2" 2>&1
}
cat > "$TMPROOT/loja.flatpakrepo" <<'FIMREPO'
[Flatpak Repo]
Title=Flathub
Url=https://dl.flathub.org/repo/
FIMREPO
for caso in \
    "tandem-deb|$DEBS/velho.deb" \
    "tandem-deb|$DEBS/arm.deb" \
    "tandem-deb|$DEBS/cortado.deb" \
    "tandem-deb|$DEBS/texto.deb" \
    "tandem-deb|$TMPROOT/nao-existe.deb" \
    "tandem-rpm|$TMPROOT/teste.rpm" \
    "tandem-rpm|$TMPROOT/curto.rpm" \
    "tandem-rpm|$TMPROOT/nao-existe.rpm" \
    "tandem-flatpak|$TMPROOT/prog.flatpakref" \
    "tandem-flatpak|$TMPROOT/loja.flatpakrepo" \
    "tandem-flatpak|$DEBS/texto.deb" \
    "tandem-flatpak|$TMPROOT/nao-existe.flatpakref" \
    "tandem-snap|$TMPROOT/pequeno.sh" \
    "tandem-snap|$TMPROOT/nao-existe.snap" \
    "tandem-script|$TMPROOT/pequeno.sh" \
    "tandem-script|$TMPROOT/makeself.sh" \
    "tandem-script|$TMPROOT/nao-existe.sh" \
    ; do
    bin="${caso%%|*}"; alvo="${caso#*|}"
    dito="$(sem_ninguem "$bin" "$alvo")"
    if [ -n "$dito" ]; then
        pass "$bin says something about $(basename -- "$alvo")"
    else
        fail "$bin says something about $(basename -- "$alvo")" \
             "uma frase em português" "zero bytes"
    fi
done

section "community list (modelled on filter lists)"

PROG_L="$ARTIFACTS/prog64.exe"
ID_L="$(t_memoria_id "$PROG_L")"
export TANDEM_LISTA="$TMPROOT/lista.tsv"

# With no list downloaded there is nothing to query - and that is not an error.
rm -f "$TANDEM_LISTA"
equal "with no list downloaded, the query stays quiet" "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022,dotnet48\t-\tconfirmado\t340\t2026-08\t-\n' "$ID_L"
  printf 'aaaa\t64\tvcrun2010\t-\tso-abriu\t2\t2026-07\t-\n'
} > "$TANDEM_LISTA"
equal "finds the program by the file's fingerprint" \
      "vcrun2022 dotnet48" "$(t_lista_consulta "$PROG_L")"
equal "the machine count comes along" "340" "$(t_lista_maquinas "$ID_L")"

# A lesson with nobody confirming it is NOT spread. Spreading a mistake is
# easier than spreading a correct answer: errors take no work to produce.
{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022\t-\tso-abriu\t9\t2026-08\t-\n' "$ID_L"
} > "$TANDEM_LISTA"
equal "an unconfirmed lesson is not suggested" "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

# ------------------------------------------------------------------
# Several rows about the SAME file. This is the normal shape of a merged list,
# and the first version of the query answered with the first row it happened to
# read - so the earliest report owned that program for ever. Each of the four
# cases below was measured failing against that version before this was written.
lista_com() { { printf '# TANDEM-LISTA 1\n'; cat; } > "$TANDEM_LISTA"; }

# 3 machines got in first; 400 agree on something else.
lista_com <<L
$ID_L	64	vcrun2010	-	confirmado	3	2026-06	-
$ID_L	64	vcrun2022	-	confirmado	400	2026-08	-
L
equal "the earliest row does not own the program for ever" \
      "vcrun2022" "$(t_lista_consulta "$PROG_L")"

# Merging reports is the entire job of the machine count.
lista_com <<L
$ID_L	64	vcrun2022	-	confirmado	200	2026-07	-
$ID_L	64	vcrun2022	-	confirmado	200	2026-08	-
$ID_L	64	dotnet48	-	confirmado	300	2026-08	-
L
equal "two rows with the same verbs add up" "400" "$(t_lista_maquinas "$ID_L")"
equal "and adding up changes which lesson wins" \
      "vcrun2022" "$(t_lista_consulta "$PROG_L")"

# The count shown to the owner has to describe the lesson he is being offered.
# Here the rejected row is FIRST, and the old machine count came from it.
lista_com <<L
$ID_L	64	vcrun6	-	reprovado	7	2026-08	-
$ID_L	64	vcrun2022	-	confirmado	40	2026-08	-
L
equal "the machine count comes from the row the verbs came from" \
      "40" "$(t_lista_maquinas "$ID_L")"

# 300 machines say those verbs do not fix it and 2 say they do. Spreading the
# 2 is spreading an error with a receipt on it.
lista_com <<L
$ID_L	64	vcrun2022	-	confirmado	2	2026-08	-
$ID_L	64	vcrun2022	-	reprovado	300	2026-08	-
$ID_L	64	dotnet48	-	confirmado	1	2026-05	-
L
equal "a lesson most machines rejected is not suggested" \
      "dotnet48" "$(t_lista_consulta "$PROG_L")"

# Nothing left standing is silence, not a wrong answer.
lista_com <<L
$ID_L	64	vcrun2022	-	reprovado	300	2026-08	-
L
equal "with every lesson rejected the query stays quiet" \
      "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"
equal "and the machine count refuses too" \
      "1" "$(t_lista_maquinas "$ID_L" >/dev/null 2>&1; echo $?)"

# Two lessons the same number of machines confirm on the same date: the answer
# still cannot depend on the order of the file.
lista_com <<L
$ID_L	64	dotnet48,vcrun2022	-	confirmado	5	2026-08	-
$ID_L	64	vcrun2022	-	confirmado	5	2026-08	-
L
equal "a tie is broken by the cheaper lesson, not by the file order" \
      "vcrun2022" "$(t_lista_consulta "$PROG_L")"

# A record straight off one machine has not been merged and carries no count.
lista_com <<L
$ID_L	64	vcrun2022	-	confirmado	-	2026-08	-
L
equal "an unmerged record counts as the one machine it is" \
      "1" "$(t_lista_maquinas "$ID_L")"

# Another file's rows are not this file's evidence.
lista_com <<L
outro	64	mfc42	-	confirmado	900	2026-08	-
$ID_L	64	vcrun2022	-	confirmado	4	2026-08	-
L
equal "rows about another file are not mixed in" \
      "4" "$(t_lista_maquinas "$ID_L")"

# The record that leaves this machine.
t_memoria_esquece "$PROG_L" 2>/dev/null
t_memoria_grava "$PROG_L" ARQUITETURA 64
t_memoria_junta "$PROG_L" RESOLVERAM vcrun2022
t_memoria_grava "$PROG_L" CONFIRMADO sim
REG_L="$(t_lista_registro "$PROG_L")"
equal "the record has the format's eight fields" \
      "8" "$(printf '%s' "$REG_L" | awk -F'\t' '{print NF}')"
case "$REG_L" in
    "$ID_L"*) pass "the record starts with the file identity" ;;
    *) fail "the record starts with the file identity" "$ID_L..." "$REG_L" ;;
esac
case "$REG_L" in
    *confirmado*) pass "the record carries where the confidence came from" ;;
    *) fail "the record carries where the confidence came from" "confirmado" "$REG_L" ;;
esac
# What must NEVER leave: path, user, machine, IP, day of the month.
case "$REG_L" in
    */*) fail "the record carries no path at all" "no slash" "$REG_L" ;;
    *) pass "the record carries no path at all" ;;
esac
case "$REG_L" in
    *"$(id -un)"*) fail "the record does not carry the user name" "no user" "$REG_L" ;;
    *) pass "the record does not carry the user name" ;;
esac
case "$REG_L" in
    *"$(date +%Y-%m-%d)"*) fail "the date has no day" "year-month only" "$REG_L" ;;
    *) pass "the date has no day" ;;
esac
# And the guard works even if someone breaks the generator in the future.
equal "the guard blocks a record with a path" \
      "0" "$(t_lista_vaza "abc	64	/home/alguem/x	-	confirmado	1	2026-08	-"; echo $?)"
equal "the guard blocks a record with an IP" \
      "0" "$(t_lista_vaza "abc	64	vcrun2022	-	confirmado	1	2026-08	192.168.0.7"; echo $?)"
equal "the guard lets a clean record through" \
      "1" "$(t_lista_vaza "$REG_L"; echo $?)"

# The format document promises that every verb coming from outside is validated
# before becoming a command argument. The memory/list shortcut wrote a receipt
# and called winetricks without going through any validation at all - the recipe
# validated, the list did not.
equal "a verb with an unexpected character is refused" \
      "1" "$(t_verbo_valido 'vcrun2022; rm -rf /'; echo $?)"
equal "a verb with a slash is refused" "1" "$(t_verbo_valido '../../etc/passwd'; echo $?)"
equal "an ordinary verb passes" "0" "$(t_verbo_valido vcrun2022; echo $?)"
# t_verbo_de_fora_ok, not t_verbo_valido: the list is third-party content and
# has to clear the stricter bar - no winetricks options, no *.verb file to
# source, and nothing that changes a setting instead of installing something.
case "$(grep -c 't_verbo_de_fora_ok' "$ROOT/src/bin/tandem-exe")" in
    0) fail "the list shortcut validates the verb before using it" "t_verbo_de_fora_ok" "missing" ;;
    *) pass "the list shortcut validates the verb before using it" ;;
esac
# And proof of delivery applies to that shortcut too: it was the only path that
# wrote a receipt based on the exit code alone.
case "$(grep -c 't_dll_no_prefixo' "$ROOT/src/bin/tandem-exe")" in
    0|1) fail "proof of delivery also covers the memory shortcut" \
                "two uses of t_dll_no_prefixo" "fewer than that" ;;
    *) pass "proof of delivery also covers the memory shortcut" ;;
esac

# A program with no lesson at all must not become noise in other people's list.
t_memoria_esquece "$PROG_L" 2>/dev/null
t_lista_registro "$PROG_L" >/dev/null 2>&1
equal "with no lesson, there is nothing to contribute" "1" "$?"

# A file that does not declare itself a list must NOT replace the good one
# already on disk. A broken list would silence the second opinion without anyone
# noticing - and "stopped suggesting" is the kind of defect nobody spots.
printf '# TANDEM-LISTA 1\nboa\t64\tx\t-\tconfirmado\t1\t2026-08\t-\n' > "$TANDEM_LISTA"
printf 'nao sou uma lista do Tandem\n' > "$TMPROOT/intruso.txt"
if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    TANDEM_LISTA_URL="file://$TMPROOT/intruso.txt" t_lista_atualiza >/dev/null 2>&1
    equal "a file without a valid header is refused" "3" "$?"
    equal "  and the good list stays on disk" "1" "$(grep -c '^boa' "$TANDEM_LISTA")"
    equal "  without letting the intruder in" "0" "$(grep -c 'nao sou uma lista' "$TANDEM_LISTA")"
    # And the happy path: a well-formed file does replace it.
    printf '# TANDEM-LISTA 1\nnova\t64\ty\t-\tconfirmado\t5\t2026-08\t-\n' > "$TMPROOT/boa.tsv"
    TANDEM_LISTA_URL="file://$TMPROOT/boa.tsv" t_lista_atualiza >/dev/null 2>&1
    equal "a well-formed file replaces it" "1" "$(grep -c '^nova' "$TANDEM_LISTA")"
else
    skip "list update" "no curl and no wget"
fi
unset TANDEM_LISTA

section "sending: off until the owner says otherwise"

# Everything about this is security-sensitive, so it gets the same treatment as
# the recipe sieve: the default, the refusal path, the filter at send time, the
# rate limit, and what actually goes over the wire.
CASA_E="$TMPROOT/casa-envio"; mkdir -p "$CASA_E/.config/tandem"
env_envio() {
    env HOME="$CASA_E" TANDEM_LISTA_ENVIO="${TANDEM_LISTA_ENVIO_TESTE:-}" \
        TANDEM_FILA="$CASA_E/fila.tsv" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; '"$1" 2>/dev/null
}

# Reversed in 4.1: born ON, with the owner told at install and again on first
# use. The previous default was off and the measurable consequence was an empty
# list - a default nobody changes is a decision made by the default.
equal "out of the box, sending is ON" "0" "$(env_envio 't_envio_ligado; echo $?')"
equal "and \"nobody decided\" is not the same as \"decided no\"" \
      "1" "$(env_envio 't_envio_decidido; echo $?')"
env_envio 't_envio_define nao' >/dev/null
equal "a recorded no reads as decided" "0" "$(env_envio 't_envio_decidido; echo $?')"
equal "and still off" "1" "$(env_envio 't_envio_ligado; echo $?')"
env_envio 't_envio_define sim' >/dev/null
equal "a recorded yes reads as on" "0" "$(env_envio 't_envio_ligado; echo $?')"
equal "the date of the decision is kept" "$(date +%F)" \
      "$(env_envio 't_config_le ENVIAR_DESDE')"
equal "and which version asked" "$(grep '^TANDEM_VERSAO=' "$ROOT/src/lib/common.sh" | cut -d'"' -f2)" \
      "$(env_envio 't_config_le ENVIAR_VERSAO')"

# The queue. A record is stored, never sent from the queueing path, and the same
# lesson twice is one lesson.
REG_BOM="$(printf 'abc123\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t-')"
env_envio "t_envio_enfileira \"\$(printf 'abc123\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t-')\"" >/dev/null
env_envio "t_envio_enfileira \"\$(printf 'abc123\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t-')\"" >/dev/null
# Same trap as the product had: grep -c on an empty file prints 0 AND exits 1.
linhas_de() { [ -f "$1" ] && awk 'END { print NR + 0 }' "$1" || echo 0; }
equal "the same record twice is stored once" "1" "$(linhas_de "$CASA_E/fila.tsv")"

# The sieve, at the moment of queueing. Anything carrying a path, the home
# folder, the username, the machine name or an IP address is refused - and it is
# refused HERE rather than being caught later, so it never reaches the file.
for veneno in \
    "$(printf 'abc\t64\t/home/dono/nota.exe\t-\tconfirmado\t1\t2026-08\t-')" \
    "$(printf 'abc\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t192.168.0.15')" \
    ; do
    antes="$(linhas_de "$CASA_E/fila.tsv")"
    env_envio "t_envio_enfileira \"$veneno\"" >/dev/null 2>&1
    depois="$(linhas_de "$CASA_E/fila.tsv")"
    if [ "$antes" = "$depois" ]; then
        pass "a record carrying machine data never reaches the queue"
    else
        fail "a record carrying machine data never reaches the queue" \
             "refused" "it was stored"
    fi
done

# With the address explicitly emptied, nothing goes anywhere even switched on.
# This USED to be the shipped state; since 4.6 the shipped state is an address,
# and an empty TANDEM_LISTA_ENVIO is the opt-out-by-environment path - which
# only stays empty because the default uses "${VAR-...}" and not "${VAR:-...}".
# env_envio sets the variable to empty, so this is exactly that path.
equal "an explicitly empty address sends nothing and keeps the queue" "" \
      "$(env_envio 't_envio_envia')"
# The count the owner is shown has to be a number, not two of them.
: > "$CASA_E/vazia.tsv"
equal "an empty queue counts as one zero, not two" "0" \
      "$(env HOME="$CASA_E" TANDEM_FILA="$CASA_E/vazia.tsv" \
         bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_envio_pendentes')"
equal "the queue survives having nowhere to go" "1" "$(linhas_de "$CASA_E/fila.tsv")"

# And now over the wire, against a listener that records exactly what arrives.
# A test that only checks the shell logic would never catch the line being
# mangled between the queue and the socket.
if command -v python3 >/dev/null 2>&1; then
    RECEBIDO="$TMPROOT/recebido.txt"
    : > "$RECEBIDO"
    # The server picks its own free port and writes it down. Choosing one here
    # from $$ picks a port that may be taken, and the first version of this test
    # skipped itself for exactly that reason - a test that skips is a test that
    # proves nothing while looking tidy.
    # The answer code is an argument, because the interesting answers are not
    # the successful one. Every request is recorded whatever the code, so a
    # test can ask "how many times did it actually try" - which is the only way
    # to see a retry loop from outside.
    cat > "$TMPROOT/servidor.py" <<'PYSERV'
import http.server, sys
destino, porta_arq = sys.argv[1], sys.argv[2]
codigo = int(sys.argv[3]) if len(sys.argv) > 3 else 204
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length') or 0)
        with open(destino, 'ab') as f:
            f.write(self.rfile.read(n) + b'\n')
        self.send_response(codigo)
        if 300 <= codigo < 400:
            self.send_header('Location', 'http://127.0.0.1:1/outro')
        self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
with open(porta_arq, 'w') as f:
    f.write(str(s.server_address[1]))
s.serve_forever()
PYSERV
    # Prints the port once the socket really answers. Waiting for the FILE is
    # not enough: it is written before serve_forever and a connection to a
    # socket nobody is accepting on hangs instead of failing.
    sobe_servidor() {
        local destino="$1" codigo="${2:-204}" arq porta=""
        arq="$TMPROOT/porta-$codigo.txt"; : > "$arq"
        python3 "$TMPROOT/servidor.py" "$destino" "$arq" "$codigo" >/dev/null 2>&1 &
        SERVIDOR=$!
        for _ in $(seq 1 50); do
            porta="$(cat "$arq" 2>/dev/null)"
            [ -n "$porta" ] && (exec 3<>/dev/tcp/127.0.0.1/"$porta") 2>/dev/null &&
                { exec 3>&-; break; }
            porta=""
            command -v sleep >/dev/null 2>&1 && sleep 0.1
        done
        printf '%s' "$porta"
    }
    PORTA="$(sobe_servidor "$RECEBIDO" 204)"
    if [ -n "$PORTA" ]; then
        enviados="$(TANDEM_LISTA_ENVIO_TESTE="http://127.0.0.1:$PORTA/" \
                    env_envio 't_envio_envia')"
        equal "one queued record is sent" "1" "${enviados:-0}"
        equal "and the queue is empty afterwards" "0" "$(linhas_de "$CASA_E/fila.tsv")"
        # The bytes that arrived have to be the record, and nothing else.
        equal "what arrived is exactly the record, byte for byte" \
              "$REG_BOM" "$(head -1 "$RECEBIDO" 2>/dev/null)"
        # The rate limit: a machine cannot be turned into a firehose.
        # Five DISTINCT records. The first version of this passed the counter as
        # an extra argument to bash -c, where it became $0 instead of feeding the
        # printf, so all five came out identical and the de-duplication stored
        # one - and then the ceiling had nothing to hold back. The test measured
        # its own bug.
        for i in a b c d e; do
            env_envio "t_envio_enfileira \"\$(printf 'lim$i\t64\tv\t-\tconfirmado\t1\t2026-08\t-')\"" >/dev/null
        done
        equal "five distinct records are five queue lines" "5" "$(linhas_de "$CASA_E/fila.tsv")"
        n2="$(TANDEM_LISTA_ENVIO_TESTE="http://127.0.0.1:$PORTA/" TANDEM_ENVIO_POR_DIA=2 \
              env_envio 't_envio_envia')"
        if [ "${n2:-0}" -le 2 ]; then
            pass "the daily ceiling is respected (sent ${n2:-0} with a limit of 2)"
        else
            fail "the daily ceiling is respected" "at most 2" "${n2:-0}"
        fi
        if [ "$(linhas_de "$CASA_E/fila.tsv")" -gt 0 ]; then
            pass "what the ceiling held back stays in the queue"
        else
            fail "what the ceiling held back stays in the queue" "kept" "dropped"
        fi
    else
        skip "sending over the wire" "could not open a local listener"
    fi
    kill "$SERVIDOR" 2>/dev/null; wait "$SERVIDOR" 2>/dev/null

    # ------------------------------------------------------------------
    # The answers that are NOT a success, which is where the losses were. A
    # queue line is the only copy of a lesson that has not left yet, so an
    # answer read as "delivered" when it was not deletes it.
    CASA_E3="$TMPROOT/casa-envio-3"; mkdir -p "$CASA_E3"
    env_envio3() {
        env HOME="$CASA_E3" TANDEM_LISTA_ENVIO="${TANDEM_LISTA_ENVIO_TESTE:-}" \
            TANDEM_FILA="$CASA_E3/fila.tsv" \
            bash -c '. "'"$ROOT"'/src/lib/common.sh"; '"$1" 2>/dev/null
    }
    RECEBIDO_3="$TMPROOT/recebido-302.txt"; : > "$RECEBIDO_3"
    PORTA_3="$(sobe_servidor "$RECEBIDO_3" 302)"
    if [ -n "$PORTA_3" ]; then
        ALVO_3="http://127.0.0.1:$PORTA_3/"
        env_envio3 "t_envio_enfileira \"$REG_BOM\"" >/dev/null
        # curl with no -L exits 0 on a 301, so this used to count as sent - and
        # the queue is rewritten from what did NOT go.
        equal "a redirect is not a delivery" "0" \
              "$(TANDEM_LISTA_ENVIO_TESTE="$ALVO_3" env_envio3 't_envio_envia')"
        equal "the line a redirect refused stays in the queue" "1" \
              "$(linhas_de "$CASA_E3/fila.tsv")"
        equal "and it really did try, exactly once" "1" "$(linhas_de "$RECEBIDO_3")"

        # Six more lines and a server that refuses all of them: the pass has to
        # stop, not spend twenty seconds of timeout on every one of them, on
        # every double click, for ever.
        for i in a b c d e f; do
            env_envio3 "t_envio_enfileira \"\$(printf 'cap$i\t64\tv\t-\tconfirmado\t1\t2026-08\t-')\"" >/dev/null
        done
        : > "$RECEBIDO_3"
        env_envio3 't_config_grava ENVIO_ESPERA_ATE 0' >/dev/null
        TANDEM_LISTA_ENVIO_TESTE="$ALVO_3" TANDEM_ENVIO_FALHAS=2 \
            env_envio3 't_envio_envia' >/dev/null
        equal "after two refusals in a row the pass gives up" "2" "$(linhas_de "$RECEBIDO_3")"
        equal "and every line is still there" "7" "$(linhas_de "$CASA_E3/fila.tsv")"

        # And it waits before trying again, instead of retrying on the next
        # double click.
        : > "$RECEBIDO_3"
        equal "a queue that just failed does not try again straight away" "" \
              "$(TANDEM_LISTA_ENVIO_TESTE="$ALVO_3" env_envio3 't_envio_envia')"
        equal "nothing reached the server during the wait" "0" "$(linhas_de "$RECEBIDO_3")"
        equal "and the queue is intact" "7" "$(linhas_de "$CASA_E3/fila.tsv")"

        # The reason travels in the exit status, because the count travels on
        # stdout and the caller reads that through a subshell.
        env_envio3 't_config_grava ENVIO_ESPERA_ATE 0' >/dev/null
        equal "a pass the server refused says so in its exit status" "3" \
              "$(TANDEM_LISTA_ENVIO_TESTE="$ALVO_3" TANDEM_ENVIO_FALHAS=1 \
                 env_envio3 't_envio_envia >/dev/null; echo $?')"
        equal "and being inside the wait is a different status" "4" \
              "$(TANDEM_LISTA_ENVIO_TESTE="$ALVO_3" env_envio3 't_envio_envia >/dev/null; echo $?')"

        # An owner who typed "tandem enviar agora" has asked. The wait exists to
        # stop AUTOMATIC retries on every double click, not to answer a direct
        # request with an hour of silence.
        : > "$RECEBIDO_3"
        TANDEM_LISTA_ENVIO_TESTE="$ALVO_3" TANDEM_ENVIO_FALHAS=1 \
            env_envio3 't_envio_envia forcado' >/dev/null
        if [ "$(linhas_de "$RECEBIDO_3")" -ge 1 ]; then
            pass "asking for it explicitly gets through the wait"
        else
            fail "asking for it explicitly gets through the wait" "it tried" "it waited"
        fi

        # And the whole command, with nobody to show a window to. A refusal by
        # the far end used to reach the owner as "0 line(s) sent", which reads
        # as a defect on this computer.
        SAIDA_ENV="$(env -i HOME="$CASA_E3" PATH="/usr/bin:/bin" \
            TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ROOT/src/bin" \
            TANDEM_FILA="$CASA_E3/fila.tsv" TANDEM_LISTA_ENVIO="$ALVO_3" \
            TANDEM_IDIOMA_FORCADO=en TANDEM_ENVIO_FALHAS=1 \
            timeout 60 bash "$ROOT/src/bin/tandem" enviar agora 2>&1)"
        case "$SAIDA_ENV" in
            *"did not accept"*) pass "tandem enviar agora explains a refusal by the far end" ;;
            *) fail "tandem enviar agora explains a refusal by the far end" \
                    "a sentence about the server" "$SAIDA_ENV" ;;
        esac

        # A 4xx is the far end saying this LINE is wrong, and it will say the
        # same thing for ever. Before this, any non-2xx kept the line and
        # counted a failure - so three permanently refused lines would trip the
        # hour-long wait and stop the GOOD lines from leaving. One malformed
        # record would poison the whole queue.
        RECEBIDO_4="$TMPROOT/recebido-400.txt"; : > "$RECEBIDO_4"
        PORTA_4="$(sobe_servidor "$RECEBIDO_4" 400)"
        if [ -n "$PORTA_4" ]; then
            CASA_E4="$TMPROOT/casa-envio-4"; rm -rf "$CASA_E4"; mkdir -p "$CASA_E4"
            env_envio4() {
                env HOME="$CASA_E4" TANDEM_LISTA_ENVIO="${TANDEM_LISTA_ENVIO_TESTE:-}" \
                    TANDEM_FILA="$CASA_E4/fila.tsv" \
                    bash -c '. "'"$ROOT"'/src/lib/common.sh"; '"$1" 2>/dev/null
            }
            for i in a b c; do
                env_envio4 "t_envio_enfileira \"\$(printf 'ruim$i\t64\tv\t-\tconfirmado\t1\t2026-08\t-')\"" >/dev/null
            done
            TANDEM_LISTA_ENVIO_TESTE="http://127.0.0.1:$PORTA_4/" \
                env_envio4 't_envio_envia' >/dev/null
            equal "a line the far end refused for good leaves the queue" "0" \
                  "$(linhas_de "$CASA_E4/fila.tsv")"
            # Parked, not destroyed. Stopping a line from leaving is a different
            # power from being allowed to delete it.
            equal "and it is parked where somebody can still read it" "3" \
                  "$(linhas_de "$CASA_E4/fila.tsv.recusados")"
            # And a permanent refusal is not a failure OF THE ROUTE, so it must
            # not trip the wait that exists for a broken network.
            # Never written at all is the right answer here, and it reads as
            # empty rather than as "0" - which is what the first version of
            # this assertion expected, and it was the assertion that was wrong.
            espera_4="$(env_envio4 't_config_le ENVIO_ESPERA_ATE' | tr -d '\n')"
            equal "a refused line does not start the hour-long wait" "sem espera" \
                  "$(case "${espera_4:-0}" in 0) echo "sem espera" ;; *) echo "$espera_4" ;; esac)"
        else
            skip "a line refused for good" "could not open a local listener"
        fi

        # Two passes at once. Sending is spawned detached every time a program
        # is confirmed and "tandem enviar agora" starts one too, so this is the
        # ordinary case, not a corner. Both truncated the same ".resto" file and
        # both then moved it over the queue: the truncation lands in the middle
        # of the other pass's appends and the lines already written are gone.
        if command -v flock >/dev/null 2>&1; then
            TRAVAS_E3="$(env_envio3 'printf %s "$TANDEM_TRAVAS"')"
            SEGURA="$TMPROOT/segura-envio"; SINAL="$TMPROOT/sinal-envio"
            : > "$SEGURA"; rm -f "$SINAL"
            ( exec 6> "$TRAVAS_E3/envio.lock"
              flock 6 && printf ok > "$SINAL"
              for _ in $(seq 1 100); do [ -f "$SEGURA" ] || break; sleep 0.1; done ) &
            GUARDA=$!
            for _ in $(seq 1 50); do [ -f "$SINAL" ] && break; sleep 0.1; done
            env_envio3 't_config_grava ENVIO_ESPERA_ATE 0' >/dev/null
            : > "$RECEBIDO_3"
            if [ -f "$SINAL" ]; then
                equal "with a pass already running, a second one does not start" "" \
                      "$(TANDEM_LISTA_ENVIO_TESTE="$ALVO_3" env_envio3 't_envio_envia')"
                equal "and the second pass touched nothing at all" "0" \
                      "$(linhas_de "$RECEBIDO_3")"
                equal "the queue is exactly as the first pass left it" "7" \
                      "$(linhas_de "$CASA_E3/fila.tsv")"
            else
                skip "two sends at once" "could not take the lock to hold it"
            fi
            rm -f "$SEGURA"; wait "$GUARDA" 2>/dev/null
        else
            skip "two sends at once" "no flock"
        fi
    else
        skip "the answers that are not a success" "could not open a local listener"
    fi
    kill "$SERVIDOR" 2>/dev/null; wait "$SERVIDOR" 2>/dev/null
else
    skip "sending over the wire" "no python3"
fi

# The offer, with nobody to ask. It must neither send nor RECORD A DECISION: the
# owner has not decided anything, and writing "nao" would answer for him and
# never ask again.
CASA_E2="$TMPROOT/casa-envio-2"; mkdir -p "$CASA_E2"
PROG_E="$ARTIFACTS/prog64.exe"
env HOME="$CASA_E2" TANDEM_MEMORIA="$CASA_E2/mem" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    t_memoria_grava "'"$PROG_E"'" RESOLVERAM vcrun2022
    t_memoria_grava "'"$PROG_E"'" CONFIRMADO sim
    t_envio_oferece "'"$PROG_E"'"' >/dev/null 2>&1
if [ -f "$CASA_E2/.config/tandem/configuracao.txt" ] &&
   grep -q '^ENVIAR=' "$CASA_E2/.config/tandem/configuracao.txt" 2>/dev/null; then
    fail "with nobody to ask, no decision is recorded" \
         "no ENVIAR= line" "$(grep '^ENVIAR=' "$CASA_E2/.config/tandem/configuracao.txt")"
else
    pass "with nobody to ask, nothing is sent and no decision is recorded"
fi

# The URL escaper, which puts a TAB-separated record into a prefilled form.
equal "a tab becomes %09, so the record survives a URL" "a%09b" "$(t_url_escapa "$(printf 'a\tb')")"
equal "a space becomes %20" "a%20b" "$(t_url_escapa 'a b')"
equal "letters, digits, dash and underscore are left alone" "Ab9-_" "$(t_url_escapa 'Ab9-_')"

section "silent success: exiting 0 is not the same as having worked"

equal "an instant exit is suspicious" "0" "$(t_saida_suspeita 1; echo $?)"
equal "a program that stayed open is not suspicious" "1" "$(t_saida_suspeita 40; echo $?)"

PROG_S="$ARTIFACTS/prog64.exe"
t_memoria_esquece "$PROG_S" 2>/dev/null
equal "with no answer from the owner, the lesson is worth less" \
      "so-abriu" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_grava "$PROG_S" CONFIRMADO sim
equal "with the owner confirming, the lesson is worth more" \
      "confirmado" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_grava "$PROG_S" CONFIRMADO nao
equal "with the owner rejecting, the lesson is marked as rejected" \
      "reprovado" "$(t_confianca_da_licao "$PROG_S")"

# The recipe has to carry where the confidence came from. Without this line,
# "the process exited 0" and "a person looked at the screen" arrived on the
# other side with exactly the same weight - and the second person had no way
# to tell.
case "$(t_receita_exporta "$PROG_S")" in
    *"CONFIANCA=reprovado"*) pass "the recipe comes out marked with the confidence" ;;
    *) fail "the recipe comes out marked with the confidence" "CONFIANCA=reprovado" \
              "$(t_receita_exporta "$PROG_S" | head -8)" ;;
esac

# Without a window there is no way to ask - and making up an answer would be
# worse than having no answer at all.
t_memoria_esquece "$PROG_S" 2>/dev/null
( unset DISPLAY WAYLAND_DISPLAY; t_confirma_funcionou "$PROG_S" 30 ) >/dev/null 2>&1
equal "without a window, it does not invent a confirmation" \
      "so-abriu" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_esquece "$PROG_S" 2>/dev/null

section "bitness: arriving is not arriving where this program looks"

# A win64 prefix the way Wine builds it: system32 holds the 64-bit DLLs and
# syswow64 the 32-bit ones. This test exists because the first run of the loop
# with a REAL winetricks ended like this: the mfc42 verb exited 0, delivered the
# file into syswow64, proof of delivery looked at both folders, approved, and
# the 64-bit program still found nothing.
PB="$TMPROOT/pref64"
mkdir -p "$PB/drive_c/windows/system32" "$PB/drive_c/windows/syswow64"
(
  export WINEPREFIX="$PB"
  : > "$PB/drive_c/windows/syswow64/mfc42.dll"       # 32-bit only
  : > "$PB/drive_c/windows/system32/msvcp140.dll"    # 64-bit only
  : > "$PB/drive_c/windows/syswow64/gdiplus.dll"     # both
  : > "$PB/drive_c/windows/system32/gdiplus.dll"

  t_dll_no_prefixo mfc42.dll 64;    echo "a $?"
  t_dll_no_prefixo mfc42.dll 32;    echo "b $?"
  t_dll_no_prefixo msvcp140.dll 64; echo "c $?"
  t_dll_no_prefixo msvcp140.dll 32; echo "d $?"
  t_dll_no_prefixo gdiplus.dll 64;  echo "e $?"
  t_dll_no_prefixo sumiu.dll 64;    echo "f $?"
  t_dll_no_prefixo mfc42.dll "";    echo "g $?"
) > "$TMPROOT/bit.txt"
equal "64-bit program, DLL only in syswow64: wrong bitness" \
      "2" "$(awk '$1=="a"{print $2}' "$TMPROOT/bit.txt")"
equal "32-bit program, the same DLL does the job" \
      "0" "$(awk '$1=="b"{print $2}' "$TMPROOT/bit.txt")"
equal "64-bit program, DLL in system32: does the job" \
      "0" "$(awk '$1=="c"{print $2}' "$TMPROOT/bit.txt")"
equal "32-bit program, DLL only in system32: wrong bitness" \
      "2" "$(awk '$1=="d"{print $2}' "$TMPROOT/bit.txt")"
equal "a DLL in both folders serves both" \
      "0" "$(awk '$1=="e"{print $2}' "$TMPROOT/bit.txt")"
equal "a missing DLL stays missing" \
      "1" "$(awk '$1=="f"{print $2}' "$TMPROOT/bit.txt")"
# Without knowing the architecture, condemning would be worse than not knowing.
equal "with no known architecture, it does not condemn" \
      "0" "$(awk '$1=="g"{print $2}' "$TMPROOT/bit.txt")"

# win32 prefix: only system32 exists, and it is 32-bit.
PB32="$TMPROOT/pref32"; mkdir -p "$PB32/drive_c/windows/system32"
: > "$PB32/drive_c/windows/system32/mfc42.dll"
equal "32-bit prefix: system32 serves a 32-bit program" \
      "0" "$(WINEPREFIX="$PB32"; export WINEPREFIX; t_dll_no_prefixo mfc42.dll 32; echo $?)"

TXB="$(t_texto_bitola "$(printf 'mfc42.dll\tmfc42')" 64)"
case "$TXB" in
    *"64-bit"*"32-bit"*mfc42.dll*) pass "the message names both bitnesses and the file" ;;
    *) fail "the message names both bitnesses and the file" "64/32/mfc42.dll" "$TXB" ;;
esac
case "$TXB" in
    *"not a fault of your machine"*) pass "the message takes the blame off the owner's machine" ;;
    *) fail "the message takes the blame off the owner's machine" "Não é defeito da sua máquina" "$TXB" ;;
esac

section "a verb from somebody else is not a command line"

# Found by attacking the community list on purpose, and both holes were live
# through "tandem receita --importar" - a plain text file whose own header tells
# the owner to accept it from other people.
#
#   - a leading dash passed, so "--self-update" and "-q" reached
#     "winetricks -q ...". Those are winetricks' own options, and --self-update
#     makes winetricks overwrite itself from the internet.
#   - a dot passed, and the SHIPPED winetricks sources an argument matching
#     *.verb as a shell script, from the current directory:
#       case ${verb} in */*) . "${verb}" ;; *) . ./"${verb}" ;; esac
#     executar() does `cd -- "$(dirname -- "$PROG")"` outside a subshell, so by
#     the time winetricks runs the current directory is the folder that was
#     double-clicked. A zip carrying setup.exe, evil.verb and a recipe naming
#     that verb is arbitrary code, as the user.
#
# Rejecting the dot costs nothing: zero of the installed winetricks' verb names
# contain one.
for mau in "--self-update" "-q" "--force" "evil.verb" "x.verb" "_leading" \
           "a;b" "a b" "../etc/passwd" '$(id)' '`id`' "a|b" "alldlls=builtin"; do
    if (. "$ROOT/src/lib/common.sh"; t_verbo_valido "$mau") 2>/dev/null; then
        fail "a verb name of '$mau' is refused" "refused" "accepted"
    else
        pass "a verb name of '$mau' is refused"
    fi
done
for bom in vcrun2022 dotnet48 corefonts xact_x64 d3dx9_43 9lives; do
    if (. "$ROOT/src/lib/common.sh"; t_verbo_valido "$bom") 2>/dev/null; then
        pass "and a real verb name like '$bom' still passes"
    else
        fail "and a real verb name like '$bom' still passes" "accepted" "refused"
    fi
done

# A lesson from another machine may install a DEPENDENCY. It may never change a
# setting. winetricks labels its own verbs - 315 dlls, 112 settings - and the
# settings are where the damage is: sandbox and isolate_home REMOVE the
# prefix's links to $HOME, remove_mono takes .NET support out, winxp moves the
# Windows version under an installed program's feet. All of them pass every
# validity check, install cleanly, and earn a permanent receipt under rule 4.
for destrutivo in sandbox isolate_home remove_mono forcemono winxp win95 \
                  nocrashdialog set_userpath hosts native_oleaut32; do
    if (. "$ROOT/src/lib/common.sh"; t_verbo_de_fora_ok "$destrutivo") 2>/dev/null; then
        fail "an outside lesson cannot ask for '$destrutivo'" "refused" "accepted"
    else
        pass "an outside lesson cannot ask for '$destrutivo'"
    fi
done
for dep in vcrun2022 dotnet48 corefonts; do
    if (. "$ROOT/src/lib/common.sh"; t_verbo_de_fora_ok "$dep") 2>/dev/null; then
        pass "while a real dependency like '$dep' is still allowed through"
    else
        fail "while a real dependency like '$dep' is still allowed through" \
             "accepted" "refused"
    fi
done
# The authority is winetricks itself, so this keeps working as winetricks
# changes. Without it installed there is a named fallback, and the test says
# which one it exercised rather than pretending it checked the real thing.
if command -v winetricks >/dev/null 2>&1; then
    equal "winetricks itself is what says a verb is a setting" \
          "1" "$(grep -c '^w_metadata sandbox settings' "$(command -v winetricks)")"
else
    skip "winetricks itself is what says a verb is a setting" "winetricks not installed"
fi
# Both entry points have to use the stricter check, not just one of them.
equal "the community-list loop uses the stricter check" \
      "1" "$(grep -c 't_verbo_de_fora_ok' "$ROOT/src/bin/tandem-exe")"
equal "and so does recipe import" \
      "1" "$(grep -c 't_verbo_de_fora_ok' "$ROOT/src/lib/common.sh" | awk '{print ($1>=1)?1:0}')"

section "Wine's own copy is not a delivery"

# Wine puts some 560 DLLs of its own into every prefix and marks each one at
# offset 64, where the DOS stub message would otherwise sit. Measured on a
# fresh win64 prefix: 560 of 560 carry "Wine builtin DLL" at exactly that
# offset. That is the whole reason the proof of delivery could approve the most
# expensive verb in the project on a prefix with no .NET anywhere - verbos.tsv
# maps dotnet48 -> mscoree.dll, and Wine had already put an mscoree.dll in both
# folders. Exit 0 plus a file Wine itself installed read as proof, the receipt
# was written, and under rule number 4 a receipt is permanent.
finge_builtin() {
    mkdir -p "$(dirname -- "$1")"
    { printf 'MZ'; head -c 62 /dev/zero; printf 'Wine builtin DLL'
      head -c 64 /dev/zero; } > "$1"
}
finge_nativa() {
    mkdir -p "$(dirname -- "$1")"
    { printf 'MZ'; head -c 62 /dev/zero; printf 'This program canno'
      head -c 64 /dev/zero; } > "$1"
}

PWB="$TMPROOT/pref-builtin"
mkdir -p "$PWB/drive_c/windows/system32" "$PWB/drive_c/windows/syswow64"
finge_builtin "$PWB/drive_c/windows/system32/mscoree.dll"
finge_builtin "$PWB/drive_c/windows/syswow64/mscoree.dll"
finge_nativa  "$PWB/drive_c/windows/system32/msvcp140.dll"

equal "Wine's own stub is recognised by the marker at offset 64" \
      "0" "$(t_dll_builtin_wine "$PWB/drive_c/windows/system32/mscoree.dll"; echo $?)"
equal "a file that is not one is not mistaken for it" \
      "1" "$(t_dll_builtin_wine "$PWB/drive_c/windows/system32/msvcp140.dll"; echo $?)"
equal "a file that is not there is not a builtin either" \
      "1" "$(t_dll_builtin_wine "$PWB/drive_c/windows/system32/sumiu.dll"; echo $?)"

# The regression test. Both of these used to answer 0 - "delivered" - on a
# prefix where nothing had been delivered at all.
equal "Wine's mscoree.dll does not prove dotnet48 delivered anything" \
      "1" "$(WINEPREFIX="$PWB"; export WINEPREFIX; t_dll_no_prefixo mscoree.dll 64; echo $?)"
equal "and not for a 32-bit program either" \
      "1" "$(WINEPREFIX="$PWB"; export WINEPREFIX; t_dll_no_prefixo mscoree.dll 32; echo $?)"
equal "a library that is not Wine's still counts as delivered" \
      "0" "$(WINEPREFIX="$PWB"; export WINEPREFIX; t_dll_no_prefixo msvcp140.dll 64; echo $?)"
# The pairing that made this reachable: the memory/list shortcut installs a verb
# with no Wine error to check against, so it asks the table which DLL to look
# for. Any DLL that came out of err:module:import_dll cannot be a builtin -
# Wine said it could not find it - which is why this only ever mattered here.
equal "verbos.tsv is what points dotnet48 at mscoree.dll" \
      "mscoree.dll" "$(TANDEM_VERBOS_TSV="$ROOT/src/lib/verbos.tsv" t_dll_do_verbo dotnet48)"

section "how wide is this environment"

# Wine writes "#arch=" on the fourth line of system.reg, and nothing in Tandem
# read it: "grep -rn '#arch' src/ tests/" returned zero hits. A 64-bit program
# in a 32-bit environment is the one failure that is decidable before running
# anything, and it was the one Tandem only ever diagnosed afterwards.
PA="$TMPROOT/arquitetura"
mkdir -p "$PA/w64" "$PA/w32" \
         "$PA/velho64/drive_c/windows/syswow64" \
         "$PA/velho32/drive_c/windows/system32"
printf 'WINE REGISTRY Version 2\n;; all keys relative\n\n#arch=win64\n' > "$PA/w64/system.reg"
printf 'WINE REGISTRY Version 2\n;; all keys relative\n\n#arch=win32\n' > "$PA/w32/system.reg"
# The answer and the evidence for it, together, and captured in that order:
# relying on "$?" beside a command substitution in the same command line reads
# the right value by accident of expansion order, which is not a thing to build
# a test on.
arq_com_codigo() {
    local v c
    v="$(t_prefixo_arquitetura "$1" 2>/dev/null)"; c=$?
    printf '%s %s' "$v" "$c"
}
equal "reads win64 off the fourth line of system.reg" \
      "win64 0" "$(arq_com_codigo "$PA/w64")"
equal "and win32 the same way" \
      "win32 0" "$(arq_com_codigo "$PA/w32")"
# Older Wine did not write that line, and a prefix made years ago on a counter
# machine is exactly the one that would not have it. The layout still answers -
# but it answers with a 2, because a deduction is not a fact and nothing may
# refuse to open a program on the strength of one.
equal "with no #arch line, syswow64 says 64-bit, and says it is a guess" \
      "win64 2" "$(arq_com_codigo "$PA/velho64")"
equal "and only system32 says 32-bit, also a guess" \
      "win32 2" "$(arq_com_codigo "$PA/velho32")"
equal "a folder that is not a prefix answers nothing" \
      " 1" "$(arq_com_codigo "$PA/nao-existe")"

# The guess must NOT be enough to refuse. This fixture is a 64-bit prefix that
# simply has no #arch line - which is also the shape of every synthetic prefix
# in this suite - and a 64-bit program has to run in it.
mkdir -p "$PA/sem_linha/drive_c/windows/system32"
equal "a prefix with no #arch line is not condemned as 32-bit" \
      "2" "$(t_prefixo_arquitetura "$PA/sem_linha" >/dev/null; echo $?)"

# A fake wine, so the two tests below exercise the decision without needing
# Wine installed - and, in the identity case, so the arguments can be read
# back. What that code does wrong cannot be seen from its exit status.
FINGE_W="$TMPROOT/finge-wine"; mkdir -p "$FINGE_W"
cat > "$FINGE_W/wine" <<'FIMW'
#!/bin/sh
[ -n "$T_REG_LOG" ] && printf '%s\n' "$*" >> "$T_REG_LOG"
# T_REG_FALHA names a view this fake refuses, so the partial-write case can be
# exercised. A real "wine reg" fails for ordinary reasons - a busy prefix, a
# full disk, a Wine too old for the /reg: flags - and what Tandem does then is
# the difference between a retry and a machine split in half forever.
if [ -n "$T_REG_FALHA" ]; then
    for a in "$@"; do
        [ "$a" = "/reg:$T_REG_FALHA" ] && exit 1
    done
fi
exit 0
FIMW
chmod +x "$FINGE_W/wine"

CASA_32="$TMPROOT/casa-32bits"; mkdir -p "$CASA_32"
: > "$CASA_32/.primeira-vez"
PREF_ALHEIO="$TMPROOT/prefixo-alheio-32"
mkdir -p "$PREF_ALHEIO/drive_c/Programa"
printf 'WINE REGISTRY Version 2\n;; all keys relative\n\n#arch=win32\n' > "$PREF_ALHEIO/system.reg"
cp "$ARTIFACTS/prog64.exe" "$PREF_ALHEIO/drive_c/Programa/prog64.exe"
SAIDA_32="$(env -i HOME="$CASA_32" PATH="$FINGE_W:/usr/bin:/bin" \
    TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ROOT/src/bin" \
    timeout 120 bash "$ROOT/src/bin/tandem-exe" \
    "$PREF_ALHEIO/drive_c/Programa/prog64.exe" 2>&1)"
C_32=$?
equal "a 64-bit program in a 32-bit environment does not fail in silence" \
      "1" "$([ -n "$SAIDA_32" ] && echo 1 || echo 0)"
contem "it names the width that is the problem" "32-bit" "$SAIDA_32"
contem "and the folder that is the environment" "$PREF_ALHEIO" "$SAIDA_32"
equal "and it refuses instead of pretending it ran" "1" "$C_32"

section "the identity that was never actually written"

# Measured on real Wine 9.0: wineboot writes a RANDOM MachineGuid into the
# 64-bit view while creating the prefix, before Tandem gets a turn. The guard
# was "the registry value is absent", so it was never true and this half never
# once ran - while the mark file recorded MACHINEGUID=<the seed value>, a mark
# describing something the prefix did not contain. Remake the environment and
# the program that tied its licence to this machine sees a different machine:
# exactly the loss the function exists to prevent.
PID_OK="$TMPROOT/pref-identidade"
mkdir -p "$PID_OK/drive_c"
: > "$PID_OK/.tandem-prefixo"
printf 'WINE REGISTRY Version 2\n\n#arch=win64\n\n[Software\\\\Microsoft\\\\Cryptography] 1700000000\n"MachineGuid"="b9ab1485-29b0-43ef-90e4-18db97d1d4e4"\n' \
    > "$PID_OK/system.reg"
REG_LOG="$TMPROOT/reg-chamadas.txt"; : > "$REG_LOG"
( export T_REG_LOG="$REG_LOG"; PATH="$FINGE_W:$PATH"
  t_identidade_fixa "$PID_OK" ) >/dev/null 2>&1
equal "Wine's own MachineGuid no longer stops the freeze from happening" \
      "2" "$(grep -c 'MachineGuid' "$REG_LOG")"
# "wine reg" is a 32-bit process here - Ubuntu's wrapper picks the 32-bit
# loader when wine32 is present, the same reason "wine uninstaller --list"
# reads the other view - so a write with no /reg: flag landed in Wow6432Node
# while the read looked at the 64-bit key. The code wrote the view it did not
# read, and both views have to carry the same machine.
contem "the 64-bit view is asked for by name" "/reg:64" "$(cat "$REG_LOG")"
contem "and so is the 32-bit one, which is what a 32-bit program reads" \
       "/reg:32" "$(cat "$REG_LOG")"
equal "the volume serial went in as well" \
      "1" "$([ -s "$PID_OK/drive_c/.windows-serial" ] && echo 1 || echo 0)"

: > "$REG_LOG"
( export T_REG_LOG="$REG_LOG"; PATH="$FINGE_W:$PATH"
  t_identidade_fixa "$PID_OK" ) >/dev/null 2>&1
equal "a prefix already stamped is never stamped again" \
      "0" "$(grep -c 'MachineGuid' "$REG_LOG")"

# Half a machine is worse than none, and this is the defect the first version of
# the fix introduced: it wrote the mark whatever happened AND made the mark the
# guard, so a prefix where one view refused the write was frozen with its two
# views disagreeing - 32-bit and 64-bit programs seeing different machines,
# nothing ever retrying, and the mark claiming a GUID only half the prefix held.
# The same lie the fix was for, one shape further out. Caught in review.
PID_MEIO="$TMPROOT/pref-meia-identidade"
mkdir -p "$PID_MEIO/drive_c"
: > "$PID_MEIO/.tandem-prefixo"
printf 'WINE REGISTRY Version 2\n\n#arch=win64\n' > "$PID_MEIO/system.reg"
: > "$REG_LOG"
( export T_REG_LOG="$REG_LOG" T_REG_FALHA=32; PATH="$FINGE_W:$PATH"
  t_identidade_fixa "$PID_MEIO" ) >/dev/null 2>&1
COD_MEIO=$?
equal "a view that refuses the write is reported as a failure" "1" "$COD_MEIO"
equal "and the mark records no identifier, so the next run tries again" \
      "MACHINEGUID=" "$(grep '^MACHINEGUID=' "$PID_MEIO/.tandem-identidade")"
# The seed and the serial are still worth recording on their own.
contem "while the seed still goes on file" \
       "SEMENTE=" "$(cat "$PID_MEIO/.tandem-identidade")"
: > "$REG_LOG"
( export T_REG_LOG="$REG_LOG"; PATH="$FINGE_W:$PATH"
  t_identidade_fixa "$PID_MEIO" ) >/dev/null 2>&1
equal "and the next run really does try both views again" \
      "2" "$(grep -c 'MachineGuid' "$REG_LOG")"
equal "and then it records the identifier" \
      "1" "$(grep -c '^MACHINEGUID=[0-9a-f]' "$PID_MEIO/.tandem-identidade")"

# A win32 prefix has only one view. Demanding both there would mean never
# stamping it at all, which is a refusal dressed up as a safety check.
PID_32="$TMPROOT/pref-identidade-32"
mkdir -p "$PID_32/drive_c"
: > "$PID_32/.tandem-prefixo"
printf 'WINE REGISTRY Version 2\n\n#arch=win32\n' > "$PID_32/system.reg"
: > "$REG_LOG"
( export T_REG_LOG="$REG_LOG"; PATH="$FINGE_W:$PATH"
  t_identidade_fixa "$PID_32" ) >/dev/null 2>&1
equal "a 32-bit environment is stamped in its one view" \
      "1" "$(grep -c 'MachineGuid' "$REG_LOG")"
equal "and that view is named, not left to the default" \
      "1" "$(grep -c '/reg:32' "$REG_LOG")"

# Rule number 1. The write is small, which is exactly why it would be the one
# to slip through.
PID_NAO="$TMPROOT/pref-de-outro"
mkdir -p "$PID_NAO/drive_c"
printf 'WINE REGISTRY Version 2\n\n#arch=win64\n' > "$PID_NAO/system.reg"
: > "$REG_LOG"
( export T_REG_LOG="$REG_LOG"; PATH="$FINGE_W:$PATH"
  t_identidade_fixa "$PID_NAO" ) >/dev/null 2>&1
equal "a prefix without our mark is not written to at all" \
      "0" "$(grep -c . "$REG_LOG")"
equal "and no mark of ours is left inside it" \
      "0" "$([ -f "$PID_NAO/.tandem-identidade" ] && echo 1 || echo 0)"

# The report showed only the 64-bit view, which is how a MachineGuid written
# into the other one went unnoticed. Values, not words: this assertion has to
# hold in all seven languages.
PID_2V="$TMPROOT/pref-duas-vistas"
mkdir -p "$PID_2V/drive_c"
printf 'WINE REGISTRY Version 2\n\n#arch=win64\n\n[Software\\\\Microsoft\\\\Cryptography] 1700000000\n"MachineGuid"="aaaa1111-0000-0000-0000-000000000000"\n\n[Software\\\\Wow6432Node\\\\Microsoft\\\\Cryptography] 1700000000\n"MachineGuid"="bbbb2222-0000-0000-0000-000000000000"\n' \
    > "$PID_2V/system.reg"
TX_2V="$(t_texto_identidade "$PID_2V")"
contem "the report shows what a 64-bit program sees" "aaaa1111" "$TX_2V"
contem "and the different value a 32-bit program sees" "bbbb2222" "$TX_2V"
# Two views that agree are the normal case and deserve no paragraph about it:
# the value appears once, on the identifier line, and nowhere else.
PID_1V="$TMPROOT/pref-vistas-iguais"
mkdir -p "$PID_1V/drive_c"
printf 'WINE REGISTRY Version 2\n\n#arch=win64\n\n[Software\\\\Microsoft\\\\Cryptography] 1700000000\n"MachineGuid"="cccc3333-0000-0000-0000-000000000000"\n\n[Software\\\\Wow6432Node\\\\Microsoft\\\\Cryptography] 1700000000\n"MachineGuid"="cccc3333-0000-0000-0000-000000000000"\n' \
    > "$PID_1V/system.reg"
equal "and it stays quiet when the two views agree" \
      "1" "$(t_texto_identidade "$PID_1V" | grep -c 'cccc3333')"

section "choosing the verb by the program's bitness"

equal "a 32-bit program keeps the normal verb" \
      "xact" "$(t_verbo_para_arquitetura xact 32)"
equal "a verb with no 64-bit sibling is not swapped" \
      "vcrun2022" "$(t_verbo_para_arquitetura vcrun2022 64)"
equal "with no known architecture, nothing is swapped" \
      "xact" "$(t_verbo_para_arquitetura xact '')"
if t_winetricks_tem_verbo xact_x64; then
    equal "a 64-bit program gets the xact_x64 sibling" \
          "xact_x64" "$(t_verbo_para_arquitetura xact 64)"
else
    # Old winetricks without the sibling: better the normal verb than a verb
    # name this winetricks does not know.
    equal "without the sibling in this winetricks, keeps the normal verb" \
          "xact" "$(t_verbo_para_arquitetura xact 64)"
fi

equal "mfc42 is recognized as 32-bit-only" "0" "$(t_verbo_so_32 mfc42; echo $?)"
equal "vcrun2022 is not 32-bit-only"       "1" "$(t_verbo_so_32 vcrun2022; echo $?)"
# The classification comes from the INSTALLED winetricks, not from a list
# written here: a fixed list covered eight verbs, and the winetricks inventory
# found 42.
equal "a verb with an _x64 sibling does not count as 32-bit-only" "1" "$(t_verbo_so_32 xact; echo $?)"
equal "a verb winetricks does not know does not become 32-bit-only" \
      "1" "$(t_verbo_so_32 naoexisteesteverbo; echo $?)"
if t_winetricks_tem_verbo dsound; then
    equal "the classification reaches a verb outside the old list (dsound)" \
          "0" "$(t_verbo_so_32 dsound; echo $?)"
else
    skip "dsound classification" "verb absent in this winetricks"
fi
# wmp9 has no real win64 branch; wmp11 does, and delivers a superset.
if t_winetricks_tem_verbo wmp11; then
    equal "64-bit wmvcore goes to wmp11, not to wmp9" \
          "wmp11" "$(t_verbo_para_arquitetura "$(t_dll_para_verbo wmvcore.dll)" 64)"
    equal "  and the 32-bit one stays on wmp9" \
          "wmp9" "$(t_verbo_para_arquitetura "$(t_dll_para_verbo wmvcore.dll)" 32)"
else
    skip "wmvcore in 64 bits" "wmp11 absent in this winetricks"
fi

# BITNESS AUDITOR. The two lists above were compiled from winetricks 20240105,
# reading verb by verb. Winetricks is updated outside Tandem: without this test,
# the day the project starts installing a 64-bit payload for mfc42 nobody finds
# out, and Tandem keeps warning that there is no fix for something that now has
# one.
WT="$(command -v winetricks 2>/dev/null)"
if [ -n "$WT" ] && [ -r "$WT" ]; then
    diverged=""
    for v in dbghelp mfc42 msxml3 msxml4 openal riched20 vcrun2003 wsh57; do
        if sed -n "/^load_${v}()/,/^}/p" "$WT" 2>/dev/null |
           grep -qE 'x64|win64|W_SYSTEM64|amd64'; then
            diverged="$diverged $v"
        fi
    done
    # And the other way round: a verb the table uses, covers 64, and is marked
    # as 32-bit-only.
    for v in vcrun2022 vcrun2010 dotnet48 d3dx9 gdiplus xinput; do
        t_verbo_so_32 "$v" && diverged="$diverged !$v"
    done
    if [ -z "$diverged" ]; then
        pass "the 32-bit-only verb list matches the installed winetricks"
    else
        fail "the 32-bit-only verb list matches the installed winetricks" \
               "(no divergence)" "$diverged"
    fi
    # And does the x64 sibling really exist? Promising a nonexistent verb would
    # make winetricks fail with an error the owner has no way to understand.
    if t_winetricks_tem_verbo xact_x64; then
        pass "the xact_x64 sibling exists in this winetricks"
    else
        skip "the xact_x64 sibling" "winetricks without that verb"
    fi
    equal "a made-up verb does not pass for an existing one" \
          "1" "$(t_winetricks_tem_verbo naoexisteesteverbo; echo $?)"
else
    skip "bitness auditor" "winetricks not installed"
fi

section "data: what can be remade and what cannot"

# A prefix with both things mixed together, which is how every real prefix is.
PD="$TMPROOT/prefdados"
mkdir -p "$PD/drive_c/windows/system32" \
         "$PD/drive_c/users/zero/Documents" \
         "$PD/drive_c/users/zero/AppData/Roaming/SistemaLoja" \
         "$PD/drive_c/users/Public/Documents" \
         "$PD/drive_c/Program Files/SistemaLoja" \
         "$PD/drive_c/Program Files/SistemaLoja/Temp" \
         "$PD/drive_c/users/zero/Desktop"
: > "$PD/system.reg"; : > "$PD/.tandem-prefixo"
# Environment: remakeable, does not go in.
head -c 4096 /dev/zero > "$PD/drive_c/windows/system32/msvcp140.dll"
head -c 2048 /dev/zero > "$PD/drive_c/Program Files/SistemaLoja/loja.exe"
# Data: irreplaceable, goes in.
head -c 9000 /dev/zero > "$PD/drive_c/Program Files/SistemaLoja/cadastro.mdb"
head -c 1500 /dev/zero > "$PD/drive_c/users/zero/Documents/vendas.xlsx"
head -c 700  /dev/zero > "$PD/drive_c/users/zero/AppData/Roaming/SistemaLoja/config.db"
# Junk that does not deserve the trip.
head -c 5000 /dev/zero > "$PD/drive_c/Program Files/SistemaLoja/Temp/rascunho.bak"
# An empty folder is not data, it is Wine decoration.
LISTA_D="$(t_dados_lista "$PD")"

case "$LISTA_D" in
    *"Program Files/SistemaLoja/cadastro.mdb"*) pass "finds the database dumped next to the executable" ;;
    *) fail "finds the database dumped next to the executable" "cadastro.mdb" "$LISTA_D" ;;
esac
case "$LISTA_D" in
    *"users/zero/Documents"*) pass "finds the user's Documents folder" ;;
    *) fail "finds the user's Documents folder" "users/zero/Documents" "$LISTA_D" ;;
esac
case "$LISTA_D" in
    *msvcp140.dll*|*loja.exe*) fail "does not carry the environment along" "no dll and no exe" "$LISTA_D" ;;
    *) pass "does not carry the environment along" ;;
esac
case "$LISTA_D" in
    *rascunho.bak*) fail "ignores whatever is in Temp" "no rascunho.bak" "$LISTA_D" ;;
    *) pass "ignores whatever is in Temp" ;;
esac
case "$LISTA_D" in
    *users/Public*) fail "ignores the Windows system folders" "no Public" "$LISTA_D" ;;
    *) pass "ignores the Windows system folders" ;;
esac
case "$LISTA_D" in
    *Desktop*) fail "an empty folder does not become an item" "no Desktop" "$LISTA_D" ;;
    *) pass "an empty folder does not become an item" ;;
esac
equal "sums up the size of everything it found" \
      "0" "$([ "$(t_dados_total "$PD")" -gt 10000 ]; echo $?)"

# The copy has to be openable and contain the data, only the data.
ARQD="$TMPROOT/dados.tar.gz"
t_dados_salva "$PD" "$ARQD"
equal "the data copy is generated" "0" "$?"
CONTEUDO="$(tar -tzf "$ARQD" 2>/dev/null)"
case "$CONTEUDO" in
    *cadastro.mdb*) pass "the copy takes the database" ;;
    *) fail "the copy takes the database" "cadastro.mdb" "$CONTEUDO" ;;
esac
case "$CONTEUDO" in
    *msvcp140.dll*) fail "the copy does not take the environment" "no dll" "$CONTEUDO" ;;
    *) pass "the copy does not take the environment" ;;
esac
# Restoring into an empty prefix has to put things back in the right place.
PD2="$TMPROOT/prefvazio"; mkdir -p "$PD2/drive_c"
tar -C "$PD2/drive_c" -xzf "$ARQD" 2>/dev/null
equal "the copy comes back in the right place" \
      "0" "$([ -f "$PD2/drive_c/Program Files/SistemaLoja/cadastro.mdb" ]; echo $?)"

# A prefix with nothing of the owner's: there is nothing to save, and that is
# NOT an error.
PD3="$TMPROOT/prefnovo"; mkdir -p "$PD3/drive_c/windows/system32"
equal "a freshly created prefix has no data" "0" "$(t_dados_total "$PD3")"
# Three distinct outcomes, and the distinction is the point: "there was nothing"
# is normal and silent, "there was data and the copy failed" has to stop whoever
# is about to delete. Merging the two into a "return 1" made a full disk look
# like an empty prefix, and the deletion went ahead anyway.
t_dados_salva "$PD3" "$TMPROOT/vazio.tar.gz" 2>/dev/null
equal "a prefix with no data returns 2, not 1" "2" "$?"
equal "  and leaves no half-written file on disk" \
      "1" "$([ -f "$TMPROOT/vazio.tar.gz" ]; echo $?)"
t_dados_resgate "$PD3" teste >/dev/null 2>&1
equal "rescuing an empty prefix also returns 2" "2" "$?"
# A copy that really FAILS: destination on a path that does not exist.
t_dados_salva "$PD" "/nao/existe/x.tar.gz" 2>/dev/null
equal "a copy that fails returns 1, not 2" "1" "$?"
# And the sentence the owner reads in that case has to spell out the risk.
case "$(t_texto_resgate_falhou)" in
    *"could NOT make a copy"*"no getting them back"*)
        pass "the failed-rescue message states the risk" ;;
    *) fail "the failed-rescue message states the risk" \
              "could NOT make a copy... no getting them back" \
              "$(t_texto_resgate_falhou)" ;;
esac
# And the three destructive paths have to handle code 1 before deleting.
for alvo in src/bin/tandem-exe src/bin/tandem; do
    if grep -q 't_texto_resgate_falhou' "$ROOT/$alvo"; then
        pass "$alvo stops when the rescue copy fails"
    else
        fail "$alvo stops when the rescue copy fails" \
               "t_texto_resgate_falhou" "missing"
    fi
done

# Multi-line value in memory: the format is KEY=VALUE per line, and writing it
# raw left orphan lines that the rewrite did not remove - a fresh copy on every
# open, forever. Measured: four writes, 22 lines, three blocks of junk.
MEM_ML="$ARTIFACTS/prog32.exe"
t_memoria_esquece "$MEM_ML" 2>/dev/null
for _i in 1 2 3 4; do
    t_memoria_grava "$MEM_ML" LIMITE "linha um
linha dois

linha quatro"
done
t_memoria_grava "$MEM_ML" RESULTADO abriu
equal "a multi-line value does not accumulate junk" \
      "5" "$(wc -l < "$(t_memoria_arquivo "$MEM_ML")")"
equal "  and comes back whole when read" \
      "linha um
linha dois

linha quatro" "$(t_memoria_le "$MEM_ML" LIMITE)"
equal "  without spoiling the other keys" "abriu" "$(t_memoria_le "$MEM_ML" RESULTADO)"
t_memoria_esquece "$MEM_ML" 2>/dev/null

equal "size in readable Portuguese" "9 KB" "$(t_tamanho_amigavel 9216)"
equal "a small size stays in bytes" "800 bytes" "$(t_tamanho_amigavel 800)"

section "proof of delivery: winetricks exiting 0 does not prove the DLL arrived"

# Up to here the suite exercised the libraries. This block runs the WHOLE
# tandem-exe - the run->detect->install->repeat loop - with a fake wine and a
# fake winetricks. It is the only way to exercise in CI the path that never
# fired in the field, because the only program actually installed for real
# (7-Zip) depends on nothing.

E2E="$TMPROOT/e2e"; mkdir -p "$E2E/bin"

# A program that always fails complaining about the same DLL.
cat > "$E2E/bin/wine" <<'FIM'
#!/bin/sh
# "wine reg add" has to work: it is what turns off the hijacking of file
# associations. Any other call pretends the program is broken.
[ "$1" = reg ] && exit 0
printf '0009:err:module:import_dll Library MSVCR71.dll (needed by Z:\\x.exe) not found\n' >&2
exit 53
FIM
printf '#!/bin/sh\nexit 0\n' > "$E2E/bin/wineserver"
# The obedient winetricks: always exits 0, and only delivers the file if told
# to. That is exactly the trap - the exit code is not the delivery.
cat > "$E2E/bin/winetricks" <<'FIM'
#!/bin/sh
printf '%s\n' "$*" >> "$E2E_DIARIO"
if [ -n "$E2E_ENTREGA" ]; then
    mkdir -p "$WINEPREFIX/drive_c/windows/system32"
    : > "$WINEPREFIX/drive_c/windows/system32/$E2E_ENTREGA"
fi
exit 0
FIM
# Without this the loop would call the real systemd-inhibit, which does not run
# in a container.
cat > "$E2E/bin/systemd-inhibit" <<'FIM'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in --*) shift ;; *) break ;; esac; done
exec "$@"
FIM
# Answers "Install" and saves the text the owner would see on screen.
cat > "$E2E/bin/zenity" <<'FIM'
#!/bin/sh
for a in "$@"; do
    case "$a" in --text=*) printf '%s\n<<<>>>\n' "${a#--text=}" >> "$E2E_JANELAS" ;; esac
done
exit 0
FIM
chmod +x "$E2E/bin"/*

# $1 = folder for this round (becomes HOME), $2 = file winetricks delivers,
# $3 = "semgui" to run without a graphical session (terminal path)
roda_exe() {
    local casa="$1" delivers="$2" modo="${3:-gui}" pref tela=:99
    pref="$casa/.local/share/tandem/wine"
    mkdir -p "$pref/drive_c/windows/system32"
    : > "$pref/system.reg"; : > "$pref/.tandem-prefixo"
    [ "$modo" = semgui ] && tela=""
    env -i HOME="$casa" DISPLAY="$tela" PATH="$E2E/bin:/usr/bin:/bin" \
        E2E_ENTREGA="$delivers" E2E_DIARIO="$casa/diario.txt" \
        E2E_JANELAS="$casa/janelas.txt" TANDEM_LIB="$ROOT/src/lib" \
        bash "$ROOT/src/bin/tandem-exe" "$ARTIFACTS/prog64.exe" \
        > "$casa/stdout.txt" 2> "$casa/stderr.txt"
}

if [ ! -x "$E2E/bin/wine" ]; then
    skip "proof of delivery" "could not set up the fake environment"
else
    # --- Case 1: the installation delivers the file. Normal receipt.
    A="$E2E/entregou"; mkdir -p "$A"; roda_exe "$A" msvcr71.dll
    equal "delivered: the receipt is written" \
          "vcrun2003" "$(sort -u "$A/.local/share/tandem/wine/.tandem-verbos" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    equal "delivered: no suspicious translation is recorded" \
          "1" "$([ -f "$A/.local/state/tandem/traducao-suspeita.tsv" ]; echo $?)"
    equal "delivered: winetricks was called exactly once" \
          "1" "$(grep -c vcrun2003 "$A/diario.txt" 2>/dev/null)"

    # --- Case 2: winetricks exits 0 and the file never arrives.
    B="$E2E/enganou"; mkdir -p "$B"; roda_exe "$B" ""
    equal "not delivered: the receipt is NOT written" \
          "1" "$([ -s "$B/.local/share/tandem/wine/.tandem-verbos" ]; echo $?)"
    equal "not delivered: the suspicion is recorded with the DLL and the verb" \
          "msvcr71.dll	vcrun2003" \
          "$(cut -f1,2 "$B/.local/state/tandem/traducao-suspeita.tsv" 2>/dev/null | head -1)"
    # The message has to name the file that was missing and take the blame.
    # Saying "I installed the dependencies and it still does not open" would
    # send the owner looking for a defect in their machine, which is perfect.
    JAN="$(cat "$B/janelas.txt" 2>/dev/null)"
    case "$JAN" in
        *msvcr71.dll*is\ still\ missing*) pass "not delivered: the message names the file that was missing" ;;
        *) fail "not delivered: the message names the file that was missing" \
                  "...msvcr71.dll is still missing..." "${JAN:-(no window)}" ;;
    esac
    case "$JAN" in
        *"my mistake, not your machine"*) pass "not delivered: Tandem takes the blame" ;;
        *) fail "not delivered: Tandem takes the blame" \
                  "erro meu, não da sua máquina" "${JAN:-(no window)}" ;;
    esac
    case "$JAN" in
        *"already installed what this program was asking for"*)
            fail "not delivered: does not fall into the receipt dead end" \
                   "another message" "Já instalei o que este programa pedia" ;;
        *) pass "not delivered: does not fall into the receipt dead end" ;;
    esac
    # The wrong lesson must not become memory: it would travel with the recipe
    # to the other machine and teach the same mistake again.
    equal "not delivered: no NAO_RESOLVERAM in memory" \
          "" "$(grep -h '^NAO_RESOLVERAM=' "$B/.local/state/tandem/memoria/"*.txt 2>/dev/null)"
    # Within the same run the suspicious verb is not reinstalled: that would be
    # half an hour thrown away, in the .NET case.
    equal "not delivered: does not repeat the installation in the same run" \
          "1" "$(grep -c vcrun2003 "$B/diario.txt" 2>/dev/null)"

    # --- Case 3: second run. With no receipt, it has to offer again.
    roda_exe "$B" ""
    equal "second run: offers to install once more" \
          "2" "$(grep -c vcrun2003 "$B/diario.txt" 2>/dev/null)"
    equal "second run: the suspicion is recorded again, with a date" \
          "2" "$(grep -c vcrun2003 "$B/.local/state/tandem/traducao-suspeita.tsv" 2>/dev/null)"

    # --- Case 4: without a graphical session, the message has to come out on
    # the terminal.
    #
    # This test exists because of a defect measured on a real Ubuntu 24.04: the
    # loop detected the DLL, translated it correctly, assembled the right
    # message with the right command - and returned code 53 with ZERO BYTES of
    # output. The cause was "exec 7> arq 2>/dev/null": exec without a command
    # applies the redirections to the whole shell, permanently, so that
    # 2>/dev/null diverted stderr for all the rest of the program. No test
    # caught it because they all ran with DISPLAY set, where the message comes
    # out through the window.
    C="$E2E/semjanela"; mkdir -p "$C"; roda_exe "$C" "" semgui
    if [ -s "$C/stderr.txt" ]; then pass "no window: the message comes out on the terminal"
    else fail "no window: the message comes out on the terminal" \
                "any text on stderr" "zero bytes (silent error)"; fi
    case "$(cat "$C/stderr.txt" 2>/dev/null)" in
        *"winetricks -q vcrun2003"*) pass "no window: states the exact command to fix it" ;;
        *) fail "no window: states the exact command to fix it" \
                  "winetricks -q vcrun2003" "$(head -c 200 "$C/stderr.txt" 2>/dev/null)" ;;
    esac
fi

section ".deb package"

DEB_SAIDA="$TMPROOT/build"
mkdir -p "$DEB_SAIDA"
if python3 build.py --check > "$TMPROOT/build.log" 2>&1; then
    pass "build.py --check"
else
    fail "build.py --check" "success" "$(tail -3 "$TMPROOT/build.log")"
fi

VERSAO_DEB="$(grep '^Version:' debian/control | cut -d' ' -f2)"
PACOTE_DEB="$ROOT/tandem_${VERSAO_DEB}_all.deb"

equal "the version in control matches the one in the executable" \
      "$VERSAO_DEB" "$(grep '^TANDEM_VERSAO=' src/lib/common.sh | cut -d'"' -f2)"

equal "the changelog's newest entry is the version being built" \
      "$VERSAO_DEB" "$(sed -n '1s/^tandem (\([^)]*\)).*/\1/p' debian/changelog)"

# lintian refuses a release whose newest changelog entry is not dated after the
# one below it, and it has caught this project twice - both times because an
# earlier entry carried a timestamp in the FUTURE, so a correctly dated new
# entry sorted behind it. Both times the discovery was a failed release rather
# than a failed test, which is the wrong order to find it in.
DATA_1="$(grep -m1 '^ -- ' debian/changelog | sed 's/^ -- [^>]*>  //')"
DATA_2="$(grep '^ -- ' debian/changelog | sed -n '2s/^ -- [^>]*>  //p')"
if [ -z "$DATA_2" ]; then
    pass "the newest changelog entry is dated after the one before it"
elif [ "$(date -d "$DATA_1" +%s 2>/dev/null || echo 0)" \
       -gt "$(date -d "$DATA_2" +%s 2>/dev/null || echo 1)" ]; then
    pass "the newest changelog entry is dated after the one before it"
else
    fail "the newest changelog entry is dated after the one before it" \
         "newer than $DATA_2" "$DATA_1"
fi

# lintian refuses a changelog line over 80 columns, and the release step runs it
# with --fail-on warning while demanding ZERO output - so eight lines at 81 and
# 82 columns turned a green suite into a red release. Found by CI rather than
# here, which is the wrong order, so the suite owns it now.
#
# Only the newest entry is checked, and that is a decision rather than laziness:
# older entries carry " -- Name <address>  date" trailers at 85 columns that
# lintian does not complain about, and rewrapping history to satisfy a guard
# would mean editing what was already published.
NOME_COL="the newest changelog entry stays inside 80 columns"
FIM_ENTRADA="$(awk '/^ -- /{ print NR; exit }' "$ROOT/debian/changelog")"
LONGAS="$(awk -v fim="${FIM_ENTRADA:-0}" \
              'NR < fim && length > 80 { printf "line %d is %d columns\n", NR, length }' \
              "$ROOT/debian/changelog")"
if [ -z "$LONGAS" ]; then
    pass "$NOME_COL"
else
    fail "$NOME_COL" "every line at 80 columns or fewer" "$LONGAS"
fi

# The top changelog entry must not describe a package that is already out. It
# happened: v4.1 was published on 2026-08-09 and three commits' worth of work
# kept being appended to its entry afterwards, so the entry described a package
# the public never received. Whoever hits this has to open a NEW entry, not edit
# the top one.
#
# The check is "did this version's changelog entry change since it shipped",
# not "does a tag with this version exist" - and the difference is the whole
# usefulness of it. The plain tag test is red on a freshly released tree, where
# the version in control IS the published one and nothing is wrong; it would
# have gone red the minute a release succeeded and stayed red until somebody
# bumped a number to shut it up. Comparing the file instead means a released
# tree passes, a doc-only commit after a release passes, and appending a bullet
# to a published entry fails - which is the only thing that ever went wrong.
#
# Skips rather than fails wherever the answer cannot be known: no repository, no
# tags fetched, or a shallow clone that has the tag ref but not the objects
# behind it. A guard that stops a good release for lack of information is worse
# than the drift it was written for, and this project has already been bitten by
# exactly that.
NOME_PUB="the top changelog entry does not describe an already published version"
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 ||
   [ -z "$(git -C "$ROOT" tag 2>/dev/null | head -1)" ]; then
    skip "$NOME_PUB" "no tags here, so what is published cannot be known"
elif ! git -C "$ROOT" rev-parse -q --verify "refs/tags/v$VERSAO_DEB" >/dev/null 2>&1; then
    pass "$NOME_PUB"
else
    git -C "$ROOT" diff --quiet "refs/tags/v$VERSAO_DEB" -- debian/changelog 2>/dev/null
    case $? in
        0) pass "$NOME_PUB" ;;
        1) fail "$NOME_PUB" \
                "a new entry for a version that is not out yet" \
                "v$VERSAO_DEB is published and its changelog entry has been edited since" ;;
        *) skip "$NOME_PUB" "the tag v$VERSAO_DEB is here but its objects are not" ;;
    esac
fi

if [ -f "$PACOTE_DEB" ]; then
    pass "the .deb was generated"
    if command -v dpkg-deb >/dev/null 2>&1; then
        if dpkg-deb --info "$PACOTE_DEB" >/dev/null 2>&1 &&
           dpkg-deb --contents "$PACOTE_DEB" >/dev/null 2>&1; then
            pass "dpkg-deb accepts the hand-written file"
        else
            fail "dpkg-deb accepts the hand-written file" "accepted" "refused"
        fi
        contents="$(dpkg-deb --contents "$PACOTE_DEB" 2>/dev/null)"
        for exigido in usr/bin/tandem usr/lib/tandem/common.sh \
                       usr/share/doc/tandem/copyright \
                       usr/share/doc/tandem/changelog.gz \
                       usr/share/man/man1/tandem.1.gz \
                       usr/share/polkit-1/rules.d/49-tandem.rules \
                       usr/share/mime/packages/tandem.xml; do
            if printf '%s' "$contents" | grep -q " ./$exigido\$"; then
                pass "the package ships $exigido"
            else
                fail "the package ships $exigido" "present" "missing"
            fi
        done
        if printf '%s' "$contents" | grep -qv 'root/root'; then
            : # any lines without root/root? checked explicitly below
        fi
        naoroot="$(printf '%s' "$contents" | grep -cv 'root/root')"
        equal "every file belongs to root" "0" "$naoroot"
    else
        skip "validation with dpkg-deb" "dpkg-deb not installed"
    fi

    # Two builds in a row have to produce exactly the same file.
    soma1="$(cksum < "$PACOTE_DEB")"
    python3 build.py >/dev/null 2>&1
    soma2="$(cksum < "$PACOTE_DEB")"
    equal "the build is reproducible" "$soma1" "$soma2"
else
    fail "the .deb was generated" "$PACOTE_DEB" "missing"
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
    for d in src/applications/*.desktop; do
        if desktop-file-validate "$d" 2>&1 | grep -q .; then
            fail "desktop-file-validate $(basename "$d")" "no warnings" \
                   "$(desktop-file-validate "$d" 2>&1 | head -1)"
        else
            pass "desktop-file-validate $(basename "$d")"
        fi
    done
else
    skip "desktop-file-validate" "not installed"
fi

section "the failure is explained from the verb that failed"

# THE DEFECT, stated exactly, because it is the reason this function exists at
# all: MARCA_WT was reassigned on every iteration of the install loop,
# successes included, so after the loop it marked the LAST VERB ATTEMPTED
# rather than the last one that FAILED. The whole cause table then ran over
# that slice. When a program needs two components and the first fails, the
# owner was told his internet had failed - about a component whose real problem
# was a missing cabextract - because a LATER component downloaded normally. He
# goes and looks at his router.
#
# Every existing test installs a single verb, which is why nothing could see
# it, and reaching the code needed a real winetricks to fail. So the table is
# a function now and the two-verb case is a fixture.
causa() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; t_causa_do_winetricks "$1" /tmp/x.log' _ "$1" 2>/dev/null
}
# What the OLD code fed the table: the whole tail of the log, which contains
# the successful verb's download chatter as well as the failure.
cat > "$TMPROOT/wt-ambos.log" <<'FIMWT'
Executing load_vcrun2022
Executing cabextract -q -d /tmp/x /tmp/vc_redist.x64.exe
sh: 1: cabextract: not found
------------------------------------------------------
Executing load_mfc42
Downloading https://example.invalid/mfc42.exe
saved [1234/1234]
FIMWT
# What the NEW code feeds it: only the failing verb's output.
cat > "$TMPROOT/wt-so-falha.log" <<'FIMWT2'
Executing load_vcrun2022
Executing cabextract -q -d /tmp/x /tmp/vc_redist.x64.exe
sh: 1: cabextract: not found
FIMWT2
contem "the real cause is named when only the failing verb is looked at" \
       "cabextract" "$(causa "$TMPROOT/wt-so-falha.log")"
# The table prefers a specific cause over the internet guess, so even the old
# mixed slice names cabextract here - what the old code actually lost is the
# case below, where the failing verb said nothing specific at all.
cat > "$TMPROOT/wt-mudo.log" <<'FIMWT3'
Executing load_vcrun2022
warning: winetricks is not compatible with this prefix
FIMWT3
cat > "$TMPROOT/wt-mudo-mais-sucesso.log" <<'FIMWT4'
Executing load_vcrun2022
warning: winetricks is not compatible with this prefix
------------------------------------------------------
Executing load_mfc42
Downloading https://example.invalid/mfc42.exe
saved [1234/1234]
FIMWT4
naocontem "a verb that failed silently is NOT blamed on the internet" \
          "internet" "$(causa "$TMPROOT/wt-mudo.log")"
contem "which is exactly what the old whole-tail slice got wrong" \
       "internet" "$(causa "$TMPROOT/wt-mudo-mais-sucesso.log")"
# And the slice really is taken per verb, inside the loop, not after it.
naocontem "so the slice is taken when a verb fails, not after the loop" \
          'tail -n +"$((MARCA_WT+1))" "$LOG" > "$RESTO"' \
          "$(cat "$ROOT/src/bin/tandem-exe")"
contem "and it is appended from the failure branch" \
       'tail -n +"$((MARCA_WT+1))" "$LOG" >> "$RESTO"' \
       "$(cat "$ROOT/src/bin/tandem-exe")"

# A Brazilian date order inside a sentence that IS translated. The wrong-clock
# message reaches en, zh_CN, hi and ar readers with dd/mm/yyyy in the middle of
# it; %x is the locale's own order.
naocontem "the wrong-clock message does not hard-code a Brazilian date order" \
          "+%d/%m/%Y" "$(cat "$ROOT/src/lib/common.sh" "$ROOT/src/bin/tandem-exe")"

section "the .exe is asked whether the download finished"

# The question is already asked of a .jar (its index lives at the end), of an
# .AppImage (payload offset plus squashfs bytes_used) and of a .deb (a missing
# data.tar member). It was never asked of the .exe - and a 400 MB
# point-of-sale installer cut short over a shop connection is the commonest
# broken thing that reaches this project. Wine's answer today is "Bad EXE
# format", after the wait, which sends the owner looking for a defect in a
# file that simply did not finish arriving.
pe_erro() {
    python3 "$ROOT/src/lib/peinfo.py" "$1" 2>&1 | sed -n 's/^ERRO=//p'
}
equal "an intact PE is not accused of being short" \
      "" "$(pe_erro "$ARTIFACTS/importslimpo.exe")"
python3 - "$ARTIFACTS/importslimpo.exe" "$TMPROOT/cortado.exe" <<'FIMPE'
import sys
d = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(d[:int(len(d) * 0.6)])
FIMPE
equal "a PE cut short is reported as an unfinished download" \
      "pe_incompleto" "$(pe_erro "$TMPROOT/cortado.exe")"

# THE HALF THAT MATTERS MORE, because getting it wrong would refuse to open
# exactly the software this project exists for. NSIS and Inno Setup append
# their payload AFTER the last section, so every real Windows installer is
# longer than its section table accounts for. The check is one-sided on
# purpose: only "shorter than declared" is ever a verdict.
python3 - "$ARTIFACTS/importslimpo.exe" "$TMPROOT/comcarga.exe" <<'FIMPE2'
import sys
d = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(d + b"NSIS-PAYLOAD" * 50000)
FIMPE2
equal "an installer with its payload appended is NOT called incomplete" \
      "" "$(pe_erro "$TMPROOT/comcarga.exe")"
# And the token has to become a sentence, in the reader's language.
contem "and the token becomes a sentence the owner can act on" \
       "Downloading it again" \
       "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
          bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_erro_do_leitor pe_incompleto')"

section "why this component, not just which"

# The screen where the owner agrees to a half-hour download named the runtime
# and never the file the program actually asked for, so he was agreeing on
# trust. Tandem has known the pair since 3.3 - t_pares_do_log keeps it so
# delivery can be proved afterwards - and was throwing the useful half away.
cat > "$TMPROOT/porque.log" <<'FIMLOG'
0009:err:module:import_dll Library MSVCP140.dll (needed by Z:\x.exe) not found
0009:err:module:import_dll Library VCRUNTIME140.dll (needed by Z:\x.exe) not found
0009:err:module:import_dll Library mfc42.dll (needed by Z:\x.exe) not found
FIMLOG
lista_porque() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO="$1" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"; . "'"$ROOT"'/src/lib/winedeps.sh"
        PARES="$(t_pares_do_log "'"$TMPROOT"'/porque.log")"
        for v in $(t_verbos_do_log "'"$TMPROOT"'/porque.log"); do
            dlls="$(printf "%s\n" "$PARES" | awk -F"\t" -v alvo="$v" "\$2 == alvo { print \$1 }" |
                    sort -u | tr "\n" "," | sed "s/,\$//; s/,/, /g")"
            [ -n "$dlls" ] && t_msg componente_porque "$(t_verbo_amigavel "$v")" "$dlls" && printf "\n"
        done' 2>/dev/null
}
PORQUE="$(lista_porque en)"
contem "the install list names the file the program actually asked for" \
       "the program asked for mfc42.dll" "$PORQUE"
# Two DLLs from the same runtime are one line, not two installs.
contem "and two files from one runtime are grouped on its single line" \
       "msvcp140.dll, vcruntime140.dll" "$PORQUE"
contem "and the reason is in the reader's own language" \
       "程序要的是" "$(lista_porque zh_CN)"

section "a saved web page is named as one, by every handler"

# A download that goes wrong rarely produces nothing: the site answers with a
# 404, a login wall or a robot check, and the browser saves that HTML under the
# name the link promised. t_parece_pagina_web has existed since 3.8 and had
# exactly TWO callers - tandem-deb and the CLI's content sniff, which a
# double-clicked .jar never reaches. Everywhere else the owner was told his
# download stopped part way, which is the worst possible answer: it sends him
# back to the same link to fetch the same page, for ever.
#
# The .jar and .rpm orderings are the interesting half. A zip's index lives at
# the END of the file, so an HTML page named .jar fails as "zip_invalido" -
# indistinguishable from a real truncation - and the .rpm reader answers
# "nao_e_rpm" rather than a truncation token, so a check wired only into the
# incomplete-download branch never fires. Both were measured, not assumed.
PAGINA="$TMPROOT/instalador-pagina"
cat > "$PAGINA.html" <<'FIMHTML'
<!DOCTYPE html>
<html><head><title>404 Not Found</title></head>
<body><h1>Not Found</h1><p>The requested URL was not found on this server.</p></body></html>
FIMHTML
for par in "apk:apk" "AppImage:appimage" "jar:jar" "rpm:rpm" "snap:snap" \
           "flatpakref:flatpak" "deb:deb"; do
    ext="${par%%:*}"; h="${par##*:}"
    cp "$PAGINA.html" "$PAGINA.$ext"
    saida="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
        timeout 60 bash "$ROOT/src/bin/tandem-$h" "$PAGINA.$ext" </dev/null 2>&1 | head -3)"
    contem "tandem-$h says a .$ext that is really a web page is a web page" \
           "it is a web page saved under a program" "$saida"
done

# And the negative, which is what stops this from being a fix that lies in the
# other direction: a genuinely short file must still be reported as a stopped
# download, not as a web page.
head -c 200 /dev/zero > "$TMPROOT/curto.rpm"
naocontem "but a genuinely truncated file is not called a web page" \
          "web page saved under" \
          "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
             bash "$ROOT/src/bin/tandem-rpm" "$TMPROOT/curto.rpm" </dev/null 2>&1 | head -2)"

section "the badge on the front page does not lie"

# It drifted twice, in both directions, because nothing checked it: the README
# announced 473 tests while the suite ran 499, and then 499 while it ran 547.
# A number on the front page that nobody verifies is a claim like any other,
# and this project's whole argument is that claims get checked.
#
# The two assertions below count themselves - they are tests too - so the
# badge states the number of checks that pass when everything passes. When it
# fails, the message says exactly which number to write.
# It cannot be an exact comparison, and the first version of this check found
# that out by blocking a release: how many checks RUN depends on which optional
# tools the machine has. This container skips one, CI skips two and runs two
# others that do not exist here, so "passed" differs by a handful between the
# two and neither number is wrong.
#
# So the tolerance is symmetric, and the first one-sided version of this check
# proves why: written as "never fewer than ran here" it blocked the release
# from CI, where two more checks run than in this container. A guard that stops
# a good release is worse than the drift it was written for.
#
# Fifteen either way. The two drifts that actually happened were 26 and 48 -
# whole features' worth of tests - so the slack costs nothing real and no
# difference in optional tooling can hold a release hostage again.
TOTAL_AQUI=$((OK + FAILED + SKIPPED + 2))   # +2: the two checks below count
FOLGA=15
for par in "README.md|tests" "LEIAME.md|testes"; do
    arq="${par%%|*}"; rotulo="${par#*|}"
    achado="$(sed -n "s|.*badge/$rotulo-\([0-9]*\)-.*|\1|p" "$ROOT/$arq" | head -1)"
    dist=$(( ${achado:-0} - TOTAL_AQUI )); [ "$dist" -lt 0 ] && dist=$(( -dist ))
    if [ -n "$achado" ] && [ "$dist" -le "$FOLGA" ] 2>/dev/null; then
        pass "$arq does not misstate how many tests it has"
    else
        fail "$arq does not misstate how many tests it has" \
             "within $FOLGA of $TOTAL_AQUI — write $TOTAL_AQUI" \
             "${achado:-no badge found}"
    fi
done

# ------------------------------------------------------------- summary

printf '\n────────────────────────────────────────\n'
printf '%d passed, %d failed, %d skipped\n' "$OK" "$FAILED" "$SKIPPED"
if [ "$FAILED" -gt 0 ]; then
    printf '\nfailures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
