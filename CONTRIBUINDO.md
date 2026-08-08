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
[issue](https://github.com/ChrnX0/Tandem/issues/new?template=lista.yml):

```bash
tandem contribuir /caminho/do/programa.exe
```

A linha não carrega nome de arquivo, caminho, seu usuário, o nome do
computador, endereço de rede nem uma linha de log — e o Tandem se recusa a
gerá-la se alguma dessas coisas aparecer. O que vai é uma impressão digital do
arquivo, a arquitetura, e quais componentes do Windows resolveram. O formato
inteiro está em [docs/FORMATO-LISTA.md](docs/FORMATO-LISTA.md).

**Não deu certo?** Rode isto e anexe o arquivo:

```bash
tandem socorro
```

Ele junta diagnóstico, autoteste, o que o Tandem aprendeu e os registros
técnicos num arquivo só. **Dê uma olhada antes de anexar**: ele mostra caminhos
de arquivos da sua máquina.

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
bash tests/run.sh            # 289 testes, sem Wine, sem Waydroid, sem instalar
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

Antes de propor, dê uma olhada em [docs/IDEIAS.md](docs/IDEIAS.md). São 52
ideias com veredito, e **as recusadas trazem o motivo escrito**. Metade das
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
docs/IDEIAS.md            o ideário, com veredito
docs/FORMATO-LISTA.md     o formato da lista da comunidade
```

## Licença

MIT. Ao contribuir, você concorda em licenciar sua contribuição nos mesmos
termos.
