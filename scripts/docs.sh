#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manual_built=false
if [[ "${1:-}" == --manual-built ]]; then manual_built=true; shift; fi
output_dir="${1:-$root_dir/generated-docs}"
roc_bin="${ROC:-roc}"
renderer="${ROC_DOCS_BINARY:-roc-docs}"
version="${DOCS_VERSION:-unreleased}"
compiler_identity="$("$roc_bin" version)"
pinned_compiler="$(cat "$root_dir/.roc-version")"
if [[ "$compiler_identity" != *"$pinned_compiler"* ]]; then
    echo "ERROR: API extraction requires $pinned_compiler, got $compiler_identity" >&2
    exit 1
fi

if ! command -v rg >/dev/null; then
    echo "ERROR: rg (ripgrep) is required for the private-type audit; run 'blueprint run docs'" >&2
    exit 1
fi

if [[ "$manual_built" == false ]]; then
    binding_args=()
    if [[ "$version" != unreleased ]]; then
        mkdir -p "$root_dir/.roc-pdf-tmp"
        bundle_dir="$(mktemp -d "$root_dir/.roc-pdf-tmp/docs-bundle.XXXXXX")"
        bash "$root_dir/scripts/bundle.sh" --output-dir "$bundle_dir"
        bundle="$(find "$bundle_dir" -maxdepth 1 -name '*.tar.zst' -type f -print -quit)"
        binding_args=(--release-version "$version" --bundle "$bundle")
    fi
    python3 "$root_dir/scripts/prepare_manual.py" --revision "${DOCS_REVISION:-main}" "${binding_args[@]}"
    if [[ -n "${bundle_dir:-}" ]]; then rm -rf "$bundle_dir"; fi
    "$renderer" build --workspace "$root_dir" --docs-directory .roc-pdf-tmp/manual-source \
        --entrypoint index.adoc --output-directory .roc-pdf-tmp/manual-build \
        --pdf-filename roc-pdf.pdf --docs-version "$version" \
        --site-url https://lukewilliamboswell.github.io/roc-pdf/manual/
fi
mkdir -p "$output_dir"
"$roc_bin" docs --output="$output_dir" "$root_dir/package/main.roc"

if rg -n 'Kernel[A-Za-z]+' "$output_dir"; then
    echo "ERROR: generated public documentation exposes a private Kernel type" >&2
    exit 1
fi

rm -rf "$output_dir/manual"
cp -R "$root_dir/.roc-pdf-tmp/manual-build/site" "$output_dir/manual"
cp "$root_dir/.roc-pdf-tmp/manual-source/source-digests.json" "$output_dir/manual/source-digests.json"
python3 "$root_dir/scripts/check_manual.py" --site "$output_dir/manual" \
    --pdf "$output_dir/manual/roc-pdf.pdf" --source "$root_dir/.roc-pdf-tmp/manual-source"
echo "Generated public API documentation and user manual in $output_dir"
