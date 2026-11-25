#!/bin/sh
# Download a file from the first source that gives the pinned SHA-256
# (ADR-0030).
#
# Usage: scripts/fetch.sh SHA256 OUT URL...
#
# The script tries each URL in the order given. A source that fails, is too
# slow, or gives a file with a different checksum goes to the next URL. The
# pinned checksum makes each source safe. fetch-zig.sh and fetch-gnu-make.sh
# give the URLs.
#
# The script runs on Linux, macOS, FreeBSD and Git Bash on Windows, so it
# uses only POSIX sh, curl, awk and the checksum tool of the system.
set -eu

if [ $# -lt 3 ]; then
  echo "usage: fetch.sh SHA256 OUT URL..." >&2
  exit 2
fi
want=$1
out=$2
shift 2

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256 -q "$1"
  fi
}

# Two passes. The first pass stops a source that sends less than 1 MB/s for
# 20 s, so a slow mirror costs 20 s and not minutes. If no source is that
# fast, the second pass accepts 50 kB/s, with a limit of 10 min for each file.
for pass in fast slow; do
  if [ "$pass" = fast ]; then
    limits="--speed-limit 1000000 --speed-time 20 --max-time 300"
  else
    limits="--speed-limit 50000 --speed-time 30 --max-time 600"
  fi
  for url in "$@"; do
    rm -f "$out"
    # shellcheck disable=SC2086 # split the curl options
    if ! curl -fsSL --connect-timeout 15 $limits -o "$out" "$url"; then
      echo "fetch: $url failed ($pass pass)" >&2
      continue
    fi
    got=$(sha256 "$out")
    if [ "$got" = "$want" ]; then
      echo "fetch: $out from $url"
      exit 0
    fi
    echo "fetch: $url gave checksum $got, not $want" >&2
  done
done
rm -f "$out"
echo "fetch: no source gave $out with the pinned checksum" >&2
exit 1
