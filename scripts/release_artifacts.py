#!/usr/bin/env python3
"""Build and verify the inert artifacts consumed by the publication job."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from prepare_manual import PROJECT_URL, ROOT, pin_source_links, version_key


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def latest_notes() -> str:
    return max((path.stem for path in (ROOT / "docs/releases").glob("*.adoc")
                if path.stem != "unreleased"), key=version_key)


def bind_notes(source: str, tag: str, bundle: Path, revision: str) -> str:
    url = f"{PROJECT_URL}/releases/download/{tag}/{bundle.name}"
    if "{package-url}" not in source or "{bundle-sha256}" not in source:
        raise ValueError("next release notes must name {package-url} and {bundle-sha256}")
    rendered = source.replace("{package-url}", url).replace("{bundle-sha256}", digest(bundle))
    if "TODO(release)" in rendered:
        raise ValueError("release notes contain TODO(release)")
    return pin_source_links(rendered, revision)


def render_notes(source: str, tag: str) -> str:
    scratch = ROOT / ".roc-pdf-tmp"
    scratch.mkdir(exist_ok=True)
    renderer = os.environ.get("ROC_DOCS_BINARY", "roc-docs")
    with tempfile.TemporaryDirectory(prefix="release-notes-", dir=scratch) as directory:
        work = Path(directory)
        sources = work / "source"
        sources.mkdir()
        (sources / "index.adoc").write_text(source)
        output = work / "output"
        subprocess.run([
            renderer, "build", "--workspace", str(work), "--docs-directory", "source",
            "--entrypoint", "index.adoc", "--output-directory", "output",
            "--docs-version", tag, "--markdown", "true",
        ], check=True)
        markdown = (output / "site/index.md").read_text()
    header, separator, body = markdown.partition("\n\n")
    if not separator or not header.startswith(f"> Documentation version: {tag}.") or not body:
        raise ValueError("unexpected Markdown export for release notes")
    return body


def build(tag: str, bundle: Path, docs: Path, revision: str, output: Path) -> None:
    version_key(tag)
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("release revision must be one full recorded commit SHA")
    source_path = f"docs/releases/{tag}.adoc"
    notes = (ROOT / source_path).read_text()
    pinned = (ROOT / ".roc-version").read_text().strip()
    if pinned not in notes:
        raise ValueError("release notes must state the pinned compiler")
    compiler = subprocess.check_output([os.environ.get("ROC", "roc"), "version"], text=True).strip()
    if pinned not in compiler:
        raise ValueError("release compiler differs from .roc-version")
    manual_inventory = json.loads((docs / "manual/source-digests.json").read_text())
    assert manual_inventory["revision"] == revision, "manual source links do not describe the release commit"
    bindings = manual_inventory["release_bindings"][source_path]
    assert bindings == {
        "{package-url}": f"{PROJECT_URL}/releases/download/{tag}/{bundle.name}",
        "{bundle-sha256}": digest(bundle),
    }, "manual does not describe the tested bundle"
    assert f'<span id="revnumber">{tag}</span>' in (docs / "manual/index.html").read_text(), "release manual has the wrong version label"
    output.mkdir(parents=True, exist_ok=True)
    authored = bind_notes(notes, tag, bundle, revision)
    (output / "release-notes.md").write_text(render_notes(authored + f"\n\nCompiler: `{compiler}`.\n", tag))
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
    with zipfile.ZipFile(examples) as zipped:
        assert zipped.testzip() is None
        plan = json.loads(zipped.read(f"roc-pdf-examples-{tag}/spec.json"))
        assert plan["release"] == tag and plan["dependencies"] == [bindings["{package-url}"]], "examples describe a different release bundle"
        assert sorted(app["path"] for app in plan["apps"]) == sorted(
            f"examples/{path.parent.name}/main.roc" for path in (ROOT / "examples").glob("*/main.roc")
        ), "examples archive omits a public application"
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
    with tempfile.TemporaryDirectory() as directory:
        bundle = Path(directory) / "hash.tar.zst"
        bundle.write_bytes(b"bundle")
        notes = bind_notes("{package-url}\n{bundle-sha256}\n"
                           "https://github.com/lukewilliamboswell/roc-pdf/blob/main/docs/authoring.adoc[Guide]",
                           "0.3.0", bundle, "a" * 40)
        assert "/0.3.0/hash.tar.zst" in notes and digest(bundle) in notes
        assert "/blob/" + "a" * 40 + "/docs/authoring.adoc" in notes
        for source in ("missing placeholders", "{package-url} {bundle-sha256} TODO(release)"):
            try:
                bind_notes(source, "0.3.0", bundle, "a" * 40)
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
