# Ideário do Tandem

Este arquivo é a síntese que faltava. Dois painéis adversariais rodaram nesta
sessão (31 ideias no primeiro, 21 no segundo, com juízes independentes em cada
um) e os achados ficaram espalhados nos julgamentos — vários viraram código sem
que o ideário existisse, e os outros iam se perder junto com a sessão.

Cada entrada tem **veredito**. Ideia sem veredito é conversa; ideia recusada com
o motivo escrito vale tanto quanto ideia aceita, porque impede a próxima sessão
de repropor o mesmo erro.

Legenda:

| | |
|---|---|
| **FEITO** | está no código, com teste |
| **PRÓXIMO** | aceito, na fila, com o desenho já decidido |
| **DEPOIS** | aceito, mas depende de algo que ainda não existe |
| **RECUSADO** | com o motivo — não repropor sem argumento novo |

---

## O critério que separa as boas das ruins

O painel só ficou útil depois que apareceu um critério para julgar. É este:

> O Tandem não compete em "rodar programa Windows". Wine, Bottles, Lutris e
> PlayOnLinux fazem isso melhor e há mais tempo. O que ninguém faz é **fechar o
> laço de diagnóstico para quem não sabe ler um log**. Toda ideia que aumenta a
> quantidade de coisas que o Tandem executa vale menos que qualquer ideia que
> aumente a quantidade de coisas que o Tandem **explica**.

Corolário duro, que matou nove ideias de uma vez: *funcionalidade que o dono da
loja não consegue nem perceber que existe não é funcionalidade.*

---

## 1. Não perder o que é insubstituível

O ponto cego que o crítico do segundo painel encontrou, e que sozinho justifica
o painel inteiro: das 52 ideias das duas rodadas, **zero** falavam sobre o que
os programas escrevem. Todas falavam sobre abri-los. Ambiente se reconstrói em
vinte minutos; o cadastro de clientes de sete anos, não.

Pior: existem hoje **três caminhos que apagam dados do usuário sem cópia**.

| Ideia | Veredito |
|---|---|
| **`tandem dados`** — separar, na cabeça do programa e na do dono, *ambiente* (reconstruível) de *dados* (insubstituíveis). Listar o que cada programa instalado escreve, onde, e com que tamanho. | **PRÓXIMO** — é o item 1 da fila |
| **Cópia obrigatória antes de todo caminho destrutivo.** `rm -rf` de prefixo incompleto, `tandem desinstalar`, `tandem restore` sobrescrevendo. Nenhum deles pergunta hoje. | **PRÓXIMO** — junto com o `dados` |
| **`tandem backup` separar os dois volumes.** Hoje ele empacota o prefixo inteiro num `.tar.gz`: o `.NET` de 30 minutos e o cadastro de clientes no mesmo arquivo, com o mesmo peso. Backup que demora demais não é feito. | **PRÓXIMO** |
| **Achar o que é dado sem adivinhar**: `Documents`, `AppData/Roaming`, e — o caso que importa — arquivos alterados dentro da pasta do programa depois da instalação. `.mdb`, `.fdb`, `.gdb`, `.dbf`, `.sqlite` num diretório de programa são dados de gente. | **PRÓXIMO** — é o mecanismo do `tandem dados` |
| Backup automático agendado | **RECUSADO** — agendamento silencioso enche o disco de uma máquina de loja sem ninguém perceber, e disco cheio é uma das causas de falha que o próprio Tandem diagnostica. Cópia sob comando, com o tamanho dito antes. |
| Sincronizar dados para a nuvem | **RECUSADO** — dado de cliente de loja saindo da máquina por decisão de um automatismo. Não é nossa decisão a tomar. |

## 2. Saber se realmente funcionou

O modo característico de o Wine falhar com software comercial não é fechar com
erro — é **abrir e estar sutilmente errado**. Relatório que imprime em branco,
acento virando caixinha, janela que abre atrás de outra. Hoje `CODIGO -eq 0`
vira "abriu", vira `RESULTADO=abriu` na memória, e vira receita exportada para
a máquina do vizinho.

| Ideia | Veredito |
|---|---|
| **Distinguir "o processo saiu 0" de "o programa funcionou".** Saiu em menos de 2 s sem abrir janela nenhuma não é sucesso: é o instalador que morreu calado. Dá para conferir com `xdotool`/`wmctrl` quando existem, e pelo tempo de vida quando não existem. | **PRÓXIMO** — item 2 da fila |
| **Perguntar, uma vez só, depois de fechar:** "o programa funcionou como você esperava?" A resposta é o único sinal E4 que existe — e é ela que deveria decidir se a receita vale a pena ser exportada. | **PRÓXIMO** — casa com a memória que já existe |
| **Marcar a receita com a origem da confiança**: "isto funcionou aqui e o dono confirmou" pesa diferente de "o processo saiu 0". | **PRÓXIMO** |
| **Testar impressão explicitamente.** Para software de loja, imprimir *é* o programa. Wine + CUPS funciona; Wine + impressora térmica por USB, quase nunca. | **DEPOIS** — precisa de um programa de loja real primeiro |
| Captura de tela automática da janela aberta | **RECUSADO** — tela de sistema de PDV tem dado de cliente. Não se guarda isso sem pedir. |

## 3. Aprendizado e memória

Já implementado. O desenho que sobreviveu ao painel:

| Ideia | Veredito |
|---|---|
| **Memória por arquivo, não por nome.** Identidade = `sha256` do tamanho + primeiro e último MiB. Nome de arquivo mente (`setup.exe` são milhares de programas diferentes); conteúdo, não. | **FEITO** |
| **A memória sugere, nunca decide.** Ela encurta o caminho só se o dono mandar. Instalar sozinho com base numa lição passada é repetir um engano para sempre — e num prefixo de loja isso custa caro. | **FEITO** — e é a regra que impede o pior modo de falha da ideia toda |
| **Lição negativa também é lição**: `NAO_RESOLVERAM` guarda o que foi instalado e não resolveu, para não prometer de novo. | **FEITO** |
| **Lição negativa suspeita não vira lição.** Se a DLL pedida nem chegou, o erro foi da minha tradução — gravar isso ensinaria o engano à próxima máquina. | **FEITO** — v3.3 |
| **`tandem esquecer`** — a memória tem que ter porta de saída, ou vira dívida. | **FEITO** |
| Perfil de uso / telemetria de quais programas o dono abre | **RECUSADO** — nada que o dono não veja e não possa apagar. |

## 4. Conhecimento coletivo

O pedido original era um servidor-ponte entre todos os Tandems. A ideia é boa; a
implementação de servidor é que é cara e arriscada. O painel achou o meio-termo.

| Ideia | Veredito |
|---|---|
| **Receita: um arquivo de texto exportável com o que aquele programa precisou.** `tandem receita` exporta, importa e valida. Conhecimento coletivo por WhatsApp, sem servidor, sem conta, sem CNPJ, sem LGPD. | **FEITO** |
| **Validar tudo que entra.** Receita é conteúdo de terceiro: verbo só passa se existir na lista conhecida do winetricks. Sem isso, receita vira execução remota de comando. | **FEITO** |
| **Receita não carrega caminho nem nome de máquina.** Só o par programa/verbos. | **FEITO** |
| **Servidor-ponte de verdade**, com agregação: "em 340 máquinas este programa precisou destes três componentes; em 12 não funcionou de jeito nenhum". Esse número é uma informação que nenhum fórum tem. | **DEPOIS** — o formato de receita já é o protocolo; o que falta é o servidor. Só vale a pena depois que houver Tandems suficientes para o número significar algo, e o custo real é moderação de conteúdo hostil, não código |
| Sincronização automática ao instalar | **RECUSADO** — a máquina de uma loja não fala com servidor nenhum sem o dono mandar. |

## 5. Alternativas nativas

| Ideia | Veredito |
|---|---|
| **Sugerir equivalente Linux — mas só quando o programa não tem conserto.** É a diferença entre ajuda e proselitismo: sugerir LibreOffice para quem acabou de instalar o Office com sucesso é arrogância; ficar calado quando o programa depende de um dongle que nunca vai funcionar é abandonar a pessoa. | **FEITO** — só dispara no ramo `LIMITE` |
| **Classificar em `nativo` (faz a mesma coisa) e `parecido` (troca alguma coisa), e dizer o que muda.** "Abre os mesmos arquivos, mas macro do Excel não roda" é a frase honesta. | **FEITO** |
| **Reconhecer o que nunca vai funcionar antes de rodar**, lendo a tabela de importações do `.exe`: HASP/Sentinel, CodeMeter, `winusb`, DLL de driver. | **FEITO** — `limites.tsv` + `peinfo.py` |
| Sugerir alternativa web (SaaS) | **RECUSADO** — trocar um programa que roda offline por um que exige internet, numa loja, é piorar. |

## 6. Diagnóstico e honestidade

Onde o projeto de fato ganha da concorrência.

| Ideia | Veredito |
|---|---|
| **`tandem autoteste`** — o `doctor` *lista* o que existe; o autoteste *exercita*. Cinco defeitos de campo eram invisíveis para uma lista. | **FEITO** |
| **Ler o motivo da falha nas palavras do winetricks** em vez de despejar o log: disco cheio, data errada do relógio, DNS, checksum, falta `cabextract`. | **FEITO** |
| **Prova de entrega** — conferir se a DLL chegou, em vez de confiar no código de saída. | **FEITO** — v3.3 |
| **O índice do winetricks como auditor da tabela escrita à mão.** Inverter o `w_override_dlls` do próprio winetricks e comparar. Achou seis erros de tradução, um deles mandando instalar um gerenciador de fontes da Adobe no lugar do runtime do Visual C++. | **FEITO** |
| **O auditor tem um ponto cego declarado**: ele só lê `w_override_dlls`. Verbos que declaram as DLLs apenas no `title=` — o `vcrun2003` é um — têm zero entradas no índice. O gerador precisa ler também a lista entre parênteses do título. | **PRÓXIMO** — item 3 da fila |
| **Guardar as traduções suspeitas num arquivo** em vez de só reclamar na tela: é a lista de trabalho para consertar a tabela. | **FEITO** — v3.3 |
| **`tandem logs`** que abre o log mais recente sem o dono saber onde ele mora. | **FEITO** |
| Enviar o log para análise automática | **RECUSADO** — log de Wine contém caminhos, nomes de arquivo e às vezes nome de cliente. |

## 7. Instalar e preparar o ambiente

| Ideia | Veredito |
|---|---|
| **`tandem preparar`** — instalar Wine, winetricks, adb e Waydroid de uma vez, incluindo o repositório do Waydroid com chave e o `dpkg --add-architecture i386` na ordem certa. | **FEITO** |
| **Oferecer instalar o Wine na hora do duplo clique**, em vez de mandar abrir o terminal. O momento em que a pessoa quer resolver é aquele. | **FEITO** |
| **Não dá para instalar no `postinst`** — o `dpkg` segura a trava e o `apt-get` de dentro espera para sempre. | **FEITO** — é por isso que `preparar` é comando separado |
| **`tandem programas`** — o GNOME sob Wayland não relê o menu de aplicativos até sair e entrar na conta, e `update-desktop-database` não resolve. Sem uma lista própria, o dono instala e não acha. | **FEITO** |
| **Limpar atalho órfão** — `.desktop` cujo `.lnk` sumiu é botão que não abre nada. | **FEITO** |
| **Clonar um prefixo com `.NET` pronto** em vez de rodar `dotnet48` do zero (30 min, alta taxa de falha). | **DEPOIS** — exige cuidado extremo para nunca ler de prefixo protegido em uso, e um lugar de onde baixar o prefixo pronto |
| Empacotar o Wine dentro do `.deb` | **RECUSADO** — 400 MB, licenciamento, e nos tornaria responsáveis por atualizar o Wine. |

## 8. Android

| Ideia | Veredito |
|---|---|
| **Ler o `AndroidManifest.xml` binário sem SDK** e comparar `minSdkVersion` e ABIs com o Android que está rodando, *antes* de instalar. | **FEITO** — `apkinfo.py`, Python puro |
| **Parsear a saída do `waydroid app install`**, que retorna 0 mesmo falhando. | **FEITO** |
| **Esperar `sys.boot_completed`**, não `Session: RUNNING`. Com GAPPS são mais 20–60 s. | **FEITO** |
| **Registrar `.xapk`/`.apks`/`.apkm` como tipo MIME próprio** — sem isso o sistema vê um ZIP genérico e o duplo clique nunca chega no Tandem. | **FEITO** |
| **Dizer na cara que USB não existe dentro do Waydroid.** Impressora térmica, leitor de cartão, balança, leitor de código de barras: nada disso passa. Para uma loja, essa frase economiza uma tarde. | **FEITO** — está no README |
| Passar USB para o Waydroid | **RECUSADO** — não existe. Prometer isso seria mentira. |

## 9. Para o dono da loja

| Ideia | Veredito |
|---|---|
| **Nenhum caminho de erro termina em silêncio.** É a régua do projeto inteiro, e o defeito mais caro já encontrado (o zenity recusando acento em locale não gerado) apagava a interface inteira sem deixar rastro. | **FEITO** |
| **Português sem jargão.** `NO_MATCHING_ABIS` vira "este app é feito só para celular e não roda aqui". | **FEITO** |
| **Assumir a culpa quando a culpa é nossa.** "Instalei as dependências e ainda não abre" manda o dono procurar defeito numa máquina perfeita. | **FEITO** — v3.3 |
| **Dizer o tempo antes de gastar.** `.NET` leva meia hora; a pessoa precisa saber disso *antes* de clicar, não depois. | **FEITO** — está no nome amigável do verbo |
| **Impedir a máquina de suspender no meio de uma instalação longa** — suspender no meio corrompe o prefixo. | **FEITO** — `systemd-inhibit` |
| **Um botão "me manda o diagnóstico"** que gera um arquivo único para o dono mandar por WhatsApp para quem entende. | **PRÓXIMO** — é barato e resolve o suporte remoto, que hoje depende de ditar comandos por telefone |
| Assistente de primeira execução com várias telas | **RECUSADO** — a promessa do produto é *dois cliques*. Um assistente de boas-vindas é a negação dela. |

## 10. Engenharia

| Ideia | Veredito |
|---|---|
| **Hierarquia de evidência** (E0 acreditado → E1 estático → E2 testado → E3 exercitado → E4 em produção), com "pronto" exigindo ≥ E3. | **FEITO** — vinda do ProofGate, e é ela que produziu quase todos os consertos desta sessão |
| **Empacotador que não depende de `dpkg-deb`** — escreve o `ar` à mão e roda em qualquer SO. | **FEITO** |
| **Construção reproduzível**, conferida no CI. | **FEITO** |
| **CI que instala, configura e remove o pacote de verdade** num Ubuntu 24.04, que é a base do Zorin 18. | **FEITO** |
| **Os executáveis respeitarem `TANDEM_LIB`.** Com o caminho fixo em `/usr/lib/tandem` não havia como exercitar o laço principal sem instalar o pacote — e era justamente o laço que nunca tinha rodado. | **FEITO** — v3.3 |
| **Teste de mutação nos testes novos**: quebrar o código de propósito e confirmar que o teste reprova. Teste que não sabe falhar não prova nada. | **FEITO** — aplicado aos doze testes da v3.3 |
| **A suíte apontar para o repositório, nunca para o pacote instalado.** Sem isso, numa máquina com o Tandem instalado a suíte aprovava a versão antiga. | **FEITO** |

---

## A fila, em ordem

1. **`tandem dados`** e a cópia obrigatória antes dos três caminhos destrutivos.
2. **Sucesso em silêncio**: parar de tratar `exit 0` como "funcionou".
3. **Ponto cego do auditor**: ler também as DLLs declaradas no `title=`.
4. **Botão de diagnóstico** para mandar por WhatsApp.
5. Testar em campo o que ainda não rodou na máquina do dono: `preparar`,
   `desinstalar`, duplo clique num `.xapk` de verdade, e — o que mais importa —
   **um `.exe` que realmente falte alguma coisa**, para o laço
   roda→detecta→instala trabalhar pela primeira vez fora do teste.

## A pergunta que continua sem resposta

**Nenhum programa de loja de verdade jamais rodou nisto.** O único programa
instalado em campo foi o 7-Zip, que não depende de nada — por isso o laço
principal nunca precisou agir. Todo o resto deste documento é bem fundamentado e
bem testado, e nada disso substitui um sistema comercial real abrindo, ou não
abrindo, numa máquina de verdade.
