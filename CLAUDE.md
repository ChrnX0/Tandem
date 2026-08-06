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
for f in src/bin/* src/lib/*.sh debian/post*; do bash -n "$f" || echo "FALHOU $f"; done
```

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

## Estado

Verificado: sintaxe dos 9 scripts; estrutura do `.deb` (ar, tar, modos,
root:root); `apkinfo.py` contra APK e XAPK sintéticos (ABIs, splits, OBB,
degradação em arquivo inválido); detector de dependências contra log real do
Wine (agrupou `MSVCP140`+`VCRUNTIME140` em um `vcrun2022`, ignorou
`kernel32.dll`, separou DLL própria do programa).

**Não verificado — precisa de máquina real:** duplo clique vencendo a disputa
de associação, `pkexec`, janelas do zenity, criação do prefixo, instalação de
XAPK de verdade, regra polkit. Nada disso rodou em Linux ainda.

Ambiente de referência onde o projeto nasceu: Zorin OS 18.1 (base Ubuntu
noble), kernel 7.0, x86_64, Wayland/GNOME, 15 GB RAM, Wine 10.0 do repositório
da distro, Waydroid 1.6.2 MAINLINE com GAPPS e libhoudini, `binderfs` com nós
`anbox-*`.

## Próximos passos

1. Instalar o `.deb` no Zorin e rodar `tandem doctor`. É o primeiro teste real.
2. Publicar release no GitHub com o `.deb` anexado.
3. Suporte a `.apkm` foi declarado mas só `.xapk`/`.apks` foram testados.
4. Considerar clonar um prefixo com .NET pronto em vez de rodar `dotnet48` do
   zero (30 min, alta taxa de falha) — ideia levantada, não implementada,
   requer cuidado para nunca ler de prefixo protegido em uso.

## Ambiente da máquina de desenvolvimento

Windows. Cópia de trabalho em `C:\tandem`. O `git push` funciona porque a
credencial do GitHub já está no credential helper — **não tente ler o arquivo
de credenciais** (é bloqueado, e com razão): basta rodar `git push` e o Git a
usa sozinho. A integração MCP do GitHub desta conta é **somente leitura**:
`create_repository` e `push_files` retornam 403. Use `git` direto.
