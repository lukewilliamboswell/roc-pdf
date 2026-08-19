#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$root_dir/generated-docs}"
roc_bin="${ROC:-roc}"

mkdir -p "$output_dir"
"$roc_bin" docs --output="$output_dir" "$root_dir/package/main.roc"

if rg -n 'Kernel[A-Za-z]+' "$output_dir"; then
    echo "ERROR: generated public documentation exposes a private Kernel type" >&2
    exit 1
fi

echo "Generated public API documentation in $output_dir"
