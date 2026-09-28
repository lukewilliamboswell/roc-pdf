# CIDSystemInfo ASCII strings and the Arlington case lane

This change fixes a `Pdf20` object-model defect that predates Gate 5 and adds
the Arlington lane that found it to Linux CI.

## Cause

`KernelPdfFont.add_cid_system_info` wrote the constant `CIDSystemInfo`
entries with `KernelObject.add_text_string`. Every CIDFontType2 descendant
therefore carried UTF-16BE text strings:

```
/CIDSystemInfo << /Ordering <FEFF004900640065006E0074006900740079>
                  /Registry <FEFF00410064006F00620065> /Supplement 0 >>
```

ISO 32000-2 Table 114 types `/Registry` and `/Ordering` as ASCII strings. A
text string is a different type, and its byte-order mark makes the value
non-ASCII. The pinned Arlington 1.30.2 validator rejected every font-bearing
file with `CIDSystemInfo-Registry#8` and `CIDSystemInfo-Ordering#8` ("shall
have type StringAscii"). veraPDF PDF/A-4 decodes the strings and reports
nothing, and PDFium, PDFBox, and MuPDF all accept them, so no existing lane
caught it. `scripts/check_fonts.py` had pinned the wrong bytes as canonical.

## Fix

The entries are now opaque byte strings built from ASCII literals with
`KernelObject.add_byte_string(builder, Str.to_utf8("Identity"))` and
`add_byte_string_value`, and serialize as hex:

```
/CIDSystemInfo << /Ordering <4964656E74697479> /Registry <41646F6265> /Supplement 0 >>
```

Each CIDFont is exactly 34 bytes smaller. The entries remain constants of the
one emission site, so font-leaf recipes, leaf digests, deduplication, object
numbering, and every distinctness result are unchanged. Only object offsets
after the first CIDFont move. The ToUnicode CMap's PostScript
`/CIDSystemInfo` dictionary is program text inside a stream, not a PDF
object, and is untouched. `check_fonts.py` pins the new bytes and reports
"not the canonical ASCII Adobe-Identity-0".

## Budgets

Fixtures pass static `KernelObject.Limits`. Each CIDFont's `CIDSystemInfo`
now needs 2 byte strings and 13 byte-string bytes ("Identity" + "Adobe"). It
needs 2 fewer text strings and 13 fewer text-string bytes, because text
strings are budgeted by their UTF-8 length. Each font-bearing record moves
exactly that amount from its text budget to its byte budget for the most
CIDFonts it builds. Headroom for other strings is unchanged, and the byte
budget is exact.

| Record | CIDFonts | Byte strings / bytes | Text strings / bytes |
| --- | --- | --- | --- |
| `pdf_font` `object_limits` | 1 | 0/0 → 2/13 | 2/32 → 0/19 |
| `font_leaves` `object_limits` | 64 | 0/0 → 128/832 | 2048/65536 → 1920/64704 |
| `caller_font`, `visible_text`, `actual_text` `tagged_object_limits` | 1 | 0/0 → 2/13 | 4/64 → 2/51 |
| `form_text` `object_limits` | 1 | 0/0 → 2/13 | 4/64 → 2/51 |
| `facade_output`, `facade_fragments` `output_object_limits` | 1 | 0/0 → 2/13 | 8/256 → 6/243 |
| `actual_text` `multi_face_object_limits` | 2 | 0/0 → 4/26 | 8/64 → 4/38 |
| `actual_text` `rtl_object_limits` | 1 | 0/0 → 2/13 | 8/64 → 6/51 |

`rtl_object_limits` previously inherited its bytes from the two-face record
and overrode only the string count. It now states its one-font transfer
explicitly, so it neither inherits the two-face byte budget nor loses the
text-byte headroom it had. The production budgets in `Pdf.roc`
(`standard_object_limits`) already admit 65,536 byte strings and needed no
change. The tightened records are live evidence. With the old text-string
path and the new budgets, the `actual_text` expectations fail with
`StructureFailure`.

## Work accounting

`add_text_string` records `bytes_checked` for the UTF-8 length it validates
and lexically encodes. `add_byte_string` records no work, because byte
strings are opaque: nothing is decoded or validated, and serialization is a
fixed hex expansion already bounded by `KernelOutputBound`. Adding synthetic
work here would count validation that does not happen, so none was added.
`object_bytes_checked` therefore falls by 13 per CIDFont. Only
`text-layout Type 0 PDF font objects` reports that counter (298 → 285).

## Harness change

`check_fonts.py --self-test` validates committed font-leaf snapshots
byte-for-byte. Like the PDF/A-4 and structure self-tests, it cannot pass
while `--update-snapshots` is replacing those snapshots, so it is now
`skip_on_snapshot_update` in `scripts/harness_validators.py` and runs again
as a `post_update_checks` entry in `tests/spec.json`. Ordinary runs are
unchanged.

## Reviewed rebaseline

Protocol: pinned `nightly-2026-09-26-d6267b4`, a fresh empty
`XDG_CACHE_HOME`, full harness order, `--jobs 6`, and
`./scripts/test.py --update-snapshots --baseline-report`. Every delta below
was checked mechanically against the CIDFont count of the pre-change file.
The values were then applied identically to `arm64mac` and `x64musl`.

**Snapshots.** 46 test snapshots changed, holding 128 CIDFonts: 38 with one,
2 with two, 3 with three, and one each with five, eight, and sixty-four. Each
file shrank by exactly 34 bytes per CIDFont (−4,352 bytes in total). The 9
gallery examples each have one CIDFont and shrank by exactly 34 bytes. Every
example page rasterizes byte-identically to the previous file with PDFium, so
`examples/previews` stay valid. `assets/provenance.json` sizes and digests
were refreshed textually for all 55 files.

**Work counters.** 58 cases differ. Every work delta is one of these:

- `output_bytes`, `first_output_bytes`, `second_output_bytes`,
  `archive_bytes`, `standard_bytes`: −34 per CIDFont per generation;
- `object_bytes_checked`: −13 per CIDFont (the `pdf_font` case only);
- `chunk_offset_weight`: −1,088 in both chunked facade cases. The weight sums
  chunk index × chunk length, and the 34 bytes leave chunk 32 (−34 × 32).

No other counter moved.

**Allocations.** All 58 deltas are decreases, and each scales with the number
of `CIDSystemInfo` constructions:

| Delta | Cases |
| --- | --- |
| −5 | 27 |
| −6 | 14 |
| −10 | 6 (two generations or two outputs) |
| −9 | 2 (two faces) |
| −18 | 2 (two faces, two generations) |
| −12 | 1 (two generations of a −6 case) |
| −15, −30, −30 | 3 (three fonts; −30 builds each twice) |
| −25 | 1 (five fonts) |
| −82 | eight distinct fonts |
| −640 | sixty-four distinct fonts |

Each was attributed with full, fresh-cache harness runs of controlled
variants:

- **−2 per construction: literal conversion.** `Str.to_utf8("Identity")` and
  `Str.to_utf8("Adobe")` on literals are compile-time constants. The old path
  converted each `Str` to UTF-8 at run time inside `add_text_string`. A
  variant that converts the same literals at run time through a helper
  restores exactly +2 per construction in every case (for example, +256 at
  64 fonts, where each font's info is built twice).
- **Remaining −3 to −4 per construction: string-store path.** This is the
  difference between `add_text_string` and `add_byte_string`'s store update
  under the pinned dev backend. A variant that routes the bytes through
  `KernelLex.Text.from_str` or `KernelLex.Text.bytes` changes nothing, so
  the `Text` wrapper is not the cause. The residual was not further
  attributed to a single allocation site. It is a strict decrease, linear in
  construction count, with the same sign in every case.

A single case built alone into an empty cache measures about 100 fewer
allocations than in the full harness order (the warm-cache and build-order
drift recorded in `static-pdfa4.md`). It shows only the −2 literal effect.
That is why every figure above comes from full-order runs.

## Arlington evidence

`scripts/check_arlington.py --cases` validates every distinct non-empty
snapshot in `tests/spec.json` (157) and every `examples/*.pdf` (9) against
the digest-pinned `verapdf/arlington` 1.30.2 service. Only
`tests/placeholder/snapshot.pdf` may fail. It is a fixed classic-xref PDF
written by the test platform, not package output, and it must fail exactly
`FileTrailer-ID#11` (no trailer `/ID`).

- **Before the fix:** 110 files were clean. Every one of the 55 font-bearing
  files (46 snapshots and 9 examples) failed exactly
  `CIDSystemInfo-Registry#8` and `CIDSystemInfo-Ordering#8`. The placeholder
  failed as recorded. No other rule failed anywhere.
- **After the fix:** all 165 package files are compliant with zero failed
  rules and checks: 1,488,630 passed rules and 798,668 object checks in
  total. The placeholder fails exactly its recorded rule.

The new `arlington` job in `.github/workflows/ci.yml` runs this lane on Linux
after the test job, with the pinned image as a service container on port
18080. `docs/performance/arlington.md` and the
`ROC-PDF-PDF20-EMISSION-XREF` ledger entry now describe this lane. Before it,
no CI job had run Arlington since CI was trimmed.

## Validation

- A fresh-cache `./scripts/test.py --allocation-baselines --jobs 6` passes
  all cases with the rebaselined expectations.
- `python3 scripts/check_contracts.py` passes.
- `python3 scripts/check_pdfa4.py --cases --standard-cases` passes. Archive
  snapshots are still compliant, and Standard snapshots fail only their
  deliberate omissions.
- `ROC=… python3 scripts/check_gallery.py` passes.
- `python3 scripts/check_arlington.py --self-test` passes offline, and
  `--cases` passes as above.
