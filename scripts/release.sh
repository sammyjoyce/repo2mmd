#!/usr/bin/env bash
# Builds the release archives into dist/ with the pinned Zig toolchain.
# For a given commit the archives are byte-for-byte reproducible: every target
# is cross-compiled from one host, binaries are stripped, and tar/gzip
# metadata comes from SOURCE_DATE_EPOCH (the commit time by default).
# Runs on Linux only: it needs GNU tar (--sort, --mtime) and sha256sum.
#
# Usage: scripts/release.sh [vX.Y.Z]   (the tag must match build.zig.zon)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(sed -n 's/^ *\.version = "\(.*\)",$/\1/p' build.zig.zon)"
if [[ $# -gt 0 && "$1" != "v$version" ]]; then
  echo "error: tag $1 does not match build.zig.zon version $version" >&2
  exit 1
fi

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"

# glibc 2.28 keeps the Linux binaries loadable on older distributions. Plugins
# are loaded with dlopen, so a static musl build is not an option.
targets=(x86_64-linux-gnu.2.28 aarch64-linux-gnu.2.28 x86_64-macos aarch64-macos)

rm -rf dist
mkdir -p dist/stage
for target in "${targets[@]}"; do
  name="repo2mmd-$version-${target%.2.28}"
  stage="dist/stage/$name"
  zig build -Dtarget="$target" -Doptimize=ReleaseSafe -Dstrip=true --prefix "$stage"
  cp LICENSE README.md "$stage/"
  mkdir -p "$stage/licenses"
  for dep in tree-sitter tree-sitter-typescript tree-sitter-zig; do
    cp "third_party/$dep/LICENSE" "$stage/licenses/$dep.LICENSE"
  done
  tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
    --mode=u+w,go-w -C dist/stage -cf - "$name" | gzip -n -9 >"dist/$name.tar.gz"
done
rm -rf dist/stage

(cd dist && sha256sum -- *.tar.gz >SHA256SUMS)
cat dist/SHA256SUMS
