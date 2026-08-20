#!/bin/bash
# Tandem - generic uninstaller. The companion to install.sh: it removes exactly
# what the MANIFEST lists and nothing else, then prunes the directories it
# emptied. Run it from the same extracted bundle:
#
#   sudo ./uninstall.sh
#   DESTDIR=/tmp/pkg ./uninstall.sh    # to undo a staged install
set -e

AQUI="$(cd -- "$(dirname -- "$0")" && pwd)" || exit 1
LISTA="$AQUI/MANIFEST"
DESTINO="${DESTDIR:-}"

[ -f "$LISTA" ] || { echo "uninstall.sh: MANIFEST not found beside me" >&2; exit 1; }
if [ -z "$DESTINO" ] && [ "$(id -u)" != 0 ]; then
    echo "uninstall.sh: run me as root (sudo ./uninstall.sh), or set DESTDIR." >&2
    exit 1
fi

# The files first. The mode column is ignored on the way out; only the path
# matters.
cut -f2 -- "$LISTA" | while read -r rel; do
    [ -n "$rel" ] || continue
    rm -f -- "$DESTINO/$rel"
done

# Then the directories, deepest first. rmdir refuses a non-empty directory, so a
# shared one - /usr/bin, /usr/share/applications - is left untouched, while a
# directory that was only ours (/usr/lib/tandem) is taken away. The list of
# ancestors is derived from the MANIFEST, so it never drifts; a child path is
# always longer than its parent, so longest-first removes children before
# parents.
cut -f2 -- "$LISTA" | while read -r rel; do
    d="$rel"
    while [ "$d" != "." ] && [ "$d" != "/" ]; do
        d="$(dirname -- "$d")"
        [ "$d" = "." ] && break
        printf '%s\n' "$d"
    done
done | sort -u | awk '{ print length($0), $0 }' | sort -rn | cut -d" " -f2- \
    | while read -r d; do rmdir -- "$DESTINO/$d" 2>/dev/null || true; done

# Refresh the live caches, so the desktop stops offering a program that is gone.
if [ -z "$DESTINO" ] || [ "$DESTINO" = / ]; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
    update-mime-database /usr/share/mime 2>/dev/null || true
fi
exit 0
