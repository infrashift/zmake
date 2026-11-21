#!/bin/sh
# Build the release archives in zig-out/dist (ADR-0028).
#
# Usage: scripts/dist.sh [VERSION]
#
# VERSION is the tag without the "v", for example 0.1.0 or 0.1.0-rc.1. Its
# part before the first "-" must be the version in build.zig.zon. With no
# VERSION, the script uses the version in build.zig.zon.
#
# Each archive holds bin/zmake, the man pages under share/man, LICENSE and
# README.md, in a directory with the name of the archive. zig build installs
# the binary and the man pages, so this script has no install logic.
set -eu

ZIG=${ZIG:-zig}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

base=$(sed -n 's/^ *\.version = "\([^"]*\)",$/\1/p' build.zig.zon)
if [ -z "$base" ]; then
  echo "dist: build.zig.zon has no version" >&2
  exit 1
fi
version=${1:-$base}
version=${version#v}
if [ "${version%%-*}" != "$base" ]; then
  echo "dist: version $version does not match $base in build.zig.zon" >&2
  exit 1
fi

# The binary prints the commit of the build (ADR-0025). A release binary must
# name a commit that is in the repository, so the tracked files must be clean.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "dist: the work tree has changes; commit them first" >&2
  exit 1
fi
commit=$(git rev-parse HEAD)

out=zig-out/dist
rm -rf "$out"
mkdir -p "$out/stage"

for pair in linux-amd64:x86_64-linux-musl linux-arm64:aarch64-linux-musl macos-arm64:aarch64-macos; do
  name=${pair%%:*}
  target=${pair#*:}
  dir="zmake-v$version-$name"
  echo "dist: $dir ($target)"
  "$ZIG" build --release -Dtarget="$target" -p "$out/stage/$dir"
  cp LICENSE README.md "$out/stage/$dir/"
  tar -czf "$out/$dir.tar.gz" -C "$out/stage" "$dir"
done

# The host can run the linux-amd64 binary in CI. Check its version line.
if [ "$(uname -sm)" = "Linux x86_64" ]; then
  line=$("$out/stage/zmake-v$version-linux-amd64/bin/zmake" --version)
  if [ "$line" != "zmake $base ($commit)" ]; then
    echo "dist: the version line is \"$line\", not \"zmake $base ($commit)\"" >&2
    exit 1
  fi
  echo "dist: $line"
fi

cd "$out"
if command -v sha256sum > /dev/null 2>&1; then
  sha256sum zmake-v"$version"-*.tar.gz > SHA256SUMS
else
  shasum -a 256 zmake-v"$version"-*.tar.gz > SHA256SUMS
fi
cat SHA256SUMS
