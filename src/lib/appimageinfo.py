#!/usr/bin/env python3
"""Reads the label of an AppImage WITHOUT running anything.

An AppImage is an ELF binary with a filesystem glued to its end. Everything
that decides whether it can run at all is in the first sixty bytes: the
architecture it was compiled for and which of the two AppImage generations it
belongs to. Reading that beforehand is the difference between "nothing
happened" and "this file is for another kind of processor".

The one check worth more than all the others: whether the file is COMPLETE. A
half-finished download is the most common way an AppImage fails for a lay
user, and it fails looking exactly like a broken program. The end of the ELF
section table is where the payload starts - the same number the runtime's own
--appimage-offset prints - and the payload header says how many bytes it
should have. If the file is shorter than that, nothing else needs
investigating.

Usage:  appimageinfo.py <file.AppImage>
Output: KEY=VALUE lines, the same contract as peinfo.py and apkinfo.py

TIPO=1|2|?
ARQUITETURA=x86_64|i386|aarch64|armhf|riscv64|ppc64le|?
DESLOCAMENTO=<where the payload starts, empty if it cannot be worked out>
CARGA=squashfs|iso9660|?
COMPLETO=1|0|?          1 = the payload fits in the file, 0 = truncated
ERRO=<token>[|<data>]  when something failed; see t_erro_do_leitor
   The field carries a TOKEN, never a sentence. It used to carry Portuguese
   prose, and the handler printed it straight to the owner - so this file held
   user-facing messages that no translation tool in the tree had ever opened,
   and a raw Python exception reached a shop owner in English. The shell turns
   a token into a sentence in the owner's language; an unknown token is logged
   and answered with a generic one, because a reader that learns a new failure
   must not be able to produce silence.
"""
import os
import struct
import sys

# e_machine, from the ELF specification. The names are the ones the user's own
# "uname -m" prints, so the comparison downstream is a string comparison and
# not a table nobody can check.
MAQUINAS = {
    0x03: "i386",
    0x3E: "x86_64",
    0x28: "armhf",
    0xB7: "aarch64",
    0xF3: "riscv64",
    0x15: "ppc64le",
}

# ISO9660 puts its first 32 KiB aside for boot code - which is exactly where a
# type 1 AppImage keeps its ELF runtime, so the primary volume descriptor sits
# at a fixed absolute position.
ISO_PVD = 32768


class NaoEhAppImage(Exception):
    pass


def _u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def _u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def _u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def cabecalho(cab):
    """(type, architecture) from the ELF header of an AppImage."""
    if len(cab) < 64 or cab[:4] != b"\x7fELF":
        raise NaoEhAppImage("nao_e_elf")
    # Bytes 8, 9 and 10 are ABI padding in the ELF specification, and the
    # AppImage standard writes its own mark there: 'A', 'I', generation.
    if cab[8:10] != b"AI":
        raise NaoEhAppImage("sem_marca_ai")
    tipo = cab[10]
    if tipo not in (1, 2):
        raise NaoEhAppImage("geracao_desconhecida|%d" % tipo)
    arq = MAQUINAS.get(_u16(cab, 18), "?")
    return tipo, arq


def deslocamento(cab):
    """Where the payload starts: the end of the ELF section header table.

    The runtime's own --appimage-offset returns this same number, and it does
    so by running the file. Here it comes out of the header, with nothing
    executed.
    """
    classe = cab[4]
    if classe == 2:                        # 64-bit
        shoff, shentsize, shnum = _u64(cab, 0x28), _u16(cab, 0x3A), _u16(cab, 0x3C)
    elif classe == 1:                      # 32-bit
        shoff, shentsize, shnum = _u32(cab, 0x20), _u16(cab, 0x2E), _u16(cab, 0x30)
    else:
        return None
    if not shoff or not shnum:
        return None
    return shoff + shentsize * shnum


def carga(f, off, tamanho):
    """(payload kind, whether it fits in the file).

    Returns "?" for the kind and None for the verdict whenever the header
    cannot be read: not knowing is a legitimate answer here, and claiming a
    file is broken because of a format we do not recognise would be worse than
    saying nothing.
    """
    if off is None:
        return "?", None
    if off + 96 > tamanho:
        # The file is shorter than its own declared payload offset: the download
        # stopped before the squashfs even began. That is a truncation, not an
        # "unknown" - the type-1 (ISO) path already treats the same shape as
        # incomplete at carga_iso. Returning False routes it to the handler's
        # COMPLETO=0 branch ("the download of this file did not finish") instead
        # of chmod+x and exec'ing a half-downloaded binary, whose kernel ENOEXEC
        # leaks bash's own "line N: ...: cannot execute binary file" - Tandem's
        # script path and line number - to the owner as if the program said it.
        # One-sided on purpose: a COMPLETE AppImage always has its payload end
        # at or before EOF, so off + 96 > tamanho can never fire on a good file.
        return "?", False
    f.seek(off)
    sb = f.read(96)
    if len(sb) >= 48 and sb[:4] == b"hsqs":
        # squashfs, little endian: bytes_used is the total size of the
        # filesystem, at offset 40 of the superblock.
        usados = _u64(sb, 40)
        if usados == 0 or usados > tamanho:
            return "squashfs", False
        return "squashfs", (off + usados) <= tamanho
    if sb[:4] == b"sqsh":
        # Big-endian squashfs. Recognised so the payload is not reported as
        # unknown, but its fields are not read: no AppImage builder in use
        # produces one, so a reader for it would be code nobody exercises.
        return "squashfs", None
    return "?", None


def carga_iso(f, tamanho):
    """The same verdict for a type 1 AppImage, whose payload is an ISO9660."""
    if tamanho < ISO_PVD + 2048:
        return "?", False
    f.seek(ISO_PVD)
    pvd = f.read(2048)
    if len(pvd) < 132 or pvd[1:6] != b"CD001":
        return "?", None
    blocos = _u32(pvd, 80)
    tam_bloco = _u16(pvd, 128)
    if not blocos or not tam_bloco:
        return "iso9660", None
    return "iso9660", (blocos * tam_bloco) <= tamanho


def inspecionar(caminho):
    tamanho = os.path.getsize(caminho)
    with open(caminho, "rb") as f:
        cab = f.read(64)
        tipo, arq = cabecalho(cab)
        if tipo == 1:
            off = 0
            tipo_carga, completo = carga_iso(f, tamanho)
        else:
            off = deslocamento(cab)
            tipo_carga, completo = carga(f, off, tamanho)
    return tipo, arq, off, tipo_carga, completo


# The KEY=VALUE contract, defended HERE rather than assumed.
#
# The shell reads this output a line at a time. Everything printed below is
# either a number this reader computed or a STRING THAT CAME OUT OF THE FILE -
# and the file arrived from the internet, on a machine belonging to somebody
# who is not a programmer.
#
# Whether a value can contain a newline is a property of the source format, not
# of this reader: a .deb control file is line-based and cannot carry one, while
# a PE import name, an RPM header string and an Android manifest string are all
# length- or NUL-delimited and carry one perfectly well. Relying on the input
# format to protect the output format is an accident waiting for the one format
# that does not.
#
# So every value is cleaned on the way out. The asymmetry that made this
# visible: the raw-exception path already did `.replace("\n", " ")` while the
# data path, three lines below it, did not.
def limpo(valor):
    """A value that cannot forge a line, whatever the file said."""
    texto = "%s" % valor
    return "".join(" " if c in "\r\n" or ord(c) < 32 else c for c in texto)


def main():
    if len(sys.argv) < 2:
        print("ERRO=uso")
        return 2
    caminho = sys.argv[1]
    if not os.path.isfile(caminho):
        print("ERRO=sem_arquivo")
        return 2
    try:
        tipo, arq, off, tipo_carga, completo = inspecionar(caminho)
    except NaoEhAppImage as e:
        print("ERRO=%s" % limpo(e))
        return 1
    except Exception as e:                        # truncated, chopped file
        print("ERRO=cru|%s" % str(e).replace("\n", " ")[:200])
        return 1

    print("TIPO=%d" % tipo)
    print("ARQUITETURA=%s" % limpo(arq))
    print("DESLOCAMENTO=%s" % limpo(("" if off is None else off)))
    print("CARGA=%s" % limpo(tipo_carga))
    print("COMPLETO=%s" % limpo(("?" if completo is None else int(completo))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
