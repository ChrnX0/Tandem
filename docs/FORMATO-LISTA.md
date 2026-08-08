# O formato da lista da comunidade

A ideia: um Tandem que faz um programa funcionar publica o que aprendeu, e
todos os outros Tandems recebem essa lição sozinhos — do mesmo jeito que um
bloqueador de anúncios recebe as listas de filtro.

A escolha de engenharia que faz isso ser viável: **a lista é um arquivo de
texto estático**, buscado por HTTPS, não uma API. É por isso que o EasyList
sobrevive há vinte anos com orçamento de voluntário e um serviço próprio não
sobreviveria: arquivo estático não tem servidor caindo, não tem conta, não tem
banco de dados, não tem custo por usuário, e pode ser espelhado por qualquer um.

## As duas metades, e por que elas são assimétricas

| | Como funciona | Por quê |
|---|---|---|
| **Descer** (ler a lista) | Automático, quando o dono liga | É só um `GET` de um arquivo público. Nada da máquina sai. |
| **Subir** (contribuir) | O Tandem **monta** o registro; **quem envia é o dono** | A máquina de uma loja não fala com servidor nenhum por decisão de um automatismo. |

Essa assimetria não é preguiça — é a regra nº 1 do projeto aplicada à rede.
Contribuição automática significaria uma máquina de produção mandando dados
para fora sem ninguém pedir, e "só dados inofensivos" é uma promessa que
alguém quebra na primeira vez que um caminho de arquivo entra por engano.

## O registro

Uma linha por programa conhecido, campos separados por TAB. Formato de linha
única, legível, `grep`ável e mesclável — os mesmos motivos que fazem as listas
de filtro serem texto.

```
identidade  arch  verbos          reprovados   confianca   maquinas  visto       nota
```

| Campo | O que é | Exemplo |
|---|---|---|
| `identidade` | `sha256` de tamanho + primeiro e último MiB do arquivo | `9f2a...c1` |
| `arch` | `32`, `64` ou `arm64`, lido do cabeçalho PE | `64` |
| `verbos` | verbos do winetricks que resolveram, por vírgula | `vcrun2022,dotnet48` |
| `reprovados` | verbos que foram instalados e **não** resolveram | `vcrun6` |
| `confianca` | `confirmado`, `so-abriu` ou `reprovado` | `confirmado` |
| `maquinas` | em quantas máquinas essa mesma lição se repetiu | `340` |
| `visto` | data do relato mais recente, `AAAA-MM` | `2026-08` |
| `nota` | uma frase em português, ou vazio | `precisa da versão de 32 bits` |

Campo vazio é `-`. Linha começando com `#` é comentário. A primeira linha
declara a versão do formato:

```
# TANDEM-LISTA 1
```

### A identidade é do ARQUIVO, não do usuário

`t_memoria_id` já existia e serve exatamente para isto: `sha256` de
`tamanho + primeiro MiB + último MiB`. Ela identifica o instalador do sistema
de PDV tal, versão tal — a **mesma** em qualquer máquina do mundo que tenha o
mesmo arquivo. Não passa por ela nem o nome do arquivo, nem a pasta, nem o
usuário, nem a máquina. Duas lojas diferentes com o mesmo sistema produzem a
mesma identidade e a contagem `maquinas` sobe; nenhuma das duas fica sabendo
da outra, e ninguém de fora consegue voltar da identidade para o arquivo sem
já ter o arquivo.

### O que NUNCA entra numa contribuição

Isto é a especificação, não uma recomendação — o `tandem contribuir` recusa a
gerar o registro se alguma coisa daqui aparecer:

- caminho de arquivo, nome de arquivo, nome de pasta
- nome de usuário, nome da máquina, endereço IP ou MAC
- conteúdo de log
- qualquer coisa dentro do prefixo Wine
- data com dia (só ano e mês — dia identifica)

O que entra são fatos sobre o **binário** (que qualquer um com o mesmo arquivo
apura sozinho) e sobre **quais verbos do winetricks resolveram** — que é
conhecimento público sobre software público.

## Por que a confiança viaja junto

Sem o campo `confianca`, "o processo terminou sem erro" e "uma pessoa olhou a
tela e disse que estava certo" chegariam do outro lado com o mesmo peso. Como
o modo de falha característico do Wine com software comercial é **abrir e
estar sutilmente errado**, uma lista sem esse campo espalharia lições erradas
com a mesma eficiência com que espalha as certas — e mais rápido, porque erro
não dá trabalho de produzir.

## O que a lista NÃO faz

- **Não instala nada sozinha.** Ela vira sugestão; o Tandem continua
  perguntando. Receita não é ordem, e lista de terceiro menos ainda.
- **Não traz comando.** Todo verbo é validado contra a lista de verbos que o
  `winetricks` desta máquina conhece antes de ser usado. Entrada vinda de fora
  não pode carregar execução.
- **Não sobe nada sozinha.** Ver a tabela acima.
