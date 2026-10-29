# Automation and documentation publication

The integration keeps the package compiler, pure Roc runtime, independent
oracles and exact allocation/byte/work evidence. Shared automation is tooling;
its compiler and documentation renderer do not become package dependencies.

## Tool identities and provisioning

| Tool | Reviewed identity and boundary |
| --- | --- |
| Package compiler | `.roc-version`, `nightly-2026-10-28-bad769b`; installed explicitly by CI and checked by the local harness, bundler and API-doc stage |
| Blueprint | 0.8.0, existing platform URL and lock; Zig 0.16.0 and ripgrep 15.2.0 remain digest-checked recipes |
| Shared actions | `tools-0.7.0`, commit `8acff758d5d73210f1731bed75adb9322f5e773d`; setup, renderer locator/build, publisher and released-example compatibility references are full SHAs |
| Native manual renderer | `roc-docs` tools-0.7.0, Linux x86-64 and Apple Silicon; exact sizes/digests in `Blueprint.lock`; its build used tooling compiler `nightly-2026-10-21-5349569` |
| CI JDK/Python | Temurin 21.0.13+9 and Python 3.14.0 through full-SHA setup actions; explicit provisioning inputs, never production dependencies |
| Independent PDF tools | PDFBox 3.0.8, qpdf 12.3.2, PDFium Chromium 7988, MuPDF 1.28.2, veraPDF 1.30.2 and corpus artifacts retain their vendored hashes/licenses; Arlington retains its exact container digest |
| Regeneration tools | Current rc4-font and sRGB checks are offline and read-only in CI. Older font fixture generators retain fontTools 4.61.1 (hash-locked optional install in `requirements-tools.txt`), with the historical CJK generator's separate 4.46.0 requirement. Photo/JPEG regeneration retains its recorded Pillow 10.2.0 provenance. Historical generators are audited inputs, not silently rerun by publication. |

The released renderer digests are
`3e5ef524aa17eeb81538c639ad4959bf4690b178898930ea0a42a2cd8bf7312d`
(22,216,616-byte Linux executable) and
`181817a0673f5036b75d3d29707ef665b45ea7f3ccfe9bbc35362a72639b40fc`
(17,396,432-byte macOS executable). The release's `roc-docs-LICENSES.txt`
is 36,294 bytes, SHA-256
`6e9f95b2305a375527a046fde8e1d447fadffd96a6ae3ffd34b7f63e51bc323e`;
the executable also provides `--licenses`. Blueprint verifies restored and
downloaded bytes. The shared build action accepts that verified executable and
does not install an arbitrary renderer itself.

Native documentation rendering needs no compiler or browser. API extraction
is a separate pinned-compiler stage. The shared publisher at this revision
provisions its own Nix/tooling compiler in its own immutable action checkout;
the privileged caller job checks out no project source and runs no artifact as
code. Validator/corpus provisioning consumes retained bytes without a network
fallback; external compiler/JDK/Blueprint/container provisioning remains an
explicit online setup stage. No fully offline runner-image claim is made.

## Manual sources, URLs and acceptance

The authored Markdown user guides retain their existing GitHub URLs and
anchors. `scripts/prepare_manual.py` deterministically prepares their admitted
headings, links, source listings and tables as top-level AsciiDoc chapters,
using `docs/index.adoc` as the book entrypoint. It rejects unsupported block
forms and missing links, copies only known gallery PNGs, and records every
source/asset digest. Original examples remain in compile/gallery checks;
rendering a listing does not prove that it compiles. Historical release
listings retain their historical APIs.

Compiler-generated API routes remain at the site root; the native manual is
assembled under `/manual/`. The manual links to the existing API and checked
example sources. Each chapter has HTML/Markdown, canonical namespaced anchors
and PDF destinations. Default-branch output says `unreleased`; versioned release
archives retain the generated API, manual, Markdown, digest inventory and PDF.
Contributor workflows/evidence stay under `development/`; root architecture
and roadmap documents remain authoritative.

The released renderer cannot print U+2318. Descriptive prose therefore names
the Command symbol and its exact code point, preserving the font-coverage fact.
No font substitution, omitted source text or renderer patch is used. Its PDF
table column weights remain unimplemented; this manual does not rely on exact
column-weight fidelity. Row/cell associations, content and tagged ownership
remain checked.

`check_manual.py` checks exact listing whitespace in every chapter HTML,
local links/anchors, static Markdown discovery, original source/asset digests,
independent PDFBox source/table extraction, tagged tables and the three exact
decoded RGB gallery images. Its review mode independently renders contents,
table and figure pages. `check_manual_browser.mjs` exercises every page at
1280-pixel desktop and 390-pixel mobile widths, loaded/described images,
horizontal overflow, source colours/transparent backgrounds, capability-table
presence, mobile contents controls and dark mode. It retains screenshots and a
browser binary digest report.

Local acceptance used Node 23.9.0, Google Chrome 156.0.8078.49 (executable
SHA-256 `8fc0b8ffb31698a1be44f41df5e4adbdfae8720e94fa458e29f9dfd3bf142e1c`),
PDFBox 3.0.8 and installed Java 17.0.10+11-LTS. This browser/JDK audit describes
the test host; the native renderer remains the exact locked release. Machine
reports are retained alongside this record; screenshots are reproducible in
`.roc-pdf-tmp/manual-review/`. Publication switches only after manual/API checks
pass, and no website is deployed from this integration branch. The retained
[PDF report](manual-publication-review/pdf.json) and
[browser report](manual-publication-review/browser.json) identify the checked
manual outputs and the source inventory at the recorded documentation commit; final
CI repeats the checks from its own recorded commit. The final local dry run
has 21 HTML pages, 49 PDF pages, 39 exact source blocks, three exact RGB
figures and three tagged tables. Independent PDF screenshots retain their
hashes in the PDF report; the capability table and all three gallery figure
pages were visually inspected after rendering.
The migration added an explicit Markdown-to-PSV closing-pipe conversion after
visual inspection caught shifted table cells; exact HTML cell grids and PDF
semantic row/cell shapes now guard that boundary.

## Check and publication boundaries

`checks.yml` is called by ordinary CI and release dispatch with one full SHA.
It includes package tests and exact allocation/byte/work guards, fuzz smoke,
independent PDF/A-4 package/Standard/corpus validation, Arlington, docs, public
bundle/gallery/archive consumers and an `always()` aggregate requiring every
result to be `success`. Release/main runs add the registered macOS target;
nightly released-example compatibility uses the same Linux/macOS systems.
The retained `nightly_validation` dispatch inputs still suppress publishing or
deployment; the current shared released-example workflow itself does not call
these controllers. Compiler-candidate dispatch may still use a branch and omit
a tag; it derives the authored version and skips publication eligibility/API
version checks. It still builds and tests the actual bundle, gallery, extracted
examples and docs, but omits publication artifact assembly: authored notes must
continue to describe the released compiler rather than a candidate pin. Its
uploaded bundle/examples remain test artifacts, and the publisher cannot run.
Actual publication always requires main, a new version, eligible authored notes
and the API gate. No input was removed based on an assumed absence of callers.

The [GitHub runner reference](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
lists public `macos-15` as arm64 (checked 2026-10-29), matching Blueprint's
registered `aarch64-darwin` target; Linux uses `ubuntu-22.04` x86-64.

The release build tests the actual files and renders authored note placeholders.
Its manifest records the commit/compiler and each asset's name, size and hash.
The publisher verifies that manifest, the notes digest and explicit inventory,
then stages/uploads/downloads/verifies/publishes through the shared action.
It receives only its own run's artifacts. API compatibility uses the actual
`roc bump --old ... --expect ...` interface of the pinned compiler.

The final [local artifact review](release-artifacts-rc4-review.json) records
four asset hashes and the notes digest, 14 strict served-bundle gallery checks,
the isolated public consumer, and all 14 reconstructed and extracted ZIP apps.
All 250 package/example/docs inputs and 85 ZIP source/resource members were
compared with the recorded documentation commit; only the ZIP's explicit
release dependency URL differs. The corrected manual is bound to that commit
and the tested bundle. The earlier candidate manifest is retained as history.
The source-face diagnostic correction required a new bundle. For that refresh,
the previously verified ZIP was checked against its recorded SHA-256, all 14
curated default cases and all 85 current source/resource members. Those files
also matched the recorded source commit. Its exact expected stdout values were
reused through a private replacement of `examples_archive.record`; the existing
archive assembly, spec and `--test-bundle` path then built and ran all 14
extracted apps against the new package. New staged sources were checked again
with only the explicit bundle URL changed. This preserves independent expected
outputs without recording new stdout as its own expectation. The production
CLI is unchanged. This is a working-tree smoke test; the final clean CI commit
is authoritative for publication.

The original 49-page manual also passes veraPDF greenfield 1.30.2 with the
explicit PDF/A-4 flavour, zero failed checks and no parser logs. The bundle
job provisions the same verified offline validator and checks the downloaded
manual before assembling publication files, using pinned Java and Python.
Negative artifact checks reject a stale manual revision, a different bundle,
and an examples ZIP naming an earlier bundle.

Bundle consumers still reject repository-only `all.roc`, require exact imported
data and licences, and compile outside the checkout against the served bundle.
The initial rc4 consumer preflight measured 104 members and 10,117,080 expanded bytes,
inside the compiler's default 10 MiB cap; no size flag is raised. Some private
fixture modules and the older tiny font remain in the archive because retained
module `expect`s import them. Removing required imported files would break the
public package boundary, so this audit does not strip them. Release manifests
also enforce and report the expanded-size bound. The earlier static-font and
metadata candidate had 104 members, 3,974,464 compressed bytes and 10,158,511
expanded bytes; its filename is
`418pLV65t6TtiHWPtDmWorrsLCrEjTnEjrWrkNvigeDQ.tar.zst` and SHA-256 is
`a43327f74c38caf2af20bf8270bf09317811404728de8dd3392e57b7bf2c4a72`.
The corrected source-face diagnostic bundle has 104 members, 3,974,692
compressed bytes and 10,158,917 expanded bytes. Its filename is
`C3YnjBMeN7A9ar7F5seM73coSTkYLSksTD2BNikQEVSP.tar.zst`, with SHA-256
`83e4ca7077ca2bb561d39f944ea23e7bc13ffa3a9c78637ea63e9d68674dfaa4`.
The new freshness lane also
exposed stale sRGB generator spellings after named arguments and Roc formatting;
its generator strings now reproduce the retained module exactly, without
changing the ICC payload, package PDF bytes or allocation evidence.

## Gallery font migration review

The retained gallery was regenerated after reviewing the switch to unchanged
static rc4 fonts, genuine family styles, inspected per-face metadata and
versioned font recipes. Three caller examples also needed explicit style
choices: chunked export and release notes select a genuine italic emphasis
family; source blocks use the built-in Sans family for prose and their own
registered monospace face for code. The chunked collector now returns directly
when emission ends, keeping the consumed encoder uniquely owned.

The update checks tagged semantic characters independently of line wrapping,
retains old artifacts locally, and records before/after hashes and sizes in
[gallery-rc4-review.json](gallery-rc4-review.json). Poppler 26.07.0 produces the
same 96 dpi previews as the existing gallery. Changed first-page previews were
visually inspected: genuine italic labels and links, prose and code faces,
charts, table rows, source indentation and page furniture remain legible and
within the page. Allocation and work baselines are reviewed separately; this
gallery operation does not update them.

## Repository settings

The before/after read-only snapshots are
[automation-settings-before.json](automation-settings-before.json) and
[automation-settings-after.json](automation-settings-after.json). Applied
changes enable immutable releases, disable workflow PR creation/approval,
restrict a new `release` environment to the named `main` branch and add active
all-tag update/deletion protection with no bypass. The audit found one direct
admin/maintainer, so no second-maintainer reviewer was invented. Existing Pages
`main` restrictions, read-only default token, signatures/PR/strict-current-check
rules and absence of app/deploy-key bypass remain effective. An admin-role
bypass is distinct from an app/deploy-key bypass.

Required branch check names are intentionally preserved until the real PR
reports the new reusable-workflow contexts successfully. The integration owner
must record those observed names and update required contexts before closing
the automation tracker; guessed nested job names are not evidence. A failed or
skipped check must not count as a successful aggregate. No release has been
published as part of this work.
