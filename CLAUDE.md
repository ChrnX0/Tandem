# Tandem — contexto para o agente

Leia antes de mexer em qualquer coisa. Este arquivo existe para uma sessão nova
retomar o trabalho sem repetir descobertas que já custaram caro.

## O que é

Pacote `.deb` que faz `.exe`, `.msi`, `.apk` e `.xapk` abrirem com **dois
cliques** no Linux. Não é gerenciador de prefixos nem substituto do Bottles: é
uma **camada fina de decisão, tradução e diagnóstico** por cima de `wine`,
`winetricks -q` e `waydroid`.

O usuário-alvo não é programador. A régua de qualidade é: *nenhum caminho de
erro pode terminar em silêncio*. "Cliquei duas vezes e não aconteceu nada" é
tratado como defeito, não como limitação.

## Regras invioláveis

1. **Nunca escrever em prefixo Wine que o Tandem não criou.** Prefixo nosso tem
   a marca `.tandem-prefixo`. Qualquer outro é somente leitura para a
   automação: o Tandem executa o programa lá dentro, informa o que falta e
   **para**. Isso existe porque a máquina de origem roda um sistema de frente de
   caixa em prefixo próprio — instalar dependência dentro de um ambiente de
   produção que funciona é pior do que não automatizar nada.
2. **Mensagens ao usuário em português, sem jargão.** `NO_MATCHING_ABIS` vira
   "este app é feito só para celular e não roda aqui".
3. **`set -e` só no empacotador, nunca nos executáveis.** Os laços de espera
   dependem de comandos que falham de propósito (`grep -q ... && break`).
4. **Não repetir instalação já paga.** `dotnet48` leva ~30 min; há recibo em
   `$WINEPREFIX/.tandem-verbos`.
5. **O empacotador não pode depender de `dpkg-deb`.** `build.py` escreve o
   arquivo `ar` à mão e roda em qualquer SO, inclusive Windows.

## Mapa

```
build.py                  empacotador (ar + tar.gz manuais)
debian/control            versão do pacote vive aqui
debian/changelog          entrada nova a cada versão; lintian exige data nova
debian/copyright          DEP-5; lintian exige
debian/postinst           só atalho: o trabalho por-usuário é na 1ª execução
man/tandem.1              manual; os outros quatro são stubs ".so"
src/mime/tandem.xml       registra .xapk/.apks/.apkm como subclasse de zip
src/lib/common.sh         log, mensagem, locale, progresso, prefixo, PE, waydroid,
                          memoria, receitas, alternativas, pre-voo, preparar
src/lib/winedeps.sh       DLL -> verbo do winetricks; DLLs sem tradução
src/lib/apkinfo.py        leitor de AndroidManifest binário, Python puro
src/lib/peinfo.py         leitor da tabela de importações do PE, sem executar
src/lib/verbos.tsv        índice DLL->verbo GERADO; não editar à mão
src/lib/limites.tsv       assinaturas do que nunca vai funcionar (dongle, driver)
src/lib/alternativas.tsv  programas de Linux que fazem o mesmo trabalho
tools/indice-winetricks.py  gera verbos.tsv lendo o winetricks instalado
proofgate.json            portão de evidência: stack, arquivos acoplados
.github/workflows/ci.yml  suíte + lintian + ciclo real de instalação
src/bin/tandem            CLI + painel zenity; preparar/programas/desinstalar
src/bin/tandem-exe        loop roda->detecta->instala->repete
src/bin/tandem-apk        pré-voo + install; xapk/apks via adb install-multiple
src/bin/tandem-repair     disputa de associação MIME
src/polkit/               regra estreita: só start/restart do waydroid-container
tests/run.sh              suíte; tests/mkapk.py gera os pacotes sintéticos
```

Comandos (`tandem --help` é a fonte da verdade):

```
install    programas   desinstalar   preparar     android
doctor     autoteste   repair        backup       restore
protect    alternativas  receita     memoria      esquecer     logs
```

Build e verificação:

```bash
python3 build.py --check
bash tests/run.sh          # 206 testes, sem Wine, sem Waydroid, sem instalar
```

A suíte carrega as bibliotecas direto de `src/lib` e gera pacotes Android
sintéticos com `AndroidManifest.xml` binário de verdade (`tests/mkapk.py`), então
o leitor de manifesto é exercitado no mesmo caminho de código de um APK real.
Ferramenta opcional ausente é pulada, não reprovada. **Rode antes de commitar.**

## Como o detector de dependências funciona

O Wine escreve `err:module:import_dll Library MSVCP140.dll not found` quando
falta biblioteca. `t_verbos_do_log` lê essas linhas, ignora DLLs que o próprio
Wine implementa (`kernel32`, `user32`…) e traduz o resto para verbos do
winetricks. DLL sem tradução conhecida **não** é dependência do sistema — é
arquivo que o programa deveria trazer junto, e a mensagem diz isso.

Teste sem precisar do Wine:

```bash
. src/lib/winedeps.sh
printf '0:err:module:import_dll Library MSVCP140.dll (needed by X) not found\n' > /tmp/w.log
t_verbos_do_log /tmp/w.log     # espera: vcrun2022
```

## Fatos do ecossistema já apurados (não repesquisar)

- **Nenhum projeto faz detecção automática de dependência de `.exe`.** Nem
  Bottles, nem Lutris, nem PlayOnLinux — todos exigem um humano escolhendo numa
  lista. O loop do Tandem é trabalho novo; calibre a expectativa de acerto.
- **O Bottles não instala dependência por linha de comando** (só GUI), o que o
  inviabiliza como motor.
- **O Tandem entra numa disputa de associação, não num vazio.** O Zorin 18 traz
  "Windows App Support" e o Waydroid instala `waydroid.app.install.desktop`. Se
  o duplo clique abrir um diálogo "Abrir com…", é isso — rode `tandem repair`,
  que mostra quem detinha o tipo antes e depois.
- **`~/.config/gnome-mimeapps.list` e `zorin-mimeapps.list` têm precedência
  maior** que `mimeapps.list` e sobrescrevem em silêncio. O `tandem-repair`
  limpa os concorrentes com backup.
- **`waydroid app install` retorna 0 mesmo falhando.** Sempre parsear a saída.
- **`Session: RUNNING` não significa Android pronto.** Esperar
  `sys.boot_completed`; com GAPPS leva mais 20–60 s.
- **`winemenubuilder` faz duas coisas.** Cria atalhos de menu (queremos) e
  sequestra associações de `.txt`/`.jpg`/`.pdf` (não queremos). Desligar o
  binário mata as duas; a chave certa é
  `HKCU\Software\Wine\FileOpenAssociations\Enable = N`.
- **`WINEARCH` só na criação do prefixo.** Definir em prefixo existente faz o
  Wine se recusar a iniciar.
- **`.msi` não é PE.** `wine arquivo.msi` falha sempre; tem que ser
  `wine msiexec /i`.
- **O zenity recusa acento se o locale não existir.** Definir um locale que o
  sistema não gerou (`LC_ALL=pt_BR.UTF-8` num Zorin instalado em inglês) faz o
  glib cair para `ANSI_X3.4-1968`; a partir daí qualquer argumento não-ASCII
  devolve `This option is not available`, código 255, e **nenhuma janela
  aparece**. Como toda mensagem daqui tem acento, isso apagava a interface
  inteira em silêncio. Detector confiável: `locale charmap` tem que dizer
  `UTF-8`. Use `t_locale_utf8`, nunca escreva um locale fixo.
- **`zenity --error` bloqueia até o clique** e devolve 0. Se devolver diferente
  de 0, a janela não foi mostrada — é esse o sinal que o `t_erro` usa para
  decidir se precisa repetir a mensagem no terminal.
- **Cano de progresso aberto só para escrita mata o processo.** Quando o
  zenity sumia, a mensagem seguinte levava SIGPIPE e derrubava o Tandem
  inteiro: código 141, nada no log. Dentro do laço do `winetricks` isso cortava
  uma instalação pela metade. Abrir o descritor com `exec 8<> fifo` resolve —
  com leitura e escrita o cano nunca fica sem leitor.
- **`exec N> arquivo` que falha não aborta o bash.** O script segue vivo, o
  `flock` responde "Bad file descriptor", e confundir isso com "trava tomada"
  fazia o duplo clique morrer em silêncio. Trava impossível e trava ocupada são
  casos distintos: no primeiro, siga sem trava.
- **`wine uninstaller --list` mente.** Instalador de 32 bits grava a chave em
  `Wow6432Node\...\Uninstall`, e o `uninstaller.exe` — que vira processo de 32
  bits quando há `wine32` — enumera a outra visão. Confirmado com Wine real: o
  7-Zip instalado e a lista vazia. Leia `system.reg` e `user.reg` direto; as
  duas visões aparecem, e nem precisa do Wine para listar.
- **O GNOME sob Wayland não relê a lista de aplicativos.** Um `.desktop` novo
  numa subpasta recém-criada (`applications/wine/Programs/X/`) só aparece no
  menu depois de sair e entrar na conta. `update-desktop-database` **não**
  resolve — testado na máquina real. Por isso existe `tandem programas`: o
  Tandem não pode depender do menu do sistema para você achar o que instalou.
- **Não dá para instalar dependências no `postinst`.** O `dpkg` segura uma
  trava enquanto ele roda; um `apt-get` lá dentro espera para sempre. Daí
  `tandem preparar` ser um comando separado.
- **`[ -t 1 ]` sozinho não distingue duplo clique de redirecionamento.** Cano e
  arquivo também não são terminal, e mandar o diagnóstico para uma janela fazia
  `tandem doctor > relatorio.txt` gravar zero bytes. Teste os três:
  `[ -t 1 ] || [ -p /dev/fd/1 ] || [ -f /dev/fd/1 ]`.
- **O Waydroid não está nos repositórios do Ubuntu/Zorin.** `apt-cache policy
  waydroid` devolve `Candidate: (none)`. Vem de `repo.waydro.id`, com chave.

## Estado

Verificado **em Linux real** (Ubuntu 24.04 noble, mesma base do Zorin 18, com
root), não mais só por leitura:

- O `.deb` escrito à mão pelo `build.py` é aceito pelo `dpkg` de verdade:
  `dpkg-deb --info/--contents`, `dpkg -i`, `dpkg --configure`. Instala,
  configura e desinstala. Construção reproduzível (duas builds, mesmo cksum).
- `lintian` limpo: zero erros, zero avisos.
- O `postinst` no caminho por-usuário: protegeu sozinho os três prefixos Wine
  pré-existentes (`~/.wine`, `~/.wine-pdv`, `wineprefixes/*`). **Regra nº 1
  confirmada ponta a ponta.**
- `tandem-repair` contra um `gnome-mimeapps.list` concorrente: removeu as
  entradas em disputa, preservou o `text/plain` alheio, gravou no
  `mimeapps.list`, deixou backup.
- `tandem doctor`, `version`, `--help`, painel sem GUI: todos com saída.
- Janelas do zenity abrem de fato (verificado sob Xvfb), inclusive com acento.
- Wine 10.0 real instalado no container: prefixo `win64` criado do zero,
  7-Zip x64 instalado por `.exe` e por `.msi`, registro inspecionado à mão.
- 206 testes automatizados em `tests/run.sh`; CI no GitHub Actions.

Verificado **no Zorin 18.1 do usuário** (Wayland, Wine 10.0, Waydroid ativo):

- `tandem doctor` completo, com o ambiente todo presente.
- Os dois prefixos pré-existentes (`~/.wine` e `~/.wine-pdv`, o do PDV) foram
  protegidos **sozinhos** na primeira execução, sem digitar nada.
- Duplo clique roteando: `xdg-mime query default` responde `tandem-exe.desktop`
  e `tandem-apk.desktop`.
- 7-Zip x64 instalado pelo Tandem: prefixo criado, instalador executado,
  `.lnk` no Menu Iniciar, `winemenubuilder` gerando o `.desktop`.
- **As associações do usuário sobreviveram intactas** — `zip`, `txt`, `jpeg` e
  `pdf` continuam com os apps do Zorin, nenhum `wine-extension`. É a prova da
  decisão de desligar só o sequestro pela chave `FileOpenAssociations` em vez
  do `winemenubuilder` inteiro.
- A janela de erro acentuada aparece de verdade, com o texto certo.

**Ainda não verificado — precisa da máquina de verdade:** `pkexec` e a regra
polkit (o serviço do Waydroid já estava ativo, então a regra nunca foi
exercitada), o laço roda→detecta→instala com `winetricks` real ponta a ponta
(o 7-Zip não depende de nada, então o laço nunca precisou agir), instalação de
XAPK num Waydroid real, e os comandos novos `preparar`, `programas` e
`desinstalar` em campo.

Ambiente de referência onde o projeto nasceu: Zorin OS 18.1 (base Ubuntu
noble), kernel 7.0, x86_64, Wayland/GNOME, 15 GB RAM, Wine 10.0 do repositório
da distro, Waydroid 1.6.2 MAINLINE com GAPPS e libhoudini, `binderfs` com nós
`anbox-*`.

## O que foi construído depois da 2.1

- **Pré-voo** (`peinfo.py`): lê a tabela de importações do `.exe` sem executar.
  Validado contra o `objdump` em 37 binários reais — saída idêntica nos 37.
- **Veredito de impossibilidade** (`limites.tsv`): reconhece chave de proteção,
  driver de sistema e USB direto ANTES de rodar. Não bloqueia; explica a falha.
- **Índice do winetricks** (`verbos.tsv`, 246 DLLs): gerado do `w_override_dlls`
  de cada verbo. Só responde com confiança alta — 192 sim, 54 se calam.
  Usado sobretudo como AUDITOR da tabela à mão, e nessa função achou **seis
  erros de mapeamento** que instalavam a coisa errada e gravavam recibo.
- **Memória e receitas**: o que cada programa pediu, indexado pelo ARQUIVO
  (tamanho + primeiro e último MiB), então a lição sobrevive a mudar de pasta
  e vale noutra máquina. Receita é arquivo de texto que o dono manda para
  alguém. Só puxa, nunca empurra.
- **`tandem autoteste`**: exercita em vez de listar. Onde não dá para
  exercitar, diz que pulou.
- **`tandem preparar`**, **`programas`**, **`desinstalar`**, **`alternativas`**.
- **Portão de evidência e CI**, os dois primeiros do projeto.

## Próximos passos

0. **A tese, e o item mais importante da lista: prova de entrega.** Hoje o
   recibo `.tandem-verbos` é gravado quando `winetricks -q` sai 0, o que
   mistura "o comando rodou" com "o componente certo chegou". Como a regra
   nº 4 proíbe repetir, toda tradução errada vira beco permanente: o verbo
   entra no recibo, na volta cai em REPETIDOS, e o dono lê "já instalei o que
   este programa pedia" — mentira. Foi o que o `atl*` fez por seis versões.
   O conserto: depois do `winetricks` sair 0 e ANTES de gravar o recibo,
   conferir se a DLL que faltava apareceu no `system32`/`syswow64`. Se não
   apareceu, não grava recibo e diz a verdade — "a tradução que eu uso para
   esse arquivo provavelmente está errada; é problema meu". Isso torna o laço
   auto-corretivo, e é pré-requisito de qualquer clone de prefixo.
1. **`tandem dados`.** Nada no projeto separa AMBIENTE (reconstruível em 30
   min) de DADOS (irreconstruíveis; NF-e tem guarda de 5 anos). Três caminhos
   apagam dado do dono hoje sem cópia: `tandem-exe:83` (`rm -rf` do prefixo
   incompleto), `acao_restore` (devolve o ambiente e leva as vendas do mês) e
   o desinstalador do programa. O `backup` salva só o ambiente. A frase que
   resume: *"se você desistir do Linux, seus dados voltam com você"* — é isso
   que faz um dono de loja aceitar tentar.
2. **Sucesso em silêncio.** `CODIGO -eq 0` é tratado como "funcionou", mas o
   modo de falha típico do Wine com software comercial é abrir e estar
   sutilmente errado: cupom com acento quebrado, relatório em branco, data
   invertida. Tudo isso sai 0, o Tandem comemora, e a receita exporta a lição
   errada. Um projeto cuja régua é "nenhum erro em silêncio" tem no centro um
   sucesso em silêncio.
3. O auditor tem um ponto cego confirmado: o gerador só lê `w_override_dlls`,
   e verbos como o `vcrun2003` declaram as DLLs apenas no `title=`. Resultado:
   zero entradas de `vcrun2003` no índice — ele era cego exatamente onde a
   tabela errava. Ler também a lista entre parênteses do `title=`.
4. Testar em campo os comandos novos: `desinstalar`, `programas`, `preparar`,
   `autoteste`, `alternativas`, `receita`.
2. Duplo clique num `.xapk` de verdade. Os tipos MIME agora estão registrados
   (`src/mime/tandem.xml`); antes o sistema via só um ZIP genérico e o suporte
   a pacotes divididos era inalcançável pelo duplo clique.
3. Um `.exe` que **falte** alguma coisa, para o laço roda→detecta→instala
   finalmente trabalhar. O 7-Zip foi fácil demais: não depende de nada.
4. Publicar release no GitHub com o `.deb` anexado.
5. Suporte a `.apkm` foi declarado mas só `.xapk`/`.apks` foram testados.
6. Considerar clonar um prefixo com .NET pronto em vez de rodar `dotnet48` do
   zero (30 min, alta taxa de falha) — ideia levantada, não implementada,
   requer cuidado para nunca ler de prefixo protegido em uso.
7. Um painel de ideação de seis lentes rodou e gerou 31 ideias julgadas; dois
   agentes (roteiro e crítico de completude) morreram no limite de sessão. Os
   achados que sobreviveram viraram os consertos de SIGPIPE, trava e
   winetricks. Falta a síntese estratégica.

## Ambiente da máquina de desenvolvimento

Windows. Cópia de trabalho em `C:\tandem`. O `git push` funciona porque a
credencial do GitHub já está no credential helper — **não tente ler o arquivo
de credenciais** (é bloqueado, e com razão): basta rodar `git push` e o Git a
usa sozinho. A integração MCP do GitHub desta conta é **somente leitura**:
`create_repository` e `push_files` retornam 403. Use `git` direto.
