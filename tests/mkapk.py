#!/usr/bin/env python3
"""Generates synthetic Android packages for the Tandem tests.

Writes a real binary AndroidManifest.xml (AXML) - string pool, resource
map and START tag - so that apkinfo.py is exercised through the same code
path it runs with a real APK. Depends on neither the Android SDK nor the
network.

Usage:  mkapk.py <output-directory>
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
    """Serializes a string pool chunk in UTF-16 (the format aapt uses)."""
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
        len(strings), 0,       # string count, style count
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
    # idIndex, classIndex, styleIndex. attributeStart is relative to the
    # start of this struct (20 bytes), attributeSize is the size of EACH
    # attribute.
    body += struct.pack("<HHHHHH", 20, 20, len(attrs), 0, 0, 0)
    body += b"".join(attrs)
    csize = hsize + len(body)
    # header: type, hsize, csize, line, comment
    return struct.pack("<HHIII", START_TAG, hsize, csize, 1, 0xFFFFFFFF) + body


def manifesto(pacote, minsdk):
    """Minimal binary AndroidManifest.xml with <manifest package> and <uses-sdk>."""
    # The order matters: the index of each string is used in the attributes,
    # and the resource map is indexed by the index of the attribute NAME.
    strings = ["package", "minSdkVersion", "manifest", "uses-sdk", pacote]
    I_PACKAGE, I_MINSDK, I_MANIFEST, I_USESSDK, I_VALOR = range(5)

    # One entry per string; only the ones that are attribute names matter.
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
    """Builds a .xapk/.apks: several .apk inside a zip, no manifest at the root."""
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


def pacote_apkm(caminho, base_pacote="com.exemplo.apkm", cifrado=False):
    """Builds an .apkm, the format APKMirror distributes.

    Two things separate it from a .xapk: the metadata file is info.json rather
    than manifest.json, and some of them are ENCRYPTED by the site - in which
    case nothing but that site's own installer opens one. That is worth
    detecting rather than discovering at extraction time, so this can write both.
    """
    tmp_base = caminho + ".base.tmp"
    apk(tmp_base, base_pacote, 26, ("arm64-v8a", "armeabi-v7a"))
    with open(tmp_base, "rb") as f:
        base_bytes = f.read()
    os.remove(tmp_base)

    with zipfile.ZipFile(caminho, "w") as z:
        z.writestr("base.apk", base_bytes)
        z.writestr("split_config.arm64_v8a.apk", base_bytes)
        z.writestr("split_config.xxhdpi.apk", base_bytes)
        z.writestr("info.json", b'{"apk_title":"exemplo","pname":"%s"}'
                   % base_pacote.encode())
    if cifrado:
        # zipfile cannot write an encrypted archive, so bit 0 of the
        # general-purpose flag is set by hand - in the local headers AND in the
        # central directory, because a reader may consult either.
        with open(caminho, "rb") as f:
            d = bytearray(f.read())
        i = 0
        while True:
            i = d.find(b"PK\x03\x04", i)
            if i < 0:
                break
            d[i + 6] |= 0x01
            i += 4
        i = 0
        while True:
            i = d.find(b"PK\x01\x02", i)
            if i < 0:
                break
            d[i + 8] |= 0x01
            i += 4
        with open(caminho, "wb") as f:
            f.write(bytes(d))
    return caminho


def pe(caminho, maquina):
    """Minimal PE executable, just enough for t_pe_arch to decide."""
    cab = bytearray(b"\x00" * 0x100)
    cab[0:2] = b"MZ"
    struct.pack_into("<I", cab, 60, 0x80)          # e_lfanew
    cab[0x80:0x84] = b"PE\x00\x00"
    struct.pack_into("<H", cab, 0x84, maquina)     # Machine
    with open(caminho, "wb") as f:
        f.write(bytes(cab))
    return caminho


def pe_com_imports(caminho, maquina=0x8664, dlls=("KERNEL32.dll",)):
    """PE with a real import table, to exercise peinfo.

    A single section, virtual address equal to the offset in the file, so
    that the reader's RVA->offset conversion is exercised with numbers that
    do not match by accident.
    """
    SEC_RVA, SEC_RAW = 0x1000, 0x400
    corpo = bytearray()

    def rva(off_no_corpo):
        return SEC_RVA + off_no_corpo

    # DLL names, one by one, zero-terminated
    nomes = {}
    for d in dlls:
        nomes[d] = rva(len(corpo))
        corpo += d.encode("ascii") + b"\x00"
    while len(corpo) % 4:
        corpo += b"\x00"

    # import descriptors: 20 bytes each, terminated by an all-zero one
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
    # NumberOfRvaAndSizes and the directory table
    base_dir = opc + (112 if e64 else 96)
    struct.pack_into("<I", cab, base_dir - 4, 16)
    struct.pack_into("<II", cab, base_dir + 8, desc_rva, len(dlls) * 20)
    # section header
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
    pacote_apkm(j("mirror.apkm"))
    pacote_apkm(j("trancado.apkm"), "com.exemplo.trancado", cifrado=True)

    with open(j("corrompido.apk"), "wb") as f:
        f.write(b"PK\x03\x04this is not a valid zip in any way at all")
    with open(j("vazio.apk"), "wb") as f:
        f.write(b"")

    pe(j("prog32.exe"), 0x014C)
    pe(j("prog64.exe"), 0x8664)
    pe(j("progarm.exe"), 0xAA64)
    with open(j("naoexe.exe"), "wb") as f:
        f.write(b"this is not a PE\n")

    pe_com_imports(j("imports64.exe"), 0x8664,
                   ("KERNEL32.dll", "MSVCP140.dll", "VCRUNTIME140.dll"))
    pe_com_imports(j("imports32.exe"), 0x014C,
                   ("kernel32.dll", "hasp_windows_x64.dll"))
    pe_com_imports(j("importslimpo.exe"), 0x8664, ("KERNEL32.dll", "USER32.dll"))

    print("generated in %s" % destino)


if __name__ == "__main__":
    main()
