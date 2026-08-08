#!/usr/bin/env python3
"""Reads the label of an .rpm WITHOUT installing anything.

An .rpm on a Debian-based system is a dead end, and today it is a SILENT dead
end: nothing owns the type, so the double click does nothing at all. The owner
downloaded the file from the program's own website, where it sat next to the
.deb under a heading he could not read, and now his computer is ignoring him.

The honest answer needs three things out of the file - the name, the version and
which distribution it was built for - and none of them requires rpm to be
installed. With the name in hand the answer stops being "no" and becomes "this
one is for Fedora; the same program is in your own system, install it like
this", which is a different conversation.

Converting it with alien is deliberately NOT offered. A converted package
carries the wrong dependency names, skips the scripts that set the program up,
and installs files where this distribution does not keep them. It produces
something that looks installed and is not, which is the exact failure mode this
project exists to prevent.

Usage:  rpminfo.py <file.rpm>
Output: KEY=VALUE lines, the same contract as peinfo.py and apkinfo.py

PACOTE=<name>
VERSAO=<version-release>
ARQUITETURA=<x86_64|noarch|aarch64|i686...>
DISTRIBUICAO=<Distribution, or the Vendor when there is no Distribution>
DESCRICAO=<summary, one line>
REQUER=<requirement names, comma separated, internal ones dropped>
ERRO=<message, if something failed>
"""
import os
import struct
import sys

MAGIC_LEAD = b"\xed\xab\xee\xdb"
MAGIC_CAB = b"\x8e\xad\xe8"

TAG_NOME = 1000
TAG_VERSAO = 1001
TAG_LANCAMENTO = 1002
TAG_RESUMO = 1004
TAG_DISTRIBUICAO = 1010
TAG_FORNECEDOR = 1011
TAG_ARQUITETURA = 1022
TAG_REQUER = 1049

TIPO_STRING = 6
TIPO_ARRAY = 8
TIPO_I18N = 9

# An rpm header is a few hundred entries. A file claiming far more is malformed,
# and walking it would be reading the rest of the disk as if it were an index.
TETO_ENTRADAS = 100000


class RpmRuim(Exception):
    pass


def cabecalho(dados, pos):
    """(entries, store, position after this header).

    An rpm header is a fixed 16-byte preamble, an index of 16-byte entries, and
    a blob the entries point into. There are two of them in a file - the
    signature and the real one - with the same shape.
    """
    if pos + 16 > len(dados):
        raise RpmRuim("arquivo incompleto: o cabecalho nao cabe no arquivo")
    if dados[pos:pos + 3] != MAGIC_CAB:
        raise RpmRuim("cabecalho rpm nao reconhecido")
    n, tam = struct.unpack_from(">II", dados, pos + 8)
    if n > TETO_ENTRADAS:
        raise RpmRuim("cabecalho rpm com %d entradas: arquivo malformado" % n)
    inicio_indice = pos + 16
    inicio_loja = inicio_indice + n * 16
    fim = inicio_loja + tam
    if fim > len(dados):
        raise RpmRuim("arquivo incompleto: o pacote termina antes do que ele diz")
    entradas = []
    for i in range(n):
        p = inicio_indice + i * 16
        entradas.append(struct.unpack_from(">iiii", dados, p))
    return entradas, dados[inicio_loja:fim], fim


def valor(entradas, loja, alvo):
    """The value of one tag: a string, or a list of strings for an array."""
    for tag, tipo, off, cont in entradas:
        if tag != alvo:
            continue
        if off < 0 or off > len(loja):
            return None
        if tipo in (TIPO_STRING, TIPO_I18N):
            fim = loja.find(b"\0", off)
            if fim < 0:
                fim = len(loja)
            return loja[off:fim].decode("utf-8", "replace")
        if tipo == TIPO_ARRAY:
            fora = []
            p = off
            for _ in range(max(0, min(cont, TETO_ENTRADAS))):
                fim = loja.find(b"\0", p)
                if fim < 0:
                    break
                fora.append(loja[p:fim].decode("utf-8", "replace"))
                p = fim + 1
            return fora
        return None
    return None


def inspecionar(caminho):
    with open(caminho, "rb") as f:
        dados = f.read()
    if len(dados) < 96 or dados[:4] != MAGIC_LEAD:
        raise RpmRuim("nao e um arquivo .rpm")
    # The lead is a fixed 96 bytes, then the signature header, then the real one.
    # The signature is padded so the header that follows starts on an 8-byte
    # boundary; skipping that padding is the one step that is easy to get wrong
    # and produces "unrecognised header" on a perfectly good file.
    _, _, depois_assinatura = cabecalho(dados, 96)
    resto = depois_assinatura + ((8 - (depois_assinatura % 8)) % 8)
    entradas, loja, _ = cabecalho(dados, resto)

    nome = valor(entradas, loja, TAG_NOME) or ""
    versao = valor(entradas, loja, TAG_VERSAO) or ""
    lancamento = valor(entradas, loja, TAG_LANCAMENTO) or ""
    arq = valor(entradas, loja, TAG_ARQUITETURA) or "?"
    dist = valor(entradas, loja, TAG_DISTRIBUICAO) or valor(entradas, loja, TAG_FORNECEDOR) or ""
    resumo = valor(entradas, loja, TAG_RESUMO) or ""
    requer = valor(entradas, loja, TAG_REQUER) or []
    if isinstance(requer, str):
        requer = [requer]
    # Three kinds of requirement are dropped, all for the same reason: naming
    # them to the owner would be noise piled on top of a dead end. rpmlib(...)
    # and config(...) are the package manager talking to itself; a bare path is
    # a file dependency; and libfoo.so.6(GLIBC_2.34)(64bit) is a linker-level
    # requirement, not a package anybody installs by name.
    requer = [r for r in requer
              if r and not r.startswith(("rpmlib(", "config(", "/"))
              and ".so" not in r and "(" not in r]

    cheia = versao + ("-" + lancamento if lancamento else "")
    return nome, cheia, arq, dist, resumo, sorted(set(requer))


def uma_linha(s):
    return " ".join((s or "").split())


def main():
    if len(sys.argv) < 2:
        print("ERRO=uso: rpminfo.py <arquivo>")
        return 2
    caminho = sys.argv[1]
    if not os.path.isfile(caminho):
        print("ERRO=arquivo nao encontrado")
        return 2
    try:
        nome, versao, arq, dist, resumo, requer = inspecionar(caminho)
    except RpmRuim as e:
        print("ERRO=%s" % e)
        return 1
    except Exception as e:
        print("ERRO=%s" % str(e).replace("\n", " ")[:200])
        return 1

    print("PACOTE=%s" % uma_linha(nome))
    print("VERSAO=%s" % uma_linha(versao))
    print("ARQUITETURA=%s" % uma_linha(arq))
    print("DISTRIBUICAO=%s" % uma_linha(dist))
    print("DESCRICAO=%s" % uma_linha(resumo)[:200])
    print("REQUER=%s" % ",".join(requer[:40]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
