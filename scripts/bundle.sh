#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$root_dir/dist"
roc_bin="${ROC:-roc}"

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
# `roc bundle` follows module imports but silently omits files reached through
# byte imports (`import "x.ttf" as bytes : List(U8)`, roc-lang/roc#11907), so
# every file a package module byte-imports is named on the command line. The
# list is read from the modules themselves so a new data import cannot be
# forgotten; an import that escapes package/ is rejected.
data_files=()
while IFS= read -r data_file; do
    case "$data_file" in
        /* | ../* | */../*)
            echo "ERROR: package byte import escapes package/: $data_file" >&2
            exit 1
            ;;
    esac
    if [[ ! -f "$data_file" ]]; then
        echo "ERROR: package byte import names a missing file: $data_file" >&2
        exit 1
    fi
    data_files+=("$data_file")
done < <(sed -n 's/^import "\([^"]*\)" as .*/\1/p' ./*.roc | LC_ALL=C sort -u)
"$roc_bin" bundle main.roc "${data_files[@]}" --output-dir "$output_dir"
