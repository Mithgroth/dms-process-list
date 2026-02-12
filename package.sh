#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$script_dir"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read plugin version from plugin.json" >&2
  exit 1
fi

plugin_id="$(jq -r '.id' "$plugin_dir/plugin.json")"
plugin_version="$(jq -r '.version' "$plugin_dir/plugin.json")"
out_dir="$plugin_dir/dist"
archive="$out_dir/${plugin_id}-${plugin_version}.tar.gz"
source_files=(
  "plugin.json"
  "ProcessListDesktop.qml"
  "README.md"
  "LICENSE"
  "package.sh"
)

if [ -f "$plugin_dir/.gitignore" ]; then
  source_files+=(".gitignore")
fi

mkdir -p "$out_dir"

tar \
  --transform "s#^#${plugin_id}/#" \
  -czf "$archive" \
  -C "$plugin_dir" \
  "${source_files[@]}"

echo "Created: $archive"
