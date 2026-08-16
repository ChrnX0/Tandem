#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Runs a command behind a REAL terminal, and answers its question.

    tests/terminal.py <answer> <command> [args...]

Prints whatever the command wrote, and exits with its status.

WHY THIS EXISTS. Ten places in this tree branch on `[ -t 0 ]` - the
confirmation prompt of five handlers, t_texto's read of standard input, and the
sudo path - and the suite could not reach any of them. `sem_ninguem` runs every
handler under `env -i` with no terminal, which is the OTHER side of the same
branch, so the whole terminal half was measured by nothing. That half is the
fallback that exists so that no path ends in silence, which makes it exactly
the wrong thing to leave unmeasured.

It is stdlib only, on purpose: `expect` and `unbuffer` are not installed on a
bare runner, and a test that skips itself on CI is a test that never runs. The
`pty` module has been in Python since 2.x and needs nothing.

A pty is not a pipe with a flag on it. The child gets a controlling terminal,
so `[ -t 0 ]`, `[ -t 1 ]` and `[ -t 2 ]` are all true - which is what makes
this cover t_tem_terminal as well as the prompts.

NOT NAMED pty.py, and that is not taste: a file with that name imports ITSELF
instead of the standard library module, and the first version of this failed
with "module 'pty' has no attribute 'fork'" on its very first run.

The answer is written ONCE, after a short settle, and then the read runs to
EOF. Writing before the child has drained its own startup output works because
the pty buffers it; waiting for a prompt string would tie the harness to the
wording of a message, and the wording is translated seven ways.
"""
import os
import pty
import select
import sys
import time


# 25s suits the suite, where every child is a shell one-liner. It is FATAL for
# the shop harness: winetricks dotnet48 alone takes about half an hour, and the
# first end-to-end run of tests/real-shop.sh killed Tandem at 25 seconds and
# reported status 255. A caller with a slow child sets TANDEM_PTY_LIMITE.
LIMITE_PADRAO = float(os.environ.get("TANDEM_PTY_LIMITE", "25"))


def executa(resposta, comando, limite=None):
    """(output, exit status) with the command on a real terminal."""
    if limite is None:
        limite = LIMITE_PADRAO
    pid, fd = pty.fork()
    if pid == 0:
        # The child. No exception may escape here - it would return a SECOND
        # copy of the test process to the caller, which is the classic fork
        # bug and looks like the suite passing twice.
        try:
            os.execvp(comando[0], comando)
        except Exception:
            os._exit(127)

    saida = []
    respondeu = False
    inicio = time.time()
    while True:
        if time.time() - inicio > limite:
            saida.append("\n[terminal.py: gave up after %gs]" % limite)
            break
        pronto, _, _ = select.select([fd], [], [], 0.2)
        if not respondeu and time.time() - inicio > 0.6:
            try:
                os.write(fd, (resposta + "\n").encode("utf-8"))
            except OSError:
                pass          # it already exited; nothing was waiting anyway
            respondeu = True
        if not pronto:
            continue
        try:
            pedaco = os.read(fd, 4096)
        except OSError:
            break             # the slave side closed: normal end of a pty read
        if not pedaco:
            break
        saida.append(pedaco.decode("utf-8", "replace"))

    os.close(fd)
    _, status = os.waitpid(pid, 0)
    codigo = os.waitstatus_to_exitcode(status) if hasattr(
        os, "waitstatus_to_exitcode") else (status >> 8)
    return "".join(saida), codigo


def main():
    if len(sys.argv) < 3:
        print("uso: terminal.py <resposta> <comando> [args...]", file=sys.stderr)
        return 2
    texto, codigo = executa(sys.argv[1], sys.argv[2:])
    sys.stdout.write(texto)
    return codigo


if __name__ == "__main__":
    sys.exit(main())
