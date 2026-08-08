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
RAIZ="$PWD"

OK=0; FALHOU=0; PULOU=0
FALHAS=()

passou()  { OK=$((OK+1));       printf '  ok   %s\n' "$1"; }
falhou()  { FALHOU=$((FALHOU+1)); FALHAS+=("$1"); printf '  FAILED %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }
pulou()   { PULOU=$((PULOU+1)); printf '  --   %s (%s)\n' "$1" "$2"; }
secao()   { printf '\n== %s ==\n' "$1"; }

# igual <name> <expected> <obtained>
igual() {
    if [ "$2" = "$3" ]; then passou "$1"; else falhou "$1" "$2" "$3"; fi
}

# Isolated environment: nothing here may touch the HOME of whoever runs the tests.
TMPRAIZ="$(mktemp -d)"
trap 'rm -rf -- "$TMPRAIZ"' EXIT
export HOME="$TMPRAIZ/casa"
mkdir -p "$HOME"
# No graphical session: this is how the tests exercise the terminal path.
unset DISPLAY WAYLAND_DISPLAY

# The suite tests the REPOSITORY, never the installed package. Without this the
# libraries resolved to /usr/lib/tandem whenever Tandem was installed on the
# machine, and the suite ended up checking the old version - a test that
# approves the wrong code is worse than no test at all.
export TANDEM_LIB="$RAIZ/src/lib"
export TANDEM_VERBOS_TSV="$RAIZ/src/lib/verbos.tsv"
export TANDEM_LIMITES="$RAIZ/src/lib/limites.tsv"
export TANDEM_ALTERNATIVAS="$RAIZ/src/lib/alternativas.tsv"

ARTEFATOS="$TMPRAIZ/artefatos"
python3 tests/mkapk.py "$ARTEFATOS" >/dev/null || { echo "could not generate the artifacts"; exit 1; }

# shellcheck source=../src/lib/common.sh
. "$RAIZ/src/lib/common.sh"
# shellcheck source=../src/lib/winedeps.sh
. "$RAIZ/src/lib/winedeps.sh"

# ----------------------------------------------------------------- syntax

secao "script syntax"
for f in src/bin/* src/lib/*.sh debian/postinst debian/postrm; do
    if bash -n "$f" 2>/dev/null; then passou "bash -n $f"
    else falhou "bash -n $f" "valid syntax" "syntax error"; fi
done

if command -v shellcheck >/dev/null 2>&1; then
    saida="$(LC_ALL=C.UTF-8 shellcheck --shell=bash --exclude=SC1091 \
             --severity=warning --format=gcc \
             src/bin/* src/lib/*.sh debian/postinst debian/postrm 2>&1)"
    if [ -z "$saida" ]; then passou "shellcheck with no warnings"
    else falhou "shellcheck with no warnings" "(nothing)" "$saida"; fi
else
    pulou "shellcheck" "not installed"
fi

# ------------------------------------------------------- DLL detection

secao "Wine dependency detection"

LOG_WINE="$TMPRAIZ/wine.log"
cat > "$LOG_WINE" <<'EOF'
0024:err:module:import_dll Library MSVCP140.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library VCRUNTIME140.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library VCRUNTIME140_1.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library kernel32.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library mscoree.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library d3dx9_43.dll (needed by Z:\p\a.exe) not found
0024:err:module:import_dll Library MinhaLibPropria.dll (needed by Z:\p\a.exe) not found
EOF

igual "three VC++ DLLs become a single verb" \
      "d3dx9 dotnet48 vcrun2022" \
      "$(t_verbos_do_log "$LOG_WINE" | tr '\n' ' ' | sed 's/ $//')"

igual "a DLL that Wine itself implements is ignored" \
      "" \
      "$(t_verbos_do_log "$LOG_WINE" | grep -c kernel32 | sed 's/^0$//')"

igual "the program's own DLL does not become a system dependency" \
      "MinhaLibPropria.dll" \
      "$(t_dlls_sem_traducao "$LOG_WINE")"

igual "a missing log does not break anything" "" "$(t_verbos_do_log /nao/existe)"
igual "an empty log yields no verb" "" "$(: > "$TMPRAIZ/v.log"; t_verbos_do_log "$TMPRAIZ/v.log")"

igual "the friendly name translates the verb" \
      "Visual C++ 2015-2022" "$(t_verbo_amigavel vcrun2022)"
igual "an unknown verb shows up as-is" \
      "coisanova" "$(t_verbo_amigavel coisanova)"

# upper and lower case must not change the result
igual "translation is case-insensitive" \
      "vcrun2022 vcrun2022" \
      "$(t_dll_para_verbo MSVCP140.DLL) $(t_dll_para_verbo msvcp140.dll)"

# ATL comes from the Visual C++ runtime, not from atmlib (Adobe Type Manager).
# The mistake installed the wrong thing, wrote a receipt, and on the next run
# Tandem said "I already installed what this program asked for" and gave up.
igual "the six mappings the auditor fixed" \
      "amstream d3dcompiler_46 wmp11 xinput vcrun2003 vcrun2019" \
      "$(for d in amstream.dll d3dcompiler_46.dll wmasf.dll xinput1_3.dll msvcr71.dll atl140.dll; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d)"; done | sed 's/ $//')"
# And the neighbours that were RIGHT must not have been dragged along.
igual "the correct neighbours remain intact" \
      "quartz wmp9 xact d3dcompiler_47" \
      "$(for d in quartz.dll wmvcore.dll xaudio2_7.dll d3dcompiler_47.dll; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d)"; done | sed 's/ $//')"

igual "atl comes from the Visual C++ of the same year, not from Adobe Type Manager" \
      "vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013 vcrun2019" \
      "$(for d in atl80 atl90 atl100 atl110 atl120 atl140; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d.dll)"; done | sed 's/ $//')"

secao "index generated from winetricks (second opinion)"

igual "the hand-written table takes precedence over the index" \
      "vcrun2022 dotnet48" \
      "$(t_dll_para_verbo msvcp140.dll) $(t_dll_para_verbo mscoree.dll)"

if [ -f "$RAIZ/src/lib/verbos.tsv" ]; then
    n_ind="$(grep -vc '^#' "$RAIZ/src/lib/verbos.tsv")"
    if [ "$n_ind" -gt 150 ]; then
        passou "the index covers $n_ind DLLs"
    else
        falhou "the index covers more than 150 DLLs" ">150" "$n_ind"
    fi
    igual "the index answers for a DLL the hand-written table does not know" \
          "dsound" "$(t_dll_para_verbo dsound.dll)"
    igual "a DLL in neither of the two stays untranslated" \
          "" "$(t_dll_para_verbo MinhaLibPropria.dll)"
    # The tie-break has to understand versions with an omitted dot: dotnet48 is
    # 4.8, dotnet472 is 4.7.2. Comparing as integers would give 472 > 48.
    igual "the index tie-break picks the newest version" \
          "dotnet48" \
          "$(grep -m1 '^mscoree\.dll' "$RAIZ/src/lib/verbos.tsv" | cut -f2)"
else
    pulou "winetricks index" "verbos.tsv missing"
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

if [ -f "$RAIZ/src/lib/verbos.tsv" ]; then
    suspeitos=""
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
            *) suspeitos="$suspeitos $a_dll->$a_mao(winetricks:$a_todos)" ;;
        esac
    done < "$RAIZ/src/lib/verbos.tsv"
    if [ -z "$suspeitos" ]; then
        passou "the hand-written table only promises verbs winetricks confirms"
    else
        falhou "the hand-written table only promises verbs winetricks confirms" \
               "(no suspects)" "$suspeitos"
    fi
fi

if command -v winetricks >/dev/null 2>&1; then
    if python3 tools/indice-winetricks.py --conferir >/dev/null 2>&1; then
        passou "the on-disk index matches the installed winetricks"
    else
        pulou "on-disk index vs installed winetricks" "different winetricks versions"
    fi
else
    pulou "regenerate the index" "winetricks not installed"
fi

secao "Linux alternatives"

igual "recognizes a program that HAS an official Linux version" \
      "nativo" "$(t_alternativas_para teamviewer | head -1 | cut -d'|' -f1)"
igual "recognizes a program that only has a look-alike" \
      "parecido" "$(t_alternativas_para photoshop | head -1 | cut -d'|' -f1)"
igual "the search ignores case, spaces and hyphens" \
      "nativo nativo nativo" \
      "$(for n in TeamViewer 'team viewer' team-viewer; do
             printf '%s ' "$(t_alternativas_para "$n" | head -1 | cut -d"|" -f1)"; done | sed 's/ $//')"
t_alternativas_para "programa-que-ninguem-conhece" >/dev/null 2>&1
igual "an unknown program fails without making things up" "1" "$?"
t_alternativas_para "" >/dev/null 2>&1
igual "an empty name fails without breaking" "1" "$?"

# The difference between "nativo" and "parecido" is the heart of the honesty
# here: saying GIMP is Photoshop would be deceiving the owner.
texto_alt="$(t_texto_alternativas photoshop)"
case "$texto_alt" in
    *"faz um trabalho parecido"*"Atenção:"*) passou "a look-alike alternative comes with the caveat" ;;
    *) falhou "a look-alike alternative comes with the caveat" "faz um trabalho parecido + Atenção" "$texto_alt" ;;
esac
texto_nat="$(t_texto_alternativas teamviewer)"
case "$texto_nat" in
    *"feito para Linux"*) passou "a native alternative is presented as the same program" ;;
    *) falhou "a native alternative is presented as the same program" "feito para Linux" "$texto_nat" ;;
esac

# Every line of the table needs its five columns: a malformed line would show
# up as an empty suggestion right in the owner's face.
malformadas="$(awk -F"\t" '!/^#/ && NF>0 && (NF!=5 || $3=="")' "$TANDEM_ALTERNATIVAS" | wc -l)"
igual "every line of the table has all five columns" "0" "$malformadas"

secao "memory: what Tandem learns"

MEM_A="$ARTEFATOS/imports64.exe"
MEM_B="$ARTEFATOS/importslimpo.exe"

id_a="$(t_memoria_id "$MEM_A")"
igual "the identity has a fixed length" "32" "${#id_a}"
igual "the same file always has the same identity" \
      "$id_a" "$(t_memoria_id "$MEM_A")"
if [ "$id_a" = "$(t_memoria_id "$MEM_B")" ]; then
    falhou "different files have different identities" "different" "equal"
else
    passou "different files have different identities"
fi
# The identity follows the FILE, not the path: a recipe learned here has to
# still hold after the owner moves the program to another folder.
cp "$MEM_A" "$TMPRAIZ/mudou-de-pasta.exe"
igual "the identity survives a change of folder and name" \
      "$id_a" "$(t_memoria_id "$TMPRAIZ/mudou-de-pasta.exe")"
t_memoria_id /nao/existe >/dev/null 2>&1
igual "a missing file has no identity" "1" "$?"

t_memoria_grava "$MEM_A" RESULTADO abriu
igual "writes and reads back" "abriu" "$(t_memoria_le "$MEM_A" RESULTADO)"
t_memoria_grava "$MEM_A" RESULTADO "nao abriu"
igual "writing again replaces, does not duplicate" \
      "nao abriu" "$(t_memoria_le "$MEM_A" RESULTADO)"
igual "  and only one line is left" \
      "1" "$(grep -c '^RESULTADO=' "$(t_memoria_arquivo "$MEM_A")")"

t_memoria_junta "$MEM_A" RESOLVERAM vcrun2022
t_memoria_junta "$MEM_A" RESOLVERAM d3dx9
t_memoria_junta "$MEM_A" RESOLVERAM vcrun2022
igual "the list accumulates without repeating" \
      "vcrun2022 d3dx9" "$(t_memoria_le "$MEM_A" RESOLVERAM)"

igual "the file keeps the program name, so the owner recognizes it" \
      "imports64.exe" "$(t_memoria_le "$MEM_A" PROGRAMA)"
if grep -q '^#' "$(t_memoria_arquivo "$MEM_A")"; then
    passou "the file explains itself in readable text"
else
    falhou "the file explains itself in readable text" "header with #" "missing"
fi

# One program's memory must not leak into another's.
igual "each program has its own memory" "" "$(t_memoria_le "$MEM_B" RESOLVERAM 2>/dev/null)"

secao "evidence gate (proofgate)"

if [ -f "$RAIZ/proofgate.json" ]; then
    passou "the repository declares its own stack to the gate"
    # Without this the gate goes green without running any test: the automatic
    # detection only knows ecosystems with a manifest, and shell has none.
    if grep -q '"test": *"bash tests/run.sh"' "$RAIZ/proofgate.json"; then
        passou "the gate knows how to run this project's suite"
    else
        falhou "the gate knows how to run this project's suite" "commands.test" "missing"
    fi
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$RAIZ/proofgate.json" 2>/dev/null; then
        passou "proofgate.json is valid JSON"
    else
        falhou "proofgate.json is valid JSON" "JSON" "malformed"
    fi
else
    pulou "evidence gate" "proofgate.json missing"
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
COMANDOS="$(sed -n '/^case /,/^esac$/p' "$RAIZ/src/bin/tandem" |
            sed -n 's/^    \([^ )]*\)).*/\1/p' | sed 's/|.*//' |
            grep -vxF -e '""' -e painel -e --primeira-vez -e version \
                     -e help -e '*' -e '' | sort -u)"
n_cmd="$(printf '%s\n' "$COMANDOS" | grep -c .)"
if [ "$n_cmd" -ge 15 ]; then passou "extracted $n_cmd commands from the main case"
else falhou "extracted the commands from the main case" ">=15" "$n_cmd"; fi

for onde in man/tandem.1 README.md LEIAME.md; do
    faltando=""
    for c in $COMANDOS; do
        grep -q "tandem $c" "$RAIZ/$onde" || faltando="$faltando $c"
    done
    igual "every command shows up in $onde" "" "$faltando"
done

# And the other way round: the manual must not promise a command that does not exist.
promete_demais=""
for c in $(grep -oE '^\.BI? "?tandem ([a-z]+)' "$RAIZ/man/tandem.1" |
           awk '{print $NF}' | tr -d '"' | sort -u); do
    grep -q "^  tandem $c\b\|^    $c|" "$RAIZ/src/bin/tandem" ||
        grep -qE "^    $c\||^    $c\)" "$RAIZ/src/bin/tandem" ||
        promete_demais="$promete_demais $c"
done
igual "the manual does not promise a nonexistent command" "" "$promete_demais"

secao "recipes: collective knowledge without a server"

t_memoria_grava "$MEM_A" RESULTADO abriu
t_memoria_grava "$MEM_A" RESOLVERAM "vcrun2022 msxml6"
REC="$TMPRAIZ/receita.txt"
t_receita_exporta "$MEM_A" > "$REC"

if grep -q '^TANDEM_RECEITA=1$' "$REC" && grep -q '^IDENTIDADE=' "$REC"; then
    passou "the recipe declares itself and carries the program identity"
else
    falhou "the recipe declares itself and carries the program identity" \
           "TANDEM_RECEITA + IDENTIDADE" "$(cat "$REC")"
fi
if grep -q '^#.*mandar para outra pessoa' "$REC"; then
    passou "the recipe explains itself to whoever receives it"
else
    falhou "the recipe explains itself to whoever receives it" "explanatory header" "missing"
fi

t_memoria_esquece "$MEM_A" 2>/dev/null
t_receita_importa "$REC" "$MEM_A"
igual "a legitimate recipe is accepted" "0" "$?"
igual "  and becomes memory" "vcrun2022 msxml6" "$(t_memoria_le "$MEM_A" RESOLVERAM)"

# A recipe belongs to the FILE, not to the name. Applying another program's
# recipe would teach the wrong lesson, and nobody would notice.
t_receita_importa "$REC" "$MEM_B" 2>/dev/null
igual "another program's recipe is refused" "3" "$?"
igual "  and does not contaminate the other one's memory" "" "$(t_memoria_le "$MEM_B" RESOLVERAM 2>/dev/null)"

# The defence that matters most: a recipe's verb becomes an argument to
# "winetricks -q". A recipe coming from outside must not carry a command.
for veneno in 'vcrun2022 ;curl|sh' 'a$(rm -rf /)' '../../etc/passwd' 'a b`id`' 'a/b' 'a b c;d'; do
    # Built with grep+printf, not with sed: the poison itself has | and $ and
    # would break sed's delimiter before ever reaching the code under test.
    { grep -v '^RESOLVERAM=' "$REC"; printf 'RESOLVERAM=%s\n' "$veneno"; } > "$TMPRAIZ/veneno.txt"
    t_memoria_esquece "$MEM_A" 2>/dev/null
    t_receita_importa "$TMPRAIZ/veneno.txt" "$MEM_A" 2>/dev/null
    if [ "$?" = 4 ] && [ -z "$(t_memoria_le "$MEM_A" RESOLVERAM 2>/dev/null)" ]; then
        passou "refuses a recipe with an embedded command: $veneno"
    else
        falhou "refuses a recipe with an embedded command: $veneno" "code 4 and nothing written" \
               "$(t_memoria_le "$MEM_A" RESOLVERAM 2>/dev/null)"
    fi
done

printf 'isto nao e receita\n' > "$TMPRAIZ/naorec.txt"
t_receita_importa "$TMPRAIZ/naorec.txt" "$MEM_A" 2>/dev/null
igual "a file that does not declare itself a recipe is refused" "2" "$?"
t_receita_importa /nao/existe "$MEM_A" 2>/dev/null
igual "a missing recipe fails without breaking" "1" "$?"

t_verbo_valido vcrun2022; igual "an ordinary verb name is accepted" "0" "$?"
t_verbo_valido 'a;b';      igual "a name with a semicolon is refused" "1" "$?"
t_verbo_valido '';         igual "an empty name is refused" "1" "$?"
t_verbo_valido "$(printf 'a%.0s' $(seq 1 60))"
igual "an absurdly long name is refused" "1" "$?"

t_memoria_esquece "$MEM_A" 2>/dev/null
t_memoria_grava "$MEM_A" RESULTADO abriu

t_memoria_esquece "$MEM_A"
igual "forgetting really erases" "" "$(t_memoria_le "$MEM_A" RESULTADO 2>/dev/null)"
t_memoria_esquece "$MEM_A" 2>/dev/null
igual "forgetting what does not exist fails without breaking" "1" "$?"

# -------------------------------------------------------- PE pre-flight

secao "pre-flight: reading the .exe without running it"

pecampo() { python3 src/lib/peinfo.py "$1" 2>/dev/null | grep "^$2=" | cut -d= -f2-; }

igual "reads the architecture of a 64-bit PE" \
      "64" "$(pecampo "$ARTEFATOS/imports64.exe" ARQUITETURA)"
igual "reads the architecture of a 32-bit PE" \
      "32" "$(pecampo "$ARTEFATOS/imports32.exe" ARQUITETURA)"
igual "reads the whole import table" \
      "kernel32.dll,msvcp140.dll,vcruntime140.dll" \
      "$(pecampo "$ARTEFATOS/imports64.exe" DLLS)"
igual "normalizes the names to lowercase" \
      "hasp_windows_x64.dll,kernel32.dll" \
      "$(pecampo "$ARTEFATOS/imports32.exe" DLLS)"
igual "a file that is not a PE degrades with a message" \
      "nao comeca com MZ" "$(pecampo "$ARTEFATOS/naoexe.exe" ERRO)"
igual "a missing file degrades with a message" \
      "arquivo nao encontrado" "$(pecampo /nao/existe.exe ERRO)"
python3 src/lib/peinfo.py >/dev/null 2>&1
igual "no argument returns a usage error" "2" "$?"

# What the pre-flight can prove on its own: recognizing, BEFORE running, a
# program that depends on something that will never work here.
TANDEM_LIB="$RAIZ/src/lib" TANDEM_LIMITES="$RAIZ/src/lib/limites.tsv" \
    bash -c '. "'"$RAIZ"'/src/lib/common.sh"; t_limite_do_programa "'"$ARTEFATOS"'/imports32.exe"' \
    > "$TMPRAIZ/lim.txt" 2>/dev/null
case "$(cat "$TMPRAIZ/lim.txt")" in
    dongle\|*chave\ física*) passou "recognizes hardware-key protection before running" ;;
    *) falhou "recognizes hardware-key protection before running" \
              "dongle|...chave física..." "$(cat "$TMPRAIZ/lim.txt")" ;;
esac

TANDEM_LIB="$RAIZ/src/lib" TANDEM_LIMITES="$RAIZ/src/lib/limites.tsv" \
    bash -c '. "'"$RAIZ"'/src/lib/common.sh"; t_limite_do_programa "'"$ARTEFATOS"'/importslimpo.exe"' \
    > "$TMPRAIZ/lim2.txt" 2>/dev/null
igual "an ordinary program gets no impossibility verdict" \
      "" "$(cat "$TMPRAIZ/lim2.txt")"

# ------------------------------------------------------------ PE reading

secao "PE executable architecture"
igual "32-bit PE"  "32"    "$(t_pe_arch "$ARTEFATOS/prog32.exe")"
igual "64-bit PE"  "64"    "$(t_pe_arch "$ARTEFATOS/prog64.exe")"
igual "ARM64 PE"   "arm64" "$(t_pe_arch "$ARTEFATOS/progarm.exe")"
t_pe_arch "$ARTEFATOS/naoexe.exe" >/dev/null 2>&1
igual "a file that is not a PE fails" "1" "$?"
t_pe_arch /nao/existe >/dev/null 2>&1
igual "a missing file fails" "1" "$?"

# ------------------------------------------------------- Wine prefixes

secao "Wine prefix protection"

PREF_NOSSO="$HOME/.local/share/tandem/wine"
PREF_ALHEIO="$HOME/.wine-pdv"
PREF_MARCADO="$HOME/.wine-tandem"
mkdir -p "$PREF_NOSSO/drive_c" "$PREF_ALHEIO/drive_c" "$PREF_MARCADO/drive_c"
touch "$PREF_NOSSO/system.reg" "$PREF_ALHEIO/system.reg" "$PREF_MARCADO/system.reg"
: > "$PREF_MARCADO/.tandem-prefixo"

t_prefixo_protegido "$PREF_ALHEIO";  igual "someone else's prefix is protected" "0" "$?"
t_prefixo_protegido "$PREF_NOSSO";   igual "the default prefix is not protected" "1" "$?"
t_prefixo_protegido "$PREF_MARCADO"; igual "a prefix carrying our mark is not protected" "1" "$?"
t_prefixo_protegido "$HOME/.wine-que-nao-existe"
igual "an unknown prefix is protected" "0" "$?"

# The user's explicit list has to beat even the ownership mark.
mkdir -p "$(dirname -- "$TANDEM_PROTEGIDOS")"
printf '%s\n' "$PREF_MARCADO" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$PREF_MARCADO"
igual "tandem protect beats Tandem's own mark" "0" "$?"
printf '%s\n' "$PREF_NOSSO" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$PREF_NOSSO"
igual "tandem protect also applies to the default prefix" "0" "$?"
: > "$TANDEM_PROTEGIDOS"

# Walks up the tree until it finds the prefix root.
mkdir -p "$PREF_ALHEIO/drive_c/Programas/Sistema"
touch "$PREF_ALHEIO/drive_c/Programas/Sistema/pdv.exe"
igual "finds the prefix root from the file path" \
      "$PREF_ALHEIO" \
      "$(t_prefixo_do_arquivo "$PREF_ALHEIO/drive_c/Programas/Sistema/pdv.exe")"
t_prefixo_do_arquivo "$TMPRAIZ/solto.exe" >/dev/null 2>&1
igual "a file outside any prefix fails" "1" "$?"

secao "first-run scan"

# The scenario that failed on the real machine: two prefixes under ~/.wine* and
# an empty protected list because postinst never found out who had installed.
: > "$TANDEM_PROTEGIDOS"
PREF_FUNDO="$HOME/Programas/PDV/prefixo"
mkdir -p "$PREF_FUNDO/drive_c"
touch "$PREF_FUNDO/system.reg"

t_procura_prefixos

for esperado in "$PREF_ALHEIO" "$PREF_FUNDO"; do
    if grep -qxF -- "$esperado" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
        passou "the scan found $esperado"
    else
        falhou "the scan found $esperado" "on the list" "missing"
    fi
done

if grep -qxF -- "$PREF_NOSSO" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    falhou "the scan ignores Tandem's default prefix" "missing" "on the list"
else
    passou "the scan ignores Tandem's default prefix"
fi
if grep -qxF -- "$PREF_MARCADO" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    falhou "the scan ignores a prefix carrying Tandem's mark" "missing" "on the list"
else
    passou "the scan ignores a prefix carrying Tandem's mark"
fi

# A directory with system.reg but no drive_c is not a Wine prefix.
mkdir -p "$HOME/naoprefixo"; touch "$HOME/naoprefixo/system.reg"
t_procura_prefixos
if grep -qxF -- "$HOME/naoprefixo" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    falhou "system.reg without drive_c does not count as a prefix" "missing" "on the list"
else
    passou "system.reg without drive_c does not count as a prefix"
fi

t_procura_prefixos
igual "running twice does not duplicate the list" \
      "0" "$(sort "$TANDEM_PROTEGIDOS" | uniq -d | wc -l)"

t_protege "$PREF_ALHEIO"; igual "t_protege is idempotent" "0" "$?"
t_protege "/caminho/que/nao/existe"; igual "t_protege refuses an invalid path" "1" "$?"

# The first-run marker has to prevent the repeat.
MARCA_PV="$(dirname -- "$TANDEM_PROTEGIDOS")/.primeira-vez"
rm -f "$MARCA_PV"
t_primeira_vez
igual "the first run leaves the marker" "0" "$([ -f "$MARCA_PV" ]; echo $?)"
: > "$TANDEM_PROTEGIDOS"
t_primeira_vez
igual "the second run does not scan again" "0" "$(wc -l < "$TANDEM_PROTEGIDOS")"
rm -f "$MARCA_PV"; : > "$TANDEM_PROTEGIDOS"

# ------------------------------------------------------------- messages

secao "no message gets lost"

t_tem_gui; igual "without DISPLAY there is no graphical interface" "1" "$?"

t_log_init teste "suite"
igual "an error without a graphical interface goes to the terminal" \
      "Tandem: deu ruim" \
      "$(t_erro "deu ruim" 2>&1 1>/dev/null)"
igual "a warning without a graphical interface goes to the terminal" \
      "Tandem: atencao" \
      "$(t_aviso "atencao" 2>&1 1>/dev/null)"
igual "a success without a graphical interface goes to the terminal" \
      "Tandem: pronto" \
      "$(t_ok "pronto" 2>&1 1>/dev/null)"

t_erro "mensagem que precisa ficar registrada" >/dev/null 2>&1
if grep -q "ERRO: mensagem que precisa ficar registrada" "$LOG" 2>/dev/null; then
    passou "the error is recorded in the log for the post-mortem"
else
    falhou "the error is recorded in the log for the post-mortem" "line in the log" "missing"
fi

t_pergunta "posso?" >/dev/null 2>&1
igual "a question without a graphical interface answers no" "1" "$?"

igual "long text falls back to standard output without a graphical interface" \
      "linha um" "$(printf 'linha um\n' | t_texto 'titulo')"

# With a graphical interface, pipes and files still receive the text: whoever
# writes "tandem doctor > relatorio.txt" wants the report, not a window.
igual "with a display, the pipe still receives the text" \
      "conteudo" \
      "$(DISPLAY=:0 bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf "conteudo\n" | t_texto t' | cat)"
DISPLAY=:0 bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf "conteudo\n" | t_texto t' > "$TMPRAIZ/redir.txt"
igual "with a display, the file still receives the text" \
      "conteudo" "$(cat "$TMPRAIZ/redir.txt")"

# the diagnostics printf must not interpret a % coming from a path
igual "a percent sign in text does not break the output" \
      "50% pronto" "$(printf '%b' "50% pronto")"

secao "MIME types of split packages"

# Without these types a double click on a .xapk never reaches Tandem:
# freedesktop does not know the extension and the system sees only a generic ZIP.
igual "the MIME types file is valid XML" "ok" \
      "$(python3 -c 'import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print("ok")' \
         src/mime/tandem.xml 2>&1 | tail -1)"

for tipo in vnd.android.xapk vnd.android.apks vnd.android.apkm; do
    if grep -q "application/$tipo" src/mime/tandem.xml; then
        passou "declares application/$tipo"
    else
        falhou "declares application/$tipo" "present" "missing"
    fi
    if grep -q "application/$tipo" src/applications/tandem-apk.desktop; then
        passou "  and the .desktop claims the type"
    else
        falhou "  and the .desktop claims the type" "present" "missing"
    fi
    if grep -q "application/$tipo" src/bin/tandem-repair; then
        passou "  and repair reapplies the type"
    else
        falhou "  and repair reapplies the type" "present" "missing"
    fi
done

# Being a subclass of zip is what makes the extension match beat content
# detection: without it the system insists the file is a ZIP.
if grep -q 'sub-class-of.*application/zip' src/mime/tandem.xml; then
    passou "the types are subclasses of application/zip"
else
    falhou "the types are subclasses of application/zip" "sub-class-of zip" "missing"
fi

secao "the progress bar must not kill Tandem"

# Panel finding, confirmed: with the pipe opened write-only, closing the
# progress window sent SIGPIPE and killed the whole process - exit 141, nothing
# in the log, no window. Inside the winetricks loop that cut a dependency
# installation in half.
FZ="$TMPRAIZ/fz"; mkdir -p "$FZ"
printf '#!/bin/sh\nhead -c1 >/dev/null 2>&1\nexit 0\n' > "$FZ/zenity"
chmod +x "$FZ/zenity"
cat > "$TMPRAIZ/prog.sh" <<FIM
export HOME="$HOME"
export PATH="$FZ:\$PATH"
export DISPLAY=:0
. "$RAIZ/src/lib/common.sh"
t_log_init progteste x
t_progresso_abre "instalando"
sleep 0.4
t_progresso_texto "primeiro"
sleep 0.2
t_progresso_texto "segundo"
t_progresso_fecha
echo VIVO
FIM
saida_prog="$(bash "$TMPRAIZ/prog.sh" 2>/dev/null)"; rc_prog=$?
igual "the script survives the progress window being closed" "0" "$rc_prog"
igual "  and reaches the end" "VIVO" "$saida_prog"
if grep -q 'janela de progresso fechada' "$TANDEM_ESTADO/progteste.log" 2>/dev/null; then
    passou "  and records in the log that the window vanished"
else
    falhou "  and records in the log that the window vanished" "line in the log" "missing"
fi

secao "locks: being unable to create one is not the same as it being taken"

igual "locks live in the runtime directory when it exists" \
      "$TMPRAIZ/run/tandem" \
      "$(XDG_RUNTIME_DIR="$TMPRAIZ/run" bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf %s "$TANDEM_TRAVAS"')"
igual "without a runtime directory, falls back to the state folder" \
      "$TANDEM_ESTADO" \
      "$(env -u XDG_RUNTIME_DIR bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf %s "$TANDEM_TRAVAS"')"

# bash does NOT abort when an "exec N>" fails: without telling the two cases
# apart, a full home folder turned into "this program is already opening" and
# exit 0.
igual "exec with an invalid path fails without bringing the script down" \
      "seguiu" \
      "$(bash -c 'if exec 7> /nao/existe/x.lock; then echo travou; else echo seguiu; fi' 2>/dev/null)"

secao "menu shortcuts after an installer"

APPS="$HOME/.local/share/applications/wine/Programs/Coisa"
mkdir -p "$APPS"
ANTES_AT="$(t_atalhos_wine)"
igual "with no shortcut at all, the list comes back empty" "" "$ANTES_AT"

igual "nothing new, nothing announced" \
      "" "$(t_anuncia_atalhos "$ANTES_AT" 2>&1 1>/dev/null)"

: > "$APPS/Coisa Legal.desktop"
saida_at="$(t_anuncia_atalhos "$ANTES_AT" 2>&1 1>/dev/null)"
case "$saida_at" in
    *"Coisa Legal"*) passou "a new shortcut is announced by name" ;;
    *) falhou "a new shortcut is announced by name" "mentions 'Coisa Legal'" "$saida_at" ;;
esac

# Once announced, the same earlier list must not announce it again: the
# comparison has to be against the current state.
DEPOIS_AT="$(t_atalhos_wine)"
igual "an already known shortcut is not re-announced" \
      "" "$(t_anuncia_atalhos "$DEPOIS_AT" 2>&1 1>/dev/null)"

secao "installed programs and uninstallation"

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

igual "reads BOTH registry views (native and 32-bit)" \
      "7-Zip 24.09 (x64) Programa MSI 1.0" \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '{print $2}' | sort | tr '\n' ' ' | sed 's/ $//')"

igual "a system component is left out" \
      "" "$(t_uninstall_dump "$PREF_NOSSO" | grep -c Oculto | sed 's/^0$//')"

igual "an entry with no uninstaller is left out" \
      "" "$(t_uninstall_dump "$PREF_NOSSO" | grep -c SemNada | sed 's/^0$//')"

igual "extracts the silent uninstaller with quotes and a real path" \
      '"C:\Program Files\7-Zip\Uninstall.exe" /S' \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '$1=="7-Zip"{print $3}')"

igual "extracts the key that identifies the program" \
      "{GUID-MSI}" \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '$2=="Programa MSI 1.0"{print $1}')"

igual "t_programas_instalados keeps the key|||name format" \
      "7-Zip|||7-Zip 24.09 (x64)" \
      "$(t_programas_instalados "$PREF_NOSSO" | grep '^7-Zip')"

# The Windows command separator: quoted path + argument.
FALSO="$TMPRAIZ/bin"; mkdir -p "$FALSO"
cat > "$FALSO/wine" <<'FIM'
#!/bin/sh
printf '%s\n' "exe=$1" "args=$*"
FIM
chmod +x "$FALSO/wine"
PATH="$FALSO:$PATH"

igual "runs an uninstaller with a quoted path" \
      'exe=C:\Program Files\7-Zip\Uninstall.exe' \
      "$(t_executa_comando_windows '"C:\Program Files\7-Zip\Uninstall.exe" /S' | head -1)"
igual "  and passes the arguments through" \
      'args=C:\Program Files\7-Zip\Uninstall.exe /S' \
      "$(t_executa_comando_windows '"C:\Program Files\7-Zip\Uninstall.exe" /S' | tail -1)"
igual "runs a command without quotes (MsiExec)" \
      'exe=MsiExec.exe' \
      "$(t_executa_comando_windows 'MsiExec.exe /X{GUID-MSI}' | head -1)"

secao "preparar: Tandem installs what is missing"

# On an empty PATH nothing exists, so the list has to come back complete - that
# way the test does not depend on what is installed on the machine running the
# suite.
faltas="$(PATH=/nao/existe t_pecas_faltando | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')"
igual "with nothing installed, lists everything that is missing" \
      "wine winetricks adb waydroid" "$faltas"
# And with everything present, the list comes back empty.
FINGE="$TMPRAIZ/finge"; mkdir -p "$FINGE"
for c in wine winetricks adb waydroid; do printf '#!/bin/sh\n' > "$FINGE/$c"; chmod +x "$FINGE/$c"; done
igual "with everything installed, there is nothing to prepare" \
      "" "$(PATH="$FINGE" t_pecas_faltando | grep -v '^wine32|' )"

script="$(t_script_instalacao wine wine32 waydroid)"
case "$script" in
    *"apt-get install -y wine winetricks"*) passou "the plan installs wine and winetricks together" ;;
    *) falhou "the plan installs wine and winetricks together" "apt-get install -y wine winetricks" "$script" ;;
esac
case "$script" in
    *"dpkg --add-architecture i386"*) passou "the plan enables 32-bit before wine32" ;;
    *) falhou "the plan enables 32-bit before wine32" "dpkg --add-architecture i386" "(missing)" ;;
esac
case "$script" in
    *"repo.waydro.id"*signed-by*) passou "waydroid comes from the official repository with a key" ;;
    *) falhou "waydroid comes from the official repository with a key" "repo.waydro.id + signed-by" "(missing)" ;;
esac
case "$script" in
    *"waydroid init"*) passou "the plan initializes Android after installing" ;;
    *) falhou "the plan initializes Android after installing" "waydroid init" "(missing)" ;;
esac

# t_como_root: are we root in the tests? then run it directly.
if [ "$(id -u)" = 0 ]; then
    igual "as root, runs directly without asking for a password" \
          "funcionou" "$(t_como_root 'echo funcionou')"
else
    pulou "as root runs directly" "suite running without root"
fi

# Shortcuts: only the ones in our prefix, and an orphan is one that lost its .lnk.
WP="$HOME/.local/share/applications/wine/Programs"
mkdir -p "$WP/7-Zip" "$WP/Alheio"
printf '[Desktop Entry]\nName=7-Zip File Manager\nExec=env WINEPREFIX="%s" wine x\n' \
       "$PREF_NOSSO" > "$WP/7-Zip/7-Zip File Manager.desktop"
printf '[Desktop Entry]\nName=Coisa Alheia\nExec=env WINEPREFIX="%s" wine x\n' \
       "$PREF_ALHEIO" > "$WP/Alheio/Coisa Alheia.desktop"

igual "lists only the shortcuts from our prefix" \
      "1" "$(t_atalhos_nossos | wc -l)"
igual "reads the friendly name of the shortcut" \
      "7-Zip File Manager" "$(t_nome_do_atalho "$WP/7-Zip/7-Zip File Manager.desktop")"

# With the .lnk present, the shortcut is valid and must not be removed.
LNKDIR="$PREF_NOSSO/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/7-Zip"
mkdir -p "$LNKDIR"; : > "$LNKDIR/7-Zip File Manager.lnk"
igual "a shortcut whose program is installed is not removed" "0" "$(t_limpa_atalhos_orfaos)"
igual "  and stays on disk" \
      "0" "$([ -f "$WP/7-Zip/7-Zip File Manager.desktop" ]; echo $?)"

# Without the .lnk it became a button that opens nothing: it has to go.
rm -f "$LNKDIR/7-Zip File Manager.lnk"
igual "an orphan shortcut is removed" "1" "$(t_limpa_atalhos_orfaos)"
igual "  and is gone from disk" \
      "1" "$([ -f "$WP/7-Zip/7-Zip File Manager.desktop" ]; echo $?)"
igual "  and someone else's shortcut was preserved" \
      "0" "$([ -f "$WP/Alheio/Coisa Alheia.desktop" ]; echo $?)"

# Without wine on the PATH the listing fails without breaking the caller.
igual "without wine, the listing degrades in controlled silence" \
      "" "$(PATH=/nao/existe; t_programas_instalados 2>/dev/null)"

secao "Wine architecture"
t_tem_wine64; r64=$?
t_tem_wine32; r32=$?
case "$r64$r32" in
    [01][01]) passou "t_tem_wine64 and t_tem_wine32 return 0 or 1" ;;
    *) falhou "t_tem_wine64 and t_tem_wine32 return 0 or 1" "0 or 1" "$r64$r32" ;;
esac

secao "locale (zenity refuses accents on a nonexistent locale)"

t_locale_existe C.UTF-8;     igual "recognizes an existing locale despite the hyphen" "0" "$?"
t_locale_existe c.utf8;      igual "the comparison ignores case and hyphens" "0" "$?"
t_locale_existe zz_ZZ.UTF-8; igual "refuses a nonexistent locale" "1" "$?"
t_locale_existe "";          igual "refuses an empty locale" "1" "$?"

igual "picks the first candidate that exists" \
      "C.UTF-8" "$(t_locale_utf8 zz_ZZ.UTF-8 C.UTF-8)"
igual "falls back to C.UTF-8 when none exists" \
      "C.UTF-8" "$(t_locale_utf8 zz_ZZ.UTF-8 yy_YY.UTF-8)"
igual "with no candidate at all it still returns something usable" \
      "C.UTF-8" "$(t_locale_utf8)"
igual "an empty candidate does not disturb the choice" \
      "C.UTF-8" "$(t_locale_utf8 "" "" C.UTF-8)"

# What matters in the end: the chosen locale has to produce a UTF-8 charmap,
# because that is what decides whether zenity accepts or refuses accented text.
igual "the chosen locale produces a UTF-8 charmap" \
      "UTF-8" "$(LC_ALL="$(t_locale_utf8 zz_ZZ.UTF-8)" locale charmap 2>/dev/null)"

# -------------------------------------------------------------- apkinfo

secao "Android package inspection"

campo() { python3 src/lib/apkinfo.py "$1" 2>/dev/null | grep "^$2=" | cut -d= -f2-; }

igual "plain apk: format"         "apk"                   "$(campo "$ARTEFATOS/universal.apk" FORMATO)"
igual "plain apk: package"        "com.exemplo.universal" "$(campo "$ARTEFATOS/universal.apk" PACOTE)"
igual "plain apk: minimum sdk"    "21"                    "$(campo "$ARTEFATOS/universal.apk" MINSDK)"
igual "universal apk: no ABI"     ""                      "$(campo "$ARTEFATOS/universal.apk" ABIS)"

igual "x86 apk: ABIs"             "x86,x86_64"            "$(campo "$ARTEFATOS/x86.apk" ABIS)"
igual "ARM-only apk: ABIs"        "arm64-v8a,armeabi-v7a" "$(campo "$ARTEFATOS/armonly.apk" ABIS)"
igual "demanding apk: minimum sdk" "99"                   "$(campo "$ARTEFATOS/futuro.apk" MINSDK)"

igual "xapk: format"              "xapk"                  "$(campo "$ARTEFATOS/jogo.xapk" FORMATO)"
igual "xapk: package comes from the base apk" "com.exemplo.jogo" "$(campo "$ARTEFATOS/jogo.xapk" PACOTE)"
igual "xapk: sdk comes from the base apk" "24"                  "$(campo "$ARTEFATOS/jogo.xapk" MINSDK)"
igual "xapk: counts the parts"    "2"                     "$(campo "$ARTEFATOS/jogo.xapk" SPLITS)"
igual "xapk: detects OBB"         "1"                     "$(campo "$ARTEFATOS/jogo.xapk" OBB)"

igual "apks: format"              "apks"                  "$(campo "$ARTEFATOS/app.apks" FORMATO)"
igual "apks: counts the parts"    "3"                     "$(campo "$ARTEFATOS/app.apks" SPLITS)"
igual "apks: no OBB"              "0"                     "$(campo "$ARTEFATOS/app.apks" OBB)"

igual "a corrupt file degrades with a message" \
      "arquivo corrompido ou nao e um pacote Android" \
      "$(campo "$ARTEFATOS/corrompido.apk" ERRO)"
igual "an empty file degrades with a message" \
      "arquivo corrompido ou nao e um pacote Android" \
      "$(campo "$ARTEFATOS/vazio.apk" ERRO)"
igual "a missing file degrades with a message" \
      "arquivo nao encontrado" \
      "$(campo /nao/existe.apk ERRO)"

python3 src/lib/apkinfo.py >/dev/null 2>&1
igual "no argument returns a usage error" "2" "$?"

# ------------------------------------------------------------- package

secao "no command comes out mute"

# t_texto reads the CONTENT from standard input and uses the argument as the
# TITLE. Five new commands passed the text as an argument and read an empty
# stdin: they ran, exited 0 and printed NOT ONE LINE. No test caught it because
# they all exercised library functions, never the whole command.
# Found by running "tandem dados" on a real Ubuntu.
CASA_C="$TMPRAIZ/cli"; mkdir -p "$CASA_C/.local/share/tandem/wine/drive_c/windows"
: > "$CASA_C/.local/share/tandem/wine/system.reg"
: > "$CASA_C/.local/share/tandem/wine/.tandem-prefixo"
: > "$CASA_C/.primeira-vez"
for cmd in "dados" "lista" "doctor" "--help" "version"; do
    saida="$(env -i HOME="$CASA_C" PATH="/usr/bin:/bin" TANDEM_LIB="$RAIZ/src/lib" \
             bash "$RAIZ/src/bin/tandem" $cmd 2>&1)"
    if [ -n "$saida" ]; then passou "\"tandem $cmd\" prints something"
    else falhou "\"tandem $cmd\" prints something" "any text" "zero bytes"; fi
done

# And wrong usage has to degrade, never come out mute: with nothing on the
# input, t_texto prints at least the title.
igual "t_texto with no content prints the title" \
      "Titulo qualquer" "$(t_texto "Titulo qualquer" < /dev/null)"
# The guard against freezing can only be exercised where a terminal exists.
if [ -c /dev/tty ] && (exec < /dev/tty) 2>/dev/null; then
    timeout 5 bash -c '. "'"$RAIZ"'/src/lib/common.sh"; t_texto "T" < /dev/tty' >/dev/null 2>&1
    igual "t_texto with a terminal on the input does not hang" "0" "$?"
else
    pulou "t_texto with a terminal on the input" "the suite runs without a controlling terminal"
fi

secao "community list (modelled on filter lists)"

PROG_L="$ARTEFATOS/prog64.exe"
ID_L="$(t_memoria_id "$PROG_L")"
export TANDEM_LISTA="$TMPRAIZ/lista.tsv"

# With no list downloaded there is nothing to query - and that is not an error.
rm -f "$TANDEM_LISTA"
igual "with no list downloaded, the query stays quiet" "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022,dotnet48\t-\tconfirmado\t340\t2026-08\t-\n' "$ID_L"
  printf 'aaaa\t64\tvcrun2010\t-\tso-abriu\t2\t2026-07\t-\n'
} > "$TANDEM_LISTA"
igual "finds the program by the file's fingerprint" \
      "vcrun2022 dotnet48" "$(t_lista_consulta "$PROG_L")"
igual "the machine count comes along" "340" "$(t_lista_maquinas "$ID_L")"

# A lesson with nobody confirming it is NOT spread. Spreading a mistake is
# easier than spreading a correct answer: errors take no work to produce.
{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022\t-\tso-abriu\t9\t2026-08\t-\n' "$ID_L"
} > "$TANDEM_LISTA"
igual "an unconfirmed lesson is not suggested" "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

# The record that leaves this machine.
t_memoria_esquece "$PROG_L" 2>/dev/null
t_memoria_grava "$PROG_L" ARQUITETURA 64
t_memoria_junta "$PROG_L" RESOLVERAM vcrun2022
t_memoria_grava "$PROG_L" CONFIRMADO sim
REG_L="$(t_lista_registro "$PROG_L")"
igual "the record has the format's eight fields" \
      "8" "$(printf '%s' "$REG_L" | awk -F'\t' '{print NF}')"
case "$REG_L" in
    "$ID_L"*) passou "the record starts with the file identity" ;;
    *) falhou "the record starts with the file identity" "$ID_L..." "$REG_L" ;;
esac
case "$REG_L" in
    *confirmado*) passou "the record carries where the confidence came from" ;;
    *) falhou "the record carries where the confidence came from" "confirmado" "$REG_L" ;;
esac
# What must NEVER leave: path, user, machine, IP, day of the month.
case "$REG_L" in
    */*) falhou "the record carries no path at all" "no slash" "$REG_L" ;;
    *) passou "the record carries no path at all" ;;
esac
case "$REG_L" in
    *"$(id -un)"*) falhou "the record does not carry the user name" "no user" "$REG_L" ;;
    *) passou "the record does not carry the user name" ;;
esac
case "$REG_L" in
    *"$(date +%Y-%m-%d)"*) falhou "the date has no day" "year-month only" "$REG_L" ;;
    *) passou "the date has no day" ;;
esac
# And the guard works even if someone breaks the generator in the future.
igual "the guard blocks a record with a path" \
      "0" "$(t_lista_vaza "abc	64	/home/alguem/x	-	confirmado	1	2026-08	-"; echo $?)"
igual "the guard blocks a record with an IP" \
      "0" "$(t_lista_vaza "abc	64	vcrun2022	-	confirmado	1	2026-08	192.168.0.7"; echo $?)"
igual "the guard lets a clean record through" \
      "1" "$(t_lista_vaza "$REG_L"; echo $?)"

# The format document promises that every verb coming from outside is validated
# before becoming a command argument. The memory/list shortcut wrote a receipt
# and called winetricks without going through any validation at all - the recipe
# validated, the list did not.
igual "a verb with an unexpected character is refused" \
      "1" "$(t_verbo_valido 'vcrun2022; rm -rf /'; echo $?)"
igual "a verb with a slash is refused" "1" "$(t_verbo_valido '../../etc/passwd'; echo $?)"
igual "an ordinary verb passes" "0" "$(t_verbo_valido vcrun2022; echo $?)"
case "$(grep -c 't_verbo_valido' "$RAIZ/src/bin/tandem-exe")" in
    0) falhou "the list shortcut validates the verb before using it" "t_verbo_valido" "missing" ;;
    *) passou "the list shortcut validates the verb before using it" ;;
esac
# And proof of delivery applies to that shortcut too: it was the only path that
# wrote a receipt based on the exit code alone.
case "$(grep -c 't_dll_no_prefixo' "$RAIZ/src/bin/tandem-exe")" in
    0|1) falhou "proof of delivery also covers the memory shortcut" \
                "two uses of t_dll_no_prefixo" "fewer than that" ;;
    *) passou "proof of delivery also covers the memory shortcut" ;;
esac

# A program with no lesson at all must not become noise in other people's list.
t_memoria_esquece "$PROG_L" 2>/dev/null
t_lista_registro "$PROG_L" >/dev/null 2>&1
igual "with no lesson, there is nothing to contribute" "1" "$?"

# A file that does not declare itself a list must NOT replace the good one
# already on disk. A broken list would silence the second opinion without anyone
# noticing - and "stopped suggesting" is the kind of defect nobody spots.
printf '# TANDEM-LISTA 1\nboa\t64\tx\t-\tconfirmado\t1\t2026-08\t-\n' > "$TANDEM_LISTA"
printf 'nao sou uma lista do Tandem\n' > "$TMPRAIZ/intruso.txt"
if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    TANDEM_LISTA_URL="file://$TMPRAIZ/intruso.txt" t_lista_atualiza >/dev/null 2>&1
    igual "a file without a valid header is refused" "3" "$?"
    igual "  and the good list stays on disk" "1" "$(grep -c '^boa' "$TANDEM_LISTA")"
    igual "  without letting the intruder in" "0" "$(grep -c 'nao sou uma lista' "$TANDEM_LISTA")"
    # And the happy path: a well-formed file does replace it.
    printf '# TANDEM-LISTA 1\nnova\t64\ty\t-\tconfirmado\t5\t2026-08\t-\n' > "$TMPRAIZ/boa.tsv"
    TANDEM_LISTA_URL="file://$TMPRAIZ/boa.tsv" t_lista_atualiza >/dev/null 2>&1
    igual "a well-formed file replaces it" "1" "$(grep -c '^nova' "$TANDEM_LISTA")"
else
    pulou "list update" "no curl and no wget"
fi
unset TANDEM_LISTA

secao "silent success: exiting 0 is not the same as having worked"

igual "an instant exit is suspicious" "0" "$(t_saida_suspeita 1; echo $?)"
igual "a program that stayed open is not suspicious" "1" "$(t_saida_suspeita 40; echo $?)"

PROG_S="$ARTEFATOS/prog64.exe"
t_memoria_esquece "$PROG_S" 2>/dev/null
igual "with no answer from the owner, the lesson is worth less" \
      "so-abriu" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_grava "$PROG_S" CONFIRMADO sim
igual "with the owner confirming, the lesson is worth more" \
      "confirmado" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_grava "$PROG_S" CONFIRMADO nao
igual "with the owner rejecting, the lesson is marked as rejected" \
      "reprovado" "$(t_confianca_da_licao "$PROG_S")"

# The recipe has to carry where the confidence came from. Without this line,
# "the process exited 0" and "a person looked at the screen" arrived on the
# other side with exactly the same weight - and the second person had no way
# to tell.
case "$(t_receita_exporta "$PROG_S")" in
    *"CONFIANCA=reprovado"*) passou "the recipe comes out marked with the confidence" ;;
    *) falhou "the recipe comes out marked with the confidence" "CONFIANCA=reprovado" \
              "$(t_receita_exporta "$PROG_S" | head -8)" ;;
esac

# Without a window there is no way to ask - and making up an answer would be
# worse than having no answer at all.
t_memoria_esquece "$PROG_S" 2>/dev/null
( unset DISPLAY WAYLAND_DISPLAY; t_confirma_funcionou "$PROG_S" 30 ) >/dev/null 2>&1
igual "without a window, it does not invent a confirmation" \
      "so-abriu" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_esquece "$PROG_S" 2>/dev/null

secao "bitness: arriving is not arriving where this program looks"

# A win64 prefix the way Wine builds it: system32 holds the 64-bit DLLs and
# syswow64 the 32-bit ones. This test exists because the first run of the loop
# with a REAL winetricks ended like this: the mfc42 verb exited 0, delivered the
# file into syswow64, proof of delivery looked at both folders, approved, and
# the 64-bit program still found nothing.
PB="$TMPRAIZ/pref64"
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
) > "$TMPRAIZ/bit.txt"
igual "64-bit program, DLL only in syswow64: wrong bitness" \
      "2" "$(awk '$1=="a"{print $2}' "$TMPRAIZ/bit.txt")"
igual "32-bit program, the same DLL does the job" \
      "0" "$(awk '$1=="b"{print $2}' "$TMPRAIZ/bit.txt")"
igual "64-bit program, DLL in system32: does the job" \
      "0" "$(awk '$1=="c"{print $2}' "$TMPRAIZ/bit.txt")"
igual "32-bit program, DLL only in system32: wrong bitness" \
      "2" "$(awk '$1=="d"{print $2}' "$TMPRAIZ/bit.txt")"
igual "a DLL in both folders serves both" \
      "0" "$(awk '$1=="e"{print $2}' "$TMPRAIZ/bit.txt")"
igual "a missing DLL stays missing" \
      "1" "$(awk '$1=="f"{print $2}' "$TMPRAIZ/bit.txt")"
# Without knowing the architecture, condemning would be worse than not knowing.
igual "with no known architecture, it does not condemn" \
      "0" "$(awk '$1=="g"{print $2}' "$TMPRAIZ/bit.txt")"

# win32 prefix: only system32 exists, and it is 32-bit.
PB32="$TMPRAIZ/pref32"; mkdir -p "$PB32/drive_c/windows/system32"
: > "$PB32/drive_c/windows/system32/mfc42.dll"
igual "32-bit prefix: system32 serves a 32-bit program" \
      "0" "$(WINEPREFIX="$PB32"; export WINEPREFIX; t_dll_no_prefixo mfc42.dll 32; echo $?)"

TXB="$(t_texto_bitola "$(printf 'mfc42.dll\tmfc42')" 64)"
case "$TXB" in
    *"64 bits"*"32 bits"*mfc42.dll*) passou "the message names both bitnesses and the file" ;;
    *) falhou "the message names both bitnesses and the file" "64/32/mfc42.dll" "$TXB" ;;
esac
case "$TXB" in
    *"Não é defeito da sua máquina"*) passou "the message takes the blame off the owner's machine" ;;
    *) falhou "the message takes the blame off the owner's machine" "Não é defeito da sua máquina" "$TXB" ;;
esac

secao "choosing the verb by the program's bitness"

igual "a 32-bit program keeps the normal verb" \
      "xact" "$(t_verbo_para_arquitetura xact 32)"
igual "a verb with no 64-bit sibling is not swapped" \
      "vcrun2022" "$(t_verbo_para_arquitetura vcrun2022 64)"
igual "with no known architecture, nothing is swapped" \
      "xact" "$(t_verbo_para_arquitetura xact '')"
if t_winetricks_tem_verbo xact_x64; then
    igual "a 64-bit program gets the xact_x64 sibling" \
          "xact_x64" "$(t_verbo_para_arquitetura xact 64)"
else
    # Old winetricks without the sibling: better the normal verb than a verb
    # name this winetricks does not know.
    igual "without the sibling in this winetricks, keeps the normal verb" \
          "xact" "$(t_verbo_para_arquitetura xact 64)"
fi

igual "mfc42 is recognized as 32-bit-only" "0" "$(t_verbo_so_32 mfc42; echo $?)"
igual "vcrun2022 is not 32-bit-only"       "1" "$(t_verbo_so_32 vcrun2022; echo $?)"
# The classification comes from the INSTALLED winetricks, not from a list
# written here: a fixed list covered eight verbs, and the winetricks inventory
# found 42.
igual "a verb with an _x64 sibling does not count as 32-bit-only" "1" "$(t_verbo_so_32 xact; echo $?)"
igual "a verb winetricks does not know does not become 32-bit-only" \
      "1" "$(t_verbo_so_32 naoexisteesteverbo; echo $?)"
if t_winetricks_tem_verbo dsound; then
    igual "the classification reaches a verb outside the old list (dsound)" \
          "0" "$(t_verbo_so_32 dsound; echo $?)"
else
    pulou "dsound classification" "verb absent in this winetricks"
fi
# wmp9 has no real win64 branch; wmp11 does, and delivers a superset.
if t_winetricks_tem_verbo wmp11; then
    igual "64-bit wmvcore goes to wmp11, not to wmp9" \
          "wmp11" "$(t_verbo_para_arquitetura "$(t_dll_para_verbo wmvcore.dll)" 64)"
    igual "  and the 32-bit one stays on wmp9" \
          "wmp9" "$(t_verbo_para_arquitetura "$(t_dll_para_verbo wmvcore.dll)" 32)"
else
    pulou "wmvcore in 64 bits" "wmp11 absent in this winetricks"
fi

# BITNESS AUDITOR. The two lists above were compiled from winetricks 20240105,
# reading verb by verb. Winetricks is updated outside Tandem: without this test,
# the day the project starts installing a 64-bit payload for mfc42 nobody finds
# out, and Tandem keeps warning that there is no fix for something that now has
# one.
WT="$(command -v winetricks 2>/dev/null)"
if [ -n "$WT" ] && [ -r "$WT" ]; then
    divergiu=""
    for v in dbghelp mfc42 msxml3 msxml4 openal riched20 vcrun2003 wsh57; do
        if sed -n "/^load_${v}()/,/^}/p" "$WT" 2>/dev/null |
           grep -qE 'x64|win64|W_SYSTEM64|amd64'; then
            divergiu="$divergiu $v"
        fi
    done
    # E o contrario: verbo que a tabela usa, cobre 64, e esta marcado como so-32.
    for v in vcrun2022 vcrun2010 dotnet48 d3dx9 gdiplus xinput; do
        t_verbo_so_32 "$v" && divergiu="$divergiu !$v"
    done
    if [ -z "$divergiu" ]; then
        passou "a lista de verbos so-32 bate com o winetricks instalado"
    else
        falhou "a lista de verbos so-32 bate com o winetricks instalado" \
               "(nenhuma divergencia)" "$divergiu"
    fi
    # E o irmao x64 existe mesmo? Prometer um verbo inexistente faria o
    # winetricks falhar com um erro que o dono nao tem como entender.
    if t_winetricks_tem_verbo xact_x64; then
        passou "o irmao xact_x64 existe neste winetricks"
    else
        pulou "o irmao xact_x64" "winetricks sem esse verbo"
    fi
    igual "verbo inventado nao passa por existente" \
          "1" "$(t_winetricks_tem_verbo naoexisteesteverbo; echo $?)"
else
    pulou "auditor da bitola" "winetricks nao instalado"
fi

secao "dados: o que se refaz e o que nao se refaz"

# Um prefixo com as duas coisas misturadas, que e como todo prefixo real e.
PD="$TMPRAIZ/prefdados"
mkdir -p "$PD/drive_c/windows/system32" \
         "$PD/drive_c/users/zero/Documents" \
         "$PD/drive_c/users/zero/AppData/Roaming/SistemaLoja" \
         "$PD/drive_c/users/Public/Documents" \
         "$PD/drive_c/Program Files/SistemaLoja" \
         "$PD/drive_c/Program Files/SistemaLoja/Temp" \
         "$PD/drive_c/users/zero/Desktop"
: > "$PD/system.reg"; : > "$PD/.tandem-prefixo"
# Ambiente: refazivel, nao entra.
head -c 4096 /dev/zero > "$PD/drive_c/windows/system32/msvcp140.dll"
head -c 2048 /dev/zero > "$PD/drive_c/Program Files/SistemaLoja/loja.exe"
# Dados: insubstituiveis, entram.
head -c 9000 /dev/zero > "$PD/drive_c/Program Files/SistemaLoja/cadastro.mdb"
head -c 1500 /dev/zero > "$PD/drive_c/users/zero/Documents/vendas.xlsx"
head -c 700  /dev/zero > "$PD/drive_c/users/zero/AppData/Roaming/SistemaLoja/config.db"
# Lixo que nao merece viagem.
head -c 5000 /dev/zero > "$PD/drive_c/Program Files/SistemaLoja/Temp/rascunho.bak"
# Pasta vazia nao e dado, e enfeite do Wine.
LISTA_D="$(t_dados_lista "$PD")"

case "$LISTA_D" in
    *"Program Files/SistemaLoja/cadastro.mdb"*) passou "acha o banco largado ao lado do executavel" ;;
    *) falhou "acha o banco largado ao lado do executavel" "cadastro.mdb" "$LISTA_D" ;;
esac
case "$LISTA_D" in
    *"users/zero/Documents"*) passou "acha a pasta Documentos do usuario" ;;
    *) falhou "acha a pasta Documentos do usuario" "users/zero/Documents" "$LISTA_D" ;;
esac
case "$LISTA_D" in
    *msvcp140.dll*|*loja.exe*) falhou "nao carrega o ambiente junto" "sem dll nem exe" "$LISTA_D" ;;
    *) passou "nao carrega o ambiente junto" ;;
esac
case "$LISTA_D" in
    *rascunho.bak*) falhou "ignora o que esta em Temp" "sem rascunho.bak" "$LISTA_D" ;;
    *) passou "ignora o que esta em Temp" ;;
esac
case "$LISTA_D" in
    *users/Public*) falhou "ignora as pastas de sistema do Windows" "sem Public" "$LISTA_D" ;;
    *) passou "ignora as pastas de sistema do Windows" ;;
esac
case "$LISTA_D" in
    *Desktop*) falhou "pasta vazia nao vira item" "sem Desktop" "$LISTA_D" ;;
    *) passou "pasta vazia nao vira item" ;;
esac
igual "soma o tamanho de tudo que achou" \
      "0" "$([ "$(t_dados_total "$PD")" -gt 10000 ]; echo $?)"

# A copia tem que ser abrivel e conter os dados, so os dados.
ARQD="$TMPRAIZ/dados.tar.gz"
t_dados_salva "$PD" "$ARQD"
igual "a copia dos dados e gerada" "0" "$?"
CONTEUDO="$(tar -tzf "$ARQD" 2>/dev/null)"
case "$CONTEUDO" in
    *cadastro.mdb*) passou "a copia leva o banco" ;;
    *) falhou "a copia leva o banco" "cadastro.mdb" "$CONTEUDO" ;;
esac
case "$CONTEUDO" in
    *msvcp140.dll*) falhou "a copia nao leva o ambiente" "sem dll" "$CONTEUDO" ;;
    *) passou "a copia nao leva o ambiente" ;;
esac
# Devolver num prefixo vazio tem que recolocar no lugar certo.
PD2="$TMPRAIZ/prefvazio"; mkdir -p "$PD2/drive_c"
tar -C "$PD2/drive_c" -xzf "$ARQD" 2>/dev/null
igual "a copia volta no lugar certo" \
      "0" "$([ -f "$PD2/drive_c/Program Files/SistemaLoja/cadastro.mdb" ]; echo $?)"

# Prefixo sem nada do dono: nao ha o que salvar, e isso NAO e erro.
PD3="$TMPRAIZ/prefnovo"; mkdir -p "$PD3/drive_c/windows/system32"
igual "prefixo recem-criado nao tem dados" "0" "$(t_dados_total "$PD3")"
# Tres desfechos distintos, e a distincao e o ponto: "nao havia nada" e normal
# e silencioso, "havia dado e a copia falhou" tem que parar quem esta prestes a
# apagar. Juntar os dois num "return 1" fazia disco cheio parecer prefixo vazio,
# e a exclusao seguia de qualquer jeito.
t_dados_salva "$PD3" "$TMPRAIZ/vazio.tar.gz" 2>/dev/null
igual "prefixo sem dados devolve 2, nao 1" "2" "$?"
igual "  e nao deixa arquivo pela metade no disco" \
      "1" "$([ -f "$TMPRAIZ/vazio.tar.gz" ]; echo $?)"
t_dados_resgate "$PD3" teste >/dev/null 2>&1
igual "o resgate de prefixo vazio tambem devolve 2" "2" "$?"
# Copia que FALHA de verdade: destino num caminho que nao existe.
t_dados_salva "$PD" "/nao/existe/x.tar.gz" 2>/dev/null
igual "copia que falha devolve 1, e nao 2" "1" "$?"
# E a frase que o dono le nesse caso tem que dizer o risco com todas as letras.
case "$(t_texto_resgate_falhou)" in
    *"NÃO consegui fazer uma cópia"*"não há como recuperar"*)
        passou "a mensagem de resgate falhado diz o risco" ;;
    *) falhou "a mensagem de resgate falhado diz o risco" \
              "NÃO consegui... não há como recuperar" "$(t_texto_resgate_falhou)" ;;
esac
# E os tres caminhos destrutivos tem que tratar o codigo 1 antes de apagar.
for alvo in src/bin/tandem-exe src/bin/tandem; do
    if grep -q 't_texto_resgate_falhou' "$RAIZ/$alvo"; then
        passou "$alvo para quando a copia de resgate falha"
    else
        falhou "$alvo para quando a copia de resgate falha" \
               "t_texto_resgate_falhou" "ausente"
    fi
done

# Valor de varias linhas na memoria: o formato e CHAVE=VALOR por linha, e
# gravar cru deixava linhas orfas que a reescrita nao removia - uma copia nova
# a cada abertura, para sempre. Medido: quatro gravacoes, 22 linhas, tres
# blocos de lixo.
MEM_ML="$ARTEFATOS/prog32.exe"
t_memoria_esquece "$MEM_ML" 2>/dev/null
for _i in 1 2 3 4; do
    t_memoria_grava "$MEM_ML" LIMITE "linha um
linha dois

linha quatro"
done
t_memoria_grava "$MEM_ML" RESULTADO abriu
igual "valor de varias linhas nao acumula lixo" \
      "5" "$(wc -l < "$(t_memoria_arquivo "$MEM_ML")")"
igual "  e volta inteiro na leitura" \
      "linha um
linha dois

linha quatro" "$(t_memoria_le "$MEM_ML" LIMITE)"
igual "  sem estragar as outras chaves" "abriu" "$(t_memoria_le "$MEM_ML" RESULTADO)"
t_memoria_esquece "$MEM_ML" 2>/dev/null

igual "tamanho em portugues legivel" "9 KB" "$(t_tamanho_amigavel 9216)"
igual "tamanho pequeno fica em bytes" "800 bytes" "$(t_tamanho_amigavel 800)"

secao "prova de entrega: o winetricks sair 0 nao prova que a DLL chegou"

# Ate aqui a suite exercitava as bibliotecas. Este bloco roda o tandem-exe
# INTEIRO - o laco roda->detecta->instala->repete - com um wine e um
# winetricks de mentira. E o unico jeito de exercitar em CI o caminho que
# nunca disparou em campo, porque o unico programa ja instalado de verdade
# (7-Zip) nao depende de nada.

E2E="$TMPRAIZ/e2e"; mkdir -p "$E2E/bin"

# Um programa que sempre falha reclamando da mesma DLL.
cat > "$E2E/bin/wine" <<'FIM'
#!/bin/sh
# "wine reg add" tem que funcionar: e o desligamento do sequestro de
# associacoes de arquivo. Qualquer outra chamada finge o programa quebrado.
[ "$1" = reg ] && exit 0
printf '0009:err:module:import_dll Library MSVCR71.dll (needed by Z:\\x.exe) not found\n' >&2
exit 53
FIM
printf '#!/bin/sh\nexit 0\n' > "$E2E/bin/wineserver"
# O winetricks obediente: sai 0 sempre, e so entrega o arquivo se mandarem.
# E exatamente esta a armadilha - o codigo de saida nao e a entrega.
cat > "$E2E/bin/winetricks" <<'FIM'
#!/bin/sh
printf '%s\n' "$*" >> "$E2E_DIARIO"
if [ -n "$E2E_ENTREGA" ]; then
    mkdir -p "$WINEPREFIX/drive_c/windows/system32"
    : > "$WINEPREFIX/drive_c/windows/system32/$E2E_ENTREGA"
fi
exit 0
FIM
# Sem isto o laco chamaria o systemd-inhibit real, que nao roda em container.
cat > "$E2E/bin/systemd-inhibit" <<'FIM'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in --*) shift ;; *) break ;; esac; done
exec "$@"
FIM
# Responde "Instalar" e guarda o texto que o dono veria na tela.
cat > "$E2E/bin/zenity" <<'FIM'
#!/bin/sh
for a in "$@"; do
    case "$a" in --text=*) printf '%s\n<<<>>>\n' "${a#--text=}" >> "$E2E_JANELAS" ;; esac
done
exit 0
FIM
chmod +x "$E2E/bin"/*

# $1 = pasta da rodada (vira o HOME), $2 = arquivo que o winetricks entrega,
# $3 = "semgui" para rodar sem sessao grafica (caminho de terminal)
roda_exe() {
    local casa="$1" entrega="$2" modo="${3:-gui}" pref tela=:99
    pref="$casa/.local/share/tandem/wine"
    mkdir -p "$pref/drive_c/windows/system32"
    : > "$pref/system.reg"; : > "$pref/.tandem-prefixo"
    [ "$modo" = semgui ] && tela=""
    env -i HOME="$casa" DISPLAY="$tela" PATH="$E2E/bin:/usr/bin:/bin" \
        E2E_ENTREGA="$entrega" E2E_DIARIO="$casa/diario.txt" \
        E2E_JANELAS="$casa/janelas.txt" TANDEM_LIB="$RAIZ/src/lib" \
        bash "$RAIZ/src/bin/tandem-exe" "$ARTEFATOS/prog64.exe" \
        > "$casa/stdout.txt" 2> "$casa/stderr.txt"
}

if [ ! -x "$E2E/bin/wine" ]; then
    pulou "prova de entrega" "nao consegui montar o ambiente falso"
else
    # --- Caso 1: a instalacao entrega o arquivo. Recibo normal.
    A="$E2E/entregou"; mkdir -p "$A"; roda_exe "$A" msvcr71.dll
    igual "entregou: o recibo e gravado" \
          "vcrun2003" "$(sort -u "$A/.local/share/tandem/wine/.tandem-verbos" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    igual "entregou: nao ha traducao suspeita anotada" \
          "1" "$([ -f "$A/.local/state/tandem/traducao-suspeita.tsv" ]; echo $?)"
    igual "entregou: o winetricks foi chamado uma vez so" \
          "1" "$(grep -c vcrun2003 "$A/diario.txt" 2>/dev/null)"

    # --- Caso 2: o winetricks sai 0 e o arquivo nao chega.
    B="$E2E/enganou"; mkdir -p "$B"; roda_exe "$B" ""
    igual "nao entregou: o recibo NAO e gravado" \
          "1" "$([ -s "$B/.local/share/tandem/wine/.tandem-verbos" ]; echo $?)"
    igual "nao entregou: a suspeita fica anotada com a DLL e o verbo" \
          "msvcr71.dll	vcrun2003" \
          "$(cut -f1,2 "$B/.local/state/tandem/traducao-suspeita.tsv" 2>/dev/null | head -1)"
    # A mensagem tem que citar o arquivo que faltou e assumir a culpa. Dizer
    # "instalei as dependencias e ainda nao abre" mandaria o dono procurar
    # defeito na maquina dele, que esta perfeita.
    JAN="$(cat "$B/janelas.txt" 2>/dev/null)"
    case "$JAN" in
        *msvcr71.dll*continua\ faltando*) passou "nao entregou: a mensagem cita o arquivo que faltou" ;;
        *) falhou "nao entregou: a mensagem cita o arquivo que faltou" \
                  "...msvcr71.dll continua faltando..." "${JAN:-(nenhuma janela)}" ;;
    esac
    case "$JAN" in
        *"erro meu, não da sua máquina"*) passou "nao entregou: a culpa e assumida pelo Tandem" ;;
        *) falhou "nao entregou: a culpa e assumida pelo Tandem" \
                  "erro meu, não da sua máquina" "${JAN:-(nenhuma janela)}" ;;
    esac
    case "$JAN" in
        *"Já instalei o que este programa pedia"*)
            falhou "nao entregou: nao cai no beco sem saida do recibo" \
                   "outra mensagem" "Já instalei o que este programa pedia" ;;
        *) passou "nao entregou: nao cai no beco sem saida do recibo" ;;
    esac
    # A licao errada nao pode virar memoria: ela viajaria com a receita para
    # a outra maquina e ensinaria o engano de novo.
    igual "nao entregou: nada de NAO_RESOLVERAM na memoria" \
          "" "$(grep -h '^NAO_RESOLVERAM=' "$B/.local/state/tandem/memoria/"*.txt 2>/dev/null)"
    # Dentro da mesma execucao o verbo suspeito nao e reinstalado: seriam
    # meia hora jogadas fora, no caso do .NET.
    igual "nao entregou: nao repete a instalacao na mesma execucao" \
          "1" "$(grep -c vcrun2003 "$B/diario.txt" 2>/dev/null)"

    # --- Caso 3: segunda execucao. Sem recibo, tem que oferecer de novo.
    roda_exe "$B" ""
    igual "segunda execucao: oferece instalar outra vez" \
          "2" "$(grep -c vcrun2003 "$B/diario.txt" 2>/dev/null)"
    igual "segunda execucao: a suspeita e anotada de novo, com data" \
          "2" "$(grep -c vcrun2003 "$B/.local/state/tandem/traducao-suspeita.tsv" 2>/dev/null)"

    # --- Caso 4: sem sessao grafica, a mensagem tem que sair pelo terminal.
    #
    # Este teste existe por causa de um defeito medido num Ubuntu 24.04 real:
    # o laco detectava a DLL, traduzia certo, montava a mensagem certa com o
    # comando certo - e devolvia codigo 53 com ZERO BYTE de saida. A causa era
    # "exec 7> arq 2>/dev/null": exec sem comando aplica as redirecoes ao
    # shell inteiro, e de forma permanente, entao aquele 2>/dev/null desviava
    # o stderr de todo o resto do programa. Nenhum teste pegava porque todos
    # rodavam com DISPLAY definido, onde a mensagem sai pela janela.
    C="$E2E/semjanela"; mkdir -p "$C"; roda_exe "$C" "" semgui
    if [ -s "$C/stderr.txt" ]; then passou "sem janela: a mensagem sai pelo terminal"
    else falhou "sem janela: a mensagem sai pelo terminal" \
                "qualquer texto no stderr" "zero byte (erro em silencio)"; fi
    case "$(cat "$C/stderr.txt" 2>/dev/null)" in
        *"winetricks -q vcrun2003"*) passou "sem janela: diz o comando exato para resolver" ;;
        *) falhou "sem janela: diz o comando exato para resolver" \
                  "winetricks -q vcrun2003" "$(head -c 200 "$C/stderr.txt" 2>/dev/null)" ;;
    esac
fi

secao "pacote .deb"

DEB_SAIDA="$TMPRAIZ/build"
mkdir -p "$DEB_SAIDA"
if python3 build.py --check > "$TMPRAIZ/build.log" 2>&1; then
    passou "build.py --check"
else
    falhou "build.py --check" "sucesso" "$(tail -3 "$TMPRAIZ/build.log")"
fi

VERSAO_DEB="$(grep '^Version:' debian/control | cut -d' ' -f2)"
PACOTE_DEB="$RAIZ/tandem_${VERSAO_DEB}_all.deb"

igual "versao do control bate com a do executavel" \
      "$VERSAO_DEB" "$(grep '^VERSAO=' src/bin/tandem | cut -d'"' -f2)"

if [ -f "$PACOTE_DEB" ]; then
    passou "o .deb foi gerado"
    if command -v dpkg-deb >/dev/null 2>&1; then
        if dpkg-deb --info "$PACOTE_DEB" >/dev/null 2>&1 &&
           dpkg-deb --contents "$PACOTE_DEB" >/dev/null 2>&1; then
            passou "dpkg-deb aceita o arquivo escrito a mao"
        else
            falhou "dpkg-deb aceita o arquivo escrito a mao" "aceito" "recusado"
        fi
        conteudo="$(dpkg-deb --contents "$PACOTE_DEB" 2>/dev/null)"
        for exigido in usr/bin/tandem usr/lib/tandem/common.sh \
                       usr/share/doc/tandem/copyright \
                       usr/share/doc/tandem/changelog.gz \
                       usr/share/man/man1/tandem.1.gz \
                       usr/share/polkit-1/rules.d/49-tandem.rules \
                       usr/share/mime/packages/tandem.xml; do
            if printf '%s' "$conteudo" | grep -q " ./$exigido\$"; then
                passou "o pacote traz $exigido"
            else
                falhou "o pacote traz $exigido" "presente" "ausente"
            fi
        done
        if printf '%s' "$conteudo" | grep -qv 'root/root'; then
            : # ha linhas sem root/root? checado abaixo de forma explicita
        fi
        naoroot="$(printf '%s' "$conteudo" | grep -cv 'root/root')"
        igual "todo arquivo pertence a root" "0" "$naoroot"
    else
        pulou "validacao com dpkg-deb" "dpkg-deb nao instalado"
    fi

    # Duas construcoes seguidas tem que dar exatamente o mesmo arquivo.
    soma1="$(cksum < "$PACOTE_DEB")"
    python3 build.py >/dev/null 2>&1
    soma2="$(cksum < "$PACOTE_DEB")"
    igual "a construcao e reproduzivel" "$soma1" "$soma2"
else
    falhou "o .deb foi gerado" "$PACOTE_DEB" "ausente"
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
    for d in src/applications/*.desktop; do
        if desktop-file-validate "$d" 2>&1 | grep -q .; then
            falhou "desktop-file-validate $(basename "$d")" "sem avisos" \
                   "$(desktop-file-validate "$d" 2>&1 | head -1)"
        else
            passou "desktop-file-validate $(basename "$d")"
        fi
    done
else
    pulou "desktop-file-validate" "nao instalado"
fi

# ------------------------------------------------------------- resumo

printf '\n────────────────────────────────────────\n'
printf '%d passaram, %d falharam, %d pulados\n' "$OK" "$FALHOU" "$PULOU"
if [ "$FALHOU" -gt 0 ]; then
    printf '\nfalhas:\n'
    for f in "${FALHAS[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
