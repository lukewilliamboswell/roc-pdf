# Gate 3 CJK subset asset prerequisite

## Chosen slice and evidence boundary

The next missing Gate 3 multilingual matrix row is one advanced CJK caller-font
run: an exact Han source scalar, a validated nonzero glyph in a
provenance-recorded caller/test face, one-to-one source/cluster facts, a
deterministic sanitized TrueType subset, Type 0/CID widths and `ToUnicode`,
and tagged PDF output. Its completion evidence would require a positive
snapshot and dev-backend allocation baseline, deterministic work counters,
direct CID/width/`ToUnicode`/embedded-subset inspection, qpdf, PDFBox exact
extraction, separate PDFBox and PDFium rendering facts, and an atomic
uncovered-or-corrupt-font negative that produces no PDF.

This record does not implement that output or claim the matrix row. It records
the immediate, reviewable asset prerequisite so the package does not substitute
a system font, widen the built-in face, or manufacture CJK glyph facts.

## Asset audit

`assets/provenance.json` records exactly three available TrueType source faces:

- `vendor/fonts/RocPdfSans-Regular.ttf`, the deliberately small built-in face;
- `vendor/fonts/Inter-4.1-Regular.ttf`, a test/caller asset used by the
  supplementary-plane fixture; and
- `tests/assets/CallerFont-Regular.ttf`, the generated caller-font fixture
  (its restricted-rights twin has the same glyph coverage).

None has a Han glyph. The repeatable local cmap inspection below reports no
range containing the minimal proposed source scalar U+4E2D (`中`):

```sh
fc-query --format='%{family}\\n%{charset}\\n' \
  vendor/fonts/Inter-4.1-Regular.ttf \
  tests/assets/CallerFont-Regular.ttf \
  vendor/fonts/RocPdfSans-Regular.ttf
```

The generated caller fixture reports only `20 43-44 46 50 61 66 e9`; the
built-in face has Latin, combining-mark, punctuation, and symbol coverage; and
Inter's recorded character set has no U+4E00--U+9FFF range. The manifest also
contains no Noto or other CJK source font. The existing CJK script-itemization
unit fact is Unicode-property evidence, not font coverage or a usable glyph
run.

Consequently this repository cannot construct the required positive fixture
from an existing provenance-recorded caller/test font. Attempting it would
correctly be an uncovered-scalar failure, not CJK subset evidence.

## Required prerequisite

Add one redistributable, static TrueType-flavoured OpenType CJK fixture font
under `tests/assets` or `vendor/fonts`, with all of the following reviewed in
the same change:

- a provenance-manifest entry containing immutable upstream source/revision,
  SHA-256, byte count, license, attribution, and redistribution permission;
- explicit coverage of every selected CJK scalar and a nonzero inspected glyph,
  verified through the package's bounded `cmap` inspection rather than a font
  name or system lookup;
- embedding rights accepted by `KernelFont`, plus bounds-valid sfnt tables and
  an exact caller-resource registration path;
- a declared CJK script provision and advanced shaped-run facts that preserve
  exact source, cluster, language, script, direction, glyph, and width data;
- a deterministic closure test proving the sanitized subset contains exactly
  the selected glyph closure and no external font reference; and
- a separate atomic negative for either a corrupted source allocation or an
  uncovered selected scalar. It must fail before scene/object planning and
  emit no PDF.

The asset must remain test-only or caller-supplied. It must not become a core
production dependency merely to make the convenience facade appear to support
CJK. Once this prerequisite lands, the positive output slice can add its
snapshot, structural and renderer/extractor oracles, qpdf result, work record,
and reviewed `--opt=dev` allocation baseline.

Gate 3 remains open.
