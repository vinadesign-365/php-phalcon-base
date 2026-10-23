#!/bin/sh
# apt-get install with a fallback for EOL Debian releases (buster, bullseye) on archive.debian.org:
# the mirrors can still serve the index but return 404 for the packages.
set -eu

install() {
    apt-get update && apt-get install -y --no-install-recommends "$@"
}

if ! install "$@"; then
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
        [ -f "$f" ] || continue
        sed -i \
            -e 's|deb.debian.org/debian-security|archive.debian.org/debian-security|g' \
            -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
            -e 's|deb.debian.org/debian|archive.debian.org/debian|g' \
            -e '/-updates/d' "$f"
    done
    install "$@"
fi
