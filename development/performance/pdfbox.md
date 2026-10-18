# structural-kernel strict PDFBox parsing

## Parser pin and strict boundary

Linux CI selects the exact Temurin 17.0.20+8 build through an immutable
`setup-java` action revision, then uses Apache PDFBox 3.0.8's vendored
standalone application jar and verifies SHA-512
`768847238f683568507bf73570a2b6fedcbe58b25c7b4f97fba536ba110b290fe96ba065aed58629d41fb94857d76bc1978c2f31d294b553c69f287f71ee9600`.
The checker also reads the jar manifest and rejects any implementation version
other than 3.0.8.

`scripts/StrictPdfCheck.java` constructs `PDFParser` over the original file and
calls `parse(false)`. The explicit `false` selects PDFBox's non-lenient path;
the ordinary loader and the parser's zero-argument `parse()` are not used
because they enable auto-healing by default. The checker captures both Java
warning records and raw standard-error diagnostics across parsing, lazy object
loading, stream decoding, content parsing, and close. Any warning or diagnostic
fails the check.

## Independent facts

Every xref entry is dereferenced. The checker asserts PDF 2.0, an xref stream,
no hybrid xref or encryption, contiguous generation-zero object numbers, exact
`/Size`, object 1 as `/Root`, a paired 32-byte identifier, and exact catalog,
page-tree, page, and xref-stream type counts. It walks the independent PDFBox
page model, verifies every parent, content, and indirect-length reference,
checks the A4 media box and empty resource dictionary, decodes every content
stream, and incrementally parses every content token.

| Snapshot | Pages | Objects | `/Pages` nodes | Decoded bytes | Operators |
| --- | ---: | ---: | ---: | ---: | ---: |
| blank | 1 | 6 | 1 | 0 | 0 |
| one-block DEFLATE | 1 | 6 | 1 | 65,535 | 32,768 |
| five-block DEFLATE | 1 | 6 | 1 | 262,144 | 131,072 |
| balanced pages | 4,096 | 12,423 | 133 | 0 | 0 |
| unchanged resource | 1 | 6 | 1 | 64 | 0 |

The generated streams must contain only balanced, alternating `q` and `Q`
operators; blank and unchanged-resource streams must be empty or whitespace-
only. This forces lazy object loading, Flate decoding, and content parsing
instead of accepting a successful initial catalog load as sufficient evidence.

## Recovery negative

The checker shifts the blank fixture's `startxref` by one byte without changing
the file length. PDFBox must reject it while executing `parse(false)` with the
dedicated strict-parse exit status. A later object-fact mismatch does not count
as proof that recovery was disabled.

PDFBox is independent parser evidence, not the conformance source of truth and
not a repair or rewrite stage. Arlington, qpdf, and the byte-level structural
checker retain their separate scopes.
