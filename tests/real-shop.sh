#!/bin/bash
# Tandem - the closed loop, against a REAL shop program, on a REAL counter.
#
# This is the project's largest uncertainty and no amount of CI moves it:
# tests/run.sh covers the libraries against a fake wine and a fake winetricks;
# tests/real-programs.sh runs freely redistributable Windows software weekly.
# Neither has ever seen a Brazilian point-of-sale system, an accounting package
# or a fiscal printer driver - which is the software the person this was
# written for actually needs.
#
#   bash tests/real-shop.sh /caminho/do/instalador.exe
#
# What it is FOR is turning "the one afternoon" into an instrument. Doing this
# by hand means running the thing, squinting at a log, trying to remember what
# to write down and what to ask afterwards. This captures the whole loop -
# pre-flight, what Wine asked for, which components were mapped and installed,
# whether each one arrived in a width this program can use, how long it took,
# and what the owner says at the end - into one report.
#
# ------------------------------------------------------------------ TWO RULES
#
# RULE ONE, and it is not negotiable: this NEVER writes into a Wine prefix
# Tandem did not create. The machine this exists for runs a point-of-view sale
# system in its own prefix, and installing a dependency inside a working
# production environment is worse than not automating at all. The harness
# refuses to start if the prefix it would use lacks the .tandem-prefixo marker
# AND already exists - see conferir_prefixo below, which aborts rather than
# asking, because a wrong "yes" here costs somebody their till.
#
# RULE TWO: the component question is answered automatically, and the "did it
# actually work" question is NOT. The first is a decision about downloads and
# the owner already made it by running this. The second is the only evidence
# the community list carries that is worth anything - a person looking at a
# screen - and a harness that answered it for him would be manufacturing the
# one field nobody else can supply. It is asked, out loud, at the end.

cd "$(dirname -- "$0")/.." || exit 1
ROOT="$PWD"

PROG="${1:-}"
if [ -z "$PROG" ] || [ "$PROG" = "--ajuda" ] || [ "$PROG" = "-h" ]; then
    cat <<'AJUDA'
Uso:  bash tests/real-shop.sh /caminho/do/instalador.exe

Roda o instalador de verdade pelo Tandem, deixa ele instalar os componentes
que detectar, e escreve um relatorio com o caminho inteiro. No fim pergunta se
o programa funcionou - essa resposta e sua, e e a unica coisa do relatorio que
ninguem consegue adivinhar.

O prefixo do PDV nao e tocado. Se o Tandem for usar um prefixo que nao foi ele
que criou, isto para antes de comecar.
AJUDA
    exit 0
fi

if [ ! -f "$PROG" ]; then
    printf 'Nao achei o arquivo: %s\n' "$PROG" >&2
    exit 1
fi
PROG="$(cd "$(dirname -- "$PROG")" && printf '%s/%s' "$PWD" "$(basename -- "$PROG")")"

# The library comes from the tree this script sits in, so the harness measures
# the code being worked on rather than whatever version is installed.
export TANDEM_LIB="${TANDEM_LIB:-$ROOT/src/lib}"
export TANDEM_BIN="${TANDEM_BIN:-$ROOT/src/bin}"
# shellcheck source=../src/lib/common.sh
. "$TANDEM_LIB/common.sh" || { printf 'nao consegui carregar a biblioteca\n' >&2; exit 1; }
# BOTH, because common.sh does not source winedeps.sh - tandem-exe sources the
# two separately. Loading only the first left t_dll_para_verbo undefined, and
# the harness would have died on that line at the counter, which is the one
# place there is no second try.
# shellcheck source=../src/lib/winedeps.sh
. "$TANDEM_LIB/winedeps.sh" 2>/dev/null

QUANDO="$(date +%Y-%m-%d-%H%M%S)"
RELATORIO="${TANDEM_RELATORIO:-$HOME/tandem-balcao-$QUANDO.txt}"
BRUTO="$(mktemp -t tandem-balcao-XXXXXX)"
trap 'rm -f "$BRUTO"' EXIT

diz() { printf '%s\n' "$*" | tee -a "$RELATORIO"; }
secao() { printf '\n== %s ==\n' "$*" | tee -a "$RELATORIO"; }

: > "$RELATORIO"
diz "Tandem $TANDEM_VERSAO - relatorio de balcao"
diz "arquivo: $(basename -- "$PROG")"
diz "quando:  $QUANDO"
diz ""
diz "Este relatorio NAO carrega o caminho do arquivo, o seu nome de usuario"
diz "nem o nome da maquina. So o que foi preciso para o programa abrir."

# --------------------------------------------------------------- RULE ONE
#
# Refuses rather than asks. t_prefixo_do_arquivo is what tandem-exe itself
# uses, so this is the same answer the real run will get - asking the question
# here and a different one there would prove nothing.
conferir_prefixo() {
    local pfx
    pfx="$(t_prefixo_do_arquivo "$PROG" 2>/dev/null)"
    if [ -z "$pfx" ]; then
        diz "prefixo: o Tandem vai criar um novo"
        return 0
    fi
    if [ ! -d "$pfx" ]; then
        diz "prefixo: sera criado ($(basename -- "$pfx"))"
        return 0
    fi
    if [ -f "$pfx/.tandem-prefixo" ]; then
        diz "prefixo: um que o Tandem criou ($(basename -- "$pfx"))"
        return 0
    fi
    printf '\n' >&2
    printf 'PAREI. O ambiente que seria usado nao foi criado pelo Tandem:\n' >&2
    printf '  %s\n\n' "$pfx" >&2
    printf 'Pode ser o ambiente de um programa que ja funciona - o do PDV, por\n' >&2
    printf 'exemplo. Mexer nele para testar seria pior que nao testar.\n' >&2
    return 1
}

secao "o ambiente"
conferir_prefixo || exit 2
diz "wine:       $(t_stack_wine 2>/dev/null || printf 'nao encontrado')"
diz "winetricks: $(command -v winetricks >/dev/null 2>&1 && printf 'presente' || printf 'AUSENTE')"
diz "wine 32:    $(t_tem_wine32 2>/dev/null && printf 'sim' || printf 'nao')"
diz "livre:      $(df -h --output=avail "$HOME" 2>/dev/null | tail -1 | tr -d ' ')"

# --------------------------------------------------------------- PRE-FLIGHT
#
# Everything readable WITHOUT running the program. On a shop installer this is
# the half most likely to say something nobody knew: 2 of 2 real installers
# surveyed for this project are 32-bit, including the one that installs 64-bit
# software, and that fact came out of exactly this reading.
secao "antes de rodar (nada foi executado ainda)"
diz "tamanho:    $(t_tamanho_amigavel "$(stat -c%s "$PROG" 2>/dev/null || echo 0)" 2>/dev/null)"
ARCH="$(t_pe_arch "$PROG" 2>/dev/null)"
diz "bitola:     ${ARCH:-nao consegui ler}"
diz "impressao:  $(t_memoria_id "$PROG" 2>/dev/null | cut -c1-16)..."

IMPORTS="$(t_pe_dlls "$PROG" 2>/dev/null)"
if [ -n "$IMPORTS" ]; then
    diz "pede estas bibliotecas:"
    for d in $IMPORTS; do diz "  - $d"; done
else
    diz "nao consegui ler a tabela de importacoes (pode ser um instalador comprimido)"
fi

LIMITE="$(t_limite_do_programa "$PROG" 2>/dev/null)"
[ -n "$LIMITE" ] && diz "limite conhecido: ${LIMITE#*|}"

# --------------------------------------------------------------- THE RUN
#
# The graphical session is disabled ON PURPOSE. It is not to avoid windows: it
# is so every question and every answer lands in the captured output instead of
# on a screen nobody is recording, and so the ONE component question can be
# answered deterministically. tests/terminal.py hands the child a real
# terminal, which is the path this project only started measuring in 4.16.
secao "rodando pelo Tandem"
diz "(a pergunta sobre instalar componentes e respondida com SIM automaticamente;"
diz " a pergunta sobre o programa ter funcionado e sua, la embaixo)"
INICIO=$SECONDS
if [ -f "$ROOT/tests/terminal.py" ]; then
    ( unset DISPLAY WAYLAND_DISPLAY
      TANDEM_PTY_LIMITE="${TANDEM_PTY_LIMITE:-7200}" \
      python3 "$ROOT/tests/terminal.py" "s" \
              bash "$TANDEM_BIN/tandem-exe" "$PROG" ) > "$BRUTO" 2>&1
    RC=$?
else
    ( unset DISPLAY WAYLAND_DISPLAY
      printf 's\n' | bash "$TANDEM_BIN/tandem-exe" "$PROG" ) > "$BRUTO" 2>&1
    RC=$?
fi
LEVOU=$(( SECONDS - INICIO ))
diz "terminou com status $RC, em $((LEVOU / 60)) min $((LEVOU % 60)) s"
diz ""
diz "--- o que apareceu na tela ---"
sed 's/^/  /' "$BRUTO" | tee -a "$RELATORIO" >/dev/null
sed -n '1,60p' "$BRUTO" | sed 's/^/  /'

# --------------------------------------------------------------- THE LOOP
#
# What the memory recorded is the loop's own account of itself, and it is the
# part a second machine can use. PROVA is the one worth reading twice: it says
# whether the file Wine asked for actually arrived, in a width this program can
# load - "entregue" is proof, "sem-alvo" means there was nothing to check, and
# those two are deliberately not the same answer.
secao "o que o Tandem aprendeu"
for campo in ARQUITETURA RESOLVERAM NAO_RESOLVERAM PROVA RESULTADO CONFIRMADO SEGUNDOS; do
    valor="$(t_memoria_le "$PROG" "$campo" 2>/dev/null)"
    [ -n "$valor" ] && diz "$(printf '%-16s %s' "$campo:" "$valor")"
done

PEDIDAS="$(grep -o 'Library [A-Za-z0-9_.-]*\.dll' "${LOG:-/dev/null}" 2>/dev/null |
           sort -u | sed 's/^Library //')"
if [ -n "$PEDIDAS" ]; then
    diz ""
    diz "bibliotecas que o Wine reclamou:"
    for d in $PEDIDAS; do diz "  - $d -> $(t_dll_para_verbo "$d" 2>/dev/null || printf '(sem traducao)')"; done
fi

# --------------------------------------------------------------- RULE TWO
#
# His answer, and only his. Everything above is the machine describing itself;
# this is the single field that requires a person, and it is the one the
# community list weighs a full report on. Wine's characteristic failure with
# commercial software is opening and being subtly wrong, so "it exited 0" is
# not an answer to this question and never was.
secao "agora e com voce"
printf '\n'
printf 'O programa abriu E funcionou como voce esperava?\n'
printf 'Se ele abriu mas fez algo errado - imprimiu torto, nao achou a impressora,\n'
printf 'travou numa tela - a resposta e NAO. Isso vale mais que tudo acima.\n\n'
printf '  [s] sim, funcionou    [n] nao    [p] abriu mas nao deu para saber\n> '
# "nobody was there to ask" and "he could not tell" are different facts, and a
# read against a closed stdin returns instantly with an empty answer - so
# without this the report would quietly claim the second when the first
# happened. It is the same distinction t_pergunta is documented as needing,
# and the reason this harness must never be run from cron.
if ! read -r RESPOSTA; then
    diz "resposta do dono: NAO HAVIA NINGUEM PARA PERGUNTAR"
    diz "(rodado sem terminal - o campo que mais vale ficou em branco, e"
    diz " nenhuma confirmacao foi gravada)"
    secao "fim"
    diz "relatorio salvo em: $RELATORIO"
    exit 0
fi

case "$RESPOSTA" in
    s|S|sim|SIM|y|Y)
        t_memoria_grava "$PROG" CONFIRMADO sim 2>/dev/null
        diz "resposta do dono: FUNCIONOU" ;;
    n|N|nao|NAO)
        t_memoria_grava "$PROG" CONFIRMADO nao 2>/dev/null
        diz "resposta do dono: NAO funcionou" ;;
    *)
        diz "resposta do dono: nao deu para saber" ;;
esac

# --------------------------------------------------------------- THE RECORD
#
# Built and shown before anything leaves. t_lista_vaza is the sieve that
# refuses a line carrying a filename, a path, a user name, a machine name or an
# IP - it runs when the line is built and again before the POST, because the
# queue is a plain text file and those get edited by hand.
secao "o que vai para a lista"
REGISTRO="$(t_lista_registro "$PROG" 2>/dev/null)"
if [ -z "$REGISTRO" ]; then
    diz "nada - este programa nao precisou de nenhum componente, entao nao ha"
    diz "licao que sirva para outra maquina. Isso e uma resposta, nao uma falha."
else
    diz "$REGISTRO"
    if t_lista_vaza "$REGISTRO" 2>/dev/null; then
        diz ""
        diz "PAREI o envio: a peneira achou algo pessoal nesta linha. Nada foi enviado."
    else
        t_envio_enfileira "$REGISTRO" 2>/dev/null &&
            diz "" &&
            diz "enfileirado para envio. Para ver a fila:  tandem enviar" ||
            diz "(nao consegui enfileirar; a linha esta acima, inteira)"
    fi
fi

secao "fim"
diz "relatorio salvo em: $RELATORIO"
printf '\nRelatorio salvo em:\n  %s\n\n' "$RELATORIO"
printf 'Se for me mandar, mande esse arquivo - ele ja foi escrito sem caminho,\n'
printf 'sem nome de usuario e sem nome de maquina.\n'
