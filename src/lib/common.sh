#!/bin/bash
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

t_aviso() {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -i "${2:-dialog-information}" -a Tandem "Tandem" "$1" 2>/dev/null && return 0
    command -v logger >/dev/null 2>&1 && logger -t tandem "$1"
    return 0
}

t_ok() {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -i emblem-ok -t 10000 -a Tandem "Tandem" "$1" 2>/dev/null
    command -v logger >/dev/null 2>&1 && logger -t tandem "OK: $1"
    return 0
}

# Erro que o usuario PRECISA ver: notificacao + janela.
t_erro() {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u critical -i dialog-error -a Tandem "Tandem" "$1" 2>/dev/null
    if command -v zenity >/dev/null 2>&1; then
        zenity --error --no-wrap --title="Tandem" \
               --text="$1${LOG:+$'\n\n'Detalhes técnicos:$'\n'$LOG}" 2>/dev/null
    fi
    command -v logger >/dev/null 2>&1 && logger -t tandem "ERRO: $1"
    return 0
}

t_pergunta() {
    command -v zenity >/dev/null 2>&1 || return 1
    zenity --question --no-wrap --title="Tandem" --text="$1" \
           --ok-label="${2:-Sim}" --cancel-label="${3:-Não}" 2>/dev/null
}

# Barra de progresso indeterminada. Uso:
#   t_progresso_abre "Instalando..." ; ... ; t_progresso_fecha
t_progresso_abre() {
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
t_prefixo_protegido() {
    local p="$1"
    [ "$p" = "$TANDEM_PREFIXO_PADRAO" ] && return 1
    [ -f "$p/.tandem-prefixo" ] && return 1
    if [ -f "$TANDEM_PROTEGIDOS" ] && grep -qxF -- "$p" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
        return 0
    fi
    return 0   # desconhecido = trate como protegido
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
