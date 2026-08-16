#!/usr/bin/env python3
"""Reads the label of a Windows executable WITHOUT running anything.

Every PE carries, inside the file itself, the list of libraries it will ask
the system for when it opens - the import table. Until now Tandem only found
that out AFTER running and failing, by reading Wine's "err:module:import_dll".
By reading the table beforehand, it knows what is going to be missing without
ever having failed, and it can warn in two seconds that a program has no fix -
instead of the owner finding out after half an hour installing dependencies.

Usage:  peinfo.py <file.exe>
Output: KEY=VALUE lines, the same contract as apkinfo.py

ARQUITETURA=32|64|arm64|?
DOTNET=0|1
DLLS=<comma-separated list, lowercase>
ATRASADAS=<same, for the delayed imports>
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

# Entries of the PE data directory table that matter to us.
DIR_IMPORT = 1
DIR_DELAY = 13
DIR_CLR = 14        # if filled in, the program is .NET

MAQUINAS = {0x014C: "32", 0x8664: "64", 0xAA64: "arm64", 0x01C4: "arm"}


class NaoEhPE(Exception):
    pass


def _u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def _u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def cabecalho(dados):
    """Returns (architecture, start_of_optional, size_of_optional, n_sections)."""
    if len(dados) < 0x40 or dados[:2] != b"MZ":
        raise NaoEhPE("nao_e_mz")
    pe = _u32(dados, 0x3C)
    if pe <= 0 or pe + 24 > len(dados) or dados[pe:pe + 4] != b"PE\0\0":
        raise NaoEhPE("sem_assinatura_pe")
    maquina = _u16(dados, pe + 4)
    n_secoes = _u16(dados, pe + 6)
    tam_opcional = _u16(dados, pe + 20)
    return MAQUINAS.get(maquina, "?"), pe + 24, tam_opcional, n_secoes


def diretorios(dados, opcional):
    """List of [(rva, size)] from the data directory table.

    The offset differs between PE32 and PE32+ because the latter swaps
    several fields from 4 to 8 bytes and has no BaseOfData.
    """
    magia = _u16(dados, opcional)
    if magia == 0x10B:
        base = opcional + 96
    elif magia == 0x20B:
        base = opcional + 112
    else:
        raise NaoEhPE("pe_cabecalho_desconhecido")
    n = _u32(dados, base - 4)
    n = min(n, 16)
    saida = []
    for i in range(n):
        p = base + i * 8
        if p + 8 > len(dados):
            break
        saida.append((_u32(dados, p), _u32(dados, p + 4)))
    return saida


def secoes(dados, opcional, tam_opcional, n_secoes):
    """[(rva, virtual_size, raw_size, raw_offset)] for each section."""
    base = opcional + tam_opcional
    fora = []
    for i in range(n_secoes):
        p = base + i * 40
        if p + 40 > len(dados):
            break
        fora.append((_u32(dados, p + 12), _u32(dados, p + 8),
                     _u32(dados, p + 16), _u32(dados, p + 20)))
    return fora


def para_offset(rva, secs):
    """Converts a virtual address into a position inside the file."""
    for va, vsize, bruto, off in secs:
        # The recorded raw size is usually larger than the virtual one because
        # of alignment; using the larger of the two avoids rejecting a valid
        # address.
        limite = max(vsize, bruto)
        if va <= rva < va + limite:
            return off + (rva - va)
    return None


def texto_em(dados, off, limite=256):
    """Reads a zero-terminated ASCII string."""
    if off is None or off < 0 or off >= len(dados):
        return ""
    fim = dados.find(b"\0", off, off + limite)
    if fim < 0:
        fim = min(off + limite, len(dados))
    return dados[off:fim].decode("ascii", "replace")


def nomes_de_dll(dados, rva, secs, atrasada=False):
    """Walks the import descriptors and returns the DLL names.

    Each descriptor is 20 bytes long and the list ends at an all-zero
    descriptor. The name field sits at offset 12 (normal import) or 4
    (delayed import, whose descriptor has a different layout).
    """
    achados = []
    off = para_offset(rva, secs)
    if off is None:
        return achados
    campo_nome = 4 if atrasada else 12
    for i in range(4096):                       # sanity ceiling
        p = off + i * 20
        if p + 20 > len(dados):
            break
        bloco = dados[p:p + 20]
        if bloco == b"\0" * 20:
            break
        nome_rva = _u32(dados, p + campo_nome)
        if not nome_rva:
            continue
        # Some files record the delayed name as an absolute address.
        pos = para_offset(nome_rva, secs)
        if pos is None and atrasada:
            pos = nome_rva if nome_rva < len(dados) else None
        nome = texto_em(dados, pos)
        if nome.lower().endswith(".dll") or nome.lower().endswith(".drv"):
            achados.append(nome.lower())
    return achados


def truncado(dados, dirs, secs):
    """True when the file is SHORTER than its own headers declare it to be.

    The same question is already asked of a .jar (its index lives at the end),
    of an .AppImage (payload offset plus squashfs bytes_used) and of a .deb (a
    missing data.tar member). It was never asked of the .exe - and a 400 MB
    point-of-sale installer cut short over a shop connection is the commonest
    broken thing that reaches this project. Today that produces "Bad EXE
    format" from Wine after the wait, which sends the owner looking for a
    defect in a file that simply did not finish arriving.

    ONE-SIDED ON PURPOSE. Only "shorter than declared" is a verdict. A valid
    file being LONGER is normal and must never be reported: NSIS and Inno Setup
    append their payload after the last section, so every real installer is
    longer than its section table accounts for. Reporting that would refuse to
    open exactly the software this project exists for.

    Data directory 4 is the certificate table, and it is the one entry whose
    address is a FILE OFFSET rather than an RVA - so it can be compared with
    the length directly, with no section walk in between.
    """
    fim = len(dados)
    for _va, _vsize, bruto, off in secs:
        # A section with no raw data (.bss) has offset and size zero; adding
        # them proves nothing and comparing them would flag every binary.
        if bruto and off and off + bruto > fim:
            return True
    if len(dirs) > 4:
        cert_off, cert_tam = dirs[4]
        if cert_off and cert_tam and cert_off + cert_tam > fim:
            return True
    return False


def inspecionar(caminho):
    with open(caminho, "rb") as f:
        dados = f.read()

    arq, opcional, tam_opcional, n_secoes = cabecalho(dados)
    dirs = diretorios(dados, opcional)
    secs = secoes(dados, opcional, tam_opcional, n_secoes)
    if truncado(dados, dirs, secs):
        raise NaoEhPE("pe_incompleto")

    def dir_rva(i):
        return dirs[i][0] if i < len(dirs) and dirs[i][0] else 0

    dlls, atrasadas = [], []
    if dir_rva(DIR_IMPORT):
        dlls = nomes_de_dll(dados, dir_rva(DIR_IMPORT), secs)
    if dir_rva(DIR_DELAY):
        atrasadas = nomes_de_dll(dados, dir_rva(DIR_DELAY), secs, atrasada=True)

    dotnet = 1 if dir_rva(DIR_CLR) else 0
    # A .NET binary imports only mscoree.dll; without this mark Tandem would
    # conclude that it does not depend on anything.
    if dotnet and "mscoree.dll" not in dlls:
        dlls.append("mscoree.dll")

    return arq, dotnet, sorted(set(dlls)), sorted(set(atrasadas))


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
        arq, dotnet, dlls, atrasadas = inspecionar(caminho)
    except NaoEhPE as e:
        print("ERRO=%s" % limpo(e))
        return 1
    except Exception as e:                        # truncated, chopped file
        print("ERRO=cru|%s" % str(e).replace("\n", " ")[:200])
        return 1

    print("ARQUITETURA=%s" % limpo(arq))
    print("DOTNET=%d" % dotnet)
    print("DLLS=%s" % limpo(",".join(dlls)))
    print("ATRASADAS=%s" % limpo(",".join(atrasadas)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
