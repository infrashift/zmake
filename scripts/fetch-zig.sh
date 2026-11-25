#!/bin/sh
# Download a Zig release archive and check its SHA-256 (ADR-0030).
#
# Usage: scripts/fetch-zig.sh FILE SHA256 OUT
#
# FILE is the archive name, for example zig-x86_64-linux-0.17.1.tar.xz.
# SHA256 is the checksum that the workflow pins. OUT is the output file.
#
# The script tries the community mirrors in a random order, then
# ziglang.org. The Zig project asks CI to use the mirrors and to keep the load
# off ziglang.org. A mirror can be down or slow, so each source has a time
# limit. The pinned checksum makes each source safe: a bad file fails the
# check, and the script tries the next source.
#
# The mirror list is a copy of https://ziglang.org/download/community-mirrors.txt
# from 2026-11-25. A stale entry only costs one failed attempt.
#
# The script runs on Linux, macOS, FreeBSD and Git Bash on Windows, so it
# uses only POSIX sh, curl, awk and the checksum tool of the system.
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

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256 -q "$1"
  fi
}

# The mirrors in a random order, then ziglang.org.
urls=$(printf '%s\n' "$mirrors" |
  awk -v seed="$$" 'BEGIN { srand(seed) } { print rand() "\t" $0 }' |
  sort -n | cut -f2- |
  awk -v f="$file" '{ print $0 "/" f "?source=github-infrashift-zmake" }')
urls="$urls
https://ziglang.org/download/$version/$file"

for url in $urls; do
  rm -f "$out"
  # Stop a source that sends less than 50 kB/s for 30 s, or takes 10 min.
  if ! curl -fsSL --connect-timeout 15 --speed-limit 50000 --speed-time 30 \
      --max-time 600 -o "$out" "$url"; then
    echo "fetch-zig: $url failed" >&2
    continue
  fi
  got=$(sha256 "$out")
  if [ "$got" = "$want" ]; then
    echo "fetch-zig: $file from $url"
    exit 0
  fi
  echo "fetch-zig: $url gave checksum $got, not $want" >&2
done
rm -f "$out"
echo "fetch-zig: no source gave $file with the pinned checksum" >&2
exit 1
