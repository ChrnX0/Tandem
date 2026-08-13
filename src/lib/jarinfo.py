#!/usr/bin/env python3
"""Reads the label of a .jar WITHOUT running anything.

A .jar is a zip with a manifest, and the manifest answers the two questions
that decide whether a double click can work at all:

  Is this a program?  Only a jar with a Main-Class can be run. Half of the
  .jar files on a lay user's machine are LIBRARIES - pieces of a program - and
  Java's answer to a double click on one is "no main manifest attribute", six
  words nobody outside the trade can act on. Reading the manifest first turns
  that into "this file is a piece of a program, not a program".

  Which Java does it need?  Every .class carries the version of the compiler
  that produced it in bytes 6 and 7. Java refuses to load a class newer than
  itself, and its message - UnsupportedClassVersionError, class file version
  65.0 - names a number that appears nowhere on the download page. Subtracting
  44 turns 65 into 21, and 21 is a number the owner can compare with the Java
  he has.

Classes under META-INF/versions/ are deliberately left out of that maximum:
they are the multi-release mechanism, present precisely so that a NEWER Java
can pick them up, and counting them would demand a Java the program does not
actually require.

Usage:  jarinfo.py <file.jar>
Output: KEY=VALUE lines, the same contract as peinfo.py and apkinfo.py

PRINCIPAL=<Main-Class, empty if there is none>
JAVA=<minimum Java version, empty if it cannot be worked out>
MAIOR=<raw class file major, for the log>
JAVAFX=0|1
AGENTE=0|1              1 = a Java agent, which is not run by double clicking
MULTI=0|1               1 = multi-release jar
DEPENDENCIAS=<Class-Path from the manifest, comma separated>
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
import zipfile

MANIFESTO = "META-INF/MANIFEST.MF"

# How many .class entries to sample when the main class itself is not where the
# manifest says. Reading every entry of a fat jar means reading tens of
# thousands of headers for an answer the first few hundred already give.
AMOSTRA = 400


class JarRuim(Exception):
    pass


def manifesto(z):
    """The manifest as a dict, with continuation lines already joined.

    The format wraps at 72 bytes and continues the value on the next line,
    marked by a single leading space. A Class-Path with four entries is
    routinely cut in the middle of a file name, so reading line by line without
    joining produces a path that does not exist.
    """
    try:
        bruto = z.read(MANIFESTO)
    except KeyError:
        return {}
    texto = bruto.decode("utf-8", "replace").replace("\r\n", "\n").replace("\r", "\n")
    linhas = []
    for linha in texto.split("\n"):
        if linha.startswith(" ") and linhas:
            linhas[-1] += linha[1:]
        else:
            linhas.append(linha)
    campos = {}
    for linha in linhas:
        if ":" not in linha:
            continue
        chave, _, valor = linha.partition(":")
        campos[chave.strip().lower()] = valor.strip()
    return campos


def maior_de(dados):
    """The class file major version, from bytes 6-7 of a .class."""
    if len(dados) < 8 or dados[:4] != b"\xca\xfe\xba\xbe":
        return 0
    return struct.unpack_from(">H", dados, 6)[0]


def versao(z, principal):
    """(major of the main class, or the highest major in the jar)."""
    if principal:
        caminho = principal.replace(".", "/") + ".class"
        for tentativa in (caminho, "BOOT-INF/classes/" + caminho,
                          "WEB-INF/classes/" + caminho):
            try:
                return maior_de(z.read(tentativa)[:8])
            except KeyError:
                continue
    # No main class, or it is somewhere only its own loader knows about: the
    # highest version among the ordinary classes is the honest answer, because
    # any of them may be the one that fails to load.
    maior = 0
    vistos = 0
    for nome in z.namelist():
        if not nome.endswith(".class") or nome.startswith("META-INF/versions/"):
            continue
        try:
            maior = max(maior, maior_de(z.read(nome)[:8]))
        except (KeyError, zipfile.BadZipFile, OSError):
            continue
        vistos += 1
        if vistos >= AMOSTRA:
            break
    return maior


def usa_javafx(z, campos, principal):
    """Whether the program needs JavaFX, which does not come with Java.

    Three signs, in order of how much they prove. A jar that carries javafx
    inside itself needs nothing extra; one that only REFERENCES it needs the
    package installed - and that is the case that fails on a lay user's
    machine, with a ClassNotFoundException nobody can read.
    """
    for nome in z.namelist():
        if nome.startswith("javafx/") or "/javafx/" in nome:
            return True
    if "javafx" in campos.get("class-path", "").lower():
        return True
    if principal:
        caminho = principal.replace(".", "/") + ".class"
        try:
            # The constant pool holds the name of every class referenced, as
            # plain text: javafx/application/Application shows up whole.
            if b"javafx/" in z.read(caminho):
                return True
        except (KeyError, zipfile.BadZipFile, OSError):
            pass
    return False


def inspecionar(caminho):
    try:
        z = zipfile.ZipFile(caminho)
    except zipfile.BadZipFile:
        # A .jar is a zip whose index lives at the END of the file, so an
        # interrupted download breaks it in a way that is always detectable.
        raise JarRuim("zip_invalido")
    except OSError as e:
        raise JarRuim(str(e))
    with z:
        campos = manifesto(z)
        principal = campos.get("main-class", "")
        agente = 1 if (not principal and
                       (campos.get("premain-class") or
                        campos.get("launcher-agent-class"))) else 0
        multi = 1 if campos.get("multi-release", "").lower() == "true" else 0
        maior = versao(z, principal)
        fx = 1 if usa_javafx(z, campos, principal) else 0
        deps = [p for p in campos.get("class-path", "").split() if p]
    return principal, maior, fx, agente, multi, deps


def main():
    if len(sys.argv) < 2:
        print("ERRO=uso")
        return 2
    caminho = sys.argv[1]
    if not os.path.isfile(caminho):
        print("ERRO=sem_arquivo")
        return 2
    try:
        principal, maior, fx, agente, multi, deps = inspecionar(caminho)
    except JarRuim as e:
        print("ERRO=%s" % e)
        return 1
    except Exception as e:
        print("ERRO=cru|%s" % str(e).replace("\n", " ")[:200])
        return 1

    print("PRINCIPAL=%s" % principal)
    # Major 45 is Java 1.1 and the offset has held for every release since;
    # below that the number is not a version, it is a damaged file.
    print("JAVA=%s" % (maior - 44 if maior >= 45 else ""))
    print("MAIOR=%d" % maior)
    print("JAVAFX=%d" % fx)
    print("AGENTE=%d" % agente)
    print("MULTI=%d" % multi)
    print("DEPENDENCIAS=%s" % ",".join(deps))
    return 0


if __name__ == "__main__":
    sys.exit(main())
