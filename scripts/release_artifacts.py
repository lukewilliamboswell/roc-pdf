#!/usr/bin/env python3
"""Build and verify the inert artifacts consumed by the publication job."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import subprocess
import zipfile

from prepare_manual import ROOT, version_key


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def latest_notes() -> str:
    return max((path.stem for path in (ROOT / "docs/releases").glob("*.md")), key=version_key)


def render_notes(source: str, tag: str, bundle: Path, revision: str) -> str:
    url = f"https://github.com/lukewilliamboswell/roc-pdf/releases/download/{tag}/{bundle.name}"
    if "{package-url}" not in source or "{bundle-sha256}" not in source:
        raise ValueError("next release notes must name {package-url} and {bundle-sha256}")
    rendered = source.replace("{package-url}", url).replace("{bundle-sha256}", digest(bundle))
    if "TODO(release)" in rendered:
        raise ValueError("release notes contain TODO(release)")
    def pin(match):
        target = match.group(2)
        if re.match(r"[a-z]+:|#", target):
            return match.group(0)
        path = posixpath.normpath(posixpath.join("docs/releases", target))
        return f"{match.group(1)}https://github.com/lukewilliamboswell/roc-pdf/blob/{revision}/{path})"
    return re.sub(r"(\]\()([^)\s]+)\)", pin, rendered)


def build(tag: str, bundle: Path, docs: Path, revision: str, output: Path) -> None:
    version_key(tag)
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("release revision must be one full recorded commit SHA")
    notes = (ROOT / f"docs/releases/{tag}.md").read_text()
    pinned = (ROOT / ".roc-version").read_text().strip()
    if pinned not in notes:
        raise ValueError("release notes must state the pinned compiler")
    compiler = subprocess.check_output([os.environ.get("ROC", "roc"), "version"], text=True).strip()
    if pinned not in compiler:
        raise ValueError("release compiler differs from .roc-version")
    manual_inventory = json.loads((docs / "manual/source-digests.json").read_text())
    assert manual_inventory["revision"] == revision, "manual source links do not describe the release commit"
    bindings = manual_inventory["release_bindings"][f"docs/releases/{tag}.md"]
    assert bindings == {
        "{package-url}": f"https://github.com/lukewilliamboswell/roc-pdf/releases/download/{tag}/{bundle.name}",
        "{bundle-sha256}": digest(bundle),
    }, "manual does not describe the tested bundle"
    assert f'<span id="revnumber">{tag}</span>' in (docs / "manual/index.html").read_text(), "release manual has the wrong version label"
    output.mkdir(parents=True, exist_ok=True)
    (output / "release-notes.md").write_text(render_notes(notes, tag, bundle, revision) + f"\n\nCompiler: `{compiler}`.\n")
    archive = output / f"roc-pdf-docs-{tag}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for path in sorted(docs.rglob("*")):
            if path.is_file():
                entry = zipfile.ZipInfo(f"roc-pdf-docs-{tag}/{path.relative_to(docs).as_posix()}", (1980, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o100644 << 16
                zipped.writestr(entry, path.read_bytes())
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None
        assert f"roc-pdf-docs-{tag}/index.html" in zipped.namelist()
        assert f"roc-pdf-docs-{tag}/manual/index.html" in zipped.namelist()
        for path in docs.rglob("*"):
            if path.is_file():
                assert zipped.read(f"roc-pdf-docs-{tag}/{path.relative_to(docs).as_posix()}") == path.read_bytes()
    manual = output / f"roc-pdf-{tag}.pdf"
    shutil.copyfile(docs / "manual/roc-pdf.pdf", manual)
    examples = output / f"roc-pdf-examples-{tag}.zip"
    assets = [bundle, examples, archive, manual]
    expanded = subprocess.check_output(["tar", "--zstd", "-xOf", str(bundle)])
    if len(expanded) > 10 * 1024 * 1024:
        raise ValueError("release package exceeds the compiler's default 10 MiB decompressed-package limit")
    manifest = {"schema_version": 1, "revision": revision, "version": tag, "compiler": compiler,
                "bundle_expanded_bytes": len(expanded),
                "notes_sha256": digest(output / "release-notes.md"),
                "assets": [{"name": path.name, "size": path.stat().st_size, "sha256": digest(path)} for path in assets]}
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"PASS release artifacts: four digest-bound tested files for {revision}")


def self_test() -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as directory:
        bundle = Path(directory) / "hash.tar.zst"
        bundle.write_bytes(b"bundle")
        notes = render_notes("{package-url}\n{bundle-sha256}\n[Guide](../authoring.md)", "0.3.0", bundle, "a" * 40)
        assert "/0.3.0/hash.tar.zst" in notes and digest(bundle) in notes
        assert "/blob/" + "a" * 40 + "/docs/authoring.md" in notes
        for source in ("missing placeholders", "{package-url} {bundle-sha256} TODO(release)"):
            try:
                render_notes(source, "0.3.0", bundle, "a" * 40)
            except ValueError:
                pass
            else:
                raise AssertionError("invalid release notes admitted")
    print("PASS release artifact self-test: placeholders, pinned links and incomplete-note rejection")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--docs", type=Path, default=ROOT / "generated-docs")
    parser.add_argument("--revision")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--latest-notes", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        self_test()
    elif options.latest_notes:
        print(latest_notes())
    elif not all((options.tag, options.bundle, options.revision)):
        parser.error("--tag, --bundle and --revision are required")
    else:
        build(options.tag, options.bundle, options.docs, options.revision, options.output)


if __name__ == "__main__":
    main()
