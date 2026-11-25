#!/bin/sh
# Download a Zig release archive and check its SHA-256 (ADR-0030).
#
# Usage: scripts/fetch-zig.sh FILE SHA256 OUT
#
# FILE is the archive name, for example zig-x86_64-linux-0.17.1.tar.xz.
# SHA256 is the checksum that the workflow pins. OUT is the output file.
#
# The script gives fetch.sh the community mirrors in a random order, then
# ziglang.org. The Zig project asks CI to use the mirrors and to keep the load
# off ziglang.org. fetch.sh checks the pinned checksum of each file.
#
# The mirror list is a copy of https://ziglang.org/download/community-mirrors.txt
# from 2026-11-25. A stale entry only costs one failed attempt.
set -eu

if [ $# -ne 3 ]; then
  echo "usage: fetch-zig.sh FILE SHA256 OUT" >&2
  exit 2
fi
file=$1
want=$2
out=$3

# zig-x86_64-linux-0.17.1.tar.xz -> 0.17.1
version=${file##*-}
version=${version%.tar.xz}
version=${version%.zip}

mirrors='https://pkg.hexops.org/zig
https://zigmirror.hryx.net/zig
https://zig.linus.dev/zig
https://zig.squirl.dev
https://zig.mirror.mschae23.de/zig
https://ziglang.freetls.fastly.net
https://zig.tilok.dev
https://zig-mirror.tsimnet.eu/zig
https://zig.karearl.com/zig
https://pkg.earth/zig
https://fs.liujiacai.net/zigbuilds
https://zigmirror.com
https://zig.chainsafe.dev
https://zig.savalione.com
https://zig.bcr.ist
https://zig.vortan.dev/zig
https://pkg.alexrp.com/zig'

# The mirrors in a random order, then ziglang.org. No URL has a space.
# A new CI VM often gives the same PID on each run, so the seed also uses the
# time. date +%s is not POSIX, but each CI system has it.
seed=$(( $$ + $(date +%s) ))
urls=$(printf '%s\n' "$mirrors" |
  awk -v seed="$seed" 'BEGIN { srand(seed) } { print rand() "\t" $0 }' |
  sort -n | cut -f2- |
  awk -v f="$file" '{ print $0 "/" f "?source=github-infrashift-zmake" }')

# shellcheck disable=SC2086 # split the URL list on newlines
exec sh "$(dirname "$0")/fetch.sh" "$want" "$out" $urls \
  "https://ziglang.org/download/$version/$file"
