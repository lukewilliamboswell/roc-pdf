# Automation and documentation publication

Use this guide when changing a workflow or preparing documentation for release.
The product's conformance and resource contracts remain in `architecture.md`,
`feature-roadmap.md` and the executable test inputs.

## Tools and identities

`Blueprint.roc` and `Blueprint.lock` select the reviewed Blueprint release,
native renderer, Zig and other fetched tools. `.roc-version` is the package
compiler pin. Keep those declarations authoritative instead of copying hashes
or current version strings into this guide. See [Blueprint setup](blueprint.md).

CI verifies downloaded and cached artifacts against their recorded digests.
The native renderer needs no compiler or browser; API extraction uses the pinned
package compiler. Independent PDFBox, veraPDF, Arlington and reader checks remain
test tools, never production dependencies. Their exact inputs and provisioning
are recorded under `vendor/` and in the workflow definitions.

## Build and check the manual

Canonical user chapters are top-level `docs/*.adoc`, assembled by
`docs/index.adoc`. `scripts/prepare_manual.py` stages authored bytes, exact local
PNGs, source-revision links, release bindings and an input-digest inventory.
The released renderer produces HTML, Markdown and PDF; it does not convert
hand-maintained Markdown guides into AsciiDoc.

```sh
blueprint run docs
```

The manual publishes under `/manual/`; compiler-generated API routes stay at
the site root. Existing Markdown guide paths link to the maintained chapters.
A versioned build requires its actual bundle and authored release notes so the
manual names the tested dependency and compiler.

`check_manual.py` verifies source-block bytes, table associations, local links,
anchors and source/asset digests in HTML and Markdown. PDFBox independently
checks extracted source/table content, tagged tables and the exact gallery
images. `check_manual_browser.mjs` checks desktop/mobile navigation, images,
overflow and dark mode. Keep raw output under ignored `.roc-pdf-tmp/` or CI
artifacts; inspect layout when content changes. A renderer pass does not prove
all product or accessibility claims.

## Check and publish the same bytes

The reusable checks workflow receives one source SHA and runs package/resource
checks, fuzz smoke, independent conformance lanes, documentation, public bundle
consumers and gallery/archive checks. Its aggregate requires every declared
result to succeed. Compiler-candidate dispatch suppresses publication and
deployment; it remains a diagnostic build rather than a release.

Release version checks reject malformed metadata, component overflow and
non-forward versions before invoking a compiler. A higher major, or a higher
minor while both versions are pre-1.0, already satisfies the largest possible
API-change requirement. This proof permits a compiler transition when the
immutable old bundle no longer compiles; it does not establish source
compatibility. Within the same breaking boundary, `roc bump` must compile and
compare both APIs and any failure blocks release. Prereleases use the
compatibility promise of their final base version. The version check's
self-tests cover both proof paths and rejected transitions. All candidate,
archive and conformance tests remain required in either case.

Ordinary CI may retain the latest final version only when a freshly built
complete package matches the uniquely selected immutable published asset by
name, length, SHA-256 and complete downloaded bytes. The same admitted file
then runs through the gallery and archived-example consumers. This establishes
package identity, not a new API-compatibility or release-eligibility claim.
Changed or unverifiable packages fail. Every explicit release request and every
new-version comparison still uses the strict forward-version/API check above;
an already published version cannot become a new release through this path.
Official API requests have bounded metadata, package and diagnostic output,
an absolute deadline and one process-group cleanup with bounded reaping.
Metadata is limited to 1 MiB and package files to 16 MiB before reading; errors
or incomplete cleanup fail the gate. Identity still relies on GitHub's immutable
release hosting; it does not establish compiler provenance.

Publication requires `main`, a new version and eligible authored notes. The
release manifest binds the recorded commit/compiler, asset names, lengths,
digests and notes. The publisher consumes its own run's tested artifacts,
checks out no project source and executes no candidate-produced file. It
uploads, downloads and verifies the complete asset inventory before publication.
See [the release procedure](releases/publishing.md).

Review current GitHub repository settings separately from workflow source:
required current checks, signed commits, pull requests, tag immutability,
protected release/Pages environments and workflow permissions. A configuration
file or an old settings report does not establish current enforcement.
