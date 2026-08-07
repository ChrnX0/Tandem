# shellcheck shell=bash
# Tandem - biblioteca comum.
# Carregada por todos os executaveis. Nunca use "set -e" aqui:
# os lacos de espera dependem de comandos que falham de proposito.

TANDEM_LIB="${TANDEM_LIB:-/usr/lib/tandem}"
TANDEM_ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/tandem"
mkdir -p "$TANDEM_ESTADO" 2>/dev/null || TANDEM_ESTADO=""

# Travas e canos de progresso vao para o diretorio de execucao do usuario
# quando ele existe: e disco local (numa pasta pessoal em rede o flock pode
# simplesmente nao funcionar), e por sessao de boot, e ja nasce so do dono.
# Duas maquinas compartilhando a mesma pasta pessoal tambem deixam de
# colidir - o nome do cano usa o PID, que se repete entre maquinas.
if [ -n "${XDG_RUNTIME_DIR:-}" ] && mkdir -p "$XDG_RUNTIME_DIR/tandem" 2>/dev/null; then
    TANDEM_TRAVAS="$XDG_RUNTIME_DIR/tandem"
    chmod 700 "$TANDEM_TRAVAS" 2>/dev/null
else
    TANDEM_TRAVAS="${TANDEM_ESTADO:-/tmp}"
fi

# Prefixo padrao para programas Windows avulsos.
TANDEM_PREFIXO_PADRAO="${TANDEM_PREFIXO_PADRAO:-$HOME/.local/share/tandem/wine}"

# Prefixos que a automacao NUNCA pode modificar (protege sistemas em producao).
# Uma linha por caminho. Ex: ~/.wine-pdv
TANDEM_PROTEGIDOS="$HOME/.config/tandem/protegidos.txt"

# ------------------------------------------------------------------ log

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

# ------------------------------------------------------------- mensagens
#
# Regra desta secao: nenhuma mensagem pode se perder. Toda mensagem vai
# SEMPRE para o log; a tela e o terminal sao apenas os destinos visiveis.
# Se a janela nao pode ser mostrada, o texto sai no terminal - nunca some.
#
# O zenity e o notify-send falham quando nao ha sessao grafica (terminal
# puro, SSH, TTY). Sem esta checagem eles falham em silencio e o usuario
# fica com "nao aconteceu nada", que este projeto trata como defeito.

t_tem_gui() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

# ------------------------------------------------------------------ locale
#
# O zenity (via glib) recusa QUALQUER argumento com caractere nao-ASCII
# quando o locale em vigor nao foi gerado no sistema: o glib cai para
# ANSI_X3.4-1968 e responde "This option is not available", codigo 255.
# Como toda mensagem deste programa tem acento, um locale ausente faz todas
# as janelas sumirem sem deixar rastro. Por isso nunca definimos um locale
# sem antes confirmar que ele existe.

# locale -a imprime "pt_BR.utf8": sem hifen e em minusculas. Normalize os dois
# lados antes de comparar, senao "pt_BR.UTF-8" nunca casa com nada.
t_locale_existe() {
    local alvo
    alvo="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
    [ -n "$alvo" ] || return 1
    locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '-' |
        grep -qx -- "$alvo"
}

# Primeiro candidato que exista de fato. C.UTF-8 fecha a lista porque vem
# embutido na glibc: esta presente mesmo sem nenhum locale gerado.
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

# Erro que o usuario PRECISA ver: notificacao + janela; terminal se nao houver
# nem uma nem outra. O log recebe sempre, para o pos-morte de "nao funcionou".
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

# Pergunta sim/nao. Sem interface grafica nao ha como perguntar: devolve
# 1 (= "nao"), que todos os chamadores tratam como desistencia segura.
t_pergunta() {
    t_tem_gui || return 1
    command -v zenity >/dev/null 2>&1 || return 1
    zenity --question --no-wrap --title="Tandem" --text="$1" \
           --ok-label="${2:-Sim}" --cancel-label="${3:-Não}" 2>/dev/null
}

# Mostra um texto longo lido da entrada padrao.
#
# A janela so faz sentido quando ninguem esta esperando o texto na saida
# padrao. Terminal, cano e arquivo sao pedidos EXPLICITOS por texto:
#   tandem doctor                  -> terminal
#   tandem doctor | grep wine      -> o cano recebe o texto
#   tandem doctor > relatorio.txt  -> o arquivo recebe o texto
# Testar so "[ -t 1 ]" confundia os dois ultimos com duplo clique e mandava
# o diagnostico para uma janela, gravando um arquivo vazio - justamente
# quando o usuario esta tentando enviar o diagnostico para alguem.
# Sobra o duplo clique, onde a saida vai para /dev/null ou para o journal:
# ai sim a janela e o unico jeito de a pessoa ver alguma coisa.
t_texto() {
    local titulo="${1:-Tandem}" conteudo
    conteudo="$(cat)"
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

# Barra de progresso indeterminada. Uso:
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
    # Leitura E escrita, de proposito. Abrindo so para escrita, o cano fica
    # com um unico leitor - o zenity. Quando esse leitor some (o usuario
    # fecha a janela no X, o gnome-shell reinicia, o zenity recusa uma
    # opcao), a proxima mensagem de progresso recebe SIGPIPE e MATA o Tandem
    # inteiro: saida 141, nada no log, nenhuma janela. No tandem-exe isso
    # acontece dentro do laco do winetricks, cortando uma instalacao pela
    # metade sem recibo. Mantendo o descritor 8 tambem aberto para leitura,
    # o cano nunca fica sem leitor e a escrita nunca gera o sinal.
    exec 8<> "$TANDEM_FIFO"
}

t_progresso_texto() {
    [ -n "${TANDEM_FIFO:-}" ] || return 0
    # A janela ainda esta viva? Se o usuario fechou, registramos e paramos de
    # escrever - o trabalho continua, so deixa de ter barra de progresso.
    if [ -n "${TANDEM_PROG_PID:-}" ] && ! kill -0 "$TANDEM_PROG_PID" 2>/dev/null; then
        t_diz "janela de progresso fechada pelo usuario; seguindo sem ela"
        exec 8>&- 2>/dev/null
        rm -f "$TANDEM_FIFO" 2>/dev/null
        TANDEM_FIFO=""
        return 0
    fi
    printf '# %s\n' "$1" >&8 2>/dev/null
    return 0
}

t_progresso_fecha() {
    [ -n "${TANDEM_FIFO:-}" ] || return 0
    exec 8>&- 2>/dev/null
    wait "$TANDEM_PROG_PID" 2>/dev/null
    rm -f "$TANDEM_FIFO" 2>/dev/null
    TANDEM_FIFO=""
    return 0
}

# ---------------------------------------------------------------- prefixo

# Sobe a arvore de diretorios procurando a raiz de um prefixo Wine.
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

# Um prefixo esta protegido se o usuario listou, ou se nao e o nosso padrao
# e nao foi criado pelo Tandem (marca .tandem-prefixo).
#
# A lista do usuario e consultada PRIMEIRO, de proposito: quem roda
# "tandem protect" no proprio prefixo padrao esta pedindo que nem o Tandem
# mexa nele, e essa decisao tem que valer mais que a marca de propriedade.
t_prefixo_protegido() {
    local p="$1"
    if [ -f "$TANDEM_PROTEGIDOS" ] && grep -qxF -- "$p" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
        return 0
    fi
    [ "$p" = "$TANDEM_PREFIXO_PADRAO" ] && return 1
    [ -f "$p/.tandem-prefixo" ] && return 1
    return 0   # desconhecido = trate como protegido
}

# Registra um prefixo na lista de intocaveis. Idempotente.
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

# Procura prefixos Wine que ja existiam e registra todos como protegidos.
#
# Os lugares conhecidos primeiro, depois uma varredura rasa da pasta pessoal:
# um instalador de terceiro (um sistema de frente de caixa, por exemplo) pode
# ter posto o prefixo em qualquer canto. O -maxdepth limita o custo e o
# timeout garante que uma pasta pessoal enorme nao trave a primeira execucao;
# se a varredura for cortada, os lugares conhecidos ja foram cobertos.
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

# Trabalho que precisa acontecer uma vez por usuario, na primeira execucao.
#
# Isto vive aqui, e nao no postinst do pacote, porque la o trabalho
# por-usuario depende de adivinhar quem instalou - SUDO_USER, PKEXEC_UID e
# logname. As tres vias falham juntas quando o .deb e instalado pelo
# instalador grafico, que roda num daemon sem sudo e sem terminal de
# controle: o bloco inteiro e pulado e o usuario fica sem protecao visivel e
# sem associacao de arquivo, sem nenhum aviso. Aqui nao ha o que adivinhar,
# ja estamos rodando como o dono do HOME - funcione o pacote instalado por
# apt, por dpkg, pelo instalador grafico, ou por um usuario criado depois.
#
# A marca evita repetir: quem mudar a associacao de proposito depois nao
# quer o Tandem reescrevendo a escolha dele a cada duplo clique.
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

# ------------------------------------------------------- atalhos de menu
#
# Quando um instalador Windows cria atalho no Menu Iniciar, o winemenubuilder
# cria o .desktop correspondente em ~/.local/share/applications/wine/Programs.
# Duas coisas precisam acontecer depois disso, e nenhuma acontecia:
#
# 1. Atualizar o cache do ambiente grafico. O Tandem ja fazia isso, mas ANTES
#    de executar o programa - cedo demais para ver um atalho que ainda nao
#    existia. O menu entao ignora uma subpasta que acabou de nascer.
# 2. Dizer ao usuario onde o programa foi parar. Sem isso o desfecho e
#    "instalei e sumiu": o programa entra na maquina e a pessoa nao tem
#    caminho de volta. Sucesso silencioso e tao ruim quanto erro silencioso.

t_atalhos_wine() {
    find "$HOME/.local/share/applications/wine" -name '*.desktop' 2>/dev/null | LC_ALL=C sort
}

# So os atalhos do nosso prefixo. Atalho de prefixo alheio esta na mesma
# pasta mas e do dono dele: nao listamos, nao abrimos, nao apagamos.
t_atalhos_nossos() {
    local d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        grep -qF -- "$TANDEM_PREFIXO_PADRAO" "$d" 2>/dev/null && printf '%s\n' "$d"
    done <<< "$(t_atalhos_wine)"
    return 0
}

# Nome amigavel de um atalho, para mostrar ao usuario.
t_nome_do_atalho() {
    local n
    n="$(sed -n 's/^Name=//p' "$1" 2>/dev/null | head -1)"
    [ -n "$n" ] || n="$(basename -- "${1%.desktop}")"
    printf '%s' "$n"
}

# Compara com a lista de antes e anuncia o que apareceu.
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

# --------------------------------------------- programas Windows instalados
#
# O Windows guarda a lista do "Adicionar ou remover programas" no registro,
# em CurrentVersion\Uninstall. Nos lemos o system.reg e o user.reg do prefixo
# DIRETAMENTE, em vez de perguntar ao "wine uninstaller", por um motivo
# descoberto em maquina real: instalador de 32 bits grava a chave numa visao
# do registro, e o uninstaller.exe - que vira processo de 32 bits quando o
# wine32 esta presente - enumera a outra. Resultado: 7-Zip instalado, chave
# no registro, e a lista vazia. Lendo o arquivo nos enxergamos as duas
# visoes (nativa e Wow6432Node), nao dependemos da arquitetura do processo,
# e nem precisamos do Wine para listar.
#
# Saida, uma linha por programa:
#     chave|||nome|||desinstalador-silencioso|||desinstalador
# Entradas sem nome ou sem desinstalador nao sao programas de verdade
# (componentes, runtimes) e ficam de fora, como no proprio Windows.
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

# Compatibilidade com quem so quer "chave|||nome".
t_programas_instalados() {
    t_uninstall_dump "$@" | awk -F'\\|\\|\\|' '{ printf "%s|||%s\n", $1, $2 }'
}

# Separa um comando do Windows ("C:\...\Uninstall.exe" /S) em executavel e
# argumentos, e o executa no prefixo atual. O caminho pode vir entre aspas
# (e quase sempre vem, por causa de "Program Files").
t_executa_comando_windows() {
    local cmd="$1" exe resto
    case "$cmd" in
        '"'*)
            exe="${cmd#\"}"; exe="${exe%%\"*}"
            # Corte por comprimento, nunca por padrao: as barras invertidas
            # de um caminho Windows viram escape em ${var#padrao} e o corte
            # falha em silencio, repetindo o caminho como argumento.
            resto="${cmd:$(( ${#exe} + 2 ))}" ;;
        *)
            exe="${cmd%% *}"
            resto="${cmd:${#exe}}" ;;
    esac
    resto="${resto# }"
    [ -n "$exe" ] || return 1
    # Os argumentos do desinstalador sao separados por espaco de proposito.
    # shellcheck disable=SC2086
    wine "$exe" $resto
}

# Remove atalhos de menu que apontam para programa que nao existe mais.
#
# Depois de desinstalar, o Wine costuma deixar o atalho para tras. Um atalho
# que nao abre nada e pior que atalho nenhum: o usuario clica, nao acontece
# nada, e conclui que o computador esta quebrado.
#
# So mexemos em atalho que cita o NOSSO prefixo. Atalho de prefixo alheio e
# do dono dele, mesmo estando na mesma pasta.
t_limpa_atalhos_orfaos() {
    local base d rel lnk n=0
    base="$HOME/.local/share/applications/wine/Programs"
    [ -d "$base" ] || return 0
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        grep -qF -- "$TANDEM_PREFIXO_PADRAO" "$d" 2>/dev/null || continue
        rel="${d#"$base/"}"; rel="${rel%.desktop}"
        # O Wine espelha a arvore do Menu Iniciar ao criar o atalho, entao o
        # .lnk correspondente tem o mesmo caminho relativo.
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

# Arquitetura de um executavel PE: 32, 64, arm64 ou "?"; falha se nao for PE.
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

# --------------------------------------------------------- alternativas
#
# O melhor desfecho para o dono nem sempre e "seu programa Windows roda no
# Wine". As vezes e "voce nao precisa do Wine": muitos programas tem versao
# oficial para Linux, e rodar a versao Windows deles no Wine e sempre pior -
# mais lento, sem atualizacao, e quebra quando o Wine muda.
#
# O Tandem nunca troca nada e nunca sugere trocar programa que esta
# funcionando. Isto aparece em duas situacoes: quando o dono pergunta, e
# quando o pre-voo reconheceu que aquele programa nunca vai funcionar aqui -
# onde ficar calado seria deixar o dono sem saida nenhuma.
#
# A tabela e local e auditavel, nao uma busca na internet: o Tandem funciona
# sem rede e nao manda nada para lugar nenhum. Uma linha nova basta.

TANDEM_ALTERNATIVAS="${TANDEM_ALTERNATIVAS:-${TANDEM_LIB:-/usr/lib/tandem}/alternativas.tsv}"

# Procura por nome. Devolve "classe|nome|como instalar|o que muda", uma
# alternativa por linha.
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

# Texto pronto para mostrar ao dono, ou vazio se nao houver nada.
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

# ------------------------------------------------------------- memoria
#
# Toda vez que o Tandem roda ele descobre coisas - quais componentes o
# programa pediu, qual resolveu, quanto tempo levou, se abriu no fim. Ate
# aqui isso virava uma linha de log e morria. A memoria guarda o que foi
# aprendido POR PROGRAMA, num arquivo de texto legivel que o dono pode abrir,
# conferir e mandar para outra pessoa.
#
# Duas regras que a memoria nao pode quebrar:
#
# 1. Ela nunca age sozinha. Uma receita e sugestao, nao ordem: o Tandem
#    mostra o que aprendeu e pergunta. Licao errada aprendida em silencio se
#    repetiria para sempre, e este programa mexe na maquina onde o dono
#    fatura.
# 2. Ela e sempre legivel e apagavel. Se a memoria atrapalhar, "tandem
#    esquecer" resolve, e o dono consegue LER o que estava guardado antes de
#    decidir.

TANDEM_MEMORIA="${TANDEM_MEMORIA:-$HOME/.local/share/tandem/memoria}"

# Identidade estavel de um programa: tamanho + inicio + fim do arquivo.
#
# Nao usamos o caminho, que muda de pasta e de maquina, nem o nome, que se
# repete ("setup.exe"). Ler o arquivo inteiro seria lento num instalador de
# meio giga, e as pontas mais o tamanho ja separam versoes diferentes do
# mesmo programa - que e a unica confusao que importa evitar aqui.
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
    local arq; arq="$(t_memoria_arquivo "$1")" || return 1
    [ -f "$arq" ] || return 1
    sed -n "s/^$2=//p" "$arq" | tail -1
}

# Grava uma chave, substituindo o valor anterior. Cria o arquivo na primeira
# vez, com o nome do programa em cima para o dono saber do que se trata.
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
    { grep -v "^$chave=" "$arq" 2>/dev/null; printf '%s=%s\n' "$chave" "$valor"; } > "$tmp" 2>/dev/null &&
        mv -f "$tmp" "$arq" 2>/dev/null
}

# Acrescenta um item a uma lista separada por espaco, sem repetir.
t_memoria_junta() {
    local prog="$1" chave="$2" item="$3" atual
    atual="$(t_memoria_le "$prog" "$chave" 2>/dev/null)"
    case " $atual " in *" $item "*) return 0 ;; esac
    t_memoria_grava "$prog" "$chave" "${atual:+$atual }$item"
}

t_memoria_esquece() {
    local arq; arq="$(t_memoria_arquivo "$1" 2>/dev/null)" || return 1
    [ -f "$arq" ] || return 1
    rm -f -- "$arq"
}

# --------------------------------------------------------- pre-voo do PE
#
# Todo executavel Windows traz no proprio arquivo a lista de bibliotecas que
# vai pedir - a tabela de importacoes. Ate agora o Tandem so descobria isso
# DEPOIS de rodar e falhar, lendo o err:module:import_dll do Wine.
#
# O pre-voo NAO decide o que instalar. Nao pode: so o Wine sabe quais DLLs
# ele proprio implementa, e agir por conta daria instalacao inutil - meia
# hora do dono jogada fora. O pre-voo serve para o que a leitura sozinha
# prova: reconhecer, ANTES de tentar, um programa que depende de coisa que
# nunca vai funcionar aqui, e ter isso pronto para explicar a falha depois.

t_pe_dlls() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "${TANDEM_LIB:-/usr/lib/tandem}/peinfo.py" "$1" 2>/dev/null |
        sed -n -e 's/^DLLS=//p' -e 's/^ATRASADAS=//p' | tr ',' '\n' | grep -v '^$'
}

# Devolve "classe|frase" do primeiro limite permanente reconhecido, ou nada.
# A tabela mora em limites.tsv e cresce sem tocar em codigo.
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
            # O padrao vem da tabela e usa * de proposito, entao nao pode
            # ser citado.
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

# O caso normal, e o que o prefixo do Tandem usa (WINEARCH=win64). Existe
# como funcao propria porque o diagnostico precisa AFIRMAR que 64 bits
# funciona: falar so do 32, que e a excecao, faz o leitor concluir que 64
# nao e suportado.
t_tem_wine64() {
    [ -d /usr/lib/wine/x86_64-unix ] || [ -d /usr/lib/x86_64-linux-gnu/wine ] ||
    [ -d /opt/wine-stable/lib/wine/x86_64-unix ]
}

# ------------------------------------------------------- instalar o que falta
#
# O Tandem sabe diagnosticar o que falta (doctor); daqui ele tambem conserta.
# Nao da para fazer isso durante a instalacao do proprio .deb: o dpkg segura
# uma trava enquanto o postinst roda, e "apt-get install" la dentro morre em
# deadlock. O momento certo e o primeiro uso - ou a hora exata do clique em
# que a peca faltou.

# Executa um script como root: direto se ja somos root, sudo se ha terminal,
# pkexec se ha sessao grafica. A ordem poe o terminal na frente porque nele
# o usuario VE o apt trabalhando; o pkexec mostra so o pedido de senha.
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

# O que falta nesta maquina, uma peca por linha. Cada linha e
#     codigo|descricao para o usuario
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

# Monta o script de instalacao para as pecas pedidas (uma por argumento).
# Tudo em um script so: uma unica senha, uma unica execucao.
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
                # O Waydroid nao esta nos repositorios do Ubuntu/Zorin: vem
                # do repositorio oficial do projeto. Adicionamos a fonte com
                # chave conferida, do jeito que o proprio projeto instrui.
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

# ---------------------------------------------------------------- waydroid

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

# Garante container + sessao + boot completo. Devolve 1 e ja avisa em caso de falha.
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

    # A sessao pode estar subindo pelo autostart: dê um tempo antes de competir.
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
