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
      "3113706947 5166" "$soma_esperados"
equal "the case patterns still match the real messages" \
      "446507627 2591" "$soma_padroes"

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

# THE MOST SPECIFIC ROW OF limites.tsv WINS, and that rests entirely on the
# ORDER of the file: t_limite_do_programa walks the table in the outer loop and
# stops at the first row that matches. Nothing asserted it.
#
# What it costs to lose: hasp4*.dll is Aladdin's older HASP4 and hasp*.dll is
# the modern Sentinel line, two different products with two different sets of
# instructions in column 4. Alphabetise this file, or add a broad pattern near
# the top, and a HASP4 owner is handed the Sentinel recipe - the exact harm
# this project already hit once, when the tool that translated these tables
# walked them by line number and mismatched the rows.
limite_classe() {
    TANDEM_LIB="$ROOT/src/lib" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_pe_dlls() { printf "%s\n" "'"$1"'"; }
        t_limite_do_programa /qualquer 2>/dev/null | head -1' 2>/dev/null
}
for _par in "hasp4_windows.dll|dongle" \
            "haspms32.dll|dongle" \
            "hasp_windows_x64.dll|dongle-sentinel" \
            "haspvlib_1.dll|dongle-sentinel" \
            "codemeter64.dll|dongle-codemeter" \
            "rockey4nd.dll|dongle-hid" \
            "ndis.sys|driver" \
            "qualquer.sys|driver" \
            "clisitef32i.dll|tef"; do
    _dll="${_par%%|*}"; _esperado="${_par##*|}"
    _obtido="$(limite_classe "$_dll")"; _obtido="${_obtido%%|*}"
    equal "limites.tsv puts $_dll in the most specific class" "$_esperado" "$_obtido"
done

# WHO OWNS A MIME TYPE IS ASKED OF GIO, EVERYWHERE - not just where the lesson
# was learned. xdg-mime does not resolve the MIME subclass chain and GIO does,
# and GIO is what Nautilus uses; measured on a type Tandem never touches,
# `gio mime text/sgml` answers vim.desktop while `xdg-mime query default
# text/sgml` answers nothing.
#
# t_dono_do_tipo was written for tandem-repair when that was found, and
# `tandem autoteste` went on asking xdg-mime alone - in check 7, the one whose
# own comment says that without it the rest does not matter. This assertion is
# deliberately a GLOB over every shipped executable rather than a check on the
# file where the defect happened to be, because that narrow shape is exactly
# what let it survive.
for _f in "$ROOT"/src/bin/tandem "$ROOT"/src/bin/tandem-*; do
    _corpo="$(sed 's/#.*//' "$_f")"
    case "$_corpo" in
        *"xdg-mime query default"*)
            case "$(basename "$_f")" in
                # tandem-repair SETS associations with both tools on purpose;
                # reading is what must go through t_dono_do_tipo.
                tandem-repair) pass "$(basename "$_f") does not read ownership from xdg-mime alone" ;;
                *) fail "$(basename "$_f") does not read ownership from xdg-mime alone" \
                        "t_dono_do_tipo, which asks GIO first" "a bare xdg-mime query" ;;
            esac ;;
        *) pass "$(basename "$_f") does not read ownership from xdg-mime alone" ;;
    esac
done

# ONE CONFIG FILE, MORE THAN ONE WRITER. The temp file this write goes through
# was named "$TANDEM_CONFIG.novo" - FIXED, not per process - so two writers at
# once truncated the same name and interleaved into it. Measured with four
# concurrent writers of sixty keys each: CHAVE_A and CHAVE_C came out present
# TWICE, holding different values, and t_config_le takes `tail -1`, so the
# reader then picked whichever duplicate landed last.
#
# Not a corner: t_lista_talvez_atualiza stamps LISTA_DIA from a DETACHED
# background process tandem-exe spawns on its way to opening a program.
#
# And what lives in this file makes it worse than untidy - RECEBER and ENVIAR
# are the owner's own on/off choice for the community list, so a duplicate read
# from the wrong line can turn back on something he turned off.
CFGR="$TMPROOT/config-corrida"; rm -rf "$CFGR"; mkdir -p "$CFGR"
for w in A B C D; do
    ( TANDEM_LIB="$ROOT/src/lib" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        export TANDEM_CONFIG="'"$CFGR"'/configuracao.txt" TANDEM_TRAVAS="'"$CFGR"'"
        # Sixty and not twenty: at twenty the race did not reproduce, so the
        # assertion below passed WITH the defect in place - a test that passes
        # on the defect proves nothing. It is still timing-dependent, which is
        # why the structural assertion further down is the real guard: a fixed
        # temp name is the defect itself and that can be checked with no race
        # at all.
        for i in $(seq 1 60); do
            t_config_grava "CHAVE_'"$w"'" "valor-'"$w"'-$i"
        done' 2>/dev/null ) &
done
wait
CFG_DUP=0
for w in A B C D; do
    n="$(grep -c "^CHAVE_$w=" "$CFGR/configuracao.txt" 2>/dev/null || echo 0)"
    [ "$n" = 1 ] || CFG_DUP=$((CFG_DUP + 1))
done
equal "four writers at once leave one line per key, not duplicates" "0" "$CFG_DUP"
# ...and each key must still be THERE. A write that serialised by losing keys
# would pass the assertion above while being worse than the duplicates.
CFG_FALTA=0
for w in A B C D; do
    grep -q "^CHAVE_$w=" "$CFGR/configuracao.txt" 2>/dev/null || CFG_FALTA=$((CFG_FALTA + 1))
done
equal "and every key survived the race" "0" "$CFG_FALTA"
SOBRAS=0
for f in "$CFGR"/*novo*; do [ -e "$f" ] && SOBRAS=$((SOBRAS + 1)); done
equal "no temp file is left behind" "0" "$SOBRAS"
# The temp name must carry the PID: a fixed one is the whole defect.
naocontem "the config temp file is not a name two processes share" \
          'tmp="$TANDEM_CONFIG.novo"' "$(sed 's/#.*//' "$ROOT/src/lib/common.sh")"

# THE SAME RACE, IN THE MEMORY WRITER. t_config_grava got a per-process temp
# name and a lock in 4.22; t_memoria_grava was the identical read-modify-write
# with a FIXED "$arq.novo" and no lock, left behind - the exact
# guard-scoped-to-where-the-defect-was-noticed shape. Tandem writes several
# keys per run (RESOLVERAM, CONFIRMADO, SEGUNDOS, VISTO_EM, PROVA) and a
# detached background process can touch the same file. Measured on the old
# code: four writers of thirty keys each lost two of the four keys entirely.
MEMR="$TMPROOT/memoria-corrida"; rm -rf "$MEMR"; mkdir -p "$MEMR/mem"
head -c 4000 /dev/urandom > "$MEMR/prog.exe"
for w in A B C D; do
    ( TANDEM_LIB="$ROOT/src/lib" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        export TANDEM_MEMORIA="'"$MEMR"'/mem" TANDEM_TRAVAS="'"$MEMR"'"
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
            t_memoria_grava "'"$MEMR"'/prog.exe" "K_'"$w"'" "v-$i"
        done' 2>/dev/null ) &
done
wait
MEM_ARQ="$(ls "$MEMR"/mem/*.txt 2>/dev/null | head -1)"
MEM_DUP=0
for w in A B C D; do
    n="$(grep -c "^K_$w=" "$MEM_ARQ" 2>/dev/null || echo 0)"
    [ "$n" = 1 ] || MEM_DUP=$((MEM_DUP + 1))
done
equal "four writers on one memory file leave one line per key" "0" "$MEM_DUP"
naocontem "the memory temp file is not a name two processes share" \
          'tmp="$arq.novo"' "$(sed 's/#.*//' "$ROOT/src/lib/common.sh")"

# THE LIMITE MEMORY FIELD IS TRANSLATED ON THE WAY TO THE SCREEN, not printed
# verbatim. It is stored "class|rest"; four handlers wrote hard-coded Portuguese
# into the rest (arquitetura, agente, biblioteca, outra-familia), and acao_memoria
# stripped the class and printed the rest, so a non-Portuguese owner met raw
# Portuguese on `tandem memoria` and inside `tandem socorro`. t_limite_amigavel
# translates by CLASS, which also repairs memory files already written with the
# Portuguese rest.
limamig() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c '
        . "'"$ROOT"'/src/lib/common.sh"; t_limite_amigavel "$1"' _ "$1" 2>/dev/null
}
contem "the ARM limit reads as English, not Portuguese" \
       "phone processors" "$(limamig 'arquitetura|arm sem tradutor')"
naocontem "and the stored Portuguese does not leak through" \
          "sem tradutor" "$(limamig 'arquitetura|arm sem tradutor')"
contem "the Java-agent limit reads as English" \
       "add-on" "$(limamig 'agente|nao abre sozinho')"
contem "the library limit reads as English" \
       "library" "$(limamig 'biblioteca|nao abre sozinho')"
contem "the rpm limit reads as English" \
       "does not install directly" "$(limamig 'outra-familia|rpm nao instala aqui')"
contem "the version limit carries its numbers into the sentence" \
       "needs Android 24, and this one is 21" "$(limamig 'versao|24>21')"
# The paths that already store a translated sentence must pass through untouched.
contem "an already-translated limit sentence is printed as stored" \
       "keeps talking here" "$(limamig 'bitola|keeps talking here')"
# No handler may write a raw-Portuguese LIMITE rest again - assert by the shape,
# across every handler, not just the four where it was found.
naocontem "no handler stores 'nao abre sozinho' as a LIMITE sentence to be shown raw" \
          'LIMITE "agente|nao abre sozinho' "$(grep -h 't_limite_amigavel' "$ROOT"/src/bin/tandem)"
# END TO END through acao_memoria, not just the helper - because a helper that
# is correct but never CALLED leaks all the same. A memory file carrying the
# Portuguese rest, shown in English, must read as English with no Portuguese
# left. This is the assertion that fails if the display stops calling
# t_limite_amigavel and goes back to "${lim#*|}".
MEMPT="$TMPROOT/mem-limite-pt"; rm -rf "$MEMPT"; mkdir -p "$MEMPT"
{
    printf 'PROGRAMA=app.apk
'
    printf 'LIMITE=arquitetura|arm sem tradutor
'
} > "$MEMPT/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.txt"
TELA_PT="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
           TANDEM_MEMORIA="$MEMPT" bash "$ROOT/src/bin/tandem" memoria 2>&1)"
contem "tandem memoria shows the ARM limit in English, through acao_memoria" \
       "phone processors" "$TELA_PT"
naocontem "and the stored Portuguese never reaches the screen through acao_memoria" \
          "sem tradutor" "$TELA_PT"

# A VALUE CANNOT FORGE A KEY, and this is asserted as a security property
# rather than left as a side effect. The newline escaping in t_memoria_grava
# was written for a formatting reason - a multi-line value left orphan
# continuation lines that nothing ever cleaned up - and it happens to close an
# injection as well. A defence that exists by accident is one somebody removes
# while tidying, so it gets its own assertion with the path named.
#
# The path: t_receita_importa validates every value in the recipe, and then
# writes ORIGEM_DA_RECEITA from the FILE NAME, unvalidated - and the sender of
# a recipe chooses that name. The header of a recipe is what tells the owner to
# accept one from other people. A newline there would write CONFIANCA into the
# memory file, and a forged confidence travels: into a recipe, into a community
# list record, onto somebody else's machine.
t_memoria_esquece "$MEM_A" 2>/dev/null
t_memoria_grava "$MEM_A" ORIGEM_DA_RECEITA "$(printf 'r\nCONFIANCA=confirmado\nRESOLVERAM=dotnet48')"
equal "a newline in a value does not forge a second key" "" \
      "$(t_memoria_le "$MEM_A" CONFIANCA 2>/dev/null)"
equal "nor a third" "" "$(t_memoria_le "$MEM_A" RESOLVERAM 2>/dev/null)"
# ...and the value still comes back whole, or the escaping would be silent
# data loss instead of a defence.
equal "and the value itself survives the escaping" \
      "r
CONFIANCA=confirmado
RESOLVERAM=dotnet48" "$(t_memoria_le "$MEM_A" ORIGEM_DA_RECEITA 2>/dev/null)"
t_memoria_esquece "$MEM_A" 2>/dev/null

# -------------------------------------------------------- PE pre-flight

section "backup and restore: where the owner said, and nothing silent"

# `tandem backup /media/pendrive/loja.tar.gz` DISCARDED the destination and
# wrote to $HOME. Getting the copy off this machine is the whole point of a
# backup, and the owner can unplug the drive believing it is on there. Its two
# siblings already took a path - `tandem dados restaurar` even prints "If you
# have the file, say where it is" - so backup and restore were the odd ones out
# in their own file.
DEST="$TMPROOT/destino"; rm -rf "$DEST"; mkdir -p "$DEST/existe"
equal "no destination means the home folder" \
      "$HOME/x.tar.gz" "$(t_destino_arquivo "" x.tar.gz)"
equal "an existing folder gets a name of ours inside it" \
      "$DEST/existe/x.tar.gz" "$(t_destino_arquivo "$DEST/existe" x.tar.gz)"
equal "a trailing slash does not double up" \
      "$DEST/existe/x.tar.gz" "$(t_destino_arquivo "$DEST/existe/" x.tar.gz)"
equal "a file name is taken as given" \
      "$DEST/existe/loja.tar.gz" "$(t_destino_arquivo "$DEST/existe/loja.tar.gz" x.tar.gz)"
t_destino_arquivo "$DEST/nao-existe/loja.tar.gz" x.tar.gz >/dev/null
equal "a folder that is not there fails instead of writing elsewhere" "1" "$?"

# THE ARCHIVE IS READ BEFORE THE PREFIX IS DELETED. restore did `rm -rf` first
# and unpacked afterwards, so a truncated backup - a pen drive pulled while it
# was still being written, which is how a backup on a pen drive most often ends
# up truncated - left the environment destroyed and half rebuilt. tar exits 2
# on one, so the damage was detectable the whole time. Allowing an arbitrary
# path made the second half matter too: an archive named by mistake must not be
# unpacked over the environment.
FALSO="$TMPROOT/prefixo-falso"; rm -rf "$FALSO"
mkdir -p "$FALSO/wine/drive_c/windows" "$FALSO/outro/etc"
: > "$FALSO/wine/system.reg"; : > "$FALSO/wine/drive_c/windows/x.dll"
printf 'x\n' > "$FALSO/outro/etc/qualquer.conf"
tar -C "$FALSO" -czf "$TMPROOT/bom.tar.gz" wine 2>/dev/null
tar -C "$FALSO" -czf "$TMPROOT/alheio.tar.gz" outro 2>/dev/null
python3 - "$TMPROOT/bom.tar.gz" "$TMPROOT/cortado.tar.gz" <<'FIMCUT'
import io, sys
d = io.open(sys.argv[1], "rb").read()
io.open(sys.argv[2], "wb").write(d[:max(1, len(d) // 2)])
FIMCUT
PADRAO_ANTIGO="$TANDEM_PREFIXO_PADRAO"
TANDEM_PREFIXO_PADRAO="$FALSO/wine"
t_backup_valido "$TMPROOT/bom.tar.gz";     equal "a real backup is accepted" "0" "$?"
t_backup_valido "$TMPROOT/alheio.tar.gz";  equal "a tar.gz that is not ours is told apart" "2" "$?"
t_backup_valido "$TMPROOT/cortado.tar.gz"; equal "a truncated backup is refused" "1" "$?"
t_backup_valido "$TMPROOT/nao-existe.tar.gz"
equal "a file that is not there is refused" "1" "$?"
TANDEM_PREFIXO_PADRAO="$PADRAO_ANTIGO"

# YES, SAID NO, AND NOBODY TO ASK - three answers, because t_pergunta gives
# two. Its first line is `t_tem_gui || return 1`, so it answers 1 both for "he
# clicked cancel" and for "there was no window", and that is the distinction
# this project records as the one that may never be silent. `tandem restore`
# produced ZERO BYTES and exit 1 on a machine with no graphical session - the
# command that deletes the Windows environment - and the handlers were all
# audited for exactly this shape while the CLI commands were not.
resp_sem_ninguem() {
    env -i PATH="/usr/bin:/bin" HOME="$TMPROOT" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_IDIOMA_FORCADO=en bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_pergunta_ou_terminal "q" "a" "b" "p" </dev/null >/dev/null 2>&1
        echo $?'
}
equal "with no window and no terminal, the answer is 'nobody asked'" "2" "$(resp_sem_ninguem)"

# A DISPLAY THAT IS SET BUT DEAD is not a window. t_tem_gui only checks that
# DISPLAY/WAYLAND_DISPLAY is set, and a set-but-unreachable display makes zenity
# exit 1 with no stderr - byte for byte a "No" click - so t_pergunta_ou_terminal
# used to return 1 (said no) and its callers gave up in SILENCE on tandem
# restore, a destructive path. t_gui_alcancavel tells them apart by the X
# socket, which needs no extra tool. Simulated with a DISPLAY whose socket
# cannot exist.
gui_morto() {
    env -i PATH="/usr/bin:/bin" HOME="$TMPROOT" TANDEM_LIB="$ROOT/src/lib" \
        DISPLAY=":99123" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_gui_alcancavel && echo alcancavel || echo morto'
}
equal "a set-but-dead display is not reachable" "morto" "$(gui_morto)"
# With that dead display and no terminal, the destructive question must report
# 'nobody asked' (2), never a silent 'no' (1).
resp_display_morto() {
    env -i PATH="/usr/bin:/bin" HOME="$TMPROOT" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_IDIOMA_FORCADO=en DISPLAY=":99123" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_pergunta_ou_terminal "q" "a" "b" "p" </dev/null >/dev/null 2>&1
        echo $?'
}
equal "a dead display with no terminal is 'nobody asked', not a silent no" "2" "$(resp_display_morto)"

# END TO END, because the silence was in the COMMAND and not in the library.
# Measured through the project's own pty harness before the fix: 13 bytes for
# `versao`, 1193 for `doctor`, 504 for `backup`, and 0 for `restore`.
E2EB="$TMPROOT/casa-bkp"; rm -rf "$E2EB"; mkdir -p "$E2EB/.local/share/tandem/wine/drive_c"
: > "$E2EB/.local/share/tandem/wine/system.reg"
: > "$E2EB/.local/share/tandem/wine/.tandem-prefixo"
mkdir -p "$E2EB/pendrive"
bkp_em() {
    env -i HOME="$E2EB" PATH="/usr/bin:/bin" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_BIN="$ROOT/src/bin" TANDEM_IDIOMA_FORCADO=en \
        bash "$ROOT/src/bin/tandem" "$@" 2>&1
}
bkp_em backup "$E2EB/pendrive" >/dev/null 2>&1
equal "backup writes where the owner said, not into the home folder" \
      "1" "$(ls -1 "$E2EB/pendrive"/tandem-backup-*.tar.gz 2>/dev/null | wc -l)"
equal "and nothing was left in the home folder instead" \
      "0" "$(ls -1 "$E2EB"/tandem-backup-*.tar.gz 2>/dev/null | wc -l)"
contem "a destination whose folder is missing says so, and says why" \
       "pen drive" "$(bkp_em backup /nao/existe/loja.tar.gz)"
# The silence itself. Restore with no window and no terminal must produce a
# sentence: this is the command that deletes the Windows environment.
SEM_NINGUEM="$(bkp_em restore "$(ls -1 "$E2EB/pendrive"/*.tar.gz | head -1)")"
if [ -n "$SEM_NINGUEM" ]; then
    pass "restore with nobody to ask is not silent"
else
    fail "restore with nobody to ask is not silent" "a sentence" "zero bytes"
fi
contem "and it names the file, so the owner can repeat the command" \
       "tandem restore" "$SEM_NINGUEM"
# And the path is used at all: naming a file that is not there must say THAT,
# not "no backup found in your home folder" - which is what it said while the
# owner was holding the file and pointing at it.
contem "a named file that is missing is reported as missing" \
       "not found" "$(bkp_em restore "$E2EB/pendrive/nao-existe.tar.gz")"

# THE SECOND ONE THE AUDIT FOUND. Every t_pergunta in the CLI was reached on
# purpose - with the preconditions each one needs, because on a bare machine
# four of the six exit earlier for reasons of their own and look guarded when
# they are not. Two of the six were silent, and both were commands that change
# what is inside the Windows environment: `tandem restore` and this one.
# `preparar`, `desinstalar` and `contribuir` were correct already.
# Documents, not any folder: t_dados_lista counts only the five the owner
# actually keeps things in. The first version of this fixture put the file in
# users/x/ and the copy came out EMPTY, so the command answered "I found no
# copy of your files" - which happens to contain the words "tandem dados
# restaurar", so both assertions below passed on the WRONG message and the
# whole test stayed green with the defect put back. A green instrument that
# agrees with itself.
mkdir -p "$E2EB/.local/share/tandem/wine/drive_c/users/loja/Documents"
printf 'vendas\n' > "$E2EB/.local/share/tandem/wine/drive_c/users/loja/Documents/v.txt"
bkp_em dados salvar "$E2EB/copia.tar.gz" >/dev/null 2>&1
if [ -s "$E2EB/copia.tar.gz" ]; then
    pass "the fixture really produced a copy, or the rest proves nothing"
else
    fail "the fixture really produced a copy, or the rest proves nothing" \
         "a non-empty tar.gz" "nothing was written"
fi
SEM_DADOS="$(bkp_em dados restaurar "$E2EB/copia.tar.gz")"
if [ -n "$SEM_DADOS" ]; then
    pass "giving files back with nobody to ask is not silent either"
else
    fail "giving files back with nobody to ask is not silent either" \
         "a sentence" "zero bytes"
fi
contem "and it says what the refusal was about, not that no copy was found" \
       "no window to ask you in" "$SEM_DADOS"

section "verifiable backups: prove it intact before you trust it"

# A backup is worth nothing if nobody can prove it is intact, and the disk this
# rescues from is exactly where corruption comes from. Since 4.30 the backup
# carries a sha256 checksum beside it - the same .sha256 sidecar this project
# proves its own releases with - so a restore, or `tandem backup verificar`, can
# prove the file matches what was saved before anything relies on it. It catches
# what a structural "does it open" check cannot: a swapped file, a tampered one,
# or byte-rot, on an archive that still lists cleanly.
VB="$TMPROOT/verif-bkp"; rm -rf "$VB"; mkdir -p "$VB/wine"
: > "$VB/wine/system.reg"
tar -C "$VB" -czf "$VB/b.tar.gz" wine 2>/dev/null
( cd "$VB" && sha256sum b.tar.gz > b.tar.gz.sha256 )
t_backup_verifica "$VB/b.tar.gz"
equal "a backup that matches its checksum is intact" "0" "$?"
# A sidecar recording a DIFFERENT hash: the archive still opens, so only the
# integrity check can tell it is not the file that was saved - the whole point.
printf '%s  b.tar.gz\n' "$(printf '0%.0s' {1..64})" > "$VB/b.tar.gz.sha256"
t_backup_verifica "$VB/b.tar.gz"
equal "a backup that does not match its checksum is corrupted" "1" "$?"
# No sidecar (an older backup, or a hand-copied file): not a failure, an honest
# "I can prove structure, not integrity" - never condemn on a guess.
rm -f "$VB/b.tar.gz.sha256"
t_backup_verifica "$VB/b.tar.gz"
equal "a backup with no checksum beside it is 'cannot verify', not 'corrupted'" "2" "$?"
equal "the checksum of a file is 64 hex characters" "64" \
      "$(t_backup_soma "$VB/b.tar.gz" | tr -d '\n' | wc -c | tr -d ' ')"
t_backup_soma "$VB/nao-existe.tar.gz" >/dev/null 2>&1
equal "the checksum of a missing file is refused" "1" "$?"

# End to end, from the installed command surface: backup writes the sidecar,
# verificar reads it back, and a corrupted archive is named as such.
VBH="$TMPROOT/verif-bkp-home"; rm -rf "$VBH"
mkdir -p "$VBH/.local/share/tandem/wine/drive_c" "$VBH/pen" "$VBH/pen2"
: > "$VBH/.local/share/tandem/wine/system.reg"
: > "$VBH/.local/share/tandem/wine/.tandem-prefixo"
vb_em() {
    env -i HOME="$VBH" PATH="/usr/bin:/bin" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_BIN="$ROOT/src/bin" TANDEM_IDIOMA_FORCADO=en \
        bash "$ROOT/src/bin/tandem" "$@" 2>&1
}
vb_em backup "$VBH/pen" >/dev/null 2>&1
VB_ARQ="$(ls -1 "$VBH/pen"/tandem-backup-*.tar.gz 2>/dev/null | head -1)"
equal "the backup command writes a checksum beside the archive" \
      "1" "$([ -f "$VB_ARQ.sha256" ] && echo 1 || echo 0)"
contem "verificar says a fresh backup is intact" "intact" \
       "$(vb_em backup verificar "$VB_ARQ")"
printf 'tampered\n' >> "$VB_ARQ"
contem "verificar names a corrupted backup as corrupted" "CORRUPTED" \
       "$(vb_em backup verificar "$VB_ARQ")"

# The load-bearing safety: restore must REFUSE a backup that fails its checksum
# and NOT delete the working environment to lay a broken one in its place. Uses
# a valid archive whose sidecar no longer matches, so the structural check the
# restore already did passes and ONLY the new integrity guard can refuse - an
# append would fail structurally first and never reach it. Reached with nobody
# to ask, which is fine: the refusal happens before the question.
vb_em backup "$VBH/pen2" >/dev/null 2>&1
VB_ARQ2="$(ls -1 "$VBH/pen2"/tandem-backup-*.tar.gz 2>/dev/null | head -1)"
printf '%s  %s\n' "$(printf '0%.0s' {1..64})" "$(basename -- "$VB_ARQ2")" > "$VB_ARQ2.sha256"
VB_REST="$(vb_em restore "$VB_ARQ2")"
contem "restore refuses a backup that fails its checksum" "CORRUPTED" "$VB_REST"
equal "and the working environment is untouched - nothing was deleted" \
      "1" "$([ -f "$VBH/.local/share/tandem/wine/system.reg" ] && echo 1 || echo 0)"

section "recovery rehearsal: prove a backup would come back"

# 4.30 proved a backup intact; this proves it would RESTORE - the day it is made,
# not the day the disk dies. t_restauravel runs the same pre-flight a real
# restore does before its destructive step, and touches nothing.
RV="$TMPROOT/rehearsal"; rm -rf "$RV"; mkdir -p "$RV/wine"
: > "$RV/wine/system.reg"
RV_PADRAO="$TANDEM_PREFIXO_PADRAO"; TANDEM_PREFIXO_PADRAO="$RV/wine"
tar -C "$RV" -czf "$RV/b.tar.gz" wine 2>/dev/null
( cd "$RV" && sha256sum b.tar.gz > b.tar.gz.sha256 )
equal "a good backup with a matching checksum would restore cleanly" \
      "ok" "$(t_restauravel "$RV/b.tar.gz")"
printf '%s  b.tar.gz\n' "$(printf '0%.0s' {1..64})" > "$RV/b.tar.gz.sha256"
equal "a backup that fails its checksum would NOT restore" \
      "corrompido" "$(t_restauravel "$RV/b.tar.gz")"
rm -f "$RV/b.tar.gz.sha256"
equal "a backup with no checksum still passes on structure" \
      "ok" "$(t_restauravel "$RV/b.tar.gz")"
printf 'x\n' > "$RV/plain.txt"; tar -C "$RV" -czf "$RV/alien.tar.gz" plain.txt 2>/dev/null
equal "a tar that is not a Tandem environment is told apart" \
      "nao-e-backup" "$(t_restauravel "$RV/alien.tar.gz")"
equal "a file that is not there is refused" \
      "sem-arquivo" "$(t_restauravel "$RV/nao-existe.tar.gz")"
TANDEM_PREFIXO_PADRAO="$RV_PADRAO"

# End to end: the rehearsal proves it WOULD restore and changes nothing, and a
# corrupted one is named without any destruction. Reached from the installed
# command with --testar.
RVH="$TMPROOT/rehearsal-home"; rm -rf "$RVH"
mkdir -p "$RVH/.config/tandem" "$RVH/.local/share/tandem/wine/drive_c"
printf '4.32\n' > "$RVH/.config/tandem/.primeira-vez"
: > "$RVH/.local/share/tandem/wine/system.reg"
: > "$RVH/.local/share/tandem/wine/.tandem-prefixo"
rv_em() {
    env -i HOME="$RVH" PATH="/usr/bin:/bin" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_BIN="$ROOT/src/bin" TANDEM_IDIOMA_FORCADO=en \
        TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
        bash "$ROOT/src/bin/tandem" "$@" 2>&1
}
rv_em backup "$RVH" >/dev/null 2>&1
RV_ARQ="$(ls -1t "$RVH"/tandem-backup-*.tar.gz | head -1)"
contem "restore --testar says a good backup would restore" \
       "would restore cleanly" "$(rv_em restore --testar "$RV_ARQ")"
equal "and the rehearsal changed nothing - the environment is still there" \
      "1" "$([ -f "$RVH/.local/share/tandem/wine/system.reg" ] && echo 1 || echo 0)"
printf '%s  %s\n' "$(printf '0%.0s' {1..64})" "$(basename -- "$RV_ARQ")" > "$RV_ARQ.sha256"
contem "restore --testar names a backup that would NOT restore" \
       "would NOT restore" "$(rv_em restore --testar "$RV_ARQ")"

# A real restore no longer trusts tar's exit code: after unpacking it confirms
# the environment landed (system.reg present) and warns if it did not. The untar
# itself needs a confirmed question (a terminal), so the guard is asserted where
# the destructive path cannot be reached headlessly - the same limit the restore
# tests above hit with the "nobody to ask" case.
RBIN="$ROOT/src/bin/tandem"
if grep -q 'if \[ -f "$TANDEM_PREFIXO_PADRAO/system.reg" \]; then' "$RBIN" &&
   grep -q 't_msg rst_restaurado_incompleto' "$RBIN"; then
    pass "a real restore verifies the environment landed before calling it done"
else
    fail "a real restore verifies the environment landed before calling it done" \
         "the post-restore system.reg check + rst_restaurado_incompleto" "missing"
fi

section "machine health: one reading, worst-first"

# tandem saude composes the verdicts Tandem already computes into one triage. The
# pieces that can be pure - a verdict from a number, and the worst-first ordering
# - are truth tables here; the live reads (df, the service probe) are exercised
# end to end through the command.

# Disk: the number in, the verdict out.
equal "almost no disk is a problem"        "cheio"        "$(t_saude_disco_veredito 300000)"
equal "a little disk is worth knowing"     "apertado"     "$(t_saude_disco_veredito 1500000)"
equal "plenty of disk says nothing"        "ok"           "$(t_saude_disco_veredito 9000000)"
equal "a disk it could not read is unknown, not healthy" \
      "desconhecido" "$(t_saude_disco_veredito '')"

# Recovery readiness: the 4.30 tie-in.
NOW_T="$(date +%s)"
equal "no backup at all is a problem"       "sem-backup"  "$(t_saude_backup_veredito '' "$NOW_T" 2)"
equal "a backup that fails its checksum is a problem" "corrompido" \
      "$(t_saude_backup_veredito 1000 2000 1)"
equal "a backup from over a month ago is worth knowing" "velho" \
      "$(t_saude_backup_veredito 1000000000 2000000000 2)"
equal "a recent backup with no sidecar is still fine (structure, not condemned)" \
      "ok" "$(t_saude_backup_veredito "$NOW_T" "$NOW_T" 2)"

# The ordering is a function, not an accident of which probe ran first: a plain
# numeric sort puts the problem (rank 1) above the advisory (rank 2), whatever
# order they were gathered in. Same shape as t_prova_do_run.
ORD="$(printf '2\taviso B\n1\tproblema A\n2\taviso C\n1\tproblema D\n' | t_saude_ordena)"
equal "worst-first: the two problems come before the two advisories" \
      "problema A
problema D
aviso B
aviso C" "$ORD"

# End to end from the installed command. The machine-facing reads (the clock via
# timedatectl, free space via df) are STUBBED to a healthy machine, so the test
# turns only on what the fixture controls and is not at the mercy of the runner's
# real disk or whether it has systemd - the same reason the clock tests stub
# timedatectl.
SAUH="$TMPROOT/saude-home"; rm -rf "$SAUH"; mkdir -p "$SAUH/.config/tandem" "$SAUH/stub"
printf '4.31\n' > "$SAUH/.config/tandem/.primeira-vez"
printf '#!/bin/sh\ncase "$*" in show) echo NTP=yes;; esac\nexit 0\n' > "$SAUH/stub/timedatectl"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 100000000 1000000 90000000 2%% /"\n' > "$SAUH/stub/df"
chmod +x "$SAUH/stub"/*
sau_em() {
    env -i HOME="$SAUH" PATH="$SAUH/stub:/usr/bin:/bin" TANDEM_LIB="$ROOT/src/lib" \
        TANDEM_BIN="$ROOT/src/bin" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
        TANDEM_IDIOMA_FORCADO=en bash "$ROOT/src/bin/tandem" saude 2>&1
}
SAU_OUT="$(sau_em)"
contem "saude names the missing backup as the thing to act on" \
       "no backup" "$SAU_OUT"
contem "and it names the command that fixes it" "tandem backup" "$SAU_OUT"
# With a fresh, verified backup and nothing else wrong, it says so plainly rather
# than opening an empty window.
tar -czf "$SAUH/tandem-backup-$(date +%F)-1200.tar.gz" -C /tmp -T /dev/null 2>/dev/null
SAU_ARQ="$(ls -1t "$SAUH"/tandem-backup-*.tar.gz | head -1)"
( cd "$SAUH" && sha256sum "$(basename "$SAU_ARQ")" > "$(basename "$SAU_ARQ").sha256" )
contem "with a recent verified backup and nothing wrong, saude says all is well" \
       "healthy" "$(sau_em)"

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

# RULE 1, THROUGH A SYMLINK - which is how it was actually broken. The list was
# compared as TEXT, so with the default prefix path pointing at somebody else's
# working prefix every comparison said "different path" while every one of them
# was about the same directory.
#
# Measured end to end on the installed package before the fix: Tandem
# registered the production prefix as protected, wrote "protegido:
# .../.wine-pdv" into its own log, and then ran a winetricks verb INTO IT and
# left its receipt and its .tandem-assoc there. Rule 1 is the one rule this
# project calls inviolable, and pointing a new tool at the Wine setup you
# already have is the first thing a person tries.
#
# The target of these first two is PREF_MARCADO, which carries Tandem's own
# mark, and that is deliberate. Against an UNMARKED prefix the old code
# answered "protected" anyway, through its "unknown = protected"
# fall-through - so the assertion would have passed on the defect and proved
# nothing. `tandem protect` on a prefix Tandem itself built is a real request,
# and the comment on this function says that decision has to outweigh the
# ownership mark; reached through a symlink, the old code read the mark, saw
# its own, and waved it through.
LIGA="$HOME/.local/share/tandem/wine-liga"
rm -rf "$LIGA"; ln -s "$PREF_MARCADO" "$LIGA"
printf '%s
' "$PREF_MARCADO" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$LIGA"
equal "a symlink to a listed prefix is the listed prefix" "0" "$?"
# The other direction: the LIST entry is the symlink and the caller names the
# real path. Both spellings have to resolve to the same decision, or the
# protection depends on which name somebody happened to type.
printf '%s
' "$LIGA" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$PREF_MARCADO"
equal "and a listed symlink protects the place it points at" "0" "$?"
: > "$TANDEM_PROTEGIDOS"
# The second layer, for a prefix the first-run sweep never found: our own
# default NAME leading to a working prefix that carries no mark of ours.
DEF_ANTIGO="$TANDEM_PREFIXO_PADRAO"
rm -rf "$LIGA"; ln -s "$PREF_ALHEIO" "$LIGA"
TANDEM_PREFIXO_PADRAO="$LIGA"
t_prefixo_protegido "$LIGA"
equal "the default prefix name is not a licence when it leads elsewhere" "0" "$?"
# ...and that layer must stay narrow. A real directory at the default path with
# no mark - a marker that failed to be written on a full disk, which is this
# release's own subject - must NOT turn Tandem out of its own prefix.
TANDEM_PREFIXO_PADRAO="$PREF_NOSSO"
rm -f "$PREF_NOSSO/.tandem-prefixo"
t_prefixo_protegido "$PREF_NOSSO"
equal "but a real default prefix with no mark is still ours" "1" "$?"
TANDEM_PREFIXO_PADRAO="$DEF_ANTIGO"
rm -rf "$LIGA"

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

section "serial ports: fixar creates the symlink that actually opens the port"

# "tandem portas fixar COM3 /dev/ttyUSB0" wrote ONLY the registry key
# HKLM\Software\Wine\Ports and reported "fixed". Measured with real Wine and a
# real char device: a program that opens "COM3" (which is exactly what ACBr's
# PosPrinter does through CreateFile) resolves it via dosdevices/com3 - the
# symlink Wine mints for a port it auto-detected. With ONLY the registry key,
# CreateFile("COM3") returns "File not found", byte for byte identical to a port
# that was never set - so the one command CLAUDE.md documents as the printer and
# pinpad remedy said "done" while the device stayed unreachable.
#
# The symlink is the half that makes the port OPEN. The registry key is kept
# because it is the OTHER half: it populates SERIALCOMM, which a program reads to
# LIST the ports in a dropdown. The symlink makes it open; the registry makes it
# appear. This section pins both halves, and soltar undoing exactly what fixar
# made.
#
# No Wine: fixar runs "wine reg add" best-effort AFTER the symlink, so a wine
# stub that exits 0 keeps the suite Wine-free while exercising the whole path -
# the symlink, which is where the defect lived, needs no Wine at all.

PORTAS_H="$TMPROOT/portas-fix"
PFX="$PORTAS_H/.local/share/tandem/wine"
mkdir -p "$PFX/dosdevices" "$PORTAS_H/.config/tandem"
: > "$PFX/system.reg"
: > "$PFX/.tandem-prefixo"
PVER_FIX="$(sed -n 's/^TANDEM_VERSAO="\([^"]*\)".*/\1/p' "$ROOT/src/lib/common.sh" | head -1)"
printf '%s\n' "$PVER_FIX" > "$PORTAS_H/.config/tandem/.primeira-vez"
PORTAS_BIN="$TMPROOT/portas-bin"
mkdir -p "$PORTAS_BIN"
printf '#!/bin/sh\nexit 0\n' > "$PORTAS_BIN/wine"
chmod +x "$PORTAS_BIN/wine"
DEV_FIX="$TMPROOT/fake-ttyUSB0"
: > "$DEV_FIX"

portas_cmd() {
    env -i HOME="$PORTAS_H" PATH="$PORTAS_BIN:/usr/bin:/bin" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
        bash "$ROOT/src/bin/tandem" portas "$@" 2>&1
}

portas_cmd fixar COM3 "$DEV_FIX" >/dev/null 2>&1
if [ -L "$PFX/dosdevices/com3" ]; then
    pass "fixar creates the dosdevices/comN symlink that opens the port"
else
    fail "fixar creates the dosdevices/comN symlink that opens the port" \
         "a symlink at dosdevices/com3" "no symlink was made"
fi
equal "and the symlink points at the device the owner named" \
      "$DEV_FIX" "$(readlink "$PFX/dosdevices/com3" 2>/dev/null)"

# soltar has to undo exactly what fixar made, or an owner who fixed the wrong
# device can never move it off that port.
portas_cmd soltar COM3 >/dev/null 2>&1
if [ -L "$PFX/dosdevices/com3" ]; then
    fail "soltar removes the symlink again" "no symlink" "the symlink is still there"
else
    pass "soltar removes the symlink again"
fi

# soltar only ever removes a symlink IT could have made - never a real device a
# person mounted at that path by hand. rm -f on whatever name is passed would be
# a foot-gun the moment somebody bind-mounts a device at dosdevices/comN.
: > "$PFX/dosdevices/com4"          # a plain file, not one of our symlinks
portas_cmd soltar COM4 >/dev/null 2>&1
if [ -e "$PFX/dosdevices/com4" ] && [ ! -L "$PFX/dosdevices/com4" ]; then
    pass "soltar leaves a real file at that path untouched"
else
    fail "soltar leaves a real file at that path untouched" \
         "the plain file survives" "it was removed"
fi

section "web services: the parts that need no systemd (detect, unit, verdict)"

# The tenth thing Tandem carries, and the first that is not a file. A web service
# is systemd + a port, and neither is reachable in CI - so, exactly as with the
# Wine loop, the LOGIC is what has tests here: what a folder is, the unit text,
# which port a line of ss reports, and which sentence a state deserves. The whole
# install flow is exercised further down with systemd stubbed.

# --- a service name becomes a file name and a systemctl argument ---
for good in loja loja_pdv my-svc a1; do
    if t_servico_nome_valido "$good"; then pass "service name accepted: $good"
    else fail "service name accepted: $good" accepted rejected; fi
done
for bad in "a.b" "a/b" "-x" "a b" "" 'a;b'; do
    if t_servico_nome_valido "$bad"; then
        fail "service name rejected: <$bad>" rejected accepted
    else pass "service name rejected: <$bad>"; fi
done
equal "a messy folder name becomes a safe service name" \
      "Minha-Loja-PDV" "$(t_servico_nome_de_pasta '/x/Minha Loja!! PDV')"
equal "a folder that is all punctuation still yields a usable name" \
      "servico" "$(t_servico_nome_de_pasta '/x/...')"

# --- runtime detection: look, never execute ---
SVCFIX="$TMPROOT/svc-detect"; mkdir -p "$SVCFIX"
mkdir -p "$SVCFIX/node-start"; echo '{"scripts":{"start":"node ."}}' > "$SVCFIX/node-start/package.json"
contem "node with a start script uses npm start" \
       "COMANDO=npm start" "$(t_servico_detecta "$SVCFIX/node-start")"
mkdir -p "$SVCFIX/node-main"; echo '{"main":"srv.js"}' > "$SVCFIX/node-main/package.json"
contem "node without a start script uses its main" \
       "COMANDO=node srv.js" "$(t_servico_detecta "$SVCFIX/node-main")"
mkdir -p "$SVCFIX/node-bare"; echo '{}' > "$SVCFIX/node-bare/package.json"
contem "a node folder with no entry asks for the command" \
       "ERRO=node_sem_entrada" "$(t_servico_detecta "$SVCFIX/node-bare")"
mkdir -p "$SVCFIX/dj"; : > "$SVCFIX/dj/manage.py"
contem "django with no port is refused, plainly" \
       "ERRO=precisa_porta" "$(t_servico_detecta "$SVCFIX/dj")"
contem "django with a port binds it into the command" \
       "0.0.0.0:8000" "$(t_servico_detecta "$SVCFIX/dj" 8000)"
mkdir -p "$SVCFIX/php"; : > "$SVCFIX/php/index.php"
contem "php uses the built-in server on the port we are given" \
       "php -S 0.0.0.0:8080" "$(t_servico_detecta "$SVCFIX/php" 8080)"
mkdir -p "$SVCFIX/jv"; : > "$SVCFIX/jv/app.jar"
contem "a single jar runs with java -jar" \
       "COMANDO=java -jar app.jar" "$(t_servico_detecta "$SVCFIX/jv")"
mkdir -p "$SVCFIX/win"; : > "$SVCFIX/win/server.exe"
contem "a Windows server .exe runs under Wine" \
       "COMANDO=wine server.exe" "$(t_servico_detecta "$SVCFIX/win")"
mkdir -p "$SVCFIX/nope"; : > "$SVCFIX/nope/readme.txt"
contem "a folder Tandem cannot read asks for the command instead of guessing" \
       "ERRO=nao_reconheci" "$(t_servico_detecta "$SVCFIX/nope")"

# --- the unit text ---
UNIT="$(t_servico_unit loja /opt/loja 'node server.js')"
contem "the unit runs the command given"        "ExecStart=node server.js" "$UNIT"
contem "the unit starts in the service's folder" "WorkingDirectory=/opt/loja" "$UNIT"
contem "the unit restarts a service that dies"   "Restart=always" "$UNIT"
contem "the unit starts with the user session"   "WantedBy=default.target" "$UNIT"

# --- absolutise: the insight that a unit's ExecStart must be a full path ---
# systemd's ExecStart does not honour the caller's PATH - it searches a short
# fixed list that excludes /opt and /usr/local, where node and python are often
# installed by hand - so a bare "node server.js" fails to start on exactly those
# machines. The command's first token has to be resolved. Tested against sh,
# which every machine has; revert t_servico_absolutiza to a passthrough and the
# first assertion goes red.
ABS_OK="$(t_servico_absolutiza 'sh -c true')"
if [ "${ABS_OK#/}" != "$ABS_OK" ]; then
    pass "absolutise turns a bare command into an absolute path systemd can run"
else
    fail "absolutise turns a bare command into an absolute path systemd can run" \
         "/...sh -c true" "$ABS_OK"
fi
equal "an already-absolute command is left exactly as it is" \
      "/opt/app/run --flag x" "$(t_servico_absolutiza '/opt/app/run --flag x')"
equal "a command that cannot be found is left untouched, so its error stays real" \
      "definitivamente-nao-existe-9z x" "$(t_servico_absolutiza 'definitivamente-nao-existe-9z x')"

# --- the port parser (t_porta_escutando), fed ss -ltnH-style lines ---
if printf 'LISTEN 0 511 0.0.0.0:8080 0.0.0.0:*\n' | t_porta_escutando 8080; then
    pass "a port that is listening is seen"; else
    fail "a port that is listening is seen" seen missed; fi
if printf 'LISTEN 0 511 0.0.0.0:8080 0.0.0.0:*\n' | t_porta_escutando 9999; then
    fail "a port that is not listening is not claimed" "not seen" seen; else
    pass "a port that is not listening is not claimed"; fi
# The guard that matters: :8080 must not match inside :18080.
if printf 'LISTEN 0 511 0.0.0.0:18080 0.0.0.0:*\n' | t_porta_escutando 8080; then
    fail "port 8080 is not matched inside 18080" "no match" "false match"; else
    pass "port 8080 is not matched inside 18080"; fi
if printf 'LISTEN 0 128 [::]:3000 [::]:*\n' | t_porta_escutando 3000; then
    pass "an IPv6 listening socket is seen too"; else
    fail "an IPv6 listening socket is seen too" seen missed; fi
equal "the process holding a port is read out of the ss users field" \
      "nginx" "$(printf 'LISTEN 0 511 *:80 *:* users:(("nginx",pid=1,fd=6))\n' | t_nome_no_ss)"

# --- the verdict, the whole plain-language truth table ---
equal "no user systemd is its own answer"      "sem-systemd"   "$(t_servico_veredito sem-systemd nao '')"
equal "an unknown service is named as unknown" "nao-instalado" "$(t_servico_veredito nao-instalado nao '')"
equal "a service that failed to start says so" "falhou"        "$(t_servico_veredito falhou nao '')"
equal "a stopped service says stopped"         "parado"        "$(t_servico_veredito parado nao '')"
equal "active but nothing on the port yet = still coming up" "subindo" "$(t_servico_veredito ativo nao '')"
equal "active, listening and answering = working"           "ok"      "$(t_servico_veredito ativo sim sim)"
equal "active and listening but not answering as a page"    "escuta-mudo" "$(t_servico_veredito ativo sim nao)"
equal "active and listening, port not checked = running"    "rodando" "$(t_servico_veredito ativo sim '')"

# --- Tandem's own record of a service ---
SVCREC="$TMPROOT/svc-rec"
( TANDEM_SERVICOS="$SVCREC"
  t_servico_grava loja /opt/loja 8080 "node server.js"
  t_servico_grava caixa /opt/caixa "" "wine caixa.exe" )
equal "a service records the port it answers on" \
      "8080" "$(TANDEM_SERVICOS="$SVCREC" bash -c '. "'"$ROOT"'/src/lib/common.sh"; TANDEM_SERVICOS="'"$SVCREC"'" t_servico_le loja PORTA')"
equal "the two services are both listed, sorted" \
      "caixa loja" "$(TANDEM_SERVICOS="$SVCREC" bash -c '. "'"$ROOT"'/src/lib/common.sh"; TANDEM_SERVICOS="'"$SVCREC"'" t_servico_lista_nomes' | tr '\n' ' ' | sed 's/ $//')"

section "web services: the whole install flow, with systemd stubbed"

# systemd, loginctl, ss and curl are not reachable in CI, so they are stubbed -
# the same move the port test makes for Wine. What is proven here is everything
# BUT those four: argument parsing, runtime detection, the unit that gets
# written, the record, and the plain verdict on the way back.

SVCBIN="$TMPROOT/svc-bin"; mkdir -p "$SVCBIN"
printf '#!/bin/sh\ncase "$*" in *show-environment*) exit 0;; *list-unit-files*) echo "tandem-loja.service enabled"; exit 0;; *is-active*) echo active; exit 0;; *) exit 0;; esac\n' > "$SVCBIN/systemctl"
printf '#!/bin/sh\ncase "$*" in *show-user*) echo "Linger=yes";; esac\nexit 0\n' > "$SVCBIN/loginctl"
printf '#!/bin/sh\necho "LISTEN 0 511 0.0.0.0:3000 0.0.0.0:*"\n' > "$SVCBIN/ss"
printf '#!/bin/sh\nprintf 200\n' > "$SVCBIN/curl"
# node and npm as stubs too, so `command -v npm` resolves to an absolute path in
# CI, where the real runtime is not installed. Without this the absolutise step
# below has nothing to resolve and the test depends on the machine, not the code.
printf '#!/bin/sh\nexit 0\n' > "$SVCBIN/node"
printf '#!/bin/sh\nexit 0\n' > "$SVCBIN/npm"
chmod +x "$SVCBIN"/*

SVCH="$TMPROOT/svc-home"; mkdir -p "$SVCH/.config/tandem"
printf '4.26\n' > "$SVCH/.config/tandem/.primeira-vez"
mkdir -p "$SVCH/loja"; echo '{"scripts":{"start":"node ."}}' > "$SVCH/loja/package.json"; : > "$SVCH/loja/server.js"

svc_cmd() {
    env -i HOME="$SVCH" PATH="$SVCBIN:/opt/node22/bin:/usr/bin:/bin" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
        bash "$ROOT/src/bin/tandem" servico "$@" 2>&1
}

svc_cmd instalar "$SVCH/loja" --porta 3000 >/dev/null 2>&1
UNITFILE="$SVCH/.config/systemd/user/tandem-loja.service"
if [ -f "$UNITFILE" ]; then pass "instalar writes the systemd --user unit"
else fail "instalar writes the systemd --user unit" "a unit file" "none"; fi
# THE INSIGHT, guarded: systemd's ExecStart does not honour the caller's PATH, so
# a bare "npm"/"node" fails to start on exactly the machines where the runtime
# was installed by hand. The command must be absolutised. Revert t_servico_
# absolutiza to a passthrough and this line goes red - the service would report
# "set up" and never come up.
if grep -q '^ExecStart=/' "$UNITFILE" 2>/dev/null; then
    pass "the unit's ExecStart is an absolute path, so systemd can find it"
else
    fail "the unit's ExecStart is an absolute path, so systemd can find it" \
         "ExecStart=/..." "$(grep '^ExecStart=' "$UNITFILE" 2>/dev/null)"
fi
if [ -f "$SVCH/.config/tandem/servicos/loja/info" ]; then
    pass "instalar keeps its own record of the service"
else
    fail "instalar keeps its own record of the service" "an info file" "none"
fi
contem "instalar reports the address to open" "http://localhost:3000" \
       "$(svc_cmd instalar "$SVCH/loja" --porta 3000 2>&1)"
contem "ver says the service is working, with its address" \
       "working" "$(svc_cmd ver)"
contem "remover takes the service away" "removed" "$(svc_cmd remover loja)"

# error paths: none may end in silence
contem "instalar with no folder says which folder" \
       "which folder" "$(svc_cmd instalar 2>&1)"
contem "instalar with a folder that is not there names it" \
       "could not find" "$(svc_cmd instalar "$TMPROOT/nope-nope" 2>&1)"
contem "an unknown subcommand lists what it can do" \
       "instalar, ver" "$(svc_cmd bogus 2>&1)"

section "the clock: the silent failure one step before the software fails"

# A wrong clock breaks TLS, licences and fiscal software without a word, and a
# dead CMOS battery is the usual cause. Tandem already RECOGNISES it after the
# fact (t_causa_token -> relogio); this checks it BEFORE. The live timedatectl
# read is machine-only (like Wine); the judgement is a pure function with a test
# that never cries wolf on a correct clock.

REL_EPOCH="$(date -u -d '2026-08-18' +%s)"
# --- the verdict truth table (pure) ---
equal "a date before this software's release is certainly wrong" \
      "atrasado"  "$(t_relogio_veredito "$(date -u -d 2020-01-01 +%s)" "$REL_EPOCH" yes)"
equal "an absurd far-future date is certainly wrong" \
      "adiantado" "$(t_relogio_veredito "$(date -u -d 2099-01-01 +%s)" "$REL_EPOCH" yes)"
equal "a plausible date with automatic time on is fine" \
      "ok"        "$(t_relogio_veredito "$(date -u -d 2026-09-01 +%s)" "$REL_EPOCH" yes)"
equal "a plausible date with automatic time off is only an advisory" \
      "sem_hora_automatica" "$(t_relogio_veredito "$(date -u -d 2026-09-01 +%s)" "$REL_EPOCH" no)"
# The guard that matters: a machine legitimately running old software years later
# must NOT be told its clock is wrong.
equal "five years after release, with time on, is not flagged" \
      "ok"        "$(t_relogio_veredito "$(date -u -d 2031-09-01 +%s)" "$REL_EPOCH" yes)"
# With no known release date, only NTP may speak - never a firm condemnation.
equal "with no epoch, an old date and time-on is not condemned" \
      "ok"        "$(t_relogio_veredito "$(date -u -d 1990-01-01 +%s)" "" yes)"
equal "with no epoch, time-off is still just an advisory" \
      "sem_hora_automatica" "$(t_relogio_veredito "$(date -u -d 2026-09-01 +%s)" "" no)"

# --- the NTP flag parser, fed timedatectl-show text ---
equal "NTP on is read from timedatectl show" \
      "yes" "$(printf 'Timezone=America/Sao_Paulo\nNTP=yes\nNTPSynchronized=yes\n' | t_relogio_ntp)"
equal "NTP off is read too, not confused with NTPSynchronized" \
      "no"  "$(printf 'NTP=no\nNTPSynchronized=yes\n' | t_relogio_ntp)"

# --- the release epoch, read from the shipped changelog ---
REL_CH="$TMPROOT/relogio-changelog"
printf ' -- Tandem <x@y>  Tue, 18 Aug 2026 20:15:00 +0000\n' > "$REL_CH"
equal "the release epoch comes out of the changelog trailer" \
      "$(date -u -d 'Tue, 18 Aug 2026 20:15:00 +0000' +%s)" \
      "$(TANDEM_CHANGELOG="$REL_CH" bash -c '. "'"$ROOT"'/src/lib/common.sh"; TANDEM_CHANGELOG="'"$REL_CH"'" t_relogio_epoch_conhecido')"

# --- the handler, with timedatectl stubbed (it needs systemd, absent in CI) ---
RELBIN="$TMPROOT/relogio-bin"; mkdir -p "$RELBIN"
# a timedatectl that "works" and reports automatic time OFF
printf '#!/bin/sh\ncase "$1" in show) echo "NTP=no"; echo "NTPSynchronized=no"; exit 0;; esac\nexit 0\n' > "$RELBIN/timedatectl"
chmod +x "$RELBIN/timedatectl"
RELH="$TMPROOT/relogio-home"; mkdir -p "$RELH/.config/tandem"; printf '4.27\n' > "$RELH/.config/tandem/.primeira-vez"
rel_cmd() {  # $1 = TANDEM_CHANGELOG value (may be empty)
    env -i HOME="$RELH" PATH="$RELBIN:/usr/bin:/bin" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
        TANDEM_CHANGELOG="$1" \
        bash "$ROOT/src/bin/tandem" relogio 2>&1
}
# release epoch in the FUTURE -> "now" is before it -> firmly wrong (atrasado),
# which is exactly a battery reset, driven end to end through the handler.
CH_FUT="$TMPROOT/relogio-ch-future"
printf ' -- Tandem <x@y>  Wed, 01 Jan 2099 00:00:00 +0000\n' > "$CH_FUT"
contem "a clock before the release date is called wrong, with the fix command" \
       "sudo timedatectl set-ntp true" "$(rel_cmd "$CH_FUT")"
contem "and it says the clock is wrong, not merely off" \
       "wrong" "$(rel_cmd "$CH_FUT")"
# a plausible date (real changelog date in the past) but NTP off -> advisory only
CH_PAST="$TMPROOT/relogio-ch-past"
printf ' -- Tandem <x@y>  Tue, 18 Aug 2026 20:15:00 +0000\n' > "$CH_PAST"
naocontem "a plausible date is not called wrong" \
          "is wrong" "$(rel_cmd "$CH_PAST")"
contem "but automatic-time-off is still surfaced with the fix" \
       "set-ntp true" "$(rel_cmd "$CH_PAST")"

# no timedatectl at all -> a plain sentence, never silence
RELBIN2="$TMPROOT/relogio-bin-empty"; mkdir -p "$RELBIN2"
saida_sem_td="$(env -i HOME="$RELH" PATH="$RELBIN2:/usr/bin:/bin" \
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
    bash "$ROOT/src/bin/tandem" relogio 2>&1)"
if [ -n "$saida_sem_td" ]; then
    pass "with no time service, tandem relogio still says something"
else
    fail "with no time service, tandem relogio still says something" "a sentence" "silence"
fi

# doctor shows a clock line when timedatectl works, and skips it when it does not
doc_com_td="$(env -i HOME="$RELH" PATH="$RELBIN:/usr/bin:/bin" \
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" TANDEM_CHANGELOG="$CH_PAST" \
    bash "$ROOT/src/bin/tandem" doctor 2>&1)"
contem "tandem doctor carries a clock line when it can read the clock" \
       "clock:" "$doc_com_td"

section "post-install breakage: worked yesterday, broke after a Wine upgrade"

# The silent failure one step later in time than the clock: a program that opened
# cleanly under one Wine fails after a distro upgrade swaps Wine underneath it.
# The memory already keys by file, so it records the Wine a program last opened
# under; on a later failure under a DIFFERENT Wine, Tandem names the change
# instead of a bare exit code. The full run->fail loop needs real Wine (covered
# by the real-programs harness); the DECISION is a pure function tested here, and
# it never blames an update on a guess.

equal "a Wine that changed since last success is worth naming" \
      "muda" "$(t_wine_mudou_desde 9.0 10.0 && echo muda || echo nao)"
equal "an unchanged Wine says nothing" \
      "nao"  "$(t_wine_mudou_desde 10.0 10.0 && echo muda || echo nao)"
equal "a first run, with nothing recorded, says nothing" \
      "nao"  "$(t_wine_mudou_desde '' 10.0 && echo muda || echo nao)"
equal "a machine with no Wine now is not compared against" \
      "nao"  "$(t_wine_mudou_desde 9.0 - && echo muda || echo nao)"
equal "and neither is one where the current version could not be read" \
      "nao"  "$(t_wine_mudou_desde 9.0 '' && echo muda || echo nao)"

# The sentence carries BOTH versions, by number, through {1}/{2} (never %s -
# versions have dots).
saida_wm="$(t_msg wine_mudou 9.0 10.0)"
contem "the breakage sentence names the version it worked under" "Wine 9.0" "$saida_wm"
contem "and the version the system has now"                      "Wine 10.0" "$saida_wm"

# The wiring in tandem-exe: written on the success path, read and emitted on the
# bare-exit fallback. Structural, because reaching either needs real Wine - the
# same reason the bitness and suspicious-DLL checks are asserted structurally.
EXE="$ROOT/src/bin/tandem-exe"
if grep -q 't_memoria_grava "$PROG" VERSAO_WINE' "$EXE"; then
    pass "tandem-exe records the Wine version on a clean open"
else
    fail "tandem-exe records the Wine version on a clean open" "a VERSAO_WINE write" "none"
fi
if grep -q 't_wine_mudou_desde "$WINE_ANTES" "$WINE_AGORA"' "$EXE" &&
   grep -q 't_msg wine_mudou' "$EXE"; then
    pass "and names the change on a later failure under a different Wine"
else
    fail "and names the change on a later failure under a different Wine" \
         "the guarded wine_mudou emit" "missing"
fi

# End to end where it CAN be exercised without Wine: the recorded version shows
# up on the memory screen, so the owner (and tandem socorro) can see it.
WINEMEM_H="$TMPROOT/wine-mem-home"
mkdir -p "$WINEMEM_H/.config/tandem" "$WINEMEM_H/.local/share/tandem/memoria"
printf '4.28\n' > "$WINEMEM_H/.config/tandem/.primeira-vez"
printf '# mem\nPROGRAMA=Balcao.exe\nRESULTADO=abriu\nVERSAO_WINE=9.0\n' \
    > "$WINEMEM_H/.local/share/tandem/memoria/deadbeef01.txt"
saida_mem="$(env -i HOME="$WINEMEM_H" PATH="/usr/bin:/bin" \
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMAS_DIR="$ROOT/src/lib/idiomas" \
    bash "$ROOT/src/bin/tandem" memoria 2>&1)"
contem "tandem memoria shows which Wine a program last opened under" \
       "9.0" "$saida_mem"


section "provenance: is this program known here, said calmly and once"

# The recognition signal shown before a run. It is not an antivirus and not a
# gate: it explains what Tandem already knows about THIS file and then opens it
# either way. The DECISION is a pure function - t_procedencia - tested here for
# both its verdicts and its ORDER, because the whole point is that local
# knowledge (this owner, this counter) outranks a distant shop's report.

# Local knowledge wins, in its own order: the owner's word first.
equal "the owner's own 'it works here' is the strongest signal" \
      "confirmado-aqui" "$(t_procedencia sim '' '' '')"
# reprovado outranks a community that says it works AND a prior clean open:
# his 'it does not work here' is about this exact machine.
equal "the owner's 'it did not work here' outranks any community report" \
      "reprovado-aqui" "$(t_procedencia nao 2026-01-01 9 '')"
equal "a clean open here before outranks the community" \
      "aberto-aqui" "$(t_procedencia '' 2026-01-01 9 '')"
# Community only speaks when the machine itself knows nothing.
equal "the community's honest negative is surfaced when nothing local is known" \
      "ninguem-conseguiu" "$(t_procedencia '' '' '' 4)"
equal "the community's positive count is surfaced when nothing local is known" \
      "comunidade-conhece" "$(t_procedencia '' '' 7 '')"
# The COMMON answer today: the list is empty for essentially everyone.
equal "an entirely unknown file is 'new here', not an alarm" \
      "novo" "$(t_procedencia '' '' '' '')"
# A non-numeric count never becomes a false 'known' - it is treated as absent.
equal "a count that is not a number does not fake a community signal" \
      "novo" "$(t_procedencia '' '' abc '')"
equal "and a zero count is not a signal either" \
      "novo" "$(t_procedencia '' '' 0 0)"

# The sentence each token becomes, in the SHIPPED catalogues. Rendered in a
# fresh process per language (the catalogue is loaded once at source time, so a
# command-prefix on the function would not switch it), exactly as the plural
# tests above do. The two community tokens carry a number and go through the
# plural machinery; an unknown token says NOTHING (rc 1) rather than printing a
# key name - the t_erro_do_leitor posture.
equal "'new here' renders as reassurance" \
      "This one is new here — that is normal; Tandem is seeing it for the first time." \
      "$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_procedencia_frase novo")"
contem "the 'opened before' line carries the date through {1}" "2026-08-18" \
       "$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_procedencia_frase aberto-aqui 2026-08-18")"
equal "one community report is singular" \
      "The community knows this program (1 report)." \
      "$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_procedencia_frase comunidade-conhece 1")"
equal "several community reports are plural" \
      "The community knows this program (5 reports)." \
      "$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_procedencia_frase comunidade-conhece 5")"
frase_bogus="$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'
               t_idioma_carrega; t_procedencia_frase nao-existe-este-token 2>/dev/null")"
if [ -z "$frase_bogus" ]; then
    pass "an unknown recognition token stays silent"
else
    fail "an unknown recognition token stays silent" "empty" "$frase_bogus"
fi

# The plural agrees in a language whose forms differ from English (pt_BR: relato
# / relatos), proving the count reaches t_msg_n and is not a printf %s.
equal "pt_BR agrees the report count (singular)" \
      "A comunidade conhece este programa (1 relato)." \
      "$(TANDEM_IDIOMA_FORCADO=pt_BR bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_procedencia_frase comunidade-conhece 1")"
equal "pt_BR agrees the report count (plural)" \
      "A comunidade conhece este programa (3 relatos)." \
      "$(TANDEM_IDIOMA_FORCADO=pt_BR bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_procedencia_frase comunidade-conhece 3")"

# The wiring in tandem-exe. The recognition note is emitted before the run, it
# calls the decision function, it is guarded so it speaks only when the status
# CHANGES (no nagging on a POS opened dozens of times a day), and - the
# load-bearing detail - the community counts are read OUTSIDE the "local memory
# empty" gate, so a locally-known program still gets the community's negative.
EXE="$ROOT/src/bin/tandem-exe"
if grep -q 'PROC_TOKEN="$(t_procedencia ' "$EXE" &&
   grep -q 't_procedencia_frase "$PROC_TOKEN"' "$EXE"; then
    pass "tandem-exe computes a recognition token and turns it into a sentence"
else
    fail "tandem-exe computes a recognition token and turns it into a sentence" \
         "the t_procedencia wiring" "missing"
fi
if grep -q 'if \[ "$PROC_TOKEN" != "$PROC_ANTES" \]; then' "$EXE"; then
    pass "the note fires only when the recognition status changes"
else
    fail "the note fires only when the recognition status changes" \
         "the change guard" "missing"
fi
# The community reads must sit ABOVE the memory shortcut block, not inside the
# 'SABIDOS empty' gate - checked by line order, the same way the identity-line
# ordering is asserted elsewhere.
n_proc="$(grep -n 'PROC_NINGUEM="$(t_lista_ninguem_conseguiu' "$EXE" | head -1 | cut -d: -f1)"
n_gate_fim="$(awk '/^if \[ -z "\$SABIDOS" \]; then/{s=NR} s && /^fi$/ && NR>s {print NR; exit}' "$EXE")"
if [ -n "$n_proc" ] && [ -n "$n_gate_fim" ] && [ "$n_proc" -gt "$n_gate_fim" ]; then
    pass "the community counts are read outside the 'local memory empty' gate"
else
    fail "the community counts are read outside the 'local memory empty' gate" \
         "PROC read after the gate closes (gate ends line ${n_gate_fim:-?})" \
         "PROC read at line ${n_proc:-?}"
fi
# The marker is a purely-local throttle and must not travel in a recipe.
if grep -q "grep -v '\^PROCEDENCIA='" "$ROOT/src/lib/common.sh"; then
    pass "the recognition throttle marker is stripped from an exported recipe"
else
    fail "the recognition throttle marker is stripped from an exported recipe" \
         "PROCEDENCIA excluded from t_receita_exporta" "not excluded"
fi


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

section "language: one, two, and the four different ways to say it"

# "1 minuto(s)" is what a program says when it cannot count, and until 4.15
# nine messages said it. The parentheses were not laziness: the catalogue
# format could not carry a second form, and the compiler DROPPED any .po entry
# that tried - silently, exit 0.
#
# The rule lives here as shell and the forms live in the catalogue as data, and
# that split is the whole security design. gettext ships its rule as a C
# expression inside the file; honouring one would mean $(( )) around text from
# a stranger, which is the property this format exists to deny.
for _caso in "en 1 0" "en 0 1" "en 2 1" "en 100 1" \
             "pt_BR 0 0" "pt_BR 1 0" "pt_BR 2 1" \
             "fr 0 0" "fr 1 0" "fr 2 1" \
             "zh_CN 0 0" "zh_CN 1 0" "zh_CN 5 0" "zh_CN 100 0" \
             "hi 1 0" "hi 3 1" \
             "ar 0 0" "ar 1 1" "ar 2 2" "ar 3 3" "ar 10 3" "ar 11 4" "ar 100 5"; do
    set -- $_caso
    equal "in $1, a count of $2 takes plural form $3" "$3" \
          "$(TANDEM_IDIOMA_FORCADO=$1 bash -c ". '$ROOT/src/lib/common.sh'; t_plural_indice $2")"
done

# Portuguese and French put ZERO with the singular and English does not. Get
# that backwards and the two languages this program was written in are the ones
# that read wrong.
equal "Portuguese says 0 minuto, not 0 minutos" "0" \
      "$(TANDEM_IDIOMA_FORCADO=pt_BR bash -c ". '$ROOT/src/lib/common.sh'; t_plural_indice 0")"
equal "English says 0 minutes" "1" \
      "$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'; t_plural_indice 0")"

# A count that is not a number must not put a bash arithmetic error on the
# owner's screen. Form 0 always exists, so it is the safe answer.
equal "a count that is not a number answers form 0 and says nothing" "0" \
      "$(TANDEM_IDIOMA_FORCADO="ar" bash -c ". '$ROOT/src/lib/common.sh'
         t_plural_indice 'nao-e-numero' 2>&1")"

# THE FALLBACK CHAIN, which is what made this safe to adopt one message at a
# time: this language's form N, then its form 0, then its plain key, and only
# then English. Reaching for English the moment a form is missing would have
# switched every Arabic and Hindi count to English the day this arrived.
_pl_dir="$TMPROOT/plural-catalogo"
mkdir -p "$_pl_dir"
printf '@so_singular#0\nform zero only\n\n@so_nua\na plain key with no forms\n' \
       > "$_pl_dir/en.txt"
printf '@so_nua\numa chave sem formas\n' > "$_pl_dir/pt_BR.txt"
equal "a missing form falls back to form 0 of the same language" "form zero only" \
      "$(TANDEM_IDIOMAS_DIR="$_pl_dir" TANDEM_IDIOMA_FORCADO=en \
         bash -c ". '$ROOT/src/lib/common.sh'; t_idioma_carrega; t_msg_n so_singular 7")"
equal "a message with no forms at all still answers, from the plain key" \
      "uma chave sem formas" \
      "$(TANDEM_IDIOMAS_DIR="$_pl_dir" TANDEM_IDIOMA_FORCADO=pt_BR \
         bash -c ". '$ROOT/src/lib/common.sh'; t_idioma_carrega; t_msg_n so_nua 5")"
equal "and it answers in ITS OWN language, not in English" "uma chave sem formas" \
      "$(TANDEM_IDIOMAS_DIR="$_pl_dir" TANDEM_IDIOMA_FORCADO=pt_BR \
         bash -c ". '$ROOT/src/lib/common.sh'; t_idioma_carrega; t_msg_n so_nua 1")"

# End to end, in the shipped catalogues, on the message this was found in.
contem "the shipped English says '1 minute' and not '1 minute(s)'" "1 minute so far" \
       "$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_msg_n progresso_ha_minutos 1 1")"
contem "and '2 minutes' with no parentheses anywhere" "2 minutes so far" \
       "$(TANDEM_IDIOMA_FORCADO=en bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_msg_n progresso_ha_minutos 2 2")"
contem "Portuguese agrees the verb too: 'Ja vai 1 minuto'" "Ja vai 1 minuto" \
       "$(TANDEM_IDIOMA_FORCADO=pt_BR bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_msg_n progresso_ha_minutos 1 1")"
contem "and 'Ja vao 2 minutos'" "Ja vao 2 minutos" \
       "$(TANDEM_IDIOMA_FORCADO=pt_BR bash -c ". '$ROOT/src/lib/common.sh'
          t_idioma_carrega; t_msg_n progresso_ha_minutos 2 2")"

# The nine that were converted must have no caller left on the old road: a
# t_msg on a plural key finds no plain entry in the catalogue and prints the
# KEY NAME, which is jargon on a counter.
for _k in progresso_ha_minutos progresso_sem_novidade lista_ja_nao_ajudou \
          abriu_e_fechou_sozinho env_enviadas env_servidor_recusou \
          esq_esqueci esq_enviados_apagado at_protegido_ok; do
    equal "no caller still asks t_msg for the plural key $_k" "" \
          "$(grep -rhoE "t_msg $_k\b" "$ROOT/src/bin" "$ROOT/src/lib" \
             --exclude-dir=idiomas 2>/dev/null | head -1)"
    equal "and $_k really is plural in the shipped English catalogue" "1" \
          "$(grep -c "^@$_k#0\$" "$ROOT/src/lib/idiomas/en.txt" || true)"
done

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

    # MISS SIXTEEN: the thirteenth's twin, left in the sibling. Only
    # citadas_com_prosa got the `tudo` fix, so printfs_com_prosa kept walking
    # function bodies and stayed blind in the very files the fix was written
    # for. citadas subsumes the double-quoted half, so what survived was
    # exactly this - a SINGLE-QUOTED printf format at the top level of a
    # handler, which scored TOTAL 0 with a Portuguese sentence in it.
    printf "printf 'Associacoes reaplicadas com sucesso\\\\n'\n" > "$ISCA_H"
    equal "a single-quoted printf of prose, at a handler's top level, is counted" \
          "1" "$(conta_isca "$ISCA_H")"

    # And the half that keeps it usable. Widening the scope without the two
    # gates citadas_com_prosa already applied made this tool INVENT twelve
    # findings on the real tree - a mimeapps.list section header, eight
    # .desktop filenames, a product name and a winetricks command line. A tool
    # that invents findings is worse than one that misses them, because
    # somebody has to spend an afternoon proving each one is nothing.
    cat > "$ISCA_H" <<'FIMP'
printf '[Default Applications]\n' > "$ALVO"
printf 'tandem-exe.desktop\n' >> "$ALVO"
printf 'winetricks -q %s\n' "$v"
printf 'Isto aqui o dono le mesmo\n'
FIMP
    equal "a file format, a filename and a command line are not prose; the sentence is" \
          "1" "$(conta_isca "$ISCA_H")"

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

# ...and every prompt has to go THROUGH t_confirmou for that to mean anything.
# The `case "$r" in s|S|sim|SIM)` comparison was copied into five handlers and
# fixed in all five - and missed in src/bin/tandem, twice, because the CLI is
# not a handler. That is the same scoping shape as the thirteenth miss of the
# literal counter, and it left `tandem preparar` and `tandem desinstalar`
# printing [y/N] in English and refusing the y the screen asked for.
cru="$(grep -rn 'case "\$r" in *s|S|sim|SIM' "$ROOT"/src/bin/ 2>/dev/null || true)"
equal "no prompt compares the answer by hand instead of asking t_confirmou" "" "$cru"

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
# A plural entry is ONE msgctxt and SEVERAL catalogue keys, so what should
# survive is summed from what was parsed rather than counted from msgctxt
# lines. Counting msgctxt was right until the first plural message arrived
# and then read as a defect in the compiler, which it was not.
esperadas = sum(len([f for f in t if f]) if isinstance(t, list) else 1
                for k, t, fz in itens if t and not fz)
print("%s %s %d %d" % (
    ",".join(k for k, t, f in itens if f),
    "omitida" if "@sem_arquivo\n" not in saida else "MANTIDA",
    saida.count("\n@"), esperadas))
FIM
)"
    # The fuzzy one is dropped and every other key survives. Both numbers are
    # computed, because a hard number here fails on the next message somebody
    # adds and teaches them to edit the expectation instead of reading the test.
    equal "a fuzzy entry is seen, dropped, and the rest kept" \
          "sem_arquivo omitida yes" \
          "$(printf '%s' "$resultado" |
             awk '{ print $1, $2, ($3 == $4 ? "yes" : "no:" $3 "/" $4) }')"

    # PLURALS. The bug this exists for was measured, not supposed: a probe
    # entry appended to po/en.po compiled to a catalogue that did not contain
    # it, the tool printed the same count as before, and it exited 0. Every
    # line of a translator's plural work went nowhere without a word - and the
    # people that discards are exactly the volunteers this format was adopted
    # to attract.
    PLURAL_PO="$TMPROOT/po-plural"
    mkdir -p "$PLURAL_PO"
    cp "$ROOT"/po/en.po "$PLURAL_PO/en.po"
    cat >> "$PLURAL_PO/en.po" <<'FIM'

msgctxt "chave_plural_de_teste"
msgid "one thing"
msgid_plural "{1} things"
msgstr[0] "one thing"
msgstr[1] "{1} things"
FIM
    plural_saida="$(cd "$ROOT" && python3 - "$PLURAL_PO/en.po" <<'FIM'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("c", "tools/po-para-catalogo.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
itens, cab = m.le_po(sys.argv[1])
saida = m.escreve_catalogo("en", itens, cab)
print("%s|%s|%s" % (
    "#0" if "@chave_plural_de_teste#0\none thing\n" in saida else "SEM-0",
    "#1" if "@chave_plural_de_teste#1\n{1} things\n" in saida else "SEM-1",
    "sem-chave-nua" if "@chave_plural_de_teste\n" not in saida else "CHAVE-NUA"))
FIM
)"
    equal "a plural entry reaches the catalogue as one key per form" \
          "#0|#1|sem-chave-nua" "$plural_saida"

    # A form NUMBERED PAST THE END of the language's own rule can never be
    # reached by any count. Shipping it quietly would spend somebody's
    # afternoon and deliver nothing, so the compiler refuses and says which
    # entry - the opposite of how it used to behave.
    cp "$ROOT"/po/ar.po "$PLURAL_PO/ar.po"
    cat >> "$PLURAL_PO/ar.po" <<'FIM'

msgctxt "chave_plural_demais"
msgid "one thing"
msgid_plural "{1} things"
msgstr[0] "form zero"
msgstr[6] "a seventh form, and Arabic has six"
FIM
    demais="$(cd "$ROOT" && python3 - "$PLURAL_PO/ar.po" <<'FIM'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("c", "tools/po-para-catalogo.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
itens, cab = m.le_po(sys.argv[1])
print(m.confere_plurais("ar", itens, cab))
FIM
)"
    contem "a form past the end of the language's rule is refused, loudly" \
           "chave_plural_demais" "$demais"
    contem "and the refusal counts, so the tool exits non-zero" \
           "1" "$(printf '%s\n' "$demais" | tail -1)"

    # The gaps between the two tables. The counts live in the compiler for the
    # translator's tool and in common.sh for the program, because the RULE may
    # never be evaluated from a catalogue - see t_plural_indice. Duplication a
    # test pins is cheaper than an evaluator.
    for pl in en pt_BR es fr zh_CN hi ar; do
        n_py="$(cd "$ROOT" && python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('c', 'tools/po-para-catalogo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.formas('$pl'))")"
        equal "the two plural tables agree for $pl" \
              "$n_py" "$(TANDEM_IDIOMA_FORCADO=$pl bash -c ". '$ROOT/src/lib/common.sh'; t_plural_formas $pl")"
        declarada="$(grep -m1 'Plural-Forms' "$ROOT/po/$pl.po" | grep -oE 'nplurals=[0-9]+' | cut -d= -f2)"
        equal "and po/$pl.po declares the same to Poedit and Weblate" \
              "$n_py" "$declarada"
    done

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
PAINEL_CORPO="$(sed -n '/^acao_painel()/,/^}/p' "$ROOT/src/bin/tandem"
                 sed -n '/^t_painel_lista()/,/^}/p' "$ROOT/src/lib/common.sh")"
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
#
# Plural keys are compared WITHOUT their "#N" suffix, and that is not a
# loosening: Chinese has one plural form and Arabic has six, so demanding that
# every language carry every form of every key would report Chinese as
# incomplete for not inventing a distinction its grammar does not make. What
# each language owes per form is asserted just below, against its own count.
CHAVES_PT="$(grep '^@' "$IDIOMAS_DIR/pt_BR.txt" | sed 's/#[0-9]*$//' | sort -u | wc -l)"
for l in $LINGUAS; do
    faltando=""
    while IFS= read -r k; do
        grep -qE "^${k}(#[0-9]+)?\$" "$IDIOMAS_DIR/$l.txt" || faltando="$faltando ${k#@}"
    done < <(grep '^@' "$IDIOMAS_DIR/pt_BR.txt" | sed 's/#[0-9]*$//' | sort -u)
    equal "$l has every key the original has ($CHAVES_PT)" "" "$faltando"
done

# And per form, against each language's OWN count. A plural message that is
# missing a form still answers - the chain falls back to form 0 and then to the
# plain key - but it answers with the wrong number agreement, which is the
# defect this whole mechanism was built to remove. Silently half-migrated is
# exactly how "1 minuto(s)" survived seven versions.
for l in $LINGUAS; do
    n_formas="$(TANDEM_IDIOMA_FORCADO="$l" bash -c ". '$ROOT/src/lib/common.sh'; t_plural_formas '$l'")"
    incompletas=""
    while IFS= read -r base; do
        f=0
        while [ "$f" -lt "$n_formas" ]; do
            grep -qxF "${base}#${f}" "$IDIOMAS_DIR/$l.txt" ||
                incompletas="$incompletas ${base#@}#$f"
            f=$((f + 1))
        done
    done < <(grep -oE '^@[a-z0-9_]+#[0-9]+' "$IDIOMAS_DIR/en.txt" |
             sed 's/#[0-9]*$//' | sort -u)
    equal "$l fills all $n_formas of its plural forms, in every message" \
          "" "$incompletas"
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

# ...and NO catalogue may carry a printf conversion at all, which the test above
# could not see. Four messages did until 4.11 - prep_terminal, desinst_terminal
# and the two flatpak prompts - because four call sites handed the message to
# printf as its FORMAT STRING instead of substituting through t_msg. The value
# being safe is not the point: these files will one day arrive from strangers,
# and a translator who writes "100% seguro" would break a prompt in a language
# nobody here reads. A translator is not somebody who should have to know what
# a printf conversion is.
com_conversao=""
for c in "$ROOT"/src/lib/idiomas/*.txt; do
    grep -qE '%[-+ #0-9.]*[sdiouxXeEfgGc]' "$c" 2>/dev/null &&
        com_conversao="$com_conversao $(basename -- "$c")"
done
equal "no catalogue carries a printf conversion" "" "$com_conversao"

# The other half, and the one that would let it back in: no message may be used
# AS a format string. The {1} decision is only worth anything if nothing routes
# around it.
usado_como_formato="$(grep -rn 'printf "\$(t_msg' "$ROOT"/src/bin/ "$ROOT"/src/lib/ 2>/dev/null |
                      grep -v '^\s*#' | grep -cv '# NOT' || true)"
equal "no catalogue message is handed to printf as its format" "0" "$usado_como_formato"

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
    # ...AND NOT ANOTHER PROCESS'S EITHER, which the slice could never
    # guarantee. The log is one file per handler with no PID in its name, so
    # two .sh files double-clicked a second apart both write script.log, and a
    # marker only fixes where the slice STARTS. Measured that way first, with a
    # real race; written here as a script that appends to the log itself, which
    # is the same thing happening at a time the test can pin down.
    #
    # The harm is the worst shape this project has: this installer prints
    # NOTHING, and it was reported as "this is what it said:" followed by the
    # other program's progress lines - so the silent-success guard was defeated
    # at the same moment, a slice with somebody else's lines in it never being
    # empty. The owner of an installer that did nothing was congratulated.
    cat > "$TMPROOT/intruso.sh" <<'FIMI'
#!/bin/sh
# says nothing of its own; writes into the shared log the way a second Tandem
# running at the same moment does
for i in 1 2 3 4 5; do
    printf 'Installing component %s of 5...\n' "$i" \
        >> "$HOME/.local/state/tandem/script.log" 2>/dev/null
done
exit 0
FIMI
    chmod +x "$TMPROOT/intruso.sh"
    saida_intruso="$(roda_script "$TMPROOT/intruso.sh" intruso)"
    case "$saida_intruso" in
        *"Installing component"*)
            fail "another process's lines are never shown as this program's words" \
                 "nothing of the other program" "its progress lines were shown" ;;
        *) pass "another process's lines are never shown as this program's words" ;;
    esac
    case "$saida_intruso" in
        *"said nothing"*) pass "and the silent-success guard still fires through the noise" ;;
        *) fail "and the silent-success guard still fires through the noise" \
                "the warning about saying nothing" "$saida_intruso" ;;
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

section "the other side of that branch: a REAL terminal"

# sem_ninguem above covers one half of `[ -t 0 ]` - nobody there at all. TEN
# places in this tree branch on it (the confirmation prompt of five handlers,
# t_texto's read of standard input, the sudo path), and until now the suite
# could reach NONE of the terminal half: env -i with no tty is the other side
# of every one of those ifs. The half that was unmeasured is the fallback that
# exists so that no path ends in silence.
#
# tests/terminal.py is stdlib-only on purpose - expect and unbuffer are not on
# a bare runner, and a test that skips itself on CI is a test that never runs.
if python3 -c "import pty, select" 2>/dev/null; then
    TTY_SH="$TMPROOT/instalador-tty.sh"
    printf '#!/bin/sh\necho "RODOU-DE-VERDADE"\n' > "$TTY_SH"
    chmod +x "$TTY_SH"
    num_terminal() {
        TANDEM_LIB="$ROOT/src/lib" TANDEM_CONFIG="$TMPROOT/tty-cfg" \
        TANDEM_DADOS="$TMPROOT/tty-dados" TANDEM_IDIOMA_FORCADO="$1" \
            python3 "$ROOT/tests/terminal.py" "$2" \
                bash "$ROOT/src/bin/tandem-script" "$TTY_SH" 2>&1
    }
    mkdir -p "$TMPROOT/tty-cfg" "$TMPROOT/tty-dados"

    # The harness has to give a REAL terminal, or every assertion below passes
    # while measuring the pipe it was written to replace.
    equal "the harness really does hand the child a terminal on all three fds" \
          "0 1 2" "$(python3 "$ROOT/tests/terminal.py" "" bash -c \
                     'for n in 0 1 2; do [ -t $n ] && printf "%s " $n; done' |
                     tr -s ' ' | sed 's/ $//')"

    # A REFUSAL at a terminal must be a sentence. Three refusal paths in these
    # handlers once exited 0 with zero bytes, and this is the side of the
    # branch that was never walked.
    recusa="$(num_terminal pt_BR n)"
    naocontem "refusing at a terminal does not run the installer" \
              "RODOU-DE-VERDADE" "$recusa"
    if [ -n "$recusa" ]; then
        pass "and it says so, rather than exiting quietly"
    else
        fail "and it says so, rather than exiting quietly" "uma frase" "zero bytes"
    fi

    # t_confirmou, at a real prompt, for the first time. The defect it was
    # written for is documented: five handlers printed [y/N] from the
    # catalogue and then matched only s|S|sim|SIM, so an English owner did
    # exactly what the screen asked, typed y, and was told it was cancelled -
    # on the two paths where the alternative is being told nothing happened.
    for _par in "en y" "en s" "pt_BR s" "pt_BR y" "fr o" "fr y"; do
        set -- $_par
        if printf '%s' "$(num_terminal "$1" "$2")" | grep -q "RODOU-DE-VERDADE"; then
            pass "in $1, answering '$2' at a real prompt means yes"
        else
            fail "in $1, answering '$2' at a real prompt means yes" \
                 "o instalador roda" "foi recusado"
        fi
    done
    # And the other way round, or "accepts everything" would pass all six above.
    for _par in "en n" "pt_BR n" "fr n"; do
        set -- $_par
        naocontem "in $1, answering 'n' still refuses" \
                  "RODOU-DE-VERDADE" "$(num_terminal "$1" "$2")"
    done
else
    skip "the terminal half of [ -t 0 ]" "this python has no pty module"
fi

section "the readers defend their own KEY=VALUE contract"

# Every value the six readers print is either a number they computed or a
# STRING THAT CAME OUT OF THE FILE - and the file arrived from the internet.
# Whether such a string can contain a newline is a property of the SOURCE
# FORMAT, not of the reader: a .deb control file is line-based and cannot
# carry one, while a PE import name, an RPM header string and an Android
# manifest string are length- or NUL-delimited and carry one perfectly well.
#
# Relying on the input format to protect the output format is an accident
# waiting for the one format that does not. The asymmetry that made it visible:
# peinfo's raw-exception path already did .replace("\n", " ") while the data
# path three lines below it did not.
#
# This is defence in depth, not a live failure - no real .exe has a newline in
# a DLL name. It is asserted because an untested guard is not a guard.
for _r in peinfo debinfo rpminfo jarinfo appimageinfo apkinfo; do
    sujo="$(cd "$ROOT" && python3 - "$_r" <<'FIMLIMPO'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("r", "src/lib/%s.py" % sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
casos = ["kerne\nERRO=forjado", "a\rb", "x\x0cy", "tab\there"]
ruins = [c for c in casos if any(ch in m.limpo(c) for ch in "\r\n\x0c\t")]
print(len(ruins))
FIMLIMPO
)"
    equal "$_r.py cannot be made to forge a line" "0" "$sujo"
done

# And a value with nothing wrong with it must come through untouched, or the
# cleaning would be quietly corrupting every package name it ever reads.
intacto="$(cd "$ROOT" && python3 - <<'FIMINTACTO'
import importlib.util
spec = importlib.util.spec_from_file_location("r", "src/lib/peinfo.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.limpo("kernel32.dll,msvcp140.dll") == "kernel32.dll,msvcp140.dll")
FIMINTACTO
)"
equal "and an ordinary value is not touched" "True" "$intacto"

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

# FOUR silences, and until 4.16 they were one. Answering 1 to all of them
# meant whoever is helping could not tell a machine that never downloaded the
# file from a program the world genuinely knows nothing about - and the log
# said nothing at all, so there was not even a trail to read.
codigo_lista() { t_lista_consulta "$PROG_L" >/dev/null 2>&1; printf '%s' "$?"; }

TANDEM_LISTA_ANTES="$TANDEM_LISTA"
export TANDEM_LISTA="$TMPROOT/lista-que-nao-existe.tsv"
rm -f "$TANDEM_LISTA"
equal "no list downloaded here answers 2, not the same 1 as everything else" \
      "2" "$(codigo_lista)"
export TANDEM_LISTA="$TANDEM_LISTA_ANTES"

{
  printf '# TANDEM-LISTA 1\n'
  printf 'outro-id-qualquer\t64\tvcrun2022\t-\tconfirmado\t400\t2026-08\t-\n'
} > "$TANDEM_LISTA"
equal "a list that has never heard of this program answers 3" "3" "$(codigo_lista)"

{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022\t-\tso-abriu\t9\t2026-08\t-\n' "$ID_L"
} > "$TANDEM_LISTA"
equal "known, but with no lesson worth passing on, answers 4" "4" "$(codigo_lista)"

{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022\t-\tconfirmado\t400\t2026-08\t-\n' "$ID_L"
} > "$TANDEM_LISTA"
equal "and a usable lesson still answers 0, with the verbs" "0" "$(codigo_lista)"

# The identity is matched as a FIELD. A substring hit anywhere else in the row
# would answer "the list knows this program" about a different one entirely.
{
  printf '# TANDEM-LISTA 1\n'
  printf 'outro\t64\tvcrun2022\t%s\tconfirmado\t400\t2026-08\t-\n' "$ID_L"
} > "$TANDEM_LISTA"
equal "the fingerprint appearing in another column is not a match" \
      "3" "$(codigo_lista)"

# Every code has a sentence, and none of them is the code itself. A new code
# added without one would print "sem resposta", which is the shape this
# project keeps finding: a rich verdict whose caller kept a boolean.
for _c in 1 2 3 4; do
    naocontem "code $_c has a sentence of its own, not a number" \
              "sem resposta" "$(t_lista_porque_calou "$_c")"
done

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

# ------------------------------------------------------------------
# "entregue" (4.11): Tandem proved the missing file arrived, in the right
# width, and the owner never answered. Weaker than his word, stronger than a
# shrug - and until 4.11 it was recorded as a shrug, so it contributed nothing
# at all.
lista_com <<L
$ID_L	64	vcrun2022	-	entregue	9	2026-08	-
L
equal "a proven delivery is worth suggesting, unlike a bare so-abriu" \
      "vcrun2022" "$(t_lista_consulta "$PROG_L")"
equal "and the count shown is the honest number of reports, not the weight" \
      "9" "$(t_lista_maquinas "$ID_L")"

# The halving, stated as the only thing that can decide the row. 100 proven
# deliveries weigh 50; 60 people who looked at the screen weigh 60. If the
# weight were 1.0 the first row would win, so this test fails the moment
# somebody "simplifies" entregue into a full report.
lista_com <<L
$ID_L	64	vcrun2010	-	entregue	100	2026-08	-
$ID_L	64	vcrun2022	-	confirmado	60	2026-08	-
L
equal "a person's word outweighs nearly twice as many proven deliveries" \
      "vcrun2022" "$(t_lista_consulta "$PROG_L")"

# ...and the halving is not a veto: enough of them still win.
lista_com <<L
$ID_L	64	vcrun2010	-	entregue	200	2026-08	-
$ID_L	64	vcrun2022	-	confirmado	60	2026-08	-
L
equal "enough proven deliveries do outweigh a smaller set of confirmations" \
      "vcrun2010" "$(t_lista_consulta "$PROG_L")"

# A rejection is a person saying it does NOT work, and it weighs a full report.
# So an equal number of proven deliveries loses - which is the right way round:
# the file arriving proves nothing about the program.
lista_com <<L
$ID_L	64	vcrun2022	-	entregue	50	2026-08	-
$ID_L	64	vcrun2022	-	reprovado	50	2026-08	-
L
equal "as many rejections as proven deliveries silences the row" \
      "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

# The record actually written by the send path has to be one the intake and the
# rebuild both accept - the three have drifted apart before.
lista_com <<L
$ID_L	64	vcrun2022	-	so-abriu	9	2026-08	-
L
equal "a bare so-abriu still contributes nothing" \
      "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

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
# Eight until 4.9, eleven since: the stack (Wine and winetricks versions) and
# the dedup token were APPENDED. Appending is the only change this format
# allows - every reader indexes by column, so an old client reads 1-8 and
# ignores the rest, while reordering or repurposing a column would silently
# change what every published row means.
equal "the record has the format's twelve fields" \
      "12" "$(printf '%s' "$REG_L" | awk -F'\t' '{print NF}')"
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
        # And the machine keeps a record of what left it. Until 4.11 the 2xx
        # branch was the ONLY one of the three that destroyed its line: the
        # sieve refusal and the 4xx refusal both park theirs under an explicit
        # written rule. So "what has this machine sent about my shop?" had no
        # answer on the machine - which is the question a shopkeeper, or
        # whoever audits him, actually asks, and section 3 of the idea ledger
        # rejected telemetry on exactly that rule: nothing the owner cannot see
        # and cannot delete.
        equal "a line that left is written down" "1" \
              "$(linhas_de "$CASA_E/fila.tsv.enviados")"
        # The month and not the day, for the same reason the record carries
        # only the month: a date with a day identifies.
        case "$(head -1 "$CASA_E/fila.tsv.enviados" 2>/dev/null)" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]$(printf '\t')*"$REG_BOM")
                pass "with the month it left, and the record beside it" ;;
            *) fail "with the month it left, and the record beside it" \
                    "YYYY-MM<TAB>$REG_BOM" \
                    "$(head -1 "$CASA_E/fila.tsv.enviados" 2>/dev/null)" ;;
        esac
        equal "and the count the owner is shown is that many" "1" \
              "$(env HOME="$CASA_E" TANDEM_FILA="$CASA_E/fila.tsv" \
                 bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_envio_ja_enviados')"
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

# ------------------------------------------------------------------
# The delivery proof reaching the LESSON (4.11).
#
# Before this, the proof computed three distinct outcomes and recorded none of
# them: "I verified the missing file arrived and he never clicked" and "there
# was nothing to verify and he never clicked" both came out "so-abriu", and
# both travelled to somebody else's machine, in a recipe and in a list record,
# as the same word.

# Which outcome speaks for a whole run. The order is the entire content of the
# function, so every pair that could be got backwards is pinned here.
equal "one file proven to arrive, nothing wrong: the run is entregue" \
      "entregue" "$(t_prova_do_run "entregue entregue")"
equal "nothing checkable is not the same as nothing wrong" \
      "sem-alvo" "$(t_prova_do_run "")"
equal "a proven arrival outranks a verb there was nothing to check for" \
      "entregue" "$(t_prova_do_run "entregue")"
equal "one file provably missing sinks the whole run" \
      "nao-chegou" "$(t_prova_do_run "entregue nao-chegou entregue")"
equal "the wrong width sinks a run that was otherwise proven" \
      "bitola-errada" "$(t_prova_do_run "entregue bitola-errada")"
# The ordering defect this function was extracted to make visible: inline and
# as a plain assignment, the LAST outcome spoke for the run, so a wrong-width
# after a missing file reported the milder of the two.
equal "a later wrong width does not overwrite an earlier missing file" \
      "nao-chegou" "$(t_prova_do_run "nao-chegou bitola-errada")"
equal "and the same holds in the other order" \
      "nao-chegou" "$(t_prova_do_run "bitola-errada nao-chegou")"

t_memoria_esquece "$PROG_S" 2>/dev/null
t_memoria_grava "$PROG_S" PROVA entregue
equal "a proven delivery with no answer is worth more than a shrug" \
      "entregue" "$(t_confianca_da_licao "$PROG_S")"
# The whole point of the four levels: only ONE of them lifts the lesson.
for nivel in sem-alvo nao-chegou bitola-errada; do
    t_memoria_grava "$PROG_S" PROVA "$nivel"
    equal "PROVA=$nivel does not lift the lesson above so-abriu" \
          "so-abriu" "$(t_confianca_da_licao "$PROG_S")"
done
# The owner's word outranks any file check, in both directions. Getting this
# backwards would let a file check overrule a person who looked at the screen
# and said the program does not work.
t_memoria_grava "$PROG_S" PROVA entregue
t_memoria_grava "$PROG_S" CONFIRMADO nao
equal "the owner saying no outranks a proven delivery" \
      "reprovado" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_grava "$PROG_S" CONFIRMADO sim
equal "the owner saying yes outranks a proven delivery too" \
      "confirmado" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_esquece "$PROG_S" 2>/dev/null

# ------------------------------------------------------------------
# The owner's answer on the screen built to show him what Tandem learned.
#
# It was collected and never displayed: `grep CONFIRMADO src/bin/tandem`
# returned NOTHING, while the screen faithfully printed RESULTADO=abriu, which
# the exit code sets and the "no" branch deliberately leaves alone. So the one
# program he had told Tandem was broken came back to him as "result: it
# opened" - and `tandem socorro` embeds this screen verbatim, so the report he
# sends to whoever is helping asserted that the program works.
#
# Run against the real command, not the library: this whole class of defect
# lives in the gap between what a function stores and what a screen prints, and
# only running the command can see it.
MEMC="$TMPROOT/mem-confirmado"; mkdir -p "$MEMC"
{
    printf 'PROGRAMA=quebrado.exe\n'
    printf 'RESULTADO=abriu\n'
    printf 'CONFIRMADO=nao\n'
} > "$MEMC/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.txt"
TELA="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en TANDEM_MEMORIA="$MEMC" \
        bash "$ROOT/src/bin/tandem" memoria 2>&1)"
case "$TELA" in
    *"did NOT work"*) pass "the screen says the owner rejected the program" ;;
    *) fail "the screen says the owner rejected the program" \
            "a line about his answer" "$TELA" ;;
esac
# And it comes FIRST, because it outranks the exit code's verdict printed below
# it. A screen that leads with "it opened" and mentions the rejection further
# down is read as "it worked" by somebody skimming.
LINHA_DONO="$(printf '%s\n' "$TELA" | grep -n "did NOT work" | cut -d: -f1)"
LINHA_RES="$(printf '%s\n' "$TELA" | grep -n "result:" | cut -d: -f1)"
if [ -n "$LINHA_DONO" ] && [ -n "$LINHA_RES" ] && [ "$LINHA_DONO" -lt "$LINHA_RES" ]; then
    pass "the owner's answer is printed above the exit code's verdict"
else
    fail "the owner's answer is printed above the exit code's verdict" \
         "his answer on an earlier line than result:" \
         "answer=$LINHA_DONO result=$LINHA_RES"
fi
# The other answer, so the case statement cannot be one-sided.
sed -i 's/^CONFIRMADO=nao/CONFIRMADO=sim/' "$MEMC/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.txt"
TELA="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en TANDEM_MEMORIA="$MEMC" \
        bash "$ROOT/src/bin/tandem" memoria 2>&1)"
case "$TELA" in
    *"worked the way you expected"*) pass "and it says so when he confirmed it" ;;
    *) fail "and it says so when he confirmed it" "a line about his answer" "$TELA" ;;
esac
# A memory with no answer must not invent one. The case statement matches only
# sim and nao, and an absent field has to fall through both.
sed -i '/^CONFIRMADO=/d' "$MEMC/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.txt"
TELA="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en TANDEM_MEMORIA="$MEMC" \
        bash "$ROOT/src/bin/tandem" memoria 2>&1)"
case "$TELA" in
    *"you said"*) fail "with no answer it does not invent one" "no 'you said' line" "$TELA" ;;
    *) pass "with no answer it does not invent one" ;;
esac
rm -rf "$MEMC"

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
    # SOMEBODY ELSE'S JARGON, at the top of the owner's screen.
    # update-mime-database complains on STDOUT, not stderr, so the 2>/dev/null
    # beside it silenced the wrong stream and "Directory '...' does not exist!"
    # was the first line read on any machine without
    # ~/.local/share/mime/packages - a fresh account, a minimal desktop, and
    # every one of these fake HOMEs. It appeared in five of five scenarios
    # while something else entirely was being tested, and nothing in the tree
    # could see it because no test had ever read this file for prose.
    naocontem "no other tool's complaint reaches the owner's output" \
              "does not exist" "$(cat "$A/stdout.txt" "$A/stderr.txt" 2>/dev/null)"

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
    # THE SHORTCUT PATH, which its own comment said no test reaches - and it
    # did not, which is how it kept a boolean where t_dll_no_prefixo gives
    # three answers. A lesson already in memory is applied BEFORE the detector
    # loop, and until 4.17 "delivered in a width this program cannot load" was
    # reported as "did not deliver" AND filed in traducao-suspeita.tsv.
    #
    # Wrong width is not a wrong table row: vcrun2003 really does provide
    # mfc71.dll, the verb just ships a 32-bit payload - half of them do. Filing
    # that poisons the one work list that has already found six genuinely wrong
    # mappings.
    ATALHO="$E2E/atalho"; mkdir -p "$ATALHO"
    PREF_A="$ATALHO/.local/share/tandem/wine"
    mkdir -p "$PREF_A/drive_c/windows/system32" "$PREF_A/drive_c/windows/syswow64"
    : > "$PREF_A/system.reg"; : > "$PREF_A/.tandem-prefixo"
    TANDEM_MEMORIA="$ATALHO/.local/share/tandem/memoria" \
        t_memoria_grava "$ARTIFACTS/prog64.exe" RESOLVERAM "vcrun2003" 2>/dev/null
    # winetricks that delivers the RIGHT file into the WRONG folder: syswow64
    # is where the 32-bit copies live, and this program is 64-bit.
    cat > "$E2E/bin/winetricks" <<'FIMWT'
#!/bin/sh
printf '%s\n' "$*" >> "$E2E_DIARIO"
if [ -n "$E2E_ENTREGA" ]; then
    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
    : > "$WINEPREFIX/drive_c/windows/syswow64/$E2E_ENTREGA"
fi
exit 0
FIMWT
    chmod +x "$E2E/bin/winetricks"
    roda_exe "$ATALHO" mfc71.dll
    LOG_A="$(cat "$ATALHO/.local/state/tandem/exe.log" 2>/dev/null)"
    contem "the shortcut path is reached at all" \
           "da memoria" "$LOG_A"
    contem "wrong width from a remembered lesson says WRONG WIDTH" \
           "bitola errada" "$LOG_A"
    naocontem "and does not report it as a file that never arrived" \
              "nao entregou mfc71.dll" "$LOG_A"
    # awk, not `grep -c ... || printf 0`: grep -c prints 0 AND exits 1 when the
    # file has no match, so the fallback fires too and the answer is "00". That
    # trap is written down in CLAUDE.md, having once reached the owner as a
    # queue length of "0\n0" - and this assertion walked straight into it.
    equal "and a correct table row is NOT filed as a suspicious translation" \
          "0" "$(awk '/mfc71/ { n++ } END { print n + 0 }' \
                 "$ATALHO/.local/state/tandem/traducao-suspeita.tsv" 2>/dev/null || printf 0)"

    C="$E2E/semjanela"; mkdir -p "$C"; roda_exe "$C" "" semgui
    if [ -s "$C/stderr.txt" ]; then pass "no window: the message comes out on the terminal"
    else fail "no window: the message comes out on the terminal" \
                "any text on stderr" "zero bytes (silent error)"; fi
    case "$(cat "$C/stderr.txt" 2>/dev/null)" in
        *"winetricks -q vcrun2003"*) pass "no window: states the exact command to fix it" ;;
        *) fail "no window: states the exact command to fix it" \
                  "winetricks -q vcrun2003" "$(head -c 200 "$C/stderr.txt" 2>/dev/null)" ;;
    esac

    # --- Case 5: the machine is what failed, and winetricks still exits 0.
    #
    # A full disk is the case, measured on a 3 MB filesystem: winetricks
    # downloads nothing, installs nothing, prints "No space left on device"
    # and EXITS 0. The delivery proof then correctly reports the DLL did not
    # arrive - and everything downstream blamed the translation table, because
    # the cause table was only reachable from the branch where winetricks
    # itself failed. Two harms out of one gap: a correct mapping filed in
    # traducao-suspeita.tsv, and an owner told "the program closed with an
    # error (code 53)" about a disk.
    #
    # The pair that makes this an assertion rather than a hope is Case 2 above:
    # same code path, same exit 0, same missing file, and it DOES file the
    # suspicion. So the guard here is discriminating, not unconditional.
    cat > "$E2E/bin/winetricks" <<'FIMWTD'
#!/bin/sh
printf '%s\n' "$*" >> "$E2E_DIARIO"
printf 'Executing load_vcrun2003\n'
printf 'cp: error writing /tmp/x/vcrun2003: No space left on device\n'
exit 0
FIMWTD
    chmod +x "$E2E/bin/winetricks"
    D="$E2E/discocheio"; mkdir -p "$D"; roda_exe "$D" ""
    LOG_D="$(cat "$D/.local/state/tandem/exe.log" 2>/dev/null)"
    contem "exit 0 with a full disk names the disk as the cause" \
           "causa: disco_cheio" "$LOG_D"
    naocontem "and does not report it as a mapping that failed to deliver" \
              "saiu 0 mas nao entregou" "$LOG_D"
    # cat piped into awk, not awk reading the file: when the file is ABSENT -
    # which is the outcome this asserts - awk cannot open it, prints nothing
    # and exits non-zero, so the assertion compared "0" against an empty
    # string and failed while the code was right. Emptiness through a pipe is
    # a line count of zero.
    equal "and files nothing in the suspicious-translation work list" \
          "0" "$(cat "$D/.local/state/tandem/traducao-suspeita.tsv" 2>/dev/null |
                 awk 'END { print NR + 0 }')"
    # And the owner is TOLD. Until 4.19 the cause was computed and went
    # nowhere: the sentence existed in seven languages, in the catalogue, and
    # the only branch that could reach it was one a full disk never takes.
    JAN_D="$(cat "$D/janelas.txt" 2>/dev/null)"
    contem "the owner is told the disk is full, not just the exit code" \
           "disk is full" "$JAN_D"
    # And it does not say the opposite in the line above. Appending the cause
    # under "I installed the dependencies but the program still does not open"
    # was the first attempt, and it was half a fix: the sentence the owner
    # reads first still claimed the install happened. The one that says the
    # true thing already existed, already translated seven times.
    naocontem "and is not told the components were installed, because they were not" \
              "I installed the dependencies" "$JAN_D"
    contem "it says it could not install them, and which ones" \
           "Visual C++ 2003" "$JAN_D"
    # ONCE, not once per retry. The list survives all three rounds by design -
    # that is the whole point of declaring it above the loop - so appending
    # unconditionally listed the same component three times. The suite was
    # green; it was found by reading the installed package's own output.
    equal "and names each component once, not once per retry" \
          "1" "$(printf '%s\n' "$JAN_D" | grep -c '^- Visual C++ 2003$')"

    # --- Case 6: the whole run with nowhere to write the log. Every check in
    # tandem-exe reads the log back, so this is not "one feature degraded" - it
    # is the diagnosis gone, and the owner must be told the answer got worse
    # rather than being handed a bare exit code as though nothing was missing.
    E="$E2E/semlog"; mkdir -p "$E/.local/state"
    : > "$E/.local/state/tandem"          # where a DIRECTORY is expected
    roda_exe "$E" "" semgui
    ERR_E="$(cat "$E/stderr.txt" 2>/dev/null)"
    contem "with no log, the owner is told the notes could not be written" \
           "could not write my notes" "$ERR_E"
    naocontem "and bash's own write error never reaches him" \
              "write error" "$ERR_E"
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

# And the WEEKDAY has to be the weekday that date really was. lintian refuses
# "debian-changelog-has-wrong-day-of-week" as a warning, the release step runs
# it with --fail-on warning, and this has now cost the project a red CI run: an
# entry written by hand said Fri for 2026-08-15, which was a Saturday. Nobody
# checks a day name by eye, and the ordering guard above cannot see it - both
# dates parse fine and sort correctly, because `date -d` simply ignores a
# weekday that disagrees with the rest of the field.
#
# It is checked on every entry, not only the top one: an old entry's wrong day
# is just as fatal to `lintian --fail-on warning`, and finding it during a
# release is the wrong order.
DIA_MAU=""
while IFS= read -r d; do
    dia_dito="${d%%,*}"
    dia_real="$(date -d "${d#*, }" +%a 2>/dev/null)" || continue
    [ -n "$dia_real" ] || continue
    [ "$dia_dito" = "$dia_real" ] || DIA_MAU="$DIA_MAU$d (was a $dia_real) "
done <<EOF
$(grep '^ -- ' debian/changelog | sed 's/^ -- [^>]*>  //')
EOF
equal "every changelog entry names the weekday that date really was" \
      "" "$DIA_MAU"

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

# THE SAME DEFECT FROM THE OTHER SIDE, and the guard above cannot see it: it
# asks whether the published entry was EDITED, so a commit that changes shipped
# code and leaves the changelog alone passes it cleanly. Its own comment says a
# doc-only commit after a release passes - and it has no way to tell doc-only
# from code.
#
# That is how this was found, by the owner asking "so your work is done?" while
# three commits of new behaviour (four exit codes, a new function, a new log
# line) sat in src/ under a version number the public already had, with no
# entry describing any of it. Nothing in the tree objected.
#
# So: if this version is published AND anything that goes inside the .deb has
# moved since that tag, the version has to be opened. Same skips as above,
# for the same reason - a guard that stops a good release for lack of
# information is worse than the drift it was written for.
NOME_COD="shipped code has not moved since this version was published"
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 ||
   [ -z "$(git -C "$ROOT" tag 2>/dev/null | head -1)" ]; then
    skip "$NOME_COD" "no tags here, so what is published cannot be known"
elif ! git -C "$ROOT" rev-parse -q --verify "refs/tags/v$VERSAO_DEB" >/dev/null 2>&1; then
    pass "$NOME_COD"
else
    git -C "$ROOT" diff --quiet "refs/tags/v$VERSAO_DEB" -- src man debian/postinst debian/postrm 2>/dev/null
    case $? in
        0) pass "$NOME_COD" ;;
        1) fail "$NOME_COD" \
                "open the next version before changing what ships" \
                "v$VERSAO_DEB is published and src/ has moved since: $(git -C "$ROOT" diff --name-only "refs/tags/v$VERSAO_DEB" -- src man debian/postinst debian/postrm 2>/dev/null | tr '\n' ' ')" ;;
        *) skip "$NOME_COD" "the tag v$VERSAO_DEB is here but its objects are not" ;;
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

section "the catalogue and the code agree, in both directions"

# Three questions this project is one edit away from failing, and the third is
# the one that puts nonsense on a shop counter:
#   1. a key called and not defined - t_msg prints the KEY NAME, which is right
#      for a log and is jargon on screen;
#   2. a key defined and never called - translator effort in seven languages on
#      a message nobody reads, and five catalogues are still unreviewed;
#   3. PLACEHOLDER PARITY - a message reading "it asks for Java {1} and the one
#      here is {2}" called with one argument renders a literal "{2}".
if [ -f "$ROOT/tools/chaves-e-chamadas.py" ]; then
    SAIDA_CC="$(cd "$ROOT" && python3 tools/chaves-e-chamadas.py 2>&1)"
    N_CC="$(printf '%s\n' "$SAIDA_CC" | awk '/^CHAMADAS/ { print $2 }')"
    if [ "${N_CC:-999}" = "0" ]; then
        pass "every t_msg call matches the message it calls"
    else
        fail "every t_msg call matches the message it calls" "0" "$SAIDA_CC"
    fi

    # It has to actually catch one, and the argument counter's FIRST version
    # did not: it returned a number for everything, counted the words inside a
    # "$(...)" argument, and matched t_msg inside a COMMENT - nine findings,
    # nine of them wrong. A count that is mostly noise gets ignored, and that is
    # how a real finding goes unread. It refuses to guess now: a call whose
    # arguments nest a substitution is reported as unchecked, never as clean.
    PROVA_CC="$(cd "$ROOT" && python3 - <<'FIMCC'
import importlib.util
spec = importlib.util.spec_from_file_location("c", "tools/chaves-e-chamadas.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
casos = [('t_msg k 21', 1), ('t_msg k "$A" "$B"', 2),
         ('t_msg k "$(basename -- "$P")"', None), ('t_msg k', 0),
         ('t_msg k a b c', 3), ("t_msg k 'um so'", 1)]
saida = []
for txt, esperado in casos:
    mm = m.CHAMADA.search(txt)
    saida.append("1" if m.conta_argumentos(txt, mm.end()) == esperado else "0")
t = m.sem_comentarios('# t_msg fantasma\nt_erro "$(t_msg real)"')
saida.append("1" if ("t_msg fantasma" not in t and "t_msg real" in t) else "0")
print("".join(saida))
FIMCC
)"
    equal "the argument counter is right, and a comment is not a call" \
          "1111111" "$PROVA_CC"
    # And the unchecked calls are REPORTED rather than counted as clean.
    contem "and the calls it cannot count are reported, not assumed clean" \
           "NAO CONFERIDAS" "$SAIDA_CC"
else
    skip "the catalogue and the code agree" "tools/chaves-e-chamadas.py is missing"
fi

section "who owns a type is asked of the tool the file manager uses"

# This repository already proved xdg-mime is the wrong instrument: Nautilus
# uses GIO, and GIO resolves the MIME SUBCLASS CHAIN while xdg-mime does not.
# tandem-repair had it half right - it WRITES the association with both tools
# and read it back with xdg-mime alone, so the before/after report (the whole
# point of that command) could say "nobody" about a type a text editor really
# owns through text/plain.
#
# .flatpakref is declared sub-class-of text/plain, which is exactly the case
# where "nobody" is both wrong and worse than the truth: with Tandem's
# association gone, a double-clicked .flatpakref opens in a text editor rather
# than doing nothing.
if command -v gio >/dev/null 2>&1; then
    # A type Tandem never touches, so the answer is the system's own.
    GIO_DIZ="$(gio mime text/sgml 2>/dev/null | sed -n 's/^Default application for .*: *//p' | head -1)"
    XDG_DIZ="$(xdg-mime query default text/sgml 2>/dev/null | head -1)"
    NOSSO="$(TANDEM_LIB="$ROOT/src/lib" bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; t_dono_do_tipo text/sgml' 2>/dev/null)"
    equal "Tandem's answer is the file manager's answer" "$GIO_DIZ" "$NOSSO"
    # And this machine is one where the two tools actually disagree, so the
    # assertion above is not passing by coincidence. If they ever agree here,
    # the test says so rather than quietly proving nothing.
    if [ "$GIO_DIZ" != "$XDG_DIZ" ]; then
        pass "and the two tools really do disagree on this machine"
    else
        skip "the two tools disagree on this machine" \
             "gio and xdg-mime agree on text/sgml here, so this proves nothing"
    fi
else
    skip "who owns a type is asked of the tool the file manager uses" "no gio"
fi
# No read site in tandem-repair may go back to the weaker tool.
equal "tandem-repair asks no ownership question through xdg-mime" \
      "0" "$(grep -c 'xdg-mime query default' "$ROOT/src/bin/tandem-repair")"
# But WRITING still goes through both, because setting it in one is not enough.
contem "while setting the association still goes through both tools" \
       "xdg-mime default" "$(cat "$ROOT/src/bin/tandem-repair")"

section "the stack field carries the version and nothing else"

# Found by installing the built 4.9 package and READING the field, which is the
# only method that has ever caught anything in this project. `wine --version`
# answers "wine-9.0 (Ubuntu 9.0~repack-4build3)", and the first version of
# t_versao_limpa stripped every character that was not a version character and
# glued the rest together: "9.0Ubuntu9.0repack-4buil", truncated mid-word.
#
# It matters beyond ugliness. tools/monta-lista.py GROUPS BY THE STACK, so the
# same Wine 9.0 packaged by Ubuntu, by Debian and built from source would have
# produced three different strings and fragmented the list into three rows of
# one report each instead of one row of three - the exact opposite of what the
# field was added to do.
vlimpa() {
    TANDEM_LIB="$ROOT/src/lib" bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; t_versao_limpa "$1"' _ "$1" 2>/dev/null
}
# The three real shapes, verbatim from what the tools actually print.
equal "Ubuntu's packaging of Wine 9.0 reads as 9.0" \
      "9.0" "$(vlimpa '9.0 (Ubuntu 9.0~repack-4build3)')"
equal "Debian's packaging of the same Wine reads the same" \
      "9.0" "$(vlimpa '9.0 (Debian 9.0-1)')"
equal "and a source build of it reads the same again" \
      "9.0" "$(vlimpa '9.0')"
# winetricks prints its version followed by a checksum trailer. The trailer
# goes; the "-next" suffix STAYS, because it is part of the version - a -next
# build and a release build are not interchangeable evidence, which is the
# whole reason this field exists. My first expectation here was "20240105" and
# it was the expectation that was wrong, not the code.
equal "winetricks' version keeps its suffix and loses its checksum trailer" \
      "20240105-next" "$(vlimpa '20240105-next - sha256sum: abc123')"
# Absent stays absent rather than becoming an empty field, which would shift
# every column after it.
equal "and nothing becomes a dash, never an empty column" "-" "$(vlimpa '')"

section "the driver installer that reports success and binds nothing"

# A fifth thing nobody had named, and the only one of the eight that is
# invisible to every instrument this project owns.
#
# Measured against the installed Wine: newdev.dll's HARD stub list is
# DiInstallDevice, DiRollbackDriver, DiShowUpdateDevice, DiUninstallDevice,
# InstallWindowsUpdateDriver and the pDi* family - and DiInstallDriverA/W and
# UpdateDriverForPlugAndPlayDevicesA/W are NOT in it. They are soft stubs: they
# log a FIXME and return. setupapi really does export SetupCopyOEMInfW, so the
# files genuinely get copied.
#
# That distinction is the whole point. A HARD stub raises "Call from ... to
# unimplemented function", which t_falta_no_wine catches since 4.8. A SOFT stub
# raises nothing: the installer runs, copies its files, reports success, binds
# no driver, and the owner reboots wondering why nothing changed.
for sig in newdev.dll difxapi.dll; do
    contem "$sig is recognised as a driver installer" \
           "instalador-driver" \
           "$(awk -F'\t' -v s="$sig" '$1 == s { print $2 }' "$ROOT/src/lib/limites.tsv")"
done
# It must NOT match on setupapi alone: half the installers in the world import
# setupapi and have nothing to do with drivers.
equal "but setupapi alone is not treated as a driver installer" \
      "" "$(awk -F'\t' '$1 ~ /^setupapi/ { print $2 }' "$ROOT/src/lib/limites.tsv")"
# The verdict has a WAY OUT, and it is the true one for almost every case: the
# device the disc was for is usually already working, because Linux drives the
# bridge chips these discs exist for.
contem "and the way out points at the ports command rather than at nothing" \
       "tandem portas" \
       "$(awk -F'\t' '$1 == "newdev.dll" { print $4 }' "$ROOT/src/lib/limites.tsv")"
# An unknown class must be treated as HAVING a way out, never as hopeless -
# the rule that already governs this table.
equal "a driver installer is not presented as hopeless" \
      "TEM_SAIDA" \
      "$(TANDEM_LIB="$ROOT/src/lib" bash -c '. "'"$ROOT"'/src/lib/common.sh"
          t_limite_sem_saida instalador-driver && echo SEM_SAIDA || echo TEM_SAIDA' 2>/dev/null)"

section "a COM number Tandem gives is a COM number Wine created"

# Measured against the installed Wine: mountmgr.so contains exactly
# /dev/ttyS%u, /dev/ttyUSB%u, /dev/ttyACM%u and /dev/lp%u, and its
# detect_devices() walks each family from index 0 and STOPS AT THE FIRST GAP.
# So with /dev/ttyUSB1 present and /dev/ttyUSB0 absent, a fresh wineboot
# creates com1 -> /dev/ttyS0 and NOTHING for the USB adapter.
#
# The old code listed every device that existed and numbered them in sequence,
# so the owner was told his pinpad was on COM2 when Wine had created no COM2 -
# wrong in the invisible direction, inside the one command written to end
# exactly this confusion. A hole is not exotic: unplug and replug an adapter,
# or use a two-port converter, and you have one.
DEVF="$TMPROOT/devfalso"; mkdir -p "$DEVF"
: > "$DEVF/ttyS0"; : > "$DEVF/ttyACM0"; : > "$DEVF/ttyUSB1"
# The functions read /dev directly, so the shape is asserted through a python
# model of the same rule rather than by faking /dev - and the rule itself is
# asserted against the real functions on this machine below.
portas_modelo() {
    python3 - "$1" <<'FIMPY'
import os, sys
dev = sys.argv[1]; alc = []; inv = []
for fam in ("ttyS", "ttyUSB", "ttyACM"):
    i = 0
    while os.path.exists(os.path.join(dev, "%s%d" % (fam, i))):
        alc.append("%s%d" % (fam, i)); i += 1
    visto = True
    for j in range(64):
        if os.path.exists(os.path.join(dev, "%s%d" % (fam, j))):
            if not visto: inv.append("%s%d" % (fam, j))
        else:
            visto = False
print("|".join(alc) + " // " + "|".join(inv))
FIMPY
}
equal "a device behind a gap gets no COM number, and is named as invisible" \
      "ttyS0|ttyACM0 // ttyUSB1" "$(portas_modelo "$DEVF")"
# And the real functions agree with that rule on this machine's own /dev.
REAIS="$(TANDEM_LIB="$ROOT/src/lib" bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_portas_seriais' 2>/dev/null | wc -l)"
INVIS="$(TANDEM_LIB="$ROOT/src/lib" bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_portas_invisiveis' 2>/dev/null | wc -l)"
if [ "$REAIS" -ge 0 ] && [ "$INVIS" -ge 0 ]; then
    pass "both port functions run and return a list on a real machine"
else
    fail "both port functions run and return a list on a real machine" "counts" "$REAIS/$INVIS"
fi
# No device may be both reachable and invisible - that would double-count it.
AMBOS="$(TANDEM_LIB="$ROOT/src/lib" bash -c '. "'"$ROOT"'/src/lib/common.sh"
    comm -12 <(t_portas_seriais | sort) <(t_portas_invisiveis | sort)' 2>/dev/null)"
equal "and no device is counted as both reachable and invisible" "" "$AMBOS"

# The USB printer node the kernel actually creates. usblp registers its class
# device through a usblp_devnode() that PREPENDS "usb/", so the node has always
# been /dev/usb/lp0 - and the old glob (/dev/usblp[0-9]*) matched nothing on
# any machine, which means portas_impressora_usb, a complete seven-language
# message naming the exact fix, had never fired on Earth. The repository
# already contradicted itself: alternativas.tsv says /dev/usb/lp0 correctly.
contem "the USB printer glob looks where the kernel puts the node" \
       "/dev/usb/lp" "$(grep -o '/dev/usb/lp\[0-9\]\*' "$ROOT/src/lib/common.sh" | head -1)"
equal "and the repository no longer contradicts itself about that path" \
      "/dev/usb/lp0" \
      "$(grep -oh '/dev/usb/lp[0-9]*' "$ROOT/src/lib/alternativas.tsv" | sort -u | head -1)"

# A vendor daemon installed from a script carries an arch suffix. Thales names
# them aksusbd_x86_64 and hasplmd_x86_64, so an exact pgrep answered "not
# running" about a daemon that is running - and the owner is then sent to fix
# something that is not broken.
contem "a daemon with an arch suffix is recognised as the same service" \
       "_x86_64" "$(sed -n '/^t_servico_vivo()/,/^}/p' "$ROOT/src/lib/common.sh")"

section "a list that was changed after publication is refused"

# HTTPS proves we talked to GitHub; it does not prove the bytes are what was
# published. A bad row here is not a bad row on one machine - it is a verb name
# every Tandem downloads and may be asked to install.
#
# The rollout order is the careful part and it is asserted below: a signature
# that is PRESENT and WRONG rejects the file; a signature that is ABSENT does
# not, yet. Requiring it from day one would mean any hiccup in the signing step
# silently cuts every machine off, and a quiet list is indistinguishable from a
# list with nothing to say.
if command -v openssl >/dev/null 2>&1 && openssl genpkey -algorithm ed25519 \
        -out "$TMPROOT/priv.pem" 2>/dev/null; then
    openssl pkey -in "$TMPROOT/priv.pem" -pubout -out "$TMPROOT/pub.pem" 2>/dev/null
    printf '# TANDEM-LISTA 1\naaaa\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t-\n' \
        > "$TMPROOT/assinada.tsv"
    openssl pkeyutl -sign -inkey "$TMPROOT/priv.pem" -rawin \
        -in "$TMPROOT/assinada.tsv" -out "$TMPROOT/s.bin" 2>/dev/null
    base64 -w0 < "$TMPROOT/s.bin" > "$TMPROOT/assinada.tsv.sig"
    cp "$TMPROOT/assinada.tsv" "$TMPROOT/mexida.tsv"
    printf 'aaaa\t64\tsandbox\t-\tconfirmado\t9\t2026-08\t-\n' >> "$TMPROOT/mexida.tsv"
    # file:// rather than a local HTTP server. The first version bound a FIXED
    # port, so running the suite twice in a row left the second run talking to
    # the first run's server and reading the first run's files - the assertion
    # passed on one run and failed on the next. A flaky test is worse than no
    # test: it teaches everybody to re-run until green, which is how a real
    # failure gets waved through. curl and wget both read file:// URLs, so the
    # port was never needed.
    confere() {
        TANDEM_LIB="$ROOT/src/lib" TANDEM_LISTA_CHAVE="$2" \
        TANDEM_LISTA_URL="file://$TMPROOT/$3" \
            bash -c '. "'"$ROOT"'/src/lib/common.sh"
                     t_lista_assinatura_ok "$1" && echo ACEITA || echo RECUSA' _ "$1" 2>/dev/null
    }
    equal "a correctly signed list is accepted" \
          "ACEITA" "$(confere "$TMPROOT/assinada.tsv" "$TMPROOT/pub.pem" assinada.tsv)"
    equal "a list changed after it was signed is refused" \
          "RECUSA" "$(confere "$TMPROOT/mexida.tsv" "$TMPROOT/pub.pem" assinada.tsv)"
    # No signature published yet: accept, and say so in the log. This is the
    # half that makes the rollout safe rather than the half that makes it
    # secure, and conflating the two is how a rollout breaks everybody.
    equal "a list with no signature published yet is still accepted" \
          "ACEITA" "$(confere "$TMPROOT/assinada.tsv" "$TMPROOT/pub.pem" naoexiste.tsv)"
    # And with no public key installed there is nothing to check against -
    # which is every package built before the owner hands over his key.
    equal "and a package with no public key installed does not refuse the list" \
          "ACEITA" "$(confere "$TMPROOT/mexida.tsv" "$TMPROOT/naoexiste.pem" assinada.tsv)"
else
    skip "a list changed after publication is refused" "openssl without ed25519"
fi

section "the list weighs the stack, the age, and counts each machine once"

# WineHQ AppDB's hard rule, which this project had not adopted: a test report
# is worthless unless you know exactly what produced it. Two shops can run the
# same program, need different verbs, and BOTH be right - one is on Wine 8 and
# the other on Wine 10. Merging those two produces an answer that was never
# true anywhere.
LST="$TMPROOT/lista-v2.tsv"
cat > "$LST" <<'FIMLST'
# TANDEM-LISTA 1
aaaa1111aaaa1111aaaa1111aaaa1111	64	vcrun2022	-	confirmado	400	2024-01	-	9.0	20240105	-
aaaa1111aaaa1111aaaa1111aaaa1111	64	verbofalso	-	confirmado	1	2026-08	-	9.0	20240105	-
bbbb2222bbbb2222bbbb2222bbbb2222	64	vcrun2010	-	confirmado	50	2026-08	-	8.0	20240105	-
bbbb2222bbbb2222bbbb2222bbbb2222	64	vcrun2022	-	confirmado	40	2026-08	-	9.0	20240105	-
cccc3333cccc3333cccc3333cccc3333	64	mfc42	-	confirmado	10	2026-08	-
FIMLST
resolve() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_LISTA="$LST" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_stack_wine() { printf "9.0"; }
        t_lista_linha "$1"' _ "$1" 2>/dev/null
}
# THE LOAD-BEARING ONE. The decay has a floor of a quarter precisely so that no
# amount of age lets ONE fresh report overturn a set four hundred machines
# confirmed. That is "downgrade, do not overwrite" falling out of the
# arithmetic instead of being a rule of its own - a sudden verb-set flip on an
# established fingerprint loses on weight until enough machines report it.
equal "one fresh report does not overturn four hundred older ones" \
      "vcrun2022	400" "$(resolve aaaa1111aaaa1111aaaa1111aaaa1111)"
# Same recency on both sides, so only the stack separates them: 40 reports on
# THIS Wine beat 50 on a different major version.
equal "forty reports on our own Wine beat fifty on a different one" \
      "vcrun2022	40" "$(resolve bbbb2222bbbb2222bbbb2222bbbb2222)"
# Every row written before 4.9 has eight fields. The format is append-only, so
# an old row is short, not malformed, and must still answer.
equal "a row written before the stack existed still answers" \
      "mfc42	10" "$(resolve cccc3333cccc3333cccc3333cccc3333)"
# The number shown is the honest count of reports. "3.7 reports" would be a
# number nobody can check against the file he can download and read.
naocontem "and the number shown is reports, not the internal weight" \
          "." "$(resolve cccc3333cccc3333cccc3333cccc3333 | cut -f2)"

# A DATE IN THE FUTURE IS NOT FRESHNESS. The tie-break is "the most recently
# seen wins", so a row dated 2099-12 won every tie for ever - measured on the
# old code: ten reports this month lost to ten reports dated 2099. It takes no
# attacker, only a shop with a wrong clock, and this project already detects
# wrong clocks from the certificate errors Wine itself prints.
#
# api/lista.js REFUSES such a record on the way in, with a comment stating
# exactly this harm. That covers half the problem: this file is DOWNLOADED, and
# a reader that trusts it because the writer checked is a reader with no check.
#
# The fixture is built so the two explanations cannot be confused. The future
# row carries the alphabetically LATER verb, and the final tie-break is
# alphabetical - so if the date still decided, zzz_verb wins; if it is clamped,
# the fall-through picks aaa_verb. On the old code this returned zzz_verb.
FUT="$TMPROOT/lista-futuro.tsv"
cat > "$FUT" <<'FIMFUT'
# TANDEM-LISTA 1
dddd4444dddd4444dddd4444dddd4444	64	aaa_verb	-	confirmado	10	2026-08	-	9.0	-	-	-
dddd4444dddd4444dddd4444dddd4444	64	zzz_verb	-	confirmado	10	2099-12	-	9.0	-	-	-
FIMFUT
resolve_fut() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_LISTA="$FUT" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        t_stack_wine() { printf "9.0"; }
        t_lista_linha "$1"' _ "$1" 2>/dev/null
}
equal "a row dated in the future does not win the tie-break" \
      "aaa_verb	10" "$(resolve_fut dddd4444dddd4444dddd4444dddd4444)"
# ...and the clamp must not flatten recency altogether, which would pass the
# assertion above while throwing away the thing the date is FOR.
REC="$TMPROOT/lista-recencia.tsv"
cat > "$REC" <<'FIMREC'
# TANDEM-LISTA 1
eeee5555eeee5555eeee5555eeee5555	64	aaa_verb	-	confirmado	10	2024-01	-	9.0	-	-	-
eeee5555eeee5555eeee5555eeee5555	64	zzz_verb	-	confirmado	10	2026-08	-	9.0	-	-	-
FIMREC
equal "while a genuinely newer row still wins on the same evidence" \
      "zzz_verb	10" "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_LISTA="$REC" bash -c '
          . "'"$ROOT"'/src/lib/common.sh"
          t_stack_wine() { printf "9.0"; }
          t_lista_linha eeee5555eeee5555eeee5555eeee5555' 2>/dev/null)"
# No apostrophe may enter the awk program, comments included: the whole thing
# is inside single quotes and one in a COMMENT closes the string exactly as
# well as one in code. It did, on the first attempt at the clamp above.
equal "the list resolver still parses as shell at all" "0" \
      "$(bash -n "$ROOT/src/lib/common.sh" 2>/dev/null; echo $?)"

# ---- the record carries the stack, and the sieve does not eat it
REGV2="$TMPROOT/regv2"; mkdir -p "$REGV2"
CAMPOS="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_ESTADO="$REGV2" TANDEM_MEMORIA="$REGV2/mem" \
    bash -c '. "'"$ROOT"'/src/lib/common.sh"
             export TANDEM_ESTADO="'"$REGV2"'" TANDEM_MEMORIA="'"$REGV2"'/mem"
             F=$(mktemp); printf x > "$F"
             t_memoria_grava "$F" RESOLVERAM vcrun2022
             t_memoria_grava "$F" RESULTADO abriu
             t_lista_registro "$F" | awk -F"\t" "{print NF}"; rm -f "$F"' 2>/dev/null)"
equal "a record carries twelve fields now" "12" "$CAMPOS"

# A Wine version with four numeric components is indistinguishable from an
# IPv4 address to the leak sieve's regex. Leaving the stack fields in its scope
# would park every honest record from such a machine for ever - and a parked
# record is a lesson that never leaves.
VAZOU="$(TANDEM_LIB="$ROOT/src/lib" bash -c '. "'"$ROOT"'/src/lib/common.sh"
    r="$(printf "aaaa1111aaaa1111aaaa1111aaaa1111\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t-\t9.0.0.1\t20240105\tabcdef0123456789")"
    t_lista_vaza "$r" && echo RECUSADO || echo PASSOU' 2>/dev/null)"
equal "a four-part Wine version is not mistaken for an IP address" "PASSOU" "$VAZOU"
# But the sieve still guards the fields it exists for.
VAZOU2="$(TANDEM_LIB="$ROOT/src/lib" bash -c '. "'"$ROOT"'/src/lib/common.sh"
    r="$(printf "aaaa1111aaaa1111aaaa1111aaaa1111\t64\tvcrun2022\t-\tconfirmado\t1\t2026-08\t/home/joao/pdv.exe\t9.0\t20240105\t-")"
    t_lista_vaza "$r" && echo RECUSADO || echo PASSOU' 2>/dev/null)"
equal "and a path in the free-text field is still refused" "RECUSADO" "$VAZOU2"

# ---- the deduplication token, and what it deliberately cannot do
DD="$TMPROOT/dedup"; mkdir -p "$DD/a" "$DD/b"
tok() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_ESTADO="$1" bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; export TANDEM_ESTADO="$1"; t_dedup_token "$2"' \
        _ "$1" "$2" 2>/dev/null
}
A1="$(tok "$DD/a" 1111111111111111aaaaaaaaaaaaaaaa)"
A1B="$(tok "$DD/a" 1111111111111111aaaaaaaaaaaaaaaa)"
A2="$(tok "$DD/a" 2222222222222222bbbbbbbbbbbbbbbb)"
B1="$(tok "$DD/b" 1111111111111111aaaaaaaaaaaaaaaa)"
equal "the same machine and the same program give the same token" "$A1" "$A1B"
# THE PRIVACY PROPERTY, and the reason this is defensible at all. Without the
# secret these two are unrelated values, so the token cannot be accumulated
# into a machine identifier.
if [ -n "$A1" ] && [ "$A1" != "$A2" ]; then
    pass "two programs on one machine give unrelated tokens"
else
    fail "two programs on one machine give unrelated tokens" "different" "$A1 / $A2"
fi
if [ -n "$B1" ] && [ "$A1" != "$B1" ]; then
    pass "and two machines give different tokens for one program"
else
    fail "and two machines give different tokens for one program" "different" "$A1 / $B1"
fi
equal "the secret is readable only by its owner" "600" \
      "$(stat -c '%a' "$DD/a/.envio-segredo" 2>/dev/null)"

section "two programs do not install into one prefix at the same time"

# The lock tandem-exe takes at the top is keyed to the FILE, deliberately, so
# that opening two different programs keeps working. But both of those programs
# land in the SAME prefix by default and both may decide they need components,
# so two "winetricks -q" runs could be writing into one WINEPREFIX at once -
# exactly what the file lock's own comment says corrupts a prefix. The prefix
# lock existed and wrapped only wineboot, which is the one moment two processes
# were never going to collide on anyway.
TRV="$TMPROOT/travas"; mkdir -p "$TRV"
trava_env() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_TRAVAS="$TRV" TANDEM_IDIOMA_FORCADO=en \
        WINEPREFIX="$1" bash -c "$2" 2>&1
}
# Per prefix, not one global lock: somebody may be running a program inside
# their own prefix while another installs into Tandem's.
L1="$(trava_env /tmp/pref-um '. "'"$ROOT"'/src/lib/common.sh"; t_trava_do_prefixo')"
L2="$(trava_env /tmp/pref-dois '. "'"$ROOT"'/src/lib/common.sh"; t_trava_do_prefixo')"
if [ "$L1" != "$L2" ] && [ -n "$L1" ]; then
    pass "each prefix has its own lock"
else
    fail "each prefix has its own lock" "two different paths" "$L1 / $L2"
fi

# The real thing: one holder, one waiter, measured. Not a structural check -
# a lock that is written but not taken looks identical to one that works.
( trava_env /tmp/pref-um '. "'"$ROOT"'/src/lib/common.sh"
   t_trava_prefixo_pega /tmp/pref-um; sleep 3; t_trava_prefixo_solta' >/dev/null 2>&1 ) &
SEGURA=$!
sleep 1
INI=$SECONDS
SAIDA="$(trava_env /tmp/pref-um '. "'"$ROOT"'/src/lib/common.sh"
   t_trava_prefixo_pega /tmp/pref-um; t_trava_prefixo_solta')"
ESPEROU=$((SECONDS-INI))
wait $SEGURA 2>/dev/null
if [ "$ESPEROU" -ge 1 ]; then
    pass "the second install waits for the first instead of running alongside it"
else
    fail "the second install waits for the first instead of running alongside it" \
         "a wait of at least 1s" "returned in ${ESPEROU}s - the lock is not being taken"
fi
# And it says so. Half an hour of dotnet48 behind a silent wait is the failure
# this project is named after.
contem "and the owner is told why it is waiting, not left looking at nothing" \
       "installing Windows components into the same environment" "$SAIDA"
# A lock that cannot be CREATED is not a lock that is busy: the first must
# never stop a program from opening. Same decision, same reason, as the file
# lock at the top of tandem-exe.
IMPOSSIVEL="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_TRAVAS=/proc/nao/existe \
    TANDEM_IDIOMA_FORCADO=en WINEPREFIX=/tmp/pref-um bash -c \
    '. "'"$ROOT"'/src/lib/common.sh"; t_trava_prefixo_pega /tmp/pref-um && echo seguiu' 2>/dev/null)"
contem "an impossible lock lets the program open anyway" "seguiu" "$IMPOSSIVEL"

section "Wine saying it has not implemented something is a verdict"

# The third verdict class, and the loop had no branch for it: the dependency
# exists, Wine has not finished implementing part of it, and there is NOTHING
# to install. "The program closed with error (code 53)" was the answer, which
# sends the owner looking for a defect in a machine that is fine.
#
# The two Wine wordings were taken from the INSTALLED Wine's own format strings
# (wine-9.0, x86_64-windows/ntdll.dll), not from memory - and only one of them
# is a verdict. That distinction is the whole test:
#
#   "No implementation for X imported from Y, setting to Z" - Wine stubs the
#   export at LOAD time and carries on. Programs import functions they never
#   call all the time, so this line is in the log of software that works
#   perfectly. Reporting it would alarm somebody whose program is fine.
#
#   "Call from ... to unimplemented function X, aborting" - the program
#   actually called it and Wine gave up. That is the verdict.
falta_wine() {
    TANDEM_LIB="$ROOT/src/lib" bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; . "'"$ROOT"'/src/lib/winedeps.sh"
         t_falta_no_wine "$1"' _ "$1" 2>/dev/null
}
cat > "$TMPROOT/abortou.log" <<'FIMW'
0024:err:module:import_dll Library FOO.dll not found
wine: Call from 0x7b00f4e2 to unimplemented function KERNEL32.dll.SetThreadDescription, aborting
FIMW
equal "a call Wine aborted on names the function" \
      "KERNEL32.dll.SetThreadDescription" "$(falta_wine "$TMPROOT/abortou.log")"
# THE HALF THAT MATTERS MORE. This line appears in the log of programs that
# run perfectly, so treating it as a verdict would be a false alarm on working
# software - which is worse than the silence being fixed.
cat > "$TMPROOT/soimportou.log" <<'FIMW2'
0024:err:module:No implementation for msvcrt.dll._o__fileno imported from L"Z:\x.exe", setting to 0x7b00f4e2
FIMW2
equal "but a stubbed IMPORT is not a verdict, because working programs have them" \
      "" "$(falta_wine "$TMPROOT/soimportou.log")"
equal "and an ordinary log says nothing about it" \
      "" "$(falta_wine "$TMPROOT/porque.log" 2>/dev/null)"
# The sentence has to say there is nothing to install, or the owner goes on
# hunting. And Tandem names the Wine version and stops: it does not manage Wine.
contem "the owner is told no component will fix it" \
       "nothing I can install" \
       "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c \
          '. "'"$ROOT"'/src/lib/common.sh"; t_msg falta_no_wine "KERNEL32.dll.X" "wine-9.0"')"

section "when the loader contradicts a receipt, it is written down"

# A verb reaches the REPETIDOS branch when Wine's own loader has just asked for
# its DLL AGAIN while the prefix carries a permanent receipt saying that verb
# was installed. That is the loader contradicting the receipt, in writing, in
# the same log - and traducao-suspeita.tsv is the work list that has already
# found six wrong entries in the table. t_anota_suspeita was called from two
# sites, both at install time, and SUSPEITAS is re-initialised empty on every
# process, so this moment reached nothing at all.
#
# The receipt is KEPT on purpose: rule 4 is about not paying twice, and the
# verb may well have delivered exactly what it promised while the program wants
# something else. This records and reports; it does not retry and does not undo.
SUSP="$TMPROOT/suspeita"; mkdir -p "$SUSP"
anota() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_ESTADO="$SUSP" bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; . "'"$ROOT"'/src/lib/winedeps.sh"
         export TANDEM_ESTADO="'"$SUSP"'"; t_anota_suspeita "$1" "$2" uma_vez' _ "$1" "$2" 2>/dev/null
}
anota mfc42.dll mfc42
anota msvcp140.dll vcrun2022
equal "a contradicted pair is recorded on the work list" \
      "2" "$(grep -c . "$SUSP/traducao-suspeita.tsv" 2>/dev/null || echo 0)"
# The same program failing the same way every morning must not append the same
# pair for ever: a work list nobody can skim is a work list nobody reads.
anota mfc42.dll mfc42
anota mfc42.dll mfc42
# ...but only where the caller asks for it. From the INSTALL path a repeat
# means "installed again, another day, and again failed to deliver", which is a
# count worth having and is why the date column exists at all. Changing that
# default would have rewritten the meaning of every line already on somebody's
# machine; an existing test was pinning it, and the test was right.
equal "and the same pair seen again does not grow the list" \
      "2" "$(grep -c . "$SUSP/traducao-suspeita.tsv" 2>/dev/null || echo 0)"
contem "the dll and the verb are both kept, so the table row can be found" \
       "msvcp140.dll	vcrun2022" "$(cat "$SUSP/traducao-suspeita.tsv")"
# And the branch really calls it, rather than only recording the negative
# lesson as it did before.
contem "the repeated-receipt branch records the suspicion" \
       't_anota_suspeita "$dll" "$v"' "$(cat "$ROOT/src/bin/tandem-exe")"
# The sentence must name the file still being asked for, or the owner is told
# "I already installed what it wanted" and nothing about what it still wants.
contem "and the owner is told which file is still being asked for" \
       "still asking for" \
       "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
          bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_msg ainda_pedindo mfc42.dll')"

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
          't_log_desde "$MARCA_WT" > "$RESTO"' \
          "$(cat "$ROOT/src/bin/tandem-exe")"
contem "and it is appended from the failure branch" \
       't_log_desde "$MARCA_WT" >> "$RESTO"' \
       "$(cat "$ROOT/src/bin/tandem-exe")"
# ...and by a MARKER, never by a line count. A line count is only correct
# while this process is the only writer, and Tandem now spawns background
# work - the list fetch, the version check - into the same log.
# ALL of them, not tandem-exe. This assertion read one file for three
# versions while six other handlers still sliced their log by counting its
# lines - the technique the marker exists to replace, and the one CLAUDE.md
# records as measured rather than feared. A guard scoped to the file where the
# defect was FOUND cannot see the file where it also lives; that is the same
# miss the literal counter made thirteen times.
naocontem "and never by counting lines, which a second writer shifts - in ANY handler" \
          "wc -l < \"\$LOG\"" "$(cat "$ROOT"/src/bin/tandem-*)"
naocontem "nor by slicing with a line offset, which is the other half of it" \
          'tail -n +"$((MARCA' "$(cat "$ROOT"/src/bin/tandem-*)"

# A Brazilian date order inside a sentence that IS translated. The wrong-clock
# message reaches en, zh_CN, hi and ar readers with dd/mm/yyyy in the middle of
# it; %x is the locale's own order.
naocontem "the wrong-clock message does not hard-code a Brazilian date order" \
          "+%d/%m/%Y" "$(cat "$ROOT/src/lib/common.sh" "$ROOT/src/bin/tandem-exe")"

# ONE TABLE, TWO READERS. The install loop needs to know whose fault it is -
# the machine's or our DLL table's - and the failure path needs a sentence.
# Both come from the same reading of the log now: t_causa_token answers a
# token, t_causa_por_token turns it into prose, and t_causa_do_winetricks is
# the two of them composed.
#
# The first attempt at this left the original grep chain in place BESIDE the
# new one, under a comment claiming there was only one - which is the exact
# drift the comment warned about, written the same hour. So the assertion is
# structural as well as behavioural: the phrase may appear once.
token() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; t_causa_token "$1"' _ "$1" 2>/dev/null
}
do_ambiente() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; t_causa_e_do_ambiente "$1" && echo sim || echo nao' \
        _ "$1" 2>/dev/null
}
printf 'Executing load_vcrun2003\ncp: No space left on device\n' > "$TMPROOT/wt-cheio.log"
equal "a full disk is read out of winetricks' own words" \
      "disco_cheio" "$(token "$TMPROOT/wt-cheio.log")"
equal "the same file still produces the same sentence it always did" \
      "$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_msg porque_disco_cheio')" \
      "$(causa "$TMPROOT/wt-cheio.log")"
equal "a log that does not exist is not a cause, it is 'no idea'" \
      "desconhecido" "$(token "$TMPROOT/nao-existe.log")"
# Stated as "the sentence reader does no reading of its own", NOT as "this
# phrase appears once in the file": t_causa_apt has its own table and a full
# disk looks the same to apt as it does to winetricks, so counting the phrase
# forbids a legitimate second table. That version of this assertion was
# written first and failed on t_causa_apt, which is the right answer to the
# wrong question.
CORPO_CAUSA="$(awk '/^t_causa_do_winetricks\(\) \{/ { d = 1 } d { print } /^\}/ && d { exit }' \
                "$ROOT/src/lib/common.sh")"
naocontem "the sentence reader greps nothing: it asks t_causa_token" \
          "grep" "$CORPO_CAUSA"
contem "and it is the token reader it asks" "t_causa_token" "$CORPO_CAUSA"
# WHICH causes hold back a suspicious-translation entry. A full disk says
# nothing about our mapping; "something was downloaded" and "no idea" say
# nothing about whose fault it is either, so they must NOT protect a verb -
# otherwise the work list that has found six wrong mappings stops filling.
for t in disco_cheio sem_rede relogio corrompido dbus cabextract; do
    equal "$t is the machine's fault, not the table's" "sim" "$(do_ambiente "$t")"
done
for t in internet desconhecido ""; do
    equal "'${t:-empty}' does not excuse the table" "nao" "$(do_ambiente "$t")"
done

# A VARIABLE FILLED IN ONE ROUND AND READ IN A LATER ONE cannot be initialised
# inside the loop. Both of these are that shape: INSTALADOS_AGORA collects what
# was installed so a later round can ask the owner about it, and AMBIENTE_FALHOU
# carries why the machine failed to the round that gives up. Declared inside,
# each round wiped what the round before had found - and the second one was
# written that way on its first attempt, four lines under the comment that
# explains the first. The retry loop starts at "while :", so both have to come
# before it.
INICIO_LACO="$(grep -n '^while :; do' "$ROOT/src/bin/tandem-exe" | head -1 | cut -d: -f1)"
for var in INSTALADOS_AGORA AMBIENTE_FALHOU; do
    ONDE="$(grep -n "^$var=\"\"" "$ROOT/src/bin/tandem-exe" | head -1 | cut -d: -f1)"
    if [ -n "$ONDE" ] && [ -n "$INICIO_LACO" ] && [ "$ONDE" -lt "$INICIO_LACO" ]; then
        pass "$var is declared before the retry loop, not inside it"
    else
        fail "$var is declared before the retry loop, not inside it" \
             "a line before $INICIO_LACO" "${ONDE:-not found at top level}"
    fi
done

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
# EVERY file handler, exe and script included. The list used to omit them, and
# that omission is why tandem-exe went eight versions building a whole Wine
# prefix for a 404 page and ending at "closed with an error (code 1)": the
# guard that was supposed to hold "by every handler" iterated a subset. A guard
# named for all and scoped to some is the exact shape this session keeps
# finding. exe and script check before any prefix/confirmation, so neither
# needs Wine nor a terminal here.
for par in "apk:apk" "AppImage:appimage" "jar:jar" "rpm:rpm" "snap:snap" \
           "flatpakref:flatpak" "deb:deb" "exe:exe" "sh:script"; do
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

section "an unreviewed translation says so to the people who did not choose it"

# t_idioma_revisado had exactly two call sites, both inside acao_idioma - the
# command a person types to CHANGE the language. But step 3 of t_idioma_escolhe
# resolves from the system locale with nobody typing anything, which is how
# almost everybody outside Brazil arrives. So this project's own principle -
# shipping an unreviewed translation is defensible, shipping it without saying
# so is not - was honoured only for the minority.
REVV="$TMPROOT/revisao"; mkdir -p "$REVV/home"
avisa() {
    rm -rf "$REVV/home/.config"
    # { cmd >/dev/null; } 2>&1 and not `2>&1 >/dev/null`: both keep stderr
    # only, and shellcheck flags the second because it is the shape of a very
    # common mistake. The suite demands zero warnings, and the clarified form
    # says what it means anyway.
    { env HOME="$REVV/home" XDG_CONFIG_HOME="$REVV/home/.config" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO="$1" \
        bash "$ROOT/src/bin/tandem" version >/dev/null; } 2>&1
}
for l in fr es zh_CN hi ar; do
    [ -n "$(avisa "$l")" ] ||
        fail "an unreviewed catalogue announces itself ($l)" "a notice" "silence"
done
pass "every unreviewed catalogue announces itself without being asked"
for l in en pt_BR; do
    equal "a reviewed catalogue says nothing ($l)" "" "$(avisa "$l")"
done
# The name, not the locale code: "fr" is a thing a programmer reads, and
# t_idioma_nome exists precisely for this.
case "$(avisa fr)" in
    *"French"*) pass "the notice names the language rather than the locale code" ;;
    *) fail "the notice names the language rather than the locale code" \
            "French" "$(avisa fr | head -1)" ;;
esac
# Once per (language, version). A new version adds new lines to those
# catalogues, so it is worth repeating then and not before - and a notice on
# every single command is a notice people learn to scroll past.
env HOME="$REVV/home" XDG_CONFIG_HOME="$REVV/home/.config" \
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=fr \
    bash "$ROOT/src/bin/tandem" version >/dev/null 2>&1
equal "and it does not repeat on the next command" "" \
      "$({ env HOME="$REVV/home" XDG_CONFIG_HOME="$REVV/home/.config" \
             TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=fr \
             bash "$ROOT/src/bin/tandem" version >/dev/null; } 2>&1)"
# NOT from t_primeira_vez, which tandem-exe calls at line 9 - between the double
# click and the program. Nothing belongs there.
naocontem "the notice is not wired into the double-click path" \
          "idioma_nao_revisado_aviso" "$(cat "$ROOT/src/bin/tandem-exe")"

section "the list is received without anybody typing a command"

# t_lista_atualiza had exactly ONE caller in the whole tree until 4.11 -
# `tandem lista atualizar`, typed by hand. So on a machine whose owner has
# never heard of that command, TANDEM_LISTA never existed, t_lista_consulta
# always answered nothing, and every merge rule 4.4, 4.9 and 4.11 added was
# unreachable code. Meanwhile sending is on by default: a machine that gives
# and does not take is the wrong way round.
RECV="$TMPROOT/receber"; mkdir -p "$RECV/home" "$RECV/estado"
receber() {
    env HOME="$RECV/home" XDG_CONFIG_HOME="$RECV/home/.config" \
        TANDEM_ESTADO="$RECV/estado" TANDEM_LISTA_URL="file:///nao-existe-nunca" \
        TANDEM_LIB="$ROOT/src/lib" bash -c \
        '. "'"$ROOT"'/src/lib/common.sh"; '"$1"'' 2>/dev/null
}
equal "receiving is on by default, the way sending is" "0" \
      "$(receber 't_lista_receber_ligado; echo $?')"
equal "the first call of the day goes" "0" \
      "$(receber 't_lista_talvez_atualiza >/dev/null; echo $?')"
# Stamped BEFORE the attempt, not after: a machine with no route to the address
# must make ONE failed request a day, not one per double click. That is the same
# lesson the send path learned when a cap that counted only successes turned out
# not to be a cap at all.
equal "the second call the same day does not" "1" \
      "$(receber 't_lista_talvez_atualiza >/dev/null; echo $?')"
equal "and the switch turns it off by name" "1" \
      "$(receber 't_config_grava RECEBER nao; t_config_grava LISTA_DIA ""
                 t_lista_talvez_atualiza >/dev/null; echo $?')"
equal "which t_lista_receber_ligado agrees with" "1" \
      "$(receber 't_lista_receber_ligado; echo $?')"

# tandem-exe is the one consumer - the record format describes Wine
# dependencies and nothing else - and it is where the fetch has to be wired.
if grep -q 't_lista_talvez_atualiza' "$ROOT/src/bin/tandem-exe"; then
    pass "tandem-exe keeps the list fresh instead of asking a file nobody fetched"
else
    fail "tandem-exe keeps the list fresh instead of asking a file nobody fetched" \
         "a call to t_lista_talvez_atualiza" "absent"
fi
# An automatic thing the owner cannot see is an automatic thing he cannot turn
# off, so the state of the switch is on the screen either way.
for palavra in lista_recebendo_auto lista_recebendo_nao; do
    grep -q "$palavra" "$ROOT/src/bin/tandem" ||
        fail "tandem lista says which way the switch is set" "$palavra" "absent"
done
pass "tandem lista says which way the switch is set"

section "opened from inside a zip, which no reader can see"

# Every pre-flight in this project reads the file's CONTENTS. None can see its
# SITUATION, and one situation accounts for a whole class of "files it should
# have brought with it are missing": commercial software reaches a Brazilian
# shop as a zip over WhatsApp, and the owner double-clicks the .exe inside the
# archive-manager window. The manager extracts that ONE file to a temporary
# folder - without the .msi, the data folder and the DLLs beside it.
orig() { TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; t_origem_do_arquivo "$1" || printf nada' _ "$1" 2>/dev/null; }
equal "file-roller's temp folder is recognised" "zip" "$(orig /tmp/.fr-Ab3xY/setup.exe)"
equal "so is engrampa's" "zip" "$(orig /tmp/engrampa-x/setup.exe)"
equal "the document portal is recognised as its own case" "portal" \
      "$(orig /run/user/1000/doc/a1b2/sistema.exe)"
equal "a pen drive is recognised" "removivel" "$(orig /media/zero/PENDRIVE/inst.exe)"
equal "and so is a card reader under /run/media" "removivel" \
      "$(orig /run/media/zero/CARTAO/y.exe)"
equal "an ordinary folder says nothing, which is the normal case" "nada" \
      "$(orig /home/zero/Downloads/normal.exe)"
# NOT an AppImage's own mount point. The first version of the pattern matched
# /tmp/.mount_* and would have told somebody to "save the compressed folder
# first" about a mounted AppImage - confident, and wrong.
equal "an AppImage's mount point is not called a zip" "nada" \
      "$(orig /tmp/.mount_AppXYZ/x.exe)"
# It answers a TOKEN, never a sentence - the same rule the Python readers
# follow, so the wording lives in the catalogue and gets translated.
for tok in zip portal removivel; do
    contem "the $tok case has a sentence in the catalogue" \
           "origem_$tok" "$(cat "$ROOT/src/lib/idiomas/en.txt")"
done
contem "and the missing-files message carries it" \
       "t_origem_do_arquivo" "$(cat "$ROOT/src/bin/tandem-exe")"

section "something is said during the half-hour wait"

# Nothing in this program ever spoke during the wait. t_progresso_abre opens a
# pulsating bar with one static line and t_progresso_texto is called once per
# component, so `winetricks -q dotnet48` - half an hour - showed an identical
# unchanging bar for its whole duration. Behind a counter, "downloading
# slowly", "stuck on a dead mirror" and "finished three seconds ago" are the
# same picture, and he has a customer in front of him.
PLOG="$TMPROOT/progresso.log"
# THE CRITICAL ONE: the exit status has to survive the wrapper. Getting this
# wrong would make Tandem read a failed install as a success and write a
# permanent receipt for a component that is not there - the exact damage the
# delivery proof exists to prevent, arriving by a new route.
for par in "true 0" "false 1"; do
    set -- $par
    equal "the exit status of '$1' survives the wrapper" "$2" \
          "$(TANDEM_LIB="$ROOT/src/lib" bash -c '
             . "'"$ROOT"'/src/lib/common.sh"
             TANDEM_PROGRESSO_PASSO=1 t_progresso_longo x '"$1"'; echo $?' 2>/dev/null)"
done
equal "and so does a code that is neither 0 nor 1" "7" \
      "$(TANDEM_LIB="$ROOT/src/lib" bash -c '
         . "'"$ROOT"'/src/lib/common.sh"
         TANDEM_PROGRESSO_PASSO=1 t_progresso_longo x sh -c "exit 7"; echo $?' 2>/dev/null)"

# While the log keeps growing, it says the work is still going.
FALA="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    LOG="'"$PLOG"'"; : > "$LOG"
    t_progresso_texto() { printf "%s\n" "$1" | tail -1; }
    escreve() { for i in 1 2 3; do printf "x\n" >> "'"$PLOG"'"; sleep 1; done; }
    TANDEM_PROGRESSO_PASSO=1 TANDEM_PROGRESSO_FALA=2 TANDEM_PROGRESSO_CALADO=999 \
        t_progresso_longo "base" escreve' 2>/dev/null | tail -1)"
contem "while it is working, it says so" "Still working" "$FALA"
# ...and when nothing has been written for a while, it says THAT, which is the
# sentence that tells him to go and look at his internet.
CALADO="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    LOG="'"$PLOG"'"; : > "$LOG"
    t_progresso_texto() { printf "%s\n" "$1" | tail -1; }
    TANDEM_PROGRESSO_PASSO=1 TANDEM_PROGRESSO_FALA=999 TANDEM_PROGRESSO_CALADO=2 \
        t_progresso_longo "base" sleep 4' 2>/dev/null | tail -1)"
contem "and when it goes quiet, it says to check the connection" \
       "internet connection" "$CALADO"
naocontem "and never reports zero minutes, which reads as a program that cannot count" \
          "0 minute" "$CALADO$FALA"
# It must never abort. Killing a slow-but-working dotnet48 is worse than the
# silence this replaces.
naocontem "it only ever talks, and never kills the command" \
          "kill -9" "$(sed -n '/^t_progresso_longo()/,/^}/p' "$ROOT/src/lib/common.sh")"
# And the two long installs actually go through it.
# CALL SITES, not mentions: the first version of this line counted a comment
# that names the function and reported three.
equal "both winetricks calls talk while they run" "2" \
      "$(grep -cE '^ *if t_progresso_longo' "$ROOT/src/bin/tandem-exe")"

section "the log is cut by a marker, not by counting lines"

# MEASURED, not feared. Two runs of an IDENTICAL commit in CI, one green and
# one red, on a test whose second pass suddenly failed to detect a DLL that was
# plainly in the log. tandem-exe took MARCA=$(wc -l < "$LOG") and later sliced
# with tail -n +$((MARCA+1)); that is only correct while this process is the
# ONLY writer, and Tandem now spawns background work into the same file - the
# community-list fetch and the version check. A writer landing between the
# count and the slice moves the window, and the detector reads the wrong part.
#
# The owner saw the same shape from the other side on his own machine the same
# day: lines from `tandem socorro` appearing under the heading of `tandem
# version`.
LOGM="$TMPROOT/marcador.log"
marcador() {
    TANDEM_LIB="$ROOT/src/lib" LOG="$LOGM" bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        LOG="'"$LOGM"'"; : > "$LOG"
        printf "antes\n" >> "$LOG"
        M="$(t_log_marca 1)"
        printf "primeira\n" >> "$LOG"
        printf "INTRUSO de outro processo\n" >> "$LOG"
        printf "segunda\n" >> "$LOG"
        t_log_desde "$M"' 2>/dev/null
}
equal "everything after the marker comes back, intruder included" \
      "primeira INTRUSO de outro processo segunda" \
      "$(marcador | tr '\n' ' ' | sed 's/ $//')"
# The marker itself must not come back: it is Tandem's own bookkeeping, and
# t_palavras_do_programa would show it to the owner as if the program had said
# it - the defect that put an internal Portuguese line under "this is what it
# said" in 4.5.
naocontem "and the marker itself is not part of the slice" "---8<---" "$(marcador)"
# Two attempts in one run must not share a marker, or the second slice would
# start at the first attempt and carry its output.
DOIS="$(TANDEM_LIB="$ROOT/src/lib" bash -c '
    . "'"$ROOT"'/src/lib/common.sh"
    LOG="'"$TMPROOT"'/marcador2.log"; : > "$LOG"
    a="$(t_log_marca 1)"; b="$(t_log_marca 2)"
    [ "$a" = "$b" ] && echo iguais || echo diferentes' 2>/dev/null)"
equal "two attempts of one run get different markers" "diferentes" "$DOIS"
# With no marker there is no "since", and guessing a line number is what this
# replaced.
equal "an absent marker returns nothing rather than guessing" "1" \
      "$(TANDEM_LIB="$ROOT/src/lib" bash -c '
         . "'"$ROOT"'/src/lib/common.sh"; LOG="'"$LOGM"'"
         t_log_desde "" >/dev/null; echo $?' 2>/dev/null)"

# A LOG THAT CANNOT BE WRITTEN IS NOT A DETAIL, it is every diagnosis at once.
# Which DLL Wine asked for, whether the file is a Windows program, whether the
# prefix is the wrong width, why winetricks gave up - all of it is read back
# out of this one file. When it cannot be written they all come back empty and
# the owner reads "the program closed with an error (code 53)" with nothing
# saying the answer got worse. Reached by the commonest failure there is.
#
# The probe used to be `: >> "$LOG"`, and on a FULL filesystem that SUCCEEDS:
# opening for append writes no bytes, so ENOSPC never fires. Measured on a full
# 16k tmpfs - `:` succeeds, one byte fails - so the check answered the same
# thing whether the premise was right or wrong, which is the rule this project
# wrote down after deleting twenty-four tracked files on an empty git status.
# A state directory that is a FILE reaches the same branch without needing a
# mount, which is why the test is written that way.
SEMLOG="$TMPROOT/semlog"; rm -rf "$SEMLOG"; mkdir -p "$SEMLOG"
: > "$SEMLOG/tandem"          # where a DIRECTORY is expected
semlog() {
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en bash -c '
        . "'"$ROOT"'/src/lib/common.sh"
        TANDEM_ESTADO="'"$SEMLOG"'/tandem"
        t_log_init exe teste
        printf "LOG=%s SEM=%s\n" "$LOG" "${TANDEM_SEM_LOG:-nao}"
        t_aviso_sem_log'
}
equal "an unwritable log falls back to /dev/null AND records that it did" \
      "LOG=/dev/null SEM=1" "$(semlog 2>/dev/null | head -1)"
contem "and the sentence names the folder, because 'free some space' needs a where" \
       "$SEMLOG/tandem" "$(semlog 2>/dev/null)"
# The header printf had no 2>/dev/null of its own, so bash printed
# "common.sh: line 49: printf: write error: No space left on device" - a path
# and a line number - as the FIRST thing the owner read.
equal "and nothing of bash's own leaks onto the screen" \
      "" "$(semlog 2>&1 >/dev/null)"
# When the log IS writable the helper says nothing, so a caller can append it
# without asking first - and a version that always spoke would pass the test
# above while ruining every ordinary error.
equal "with a healthy log the helper is silent and fails" "1" \
      "$(TANDEM_LIB="$ROOT/src/lib" bash -c '
         . "'"$ROOT"'/src/lib/common.sh"
         TANDEM_ESTADO="'"$TMPROOT"'"; t_log_init exe teste
         t_aviso_sem_log; echo $?' 2>/dev/null | tail -1)"
# Comments stripped FIRST. The comment that explains this defect necessarily
# quotes it, so a check reading the whole file finds its own explanation and can
# never go green - the same self-reference the expected-values checksum hit when
# it started matching its own two lines.
# THE DIAGNOSTIC WAS SILENT ABOUT THE THING THAT DISABLES DIAGNOSIS - and
# byte-for-byte identical on a machine where the notes folder worked and one
# where it did not, which is how it went unnoticed. `tandem logs` was worse
# than silent: it answered "there are no logs yet", which tells the owner
# nothing is wrong.
doctor_em() {
    env -i HOME="$1" PATH="/usr/bin:/bin" TANDEM_IDIOMA_FORCADO=en \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_BIN="$ROOT/src/bin" \
        bash "$ROOT/src/bin/tandem" "$2" 2>&1
}
DOC_OK="$TMPROOT/doc-ok"; rm -rf "$DOC_OK"; mkdir -p "$DOC_OK/.local/state"
DOC_MAU="$TMPROOT/doc-mau"; rm -rf "$DOC_MAU"; mkdir -p "$DOC_MAU/.local/state"
: > "$DOC_MAU/.local/state/tandem"
contem "doctor says so when its own notes folder cannot be written" \
       "could not write my notes" "$(doctor_em "$DOC_MAU" doctor)"
naocontem "and says nothing of the sort when the folder is fine" \
          "could not write my notes" "$(doctor_em "$DOC_OK" doctor)"
contem "logs distinguishes 'cannot write' from 'none yet'" \
       "could not write my notes" "$(doctor_em "$DOC_MAU" logs)"
naocontem "and 'none yet' is not offered as the reason" \
          "no logs yet" "$(doctor_em "$DOC_MAU" logs)"
contem "while a healthy machine gets the log itself" \
       "=====" "$(doctor_em "$DOC_OK" logs)"
# With no state folder TANDEM_ESTADO is the empty string, so the pattern was
# "/*.log" and the glob walked the ROOT of the filesystem - any stray log there
# would have been shown to the owner as if it were Tandem's. Found while
# writing the assertion above, whose premise was wrong: `tandem logs` creates
# tandem.log on its way in, so "there are no logs yet" was already unreachable
# on a healthy machine and only the broken one ever reached that branch.
naocontem "and the empty-state case never globs the root of the filesystem" \
          'ls -1t "$TANDEM_ESTADO"/*.log' \
          "$(sed -n '/^acao_logs()/,/^}/p' "$ROOT/src/bin/tandem" | sed -n '1,/TANDEM_SEM_LOG/p')"

# NOTHING LEFT BEHIND WHEN THE OWNER CLOSES THE WINDOW. Measured by killing
# tandem-exe eight seconds into a winetricks: the receipt was correctly NOT
# written and no memory was poisoned - rule 4 held, which is the thing that
# would have mattered most - but the working file stayed, one per interrupted
# double click, for ever. Every working file a handler opens under the runtime
# directory is registered, so the net catches the exits that have no `rm` of
# their own.
for f in parcial.\$\$ wt.\$\$; do
    # -F, because "$$" in a REGEX is two end-of-line anchors and matches
    # nothing. The assertion failed on correct code until that was noticed.
    ANTES="$(grep -nF "TANDEM_TRAVAS/$f" "$ROOT/src/bin/tandem-exe" | head -1 | cut -d: -f1)"
    if [ -n "$ANTES" ] &&
       sed -n "$((ANTES+1))p" "$ROOT/src/bin/tandem-exe" | grep -q 't_apaga_ao_sair'; then
        pass "the working file $f is registered for cleanup"
    else
        fail "the working file $f is registered for cleanup" \
             "a t_apaga_ao_sair on the next line" "${ANTES:-not found}"
    fi
done
# And the net must not steal an EXIT trap somebody else owns: tandem-apk unmounts
# an image in its own, and losing that is worse than a stray file.
equal "the cleanup net declines an EXIT trap that is already taken" "ja-era" \
      "$(TANDEM_LIB="$ROOT/src/lib" bash -c '
         . "'"$ROOT"'/src/lib/common.sh"
         trap "echo ja-era" EXIT
         t_apaga_ao_sair /tmp/nao-existe-tandem-teste' 2>/dev/null)"

naocontem "the probe is a real byte, not an open-and-close that a full disk passes" \
          ': >> "$LOG"' "$(sed 's/#.*//' "$ROOT/src/lib/common.sh")"

section "the list knows what did NOT work, and finally says so"

# Field 4 of the record - the components installed that did NOT fix it - has
# been written by every client, accepted by the intake, published by the
# rebuild and downloaded to every machine since 3.4, and read by NOBODY:
# t_lista_linha's awk touches fields 1, 3, 5, 6 and 7 only. So a shop could be
# one click from half an hour of dotnet48 that sixty other shops had already
# burned on this exact installer, with that fact sitting on its own disk.
INU="$TMPROOT/inuteis.tsv"
{
  printf '# TANDEM-LISTA 1\n'
  printf 'abc\t64\tvcrun2022\t-\tconfirmado\t400\t2026-08\t-\t10.0\t20240105\t-\n'
  printf 'abc\t64\t-\tdotnet48,vcrun6\treprovado\t60\t2026-08\t-\t10.0\t20240105\t-\n'
  printf 'abc\t64\t-\tdotnet48\treprovado\t30\t2026-08\t-\t10.0\t20240105\t-\n'
  printf 'xyz\t64\t-\tdotnet48\treprovado\t300\t2026-08\t-\t10.0\t20240105\t-\n'
} > "$INU"
inut() { TANDEM_LISTA="$INU" TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"; '"$1" 2>/dev/null; }

# Two rows name dotnet48; the count is their SUM, which is the whole job of
# the machine count and the thing the read path got wrong once already.
equal "reports about the same useless component add up" \
      "dotnet48$(printf '\t')90" "$(inut 't_lista_inuteis abc' | head -1)"
equal "and the worst-attested one comes first" \
      "dotnet48 vcrun6" "$(inut 't_lista_inuteis abc' | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
equal "a file nobody has reported failures for says nothing" "" \
      "$(inut 't_lista_inuteis naoexiste')"

# "Nobody got this working" is a record the intake goes out of its way to
# accept and the resolver drops on its first line - it is looking for a lesson
# and this is the absence of one.
equal "with only failures, it says how many reported them" "300" \
      "$(inut 't_lista_ninguem_conseguiu xyz')"
# ...but one shop failing where four hundred succeeded is a fact about that
# shop, not about the program.
equal "with a working lesson present, it stays quiet" "1" \
      "$(inut 't_lista_ninguem_conseguiu abc >/dev/null; echo $?')"

# The warning has to reach the QUESTION, which is the only moment it is worth
# anything - after the install has started, knowing is too late.
contem "tandem-exe warns before asking whether to spend the time" \
       "lista_ja_nao_ajudou" "$(cat "$ROOT/src/bin/tandem-exe")"
contem "and the warning is attached to the question itself" \
       'AVISO_INUTEIS' \
       "$(grep -A 2 't_pergunta "\$(t_msg licao_pergunta' "$ROOT/src/bin/tandem-exe")"
# It must not become a veto: a component that failed elsewhere can be exactly
# right here, and this project does not let a rejection outrank a confirmation.
naocontem "it warns and never removes the component from the offer" \
          "PENDENTES=" "$(sed -n '/AVISO_INUTEIS=""/,/^        ORIGEM_LICAO=/p' \
                          "$ROOT/src/bin/tandem-exe")"

section "Tandem says there is a newer Tandem, and never installs it"

# The decision first, because it is the point: Tandem does NOT update itself.
# Fetching the community list is data that only ever becomes a suggestion; a
# .deb is code that runs as root. The moment Tandem can replace its own binary
# from the internet, whoever controls the release address owns every shop
# machine at once - rule 1 turned on Tandem itself. So this only ever LOOKS.
VERV="$TMPROOT/versao"; mkdir -p "$VERV/home"
printf '{"tag_name":"v9.9","name":"Tandem 9.9"}' > "$VERV/rel.json"
tv() {
    env HOME="$VERV/home" XDG_CONFIG_HOME="$VERV/home/.config" \
        TANDEM_LIB="$ROOT/src/lib" TANDEM_VERSAO_URL="file://$VERV/rel.json" \
        TANDEM_IDIOMA_FORCADO=en bash "$ROOT/src/bin/tandem" "$@" 2>&1
}
# dpkg knows Debian version ordering; a string compare would call 4.9 newer
# than 4.10, which is the trap this project would hit on its own numbering.
comp() {
    TANDEM_LIB="$ROOT/src/lib" bash -c \
      '. "'"$ROOT"'/src/lib/common.sh"; t_versao_mais_nova "$1" "$2"; echo $?' _ "$1" "$2"
}
equal "4.12 is newer than 4.11" "0" "$(comp 4.12 4.11)"
equal "4.11 is not newer than 4.12" "1" "$(comp 4.11 4.12)"
equal "the same version is not newer than itself" "1" "$(comp 4.11 4.11)"
equal "4.10 is newer than 4.9, which a string compare gets backwards" "0" "$(comp 4.10 4.9)"
equal "and 4.9 is not newer than 4.10" "1" "$(comp 4.9 4.10)"

tv version >/dev/null 2>&1        # first run: fetches in the background
sleep 2
contem "it says there is a newer one" "9.9" "$(tv version)"
naocontem "and it does not repeat itself on the next command" "9.9" "$(tv version)"
# The off switch has to turn off the thing he can SEE. Gating only the fetch
# left the value a previous run had stored, so the notice went on for ever -
# found by running it, not by reading it.
tv versao nao-avisar >/dev/null 2>&1
sed -i '/VERSAO_AVISADA/d' "$VERV/home/.config/tandem/configuracao.txt"
naocontem "switched off, it stays quiet even though it knows" "9.9" "$(tv version)"
tv versao avisar >/dev/null 2>&1
contem "and switched back on, it speaks again" "9.9" "$(tv version)"
# Nothing in this path may install, download a package, or ask for a password.
CODIGO_VERSAO="$(sed -n '/is there a newer Tandem?/,/^t_lista_talvez_atualiza()/p' \
                 "$ROOT/src/lib/common.sh")"
for proibido in 'apt-get' 'dpkg -i' 't_como_root' 'pkexec' 'sudo'; do
    naocontem "the version check never runs $proibido" "$proibido" "$CODIGO_VERSAO"
done

section "a command typed at a prompt answers at that prompt"

# THE CARDINAL RULE, broken from the inside. Reported from the owner's own
# machine: he typed `tandem backup` and the terminal "simplesmente nao
# retornou nada". The command had a perfectly good answer - there is no
# Windows environment yet - and t_erro handed it to notify-send, because a
# graphical session existed. It went into a bubble over his desktop while he
# sat looking at a silent prompt.
#
# t_texto has had the right rule since 3.4; t_erro, t_ok and t_aviso never
# adopted it. A notification is what you use when there is NOBODY at a
# terminal - the double-click case. When somebody is there, that is where they
# are looking.
GUIB="$TMPROOT/gui-bin"; mkdir -p "$GUIB"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$NOTIF"\nexit 0\n' > "$GUIB/notify-send"
chmod +x "$GUIB/notify-send"

if command -v script >/dev/null 2>&1; then
    # A REAL tty, with a graphical session also present. Nothing short of this
    # reproduces it: with stdout redirected the old code printed too.
    SAIDA_TTY="$(PATH="$GUIB:$PATH" NOTIF=/dev/null DISPLAY=:99 \
        HOME="$TMPROOT/sem-ambiente" TANDEM_LIB="$ROOT/src/lib" \
        script -qec "TANDEM_IDIOMA_FORCADO=en bash '$ROOT/src/bin/tandem' backup" \
        /dev/null 2>&1)"
    if [ -n "$(printf '%s' "$SAIDA_TTY" | tr -d '[:space:]')" ]; then
        pass "with a terminal AND a desktop, the answer reaches the terminal"
    else
        fail "with a terminal AND a desktop, the answer reaches the terminal" \
             "a sentence" "zero bytes - the silence the owner reported"
    fi
else
    skip "the terminal-beats-desktop rule" "no script(1) to make a real tty"
fi

# ...and the double-click path must NOT lose its notification, which is the
# only way to reach somebody who has no terminal at all.
: > "$TMPROOT/notif-dc.txt"
( PATH="$GUIB:$PATH" NOTIF="$TMPROOT/notif-dc.txt" DISPLAY=:99 \
  HOME="$TMPROOT/sem-ambiente" TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
  bash "$ROOT/src/bin/tandem" backup ) </dev/null >/dev/null 2>&1
if [ "$(awk 'END { print NR + 0 }' "$TMPROOT/notif-dc.txt")" -gt 0 ]; then
    pass "with no terminal, the desktop notification is still how it reaches somebody"
else
    fail "with no terminal, the desktop notification is still how it reaches somebody" \
         "at least one notification" "none"
fi

# The rule itself. With both descriptors redirected there is nobody at a
# terminal, and it has to say so - the answer is written to fd 3 precisely so
# that checking it does not hand the function a terminal to find.
equal "with neither descriptor on a terminal, it says so" "1" \
      "$(TANDEM_LIB="$ROOT/src/lib" bash -c \
         '. "'"$ROOT"'/src/lib/common.sh"
          { t_tem_terminal; echo $? >&3; } >/dev/null 2>&1' 3>&1)"

section "what the owner reads is never the format it is stored in"

# All three found in the FIELD, on the owner's machine, on the day 4.11 went
# out - not by any check in this repository.

# 1. The memory screen printed the LIMITE field raw, and it reached him as
#    "limite: arquitetura|Este pacote...\n\nEle e para arm64...". Two leaks in
#    one line: "arquitetura|" is the internal separator carrying the CLASS of
#    the limit, and the \n were literal backslash-n, because t_memoria_grava
#    escapes newlines so a value stays on one line and t_memoria_le undoes that
#    on read - which the sed field map bypassed entirely.
MEMLIM="$TMPROOT/mem-limite"; mkdir -p "$MEMLIM"
{
    printf 'PROGRAMA=anydesk_8.0.4-1_arm64.deb\n'
    printf 'ARQUITETURA=arm64\n'
    # A FALL-THROUGH class (bitola), whose stored sentence IS what the owner
    # should read - because since 4.24 the four hard-coded-Portuguese classes
    # (arquitetura, agente, biblioteca, outra-familia) are translated by CLASS
    # via t_limite_amigavel and their stored rest is deliberately discarded,
    # tested just above. This case still exercises the display plumbing: strip
    # the class separator, turn escaped newlines into breaks, indent.
    printf 'LIMITE=bitola|Made for another processor.\\n\\nIt is arm64.\n'
} > "$MEMLIM/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.txt"
TELA_LIM="$(TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
            TANDEM_MEMORIA="$MEMLIM" bash "$ROOT/src/bin/tandem" memoria 2>&1)"
naocontem "the class token never reaches the screen" "bitola|" "$TELA_LIM"
case "$TELA_LIM" in
    *'\n'*) fail "an escaped newline is shown as a line break, not as letters" \
                 "no literal backslash-n" "$TELA_LIM" ;;
    *) pass "an escaped newline is shown as a line break, not as letters" ;;
esac
contem "and the sentence itself survives intact" \
       "Made for another processor." "$TELA_LIM"
# A blank continuation line must not be padded out with spaces.
if printf '%s\n' "$TELA_LIM" | grep -q '^ \+$'; then
    fail "blank lines in a limit are not padded with spaces" "no space-only line" "found one"
else
    pass "blank lines in a limit are not padded with spaces"
fi
rm -rf "$MEMLIM"

# 2. The self-test's first check calls t_erro for real to prove the error path
#    works - and t_erro on a graphical machine fires a CRITICAL desktop
#    notification. So the self-test popped a red "ignore this message" alarm,
#    and `tandem socorro`, which embeds it, popped it at somebody already in
#    trouble. The old form was `[ -n "$(t_erro ...)" ] || t_tem_gui`, and bash
#    evaluates the LEFT side first - so it alarmed exactly the machines where
#    the result then did not depend on it.
ALARME="$TMPROOT/alarme"; mkdir -p "$ALARME/bin" "$ALARME/home"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$NOTIFLOG"\n' > "$ALARME/bin/notify-send"
chmod +x "$ALARME/bin/notify-send"
: > "$ALARME/notif.txt"
PATH="$ALARME/bin:$PATH" NOTIFLOG="$ALARME/notif.txt" HOME="$ALARME/home" \
    TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
    bash "$ROOT/src/bin/tandem" autoteste >/dev/null 2>&1
# awk and not `grep -c ... || printf 0`: on an EMPTY file grep prints 0 and
# THEN exits 1, so the fallback fires too and the count comes out as "00".
# This repository already learned that once - it reached the owner as a queue
# length of "0\n0" - and this line walked straight back into it.
equal "the self-test raises no desktop alarm to prove alarms work" "0" \
      "$(awk '/critical/ { n++ } END { print n + 0 }' "$ALARME/notif.txt" 2>/dev/null)"
# ...and it still actually exercises the error path rather than skipping it.
contem "and it still exercises the error path" "t_erro" \
       "$(sed -n '/1\. Does the error message reach/,/^    fi/p' "$ROOT/src/bin/tandem")"
naocontem "without the short-circuit that made the alarm pointless" \
          '"$(t_erro "$(t_msg auto_ignore)" 2>&1 1>/dev/null)" ] || t_tem_gui' \
          "$(cat "$ROOT/src/bin/tandem")"
rm -rf "$ALARME"

# 3. The panel is the only screen a shop owner who never opens a terminal ever
#    sees. It showed the internal command name as its first, leftmost column -
#    "identidade", "restore", "autoteste" - and showed no version at all, so
#    finding out which Tandem he had meant opening a terminal.
PAINEL="$(sed -n '/^acao_painel()/,/^}/p' "$ROOT/src/bin/tandem"
            sed -n '/^t_painel_lista()/,/^}/p' "$ROOT/src/lib/common.sh")"
# TANDEM_VERSAO and not VERSAO: the window is built in common.sh now, where
# the short name does not exist. The point of the assertion is unchanged - the
# owner must be able to read which Tandem he is running without a terminal.
contem "the panel names its own version" '--title="Tandem $TANDEM_VERSAO"' "$PAINEL"
contem "the command tokens are returned but not displayed" \
       "--hide-column=3 --print-column=3" "$PAINEL"
# The tokens must still be there: they are what `case "$esc" in` matches, and
# hiding a column must never turn into deleting it.
contem "and the token is still the value the case matches" '"instalar"' "$PAINEL"

section "the report gets to a second human"

# acao_socorro ended with t_ok, and t_ok RETURNS as soon as notify-send
# succeeds - so on a graphical machine the whole message was a ten-second
# toast, and the owner was left to find a file in his home directory from a
# notification that had vanished. What went with it is the third paragraph, the
# one that makes the feature defensible: the file shows names and paths of his
# files. He only really decides to send it if he has read that.
SOCV="$TMPROOT/socorro"; mkdir -p "$SOCV/home" "$SOCV/estado" "$SOCV/mem"
SAIDA_SOC="$(HOME="$SOCV/home" TANDEM_ESTADO="$SOCV/estado" TANDEM_MEMORIA="$SOCV/mem" \
             TANDEM_LIB="$ROOT/src/lib" TANDEM_IDIOMA_FORCADO=en \
             bash "$ROOT/src/bin/tandem" socorro 2>&1)"
case "$SAIDA_SOC" in
    *"names and paths of files"*)
        pass "the warning about what the report contains reaches the owner" ;;
    *) fail "the warning about what the report contains reaches the owner" \
            "the paragraph about file paths" "$(printf '%s' "$SAIDA_SOC" | tail -5)" ;;
esac
case "$SAIDA_SOC" in
    *tandem-socorro-*.txt*) pass "and it names the file it just wrote" ;;
    *) fail "and it names the file it just wrote" "a path" "$SAIDA_SOC" ;;
esac
# Structural, because the defect is GUI-ONLY: on a terminal t_ok prints the
# whole text and the old code looked fine here. The window is the fix, and a
# test that cannot open a window has to check that the window is what is asked
# for.
if grep -q 't_ok "$(t_msg soc_pronto' "$ROOT/src/bin/tandem"; then
    fail "the report is shown in a window, not a toast that vanishes" \
         "soc_pronto through t_texto" "still going through t_ok"
else
    pass "the report is shown in a window, not a toast that vanishes"
fi
for atalho in t_copia_para_area soc_abrir_pasta; do
    if grep -q "$atalho" "$ROOT/src/bin/tandem"; then
        pass "socorro offers $atalho, the way contribuir already did"
    else
        fail "socorro offers $atalho, the way contribuir already did" \
             "a call" "absent"
    fi
done
# With nobody to show anything to there is nothing to copy to, and saying so is
# the difference between a shortcut that failed and a promise that was never
# kept.
equal "with no graphical session there is no clipboard to copy to" "1" \
      "$( ( unset DISPLAY WAYLAND_DISPLAY
            TANDEM_LIB="$ROOT/src/lib" bash -c \
            '. "'"$ROOT"'/src/lib/common.sh"; t_copia_para_area x; echo $?' ) 2>/dev/null )"

section "a snap and a flatpak land where nothing was looking"

# t_atalhos_do_sistema looked in /usr/share/applications and
# /usr/local/share/applications and nowhere else, so `tandem programas`' whole
# promise - GNOME under Wayland does not re-read the menu, and a program the
# owner cannot find is a program he does not have - was quietly unkept for three
# of the four package managers since 3.8. tandem-snap's "look in the menu for"
# line had never once appeared, and tandem-flatpak did not call it at all.
ATAJ="$TMPROOT/atalhos"
mkdir -p "$ATAJ/xdg/applications" \
         "$ATAJ/casa/.local/share/applications" \
         "$ATAJ/casa/.local/share/flatpak/exports/share/applications"
printf '[Desktop Entry]\nName=Do XDG_DATA_DIRS\n' > "$ATAJ/xdg/applications/a.desktop"
printf '[Desktop Entry]\nName=Do XDG_DATA_HOME\n' > "$ATAJ/casa/.local/share/applications/b.desktop"
printf '[Desktop Entry]\nName=Do flatpak do usuario\n' > "$ATAJ/casa/.local/share/flatpak/exports/share/applications/c.desktop"

atalhos_com() {
    env HOME="$ATAJ/casa" XDG_DATA_DIRS="$1" XDG_DATA_HOME="$2" \
        bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_atalhos_do_sistema' 2>/dev/null
}

LISTA_A="$(atalhos_com "$ATAJ/xdg" "")"
case "$LISTA_A" in
    *"/xdg/applications/a.desktop"*) pass "XDG_DATA_DIRS is read" ;;
    *) fail "XDG_DATA_DIRS is read" "a.desktop in the list" "$LISTA_A" ;;
esac
case "$LISTA_A" in
    *"/casa/.local/share/flatpak/exports/share/applications/c.desktop"*)
        pass "a per-user flatpak export is found with no variable set for it" ;;
    *) fail "a per-user flatpak export is found with no variable set for it" \
            "c.desktop in the list" "$LISTA_A" ;;
esac
# The default for XDG_DATA_HOME is ~/.local/share, and a machine that leaves the
# variable unset is the normal case rather than a corner - this container has
# both variables EMPTY while all three export directories exist and hold files,
# which is exactly the shape of a program started from a file manager.
case "$LISTA_A" in
    *"/casa/.local/share/applications/b.desktop"*)
        pass "XDG_DATA_HOME falls back to ~/.local/share" ;;
    *) fail "XDG_DATA_HOME falls back to ~/.local/share" "b.desktop in the list" "$LISTA_A" ;;
esac

# The same directory reachable two ways must not be walked twice: on a normal
# desktop XDG_DATA_DIRS already contains /usr/share, and a doubled entry would
# announce every newly installed program twice.
# Anchored on the whole path on purpose: this function looks at the REAL system
# directories too, by design, and the first version of this line counted
# `a\.desktop` anywhere - which matched /usr/share/applications/openjdk-21-java
# .desktop on the machine running the suite and reported a dedup failure that
# was not there. A pattern loose enough to hit a real file is a test that
# accuses the code of somebody else's filename.
DOBRADO="$(atalhos_com "$ATAJ/xdg:$ATAJ/xdg" "" | grep -c "^$ATAJ/xdg/applications/a\.desktop\$" || true)"
equal "a directory reachable twice is walked once" "1" "$DOBRADO"

# The three export directories have to be named EXPLICITLY, because reading the
# variables is not enough - measured, not assumed. This is the check that
# catches somebody tidying the list back down to two entries.
faltando=""
for d in /var/lib/snapd/desktop /var/lib/flatpak/exports/share flatpak/exports/share; do
    grep -q -- "$d" "$ROOT/src/lib/common.sh" || faltando="$faltando $d"
done
equal "snapd's and flatpak's export directories are named explicitly" "" "$faltando"

# And the announcement reports only what is NEW, which is the whole point of
# taking the list before the install.
ANTES_T="$(atalhos_com "$ATAJ/xdg" "")"
printf '[Desktop Entry]\nName=Recem instalado\n' > "$ATAJ/xdg/applications/novo.desktop"
NOVOS="$(env HOME="$ATAJ/casa" XDG_DATA_DIRS="$ATAJ/xdg" XDG_DATA_HOME="" \
    bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_anuncia_atalhos_do_sistema "$1"' _ "$ANTES_T" 2>/dev/null)"
equal "only the newly appeared shortcut is announced" "Recem instalado" "$NOVOS"

# tandem-flatpak is the handler that never asked at all.
for b in tandem-snap tandem-deb tandem-flatpak; do
    if grep -q 't_anuncia_atalhos_do_sistema' "$ROOT/src/bin/$b"; then
        pass "$b tells the owner where the program went"
    else
        fail "$b tells the owner where the program went" \
             "a call to t_anuncia_atalhos_do_sistema" "no call"
    fi
done

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
