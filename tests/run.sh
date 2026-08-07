#!/bin/bash
# Tandem - suite de testes.
#
# Roda sem Wine, sem Waydroid e sem instalar o pacote: as bibliotecas sao
# carregadas direto de src/lib e os pacotes Android sao sinteticos.
# As ferramentas opcionais (shellcheck, dpkg-deb, lintian) sao usadas
# quando existem e puladas quando nao existem, sem reprovar a suite.
#
# Uso:  bash tests/run.sh
# Saida: uma linha por teste; codigo 1 se qualquer um falhar.

# Sem "set -e": varios testes esperam comandos que falham de proposito.
cd "$(dirname -- "$0")/.." || exit 1
RAIZ="$PWD"

OK=0; FALHOU=0; PULOU=0
FALHAS=()

passou()  { OK=$((OK+1));       printf '  ok   %s\n' "$1"; }
falhou()  { FALHOU=$((FALHOU+1)); FALHAS+=("$1"); printf '  FALHOU %s\n     esperado: %s\n     obtido:   %s\n' "$1" "$2" "$3"; }
pulou()   { PULOU=$((PULOU+1)); printf '  --   %s (%s)\n' "$1" "$2"; }
secao()   { printf '\n== %s ==\n' "$1"; }

# igual <nome> <esperado> <obtido>
igual() {
    if [ "$2" = "$3" ]; then passou "$1"; else falhou "$1" "$2" "$3"; fi
}

# Ambiente isolado: nada aqui pode tocar o HOME de quem roda os testes.
TMPRAIZ="$(mktemp -d)"
trap 'rm -rf -- "$TMPRAIZ"' EXIT
export HOME="$TMPRAIZ/casa"
mkdir -p "$HOME"
# Sem sessao grafica: e assim que os testes verificam o caminho de terminal.
unset DISPLAY WAYLAND_DISPLAY

ARTEFATOS="$TMPRAIZ/artefatos"
python3 tests/mkapk.py "$ARTEFATOS" >/dev/null || { echo "nao consegui gerar os artefatos"; exit 1; }

# shellcheck source=../src/lib/common.sh
. "$RAIZ/src/lib/common.sh"
# shellcheck source=../src/lib/winedeps.sh
. "$RAIZ/src/lib/winedeps.sh"

# ---------------------------------------------------------------- sintaxe

secao "sintaxe dos scripts"
for f in src/bin/* src/lib/*.sh debian/postinst debian/postrm; do
    if bash -n "$f" 2>/dev/null; then passou "bash -n $f"
    else falhou "bash -n $f" "sintaxe valida" "erro de sintaxe"; fi
done

if command -v shellcheck >/dev/null 2>&1; then
    saida="$(LC_ALL=C.UTF-8 shellcheck --shell=bash --exclude=SC1091 \
             --severity=warning --format=gcc \
             src/bin/* src/lib/*.sh debian/postinst debian/postrm 2>&1)"
    if [ -z "$saida" ]; then passou "shellcheck sem avisos"
    else falhou "shellcheck sem avisos" "(nada)" "$saida"; fi
else
    pulou "shellcheck" "nao instalado"
fi

# ------------------------------------------------------ deteccao de DLL

secao "deteccao de dependencias do Wine"

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

igual "tres DLLs do VC++ viram um unico verbo" \
      "d3dx9 dotnet48 vcrun2022" \
      "$(t_verbos_do_log "$LOG_WINE" | tr '\n' ' ' | sed 's/ $//')"

igual "DLL que o proprio Wine implementa e ignorada" \
      "" \
      "$(t_verbos_do_log "$LOG_WINE" | grep -c kernel32 | sed 's/^0$//')"

igual "DLL do proprio programa nao vira dependencia do sistema" \
      "MinhaLibPropria.dll" \
      "$(t_dlls_sem_traducao "$LOG_WINE")"

igual "log inexistente nao quebra" "" "$(t_verbos_do_log /nao/existe)"
igual "log vazio nao produz verbo" "" "$(: > "$TMPRAIZ/v.log"; t_verbos_do_log "$TMPRAIZ/v.log")"

igual "nome amigavel traduz o verbo" \
      "Visual C++ 2015-2022" "$(t_verbo_amigavel vcrun2022)"
igual "verbo desconhecido aparece como esta" \
      "coisanova" "$(t_verbo_amigavel coisanova)"

# minusculas e maiusculas nao podem mudar o resultado
igual "traducao e insensivel a caixa" \
      "vcrun2022 vcrun2022" \
      "$(t_dll_para_verbo MSVCP140.DLL) $(t_dll_para_verbo msvcp140.dll)"

# --------------------------------------------------------- leitura de PE

secao "arquitetura de executavel PE"
igual "PE de 32 bits"  "32"    "$(t_pe_arch "$ARTEFATOS/prog32.exe")"
igual "PE de 64 bits"  "64"    "$(t_pe_arch "$ARTEFATOS/prog64.exe")"
igual "PE de ARM64"    "arm64" "$(t_pe_arch "$ARTEFATOS/progarm.exe")"
t_pe_arch "$ARTEFATOS/naoexe.exe" >/dev/null 2>&1
igual "arquivo que nao e PE falha" "1" "$?"
t_pe_arch /nao/existe >/dev/null 2>&1
igual "arquivo inexistente falha" "1" "$?"

# ------------------------------------------------------ prefixos Wine

secao "protecao de prefixos Wine"

PREF_NOSSO="$HOME/.local/share/tandem/wine"
PREF_ALHEIO="$HOME/.wine-pdv"
PREF_MARCADO="$HOME/.wine-tandem"
mkdir -p "$PREF_NOSSO/drive_c" "$PREF_ALHEIO/drive_c" "$PREF_MARCADO/drive_c"
touch "$PREF_NOSSO/system.reg" "$PREF_ALHEIO/system.reg" "$PREF_MARCADO/system.reg"
: > "$PREF_MARCADO/.tandem-prefixo"

t_prefixo_protegido "$PREF_ALHEIO";  igual "prefixo de terceiro e protegido" "0" "$?"
t_prefixo_protegido "$PREF_NOSSO";   igual "prefixo padrao nao e protegido" "1" "$?"
t_prefixo_protegido "$PREF_MARCADO"; igual "prefixo com a marca nao e protegido" "1" "$?"
t_prefixo_protegido "$HOME/.wine-que-nao-existe"
igual "prefixo desconhecido e protegido" "0" "$?"

# A lista explicita do usuario tem que vencer ate a marca de propriedade.
mkdir -p "$(dirname -- "$TANDEM_PROTEGIDOS")"
printf '%s\n' "$PREF_MARCADO" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$PREF_MARCADO"
igual "tandem protect vence a marca do proprio Tandem" "0" "$?"
printf '%s\n' "$PREF_NOSSO" > "$TANDEM_PROTEGIDOS"
t_prefixo_protegido "$PREF_NOSSO"
igual "tandem protect vale para o prefixo padrao" "0" "$?"
: > "$TANDEM_PROTEGIDOS"

# Sobe a arvore ate achar a raiz do prefixo.
mkdir -p "$PREF_ALHEIO/drive_c/Programas/Sistema"
touch "$PREF_ALHEIO/drive_c/Programas/Sistema/pdv.exe"
igual "acha a raiz do prefixo pelo caminho do arquivo" \
      "$PREF_ALHEIO" \
      "$(t_prefixo_do_arquivo "$PREF_ALHEIO/drive_c/Programas/Sistema/pdv.exe")"
t_prefixo_do_arquivo "$TMPRAIZ/solto.exe" >/dev/null 2>&1
igual "arquivo fora de qualquer prefixo falha" "1" "$?"

secao "varredura da primeira execucao"

# O cenario que falhou na maquina real: dois prefixos em ~/.wine* e a lista
# de protegidos vazia porque o postinst nao descobriu quem tinha instalado.
: > "$TANDEM_PROTEGIDOS"
PREF_FUNDO="$HOME/Programas/PDV/prefixo"
mkdir -p "$PREF_FUNDO/drive_c"
touch "$PREF_FUNDO/system.reg"

t_procura_prefixos

for esperado in "$PREF_ALHEIO" "$PREF_FUNDO"; do
    if grep -qxF -- "$esperado" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
        passou "a varredura achou $esperado"
    else
        falhou "a varredura achou $esperado" "na lista" "ausente"
    fi
done

if grep -qxF -- "$PREF_NOSSO" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    falhou "a varredura ignora o prefixo padrao do Tandem" "ausente" "na lista"
else
    passou "a varredura ignora o prefixo padrao do Tandem"
fi
if grep -qxF -- "$PREF_MARCADO" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    falhou "a varredura ignora prefixo com a marca do Tandem" "ausente" "na lista"
else
    passou "a varredura ignora prefixo com a marca do Tandem"
fi

# Diretorio com system.reg mas sem drive_c nao e prefixo Wine.
mkdir -p "$HOME/naoprefixo"; touch "$HOME/naoprefixo/system.reg"
t_procura_prefixos
if grep -qxF -- "$HOME/naoprefixo" "$TANDEM_PROTEGIDOS" 2>/dev/null; then
    falhou "system.reg sem drive_c nao conta como prefixo" "ausente" "na lista"
else
    passou "system.reg sem drive_c nao conta como prefixo"
fi

t_procura_prefixos
igual "rodar duas vezes nao duplica a lista" \
      "0" "$(sort "$TANDEM_PROTEGIDOS" | uniq -d | wc -l)"

t_protege "$PREF_ALHEIO"; igual "t_protege e idempotente" "0" "$?"
t_protege "/caminho/que/nao/existe"; igual "t_protege recusa caminho invalido" "1" "$?"

# A marca de primeira vez tem que impedir a repeticao.
MARCA_PV="$(dirname -- "$TANDEM_PROTEGIDOS")/.primeira-vez"
rm -f "$MARCA_PV"
t_primeira_vez
igual "a primeira execucao deixa a marca" "0" "$([ -f "$MARCA_PV" ]; echo $?)"
: > "$TANDEM_PROTEGIDOS"
t_primeira_vez
igual "a segunda execucao nao varre de novo" "0" "$(wc -l < "$TANDEM_PROTEGIDOS")"
rm -f "$MARCA_PV"; : > "$TANDEM_PROTEGIDOS"

# ------------------------------------------------------------ mensagens

secao "nenhuma mensagem se perde"

t_tem_gui; igual "sem DISPLAY nao ha interface grafica" "1" "$?"

t_log_init teste "suite"
igual "erro sem interface grafica sai no terminal" \
      "Tandem: deu ruim" \
      "$(t_erro "deu ruim" 2>&1 1>/dev/null)"
igual "aviso sem interface grafica sai no terminal" \
      "Tandem: atencao" \
      "$(t_aviso "atencao" 2>&1 1>/dev/null)"
igual "sucesso sem interface grafica sai no terminal" \
      "Tandem: pronto" \
      "$(t_ok "pronto" 2>&1 1>/dev/null)"

t_erro "mensagem que precisa ficar registrada" >/dev/null 2>&1
if grep -q "ERRO: mensagem que precisa ficar registrada" "$LOG" 2>/dev/null; then
    passou "erro fica registrado no log para o pos-morte"
else
    falhou "erro fica registrado no log para o pos-morte" "linha no log" "ausente"
fi

t_pergunta "posso?" >/dev/null 2>&1
igual "pergunta sem interface grafica devolve nao" "1" "$?"

igual "texto longo cai na saida padrao sem interface grafica" \
      "linha um" "$(printf 'linha um\n' | t_texto 'titulo')"

# Com interface grafica, cano e arquivo continuam recebendo o texto: quem
# escreve "tandem doctor > relatorio.txt" quer o relatorio, nao uma janela.
igual "com display, o cano ainda recebe o texto" \
      "conteudo" \
      "$(DISPLAY=:0 bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf "conteudo\n" | t_texto t' | cat)"
DISPLAY=:0 bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf "conteudo\n" | t_texto t' > "$TMPRAIZ/redir.txt"
igual "com display, o arquivo ainda recebe o texto" \
      "conteudo" "$(cat "$TMPRAIZ/redir.txt")"

# printf do diagnostico nao pode interpretar % vindo de um caminho
igual "porcento em texto nao quebra a saida" \
      "50% pronto" "$(printf '%b' "50% pronto")"

secao "a barra de progresso nao pode matar o Tandem"

# Achado do painel, confirmado: com o cano aberto so para escrita, fechar a
# janela de progresso mandava SIGPIPE e matava o processo inteiro - saida
# 141, nada no log, nenhuma janela. Dentro do laco do winetricks isso cortava
# uma instalacao de dependencia pela metade.
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
igual "o script sobrevive a janela de progresso fechada" "0" "$rc_prog"
igual "  e chega ate o fim" "VIVO" "$saida_prog"
if grep -q 'janela de progresso fechada' "$TANDEM_ESTADO/progteste.log" 2>/dev/null; then
    passou "  e registra no log que a janela sumiu"
else
    falhou "  e registra no log que a janela sumiu" "linha no log" "ausente"
fi

secao "travas: nao poder criar nao e o mesmo que estar tomada"

igual "as travas ficam no diretorio de execucao quando ele existe" \
      "$TMPRAIZ/run/tandem" \
      "$(XDG_RUNTIME_DIR="$TMPRAIZ/run" bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf %s "$TANDEM_TRAVAS"')"
igual "sem diretorio de execucao, cai para a pasta de estado" \
      "$TANDEM_ESTADO" \
      "$(env -u XDG_RUNTIME_DIR bash -c '. "'"$RAIZ"'/src/lib/common.sh"; printf %s "$TANDEM_TRAVAS"')"

# O bash NAO aborta quando um "exec N>" falha: sem distinguir os dois casos,
# uma pasta pessoal cheia virava "este programa ja esta abrindo" e exit 0.
igual "exec com caminho invalido falha sem derrubar o script" \
      "seguiu" \
      "$(bash -c 'if exec 7> /nao/existe/x.lock; then echo travou; else echo seguiu; fi' 2>/dev/null)"

secao "atalhos de menu depois de um instalador"

APPS="$HOME/.local/share/applications/wine/Programs/Coisa"
mkdir -p "$APPS"
ANTES_AT="$(t_atalhos_wine)"
igual "sem atalho nenhum, a lista vem vazia" "" "$ANTES_AT"

igual "nada novo, nada anunciado" \
      "" "$(t_anuncia_atalhos "$ANTES_AT" 2>&1 1>/dev/null)"

: > "$APPS/Coisa Legal.desktop"
saida_at="$(t_anuncia_atalhos "$ANTES_AT" 2>&1 1>/dev/null)"
case "$saida_at" in
    *"Coisa Legal"*) passou "atalho novo é anunciado pelo nome" ;;
    *) falhou "atalho novo é anunciado pelo nome" "cita 'Coisa Legal'" "$saida_at" ;;
esac

# Depois de anunciado, a mesma lista de antes nao pode anunciar de novo:
# a comparacao tem que ser contra o estado corrente.
DEPOIS_AT="$(t_atalhos_wine)"
igual "atalho ja conhecido nao e reanunciado" \
      "" "$(t_anuncia_atalhos "$DEPOIS_AT" 2>&1 1>/dev/null)"

secao "programas instalados e desinstalacao"

# O registro de um prefixo real, resumido: uma entrada na visao nativa, uma
# na visao de 32 bits (Wow6432Node - o caso do 7-Zip da maquina real), um
# componente de sistema que nao pode aparecer, e lixo sem desinstalador.
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

igual "le as DUAS visoes do registro (nativa e 32 bits)" \
      "7-Zip 24.09 (x64) Programa MSI 1.0" \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '{print $2}' | sort | tr '\n' ' ' | sed 's/ $//')"

igual "componente de sistema fica de fora" \
      "" "$(t_uninstall_dump "$PREF_NOSSO" | grep -c Oculto | sed 's/^0$//')"

igual "entrada sem desinstalador fica de fora" \
      "" "$(t_uninstall_dump "$PREF_NOSSO" | grep -c SemNada | sed 's/^0$//')"

igual "extrai o desinstalador silencioso com aspas e caminho real" \
      '"C:\Program Files\7-Zip\Uninstall.exe" /S' \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '$1=="7-Zip"{print $3}')"

igual "extrai a chave que identifica o programa" \
      "{GUID-MSI}" \
      "$(t_uninstall_dump "$PREF_NOSSO" | awk -F'\\|\\|\\|' '$2=="Programa MSI 1.0"{print $1}')"

igual "t_programas_instalados mantem o formato chave|||nome" \
      "7-Zip|||7-Zip 24.09 (x64)" \
      "$(t_programas_instalados "$PREF_NOSSO" | grep '^7-Zip')"

# O separador de comando do Windows: caminho entre aspas + argumento.
FALSO="$TMPRAIZ/bin"; mkdir -p "$FALSO"
cat > "$FALSO/wine" <<'FIM'
#!/bin/sh
printf '%s\n' "exe=$1" "args=$*"
FIM
chmod +x "$FALSO/wine"
PATH="$FALSO:$PATH"

igual "executa desinstalador com caminho entre aspas" \
      'exe=C:\Program Files\7-Zip\Uninstall.exe' \
      "$(t_executa_comando_windows '"C:\Program Files\7-Zip\Uninstall.exe" /S' | head -1)"
igual "  e repassa os argumentos" \
      'args=C:\Program Files\7-Zip\Uninstall.exe /S' \
      "$(t_executa_comando_windows '"C:\Program Files\7-Zip\Uninstall.exe" /S' | tail -1)"
igual "executa comando sem aspas (MsiExec)" \
      'exe=MsiExec.exe' \
      "$(t_executa_comando_windows 'MsiExec.exe /X{GUID-MSI}' | head -1)"

secao "preparar: o Tandem instala o que falta"

# Numa PATH pelada, tudo falta.
faltas="$(PATH=/usr/bin:/bin t_pecas_faltando | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')"
case "$faltas" in
    *wine*waydroid*) passou "detecta o que falta (achou: $faltas)" ;;
    *) falhou "detecta o que falta" "wine ... waydroid" "$faltas" ;;
esac

script="$(t_script_instalacao wine wine32 waydroid)"
case "$script" in
    *"apt-get install -y wine winetricks"*) passou "o plano instala wine e winetricks juntos" ;;
    *) falhou "o plano instala wine e winetricks juntos" "apt-get install -y wine winetricks" "$script" ;;
esac
case "$script" in
    *"dpkg --add-architecture i386"*) passou "o plano habilita 32 bits antes do wine32" ;;
    *) falhou "o plano habilita 32 bits antes do wine32" "dpkg --add-architecture i386" "(ausente)" ;;
esac
case "$script" in
    *"repo.waydro.id"*signed-by*) passou "o waydroid vem do repositorio oficial com chave" ;;
    *) falhou "o waydroid vem do repositorio oficial com chave" "repo.waydro.id + signed-by" "(ausente)" ;;
esac
case "$script" in
    *"waydroid init"*) passou "o plano inicializa o Android depois de instalar" ;;
    *) falhou "o plano inicializa o Android depois de instalar" "waydroid init" "(ausente)" ;;
esac

# t_como_root: somos root nos testes? entao executa direto.
if [ "$(id -u)" = 0 ]; then
    igual "como root, executa direto sem pedir senha" \
          "funcionou" "$(t_como_root 'echo funcionou')"
else
    pulou "como root executa direto" "suite rodando sem root"
fi

# Atalhos: so os do nosso prefixo, e orfao e o que perdeu o .lnk.
WP="$HOME/.local/share/applications/wine/Programs"
mkdir -p "$WP/7-Zip" "$WP/Alheio"
printf '[Desktop Entry]\nName=7-Zip File Manager\nExec=env WINEPREFIX="%s" wine x\n' \
       "$PREF_NOSSO" > "$WP/7-Zip/7-Zip File Manager.desktop"
printf '[Desktop Entry]\nName=Coisa Alheia\nExec=env WINEPREFIX="%s" wine x\n' \
       "$PREF_ALHEIO" > "$WP/Alheio/Coisa Alheia.desktop"

igual "lista so os atalhos do nosso prefixo" \
      "1" "$(t_atalhos_nossos | wc -l)"
igual "le o nome amigavel do atalho" \
      "7-Zip File Manager" "$(t_nome_do_atalho "$WP/7-Zip/7-Zip File Manager.desktop")"

# Com o .lnk presente, o atalho e valido e nao pode ser removido.
LNKDIR="$PREF_NOSSO/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/7-Zip"
mkdir -p "$LNKDIR"; : > "$LNKDIR/7-Zip File Manager.lnk"
igual "atalho com programa instalado nao e removido" "0" "$(t_limpa_atalhos_orfaos)"
igual "  e continua no disco" \
      "0" "$([ -f "$WP/7-Zip/7-Zip File Manager.desktop" ]; echo $?)"

# Sem o .lnk, virou botao que nao abre nada: tem que sair.
rm -f "$LNKDIR/7-Zip File Manager.lnk"
igual "atalho orfao e removido" "1" "$(t_limpa_atalhos_orfaos)"
igual "  e sumiu do disco" \
      "1" "$([ -f "$WP/7-Zip/7-Zip File Manager.desktop" ]; echo $?)"
igual "  e o atalho alheio foi preservado" \
      "0" "$([ -f "$WP/Alheio/Coisa Alheia.desktop" ]; echo $?)"

# Sem wine no PATH a lista falha sem quebrar quem chamou.
igual "sem wine, a lista degrada em silencio controlado" \
      "" "$(PATH=/nao/existe; t_programas_instalados 2>/dev/null)"

secao "arquitetura do Wine"
t_tem_wine64; r64=$?
t_tem_wine32; r32=$?
case "$r64$r32" in
    [01][01]) passou "t_tem_wine64 e t_tem_wine32 devolvem 0 ou 1" ;;
    *) falhou "t_tem_wine64 e t_tem_wine32 devolvem 0 ou 1" "0 ou 1" "$r64$r32" ;;
esac

secao "locale (o zenity recusa acento em locale inexistente)"

t_locale_existe C.UTF-8;     igual "reconhece locale existente apesar do hifen" "0" "$?"
t_locale_existe c.utf8;      igual "comparacao ignora caixa e hifen" "0" "$?"
t_locale_existe zz_ZZ.UTF-8; igual "recusa locale inexistente" "1" "$?"
t_locale_existe "";          igual "recusa locale vazio" "1" "$?"

igual "escolhe o primeiro candidato que exista" \
      "C.UTF-8" "$(t_locale_utf8 zz_ZZ.UTF-8 C.UTF-8)"
igual "cai para C.UTF-8 quando nenhum existe" \
      "C.UTF-8" "$(t_locale_utf8 zz_ZZ.UTF-8 yy_YY.UTF-8)"
igual "sem candidato algum ainda devolve algo utilizavel" \
      "C.UTF-8" "$(t_locale_utf8)"
igual "candidato vazio nao atrapalha a escolha" \
      "C.UTF-8" "$(t_locale_utf8 "" "" C.UTF-8)"

# O que importa no fim: o locale escolhido tem que produzir charmap UTF-8,
# porque e isso que decide se o zenity aceita ou recusa texto acentuado.
igual "o locale escolhido produz charmap UTF-8" \
      "UTF-8" "$(LC_ALL="$(t_locale_utf8 zz_ZZ.UTF-8)" locale charmap 2>/dev/null)"

# -------------------------------------------------------------- apkinfo

secao "inspecao de pacotes Android"

campo() { python3 src/lib/apkinfo.py "$1" 2>/dev/null | grep "^$2=" | cut -d= -f2-; }

igual "apk simples: formato"      "apk"                   "$(campo "$ARTEFATOS/universal.apk" FORMATO)"
igual "apk simples: pacote"       "com.exemplo.universal" "$(campo "$ARTEFATOS/universal.apk" PACOTE)"
igual "apk simples: sdk minimo"   "21"                    "$(campo "$ARTEFATOS/universal.apk" MINSDK)"
igual "apk universal: sem ABI"    ""                      "$(campo "$ARTEFATOS/universal.apk" ABIS)"

igual "apk x86: ABIs"             "x86,x86_64"            "$(campo "$ARTEFATOS/x86.apk" ABIS)"
igual "apk so ARM: ABIs"          "arm64-v8a,armeabi-v7a" "$(campo "$ARTEFATOS/armonly.apk" ABIS)"
igual "apk exigente: sdk minimo"  "99"                    "$(campo "$ARTEFATOS/futuro.apk" MINSDK)"

igual "xapk: formato"             "xapk"                  "$(campo "$ARTEFATOS/jogo.xapk" FORMATO)"
igual "xapk: pacote vem do apk base" "com.exemplo.jogo"   "$(campo "$ARTEFATOS/jogo.xapk" PACOTE)"
igual "xapk: sdk vem do apk base" "24"                    "$(campo "$ARTEFATOS/jogo.xapk" MINSDK)"
igual "xapk: conta as partes"     "2"                     "$(campo "$ARTEFATOS/jogo.xapk" SPLITS)"
igual "xapk: detecta OBB"         "1"                     "$(campo "$ARTEFATOS/jogo.xapk" OBB)"

igual "apks: formato"             "apks"                  "$(campo "$ARTEFATOS/app.apks" FORMATO)"
igual "apks: conta as partes"     "3"                     "$(campo "$ARTEFATOS/app.apks" SPLITS)"
igual "apks: sem OBB"             "0"                     "$(campo "$ARTEFATOS/app.apks" OBB)"

igual "arquivo corrompido degrada com mensagem" \
      "arquivo corrompido ou nao e um pacote Android" \
      "$(campo "$ARTEFATOS/corrompido.apk" ERRO)"
igual "arquivo vazio degrada com mensagem" \
      "arquivo corrompido ou nao e um pacote Android" \
      "$(campo "$ARTEFATOS/vazio.apk" ERRO)"
igual "arquivo inexistente degrada com mensagem" \
      "arquivo nao encontrado" \
      "$(campo /nao/existe.apk ERRO)"

python3 src/lib/apkinfo.py >/dev/null 2>&1
igual "sem argumento devolve erro de uso" "2" "$?"

# ------------------------------------------------------------- pacote

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
                       usr/share/polkit-1/rules.d/49-tandem.rules; do
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
