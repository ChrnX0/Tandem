#!/usr/bin/env python3
"""Reads the label of a .deb WITHOUT installing anything.

A .deb double-clicked on a machine with no store installed does nothing at all -
the same vacuum as an AppImage. And when something does open it, the failure it
reports for the commonest case is unusable: "dependency is not satisfiable:
libssl1.1". That sentence names a library nobody outside the trade has heard of,
and it does not say the one thing that matters, which is that the package was
built for an older release of the distribution and no amount of trying will fix
it here.

Everything needed to say that is inside the file. A .deb is an ar archive with
three members, and the second one carries a control file listing the package
name, its architecture and every dependency. Reading it costs milliseconds and
needs neither root nor dpkg.

The ar and tar walking is done by hand on purpose. build.py already writes this
format without dpkg-deb, so reading it back is symmetric - and it keeps the
diagnosis working on a machine where dpkg's own database is mid-transaction.

Usage:  debinfo.py <file.deb>
Output: KEY=VALUE lines, the same contract as peinfo.py and apkinfo.py

PACOTE=<Package>
VERSAO=<Version>
ARQUITETURA=<Architecture: all, amd64, arm64...>
DEPENDE=<normalised: group;group;group - alternatives inside a group split by |>
PRE_DEPENDE=<the same, for Pre-Depends>
CONFLITA=<Conflicts, normalised the same way>
TAMANHO=<Installed-Size in KiB, empty if absent>
DESCRICAO=<the short description, one line>
MANTENEDOR=<Maintainer>
ESSENCIAL=0|1
ERRO=<token>[|<data>]  when something failed; see t_erro_do_leitor
   The field carries a TOKEN, never a sentence. It used to carry Portuguese
   prose, and the handler printed it straight to the owner - so this file held
   user-facing messages that no translation tool in the tree had ever opened,
   and a raw Python exception reached a shop owner in English. The shell turns
   a token into a sentence in the owner's language; an unknown token is logged
   and answered with a generic one, because a reader that learns a new failure
   must not be able to produce silence.
"""
import ctypes
import gzip
import io
import lzma
import os
import re
import sys
import tarfile

# The control member, under the names Debian actually uses. Order does not
# matter - the archive is searched for whichever one it carries.
CONTROLES = (
    "control.tar.zst", "control.tar.gz", "control.tar.xz", "control.tar",
)

# A control tarball is kilobytes. Anything past this is either a malformed
# header or a deliberately hostile one, and a decompressor told to allocate it
# would take the machine down instead of reporting a bad file.
TETO = 64 * 1024 * 1024


class DebRuim(Exception):
    pass


def _zstd():
    """libzstd, loaded at the last moment.

    Python has no zstd reader in the standard library and neither the zstd
    command nor python3-zstandard is installed on a normal Ubuntu - but EVERY
    current .deb uses control.tar.zst, so a reader without this handles almost
    no real package. The library itself is always there: dpkg pre-depends on
    libzstd1, so on any machine where a .deb means anything at all, so is this.
    """
    ultimo = None
    for nome in ("libzstd.so.1", "libzstd.so"):
        try:
            lib = ctypes.CDLL(nome)
            break
        except OSError as e:
            ultimo = e
    else:
        raise DebRuim("sem_libzstd|%s" % ultimo)
    lib.ZSTD_getFrameContentSize.restype = ctypes.c_ulonglong
    lib.ZSTD_getFrameContentSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    lib.ZSTD_decompress.restype = ctypes.c_size_t
    lib.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                    ctypes.c_void_p, ctypes.c_size_t]
    lib.ZSTD_isError.restype = ctypes.c_uint
    lib.ZSTD_isError.argtypes = [ctypes.c_size_t]
    return lib


def _descomprime_zstd(bruto):
    lib = _zstd()
    desconhecido = (1 << 64) - 1
    erro = (1 << 64) - 2
    n = lib.ZSTD_getFrameContentSize(bruto, len(bruto))
    if n == erro:
        raise DebRuim("deb_control_danificado")
    if n == desconhecido:
        # dpkg writes the size into the frame header, so this is the path for a
        # package built by something else. Growing a guess is enough here
        # because the ceiling is small and the real content is tiny.
        for tentativa in (1 << 20, 1 << 24, TETO):
            fora = ctypes.create_string_buffer(tentativa)
            got = lib.ZSTD_decompress(fora, tentativa, bruto, len(bruto))
            if not lib.ZSTD_isError(got):
                return fora.raw[:got]
        raise DebRuim("deb_control_grande")
    if n > TETO:
        raise DebRuim("deb_tamanho_absurdo|%d" % n)
    fora = ctypes.create_string_buffer(n)
    got = lib.ZSTD_decompress(fora, n, bruto, len(bruto))
    if lib.ZSTD_isError(got):
        raise DebRuim("deb_control_nao_abriu")
    return fora.raw[:got]


def membros_ar(dados):
    """[(name, bytes)] from an ar archive, walked by hand.

    The header is 60 bytes of fixed-width ASCII fields and members are padded to
    an even offset. GNU ar writes long names into a lookup table, but no .deb
    uses names long enough for that, so a name is read straight out of the
    header with its trailing slash stripped.
    """
    if dados[:8] != b"!<arch>\n":
        raise DebRuim("nao_e_deb")
    p = 8
    saida = []
    while p + 60 <= len(dados):
        cab = dados[p:p + 60]
        if cab[58:60] != b"`\n":
            break
        nome = cab[:16].decode("ascii", "replace").strip().rstrip("/")
        bruto = cab[48:58].decode("ascii", "replace").strip()
        if not bruto.isdigit():
            break
        tam = int(bruto)
        inicio = p + 60
        if inicio + tam > len(dados):
            # The archive claims a member longer than the file: the download was
            # cut short. Same verdict as a truncated AppImage, same cause.
            raise DebRuim("pacote_incompleto")
        saida.append((nome, dados[inicio:inicio + tam]))
        p = inicio + tam + (tam % 2)
    return saida


def _le_ate_teto(fh):
    """Read a decompressing stream up to TETO, refusing anything larger.

    GzipFile/LZMAFile.read(n) yield at most n bytes and decompress lazily, so
    reading TETO+1 bounds the memory to the ceiling instead of materialising the
    whole output. A control tarball is kilobytes; a gz/xz that expands past 64
    MiB is a decompression bomb, and swallowing it whole would OOM a low-RAM
    counter PC on a double-click - the same harm the zstd path already caps.
    """
    dados = fh.read(TETO + 1)
    if len(dados) > TETO:
        raise DebRuim("deb_tamanho_absurdo|>%d" % TETO)
    return dados


def descomprime(nome, bruto):
    """The control tarball, decompressed, whatever it was compressed with.

    Every path is bounded by TETO: gz and xz stream through _le_ate_teto, zstd
    caps on the frame size, and a plain .tar is already whole in memory.
    """
    if nome.endswith(".gz"):
        with gzip.GzipFile(fileobj=io.BytesIO(bruto)) as fh:
            return _le_ate_teto(fh)
    if nome.endswith(".xz"):
        with lzma.LZMAFile(io.BytesIO(bruto)) as fh:
            return _le_ate_teto(fh)
    if nome.endswith(".zst"):
        return _descomprime_zstd(bruto)
    return bruto


def texto_do_controle(dados):
    """The content of ./control inside the control tarball."""
    membros = membros_ar(dados)
    nomes = dict(membros)
    # A .deb always carries a data member after the control one. When a download
    # is cut short exactly on a member boundary the ar walk ends cleanly and the
    # control it already read looks perfectly fine - so without this check the
    # truncation verdict depends on where the cut happened to land, which is not
    # a verdict at all.
    if not any(n.startswith("data.tar") for n in nomes):
        raise DebRuim("pacote_sem_dados")
    for nome in CONTROLES:
        if nome in nomes:
            bruto = descomprime(nome, nomes[nome])
            with tarfile.open(fileobj=io.BytesIO(bruto)) as t:
                for m in t.getmembers():
                    if m.name.lstrip("./") == "control":
                        f = t.extractfile(m)
                        if f is None:
                            continue
                        return f.read().decode("utf-8", "replace")
            raise DebRuim("deb_sem_control")
    raise DebRuim("deb_sem_control_tar")


def campos(texto):
    """The control file as a dict, with continuation lines joined.

    Debian control is RFC822-shaped: a field continues on the following lines
    while they start with a space or a tab. Depends is routinely wrapped that
    way on a package with many dependencies.
    """
    fora = {}
    chave = None
    for linha in texto.replace("\r\n", "\n").split("\n"):
        if not linha:
            continue
        if linha[0] in " \t":
            if chave:
                fora[chave] += " " + linha.strip()
            continue
        if ":" not in linha:
            continue
        chave, _, valor = linha.partition(":")
        chave = chave.strip()
        fora[chave] = valor.strip()
        # The short description is the FIRST PHYSICAL LINE of Description; the
        # paragraphs below it are the long one. Once the continuation lines are
        # joined there is no reliable way back, so it is kept aside here.
        if chave == "Description":
            fora["Description-curta"] = valor.strip()
    return fora


def normaliza_dependencias(bruto):
    """Debian dependency syntax reduced to something a shell can split.

    Input:   libc6 (>= 2.34), python3:any | python3.10, foo [amd64] <!nocheck>
    Output:  libc6(>= 2.34);python3|python3.10;foo

    The architecture qualifier after a colon, the architecture restriction in
    square brackets and the build profile in angle brackets are all dropped:
    they qualify WHICH build needs the dependency, and by the time a file is
    being double-clicked that question is already answered.
    """
    if not bruto:
        return ""
    grupos = []
    for grupo in bruto.split(","):
        alternativas = []
        for alt in grupo.split("|"):
            alt = re.sub(r"\[[^\]]*\]", " ", alt)
            alt = re.sub(r"<[^>]*>", " ", alt)
            alt = alt.strip()
            if not alt:
                continue
            m = re.match(r"^([A-Za-z0-9][A-Za-z0-9+.\-]*)(?::[A-Za-z0-9]+)?\s*(\([^)]*\))?", alt)
            if not m:
                continue
            nome = m.group(1)
            versao = (m.group(2) or "").strip()
            # Parentheses and semicolons are the separators of this format, so a
            # name carrying one would break the reader downstream. No real
            # package name can, but the file comes from outside.
            if ";" in nome or "|" in nome:
                continue
            alternativas.append(nome + versao)
        if alternativas:
            grupos.append("|".join(alternativas))
    return ";".join(grupos)


def uma_linha(s):
    """A value fit for a KEY=VALUE line."""
    return " ".join((s or "").split())


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


# Debian policy: a package name is at least two characters, starts with an
# alphanumeric, and holds only lowercase letters, digits, plus, minus and dot.
_NOME_PACOTE = re.compile(r"^[a-z0-9][a-z0-9+.-]+$")


def nome_de_pacote(valor):
    """The Package name if it matches Debian policy, else empty.

    Defence in depth for the shell downstream: a name outside this set is not
    something dpkg would ever install, and spliced into a sed program or a
    privileged sh -c it was a code-execution vector (the same untrusted-data
    class as Installed-Size). A non-conforming name is dropped here, so
    tandem-deb refuses it as "not a package" rather than trusting it. The two
    real sinks are fixed independently; this stops the value at the source.
    """
    v = limpo(uma_linha(valor)).strip()
    return v if _NOME_PACOTE.match(v) else ""


def main():
    if len(sys.argv) < 2:
        print("ERRO=uso")
        return 2
    caminho = sys.argv[1]
    if not os.path.isfile(caminho):
        print("ERRO=sem_arquivo")
        return 2
    try:
        with open(caminho, "rb") as f:
            dados = f.read()
        c = campos(texto_do_controle(dados))
    except DebRuim as e:
        print("ERRO=%s" % limpo(e))
        return 1
    except Exception as e:
        print("ERRO=cru|%s" % str(e).replace("\n", " ")[:200])
        return 1

    print("PACOTE=%s" % nome_de_pacote(c.get("Package", "")))
    print("VERSAO=%s" % limpo(uma_linha(c.get("Version", ""))))
    print("ARQUITETURA=%s" % limpo(uma_linha(c.get("Architecture", ""))))
    print("DEPENDE=%s" % limpo(normaliza_dependencias(c.get("Depends", ""))))
    print("PRE_DEPENDE=%s" % limpo(normaliza_dependencias(c.get("Pre-Depends", ""))))
    print("CONFLITA=%s" % limpo(normaliza_dependencias(c.get("Conflicts", ""))))
    # Installed-Size is an INTEGER in KiB by Debian policy. The shell puts this
    # value inside $(( )) to show "this will use N MB", and bash arithmetic
    # evaluates its operand recursively - so a value like  a[$(command)]  from a
    # hostile .deb would EXECUTE that command as the user, before any password.
    # Emit it only when it is all digits; anything else is malformed or an
    # attack, and dropping it just omits the size line. The shell guards the
    # arithmetic too (defence in depth), but the value has no business being
    # non-numeric in the first place.
    _tam = limpo(uma_linha(c.get("Installed-Size", "")))
    print("TAMANHO=%s" % (_tam if _tam.isdigit() else ""))
    print("DESCRICAO=%s" % limpo(uma_linha(c.get("Description-curta", ""))[:200]))
    print("MANTENEDOR=%s" % limpo(uma_linha(c.get("Maintainer", ""))))
    print("ESSENCIAL=%d" % (1 if c.get("Essential", "no").lower() == "yes" else 0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
