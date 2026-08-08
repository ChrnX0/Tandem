## O que muda

<!-- Uma ou duas frases. O porquê importa mais que o quê. -->

## Como você sabe que funciona

<!--
O projeto usa uma hierarquia de evidência, e "pronto" exige pelo menos E3:
  E1 estático (li o código)   E2 testado (a suíte cobre)
  E3 exercitado (rodei e olhei o resultado)   E4 funcionou na máquina de alguém
Diga qual nível você alcançou e como.
-->

## Antes de marcar como pronto

- [ ] `bash tests/run.sh` passa
- [ ] `python3 build.py --check` passa
- [ ] Se adicionei teste: quebrei o código de propósito e confirmei que ele reprova
- [ ] Se adicionei comando: está no `uso()`, no `man/tandem.1`, no `README.md` e no `LEIAME.md`
- [ ] Nenhum caminho de erro novo termina em silêncio
- [ ] Não escrevo em perfil Wine que o Tandem não criou
