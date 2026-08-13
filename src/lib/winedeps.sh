# shellcheck shell=bash
# Tandem - translation of missing DLL -> winetricks verb.
#
# How it works: when a Windows program cannot find a library, Wine writes to
# the error output:
#     err:module:import_dll Library MSVCP140.dll not found
# We read those lines, translate each DLL into the package that provides it,
# and install it with winetricks. It is what an experienced person would do
# by hand.

# DLLs that Wine itself already implements: asking winetricks does not help,
# and the error almost always points to another cause (architecture, broken
# prefix).
t_dll_nativa() {
    case "${1,,}" in
        kernel32.dll|user32.dll|gdi32.dll|advapi32.dll|shell32.dll|ole32.dll|\
        oleaut32.dll|comctl32.dll|comdlg32.dll|ws2_32.dll|wininet.dll|\
        winhttp.dll|crypt32.dll|wintrust.dll|shlwapi.dll|version.dll|\
        setupapi.dll|rpcrt4.dll|ntdll.dll|msvcrt.dll|imm32.dll|winspool.drv)
            return 0 ;;
    esac
    return 1
}

# ---------------------------------------------- generated index (2nd opinion)
#
# The hand-written table below covers ~60 DLLs. winetricks itself knows
# hundreds: inside each load_<verb>() it declares, with
# "w_override_dlls native,builtin ...", exactly which files that verb
# delivers. tools/indice-winetricks.py inverts that reading and writes
# verbos.tsv.
#
# The hand-written table takes PRECEDENCE, on purpose: it carries decisions
# the index has no way of knowing. The index only steps in when the table
# does not know how to answer - and it was by comparing the two that the
# atl*.dll error showed up.
if [ -z "${TANDEM_VERBOS_TSV:-}" ]; then
    for _c in "${TANDEM_LIB:-/usr/lib/tandem}/verbos.tsv" \
              "$(dirname -- "${BASH_SOURCE[0]:-/nao}")/verbos.tsv"; do
        [ -f "$_c" ] && { TANDEM_VERBOS_TSV="$_c"; break; }
    done
    unset _c
fi

# Only answers when the index has high confidence. When several verbs from
# DIFFERENT families deliver the same DLL, picking one is a guess - and a
# guess that costs the owner half an hour. In that case the honest answer is
# not to know.
t_dll_no_indice() {
    [ -n "${TANDEM_VERBOS_TSV:-}" ] && [ -f "$TANDEM_VERBOS_TSV" ] || return 1
    awk -F'\t' -v alvo="${1,,}" \
        '$1 == alvo && $3 == "alta" { print $2; achou = 1; exit } END { exit !achou }' \
        "$TANDEM_VERBOS_TSV"
}

# Translates a DLL into a winetricks verb. Empty = no known translation.
t_dll_para_verbo() {
    local v
    v="$(t_dll_para_verbo_tabela "$1")"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    t_dll_no_indice "$1" 2>/dev/null
    return 0
}

t_dll_para_verbo_tabela() {
    local d="${1,,}"
    case "$d" in
        # Visual C++ runtimes
        msvcp140*.dll|vcruntime140*.dll|concrt140.dll|mfc140*.dll|vcomp140.dll)
            echo vcrun2022 ;;
        msvcp120.dll|msvcr120.dll|mfc120*.dll|vcomp120.dll)  echo vcrun2013 ;;
        msvcp110.dll|msvcr110.dll|mfc110*.dll|vcomp110.dll)  echo vcrun2012 ;;
        msvcp100.dll|msvcr100.dll|mfc100*.dll|vcomp100.dll)  echo vcrun2010 ;;
        msvcp90.dll|msvcr90.dll|mfc90*.dll)                  echo vcrun2008 ;;
        msvcp80.dll|msvcr80.dll|mfc80*.dll)                  echo vcrun2005 ;;
        # vcrun6 delivers "mfc42, msvcp60, msvcirt" - not the 71 ones. What
        # delivers msvcp71/msvcr71/mfc71 is vcrun2003, which says so in its
        # own title. Second error found by the winetricks auditor.
        msvcp71.dll|msvcr71.dll|mfc71*.dll)                  echo vcrun2003 ;;
        mfc42*.dll)                                          echo mfc42 ;;

        # .NET
        mscoree.dll|mscorlib.dll|wminet_utils.dll)           echo dotnet48 ;;

        # DirectX
        d3dx9*.dll)          echo d3dx9 ;;
        d3dx10*.dll)         echo d3dx10 ;;
        d3dx11*.dll)         echo d3dx11_43 ;;
        d3dcompiler_43.dll)  echo d3dcompiler_43 ;;
        d3dcompiler_46.dll)  echo d3dcompiler_46 ;;
        d3dcompiler_4*.dll)  echo d3dcompiler_47 ;;
        # xact delivers xaudio2, x3daudio, xapofx and xactengine - not
        # xinput, which has a verb of its own. Third error from the auditor.
        xinput1_*.dll|xinput9*.dll) echo xinput ;;
        x3daudio*.dll|xaudio2*.dll|xactengine*.dll|xapofx*.dll) echo xact ;;
        dxgi.dll|d3d11.dll|d3d10*.dll)                       echo d3dx11_43 ;;

        # Common miscellany
        gdiplus.dll)         echo gdiplus ;;
        riched20.dll|riched32.dll) echo riched20 ;;
        msxml3.dll)          echo msxml3 ;;
        msxml4.dll)          echo msxml4 ;;
        msxml6.dll)          echo msxml6 ;;
        openal32.dll)        echo openal ;;
        physxloader.dll)     echo physx ;;
        quartz.dll)          echo quartz ;;
        # quartz delivers only quartz.dll; amstream has a verb of its own.
        amstream.dll)        echo amstream ;;
        wmvcore.dll)         echo wmp9 ;;
        # wmp9 delivers l3codeca, wmp, wmplayer and wmvcore - wmasf only
        # comes with wmp11. Fourth error from the auditor.
        wmasf.dll)           echo wmp11 ;;
        jscript.dll|vbscript.dll) echo wsh57 ;;
        # ATL ships together with the Visual C++ runtime of the same year.
        # This used to point at "atmlib", which is the Adobe Type Manager - a
        # FONT library, with no relation whatsoever. The damage was twofold:
        # the owner waited on an installation that fixed nothing, and the
        # receipt was written all the same, so on the next attempt Tandem
        # said "I already installed what this program asked for" and gave up.
        # Found by comparing the table against the index generated from
        # winetricks itself (tools/indice-winetricks.py).
        atl140*.dll)         echo vcrun2019 ;;
        atl120*.dll)         echo vcrun2013 ;;
        atl110*.dll)         echo vcrun2012 ;;
        atl100*.dll)         echo vcrun2010 ;;
        atl90*.dll)          echo vcrun2008 ;;
        atl80*.dll)          echo vcrun2005 ;;
        dbghelp.dll)         echo dbghelp ;;
        secur32.dll)         echo secur32 ;;
        usp10.dll)           echo usp10 ;;
        *)                   echo "" ;;
    esac
}

# Reads a Wine log and prints the needed verbs, one per line, without
# repeating.
# Usage: t_verbos_do_log /path/to/log
t_verbos_do_log() {
    local log="$1" dll verbo
    [ -f "$log" ] || return 0
    grep -o 'import_dll Library [^ ]*' "$log" 2>/dev/null |
        awk '{print $3}' | sed 's/[.,;]$//' | sort -u |
    while read -r dll; do
        [ -n "$dll" ] || continue
        t_dll_nativa "$dll" && continue
        verbo="$(t_dll_para_verbo "$dll")"
        [ -n "$verbo" ] && printf '%s\n' "$verbo"
    done | sort -u
}

# The same pairs the function above computes and throws away: dll<TAB>verb.
#
# This is the key that was missing. The receipt in .tandem-verbos stores the
# VERB NAME and the condition for writing it is winetricks having exited 0 -
# that is, a cache whose key is the question and whose value is "I already
# answered", with no record at all of whether the answer worked. Every cache
# like that stores answers, not correct answers: a wrong translation goes in
# just like a right one, and rule number 4 then forbids the correction. With
# the pair in hand we can ask afterwards: did the missing DLL show up?
t_pares_do_log() {
    local log="$1" dll verbo
    [ -f "$log" ] || return 0
    grep -o 'import_dll Library [^ ]*' "$log" 2>/dev/null |
        awk '{print $3}' | sed 's/[.,;]$//' | sort -u |
    while read -r dll; do
        [ -n "$dll" ] || continue
        t_dll_nativa "$dll" && continue
        verbo="$(t_dll_para_verbo "$dll")"
        [ -n "$verbo" ] && printf '%s\t%s\n' "${dll,,}" "$verbo"
    done | sort -u
}

# ---------------------------------------------------- suspicious translation
#
# When winetricks exits 0 and the requested DLL is still missing, the one who
# got it wrong was me: the table told it to install the wrong package. This
# case must not become a receipt (the receipt would make Tandem say "I
# already installed what this program asked for" and give up forever) nor
# become a lesson in the memory (the wrong lesson would travel along with the
# recipe to the other machine). It becomes a note, here.
# $3 = "uma_vez" to skip a pair already on the list.
#
# The default stays APPEND, and that is deliberate rather than inherited: from
# the install path a repeat means "this verb was installed again, on another
# day, and again failed to deliver", which is a count worth having and is why
# the date column exists.
#
# The caller added in 4.8 is different in kind. The repeated-receipt branch
# fires every time the owner double-clicks a program whose receipt the loader
# contradicts - so a shop that opens the same broken program every morning
# would append the same pair every morning, for ever. A work list nobody can
# skim is a work list nobody reads. Only that caller asks for the dedup, so the
# meaning of the existing lines does not change.
t_anota_suspeita() {
    local dll="$1" verbo="$2" modo="${3:-}" arq
    [ -n "$dll" ] && [ -n "$verbo" ] || return 0
    [ -n "${TANDEM_ESTADO:-}" ] || return 0
    arq="$TANDEM_ESTADO/traducao-suspeita.tsv"
    if [ "$modo" = uma_vez ] && [ -f "$arq" ] &&
       grep -q "^$dll	$verbo	" "$arq" 2>/dev/null; then
        return 0
    fi
    printf '%s\t%s\t%s\n' "$dll" "$verbo" "$(date +%F)" \
        >> "$arq" 2>/dev/null || return 0
}

# The function Wine has not implemented, when the program CALLED it and Wine
# gave up. Empty = that did not happen.
#
# The third verdict class, and until 4.8 the loop had no branch for it: the
# dependency exists, Wine has not finished implementing part of it, and there
# is nothing to install. "The program closed with error (code 53)" was the
# answer, which sends the owner looking for a defect in a machine that is fine.
# Confirmed by grepping the format strings out of the INSTALLED Wine rather
# than from memory (wine-9.0, x86_64-windows/ntdll.dll).
#
# THE TWO SHAPES ARE NOT THE SAME THING, and only one of them is a verdict:
#
#   err:module:...  No implementation for %s.%s imported from %s, setting to %p
#       Wine stubs the export at LOAD time and carries on. Programs import
#       functions they never call all the time, so this line appears in the log
#       of software that works perfectly. Reporting it would alarm somebody
#       whose program is fine - the exact failure this project's "no jargon,
#       no false alarm" rule exists to prevent.
#
#   wine: Call from %p to unimplemented function %s.%s, aborting
#       The program actually called it and Wine ABORTED. That is the verdict.
#
# So only the second is matched, and the function name is carried out so the
# owner has something to search for and to send to whoever wrote the program.
t_falta_no_wine() {
    local log="$1"
    [ -f "$log" ] || return 1
    grep -oaE 'Call from [^ ]+ to unimplemented function [^,]+' "$log" 2>/dev/null |
        sed 's/.*unimplemented function //' | sort -u | head -3 |
        tr '\n' ' ' | sed 's/ $//' | grep . || return 1
}

# Turns this run's suspicions into the sentence the owner reads. The message
# takes the blame instead of sending him hunting for a defect in the machine
# - which is what "I installed the dependencies and it still does not open"
# used to do.
t_texto_suspeitas() {
    local linhas="$1" dll verbo texto=""
    while IFS="$(printf '\t')" read -r dll verbo; do
        [ -n "$dll" ] && [ -n "$verbo" ] || continue
        texto="$texto
$(t_msg suspeitas_linha "$(t_verbo_amigavel "$verbo")" "$dll")"
    done <<EOF
$linhas
EOF
    t_msg suspeitas "$texto"
}

# The inverse path: given a verb, which DLL should it have delivered?
#
# Serves the shortcut taken by the "memoria" and "lista" commands, where
# Tandem installs without having seen any Wine error - so there is no dll/verb
# pair coming from the log to check against. Without an answer here, that path
# used to write a receipt based only on the exit code, bypassing the delivery
# proof entirely. Answering "I do not know" is legitimate: absence of proof
# does not convict.
t_dll_do_verbo() {
    local v="$1"
    [ -n "$v" ] || return 1
    [ -n "${TANDEM_VERBOS_TSV:-}" ] && [ -f "$TANDEM_VERBOS_TSV" ] || return 1
    awk -F'\t' -v alvo="$v" \
        '$2 == alvo && $3 == "alta" { print $1; achou = 1; exit } END { exit !achou }' \
        "$TANDEM_VERBOS_TSV"
}

# --------------------------------------------------------- verb x bit width
#
# Continuation of the bit-width finding. Surveyed from the installed
# winetricks 20240105, verb by verb (there is a test that redoes this survey
# and fails if these two lists grow stale):
#
#   - most modern verbs ALREADY install both payloads on their own.
#     vcrun2022, for example, runs vc_redist.x86 and, if the prefix is win64,
#     also vc_redist.x64. For those there is nothing to choose.
#   - exactly ONE verb has an explicit 64-bit sibling: xact -> xact_x64.
#   - eight verbs only have a 32-bit payload and have no sibling at all. For
#     a 64-bit program that needs them there is no fix - and saying so
#     BEFORE is worth more than finding out after half an hour of download.

# The 64-bit sibling of this verb, if it exists in THIS winetricks. Check in
# the installed file, and do not trust the hand-written list, because
# winetricks is updated outside of Tandem.
t_winetricks_tem_verbo() {
    local wt
    wt="$(command -v winetricks 2>/dev/null)" || return 1
    [ -n "$wt" ] && [ -r "$wt" ] || return 1
    grep -q "^load_${1}()" "$wt" 2>/dev/null
}

t_verbo_para_arquitetura() {
    local verbo="$1" arch="${2:-}"
    if [ "$arch" = 64 ]; then
        case "$verbo" in
            xact) t_winetricks_tem_verbo xact_x64 && { printf 'xact_x64'; return 0; } ;;
            # wmp9 has no real win64 branch: its payload is the WMP9 MPSetup
            # for 32-bit XP, which lands in syswow64. wmp11 does have one
            # (wmp11-windowsxp-x64, wmfdist11-64) and touches W_SYSTEM64_DLLS,
            # and its overrides are a strict superset of wmp9's. So for a
            # 64-bit program asking for wmvcore.dll, wmp9 delivers nothing
            # usable and wmp11 does.
            wmp9) t_winetricks_tem_verbo wmp11 && { printf 'wmp11'; return 0; } ;;
        esac
    fi
    printf '%s' "$verbo"
}

# Verbs with no 64-bit payload and no sibling that has one. They block
# nothing: Tandem warns and lets the owner decide, the same way it does with
# limites.tsv.
#
# Classified from the INSTALLED winetricks, not from a list written here. A
# fixed list named eight verbs; an inventory of the installed winetricks found
# 42 that are 32-bit-only, 38 of them reachable from a real Wine log. A list
# that only covers what somebody remembered to add covers nothing, and
# winetricks is updated from outside this project. The eight stay as the
# fallback for when winetricks cannot be read at all.
t_verbo_so_32() {
    local v="$1" wt corpo
    [ -n "$v" ] || return 1
    wt="$(command -v winetricks 2>/dev/null)"
    if [ -n "$wt" ] && [ -r "$wt" ]; then
        # A sibling that handles 64 bits means this is not a dead end.
        t_winetricks_tem_verbo "${v}_x64" && return 1
        corpo="$(sed -n "/^load_${v}()/,/^}/p" "$wt" 2>/dev/null)"
        [ -n "$corpo" ] || return 1
        printf '%s' "$corpo" | grep -qE 'x64|win64|W_SYSTEM64|amd64' && return 1
        return 0
    fi
    case "$v" in
        dbghelp|mfc42|msxml3|msxml4|openal|riched20|vcrun2003|wsh57) return 0 ;;
    esac
    return 1
}

# The component arrived, in the bit width this program cannot use.
#
# It is not a translation error nor a defect of the machine: it is a limit of
# whoever distributes the component. Half of the winetricks verbs only have a
# 32-bit payload - winetricks itself warns about that in English in the
# middle of the log, where nobody reads it.
t_texto_bitola() {
    local linhas="$1" arch="${2:-64}" outra dll verbo texto=""
    [ "$arch" = 32 ] && outra=64 || outra=32
    while IFS="$(printf '\t')" read -r dll verbo; do
        [ -n "$dll" ] && [ -n "$verbo" ] || continue
        texto="$texto
$(t_msg bitola_linha "$(t_verbo_amigavel "$verbo")" "$dll" "$outra")"
    done <<EOF
$linhas
EOF
    t_msg bitola "$arch" "$outra" "$texto"
}

# Reads a log and prints the DLLs that were missing and have NO known
# translation (they are usually libraries the program itself should have
# shipped along).
t_dlls_sem_traducao() {
    local log="$1" dll
    [ -f "$log" ] || return 0
    grep -o 'import_dll Library [^ ]*' "$log" 2>/dev/null |
        awk '{print $3}' | sed 's/[.,;]$//' | sort -u |
    while read -r dll; do
        [ -n "$dll" ] || continue
        t_dll_nativa "$dll" && continue
        [ -z "$(t_dll_para_verbo "$dll")" ] && printf '%s\n' "$dll"
    done | sort -u
}

# Friendly name of a verb, to show to the user.
#
# Half of these are product names that must stay verbatim in every language -
# somebody searching for "Visual C++ 2015-2022" has to find the same words the
# rest of the world uses. The other half were SENTENCES, written here as plain
# literals: "Editor de texto rico", "Depurador do Windows", "Desenho de texto
# (Uniscribe)". They were shown, in Portuguese, to every user of every language,
# on the most important screen this program has - the list of what it is about
# to install - and tools/conta-literais.py reported TOTAL 0 the whole time,
# because this function's NAME matches none of the prose-body patterns and it
# lives in a library rather than in a handler. That is miss number sixteen, and
# it is the same shape as the thirteenth: a rule about names cannot see a body
# that produces prose under a name nobody thought of.
t_verbo_amigavel() {
    case "$1" in
        vcrun2022) echo "Visual C++ 2015-2022" ;;
        vcrun2013) echo "Visual C++ 2013" ;;
        vcrun2012) echo "Visual C++ 2012" ;;
        vcrun2010) echo "Visual C++ 2010" ;;
        vcrun2008) echo "Visual C++ 2008" ;;
        vcrun2005) echo "Visual C++ 2005" ;;
        vcrun2019) echo "Visual C++ 2015-2019" ;;
        vcrun2003) echo "Visual C++ 2003" ;;
        vcrun6)    echo "Visual C++ 6" ;;
        mfc42)     echo "MFC 4.2" ;;
        dotnet48)  echo "$(t_msg verbo_dotnet48)" ;;
        d3dx9|d3dx10|d3dx11_43) echo "DirectX ($1)" ;;
        d3dcompiler_43|d3dcompiler_47) echo "$(t_msg verbo_d3dcompiler)" ;;
        d3dcompiler_46) echo "$(t_msg verbo_d3dcompiler)" ;;
        xact)      echo "$(t_msg verbo_xact)" ;;
        xinput)    echo "$(t_msg verbo_xinput)" ;;
        gdiplus)   echo "GDI+" ;;
        riched20)  echo "$(t_msg verbo_riched20)" ;;
        msxml3|msxml4|msxml6) echo "MSXML" ;;
        openal)    echo "$(t_msg verbo_openal)" ;;
        physx)     echo "PhysX" ;;
        quartz|amstream) echo "$(t_msg verbo_quartz)" ;;
        wmp9|wmp11) echo "Windows Media Player" ;;
        wsh57)     echo "Windows Script Host" ;;
        dbghelp)   echo "$(t_msg verbo_dbghelp)" ;;
        secur32)   echo "$(t_msg verbo_secur32)" ;;
        usp10)     echo "$(t_msg verbo_usp10)" ;;
        *)         echo "$1" ;;
    esac
}
