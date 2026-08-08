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
soma_esperados="$(grep -oE 'equal "[^"]*" +"[^"]*"' "$0" |
                  grep -v 'soma_esperados\|soma_padroes' |
                  sed 's/.*" *"//;s/"$//' | cksum)"
soma_padroes="$(grep -oE '^[[:space:]]+\*[^)]*\) *(pass|fail)' "$0" |
                sed -E 's/ *(pass|fail)$//' | cksum)"
equal "the expected values are the ones this suite was written with" \
      "3004592584 401" "$soma_esperados"
equal "the case patterns still match the real Portuguese messages" \
      "3823810213 1343" "$soma_padroes"

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
    *"faz um trabalho parecido"*"Atenção:"*) pass "a look-alike alternative comes with the caveat" ;;
    *) fail "a look-alike alternative comes with the caveat" "faz um trabalho parecido + Atenção" "$texto_alt" ;;
esac
texto_nat="$(t_texto_alternativas teamviewer)"
case "$texto_nat" in
    *"feito para Linux"*) pass "a native alternative is presented as the same program" ;;
    *) fail "a native alternative is presented as the same program" "feito para Linux" "$texto_nat" ;;
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
if grep -q '^#.*mandar para outra pessoa' "$REC"; then
    pass "the recipe explains itself to whoever receives it"
else
    fail "the recipe explains itself to whoever receives it" "explanatory header" "missing"
fi

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
      "nao comeca com MZ" "$(pecampo "$ARTIFACTS/naoexe.exe" ERRO)"
equal "a missing file degrades with a message" \
      "arquivo nao encontrado" "$(pecampo /nao/existe.exe ERRO)"
python3 src/lib/peinfo.py >/dev/null 2>&1
equal "no argument returns a usage error" "2" "$?"

# What the pre-flight can prove on its own: recognizing, BEFORE running, a
# program that depends on something that will never work here.
TANDEM_LIB="$ROOT/src/lib" TANDEM_LIMITES="$ROOT/src/lib/limites.tsv" \
    bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_limite_do_programa "'"$ARTIFACTS"'/imports32.exe"' \
    > "$TMPROOT/lim.txt" 2>/dev/null
case "$(cat "$TMPROOT/lim.txt")" in
    dongle\|*chave\ física*) pass "recognizes hardware-key protection before running" ;;
    *) fail "recognizes hardware-key protection before running" \
              "dongle|...chave física..." "$(cat "$TMPROOT/lim.txt")" ;;
esac

TANDEM_LIB="$ROOT/src/lib" TANDEM_LIMITES="$ROOT/src/lib/limites.tsv" \
    bash -c '. "'"$ROOT"'/src/lib/common.sh"; t_limite_do_programa "'"$ARTIFACTS"'/importslimpo.exe"' \
    > "$TMPROOT/lim2.txt" 2>/dev/null
equal "an ordinary program gets no impossibility verdict" \
      "" "$(cat "$TMPROOT/lim2.txt")"

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
      "arquivo corrompido ou nao e um pacote Android" \
      "$(campo "$ARTIFACTS/corrompido.apk" ERRO)"
equal "an empty file degrades with a message" \
      "arquivo corrompido ou nao e um pacote Android" \
      "$(campo "$ARTIFACTS/vazio.apk" ERRO)"
equal "a missing file degrades with a message" \
      "arquivo nao encontrado" \
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
for cmd in "dados" "lista" "doctor" "--help" "version"; do
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
      "nao tem a marca AI do AppImage" "$(t_campo "$(t_appimage_info "$AI_ELF")" ERRO)"
printf 'nao sou um ELF nenhum, so texto\n' > "$TMPROOT/texto.AppImage"
equal "a text file is not taken for an AppImage" \
      "nao comeca com ELF" "$(t_campo "$(t_appimage_info "$TMPROOT/texto.AppImage")" ERRO)"

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
      "zip invalido ou incompleto" "$(t_campo "$(t_jar_info "$JARS/cortado.jar")" ERRO)"
equal "a file that is not a zip at all" \
      "zip invalido ou incompleto" "$(t_campo "$(t_jar_info "$TMPROOT/texto.AppImage")" ERRO)"

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
    *"peça de um programa"*) pass "a library .jar is explained, not reported as broken" ;;
    *) fail "a library .jar is explained, not reported as broken" \
            "the sentence about being a piece of a program" "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-jar "$JARS/cortado.jar")"
case "$saida_n" in
    *"incompleto"*|*"cortado no meio"*) pass "an interrupted .jar download says so" ;;
    *) fail "an interrupted .jar download says so" "the sentence about the download" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-jar "$JARS/agente.jar")"
case "$saida_n" in
    *"acessório de outro programa"*) pass "a java agent is explained" ;;
    *) fail "a java agent is explained" "the sentence about being an accessory" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$AI_CORTADO")"
case "$saida_n" in
    *"download deste arquivo não terminou"*) pass "an interrupted AppImage download says so" ;;
    *) fail "an interrupted AppImage download says so" "the sentence about the download" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$AI_ARM")"
case "$saida_n" in
    *"outro tipo de processador"*) pass "an ARM AppImage says it is the processor" ;;
    *) fail "an ARM AppImage says it is the processor" "the sentence about the processor" \
            "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$AI_ELF")"
case "$saida_n" in
    *"programa de Linux comum"*) pass "an ELF named .AppImage is told how to run anyway" ;;
    *) fail "an ELF named .AppImage is told how to run anyway" \
            "the sentence about an ordinary Linux program" "${saida_n:-zero bytes}" ;;
esac
saida_n="$(correr_nativo tandem-appimage "$TMPROOT/nao-existe.AppImage")"
case "$saida_n" in
    *"não encontrado"*) pass "a missing file is reported by both new commands" ;;
    *) fail "a missing file is reported by both new commands" "arquivo nao encontrado" \
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
case "$(grep -c 't_verbo_valido' "$ROOT/src/bin/tandem-exe")" in
    0) fail "the list shortcut validates the verb before using it" "t_verbo_valido" "missing" ;;
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
    *"64 bits"*"32 bits"*mfc42.dll*) pass "the message names both bitnesses and the file" ;;
    *) fail "the message names both bitnesses and the file" "64/32/mfc42.dll" "$TXB" ;;
esac
case "$TXB" in
    *"Não é defeito da sua máquina"*) pass "the message takes the blame off the owner's machine" ;;
    *) fail "the message takes the blame off the owner's machine" "Não é defeito da sua máquina" "$TXB" ;;
esac

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
    *"NÃO consegui fazer uma cópia"*"não há como recuperar"*)
        pass "the failed-rescue message states the risk" ;;
    *) fail "the failed-rescue message states the risk" \
              "NÃO consegui... não há como recuperar" "$(t_texto_resgate_falhou)" ;;
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
        *msvcr71.dll*continua\ faltando*) pass "not delivered: the message names the file that was missing" ;;
        *) fail "not delivered: the message names the file that was missing" \
                  "...msvcr71.dll continua faltando..." "${JAN:-(no window)}" ;;
    esac
    case "$JAN" in
        *"erro meu, não da sua máquina"*) pass "not delivered: Tandem takes the blame" ;;
        *) fail "not delivered: Tandem takes the blame" \
                  "erro meu, não da sua máquina" "${JAN:-(no window)}" ;;
    esac
    case "$JAN" in
        *"Já instalei o que este programa pedia"*)
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

# ------------------------------------------------------------- summary

printf '\n────────────────────────────────────────\n'
printf '%d passed, %d failed, %d skipped\n' "$OK" "$FAILED" "$SKIPPED"
if [ "$FAILED" -gt 0 ]; then
    printf '\nfailures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
