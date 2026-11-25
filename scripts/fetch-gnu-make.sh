#!/bin/sh
# Download the GNU Make source archive and check its SHA-256 (ADR-0031).
#
# Usage: scripts/fetch-gnu-make.sh VERSION SHA256 OUT
#
# The script gives fetch.sh the GNU sources in this order:
#   1. ftpmirror.gnu.org, which sends the request to a near GNU mirror.
#      GNU asks downloaders to use it and to keep the load off ftp.gnu.org.
#   2. ftp.gnu.org.
#   3. Some large GNU mirrors, in case the GNU servers are down.
# fetch.sh checks the pinned checksum of each file, so each mirror is safe.
set -eu

if [ $# -ne 3 ]; then
  echo "usage: fetch-gnu-make.sh VERSION SHA256 OUT" >&2
  exit 2
fi
file="make-$1.tar.gz"

exec sh "$(dirname "$0")/fetch.sh" "$2" "$3" \
  "https://ftpmirror.gnu.org/make/$file" \
  "https://ftp.gnu.org/gnu/make/$file" \
  "https://mirrors.kernel.org/gnu/make/$file" \
  "https://mirror.csclub.uwaterloo.ca/gnu/make/$file" \
  "https://mirrors.ocf.berkeley.edu/gnu/make/$file" \
  "https://mirrors.dotsrc.org/gnu/make/$file" \
  "https://ftp.halifax.rwth-aachen.de/gnu/make/$file"
