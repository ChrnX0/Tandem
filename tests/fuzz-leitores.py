#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Feeds the six readers CORRUPTED versions of valid files, and insists they
answer instead of crashing.

    python3 tests/fuzz-leitores.py            # a few thousand mutations
    python3 tests/fuzz-leitores.py 20000      # more
    python3 tests/fuzz-leitores.py --semente 7 --rodadas 500

WHY THIS EXISTS. src/lib/*.py parse binary formats that arrived FROM THE
INTERNET, on a machine belonging to somebody who is not a programmer. Random
bytes are the easy case - every reader dies on the magic number and says so.
What breaks a parser is a file that gets PAST the magic and then lies: a length
field larger than the file, an offset pointing past the end, a count of
2**31 entries, a zip whose central directory disagrees with its local headers.

That is not a hypothetical here. CLAUDE.md already records two of exactly this
shape - "cap the declared size: a decompressor told to allocate a hostile
number takes the machine down", and a .deb truncated on a member boundary that
parses cleanly and looks perfect. Both were found by hand, one at a time.

THE CONTRACT, which is what this asserts:

  1. It must not raise. A traceback is English jargon on a shop counter, and
     the whole reason the ERRO field carries a TOKEN is that t_erro_do_leitor
     turns tokens into sentences. An exception has no token.
  2. It must not hang. A shopkeeper double-clicks a file; nothing may sit
     there forever.
  3. It must not eat the machine. A reader that allocates what a hostile
     header asks for takes the till down with it.
  4. Whatever it prints must be parseable KEY=VALUE, because that is what the
     shell reads. Half a line is worse than an error.

Deterministic: same seed, same mutations, so a failure can be reproduced
exactly. Failures are written out as files, because "mutation 4713 of seed 1"
is not something anybody can debug.
"""
import io
import os
import random
import resource
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEITORES = {
    "peinfo.py": (".exe",),
    "debinfo.py": (".deb",),
    "rpminfo.py": (".rpm",),
    "jarinfo.py": (".jar",),
    "appimageinfo.py": (".AppImage",),
    "apkinfo.py": (".apk", ".xapk", ".apks", ".apkm"),
}

# A reader is given this long and this much memory. Both are generous for
# reading a header and mean the machine survives a bad one.
SEGUNDOS = 20
MEMORIA_MB = 512


def limita():
    """Runs in the child, between fork and exec."""
    lim = MEMORIA_MB * 1024 * 1024
    try:
        resource.setrlimit(resource.RLIMIT_AS, (lim, lim))
    except (ValueError, OSError):
        pass          # not fatal: the timeout still bounds the damage


def muta(dados, rnd):
    """One corrupted copy. The four shapes that actually break parsers."""
    b = bytearray(dados)
    if not b:
        return bytes(b)
    escolha = rnd.randrange(5)
    if escolha == 0:
        # Bit flips, biased to the HEAD where the headers live.
        for _ in range(rnd.randrange(1, 9)):
            i = rnd.randrange(min(len(b), 512)) if rnd.random() < 0.7 \
                else rnd.randrange(len(b))
            b[i] ^= 1 << rnd.randrange(8)
    elif escolha == 1:
        # Truncation, including on a boundary - the .deb case CLAUDE.md
        # records as parsing cleanly and looking perfect.
        b = b[:rnd.randrange(0, len(b))]
    elif escolha == 2:
        # A hostile 32-bit number written over a field. This is the one that
        # turns into "allocate 4 GB".
        if len(b) >= 4:
            i = rnd.randrange(len(b) - 3)
            b[i:i + 4] = rnd.choice([
                b"\xff\xff\xff\xff", b"\xff\xff\xff\x7f",
                b"\x00\x00\x00\x80", b"\xfe\xff\xff\xff"])
    elif escolha == 3:
        # A hostile 16-bit count: number of sections, number of imports.
        if len(b) >= 2:
            i = rnd.randrange(len(b) - 1)
            b[i:i + 2] = rnd.choice([b"\xff\xff", b"\xff\x7f", b"\x00\x80"])
    else:
        # Bytes spliced in from elsewhere in the same file: keeps the magic
        # intact while making the structure disagree with itself.
        if len(b) > 16:
            n = rnd.randrange(1, min(64, len(b)))
            src = rnd.randrange(len(b) - n)
            dst = rnd.randrange(len(b) - n)
            b[dst:dst + n] = b[src:src + n]
    return bytes(b)


def roda(leitor, caminho):
    """(veredicto, detalhe). veredicto is ok / EXPLODIU / TRAVOU / SUJO."""
    try:
        p = subprocess.run(
            [sys.executable, os.path.join(RAIZ, "src", "lib", leitor), caminho],
            capture_output=True, timeout=SEGUNDOS, preexec_fn=limita)
    except subprocess.TimeoutExpired:
        return "TRAVOU", "still running after %ds" % SEGUNDOS
    except Exception as e:                      # noqa: BLE001 - the harness must not die
        return "EXPLODIU", "the harness could not run it: %r" % e

    err = p.stderr.decode("utf-8", "replace")
    if "Traceback (most recent call last)" in err:
        ultima = [l for l in err.strip().splitlines() if l.strip()][-1]
        return "EXPLODIU", ultima.strip()
    saida = p.stdout.decode("utf-8", "replace")
    # split("\n"), NOT splitlines(): Python's splitlines also breaks on form
    # feed, vertical tab and a handful of unicode separators, and the SHELL
    # that reads this output breaks only on \n. Using splitlines here reported
    # a DLL name containing 0x0c as a broken line - a finding this tool
    # invented, which is worse than one it misses.
    for linha in saida.split("\n"):
        if linha.strip() and "=" not in linha:
            return "SUJO", "a line that is not KEY=VALUE: %r" % linha[:70]
    return "ok", ""


def fixtures(tmp):
    """Valid files to corrupt, generated the same way the suite generates them."""
    arte = os.path.join(tmp, "artefatos")
    os.makedirs(arte, exist_ok=True)
    subprocess.run([sys.executable, os.path.join(RAIZ, "tests", "mkapk.py"), arte],
                   capture_output=True)
    subprocess.run([sys.executable, os.path.join(RAIZ, "tests", "mkdeb.py"),
                    os.path.join(arte, "simples.deb")], capture_output=True)
    achados = []
    for nome in sorted(os.listdir(arte)):
        caminho = os.path.join(arte, nome)
        if not os.path.isfile(caminho) or os.path.getsize(caminho) == 0:
            continue
        for leitor, exts in LEITORES.items():
            if nome.endswith(exts):
                achados.append((leitor, caminho))
    return achados


def main():
    args = sys.argv[1:]
    rodadas, semente = 2000, 1
    # The value after a flag has to be SKIPPED, not looked at again. Written
    # without the skip, "--rodadas 4000 --semente 3" ran THREE mutations: the
    # bare-number shortcut swallowed the seed's value as a round count, and the
    # tool reported "every one answered" having done essentially nothing. A
    # fuzzer that silently runs three cases is worse than no fuzzer, because it
    # is green.
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--semente" and i + 1 < len(args):
            semente = int(args[i + 1]); i += 2; continue
        if a == "--rodadas" and i + 1 < len(args):
            rodadas = int(args[i + 1]); i += 2; continue
        if a.isdigit():
            rodadas = int(a)
        i += 1

    tmp = tempfile.mkdtemp(prefix="tandem-fuzz-")
    pares = fixtures(tmp)
    if not pares:
        print("no fixtures to corrupt - is tests/mkapk.py there?")
        return 2
    print("%d valid files, %d mutations, seed %d" % (len(pares), rodadas, semente))

    guardados = os.path.join(tmp, "falhas")
    os.makedirs(guardados, exist_ok=True)
    rnd = random.Random(semente)
    falhas, vistos = [], set()
    for n in range(rodadas):
        leitor, origem = pares[rnd.randrange(len(pares))]
        dados = io.open(origem, "rb").read()
        ruim = muta(dados, rnd)
        alvo = os.path.join(tmp, "caso" + os.path.splitext(origem)[1])
        io.open(alvo, "wb").write(ruim)
        veredicto, detalhe = roda(leitor, alvo)
        if veredicto == "ok":
            continue
        # One example per distinct complaint: a thousand copies of the same
        # traceback is a report nobody reads.
        chave = (leitor, veredicto, detalhe[:90])
        if chave in vistos:
            continue
        vistos.add(chave)
        guardado = os.path.join(guardados, "%s-%d%s"
                                % (leitor.replace(".py", ""), n,
                                   os.path.splitext(origem)[1]))
        io.open(guardado, "wb").write(ruim)
        falhas.append((leitor, veredicto, detalhe, guardado))
        print("  %-8s %-16s %s" % (veredicto, leitor, detalhe[:88]))
        print("           saved: %s" % guardado)

    print()
    if not falhas:
        print("%d mutations, every one answered: no traceback, no hang, no half line"
              % rodadas)
        return 0
    print("%d distinct failures over %d mutations" % (len(falhas), rodadas))
    return 1


if __name__ == "__main__":
    sys.exit(main())
