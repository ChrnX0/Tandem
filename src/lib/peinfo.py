#!/usr/bin/env python3
"""Le a etiqueta de um executavel Windows SEM executar nada.

Todo PE traz, no proprio arquivo, a lista de bibliotecas que vai pedir ao
sistema quando abrir - a tabela de importacoes. Ate agora o Tandem so
descobria isso DEPOIS de rodar e falhar, lendo o "err:module:import_dll" do
Wine. Lendo a tabela antes, ele sabe o que vai faltar sem nunca ter falhado,
e consegue avisar em dois segundos que um programa nao tem conserto - em vez
de o dono descobrir depois de meia hora instalando dependencia.

Uso:  peinfo.py <arquivo.exe>
Saida: linhas CHAVE=VALOR, o mesmo contrato do apkinfo.py

ARQUITETURA=32|64|arm64|?
DOTNET=0|1
DLLS=<lista separada por virgula, em minusculas>
ATRASADAS=<idem, das importacoes atrasadas>
ERRO=<mensagem, se algo falhou>
"""
import os
import struct
import sys

# Diretorios da tabela de dados do PE que nos interessam.
DIR_IMPORT = 1
DIR_DELAY = 13
DIR_CLR = 14        # se preenchido, o programa e .NET

MAQUINAS = {0x014C: "32", 0x8664: "64", 0xAA64: "arm64", 0x01C4: "arm"}


class NaoEhPE(Exception):
    pass


def _u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def _u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def cabecalho(dados):
    """Devolve (arquitetura, inicio_do_opcional, tamanho_do_opcional, n_secoes)."""
    if len(dados) < 0x40 or dados[:2] != b"MZ":
        raise NaoEhPE("nao comeca com MZ")
    pe = _u32(dados, 0x3C)
    if pe <= 0 or pe + 24 > len(dados) or dados[pe:pe + 4] != b"PE\0\0":
        raise NaoEhPE("nao tem assinatura PE")
    maquina = _u16(dados, pe + 4)
    n_secoes = _u16(dados, pe + 6)
    tam_opcional = _u16(dados, pe + 20)
    return MAQUINAS.get(maquina, "?"), pe + 24, tam_opcional, n_secoes


def diretorios(dados, opcional):
    """Lista [(rva, tamanho)] da tabela de diretorios de dados.

    O deslocamento muda entre PE32 e PE32+ porque o segundo troca varios
    campos de 4 por 8 bytes e nao tem BaseOfData.
    """
    magia = _u16(dados, opcional)
    if magia == 0x10B:
        base = opcional + 96
    elif magia == 0x20B:
        base = opcional + 112
    else:
        raise NaoEhPE("cabecalho opcional desconhecido")
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
    """[(rva, tamanho_virtual, tamanho_bruto, offset_bruto)] de cada secao."""
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
    """Converte endereco virtual em posicao dentro do arquivo."""
    for va, vsize, bruto, off in secs:
        # O tamanho gravado costuma ser maior que o virtual por causa do
        # alinhamento; usar o maior evita recusar um endereco valido.
        limite = max(vsize, bruto)
        if va <= rva < va + limite:
            return off + (rva - va)
    return None


def texto_em(dados, off, limite=256):
    """Le uma string ASCII terminada em zero."""
    if off is None or off < 0 or off >= len(dados):
        return ""
    fim = dados.find(b"\0", off, off + limite)
    if fim < 0:
        fim = min(off + limite, len(dados))
    return dados[off:fim].decode("ascii", "replace")


def nomes_de_dll(dados, rva, secs, atrasada=False):
    """Percorre os descritores de importacao e devolve os nomes das DLLs.

    Cada descritor tem 20 bytes e a lista termina num descritor todo zerado.
    O campo do nome fica no deslocamento 12 (importacao normal) ou 4
    (importacao atrasada, cujo descritor tem outro formato).
    """
    achados = []
    off = para_offset(rva, secs)
    if off is None:
        return achados
    campo_nome = 4 if atrasada else 12
    for i in range(4096):                       # teto de sanidade
        p = off + i * 20
        if p + 20 > len(dados):
            break
        bloco = dados[p:p + 20]
        if bloco == b"\0" * 20:
            break
        nome_rva = _u32(dados, p + campo_nome)
        if not nome_rva:
            continue
        # Alguns arquivos gravam o nome atrasado como endereco absoluto.
        pos = para_offset(nome_rva, secs)
        if pos is None and atrasada:
            pos = nome_rva if nome_rva < len(dados) else None
        nome = texto_em(dados, pos)
        if nome.lower().endswith(".dll") or nome.lower().endswith(".drv"):
            achados.append(nome.lower())
    return achados


def inspecionar(caminho):
    with open(caminho, "rb") as f:
        dados = f.read()

    arq, opcional, tam_opcional, n_secoes = cabecalho(dados)
    dirs = diretorios(dados, opcional)
    secs = secoes(dados, opcional, tam_opcional, n_secoes)

    def dir_rva(i):
        return dirs[i][0] if i < len(dirs) and dirs[i][0] else 0

    dlls, atrasadas = [], []
    if dir_rva(DIR_IMPORT):
        dlls = nomes_de_dll(dados, dir_rva(DIR_IMPORT), secs)
    if dir_rva(DIR_DELAY):
        atrasadas = nomes_de_dll(dados, dir_rva(DIR_DELAY), secs, atrasada=True)

    dotnet = 1 if dir_rva(DIR_CLR) else 0
    # Um binario .NET importa so mscoree.dll; sem esta marca o Tandem
    # concluiria que ele nao depende de nada.
    if dotnet and "mscoree.dll" not in dlls:
        dlls.append("mscoree.dll")

    return arq, dotnet, sorted(set(dlls)), sorted(set(atrasadas))


def main():
    if len(sys.argv) < 2:
        print("ERRO=uso: peinfo.py <arquivo>")
        return 2
    caminho = sys.argv[1]
    if not os.path.isfile(caminho):
        print("ERRO=arquivo nao encontrado")
        return 2
    try:
        arq, dotnet, dlls, atrasadas = inspecionar(caminho)
    except NaoEhPE as e:
        print("ERRO=%s" % e)
        return 1
    except Exception as e:                        # arquivo truncado, cortado
        print("ERRO=%s" % str(e).replace("\n", " ")[:200])
        return 1

    print("ARQUITETURA=%s" % arq)
    print("DOTNET=%d" % dotnet)
    print("DLLS=%s" % ",".join(dlls))
    print("ATRASADAS=%s" % ",".join(atrasadas))
    return 0


if __name__ == "__main__":
    sys.exit(main())
