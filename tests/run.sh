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

# A suite testa o REPOSITORIO, nunca o pacote instalado. Sem isto as
# bibliotecas resolviam para /usr/lib/tandem quando o Tandem estava
# instalado na maquina, e a suite passava a conferir a versao antiga - um
# teste que aprova o codigo errado e pior que teste nenhum.
export TANDEM_LIB="$RAIZ/src/lib"
export TANDEM_VERBOS_TSV="$RAIZ/src/lib/verbos.tsv"
export TANDEM_LIMITES="$RAIZ/src/lib/limites.tsv"
export TANDEM_ALTERNATIVAS="$RAIZ/src/lib/alternativas.tsv"

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

# A ATL vem do runtime do Visual C++, nao do atmlib (Adobe Type Manager).
# O erro instalava a coisa errada, gravava recibo, e na volta o Tandem dizia
# "ja instalei o que este programa pedia" e desistia.
igual "os seis mapeamentos que o auditor corrigiu" \
      "amstream d3dcompiler_46 wmp11 xinput vcrun2003 vcrun2019" \
      "$(for d in amstream.dll d3dcompiler_46.dll wmasf.dll xinput1_3.dll msvcr71.dll atl140.dll; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d)"; done | sed 's/ $//')"
# E os vizinhos que estavam CERTOS nao podem ter sido levados junto.
igual "os vizinhos corretos continuam intactos" \
      "quartz wmp9 xact d3dcompiler_47" \
      "$(for d in quartz.dll wmvcore.dll xaudio2_7.dll d3dcompiler_47.dll; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d)"; done | sed 's/ $//')"

igual "atl vem do Visual C++ do mesmo ano, nao do Adobe Type Manager" \
      "vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013 vcrun2019" \
      "$(for d in atl80 atl90 atl100 atl110 atl120 atl140; do
             printf '%s ' "$(t_dll_para_verbo_tabela $d.dll)"; done | sed 's/ $//')"

secao "indice gerado do winetricks (segunda opiniao)"

igual "a tabela a mao tem precedencia sobre o indice" \
      "vcrun2022 dotnet48" \
      "$(t_dll_para_verbo msvcp140.dll) $(t_dll_para_verbo mscoree.dll)"

if [ -f "$RAIZ/src/lib/verbos.tsv" ]; then
    n_ind="$(grep -vc '^#' "$RAIZ/src/lib/verbos.tsv")"
    if [ "$n_ind" -gt 150 ]; then
        passou "o indice cobre $n_ind DLLs"
    else
        falhou "o indice cobre mais de 150 DLLs" ">150" "$n_ind"
    fi
    igual "o indice responde por DLL que a tabela a mao nao conhece" \
          "dsound" "$(t_dll_para_verbo dsound.dll)"
    igual "DLL fora das duas continua sem traducao" \
          "" "$(t_dll_para_verbo MinhaLibPropria.dll)"
    # O desempate tem que entender versao com ponto omitido: dotnet48 e 4.8,
    # dotnet472 e 4.7.2. Comparar como inteiro daria 472 > 48.
    igual "o desempate do indice escolhe a versao mais nova" \
          "dotnet48" \
          "$(grep -m1 '^mscoree\.dll' "$RAIZ/src/lib/verbos.tsv" | cut -f2)"
else
    pulou "indice do winetricks" "verbos.tsv ausente"
fi

# AUDITOR. Em vez de o indice responder no lugar da tabela, ele CONFERE a
# tabela: para cada DLL que os dois conhecem, o verbo prometido a mao tem que
# estar entre os que o winetricks diz que entregam aquela DLL. Este teste
# sozinho encontrou seis erros de mapeamento - atl->atmlib (Adobe Type
# Manager!), msvcr71->vcrun6, amstream->quartz, d3dcompiler_46->_47,
# wmasf->wmp9 e xinput->xact - cada um deles instalando a coisa errada e
# gravando recibo, o que fazia o Tandem desistir na tentativa seguinte.
#
# Divergencias DELIBERADAS ficam declaradas aqui, com o motivo. Sem esta
# lista so restavam duas saidas ruins: apagar o teste (e perder o auditor) ou
# ceder e trocar por uma traducao pior. Com ela, a divergencia conhecida passa
# e qualquer divergencia NOVA continua reprovando.
#
#   mfc42.dll: o indice so conhece o vcrun6, porque o verbo "mfc42" declara a
#   DLL no titulo em prosa ("...mfc42 library; part of vcrun6"), sem lista
#   entre parenteses para o gerador ler. Escolher o vcrun6 instalaria o
#   runtime inteiro do Visual C++ 6 para entregar um arquivo que o verbo
#   estreito extrai sozinho com cabextract.
EXCECOES_AUDITOR="mfc42.dll"

if [ -f "$RAIZ/src/lib/verbos.tsv" ]; then
    suspeitos=""
    # A quinta coluna (fonte: override/titulo/ambos) precisa ser lida, senao
    # o "read" joga ela dentro de a_todos e a comparacao de pertinencia falha
    # para TODA linha - o auditor passa a acusar as 108 traducoes certas.
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
        passou "a tabela a mao so promete verbo que o winetricks confirma"
    else
        falhou "a tabela a mao so promete verbo que o winetricks confirma" \
               "(nenhum suspeito)" "$suspeitos"
    fi
fi

if command -v winetricks >/dev/null 2>&1; then
    if python3 tools/indice-winetricks.py --conferir >/dev/null 2>&1; then
        passou "o indice em disco bate com o winetricks instalado"
    else
        pulou "indice em disco x winetricks instalado" "versoes diferentes do winetricks"
    fi
else
    pulou "regerar o indice" "winetricks nao instalado"
fi

secao "alternativas de Linux"

igual "reconhece programa que TEM versao oficial para Linux" \
      "nativo" "$(t_alternativas_para teamviewer | head -1 | cut -d'|' -f1)"
igual "reconhece programa que so tem parecido" \
      "parecido" "$(t_alternativas_para photoshop | head -1 | cut -d'|' -f1)"
igual "a busca ignora maiuscula, espaco e hifen" \
      "nativo nativo nativo" \
      "$(for n in TeamViewer 'team viewer' team-viewer; do
             printf '%s ' "$(t_alternativas_para "$n" | head -1 | cut -d"|" -f1)"; done | sed 's/ $//')"
t_alternativas_para "programa-que-ninguem-conhece" >/dev/null 2>&1
igual "programa desconhecido falha sem inventar" "1" "$?"
t_alternativas_para "" >/dev/null 2>&1
igual "nome vazio falha sem quebrar" "1" "$?"

# A diferenca entre "nativo" e "parecido" e o coracao da honestidade aqui:
# dizer que o GIMP e o Photoshop seria enganar o dono.
texto_alt="$(t_texto_alternativas photoshop)"
case "$texto_alt" in
    *"faz um trabalho parecido"*"Atenção:"*) passou "alternativa parecida vem com a ressalva" ;;
    *) falhou "alternativa parecida vem com a ressalva" "faz um trabalho parecido + Atenção" "$texto_alt" ;;
esac
texto_nat="$(t_texto_alternativas teamviewer)"
case "$texto_nat" in
    *"feito para Linux"*) passou "alternativa nativa e apresentada como o mesmo programa" ;;
    *) falhou "alternativa nativa e apresentada como o mesmo programa" "feito para Linux" "$texto_nat" ;;
esac

# Toda linha da tabela precisa das cinco colunas: uma linha malformada
# apareceria como sugestao vazia na cara do dono.
malformadas="$(awk -F"\t" '!/^#/ && NF>0 && (NF!=5 || $3=="")' "$TANDEM_ALTERNATIVAS" | wc -l)"
igual "toda linha da tabela tem as cinco colunas" "0" "$malformadas"

secao "memoria: o que o Tandem aprende"

MEM_A="$ARTEFATOS/imports64.exe"
MEM_B="$ARTEFATOS/importslimpo.exe"

id_a="$(t_memoria_id "$MEM_A")"
igual "a identidade tem tamanho fixo" "32" "${#id_a}"
igual "o mesmo arquivo tem sempre a mesma identidade" \
      "$id_a" "$(t_memoria_id "$MEM_A")"
if [ "$id_a" = "$(t_memoria_id "$MEM_B")" ]; then
    falhou "arquivos diferentes tem identidades diferentes" "diferentes" "iguais"
else
    passou "arquivos diferentes tem identidades diferentes"
fi
# A identidade segue o ARQUIVO, nao o caminho: uma receita aprendida aqui
# tem que valer depois que o dono mover o programa de pasta.
cp "$MEM_A" "$TMPRAIZ/mudou-de-pasta.exe"
igual "a identidade sobrevive a mudanca de pasta e de nome" \
      "$id_a" "$(t_memoria_id "$TMPRAIZ/mudou-de-pasta.exe")"
t_memoria_id /nao/existe >/dev/null 2>&1
igual "arquivo inexistente nao tem identidade" "1" "$?"

t_memoria_grava "$MEM_A" RESULTADO abriu
igual "grava e le de volta" "abriu" "$(t_memoria_le "$MEM_A" RESULTADO)"
t_memoria_grava "$MEM_A" RESULTADO "nao abriu"
igual "gravar de novo substitui, nao duplica" \
      "nao abriu" "$(t_memoria_le "$MEM_A" RESULTADO)"
igual "  e sobrou uma linha so" \
      "1" "$(grep -c '^RESULTADO=' "$(t_memoria_arquivo "$MEM_A")")"

t_memoria_junta "$MEM_A" RESOLVERAM vcrun2022
t_memoria_junta "$MEM_A" RESOLVERAM d3dx9
t_memoria_junta "$MEM_A" RESOLVERAM vcrun2022
igual "a lista acumula sem repetir" \
      "vcrun2022 d3dx9" "$(t_memoria_le "$MEM_A" RESOLVERAM)"

igual "o arquivo guarda o nome do programa, para o dono reconhecer" \
      "imports64.exe" "$(t_memoria_le "$MEM_A" PROGRAMA)"
if grep -q '^#' "$(t_memoria_arquivo "$MEM_A")"; then
    passou "o arquivo se explica em texto legivel"
else
    falhou "o arquivo se explica em texto legivel" "cabecalho com #" "ausente"
fi

# Memoria de um programa nao pode vazar para outro.
igual "cada programa tem a sua memoria" "" "$(t_memoria_le "$MEM_B" RESOLVERAM 2>/dev/null)"

secao "portao de evidencia (proofgate)"

if [ -f "$RAIZ/proofgate.json" ]; then
    passou "o repositorio declara a propria stack para o portao"
    # Sem isto o portao passa verde sem rodar teste nenhum: a deteccao
    # automatica so conhece ecossistemas com manifesto, e shell nao tem.
    if grep -q '"test": *"bash tests/run.sh"' "$RAIZ/proofgate.json"; then
        passou "o portao sabe rodar a suite deste projeto"
    else
        falhou "o portao sabe rodar a suite deste projeto" "commands.test" "ausente"
    fi
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$RAIZ/proofgate.json" 2>/dev/null; then
        passou "proofgate.json e JSON valido"
    else
        falhou "proofgate.json e JSON valido" "JSON" "malformado"
    fi
else
    pulou "portao de evidencia" "proofgate.json ausente"
fi

# O acoplamento declarado no portao tem que ser verdade: todo comando que o
# programa oferece precisa estar no manual, senao o pacote documenta uma
# coisa e faz outra.
# A lista de comandos e EXTRAIDA do case principal, nunca escrita a mao: com
# lista fixa o teste passava verde enquanto quatro comandos novos (dados,
# lista, contribuir, socorro) nao estavam em documento nenhum. Um teste que
# so cobre o que alguem lembrou de adicionar nao cobre nada.
#
# So o PRIMEIRO nome de cada linha do case e cobrado. Os apelidos
# (uninstall, diagnostico, meus-dados...) sao superficie deliberadamente nao
# documentada; exigir documentacao deles encheria o manual de sinonimo.
COMANDOS="$(sed -n '/^case /,/^esac$/p' "$RAIZ/src/bin/tandem" |
            sed -n 's/^    \([^ )]*\)).*/\1/p' | sed 's/|.*//' |
            grep -vxF -e '""' -e painel -e --primeira-vez -e version \
                     -e help -e '*' -e '' | sort -u)"
n_cmd="$(printf '%s\n' "$COMANDOS" | grep -c .)"
if [ "$n_cmd" -ge 15 ]; then passou "extraiu $n_cmd comandos do case principal"
else falhou "extraiu os comandos do case principal" ">=15" "$n_cmd"; fi

for onde in man/tandem.1 README.md LEIAME.md; do
    faltando=""
    for c in $COMANDOS; do
        grep -q "tandem $c" "$RAIZ/$onde" || faltando="$faltando $c"
    done
    igual "todo comando aparece em $onde" "" "$faltando"
done

# E o contrario: o manual nao pode prometer comando que nao existe.
promete_demais=""
for c in $(grep -oE '^\.BI? "?tandem ([a-z]+)' "$RAIZ/man/tandem.1" |
           awk '{print $NF}' | tr -d '"' | sort -u); do
    grep -q "^  tandem $c\b\|^    $c|" "$RAIZ/src/bin/tandem" ||
        grep -qE "^    $c\||^    $c\)" "$RAIZ/src/bin/tandem" ||
        promete_demais="$promete_demais $c"
done
igual "o manual nao promete comando inexistente" "" "$promete_demais"

secao "receitas: conhecimento coletivo sem servidor"

t_memoria_grava "$MEM_A" RESULTADO abriu
t_memoria_grava "$MEM_A" RESOLVERAM "vcrun2022 msxml6"
REC="$TMPRAIZ/receita.txt"
t_receita_exporta "$MEM_A" > "$REC"

if grep -q '^TANDEM_RECEITA=1$' "$REC" && grep -q '^IDENTIDADE=' "$REC"; then
    passou "a receita se declara e carrega a identidade do programa"
else
    falhou "a receita se declara e carrega a identidade do programa" \
           "TANDEM_RECEITA + IDENTIDADE" "$(cat "$REC")"
fi
if grep -q '^#.*mandar para outra pessoa' "$REC"; then
    passou "a receita se explica para quem receber"
else
    falhou "a receita se explica para quem receber" "cabecalho explicativo" "ausente"
fi

t_memoria_esquece "$MEM_A" 2>/dev/null
t_receita_importa "$REC" "$MEM_A"
igual "receita legitima e aceita" "0" "$?"
igual "  e vira memoria" "vcrun2022 msxml6" "$(t_memoria_le "$MEM_A" RESOLVERAM)"

# Uma receita e do ARQUIVO, nao do nome. Aplicar a de outro programa
# ensinaria a licao errada, e ninguem perceberia.
t_receita_importa "$REC" "$MEM_B" 2>/dev/null
igual "receita de outro programa e recusada" "3" "$?"
igual "  e nao contamina a memoria do outro" "" "$(t_memoria_le "$MEM_B" RESOLVERAM 2>/dev/null)"

# A defesa que mais importa: o verbo de uma receita vira argumento de
# "winetricks -q". Uma receita vinda de fora nao pode carregar comando.
for veneno in 'vcrun2022 ;curl|sh' 'a$(rm -rf /)' '../../etc/passwd' 'a b`id`' 'a/b' 'a b c;d'; do
    # Montado com grep+printf, nao com sed: o proprio veneno tem | e $ e
    # quebraria o delimitador do sed antes de chegar ao codigo testado.
    { grep -v '^RESOLVERAM=' "$REC"; printf 'RESOLVERAM=%s\n' "$veneno"; } > "$TMPRAIZ/veneno.txt"
    t_memoria_esquece "$MEM_A" 2>/dev/null
    t_receita_importa "$TMPRAIZ/veneno.txt" "$MEM_A" 2>/dev/null
    if [ "$?" = 4 ] && [ -z "$(t_memoria_le "$MEM_A" RESOLVERAM 2>/dev/null)" ]; then
        passou "recusa receita com comando embutido: $veneno"
    else
        falhou "recusa receita com comando embutido: $veneno" "codigo 4 e nada gravado" \
               "$(t_memoria_le "$MEM_A" RESOLVERAM 2>/dev/null)"
    fi
done

printf 'isto nao e receita\n' > "$TMPRAIZ/naorec.txt"
t_receita_importa "$TMPRAIZ/naorec.txt" "$MEM_A" 2>/dev/null
igual "arquivo que nao se declara receita e recusado" "2" "$?"
t_receita_importa /nao/existe "$MEM_A" 2>/dev/null
igual "receita inexistente falha sem quebrar" "1" "$?"

t_verbo_valido vcrun2022; igual "nome de verbo comum e aceito" "0" "$?"
t_verbo_valido 'a;b';      igual "nome com ponto e virgula e recusado" "1" "$?"
t_verbo_valido '';         igual "nome vazio e recusado" "1" "$?"
t_verbo_valido "$(printf 'a%.0s' $(seq 1 60))"
igual "nome absurdamente longo e recusado" "1" "$?"

t_memoria_esquece "$MEM_A" 2>/dev/null
t_memoria_grava "$MEM_A" RESULTADO abriu

t_memoria_esquece "$MEM_A"
igual "esquecer apaga de verdade" "" "$(t_memoria_le "$MEM_A" RESULTADO 2>/dev/null)"
t_memoria_esquece "$MEM_A" 2>/dev/null
igual "esquecer o que nao existe falha sem quebrar" "1" "$?"

# ------------------------------------------------------- pre-voo do PE

secao "pre-voo: ler o .exe sem executar"

pecampo() { python3 src/lib/peinfo.py "$1" 2>/dev/null | grep "^$2=" | cut -d= -f2-; }

igual "le a arquitetura de um PE de 64 bits" \
      "64" "$(pecampo "$ARTEFATOS/imports64.exe" ARQUITETURA)"
igual "le a arquitetura de um PE de 32 bits" \
      "32" "$(pecampo "$ARTEFATOS/imports32.exe" ARQUITETURA)"
igual "le a tabela de importacoes inteira" \
      "kernel32.dll,msvcp140.dll,vcruntime140.dll" \
      "$(pecampo "$ARTEFATOS/imports64.exe" DLLS)"
igual "normaliza os nomes para minusculas" \
      "hasp_windows_x64.dll,kernel32.dll" \
      "$(pecampo "$ARTEFATOS/imports32.exe" DLLS)"
igual "arquivo que nao e PE degrada com mensagem" \
      "nao comeca com MZ" "$(pecampo "$ARTEFATOS/naoexe.exe" ERRO)"
igual "arquivo inexistente degrada com mensagem" \
      "arquivo nao encontrado" "$(pecampo /nao/existe.exe ERRO)"
python3 src/lib/peinfo.py >/dev/null 2>&1
igual "sem argumento devolve erro de uso" "2" "$?"

# O que o pre-voo consegue provar sozinho: reconhecer, ANTES de rodar, um
# programa que depende de coisa que nunca vai funcionar aqui.
TANDEM_LIB="$RAIZ/src/lib" TANDEM_LIMITES="$RAIZ/src/lib/limites.tsv" \
    bash -c '. "'"$RAIZ"'/src/lib/common.sh"; t_limite_do_programa "'"$ARTEFATOS"'/imports32.exe"' \
    > "$TMPRAIZ/lim.txt" 2>/dev/null
case "$(cat "$TMPRAIZ/lim.txt")" in
    dongle\|*chave\ física*) passou "reconhece proteção por chave física antes de rodar" ;;
    *) falhou "reconhece proteção por chave física antes de rodar" \
              "dongle|...chave física..." "$(cat "$TMPRAIZ/lim.txt")" ;;
esac

TANDEM_LIB="$RAIZ/src/lib" TANDEM_LIMITES="$RAIZ/src/lib/limites.tsv" \
    bash -c '. "'"$RAIZ"'/src/lib/common.sh"; t_limite_do_programa "'"$ARTEFATOS"'/importslimpo.exe"' \
    > "$TMPRAIZ/lim2.txt" 2>/dev/null
igual "programa comum nao recebe veredito de impossibilidade" \
      "" "$(cat "$TMPRAIZ/lim2.txt")"

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

secao "tipos MIME dos pacotes divididos"

# Sem estes tipos o duplo clique num .xapk nunca chega ao Tandem: o
# freedesktop nao conhece a extensao e o sistema ve so um ZIP generico.
igual "o arquivo de tipos MIME e XML valido" "ok" \
      "$(python3 -c 'import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print("ok")' \
         src/mime/tandem.xml 2>&1 | tail -1)"

for tipo in vnd.android.xapk vnd.android.apks vnd.android.apkm; do
    if grep -q "application/$tipo" src/mime/tandem.xml; then
        passou "declara application/$tipo"
    else
        falhou "declara application/$tipo" "presente" "ausente"
    fi
    if grep -q "application/$tipo" src/applications/tandem-apk.desktop; then
        passou "  e o .desktop reivindica o tipo"
    else
        falhou "  e o .desktop reivindica o tipo" "presente" "ausente"
    fi
    if grep -q "application/$tipo" src/bin/tandem-repair; then
        passou "  e o repair reaplica o tipo"
    else
        falhou "  e o repair reaplica o tipo" "presente" "ausente"
    fi
done

# Subclasse de zip e o que faz o casamento por extensao vencer a deteccao
# por conteudo: sem isso o sistema insiste que o arquivo e um ZIP.
if grep -q 'sub-class-of.*application/zip' src/mime/tandem.xml; then
    passou "os tipos sao subclasse de application/zip"
else
    falhou "os tipos sao subclasse de application/zip" "sub-class-of zip" "ausente"
fi

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

# Numa PATH vazia nada existe, entao a lista tem que vir completa - e assim
# o teste nao depende do que esta instalado na maquina que roda a suite.
faltas="$(PATH=/nao/existe t_pecas_faltando | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')"
igual "sem nada instalado, lista tudo que falta" \
      "wine winetricks adb waydroid" "$faltas"
# E com tudo presente, a lista vem vazia.
FINGE="$TMPRAIZ/finge"; mkdir -p "$FINGE"
for c in wine winetricks adb waydroid; do printf '#!/bin/sh\n' > "$FINGE/$c"; chmod +x "$FINGE/$c"; done
igual "com tudo instalado, nao ha o que preparar" \
      "" "$(PATH="$FINGE" t_pecas_faltando | grep -v '^wine32|' )"

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

secao "nenhum comando sai mudo"

# t_texto le o CONTEUDO da entrada padrao e usa o argumento como TITULO.
# Cinco comandos novos passaram o texto como argumento e leram um stdin
# vazio: rodavam, saiam com 0 e nao imprimiam UMA LINHA. Nenhum teste pegava
# porque todos exercitavam funcoes de biblioteca, nunca o comando inteiro.
# Descoberto rodando "tandem dados" num Ubuntu de verdade.
CASA_C="$TMPRAIZ/cli"; mkdir -p "$CASA_C/.local/share/tandem/wine/drive_c/windows"
: > "$CASA_C/.local/share/tandem/wine/system.reg"
: > "$CASA_C/.local/share/tandem/wine/.tandem-prefixo"
: > "$CASA_C/.primeira-vez"
for cmd in "dados" "lista" "doctor" "--help" "version"; do
    saida="$(env -i HOME="$CASA_C" PATH="/usr/bin:/bin" TANDEM_LIB="$RAIZ/src/lib" \
             bash "$RAIZ/src/bin/tandem" $cmd 2>&1)"
    if [ -n "$saida" ]; then passou "\"tandem $cmd\" imprime alguma coisa"
    else falhou "\"tandem $cmd\" imprime alguma coisa" "qualquer texto" "zero byte"; fi
done

# E o uso errado tem que degradar, nunca sair mudo: sem nada na entrada,
# t_texto imprime pelo menos o titulo.
igual "t_texto sem conteudo imprime o titulo" \
      "Titulo qualquer" "$(t_texto "Titulo qualquer" < /dev/null)"
# A guarda contra congelar so da para exercitar onde existe terminal.
if [ -c /dev/tty ] && (exec < /dev/tty) 2>/dev/null; then
    timeout 5 bash -c '. "'"$RAIZ"'/src/lib/common.sh"; t_texto "T" < /dev/tty' >/dev/null 2>&1
    igual "t_texto com terminal na entrada nao trava" "0" "$?"
else
    pulou "t_texto com terminal na entrada" "a suite roda sem terminal de controle"
fi

secao "lista da comunidade (modelo das listas de filtro)"

PROG_L="$ARTEFATOS/prog64.exe"
ID_L="$(t_memoria_id "$PROG_L")"
export TANDEM_LISTA="$TMPRAIZ/lista.tsv"

# Sem lista baixada, nao ha o que consultar - e isso nao e erro.
rm -f "$TANDEM_LISTA"
igual "sem lista baixada, a consulta cala" "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022,dotnet48\t-\tconfirmado\t340\t2026-08\t-\n' "$ID_L"
  printf 'aaaa\t64\tvcrun2010\t-\tso-abriu\t2\t2026-07\t-\n'
} > "$TANDEM_LISTA"
igual "acha o programa pela impressao digital do arquivo" \
      "vcrun2022 dotnet48" "$(t_lista_consulta "$PROG_L")"
igual "a contagem de maquinas vem junto" "340" "$(t_lista_maquinas "$ID_L")"

# Licao sem gente confirmando NAO e espalhada. Espalhar engano e mais facil
# que espalhar acerto: erro nao da trabalho de produzir.
{
  printf '# TANDEM-LISTA 1\n'
  printf '%s\t64\tvcrun2022\t-\tso-abriu\t9\t2026-08\t-\n' "$ID_L"
} > "$TANDEM_LISTA"
igual "licao nao confirmada nao e sugerida" "" "$(t_lista_consulta "$PROG_L" 2>/dev/null)"

# O registro que sai desta maquina.
t_memoria_esquece "$PROG_L" 2>/dev/null
t_memoria_grava "$PROG_L" ARQUITETURA 64
t_memoria_junta "$PROG_L" RESOLVERAM vcrun2022
t_memoria_grava "$PROG_L" CONFIRMADO sim
REG_L="$(t_lista_registro "$PROG_L")"
igual "o registro tem os oito campos do formato" \
      "8" "$(printf '%s' "$REG_L" | awk -F'\t' '{print NF}')"
case "$REG_L" in
    "$ID_L"*) passou "o registro comeca pela identidade do arquivo" ;;
    *) falhou "o registro comeca pela identidade do arquivo" "$ID_L..." "$REG_L" ;;
esac
case "$REG_L" in
    *confirmado*) passou "o registro carrega a origem da confianca" ;;
    *) falhou "o registro carrega a origem da confianca" "confirmado" "$REG_L" ;;
esac
# O que NUNCA pode sair: caminho, usuario, maquina, IP, dia do mes.
case "$REG_L" in
    */*) falhou "o registro nao carrega caminho nenhum" "sem barra" "$REG_L" ;;
    *) passou "o registro nao carrega caminho nenhum" ;;
esac
case "$REG_L" in
    *"$(id -un)"*) falhou "o registro nao carrega o nome do usuario" "sem usuario" "$REG_L" ;;
    *) passou "o registro nao carrega o nome do usuario" ;;
esac
case "$REG_L" in
    *"$(date +%Y-%m-%d)"*) falhou "a data nao tem o dia" "so ano-mes" "$REG_L" ;;
    *) passou "a data nao tem o dia" ;;
esac
# E o guarda funciona mesmo se alguem estragar o gerador no futuro.
igual "o guarda barra um registro com caminho" \
      "0" "$(t_lista_vaza "abc	64	/home/alguem/x	-	confirmado	1	2026-08	-"; echo $?)"
igual "o guarda barra um registro com IP" \
      "0" "$(t_lista_vaza "abc	64	vcrun2022	-	confirmado	1	2026-08	192.168.0.7"; echo $?)"
igual "o guarda deixa passar um registro limpo" \
      "1" "$(t_lista_vaza "$REG_L"; echo $?)"

# O documento do formato promete que todo verbo vindo de fora e validado antes
# de virar argumento de comando. O atalho da memoria/lista gravava recibo e
# chamava o winetricks sem passar por lugar nenhum de validacao - a receita
# validava, a lista nao.
igual "verbo com caractere fora do esperado e recusado" \
      "1" "$(t_verbo_valido 'vcrun2022; rm -rf /'; echo $?)"
igual "verbo com barra e recusado" "1" "$(t_verbo_valido '../../etc/passwd'; echo $?)"
igual "verbo normal passa" "0" "$(t_verbo_valido vcrun2022; echo $?)"
case "$(grep -c 't_verbo_valido' "$RAIZ/src/bin/tandem-exe")" in
    0) falhou "o atalho da lista valida o verbo antes de usar" "t_verbo_valido" "ausente" ;;
    *) passou "o atalho da lista valida o verbo antes de usar" ;;
esac
# E a prova de entrega tambem vale nesse atalho: era o unico caminho que
# gravava recibo so com o codigo de saida.
case "$(grep -c 't_dll_no_prefixo' "$RAIZ/src/bin/tandem-exe")" in
    0|1) falhou "a prova de entrega cobre tambem o atalho da memoria" \
                "dois usos de t_dll_no_prefixo" "menos que isso" ;;
    *) passou "a prova de entrega cobre tambem o atalho da memoria" ;;
esac

# Programa sem licao nenhuma nao vira ruido na lista dos outros.
t_memoria_esquece "$PROG_L" 2>/dev/null
t_lista_registro "$PROG_L" >/dev/null 2>&1
igual "sem licao, nao ha o que contribuir" "1" "$?"

# Arquivo que nao se declara como lista NAO substitui o bom que ja esta em
# disco. Uma lista quebrada calaria a segunda opiniao sem ninguem perceber -
# e "parou de sugerir" e o tipo de defeito que ninguem nota.
printf '# TANDEM-LISTA 1\nboa\t64\tx\t-\tconfirmado\t1\t2026-08\t-\n' > "$TANDEM_LISTA"
printf 'nao sou uma lista do Tandem\n' > "$TMPRAIZ/intruso.txt"
if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    TANDEM_LISTA_URL="file://$TMPRAIZ/intruso.txt" t_lista_atualiza >/dev/null 2>&1
    igual "arquivo sem cabecalho valido e recusado" "3" "$?"
    igual "  e a lista boa continua em disco" "1" "$(grep -c '^boa' "$TANDEM_LISTA")"
    igual "  sem deixar o intruso entrar" "0" "$(grep -c 'nao sou uma lista' "$TANDEM_LISTA")"
    # E o caminho feliz: um arquivo bem formado substitui.
    printf '# TANDEM-LISTA 1\nnova\t64\ty\t-\tconfirmado\t5\t2026-08\t-\n' > "$TMPRAIZ/boa.tsv"
    TANDEM_LISTA_URL="file://$TMPRAIZ/boa.tsv" t_lista_atualiza >/dev/null 2>&1
    igual "arquivo bem formado substitui" "1" "$(grep -c '^nova' "$TANDEM_LISTA")"
else
    pulou "atualizacao da lista" "sem curl nem wget"
fi
unset TANDEM_LISTA

secao "sucesso em silencio: sair 0 nao e ter funcionado"

igual "saida instantanea e suspeita" "0" "$(t_saida_suspeita 1; echo $?)"
igual "programa que ficou aberto nao e suspeito" "1" "$(t_saida_suspeita 40; echo $?)"

PROG_S="$ARTEFATOS/prog64.exe"
t_memoria_esquece "$PROG_S" 2>/dev/null
igual "sem resposta do dono, a licao vale menos" \
      "so-abriu" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_grava "$PROG_S" CONFIRMADO sim
igual "com o dono confirmando, a licao vale mais" \
      "confirmado" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_grava "$PROG_S" CONFIRMADO nao
igual "com o dono reprovando, a licao fica marcada como reprovada" \
      "reprovado" "$(t_confianca_da_licao "$PROG_S")"

# A receita tem que carregar a origem da confianca. Sem esta linha, "o
# processo saiu 0" e "uma pessoa olhou a tela" chegavam do outro lado com
# exatamente o mesmo peso - e a segunda pessoa nao tinha como saber.
case "$(t_receita_exporta "$PROG_S")" in
    *"CONFIANCA=reprovado"*) passou "a receita sai marcada com a confianca" ;;
    *) falhou "a receita sai marcada com a confianca" "CONFIANCA=reprovado" \
              "$(t_receita_exporta "$PROG_S" | head -8)" ;;
esac

# Sem janela nao ha como perguntar - e inventar uma resposta seria pior do
# que nao ter resposta nenhuma.
t_memoria_esquece "$PROG_S" 2>/dev/null
( unset DISPLAY WAYLAND_DISPLAY; t_confirma_funcionou "$PROG_S" 30 ) >/dev/null 2>&1
igual "sem janela, nao inventa confirmacao" \
      "so-abriu" "$(t_confianca_da_licao "$PROG_S")"
t_memoria_esquece "$PROG_S" 2>/dev/null

secao "bitola: chegar nao e chegar no lugar que este programa usa"

# Prefixo win64 do jeito que o Wine monta: system32 tem as DLLs de 64 bits e
# syswow64 as de 32. Este teste existe porque a primeira execucao do laco com
# winetricks DE VERDADE terminou assim: o verbo mfc42 saiu 0, entregou o
# arquivo em syswow64, a prova de entrega olhou as duas pastas, aprovou, e o
# programa de 64 bits continuou sem achar nada.
PB="$TMPRAIZ/pref64"
mkdir -p "$PB/drive_c/windows/system32" "$PB/drive_c/windows/syswow64"
(
  export WINEPREFIX="$PB"
  : > "$PB/drive_c/windows/syswow64/mfc42.dll"       # so 32 bits
  : > "$PB/drive_c/windows/system32/msvcp140.dll"    # so 64 bits
  : > "$PB/drive_c/windows/syswow64/gdiplus.dll"     # as duas
  : > "$PB/drive_c/windows/system32/gdiplus.dll"

  t_dll_no_prefixo mfc42.dll 64;    echo "a $?"
  t_dll_no_prefixo mfc42.dll 32;    echo "b $?"
  t_dll_no_prefixo msvcp140.dll 64; echo "c $?"
  t_dll_no_prefixo msvcp140.dll 32; echo "d $?"
  t_dll_no_prefixo gdiplus.dll 64;  echo "e $?"
  t_dll_no_prefixo sumiu.dll 64;    echo "f $?"
  t_dll_no_prefixo mfc42.dll "";    echo "g $?"
) > "$TMPRAIZ/bit.txt"
igual "programa de 64 bits, DLL so em syswow64: bitola errada" \
      "2" "$(awk '$1=="a"{print $2}' "$TMPRAIZ/bit.txt")"
igual "programa de 32 bits, a mesma DLL serve" \
      "0" "$(awk '$1=="b"{print $2}' "$TMPRAIZ/bit.txt")"
igual "programa de 64 bits, DLL em system32: serve" \
      "0" "$(awk '$1=="c"{print $2}' "$TMPRAIZ/bit.txt")"
igual "programa de 32 bits, DLL so em system32: bitola errada" \
      "2" "$(awk '$1=="d"{print $2}' "$TMPRAIZ/bit.txt")"
igual "DLL nas duas pastas serve para os dois" \
      "0" "$(awk '$1=="e"{print $2}' "$TMPRAIZ/bit.txt")"
igual "DLL ausente continua ausente" \
      "1" "$(awk '$1=="f"{print $2}' "$TMPRAIZ/bit.txt")"
# Sem saber a arquitetura, condenar seria pior do que nao saber.
igual "sem arquitetura conhecida, nao condena" \
      "0" "$(awk '$1=="g"{print $2}' "$TMPRAIZ/bit.txt")"

# Prefixo win32: so existe system32, e ela e de 32 bits.
PB32="$TMPRAIZ/pref32"; mkdir -p "$PB32/drive_c/windows/system32"
: > "$PB32/drive_c/windows/system32/mfc42.dll"
igual "prefixo de 32 bits: system32 serve a programa de 32" \
      "0" "$(WINEPREFIX="$PB32"; export WINEPREFIX; t_dll_no_prefixo mfc42.dll 32; echo $?)"

TXB="$(t_texto_bitola "$(printf 'mfc42.dll\tmfc42')" 64)"
case "$TXB" in
    *"64 bits"*"32 bits"*mfc42.dll*) passou "a mensagem diz as duas bitolas e o arquivo" ;;
    *) falhou "a mensagem diz as duas bitolas e o arquivo" "64/32/mfc42.dll" "$TXB" ;;
esac
case "$TXB" in
    *"Não é defeito da sua máquina"*) passou "a mensagem tira a culpa da maquina do dono" ;;
    *) falhou "a mensagem tira a culpa da maquina do dono" "Não é defeito da sua máquina" "$TXB" ;;
esac

secao "escolher o verbo pela bitola do programa"

igual "programa de 32 bits fica com o verbo normal" \
      "xact" "$(t_verbo_para_arquitetura xact 32)"
igual "verbo sem irmao de 64 nao e trocado" \
      "vcrun2022" "$(t_verbo_para_arquitetura vcrun2022 64)"
igual "sem arquitetura conhecida, nao troca nada" \
      "xact" "$(t_verbo_para_arquitetura xact '')"
if t_winetricks_tem_verbo xact_x64; then
    igual "programa de 64 bits ganha o irmao xact_x64" \
          "xact_x64" "$(t_verbo_para_arquitetura xact 64)"
else
    # Winetricks antigo sem o irmao: melhor o verbo normal do que um nome
    # de verbo que este winetricks nao conhece.
    igual "sem o irmao neste winetricks, mantem o verbo normal" \
          "xact" "$(t_verbo_para_arquitetura xact 64)"
fi

igual "mfc42 e reconhecido como so-32" "0" "$(t_verbo_so_32 mfc42; echo $?)"
igual "vcrun2022 nao e so-32"          "1" "$(t_verbo_so_32 vcrun2022; echo $?)"
# A classificacao vem do winetricks INSTALADO, nao de lista escrita aqui: uma
# lista fixa cobria oito verbos, e o inventario do winetricks achou 42.
igual "verbo com irmao _x64 nao conta como so-32" "1" "$(t_verbo_so_32 xact; echo $?)"
igual "verbo que o winetricks nao conhece nao vira so-32" \
      "1" "$(t_verbo_so_32 naoexisteesteverbo; echo $?)"
if t_winetricks_tem_verbo dsound; then
    igual "a classificacao alcanca verbo fora da lista antiga (dsound)" \
          "0" "$(t_verbo_so_32 dsound; echo $?)"
else
    pulou "classificacao de dsound" "verbo ausente neste winetricks"
fi
# wmp9 nao tem ramo win64 de verdade; wmp11 tem, e entrega um superconjunto.
if t_winetricks_tem_verbo wmp11; then
    igual "wmvcore de 64 bits vai para o wmp11, nao para o wmp9" \
          "wmp11" "$(t_verbo_para_arquitetura "$(t_dll_para_verbo wmvcore.dll)" 64)"
    igual "  e de 32 bits continua no wmp9" \
          "wmp9" "$(t_verbo_para_arquitetura "$(t_dll_para_verbo wmvcore.dll)" 32)"
else
    pulou "wmvcore em 64 bits" "wmp11 ausente neste winetricks"
fi

# AUDITOR DA BITOLA. As duas listas acima foram levantadas do winetricks
# 20240105 lendo verbo por verbo. Winetricks e atualizado por fora do Tandem:
# sem este teste, o dia em que o projeto passar a instalar carga de 64 bits
# para o mfc42 ninguem fica sabendo, e o Tandem continua avisando que nao tem
# conserto para uma coisa que passou a ter.
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
