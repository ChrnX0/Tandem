# shellcheck shell=bash
# Tandem - traducao de DLL faltando -> verbo do winetricks.
#
# Como funciona: quando um programa Windows nao acha uma biblioteca, o Wine
# escreve na saida de erro:
#     err:module:import_dll Library MSVCP140.dll not found
# Lemos essas linhas, traduzimos cada DLL para o pacote que a fornece, e
# instalamos com o winetricks. E o que uma pessoa experiente faria a mao.

# DLLs que o proprio Wine ja implementa: pedir ao winetricks nao ajuda,
# e o erro quase sempre indica outra causa (arquitetura, prefixo quebrado).
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

# ------------------------------------------------- indice gerado (2a opiniao)
#
# A tabela escrita a mao abaixo cobre ~60 DLLs. O proprio winetricks conhece
# centenas: dentro de cada load_<verbo>() ele declara, com
# "w_override_dlls native,builtin ...", exatamente quais arquivos aquele verbo
# entrega. tools/indice-winetricks.py inverte essa leitura e grava verbos.tsv.
#
# A tabela a mao tem PRECEDENCIA, de proposito: ela carrega decisoes que o
# indice nao tem como saber. O indice entra so quando a tabela nao sabe
# responder - e foi comparando os dois que apareceu o erro das atl*.dll.
if [ -z "${TANDEM_VERBOS_TSV:-}" ]; then
    for _c in "${TANDEM_LIB:-/usr/lib/tandem}/verbos.tsv" \
              "$(dirname -- "${BASH_SOURCE[0]:-/nao}")/verbos.tsv"; do
        [ -f "$_c" ] && { TANDEM_VERBOS_TSV="$_c"; break; }
    done
    unset _c
fi

t_dll_no_indice() {
    [ -n "${TANDEM_VERBOS_TSV:-}" ] && [ -f "$TANDEM_VERBOS_TSV" ] || return 1
    awk -F'\t' -v alvo="${1,,}" \
        '$1 == alvo { print $2; achou = 1; exit } END { exit !achou }' \
        "$TANDEM_VERBOS_TSV"
}

# Traduz uma DLL para um verbo do winetricks. Vazio = sem traducao conhecida.
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
        # Runtimes Visual C++
        msvcp140*.dll|vcruntime140*.dll|concrt140.dll|mfc140*.dll|vcomp140.dll)
            echo vcrun2022 ;;
        msvcp120.dll|msvcr120.dll|mfc120*.dll|vcomp120.dll)  echo vcrun2013 ;;
        msvcp110.dll|msvcr110.dll|mfc110*.dll|vcomp110.dll)  echo vcrun2012 ;;
        msvcp100.dll|msvcr100.dll|mfc100*.dll|vcomp100.dll)  echo vcrun2010 ;;
        msvcp90.dll|msvcr90.dll|mfc90*.dll)                  echo vcrun2008 ;;
        msvcp80.dll|msvcr80.dll|mfc80*.dll)                  echo vcrun2005 ;;
        msvcp71.dll|msvcr71.dll)                             echo vcrun6 ;;
        mfc42*.dll)                                          echo mfc42 ;;

        # .NET
        mscoree.dll|mscorlib.dll|wminet_utils.dll)           echo dotnet48 ;;

        # DirectX
        d3dx9*.dll)          echo d3dx9 ;;
        d3dx10*.dll)         echo d3dx10 ;;
        d3dx11*.dll)         echo d3dx11_43 ;;
        d3dcompiler_43.dll)  echo d3dcompiler_43 ;;
        d3dcompiler_4*.dll)  echo d3dcompiler_47 ;;
        xinput1_*.dll|x3daudio*.dll|xaudio2*.dll|xactengine*.dll) echo xact ;;
        dxgi.dll|d3d11.dll|d3d10*.dll)                       echo d3dx11_43 ;;

        # Diversos comuns
        gdiplus.dll)         echo gdiplus ;;
        riched20.dll|riched32.dll) echo riched20 ;;
        msxml3.dll)          echo msxml3 ;;
        msxml4.dll)          echo msxml4 ;;
        msxml6.dll)          echo msxml6 ;;
        openal32.dll)        echo openal ;;
        physxloader.dll)     echo physx ;;
        quartz.dll|amstream.dll) echo quartz ;;
        wmvcore.dll|wmasf.dll)   echo wmp9 ;;
        jscript.dll|vbscript.dll) echo wsh57 ;;
        # A ATL vem junto com o runtime do Visual C++ do mesmo ano. Isto
        # apontava para "atmlib", que e o Adobe Type Manager - uma biblioteca
        # de FONTES, sem relacao nenhuma. O estrago era duplo: o dono esperava
        # uma instalacao que nao resolvia, e o recibo era gravado assim mesmo,
        # entao na tentativa seguinte o Tandem dizia "ja instalei o que este
        # programa pedia" e desistia. Encontrado comparando a tabela com o
        # indice gerado do proprio winetricks (tools/indice-winetricks.py).
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

# Le um log do Wine e imprime os verbos necessarios, um por linha, sem repetir.
# Uso: t_verbos_do_log /caminho/log
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

# Le um log e imprime as DLLs que faltaram e NAO tem traducao conhecida
# (normalmente sao bibliotecas que o proprio programa deveria trazer junto).
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

# Nome amigavel de um verbo, para mostrar ao usuario.
t_verbo_amigavel() {
    case "$1" in
        vcrun2022) echo "Visual C++ 2015-2022" ;;
        vcrun2013) echo "Visual C++ 2013" ;;
        vcrun2012) echo "Visual C++ 2012" ;;
        vcrun2010) echo "Visual C++ 2010" ;;
        vcrun2008) echo "Visual C++ 2008" ;;
        vcrun2005) echo "Visual C++ 2005" ;;
        vcrun6)    echo "Visual C++ 6" ;;
        mfc42)     echo "MFC 4.2" ;;
        dotnet48)  echo ".NET Framework 4.8 (demora ~30 min)" ;;
        d3dx9|d3dx10|d3dx11_43) echo "DirectX ($1)" ;;
        d3dcompiler_43|d3dcompiler_47) echo "DirectX Compiler" ;;
        xact)      echo "DirectX Áudio" ;;
        gdiplus)   echo "GDI+" ;;
        riched20)  echo "Editor de texto rico" ;;
        msxml3|msxml4|msxml6) echo "MSXML" ;;
        openal)    echo "OpenAL (áudio)" ;;
        physx)     echo "PhysX" ;;
        *)         echo "$1" ;;
    esac
}
