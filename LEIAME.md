# Tandem

**Clique duas vezes num arquivo. Ele funciona.**

O Tandem faz arquivos `.exe`, `.msi`, `.apk` e `.xapk` se comportarem como
programas nativos no Linux — sem terminal, sem configuração manual, sem
precisar caçar em fórum qual pacote do `winetricks` está faltando.

```
.exe .msi   →  Wine     — dependências detectadas e instaladas sozinhas
.apk .xapk  →  Android  — compatibilidade verificada antes, em português claro
```

[English](README.md)

---

## Por quê

Rodar um programa Windows ou um app Android no Linux já é possível hoje, mas o
caminho é hostil para quem não é programador: instalar o Wine, criar um perfil,
descobrir qual biblioteca falta lendo `err:module:import_dll` num terminal,
traduzir isso para um pacote do `winetricks`, instalar, tentar de novo. No lado
Android, ligar um serviço de contêiner, depois uma sessão, depois esperar um
boot sem nenhum sinal de progresso, e só então descobrir que o `.apk` era só
para celular.

O Tandem faz esse trabalho por você e informa o resultado numa frase sobre a
qual dá para agir.

## O que ele faz de fato

### Programas Windows

- **Descobre o que falta lendo a saída do próprio Wine.** Quando um programa
  falha, o Wine escreve `err:module:import_dll Library MSVCP140.dll not found`.
  O Tandem lê essas linhas, traduz cada DLL para o pacote que a fornece,
  instala e tenta de novo — até três rodadas. É exatamente o que uma pessoa
  experiente faria à mão.
- **Separa "falta um componente do Windows" de "o programa está incompleto".**
  DLLs sem tradução conhecida quase sempre são arquivos que o próprio programa
  deveria trazer junto. O Tandem diz isso, em vez de instalar qualquer coisa.
- **Trata cada tipo de arquivo do jeito certo.** `.msi` vai por `msiexec /i`,
  `.lnk` por `wine start /unix`. Associar `.msi` ao `wine` puro — erro comum —
  falha sempre.
- **Verifica a arquitetura antes.** Programa de 32 bits em sistema sem `wine32`
  recebe uma mensagem com a solução, não um encerramento silencioso.
- **Nunca falha calado.** Todo caminho de erro termina numa janela. "Cliquei
  duas vezes e não aconteceu nada" é tratado como defeito.

### Aplicativos Android

- **Analisa o pacote antes de instalar.** Um leitor de manifesto binário
  embutido (sem precisar do SDK do Android) extrai o nome do pacote, o
  `minSdkVersion` e as arquiteturas nativas, e compara com o Android em
  execução. Você é avisado — *"este app exige Android 15, o seu é 13"* — em vez
  de assistir a uma instalação falhar.
- **Instala pacotes divididos.** `.xapk`, `.apks` e `.apkm` são extraídos e
  instalados via ADB com `install-multiple`, incluindo os arquivos de dados
  (OBB). A maioria dos apps grandes é distribuída assim.
- **Lê o resultado verdadeiro.** O `waydroid app install` retorna sucesso mesmo
  quando falha. O Tandem lê a saída e traduz `NO_MATCHING_ABIS`,
  `INSTALL_FAILED_OLDER_SDK` e companhia para português.
- **Espera o sinal certo.** `Session: RUNNING` significa que o gerenciador de
  sessão subiu, não que o Android terminou de iniciar. O Tandem espera o
  `sys.boot_completed`.

### Segurança

Perfis Wine que o Tandem não criou são **somente leitura para a automação**.
Se um programa mora dentro de um perfil existente, o Tandem o executa *naquele
perfil* e se recusa a instalar qualquer coisa ali — informa o que falta e para.

Isso existe porque o projeto nasceu numa máquina que também roda um sistema de
frente de caixa em perfil próprio. Automação que "ajuda" instalando um
componente dentro de um ambiente de produção que funciona é pior que automação
nenhuma.

Para proteger um perfil explicitamente:

```bash
tandem protect ~/.wine-alguma-coisa
```

## Instalação

Baixe o `.deb` em [Releases](../../releases) e clique duas vezes, ou:

```bash
sudo apt install ./tandem_2.2_all.deb
```

Depois verifique o ambiente:

```bash
tandem doctor
```

O Tandem não instala Wine nem Waydroid — ele conecta o que você já tem. O
`tandem doctor` diz o que está faltando e como resolver.

## Requisitos

| Para | Você precisa de |
|---|---|
| Programas Windows | `wine`, e `winetricks` para as dependências automáticas |
| Programas de 32 bits | `wine32` (`sudo dpkg --add-architecture i386`) |
| Apps Android | [`waydroid`](https://docs.waydro.id/), já inicializado |
| Pacotes divididos (`.xapk`) | `adb` |
| Apps só de celular (ARM) | [libhoudini / libndk](https://github.com/casualsnek/waydroid_script) |

Testado no Zorin OS 18.1 (base Ubuntu 24.04). Deve funcionar em qualquer
distribuição baseada em Debian com ambiente gráfico padrão.

## Uso

Quase nenhum — você clica duas vezes nos arquivos. Quando quiser a linha de
comando:

```bash
tandem                     # painel
tandem install arquivo.xapk  # instala ou executa qualquer coisa
tandem android             # abre a tela do Android
tandem doctor              # diagnóstico do ambiente
tandem repair              # reaplica as associações de arquivo
tandem backup              # salva o ambiente Windows
tandem restore             # restaura
tandem protect <caminho>   # marca um perfil Wine como intocável
tandem logs                # mostra o registro mais recente
```

## Compilar

Não precisa de máquina Debian nem do `dpkg-deb` — o empacotador escreve o
arquivo `ar` diretamente:

```bash
python3 build.py --check
```

## Testes

A suíte roda sem Wine, sem Waydroid e sem instalar o pacote: as bibliotecas de
shell são carregadas direto de `src/lib` e os pacotes Android são sintéticos —
inclusive com um `AndroidManifest.xml` binário de verdade, para que o leitor de
manifesto seja exercitado no mesmo caminho de código de um APK real.

```bash
bash tests/run.sh
```

As ferramentas opcionais (`shellcheck`, `dpkg-deb`, `desktop-file-validate`) são
usadas quando existem e puladas quando não existem, então a suíte passa numa
máquina sem nada instalado.

## O que nunca vai funcionar

Ser honesto sobre isso desde o início economiza uma tarde:

- **Dispositivos USB dentro do Android.** O Waydroid não repassa USB.
  Impressora térmica, pinpad, leitor de código de barras e balança não existem
  dentro do contêiner. Nenhuma automação muda isso.
- **Apps de banco e de maquininha.** O Play Integrity detecta o contêiner. Não
  há contorno confiável.
- **Programas Windows com driver de kernel.** Antivírus, alguns TEF, chaves de
  proteção por hardware. O Wine roda em espaço de usuário.
- **Licenciamento amarrado ao hardware.** O Wine devolve seriais de BIOS e disco
  vazios ou sintéticos. Software que identifica a máquina pode se recusar a
  ativar — ou travar na tela de ativação.

## Licença

MIT. Veja [LICENSE](LICENSE).
