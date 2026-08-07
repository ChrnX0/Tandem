#!/usr/bin/env python3
"""Build the Tandem .deb package.

Works on any OS with Python 3 - it writes the `ar` archive by hand, so
neither dpkg-deb nor a Debian host is required.

    python3 build.py            -> tandem_<version>_all.deb
    python3 build.py --check    -> build, then verify the archive
"""
import gzip
import io
import os
import sys
import tarfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
DEB = os.path.join(ROOT, "debian")
MAN = os.path.join(ROOT, "man")
MTIME = 1735689600  # fixed, for reproducible builds

MANPAGES = ["tandem", "tandem-exe", "tandem-apk", "tandem-android", "tandem-repair"]

# path in package  <-  path in repo, mode
LAYOUT = [
    ("usr/bin/tandem",           "bin/tandem",           0o755),
    ("usr/bin/tandem-exe",       "bin/tandem-exe",       0o755),
    ("usr/bin/tandem-apk",       "bin/tandem-apk",       0o755),
    ("usr/bin/tandem-android",   "bin/tandem-android",   0o755),
    ("usr/bin/tandem-repair",    "bin/tandem-repair",    0o755),
    ("usr/lib/tandem/common.sh",   "lib/common.sh",   0o644),
    ("usr/lib/tandem/winedeps.sh", "lib/winedeps.sh", 0o644),
    ("usr/lib/tandem/apkinfo.py",  "lib/apkinfo.py",  0o755),
    ("usr/share/applications/tandem.desktop",         "applications/tandem.desktop",         0o644),
    ("usr/share/applications/tandem-exe.desktop",     "applications/tandem-exe.desktop",     0o644),
    ("usr/share/applications/tandem-apk.desktop",     "applications/tandem-apk.desktop",     0o644),
    ("usr/share/applications/tandem-android.desktop", "applications/tandem-android.desktop", 0o644),
    ("usr/share/icons/hicolor/scalable/apps/tandem.svg", "icons/tandem.svg", 0o644),
    ("usr/share/polkit-1/rules.d/49-tandem.rules", "polkit/49-tandem.rules", 0o644),
    ("usr/share/mime/packages/tandem.xml", "mime/tandem.xml", 0o644),
]

# Files that Debian policy requires but that live outside src/. The gzipped
# ones must be deterministic, so gzip_bytes() pins the timestamp too.
DOCS = [
    ("usr/share/doc/tandem/copyright", os.path.join(DEB, "copyright"), False),
    ("usr/share/doc/tandem/changelog.gz", os.path.join(DEB, "changelog"), True),
] + [
    ("usr/share/man/man1/%s.1.gz" % n, os.path.join(MAN, "%s.1" % n), True)
    for n in MANPAGES
]


def version():
    with open(os.path.join(DEB, "control"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("Version:"):
                return line.split(":", 1)[1].strip()
    raise SystemExit("Version missing from debian/control")


def _info(name, size=0, mode=0o644, directory=False):
    i = tarfile.TarInfo(name)
    i.size = size
    i.mode = 0o755 if directory else mode
    i.mtime = MTIME
    i.uid = i.gid = 0
    i.uname = i.gname = "root"
    if directory:
        i.type = tarfile.DIRTYPE
    return i


def add_bytes(tar, name, data, mode=0o644):
    tar.addfile(_info(name, len(data), mode), io.BytesIO(data))


def read(path):
    with open(path, "rb") as f:
        return f.read().replace(b"\r\n", b"\n")


def gzip_bytes(data):
    """gzip with a fixed mtime, so two builds of the same tree match."""
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode="wb", mtime=MTIME) as gz:
        gz.write(data)
    return out.getvalue()


def dirs_for(paths):
    seen = set()
    for p in paths:
        parts = p.split("/")[:-1]
        for i in range(1, len(parts) + 1):
            seen.add("/".join(parts[:i]) + "/")
    return sorted(seen)


def make_targz(build):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tar:
        build(tar)
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode="wb", mtime=MTIME) as gz:
        gz.write(raw.getvalue())
    return out.getvalue()


def build_control(tar):
    tar.addfile(_info("./", directory=True))
    add_bytes(tar, "./control", read(os.path.join(DEB, "control")))
    for script in ("postinst", "postrm"):
        p = os.path.join(DEB, script)
        if os.path.exists(p):
            add_bytes(tar, "./" + script, read(p), 0o755)


def build_data(tar):
    tar.addfile(_info("./", directory=True))
    todo = [(dst, os.path.join(SRC, src), mode, False)
            for dst, src, mode in LAYOUT]
    todo += [(dst, path, 0o644, gz) for dst, path, gz in DOCS]

    for d in dirs_for([dst for dst, _, _, _ in todo]):
        tar.addfile(_info("./" + d, directory=True))
    for dst, path, mode, gz in todo:
        if not os.path.exists(path):
            raise SystemExit("missing source file: %s" % path)
        data = read(path)
        add_bytes(tar, "./" + dst, gzip_bytes(data) if gz else data, mode)


def ar_entry(name, data):
    header = "{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}`\n".format(
        name, MTIME, 0, 0, "100644", len(data)).encode("ascii")
    assert len(header) == 60
    return header + data + (b"\n" if len(data) % 2 else b"")


def check(path):
    with open(path, "rb") as f:
        blob = f.read()
    assert blob[:8] == b"!<arch>\n", "bad ar magic"
    pos, names = 8, []
    while pos < len(blob):
        head = blob[pos:pos + 60]
        pos += 60
        name = head[0:16].decode().strip()
        size = int(head[48:58].decode().strip())
        body = blob[pos:pos + size]
        pos += size + (size % 2)
        names.append(name)
        if name.endswith(".tar.gz"):
            with tarfile.open(fileobj=io.BytesIO(gzip.decompress(body))) as t:
                for m in t.getmembers():
                    if m.isfile():
                        print("   %-52s %s %s" % (m.name, oct(m.mode), m.uname))
        elif name == "debian-binary":
            assert body == b"2.0\n", "bad debian-binary"
    assert names == ["debian-binary", "control.tar.gz", "data.tar.gz"], names
    print("OK: archive is well formed")


def main():
    out = os.path.join(ROOT, "tandem_%s_all.deb" % version())
    blob = b"!<arch>\n"
    blob += ar_entry("debian-binary", b"2.0\n")
    blob += ar_entry("control.tar.gz", make_targz(build_control))
    blob += ar_entry("data.tar.gz", make_targz(build_data))
    with open(out, "wb") as f:
        f.write(blob)
    print("built %s (%d bytes)" % (out, len(blob)))
    if "--check" in sys.argv:
        check(out)


if __name__ == "__main__":
    main()
