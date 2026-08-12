# Como colaborar com o Tandem

[English](CONTRIBUTING.md)

Obrigado por olhar. Este documento é curto de propósito: a maior contribuição
que alguém pode fazer aqui não exige escrever uma linha de código.

## A contribuição mais valiosa: dizer o que aconteceu

O Tandem tem um problema honesto — **quase nenhum programa comercial de verdade
jamais rodou nele**. O laço que detecta dependências foi exercitado com Wine e
`winetricks` reais, mas contra binários de teste, não contra o sistema de uma
loja de verdade em cima de um balcão.

Cada relato de programa real vale mais que uma funcionalidade nova.

**Deu certo?** Rode isto e cole a linha numa
[issue](https://github.com/ChrnX0/Tandem/issues/new?template=list.yml):

```bash
tandem contribuir /caminho/do/programa.exe
```

A linha não carrega nome de arquivo, caminho, seu usuário, o nome do
computador, endereço de rede nem uma linha de log — e o Tandem se recusa a
gerá-la se alguma dessas coisas aparecer. O que vai é uma impressão digital do
arquivo, a arquitetura, e quais componentes do Windows resolveram. O formato
inteiro está em [docs/LIST-FORMAT.md](docs/LIST-FORMAT.md).

**Não deu certo?** Rode isto e anexe o arquivo:

```bash
tandem socorro
```

Ele junta diagnóstico, autoteste, o que o Tandem aprendeu e os registros
técnicos num arquivo só. **Dê uma olhada antes de anexar**: ele mostra caminhos
de arquivos da sua máquina.

## Traduzir: a contribuição útil mais fácil

Cinco dos sete catálogos nunca foram lidos por quem fala o idioma. Eles estão
marcados assim, e o Tandem diz isso na cara de quem escolhe um deles:

| | revisado por falante |
|---|---|
| inglês, português | sim |
| espanhol, francês, chinês simplificado, híndi, árabe | **não** |

O risco não é erro de gramática. É a frase gramaticalmente perfeita que cai
errado — um aviso sobre pacote sem assinatura que sai burocrático em vez de
grave, e a pessoa clica em Instalar quando não devia. Nenhum teste pega isso.
Um falante lendo por dez minutos pega.

**Os arquivos são `.po` de gettext comuns**, em `po/`, então Poedit, Lokalize,
Weblate, `msgmerge` e qualquer outra ferramenta de tradução funcionam neles.
Nada para aprender, nada para instalar se você já tem uma:

```bash
poedit po/es.po          # ou abra num editor de texto qualquer
python3 tools/po-para-catalogo.py    # regera os catálogos que vão no pacote
bash tests/run.sh
```

Quando você tiver lido um arquivo inteiro, mude o cabeçalho dele:

```
"X-Reviewed-By-Speaker: yes\n"
```

e o asterisco desaparece do `tandem idioma`. Esse cabeçalho é o mecanismo
inteiro — publicar tradução que ninguém leu é defensável; publicar sem dizer,
não é.

Duas coisas do formato que não são opcionais:

- **A substituição é `{1}` `{2}`, não `%s`.** Caminhos e versões carregam sinal
  de porcentagem; existe um teste com uma pasta chamada `50% off`. Mantenha os
  números, e troque a ordem deles livremente se o seu idioma pedir outra.
- **Nunca traduza um valor que vai para arquivo.** `abriu`, `confirmado`,
  `so-abriu`, `RESOLVERAM`, `CONFIANCA`, `nativo`, `parecido` são formato em
  disco, e os nomes dos comandos (`preparar`, `programas`, `dados`) são o que
  as pessoas digitam. Traduzir um quebra em silêncio arquivos de memória já
  escritos na máquina de alguém, e quebra um comando copiado de um fórum.

Existe um segundo lugar com prosa: `src/lib/alternativas.<idioma>.tsv` e
`limites.<idioma>.tsv`. São tabelas separadas por tabulação. **Só mexa nas
últimas colunas** — a primeira é o padrão que casa e a segunda é a classe que
escolhe a moldura da mensagem. Um teste confere as duas, porque uma linha
reordenada responderia sobre o programa errado.

## Se você for mexer no código

### Antes de qualquer coisa, leia o `CLAUDE.md`

Ele não é um arquivo de IA — é o caderno do projeto. Tem as regras invioláveis e
uma lista de fatos já apurados que custaram caro para descobrir. Metade dos
problemas óbvios já tem resposta lá.

### As cinco regras que não se quebram

1. **Nunca escrever num perfil Wine que o Tandem não criou.** O projeto nasceu
   numa máquina que também roda um sistema de frente de caixa em perfil próprio.
   Instalar dependência dentro de um ambiente de produção que funciona é pior do
   que não automatizar nada.
2. **Mensagem ao usuário em português, sem jargão.** `NO_MATCHING_ABIS` vira
   "este app é feito só para celular e não roda aqui".
3. **`set -e` só no empacotador, nunca nos executáveis.** Os laços de espera
   dependem de comandos que falham de propósito.
4. **Não repetir instalação já paga.** O `dotnet48` leva meia hora.
5. **O empacotador não pode depender de `dpkg-deb`.** O `build.py` escreve o
   arquivo `ar` à mão e roda em qualquer sistema operacional.

### A régua de qualidade

> Nenhum caminho de erro pode terminar em silêncio.

"Cliquei duas vezes e não aconteceu nada" é tratado como defeito, não como
limitação. Se o seu código pode falhar, ele tem que dizer o que houve, em
português, num lugar onde a pessoa vai ver.

### Rodar e testar

```bash
python3 build.py --check     # empacota; não precisa de Debian nem de dpkg-deb
bash tests/run.sh            # 309 testes, sem Wine, sem Waydroid, sem instalar
```

A suíte carrega as bibliotecas direto de `src/lib` e gera pacotes Android
sintéticos com `AndroidManifest.xml` binário de verdade, então o leitor de
manifesto roda no mesmo caminho de código de um APK real. Ferramenta opcional
ausente é pulada, não reprovada.

**Rode a suíte antes de abrir o PR.** O CI roda ela, mais `lintian` sem nenhum
aviso, mais um ciclo real de instalar–configurar–remover num Ubuntu 24.04.

### O teste tem que saber reprovar

Antes de considerar um teste pronto, **quebre o código de propósito e confirme
que ele falha**. Teste que passa com o código quebrado não prova nada, e este
projeto já teve um portão de evidência que passava verde sem rodar um teste
sequer.

### Evidência

O projeto usa uma hierarquia explícita, e "pronto" exige pelo menos E3:

| | |
|---|---|
| E0 | acreditado |
| E1 | estático (li o código) |
| E2 | testado (a suíte cobre) |
| E3 | exercitado (rodei e olhei o resultado) |
| E4 | em produção (funcionou na máquina de alguém) |

A diferença entre E1 e E3 não é filosofia. Cinco defeitos encontrados em campo
eram invisíveis para uma leitura e visíveis para um exercício — entre eles uma
janela de erro que nunca abria e uma barra de progresso que derrubava o programa
inteiro.

## O que já foi recusado

Antes de propor, dê uma olhada em [docs/IDEAS.md](docs/IDEAS.md) — em inglês,
porque é o documento que gente de fora lê. São 52 ideias com veredito, e **as
recusadas trazem o motivo escrito**. Metade das
ideias óbvias já foi recusada por uma razão concreta — backup automático
agendado, sincronizar dados para a nuvem, assistente de primeira execução. Se
você discorda de uma recusa, ótimo: traga o argumento novo, que é exatamente
para isso que o motivo está escrito.

## Mapa rápido

```
build.py                  empacotador (ar + tar.gz manuais)
src/bin/tandem            CLI + painel; 20 comandos
src/bin/tandem-exe        o laço roda→detecta→instala→repete
src/bin/tandem-apk        pré-voo + install; xapk/apks via adb
src/lib/common.sh         mensagens, locale, prefixos, dados, memória, lista
src/lib/winedeps.sh       DLL → verbo do winetricks
src/lib/peinfo.py         lê a tabela de importações do PE, sem executar
src/lib/apkinfo.py        lê AndroidManifest binário, Python puro
tests/run.sh              a suíte
docs/IDEAS.md             o ideário, com veredito (em inglês)
docs/LIST-FORMAT.md       o formato da lista da comunidade
```

## Licença

MIT. Ao contribuir, você concorda em licenciar sua contribuição nos mesmos
termos.

### Onde as mensagens ficam, e o que rodar

```
po/en.po            O INGLÊS. Mexer numa mensagem é mexer neste arquivo.
po/<idioma>.po      as traduções
po/tandem.pot       modelo gerado; comece um idioma novo com msginit
po/LINGUAS          os idiomas que vão no pacote
src/lib/idiomas/    catálogos GERADOS - nunca edite estes à mão
```

Adicionar, mudar ou remover uma mensagem é um caminho, e só um:

```bash
$EDITOR po/en.po                     # 1. o inglês
python3 tools/atualiza-po.py         # 2. propaga para os sete
python3 tools/po-para-catalogo.py    # 3. regera o que vai no pacote
bash tests/run.sh                    # 4.
```

O passo 2 é o que se paga. Uma chave cujo **inglês mudou** é marcada `#, fuzzy`
em todos os idiomas, e o passo 3 então **descarta** entrada fuzzy — de modo que
a pessoa lê inglês em vez de uma frase que descreve um comportamento que o
Tandem não tem mais. Era essa a falha que o formato anterior não conseguia nem
detectar. O passo 2 também preserva todas as linhas de cabeçalho que encontra,
inclusive `Last-Translator` e `X-Generator`, porque apagar o nome de quem ajudou
é como se garante que a pessoa não volta.

Para começar um idioma que ainda não existe:

```bash
echo pl >> po/LINGUAS
msginit -i po/tandem.pot -l pl -o po/pl.po    # ou copie o tandem.pot à mão
python3 tools/atualiza-po.py
```

Tradução faltando é segura — cai para o inglês — então idioma pela metade é
contribuição útil, não coisa quebrada.

### Como pôr isso no Weblate

Nada no repositório precisa mudar. Aponte um componente do Weblate para:

| campo | valor |
|---|---|
| Formato do arquivo | `gettext PO file` |
| Máscara de arquivos | `po/*.po` |
| Base monolíngue | *(deixe vazio — estes são bilíngues)* |
| Modelo para novas traduções | `po/tandem.pot` |
| Adicionar nova tradução | `Usar modelo` |
| Script pós-commit | `python3 tools/po-para-catalogo.py` |

O script pós-commit importa: sem ele o Weblate comita um `.po` e o catálogo que
vai no pacote fica atrás — e o CI vai dizer isso no próximo push.
