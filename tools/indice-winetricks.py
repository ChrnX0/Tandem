#!/usr/bin/env python3
"""Generates the DLL -> verb index by reading the installed winetricks itself.

winetricks already knows exactly which files each verb delivers: inside
load_<verb>() it calls

    w_override_dlls native,builtin msvcp140 vcruntime140 ...

to tell Wine to use the freshly installed versions. Nobody uses this as an
index because winetricks only walks in the verb -> installation direction.
Reading it backwards yields the table Tandem needs - with the whole coverage
of winetricks, no network, no service and no hand-kept list.

    python3 tools/indice-winetricks.py             # writes src/lib/verbos.tsv
    python3 tools/indice-winetricks.py --conferir  # only compares with current

The hand-written table in src/lib/winedeps.sh remains valid and takes
precedence: it carries decisions the index has no way of knowing, such as
sending msvcp140 to vcrun2022 (the newest one, which serves the earlier ones)
instead of to vcrun2015. The index comes in as a second opinion, for the
hundreds of DLLs the hand-written table will never cover.
"""
import os
import re
import shutil
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "src", "lib", "verbos.tsv")

INICIO_VERBO = re.compile(r"^load_([a-z0-9_.]+)\s*\(\)")
OVERRIDE = re.compile(r"^\s*w_override_dlls\s+(?:native,builtin|native|builtin,native)\s+(.+?)\s*$")

# ------------------------------------------------ the blind spot of the 1st
#
# Reading only w_override_dlls left the index blind exactly where the
# hand-written table was wrong. vcrun2003 never calls w_override_dlls once:
# the DLLs it delivers are declared only in the title -
#     w_metadata vcrun2003 dlls \
#         title="Visual C++ 2003 libraries (mfc71,msvcp71,msvcr71)"
# - and that is why it had ZERO entries in the index, while the table sent
# msvcr71.dll to vcrun6, which does not deliver that. The auditor could not
# find the error because it could not see the right answer. The same goes for
# the mfc140* of vcrun2022, confirmed on a real machine.
#
# The risk of reading the title is the opposite: almost every parenthesis in a
# title is NOT a DLL list ("(Deprecated, no-op)", "(0.54)", "(developers
# only)"). Two narrow filters solve it: the category has to be "dlls", and the
# title has to say "dll" or "librar" before the parenthesis.
METADATA = re.compile(r"^\s*w_metadata\s+([a-z0-9_.]+)\s+([a-z]+)")
TITULO = re.compile(r'title="([^"]*)"')
LISTA_NO_TITULO = re.compile(r"\(([^()]*)\)")
TOKEN_DLL = re.compile(r"^[a-z][a-z0-9_+-]*(\.dll)?$")


def dlls_do_titulo(titulo):
    """DLL names declared between parentheses in the title, or empty list."""
    if not re.search(r"dll|librar", titulo, re.I):
        return []
    for bruto in LISTA_NO_TITULO.findall(titulo):
        pecas = [p.strip().lower() for p in bruto.split(",")]
        if len(pecas) < 2:
            continue
        if not all(TOKEN_DLL.match(p) for p in pecas):
            continue
        # "(Deprecated, no-op)" would pass the format check; it does not pass
        # the category and word filters, nor this one: a loose version number.
        if any(re.fullmatch(r"[0-9.]+", p) for p in pecas):
            continue
        return pecas
    return []

# Verbs that deliver a DLL but are not a program dependency: installing one by
# mistake only wastes the owner's time and can make the prefix worse.
IGNORAR_VERBOS = {
    "sandbox", "isolate_home", "remove_mono", "vd", "videomemorysize",
    "ddr", "orm", "psm", "rtlm", "mwo", "fontsmooth", "alldlls",
    # Installs nothing: it tells Wine to use Mono in place of .NET. Letting it
    # in made mscoree.dll point here instead of to dotnet.
    "forcemono",
}

# Words that show up on the override line but are not a DLL name.
NAO_E_DLL = re.compile(r"[^a-z0-9_.+-]")


def acha_winetricks(argv):
    for a in argv:
        if a.endswith("winetricks") and os.path.isfile(a):
            return a
    return shutil.which("winetricks")


def ler(caminho):
    """({dll: [verbs]}, {dll: source}) read from winetricks."""
    indice = {}
    fontes = {}
    verbo = None
    meta_verbo = None

    def anota(dll, v, fonte):
        indice.setdefault(dll, [])
        if v not in indice[dll]:
            indice[dll].append(v)
        anterior = fontes.get(dll)
        fontes[dll] = "ambos" if anterior and anterior != fonte else fonte

    with open(caminho, encoding="utf-8", errors="replace") as f:
        for linha in f:
            # Metadata block: only the "dlls" category matters.
            m = METADATA.match(linha)
            if m:
                meta_verbo = m.group(1) if m.group(2) == "dlls" else None
                if meta_verbo in IGNORAR_VERBOS:
                    meta_verbo = None
                continue
            if meta_verbo:
                t = TITULO.search(linha)
                if t:
                    for peca in dlls_do_titulo(t.group(1)):
                        dll = peca if peca.endswith(".dll") else peca + ".dll"
                        if len(dll) >= 5:
                            anota(dll, meta_verbo, "titulo")
                    meta_verbo = None
                elif not linha.rstrip().endswith("\\"):
                    meta_verbo = None

            m = INICIO_VERBO.match(linha)
            if m:
                verbo = m.group(1)
                continue
            if verbo is None or verbo in IGNORAR_VERBOS:
                continue
            m = OVERRIDE.match(linha)
            if not m:
                continue
            for peca in m.group(1).split():
                peca = peca.strip('"\'').lower()
                # winetricks writes the name without the extension
                # ("msvcp140") and sometimes with it ("cmd.exe"). We normalize
                # to .dll, which is the format Wine uses in the error message
                # we read.
                if peca.endswith(".exe") or peca.endswith(".drv"):
                    dll = peca
                elif peca.endswith(".dll"):
                    dll = peca
                else:
                    dll = peca + ".dll"
                if NAO_E_DLL.search(dll.replace(".", "")):
                    continue
                if len(dll) < 5:
                    continue
                anota(dll, verbo, "override")
    return indice, fontes


def escolher(verbos):
    """Breaks the tie when several verbs deliver the same DLL.

    Rule: the NEWEST one serves the earlier ones. The Visual C++ runtime is
    cumulative - whoever installs vcrun2022 has what vcrun2015 would give -,
    so among names that differ only in the year, the largest wins. Beyond
    that, the shortest name, which is usually the base package and not a
    variant.
    """
    def versao(v):
        """Number from the verb name, comparable between siblings.

        A four-digit year is a year: vcrun2022 > vcrun2015. Any other number
        is a version with the dot omitted, one digit per part:
        dotnet48 -> (4,8) and dotnet472 -> (4,7,2), so 4.8 wins. Comparing as
        an integer would give 472 > 48, which is the opposite of right.
        """
        maior = ()
        for n in re.findall(r"\d+", v):
            if len(n) == 4 and n[:2] in ("19", "20"):
                atual = (int(n),)
            else:
                atual = tuple(int(d) for d in n)
            if atual > maior:
                maior = atual
        return maior

    def chave(v):
        ver = versao(v)
        # A verb with no number at all goes to the end: among versioned
        # siblings, one that declares no version cannot win by omission.
        return (0 if ver else 1, tuple(-x for x in ver), len(v), v)

    return sorted(verbos, key=chave)[0]


def familia(v):
    """Verb name without version: vcrun2022 -> vcrun, dotnet48 -> dotnet."""
    return re.sub(r"[0-9].*$", "", v)


def confianca(verbos):
    """Can we choose among these verbs on our own?

    A single candidate: obvious. Several from the SAME family: breaking the
    tie by version is defensible, because the newer runtime serves the older
    one. Different families (ie8 vs wininet vs wininet_win2k) is a guess, and
    a guess that costs the owner half an hour - in that case the index stays
    quiet and the DLL goes back to being "no known translation", which is the
    honest answer.
    """
    if len(verbos) == 1:
        return "alta"
    return "alta" if len({familia(v) for v in verbos}) == 1 else "baixa"


def main():
    wt = acha_winetricks(sys.argv[1:])
    if not wt:
        print("winetricks not found; nothing to do", file=sys.stderr)
        return 0

    indice, fontes = ler(wt)
    linhas = []
    for dll in sorted(indice):
        verbos = indice[dll]
        linhas.append("%s\t%s\t%s\t%s\t%s" % (
            dll, escolher(verbos), confianca(verbos), ",".join(sorted(verbos)),
            fontes.get(dll, "override")))
    # The header of the generated file stays in Portuguese on purpose: the
    # column names are the same field names the rest of the code compares
    # against, and the text is byte-compared with the src/lib/verbos.tsv
    # committed to the repository by --conferir. Changing it here without
    # regenerating the table turns the check red.
    texto = ("# dll\tverbo\tconfianca\ttodos-os-verbos\tfonte\n"
             "# Gerado por tools/indice-winetricks.py a partir do winetricks\n"
             "# instalado. Nao edite a mao: as decisoes ficam em winedeps.sh.\n"
             + "\n".join(linhas) + "\n")

    if "--conferir" in sys.argv:
        atual = ""
        if os.path.exists(DESTINO):
            with open(DESTINO, encoding="utf-8") as f:
                atual = f.read()
        igual = atual == texto
        print("%d DLLs indexed from %s" % (len(linhas), wt))
        print("table on disk: %s" % ("same" if igual else "DIFFERENT"))
        return 0 if igual else 1

    with open(DESTINO, "w", encoding="utf-8") as f:
        f.write(texto)
    print("%d DLLs indexed from %s -> %s" % (len(linhas), wt, DESTINO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
