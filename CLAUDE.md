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
debian/postinst           aplica associações e protege prefixos já existentes
src/lib/common.sh         log, notificação, progresso, prefixo, PE, waydroid
src/lib/winedeps.sh       DLL -> verbo do winetricks; DLLs sem tradução
src/lib/apkinfo.py        leitor de AndroidManifest binário, Python puro
src/bin/tandem            CLI + painel zenity
src/bin/tandem-exe        loop roda->detecta->instala->repete
src/bin/tandem-apk        pré-voo + install; xapk/apks via adb install-multiple
src/bin/tandem-repair     disputa de associação MIME
src/polkit/               regra estreita: só start/restart do waydroid-container
```

Build e verificação:

```bash
python3 build.py --check
bash tests/run.sh          # 83 testes, roda sem Wine, sem Waydroid, sem instalar
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
- 83 testes automatizados em `tests/run.sh`.

**Ainda não verificado — precisa da máquina de verdade:** o duplo clique
vencendo a disputa de associação no GNOME/Zorin, `pkexec` e a regra polkit,
criação de prefixo com Wine instalado, o laço roda→detecta→instala com
`winetricks` real, e instalação de XAPK num Waydroid real. Wine e Waydroid não
existem neste ambiente de teste.

Ambiente de referência onde o projeto nasceu: Zorin OS 18.1 (base Ubuntu
noble), kernel 7.0, x86_64, Wayland/GNOME, 15 GB RAM, Wine 10.0 do repositório
da distro, Waydroid 1.6.2 MAINLINE com GAPPS e libhoudini, `binderfs` com nós
`anbox-*`.

## Próximos passos

1. Instalar o `.deb` no Zorin e rodar `tandem doctor` **numa sessão gráfica**.
   O que falta testar agora é só o que depende de Wine, Waydroid e do GNOME
   real — o resto já roda verde na suíte.
2. Confirmar o duplo clique. Se abrir o diálogo "Abrir com…", rodar
   `tandem repair` e comparar o antes/depois que ele imprime.
3. Publicar release no GitHub com o `.deb` anexado.
4. Suporte a `.apkm` foi declarado mas só `.xapk`/`.apks` foram testados.
5. Considerar clonar um prefixo com .NET pronto em vez de rodar `dotnet48` do
   zero (30 min, alta taxa de falha) — ideia levantada, não implementada,
   requer cuidado para nunca ler de prefixo protegido em uso.

## Ambiente da máquina de desenvolvimento

Windows. Cópia de trabalho em `C:\tandem`. O `git push` funciona porque a
credencial do GitHub já está no credential helper — **não tente ler o arquivo
de credenciais** (é bloqueado, e com razão): basta rodar `git push` e o Git a
usa sozinho. A integração MCP do GitHub desta conta é **somente leitura**:
`create_repository` e `push_files` retornam 403. Use `git` direto.
