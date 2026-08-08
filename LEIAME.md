# Tandem

**Clique duas vezes num arquivo. Ele funciona.**

O Tandem faz arquivos `.exe`, `.msi`, `.apk` e `.xapk` se comportarem como
programas nativos no Linux — sem terminal, sem configuração manual, sem
precisar caçar em fórum qual pacote do `winetricks` está faltando.

```
.exe .msi   →  Wine     — dependências detectadas e instaladas sozinhas
.apk .xapk  →  Android  — compatibilidade verificada antes, em português claro
```

[![CI](https://github.com/ChrnX0/Tandem/actions/workflows/ci.yml/badge.svg)](https://github.com/ChrnX0/Tandem/actions/workflows/ci.yml)
![testes](https://img.shields.io/badge/testes-294-brightgreen)
![lintian](https://img.shields.io/badge/lintian-limpo-brightgreen)
![licença](https://img.shields.io/badge/licen%C3%A7a-MIT-blue)

[English](README.md) · [Como colaborar](CONTRIBUINDO.md) · [Ideário](docs/IDEAS.md)

<p align="center">
  <img src="docs/imagens/painel.png" alt="Painel do Tandem" width="520">
</p>

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
- **Roda programas de 64 e de 32 bits.** 64 bits é o caso normal e funciona sem
  configuração — o ambiente é criado como `win64`. Programas de 32 bits também
  rodam, mas exigem o `wine32`, que é um pacote à parte; sem ele o Tandem diz
  isso e como resolver, em vez de fechar calado. Programas feitos para Windows
  ARM são detectados e recusados com explicação.
- **Nunca falha calado.** Todo caminho de erro termina numa janela. "Cliquei
  duas vezes e não aconteceu nada" é tratado como defeito.
- **Confere se o conserto chegou mesmo.** O `winetricks` sair 0 diz que *ele*
  terminou, não que o arquivo que faltava chegou. O Tandem confere se a DLL
  está lá — e na bitola certa — antes de dar a instalação por feita. Um
  programa de 64 bits não carrega DLL de 32 bits de dentro da `syswow64`, e
  metade dos pacotes do `winetricks` só tem carga de 32. Quando é esse o caso,
  ele avisa antes de você gastar o download:

<p align="center">
  <img src="docs/imagens/dependencia.png" alt="Janela avisando que o componente só existe em 32 bits" width="720">
</p>

- **Assume a culpa quando a culpa é dele.** "Instalei as dependências e ainda
  não abre" manda um dono de loja procurar defeito numa máquina que está
  perfeita. O Tandem diz qual arquivo continua faltando e de quem é o problema:

<p align="center">
  <img src="docs/imagens/bitola.png" alt="Erro explicando que o componente só existe em 32 bits" width="720">
</p>

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
sudo apt install ./tandem_3.5_all.deb
```

Depois verifique o ambiente:

```bash
tandem doctor
```

O que estiver faltando, o Tandem instala para você:

```bash
tandem preparar
```

Isso põe Wine, `winetricks`, suporte a 32 bits, `adb` e Waydroid no lugar —
inclusive o repositório do Waydroid com a chave, na ordem certa — e pede a senha
uma vez só. Isso não pode acontecer durante a instalação do `.deb`: o `dpkg`
segura uma trava enquanto o `postinst` roda, e um `apt-get` lá dentro esperaria
para sempre. O duplo clique num `.exe` sem Wine também oferece instalar na hora,
porque é aí que a pessoa quer resolver.

## Requisitos

| Para | Você precisa de |
|---|---|
| Programas Windows de 64 bits | `wine` — o caso normal, não precisa de mais nada |
| Programas Windows de 32 bits | também o `wine32` (`sudo dpkg --add-architecture i386`) |
| Dependências automáticas | `winetricks` |
| Apps Android | [`waydroid`](https://docs.waydro.id/), já inicializado |
| Pacotes divididos (`.xapk`) | `adb` |
| Apps só de celular (ARM) | [libhoudini / libndk](https://github.com/casualsnek/waydroid_script) |

Testado no Zorin OS 18.1 (base Ubuntu 24.04). Deve funcionar em qualquer
distribuição baseada em Debian com ambiente gráfico padrão.

## Uso

Quase nenhum — você clica duas vezes nos arquivos. Quando quiser a linha de
comando:

```bash
tandem                       # painel
tandem install arquivo.xapk  # instala ou executa qualquer coisa
tandem preparar              # instala o que falta (Wine, Android, ...)
tandem programas             # lista e abre os programas Windows instalados
tandem desinstalar           # remove um programa Windows instalado
tandem android               # abre a tela do Android
tandem doctor                # diagnóstico do ambiente — o que EXISTE
tandem autoteste             # exercita aqui — o que FUNCIONA
tandem repair                # reaplica as associações de arquivo
tandem dados                 # mostra os SEUS arquivos dentro do Windows
tandem dados salvar          # copia só os seus arquivos (pequeno e rápido)
tandem dados restaurar       # devolve, sem nunca sobrescrever
tandem backup                # salva o ambiente Windows inteiro
tandem restore               # restaura
tandem protect <caminho>     # marca um perfil Wine como intocável
tandem alternativas <nome>   # procura um programa de Linux que faça o mesmo
tandem receita <arquivo>     # exporta o que aprendeu, para mandar a alguém
tandem lista                 # o que a comunidade já descobriu
tandem lista atualizar       # baixa a lista (não manda nada seu)
tandem memoria               # o que o Tandem aprendeu sobre cada programa
tandem esquecer <nome>       # apaga o que ele aprendeu sobre um programa
tandem contribuir <arquivo>  # monta a linha para você mandar, se quiser
tandem socorro               # junta tudo num arquivo para pedir ajuda
tandem logs                  # mostra o registro mais recente
```

### Os seus arquivos não são o ambiente

O ambiente — o perfil, os componentes, os programas — o Tandem refaz em vinte
minutos. O que você digitou dentro desses programas, não. O `tandem dados`
separa as duas coisas, e todo caminho destrutivo (refazer um perfil pela
metade, restaurar um backup, desinstalar um programa) passa a tirar uma cópia
antes.

A promessa que isso existe para cumprir: *se você desistir do Linux, seus dados
voltam com você.*

### Lista da comunidade

O `tandem lista` baixa um arquivo de texto por HTTPS — o modelo das listas de
filtro de bloqueador de anúncio, não um servidor: sem API, sem conta, sem
uptime para pagar. Ela guarda de quais componentes do `winetricks` cada
programa precisou, indexado por uma impressão digital do próprio arquivo.

Ler é automático depois que você pede. **Publicar não é**: o `tandem
contribuir` monta a linha e mostra ela inteira — quem envia é você. A linha não
carrega nome de arquivo, caminho, usuário, nome da máquina, IP nem log, e o
gerador se recusa a produzi-la se alguma dessas coisas aparecer. O formato está
em [docs/LIST-FORMAT.md](docs/LIST-FORMAT.md).

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

## Como colaborar

A contribuição mais valiosa não exige código. **Quase nenhum programa comercial
de verdade jamais rodou nisto** — o laço de dependências foi exercitado contra
binários de teste, não contra o sistema de uma loja em cima de um balcão.

Se um programa funcionou, o `tandem contribuir <arquivo>` monta uma linha que
você cola numa issue. Ela leva uma impressão digital do arquivo, a arquitetura e
os componentes que resolveram — sem nome de arquivo, caminho, usuário, nome da
máquina, IP nem log, e o gerador se recusa a produzi-la se alguma dessas coisas
aparecer.

Se não funcionou, o `tandem socorro` junta num arquivo só tudo o que alguém
perguntaria.

Os detalhes, as cinco regras que não se quebram e a régua de evidência estão em
[CONTRIBUINDO.md](CONTRIBUINDO.md). Antes de propor coisa nova, dê uma olhada em
[docs/IDEAS.md](docs/IDEAS.md) — 52 ideias com veredito, e as recusadas trazem
o motivo escrito.

## Licença

MIT. Veja [LICENSE](LICENSE).
