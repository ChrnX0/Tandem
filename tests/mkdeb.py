#!/usr/bin/env python3
"""Generates synthetic .deb packages for the test suite.

The same reasoning as tests/mkapk.py: the reader has to be exercised on a real
binary format, not on a fixture that only looks like one. A .deb written here is
an actual ar archive with an actual gzipped control tarball, so debinfo.py walks
the same code path a package downloaded from a website takes.

It can also write the failures on purpose - a dependency that exists nowhere, a
foreign architecture, a truncated file - which is what makes the diagnosis
testable without downloading a broken package from somebody's website and hoping
it stays broken.

Usage:
    mkdeb.py <out.deb> [key=value ...]

Keys are control fields, with these defaults:
    Package=teste Version=1.0 Architecture=all Maintainer=... Description=...

    mkdeb.py /tmp/a.deb Depends='libssl1.1, libc6 (>= 2.34)'
    mkdeb.py /tmp/b.deb Architecture=arm64
    mkdeb.py /tmp/c.deb --compressao=xz      # control.tar.xz instead of .gz
"""
import gzip
import io
import lzma
import os
import sys
import tarfile

PADROES = [
    ("Package", "teste"),
    ("Version", "1.0"),
    ("Architecture", "all"),
    ("Maintainer", "Teste <teste@example.invalid>"),
    ("Installed-Size", "42"),
    ("Description", "pacote sintetico para teste\n Linha longa da descricao."),
]


def tar_de_controle(texto, compressao="gz"):
    bruto = io.BytesIO()
    with tarfile.open(fileobj=bruto, mode="w") as t:
        dados = texto.encode("utf-8")
        info = tarfile.TarInfo("./control")
        info.size = len(dados)
        info.mtime = 0
        info.mode = 0o644
        t.addfile(info, io.BytesIO(dados))
    cru = bruto.getvalue()
    if compressao == "gz":
        return "control.tar.gz", gzip.compress(cru, mtime=0)
    if compressao == "xz":
        return "control.tar.xz", lzma.compress(cru)
    return "control.tar", cru


def membro_ar(nome, dados):
    cab = b"%-16s%-12d%-6d%-6d%-8o%-10d`\n" % (
        nome.encode("ascii"), 0, 0, 0, 0o100644, len(dados))
    saida = cab + dados
    if len(dados) % 2:
        saida += b"\n"
    return saida


def escreve(caminho, campos, compressao="gz"):
    texto = "".join("%s: %s\n" % (k, v) for k, v in campos)
    nome_ctl, ctl = tar_de_controle(texto, compressao)
    # An empty data tarball: nothing here ever installs the package, and a
    # payload would only make the fixtures bigger.
    vazio = io.BytesIO()
    with tarfile.open(fileobj=vazio, mode="w"):
        pass
    dados_tar = gzip.compress(vazio.getvalue(), mtime=0)
    with open(caminho, "wb") as f:
        f.write(b"!<arch>\n")
        f.write(membro_ar("debian-binary", b"2.0\n"))
        f.write(membro_ar(nome_ctl, ctl))
        f.write(membro_ar("data.tar.gz", dados_tar))


def main():
    args = [a for a in sys.argv[1:]]
    if not args:
        print(__doc__)
        return 2
    compressao = "gz"
    restantes = []
    for a in args:
        if a.startswith("--compressao="):
            compressao = a.split("=", 1)[1]
        else:
            restantes.append(a)
    caminho = restantes.pop(0)
    campos = dict(PADROES)
    ordem = [k for k, _ in PADROES]
    for a in restantes:
        if "=" not in a:
            continue
        k, v = a.split("=", 1)
        if k not in campos:
            ordem.append(k)
        campos[k] = v
    escreve(caminho, [(k, campos[k]) for k in ordem], compressao)
    print(caminho)
    return 0


if __name__ == "__main__":
    sys.exit(main())
