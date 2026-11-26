# Associated files

The document-level writer supports PDF/A-4f alone and the same archival
declaration combined with PDF/UA-2. The accessible profile accepts only
authored supplemental files. It checks that the descriptions can be emitted
as human-readable PDF strings and asks the author to review their meaning
and confirm that the visible document contains all essential information.

## Writer checks

| Requirement | Evidence |
| --- | --- |
| ISO 19005-4:2020 §6.7.3 and Annex A | XMP identifies part 4, revision 2020 and conformance F. The declaration checker rejects a changed conformance value. |
| ISO 19005-4:2020 §6.9 | Each file specification includes F and UF, a typed AFRelationship, an embedded-stream reference and a parameter-free MIME Subtype. The catalog includes the EmbeddedFiles name tree. The tests change each fact independently. |
| ISO 32000-2:2020 §§7.9.6, 7.11 and 14.13 | Encoded keys, leaf boundaries, indirect references, payload ownership and each file's ModDate are checked before sealing. The independent checker compares the decoded objects with authored facts and detects swapping two same-size, same-MIME payloads. |
| ISO 14289-2:2024 §§6.2, 7.2.2, 8.6 and 8.14 | An accessible profile rejects a declared dependency and private-use text in the filename or description. Each file specification carries Desc. Omission is an atomic negative. |
| WTPDF 1.0 §§6.2, 7.2.2 and 8.14 | An optional declaration exercises the same supplemental-file boundary and matches the explicit WTPDF accessibility profile. |

Table 44 of the PDF 2.0 file specification and the associated-file
relationships use the published
[syntax](https://pdf-issues.pdfa.org/32000-2-2020/clause07.html#H7.11) and
[document interchange](https://pdf-issues.pdfa.org/32000-2-2020/clause14.html#H14.13)
errata. The archive metadata follows the
[PDF/A-4 identification errata](https://pdf-issues.pdfa.org/19005-4-2020/clause06.html#H6.7.3).

The optional local Arlington 1.30.2 PDF 2.0 check passed all seven distinct
associated-file PDFs in `tests/associated_files`. The separate veraPDF
1.30.2 `4f` check passed the same seven files. Its explicit `ua2` check
passed the same bytes for the invoice and all four accessible scale or
declaration fixtures. Its explicit `wt1a` check passed the WTPDF fixture.
qpdf extracted the exact example XML. These checks exercise declarations
and machine rules. They cannot determine whether a description is meaningful
or a document can be understood without the supplied data.

## Ownership and growth

Validation first scans file counts and sizes using checked remaining capacity.
File metadata and encoded keys are bounded independently from payload size.
The registry sorts its bounded metadata once. Lowering appends one file
specification, one stream and one length object per file, with a fixed-fanout
name tree. Each stream references a full caller payload using the
unchanged-resource path. Each payload is hashed once into the canonical file
identity. Shared chunks forward its bytes, owned chunks copy it once, and
the encoder drops its reference at the final stream.

`tests/spec.json` pins allocations, requested bytes and deterministic work.
The count pair crosses the 32-file leaf boundary. The volume pair keeps
the number of files and their metadata fixed. Each run prepares once and
checks both chunk retention modes against the buffered result.

| Files | Payload bytes | Chunks | Roc allocations | Allocated bytes |
| ---: | ---: | ---: | ---: | ---: |
| 4 | 64 | 40 | 1,583 | 7,906,750 |
| 48 | 768 | 172 | 3,977 | 9,358,160 |
| 4 | 131,072 | 40 | 1,588 | 8,711,837 |

Measurements use the pinned Roc dev backend with specialization enabled on
Linux x86-64 and the ReleaseFast Zig test platform. Small public fixtures
also cover insertion permutations, exact count and payload limits, bounds
rejections and both accessible declaration selections. The bounded
`AssociatedFilesModel` explores 682 states through four additions and
finalization. The document fuzz property supplies opaque bytes and verifies
canonical output or an atomic authoring diagnostic.
