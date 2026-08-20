#!/bin/bash
# Tandem - generic installer, for the Linux families that apt does not serve.
#
# Tandem ships as a .deb, which apt understands and dnf, pacman and zypper do
# not, so a Fedora, Arch or openSUSE user had no way to install it at all. This
# script is the way in for everyone else. It is shipped inside
# tandem_<version>_generic.tar.gz beside a payload/ tree and a MANIFEST, both
# written by build.py from its ONE layout - so what this installs is exactly
# what the .deb installs, and the two can never drift.
#
# Usage:
#   sudo ./install.sh
# To stage into a root of your choosing (a package build, or a test):
#   DESTDIR=/tmp/pkg ./install.sh
#
# Safe to run twice: every file is overwritten in place.
#
# set -e is right here - this is an installer, not one of the run-loop
# executables whose wait loops depend on commands that fail on purpose.
set -e

AQUI="$(cd -- "$(dirname -- "$0")" && pwd)" || exit 1
CARGA="$AQUI/payload"
LISTA="$AQUI/MANIFEST"
DESTINO="${DESTDIR:-}"

[ -f "$LISTA" ] || { echo "install.sh: MANIFEST not found beside me" >&2; exit 1; }
[ -d "$CARGA" ] || { echo "install.sh: payload/ not found beside me" >&2; exit 1; }

# A real install writes into system directories, which only root may do. A
# staged one (DESTDIR set) writes into a directory the caller already owns.
if [ -z "$DESTINO" ] && [ "$(id -u)" != 0 ]; then
    echo "install.sh: run me as root (sudo ./install.sh), or set DESTDIR to stage." >&2
    exit 1
fi

# Copy every file the MANIFEST names, each with its own mode. "install -D" makes
# the parent directories, so there is no separate mkdir pass.
while IFS=$'\t' read -r modo rel; do
    [ -n "$rel" ] || continue
    install -D -m "$modo" "$CARGA/$rel" "$DESTINO/$rel"
done < "$LISTA"

# The rest is exactly what the .deb's postinst does, and only for a real install
# to the live system - a staged copy has no caches to refresh and no user whose
# profile to set up. Each hook is optional: a machine missing one still gets a
# working Tandem, it just does not get that one cache refreshed.
if [ -z "$DESTINO" ] || [ "$DESTINO" = / ]; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
    update-mime-database /usr/share/mime 2>/dev/null || true
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

    # Apply the file associations to the profile of whoever invoked sudo, the
    # way the .deb does. The per-user work also happens on the first run, so a
    # miss here is recovered, not lost.
    USUARIO="${SUDO_USER:-}"
    [ -z "$USUARIO" ] && USUARIO="$(logname 2>/dev/null || true)"
    if [ -n "$USUARIO" ] && [ "$USUARIO" != root ]; then
        LAR="$(getent passwd "$USUARIO" | cut -d: -f6 || true)"
        if [ -n "$LAR" ] && [ -d "$LAR" ]; then
            runuser -u "$USUARIO" -- env TANDEM_SILENCIOSO=1 PATH=/usr/bin:/bin \
                tandem --primeira-vez >/dev/null 2>&1 || true
        fi
    fi

    # The install notice, READ (never sourced) from the catalogue in the
    # machine's language - the same awk pull the .deb's postinst uses, so a file
    # that will one day arrive from a translator cannot execute as root.
    diz_msg() {
        local chave="$1" lang arq base
        base=/usr/lib/tandem/idiomas
        lang="${LANG:-}"; lang="${lang%%.*}"; lang="${lang%%@*}"
        for arq in "$base/$lang.txt" "$base/${lang%%_*}.txt" "$base/en.txt"; do
            [ -r "$arq" ] || continue
            T_CHAVE="@$chave" awk '
                BEGIN { alvo = ENVIRON["T_CHAVE"] }
                $0 == alvo { dentro = 1; next }
                substr($0, 1, 1) == "@" { dentro = 0 }
                dentro { print }' "$arq"
            return 0
        done
        return 0
    }
    printf '\n'; diz_msg instalado_resumo || true; printf '\n'
    diz_msg envio_aviso_ligado || true; printf '\n'
fi
exit 0
