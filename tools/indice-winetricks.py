#!/usr/bin/env python3
"""Gera o indice DLL -> verbo lendo o proprio winetricks instalado.

O winetricks ja sabe exatamente quais arquivos cada verbo entrega: dentro de
load_<verbo>() ele chama

    w_override_dlls native,builtin msvcp140 vcruntime140 ...

para dizer ao Wine que use as versoes recem-instaladas. Ninguem usa isso como
indice porque o winetricks so anda no sentido verbo -> instalacao. Invertendo
a leitura, sai a tabela que o Tandem precisa - com a cobertura inteira do
winetricks, sem rede, sem servico e sem manter lista a mao.

    python3 tools/indice-winetricks.py             # escreve src/lib/verbos.tsv
    python3 tools/indice-winetricks.py --conferir  # so compara com o atual

A tabela escrita a mao em src/lib/winedeps.sh continua valendo e tem
precedencia: ela carrega decisoes que o indice nao tem como saber, como
mandar msvcp140 para vcrun2022 (o mais novo, que serve os anteriores) em vez
de para vcrun2015. O indice entra como segunda opinião, para as centenas de
DLLs que a tabela a mao nunca vai cobrir.
"""
import os
import re
import shutil
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "src", "lib", "verbos.tsv")

INICIO_VERBO = re.compile(r"^load_([a-z0-9_.]+)\s*\(\)")
OVERRIDE = re.compile(r"^\s*w_override_dlls\s+(?:native,builtin|native|builtin,native)\s+(.+?)\s*$")

# ------------------------------------------------------- o ponto cego do 1o
#
# Ler so w_override_dlls deixava o indice cego exatamente onde a tabela a mao
# errava. O vcrun2003 nao chama w_override_dlls nenhuma vez: as DLLs que ele
# entrega estao declaradas apenas no titulo -
#     w_metadata vcrun2003 dlls \
#         title="Visual C++ 2003 libraries (mfc71,msvcp71,msvcr71)"
# - e por isso ele tinha ZERO entradas no indice, enquanto a tabela mandava
# msvcr71.dll para o vcrun6, que nao entrega isso. O auditor nao podia achar o
# erro porque nao enxergava o certo. O mesmo vale para as mfc140* do vcrun2022,
# confirmado numa maquina real.
#
# O risco de ler titulo e o oposto: quase todo parenteses em titulo NAO e lista
# de DLL ("(Deprecated, no-op)", "(0.54)", "(developers only)"). Dois filtros
# estreitos resolvem: a categoria tem que ser "dlls", e o titulo tem que dizer
# "dll" ou "librar" antes do parenteses.
METADATA = re.compile(r"^\s*w_metadata\s+([a-z0-9_.]+)\s+([a-z]+)")
TITULO = re.compile(r'title="([^"]*)"')
LISTA_NO_TITULO = re.compile(r"\(([^()]*)\)")
TOKEN_DLL = re.compile(r"^[a-z][a-z0-9_+-]*(\.dll)?$")


def dlls_do_titulo(titulo):
    """Nomes de DLL declarados entre parenteses no titulo, ou lista vazia."""
    if not re.search(r"dll|librar", titulo, re.I):
        return []
    for bruto in LISTA_NO_TITULO.findall(titulo):
        pecas = [p.strip().lower() for p in bruto.split(",")]
        if len(pecas) < 2:
            continue
        if not all(TOKEN_DLL.match(p) for p in pecas):
            continue
        # "(Deprecated, no-op)" passaria pelo formato; nao passa pelo filtro
        # de categoria e de palavra, e nem por este: numero de versao solto.
        if any(re.fullmatch(r"[0-9.]+", p) for p in pecas):
            continue
        return pecas
    return []

# Verbos que entregam DLL mas nao sao dependencia de programa: instalar por
# engano so gasta o tempo do dono e pode piorar o prefixo.
IGNORAR_VERBOS = {
    "sandbox", "isolate_home", "remove_mono", "vd", "videomemorysize",
    "ddr", "orm", "psm", "rtlm", "mwo", "fontsmooth", "alldlls",
    # Nao instala nada: manda o Wine usar o Mono no lugar do .NET. Deixar
    # entrar fazia o mscoree.dll apontar para ca em vez de para o dotnet.
    "forcemono",
}

# Palavras que aparecem na linha de override mas nao sao nome de DLL.
NAO_E_DLL = re.compile(r"[^a-z0-9_.+-]")


def acha_winetricks(argv):
    for a in argv:
        if a.endswith("winetricks") and os.path.isfile(a):
            return a
    return shutil.which("winetricks")


def ler(caminho):
    """({dll: [verbos]}, {dll: fonte}) lido do winetricks."""
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
            # Bloco de metadados: so a categoria "dlls" interessa.
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
                # O winetricks escreve o nome sem extensao ("msvcp140") e as
                # vezes com ela ("cmd.exe"). Normalizamos para .dll, que e o
                # formato que o Wine usa na mensagem de erro que lemos.
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
    """Desempata quando varios verbos entregam a mesma DLL.

    Regra: o mais NOVO serve os anteriores. O runtime do Visual C++ e
    cumulativo - quem instala o vcrun2022 tem o que o vcrun2015 daria -,
    entao entre nomes que so diferem no ano, vence o maior. Fora isso, o
    nome mais curto, que costuma ser o pacote base e nao uma variante.
    """
    def versao(v):
        """Numero do nome do verbo, comparavel entre irmaos.

        Ano de quatro digitos e ano: vcrun2022 > vcrun2015. Qualquer outro
        numero e versao com o ponto omitido, um digito por parte:
        dotnet48 -> (4,8) e dotnet472 -> (4,7,2), entao 4.8 ganha. Comparar
        como inteiro daria 472 > 48, que e o contrario do certo.
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
        # Verbo sem numero nenhum vai para o fim: entre irmaos versionados,
        # quem nao declara versao nao pode ganhar por omissao.
        return (0 if ver else 1, tuple(-x for x in ver), len(v), v)

    return sorted(verbos, key=chave)[0]


def familia(v):
    """Nome do verbo sem a versao: vcrun2022 -> vcrun, dotnet48 -> dotnet."""
    return re.sub(r"[0-9].*$", "", v)


def confianca(verbos):
    """Da para escolher sozinho entre estes verbos?

    Um candidato so: obvio. Varios da MESMA familia: o desempate por versao
    e defensavel, porque o runtime mais novo serve o anterior. Familias
    diferentes (ie8 x wininet x wininet_win2k) e chute, e chute que custa
    meia hora do dono - nesse caso o indice se cala e a DLL volta a ser
    "sem traducao conhecida", que e a resposta honesta.
    """
    if len(verbos) == 1:
        return "alta"
    return "alta" if len({familia(v) for v in verbos}) == 1 else "baixa"


def main():
    wt = acha_winetricks(sys.argv[1:])
    if not wt:
        print("winetricks nao encontrado; nada a fazer", file=sys.stderr)
        return 0

    indice, fontes = ler(wt)
    linhas = []
    for dll in sorted(indice):
        verbos = indice[dll]
        linhas.append("%s\t%s\t%s\t%s\t%s" % (
            dll, escolher(verbos), confianca(verbos), ",".join(sorted(verbos)),
            fontes.get(dll, "override")))
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
        print("%d DLLs indexadas de %s" % (len(linhas), wt))
        print("tabela em disco: %s" % ("igual" if igual else "DIFERENTE"))
        return 0 if igual else 1

    with open(DESTINO, "w", encoding="utf-8") as f:
        f.write(texto)
    print("%d DLLs indexadas de %s -> %s" % (len(linhas), wt, DESTINO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
