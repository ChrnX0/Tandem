#!/usr/bin/env python3
"""Gera pacotes Android sinteticos para os testes do Tandem.

Escreve um AndroidManifest.xml binario (AXML) de verdade - string pool,
mapa de recursos e tag START - para que o apkinfo.py seja exercitado no
mesmo caminho de codigo que roda com um APK real. Nao depende do SDK do
Android nem de rede.

Uso:  mkapk.py <diretorio-de-saida>
"""
import os
import struct
import sys
import zipfile

STRING_POOL = 0x0001
RES_MAP = 0x0180
START_TAG = 0x0102
END_TAG = 0x0103

ATTR_MINSDK_RES = 0x0101020C  # android:minSdkVersion
TYPE_INT_DEC = 0x10
TYPE_STRING = 0x03


def _pool(strings):
    """Serializa um chunk de string pool em UTF-16 (o formato do aapt)."""
    offsets, blob = [], b""
    for s in strings:
        offsets.append(len(blob))
        raw = s.encode("utf-16-le")
        blob += struct.pack("<H", len(s)) + raw + b"\x00\x00"
    while len(blob) % 4:
        blob += b"\x00"

    hsize = 28
    str_start = hsize + 4 * len(strings)
    csize = str_start + len(blob)
    head = struct.pack(
        "<HHIIIIII",
        STRING_POOL, hsize, csize,
        len(strings), 0,       # contagem de strings, de estilos
        0,                     # flags: 0 = UTF-16
        str_start, 0,
    )
    return head + struct.pack("<%dI" % len(offsets), *offsets) + blob


def _resmap(ids):
    hsize = 8
    csize = hsize + 4 * len(ids)
    return struct.pack("<HHI", RES_MAP, hsize, csize) + struct.pack(
        "<%dI" % len(ids), *ids)


def _attr(ns, name_i, raw_i, dtype, data):
    return struct.pack("<III", ns, name_i, raw_i) + struct.pack(
        "<HBBI", 20, 0, dtype, data)


def _start_tag(name_i, attrs):
    hsize = 16
    body = struct.pack("<II", 0xFFFFFFFF, name_i)
    # ResXMLTree_attrExt: attributeStart, attributeSize, attributeCount,
    # idIndex, classIndex, styleIndex. attributeStart e' relativo ao inicio
    # desta struct (20 bytes), attributeSize e' o tamanho de CADA atributo.
    body += struct.pack("<HHHHHH", 20, 20, len(attrs), 0, 0, 0)
    body += b"".join(attrs)
    csize = hsize + len(body)
    # header: tipo, hsize, csize, linha, comentario
    return struct.pack("<HHIII", START_TAG, hsize, csize, 1, 0xFFFFFFFF) + body


def manifesto(pacote, minsdk):
    """AndroidManifest.xml binario minimo com <manifest package> e <uses-sdk>."""
    # A ordem importa: o indice de cada string e usado nos atributos, e o
    # mapa de recursos e indexado pelo indice do NOME do atributo.
    strings = ["package", "minSdkVersion", "manifest", "uses-sdk", pacote]
    I_PACKAGE, I_MINSDK, I_MANIFEST, I_USESSDK, I_VALOR = range(5)

    # Uma entrada por string; so as que sao nome de atributo importam.
    resmap = [0] * len(strings)
    resmap[I_MINSDK] = ATTR_MINSDK_RES

    corpo = _start_tag(I_MANIFEST, [
        _attr(0xFFFFFFFF, I_PACKAGE, I_VALOR, TYPE_STRING, I_VALOR),
    ])
    corpo += _start_tag(I_USESSDK, [
        _attr(0xFFFFFFFF, I_MINSDK, 0xFFFFFFFF, TYPE_INT_DEC, minsdk),
    ])

    dados = _pool(strings) + _resmap(resmap) + corpo
    cabecalho = struct.pack("<HHI", 0x0003, 8, len(dados) + 8)
    return cabecalho + dados


def apk(caminho, pacote="com.exemplo.app", minsdk=21, abis=(), extras=None):
    with zipfile.ZipFile(caminho, "w") as z:
        z.writestr("AndroidManifest.xml", manifesto(pacote, minsdk))
        z.writestr("classes.dex", b"dex\n035\x00" + b"\x00" * 64)
        for a in abis:
            z.writestr("lib/%s/libmain.so" % a, b"\x7fELF" + b"\x00" * 32)
        for nome, dados in (extras or {}).items():
            z.writestr(nome, dados)
    return caminho


def pacote_dividido(caminho, base_pacote="com.exemplo.jogo", minsdk=24,
                    abis=("arm64-v8a",), com_obb=False, splits=("config.xxhdpi",)):
    """Monta um .xapk/.apks: varios .apk dentro de um zip, sem manifesto na raiz."""
    tmp_base = caminho + ".base.tmp"
    apk(tmp_base, base_pacote, minsdk, abis)
    with open(tmp_base, "rb") as f:
        base_bytes = f.read()
    os.remove(tmp_base)

    with zipfile.ZipFile(caminho, "w") as z:
        z.writestr("%s.apk" % base_pacote, base_bytes)
        for s in splits:
            z.writestr("%s.%s.apk" % (base_pacote, s), base_bytes)
        z.writestr("manifest.json", b'{"package_name": "%s"}'
                   % base_pacote.encode())
        if com_obb:
            z.writestr("Android/obb/%s/main.1.%s.obb" % (base_pacote, base_pacote),
                       b"\x00" * 128)
    return caminho


def pe(caminho, maquina):
    """Executavel PE minimo, so o suficiente para t_pe_arch decidir."""
    cab = bytearray(b"\x00" * 0x100)
    cab[0:2] = b"MZ"
    struct.pack_into("<I", cab, 60, 0x80)          # e_lfanew
    cab[0x80:0x84] = b"PE\x00\x00"
    struct.pack_into("<H", cab, 0x84, maquina)     # Machine
    with open(caminho, "wb") as f:
        f.write(bytes(cab))
    return caminho


def pe_com_imports(caminho, maquina=0x8664, dlls=("KERNEL32.dll",)):
    """PE com tabela de importacoes de verdade, para exercitar o peinfo.

    Uma secao so, endereco virtual igual ao deslocamento no arquivo, para que
    a conversao RVA->offset do leitor seja exercitada com numeros que nao
    coincidem por acaso.
    """
    SEC_RVA, SEC_RAW = 0x1000, 0x400
    corpo = bytearray()

    def rva(off_no_corpo):
        return SEC_RVA + off_no_corpo

    # nomes das DLLs, um a um, terminados em zero
    nomes = {}
    for d in dlls:
        nomes[d] = rva(len(corpo))
        corpo += d.encode("ascii") + b"\x00"
    while len(corpo) % 4:
        corpo += b"\x00"

    # descritores de importacao: 20 bytes cada, terminados por um zerado
    desc_rva = rva(len(corpo))
    for d in dlls:
        corpo += struct.pack("<IIIII", 0, 0, 0, nomes[d], 0)
    corpo += b"\x00" * 20

    secao_bruta = bytes(corpo).ljust(0x200, b"\x00")

    cab = bytearray(SEC_RAW)
    cab[0:2] = b"MZ"
    struct.pack_into("<I", cab, 0x3C, 0x80)
    pe = 0x80
    cab[pe:pe + 4] = b"PE\x00\x00"
    e64 = maquina == 0x8664
    tam_opcional = 240 if e64 else 224
    struct.pack_into("<HHIIIHH", cab, pe + 4,
                     maquina, 1, 0, 0, 0, tam_opcional, 0x0002)
    opc = pe + 24
    struct.pack_into("<H", cab, opc, 0x20B if e64 else 0x10B)
    # NumberOfRvaAndSizes e a tabela de diretorios
    base_dir = opc + (112 if e64 else 96)
    struct.pack_into("<I", cab, base_dir - 4, 16)
    struct.pack_into("<II", cab, base_dir + 8, desc_rva, len(dlls) * 20)
    # cabecalho da secao
    sec = opc + tam_opcional
    cab[sec:sec + 8] = b".text\x00\x00\x00"
    struct.pack_into("<IIII", cab, sec + 8,
                     len(secao_bruta), SEC_RVA, len(secao_bruta), SEC_RAW)

    with open(caminho, "wb") as f:
        f.write(bytes(cab) + secao_bruta)
    return caminho


def main():
    destino = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(destino, exist_ok=True)
    j = lambda n: os.path.join(destino, n)

    apk(j("universal.apk"), "com.exemplo.universal", 21, ())
    apk(j("x86.apk"), "com.exemplo.x86", 23, ("x86_64", "x86"))
    apk(j("armonly.apk"), "com.exemplo.armonly", 26, ("arm64-v8a", "armeabi-v7a"))
    apk(j("futuro.apk"), "com.exemplo.futuro", 99, ("x86_64",))
    pacote_dividido(j("jogo.xapk"), com_obb=True)
    pacote_dividido(j("app.apks"), "com.exemplo.apks", 24, ("x86_64",),
                    False, ("config.pt", "config.x86_64"))

    with open(j("corrompido.apk"), "wb") as f:
        f.write(b"PK\x03\x04isto nao e um zip valido de jeito nenhum")
    with open(j("vazio.apk"), "wb") as f:
        f.write(b"")

    pe(j("prog32.exe"), 0x014C)
    pe(j("prog64.exe"), 0x8664)
    pe(j("progarm.exe"), 0xAA64)
    with open(j("naoexe.exe"), "wb") as f:
        f.write(b"isto nao e um PE\n")

    pe_com_imports(j("imports64.exe"), 0x8664,
                   ("KERNEL32.dll", "MSVCP140.dll", "VCRUNTIME140.dll"))
    pe_com_imports(j("imports32.exe"), 0x014C,
                   ("kernel32.dll", "hasp_windows_x64.dll"))
    pe_com_imports(j("importslimpo.exe"), 0x8664, ("KERNEL32.dll", "USER32.dll"))

    print("gerado em %s" % destino)


if __name__ == "__main__":
    main()
