# shellcheck shell=bash
# Tandem - biblioteca comum.
# Carregada por todos os executaveis. Nunca use "set -e" aqui:
# os lacos de espera dependem de comandos que falham de proposito.

TANDEM_LIB="${TANDEM_LIB:-/usr/lib/tandem}"
TANDEM_ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/tandem"
mkdir -p "$TANDEM_ESTADO" 2>/dev/null || TANDEM_ESTADO=""

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
    [ -n "$TANDEM_ESTADO" ] || return 0
    TANDEM_FIFO="$TANDEM_ESTADO/prog.$$"
    mkfifo "$TANDEM_FIFO" 2>/dev/null || { TANDEM_FIFO=""; return 0; }
    ( zenity --progress --pulsate --auto-close --no-cancel \
             --title="Tandem" --text="$1" --width=420 < "$TANDEM_FIFO" 2>/dev/null ) &
    TANDEM_PROG_PID=$!
    exec 8> "$TANDEM_FIFO"
}

t_progresso_texto() {
    [ -n "${TANDEM_FIFO:-}" ] && printf '# %s\n' "$1" >&8 2>/dev/null
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
# O Wine mantem a mesma lista do "Adicionar ou remover programas" do Windows,
# e a expoe por "wine uninstaller --list", uma linha por programa no formato
#     chave|||nome
# A chave e o que "wine uninstaller --remove" aceita.
#
# Quem chama precisa exportar WINEPREFIX. Programas portateis, que nao trazem
# desinstalador, nao aparecem aqui - e nao ha o que fazer quanto a isso, entao
# a mensagem ao usuario tem que dizer isso em vez de deixar a lista muda.
t_programas_instalados() {
    command -v wine >/dev/null 2>&1 || return 1
    wine uninstaller --list 2>/dev/null | grep -- '|||'
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
    command -v waydroid >/dev/null 2>&1 || {
        t_erro "O Android (Waydroid) não está instalado nesta máquina.

Instale com:
curl -s https://repo.waydro.id | sudo bash
sudo apt install waydroid"
        return 1; }

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
