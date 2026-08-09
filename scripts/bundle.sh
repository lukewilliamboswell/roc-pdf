#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$root_dir/dist"
roc_bin="${ROC:-}"

# Keep local package work convenient while roc-lang/roc#10700 is waiting for
# an official nightly. CI sets ROC=roc and never relies on this sibling build.
if [[ -z "$roc_bin" ]]; then
    sibling_roc="$root_dir/../roc-worktrees/fix-10697/zig-out/bin/roc"
    if [[ -x "$sibling_roc" ]]; then
        roc_bin="$sibling_roc"
    else
        roc_bin="roc"
    fi
fi

while (($# > 0)); do
    case "$1" in
        --output-dir)
            output_dir="$2"
            shift 2
            ;;
        --output-dir=*)
            output_dir="${1#--output-dir=}"
            shift
            ;;
        *)
            echo "usage: $0 [--output-dir DIRECTORY]" >&2
            exit 2
            ;;
    esac
done

pinned_roc="$(sed -n '1p' "$root_dir/.roc-version")"
pinned_revision="${pinned_roc##*-}"
actual_roc="$("$roc_bin" version)"
if [[ "$actual_roc" != *"$pinned_roc"* && "$actual_roc" != *"$pinned_revision"* ]]; then
    echo "ERROR: repository requires $pinned_roc, got '$actual_roc'" >&2
    exit 1
fi

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

cd "$root_dir/package"
"$roc_bin" bundle main.roc --output-dir "$output_dir"
