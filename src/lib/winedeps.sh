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

# So responde quando o indice tem confianca alta. Quando varios verbos de
# FAMILIAS diferentes entregam a mesma DLL, escolher e chute - e chute que
# custa meia hora do dono. Nesse caso a resposta honesta e nao saber.
t_dll_no_indice() {
    [ -n "${TANDEM_VERBOS_TSV:-}" ] && [ -f "$TANDEM_VERBOS_TSV" ] || return 1
    awk -F'\t' -v alvo="${1,,}" \
        '$1 == alvo && $3 == "alta" { print $2; achou = 1; exit } END { exit !achou }' \
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
        # O vcrun6 entrega "mfc42, msvcp60, msvcirt" - nao as 71. Quem
        # entrega msvcp71/msvcr71/mfc71 e o vcrun2003, que diz isso no
        # proprio titulo. Segundo erro achado pelo auditor do winetricks.
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
        # O xact entrega xaudio2, x3daudio, xapofx e xactengine - nao o
        # xinput, que tem verbo proprio. Terceiro erro do auditor.
        xinput1_*.dll|xinput9*.dll) echo xinput ;;
        x3daudio*.dll|xaudio2*.dll|xactengine*.dll|xapofx*.dll) echo xact ;;
        dxgi.dll|d3d11.dll|d3d10*.dll)                       echo d3dx11_43 ;;

        # Diversos comuns
        gdiplus.dll)         echo gdiplus ;;
        riched20.dll|riched32.dll) echo riched20 ;;
        msxml3.dll)          echo msxml3 ;;
        msxml4.dll)          echo msxml4 ;;
        msxml6.dll)          echo msxml6 ;;
        openal32.dll)        echo openal ;;
        physxloader.dll)     echo physx ;;
        quartz.dll)          echo quartz ;;
        # O quartz entrega so o quartz.dll; o amstream tem verbo proprio.
        amstream.dll)        echo amstream ;;
        wmvcore.dll)         echo wmp9 ;;
        # O wmp9 entrega l3codeca, wmp, wmplayer e wmvcore - o wmasf so vem
        # no wmp11. Quarto erro do auditor.
        wmasf.dll)           echo wmp11 ;;
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

# Os mesmos pares que a funcao acima calcula e descarta: dll<TAB>verbo.
#
# E a chave que faltava. O recibo em .tandem-verbos guarda o NOME DO VERBO e
# a condicao de gravacao e o winetricks ter saido 0 - ou seja, um cache cuja
# chave e a pergunta e cujo valor e "eu ja respondi", sem registro nenhum de
# se a resposta serviu. Todo cache assim guarda respostas, nao respostas
# certas: uma traducao errada entra igual a uma certa, e a regra numero 4
# passa a proibir a correcao. Com o par em maos da para perguntar depois:
# a DLL que faltava apareceu?
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

# ------------------------------------------------------- traducao suspeita
#
# Quando o winetricks sai 0 e a DLL pedida continua faltando, quem errou fui
# eu: a tabela mandou instalar o pacote errado. O caso nao pode virar recibo
# (o recibo faria o Tandem dizer "ja instalei o que este programa pedia" e
# desistir para sempre) nem virar licao na memoria (a licao errada viajaria
# junto com a receita para a outra maquina). Vira anotacao, aqui.
t_anota_suspeita() {
    local dll="$1" verbo="$2"
    [ -n "$dll" ] && [ -n "$verbo" ] || return 0
    [ -n "${TANDEM_ESTADO:-}" ] || return 0
    printf '%s\t%s\t%s\n' "$dll" "$verbo" "$(date +%F)" \
        >> "$TANDEM_ESTADO/traducao-suspeita.tsv" 2>/dev/null || return 0
}

# Transforma as suspeitas desta execucao na frase que o dono le. A mensagem
# assume a culpa em vez de mandar ele procurar defeito na maquina - que e o
# que "instalei as dependencias e ainda nao abre" fazia.
t_texto_suspeitas() {
    local linhas="$1" dll verbo texto=""
    while IFS="$(printf '\t')" read -r dll verbo; do
        [ -n "$dll" ] && [ -n "$verbo" ] || continue
        texto="$texto
- instalei $(t_verbo_amigavel "$verbo"), mas $dll continua faltando"
    done <<EOF
$linhas
EOF
    printf 'O programa pediu arquivos que eu tentei instalar, e eles não chegaram:
%s

Isso é erro meu, não da sua máquina: a tradução que eu uso para esses arquivos aponta para o pacote errado. Já anotei e não vou repetir a mesma instalação.' "$texto"
}

# O caminho inverso: dado um verbo, qual DLL ele deveria ter entregue?
#
# Serve ao atalho da memoria e da lista, onde o Tandem instala sem ter visto
# nenhum erro do Wine - entao nao existe par dll/verbo vindo do log para
# conferir. Sem uma resposta aqui, aquele caminho gravava recibo so com o
# codigo de saida, contornando inteira a prova de entrega. Responder "nao sei"
# e legitimo: ausencia de prova nao condena.
t_dll_do_verbo() {
    local v="$1"
    [ -n "$v" ] || return 1
    [ -n "${TANDEM_VERBOS_TSV:-}" ] && [ -f "$TANDEM_VERBOS_TSV" ] || return 1
    awk -F'\t' -v alvo="$v" \
        '$2 == alvo && $3 == "alta" { print $1; achou = 1; exit } END { exit !achou }' \
        "$TANDEM_VERBOS_TSV"
}

# ------------------------------------------------------- verbo x bitola
#
# Continuacao do achado da bitola. Levantado do winetricks 20240105
# instalado, verbo por verbo (ha um teste que refaz esse levantamento e
# reprova se estas duas listas envelhecerem):
#
#   - a maioria dos verbos modernos JA instala as duas cargas sozinha. O
#     vcrun2022, por exemplo, roda o vc_redist.x86 e, se o prefixo for win64,
#     tambem o vc_redist.x64. Para esses nao ha nada a escolher.
#   - UM unico verbo tem irmao de 64 bits explicito: xact -> xact_x64.
#   - oito verbos so tem carga de 32 bits e nao tem irmao nenhum. Para um
#     programa de 64 bits que precise deles, nao existe conserto - e dizer
#     isso ANTES vale mais do que descobrir depois de meia hora de download.

# O irmao de 64 bits deste verbo, se existir NESTE winetricks. Conferir no
# arquivo instalado, e nao confiar na lista a mao, porque o winetricks e
# atualizado por fora do Tandem.
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
        esac
    fi
    printf '%s' "$verbo"
}

# Verbos sem carga de 64 bits e sem irmao que tenha. Nao bloqueiam nada: o
# Tandem avisa e deixa o dono decidir, do mesmo jeito que faz com limites.tsv.
t_verbo_so_32() {
    case "$1" in
        dbghelp|mfc42|msxml3|msxml4|openal|riched20|vcrun2003|wsh57) return 0 ;;
    esac
    return 1
}

# O componente chegou, na bitola que este programa nao consegue usar.
#
# Nao e erro de traducao nem defeito da maquina: e limite de quem distribui o
# componente. Metade dos verbos do winetricks so tem carga de 32 bits - o
# proprio winetricks avisa isso em ingles no meio do log, onde ninguem le.
t_texto_bitola() {
    local linhas="$1" arch="${2:-64}" outra dll verbo texto=""
    [ "$arch" = 32 ] && outra=64 || outra=32
    while IFS="$(printf '\t')" read -r dll verbo; do
        [ -n "$dll" ] && [ -n "$verbo" ] || continue
        texto="$texto
- $(t_verbo_amigavel "$verbo") instalou $dll, mas só na versão de $outra bits"
    done <<EOF
$linhas
EOF
    printf 'Este programa é de %s bits, e o componente que ele pede só existe em %s bits:
%s

Não é defeito da sua máquina nem falta de instalação: quem distribui esse componente nunca publicou a versão de %s bits. Se existir uma versão de %s bits deste mesmo programa, ela deve funcionar aqui.' \
        "$arch" "$outra" "$texto" "$arch" "$outra"
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
        vcrun2019) echo "Visual C++ 2015-2019" ;;
        vcrun2003) echo "Visual C++ 2003" ;;
        vcrun6)    echo "Visual C++ 6" ;;
        mfc42)     echo "MFC 4.2" ;;
        dotnet48)  echo ".NET Framework 4.8 (demora ~30 min)" ;;
        d3dx9|d3dx10|d3dx11_43) echo "DirectX ($1)" ;;
        d3dcompiler_43|d3dcompiler_47) echo "DirectX Compiler" ;;
        d3dcompiler_46) echo "DirectX Compiler" ;;
        xact)      echo "DirectX Áudio" ;;
        xinput)    echo "DirectX (controles)" ;;
        gdiplus)   echo "GDI+" ;;
        riched20)  echo "Editor de texto rico" ;;
        msxml3|msxml4|msxml6) echo "MSXML" ;;
        openal)    echo "OpenAL (áudio)" ;;
        physx)     echo "PhysX" ;;
        quartz|amstream) echo "DirectShow (vídeo)" ;;
        wmp9|wmp11) echo "Windows Media Player" ;;
        wsh57)     echo "Windows Script Host" ;;
        dbghelp)   echo "Depurador do Windows" ;;
        secur32)   echo "Segurança do Windows" ;;
        usp10)     echo "Desenho de texto (Uniscribe)" ;;
        *)         echo "$1" ;;
    esac
}
