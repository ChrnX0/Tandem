#!/usr/bin/env python3
"""Inspects APK / XAPK / APKS without needing the Android SDK.

Usage:  apkinfo.py <file>
Output: KEY=VALUE lines (easy to read from the shell with eval/grep)

FORMATO=apk|xapk|apks|desconhecido
PACOTE=<package name, or empty>
MINSDK=<number, or empty>
ABIS=<comma-separated list, empty = universal>
SPLITS=<how many apks inside the package>
OBB=<0|1>
ERRO=<token>[|<data>]  when something failed; see t_erro_do_leitor
   The field carries a TOKEN, never a sentence. It used to carry Portuguese
   prose, and the handler printed it straight to the owner - so this file held
   user-facing messages that no translation tool in the tree had ever opened,
   and a raw Python exception reached a shop owner in English. The shell turns
   a token into a sentence in the owner's language; an unknown token is logged
   and answered with a generic one, because a reader that learns a new failure
   must not be able to produce silence.
"""
import sys, zipfile, struct, os

# ------------------------------------------------------------------ AXML

STRING_POOL = 0x0001
RES_MAP     = 0x0180
START_TAG   = 0x0102

ATTR_MINSDK_RES = 0x0101020C  # android:minSdkVersion


def _ler_pool(buf, off):
    """Reads a string pool chunk. Returns (list_of_strings, chunk_size)."""
    tipo, hsize, csize = struct.unpack_from("<HHI", buf, off)
    if tipo != STRING_POOL:
        return [], csize
    count, _styles, flags, str_start, _sty_start = struct.unpack_from("<IIIII", buf, off + 8)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from("<%dI" % count, buf, off + hsize)
    base = off + str_start
    out = []
    for o in offsets:
        p = base + o
        try:
            if utf8:
                # two counts (chars, bytes), each one 1 or 2 bytes long
                n = buf[p]; p += 1
                if n & 0x80:
                    p += 1
                n = buf[p]; p += 1
                if n & 0x80:
                    n = ((n & 0x7F) << 8) | buf[p]; p += 1
                out.append(buf[p:p + n].decode("utf-8", "replace"))
            else:
                n = struct.unpack_from("<H", buf, p)[0]; p += 2
                if n & 0x8000:
                    n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", buf, p)[0]; p += 2
                out.append(buf[p:p + n * 2].decode("utf-16-le", "replace"))
        except Exception:
            out.append("")
    return out, csize


def ler_manifesto(dados):
    """Extracts (package, minSdk) from the binary AndroidManifest.xml."""
    pacote, minsdk = "", None
    if len(dados) < 8:
        return pacote, minsdk
    magia = struct.unpack_from("<I", dados, 0)[0]
    if magia not in (0x00080003, 0x00080001):
        return pacote, minsdk

    pool, resmap = [], []
    off = 8
    total = len(dados)
    while off + 8 <= total:
        try:
            tipo, hsize, csize = struct.unpack_from("<HHI", dados, off)
        except Exception:
            break
        if csize <= 0 or off + csize > total:
            break

        if tipo == STRING_POOL:
            pool, _ = _ler_pool(dados, off)

        elif tipo == RES_MAP:
            n = (csize - hsize) // 4
            resmap = list(struct.unpack_from("<%dI" % n, dados, off + hsize))

        elif tipo == START_TAG:
            p = off + hsize
            _ns, nome_i = struct.unpack_from("<II", dados, p)
            a_start, _a_size, a_count = struct.unpack_from("<HHH", dados, p + 8)
            nome = pool[nome_i] if 0 <= nome_i < len(pool) else ""
            ap = off + hsize + a_start
            for _ in range(a_count):
                if ap + 20 > total:
                    break
                _ans, an_i, raw_i = struct.unpack_from("<III", dados, ap)
                _sz, _r0, dtype, data = struct.unpack_from("<HBBI", dados, ap + 12)
                attr = pool[an_i] if 0 <= an_i < len(pool) else ""
                res_id = resmap[an_i] if 0 <= an_i < len(resmap) else 0
                if nome == "manifest" and attr == "package":
                    pacote = pool[raw_i] if 0 <= raw_i < len(pool) else pacote
                if nome == "uses-sdk" and (attr == "minSdkVersion" or res_id == ATTR_MINSDK_RES):
                    if dtype == 0x10:            # TYPE_INT_DEC
                        minsdk = data
                    elif 0 <= raw_i < len(pool):
                        try:
                            minsdk = int(pool[raw_i])
                        except Exception:
                            pass
                ap += 20
        off += csize
    return pacote, minsdk


# ------------------------------------------------------------------ APK

def abis_de(z):
    achados = set()
    for nome in z.namelist():
        if nome.startswith("lib/") and nome.count("/") >= 2:
            achados.add(nome.split("/")[1])
    return sorted(achados)


def inspecionar_apk_bytes(dados_apk, nome_exibicao=""):
    import io
    with zipfile.ZipFile(io.BytesIO(dados_apk)) as z:
        pacote, minsdk = "", None
        try:
            pacote, minsdk = ler_manifesto(z.read("AndroidManifest.xml"))
        except Exception:
            pass
        return pacote, minsdk, abis_de(z)


def internos_cifrados(nomes):
    """The .apk entries of an archive whose contents cannot be read."""
    return [n for n in nomes if n.lower().endswith(".apk")]


def main():
    if len(sys.argv) < 2:
        print("ERRO=uso")
        return 2
    caminho = sys.argv[1]
    if not os.path.isfile(caminho):
        print("ERRO=sem_arquivo")
        return 2

    ext = os.path.splitext(caminho)[1].lower()
    formato, pacote, minsdk, abis, splits, obb = "desconhecido", "", None, [], 1, 0
    cifrado = 0

    try:
        with zipfile.ZipFile(caminho) as z:
            nomes = z.namelist()
            # Some .apkm files are encrypted by the site that distributes them,
            # and only that site's own installer opens one. Nothing else can, so
            # the honest answer is to say so instead of failing at extraction
            # with a message about a bad password. Bit 0 of the zip
            # general-purpose flag is where the file admits it.
            cifrado = 1 if any(i.flag_bits & 0x1 for i in z.infolist()) else 0
            if cifrado:
                # Nothing further can be read, and trying produces a Python
                # exception in English about a missing password. The format is
                # known from the name and the encryption is the whole verdict.
                formato = {".xapk": "xapk", ".apks": "apks",
                           ".apkm": "apkm"}.get(ext, "apk")
                print("FORMATO=%s" % formato)
                print("PACOTE=")
                print("MINSDK=")
                print("ABIS=")
                print("SPLITS=%d" % len(internos_cifrados(nomes)))
                print("OBB=0")
                print("CIFRADO=1")
                return 0
            internos = [n for n in nomes if n.lower().endswith(".apk")]
            tem_manifesto = "AndroidManifest.xml" in nomes

            if internos and not tem_manifesto:
                # split package (xapk / apks / apkm)
                formato = {".xapk": "xapk", ".apks": "apks", ".apkm": "apkm"}.get(ext, "xapk")
                splits = len(internos)
                obb = 1 if any(n.lower().endswith(".obb") for n in nomes) else 0
                # the base is usually the largest one, or the one without
                # "config"/"split" in its name
                candidatas = [n for n in internos
                              if "config." not in n.lower() and "split_" not in n.lower()]
                base = candidatas[0] if candidatas else max(
                    internos, key=lambda n: z.getinfo(n).file_size)
                pacote, minsdk, abis = inspecionar_apk_bytes(z.read(base))
                if not abis:
                    for n in internos:
                        for a in ("arm64-v8a", "armeabi-v7a", "x86_64", "x86"):
                            if a.replace("-", "_") in n.lower().replace("-", "_"):
                                abis.append(a)
                    abis = sorted(set(abis))

            elif tem_manifesto:
                formato = "apk"
                splits = 1
                try:
                    pacote, minsdk = ler_manifesto(z.read("AndroidManifest.xml"))
                except Exception:
                    pass
                abis = abis_de(z)
    except zipfile.BadZipFile:
        print("ERRO=apk_corrompido")
        return 1
    except Exception as e:
        print("ERRO=cru|%s" % str(e).replace("\n", " ")[:200])
        return 1

    print("FORMATO=%s" % formato)
    print("PACOTE=%s" % pacote)
    print("MINSDK=%s" % (minsdk if minsdk is not None else ""))
    print("ABIS=%s" % ",".join(abis))
    print("SPLITS=%d" % splits)
    print("OBB=%d" % obb)
    print("CIFRADO=%d" % cifrado)
    return 0


if __name__ == "__main__":
    sys.exit(main())
