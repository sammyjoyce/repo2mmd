#!/usr/bin/env bash
# Regenerates examples/zig-clap/ from a pinned commit of a public repository.
# CI reruns this and fails if the committed files differ, so the README example
# stays reproducible. Requires git, jq, and a built repo2mmd (zig build).
set -euo pipefail

repo_url="https://github.com/Hejsil/zig-clap.git"
commit="05faf3905e8548f5cc269a8836e154065e70128d"

root="$(cd "$(dirname "$0")/.." && pwd)"
bin="${REPO2MMD:-$root/zig-out/bin/repo2mmd}"
out="$root/examples/zig-clap"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git init -q "$work/zig-clap"
git -C "$work/zig-clap" fetch -q --depth 1 "$repo_url" "$commit"
git -C "$work/zig-clap" checkout -q FETCH_HEAD

# Relative root keeps file paths, evidence paths, and manifest.input_root free
# of machine paths; the commit time pins manifest.generated_at.
SOURCE_DATE_EPOCH="$(git -C "$work/zig-clap" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH
cd "$work"
"$bin" --cache-mode off generate zig-clap -o graph.mmd 2>/dev/null
"$bin" --cache-mode off generate zig-clap -o graph.json 2>/dev/null

mkdir -p "$out"
cp graph.mmd graph.json "$out/"

# File-level view for the README: file nodes and every edge, with function and
# type nodes left out. All lines come from graph.mmd unchanged.
{
  echo "graph LR"
  grep -E '^    (file__[A-Za-z0-9_]+\[|style file__)' graph.mmd
  grep -E -- '-->' graph.mmd
} >"$out/files.mmd"

# Evidence for the README: clap.zig's imports and the source lines they cite.
jq '[.graph.edges[] | select(.src == "file_clap.zig")]' graph.json >"$out/clap-zig-edges.json"
sed -n '2195,2200p' zig-clap/clap.zig >"$out/clap-zig-L2195-2200.zig"

echo "Wrote $out from $repo_url@$commit"
