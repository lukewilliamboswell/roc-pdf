# Bibliography evidence

The public compiler resolves normalized citation ownership to an explicitly
authored bibliography target before shaping. Destination names use the
same stable identity for both the structure reference and interactive link.
Two bounded walks form and fill the dense forward/backlink tape. A
bibliography's sorted identity index supports binary lookup, and its
structure children remain in author order.

ISO 32000-2:2020 §14.7.2 Table 355 and §12.3.2.3 govern structure references
and interactive structure destinations. WTPDF 1.0 §8.2.5.31 specifies
BibEntry and the ARIA bibliography section and recommends backlinks to all
citations. The producer uses the exact lowercase `/role` property in the
ARIA example in §§8.2.5.31 and 8.2.6.4. BibEntry uses the PDF 1.7
namespace, and a P under the PDF 2.0 Sect supplies the mixed-namespace
containment from ISO/TS 32005:2023 Table 5.

The independent oracle traverses tagged owners, decodes marked text and
checks every page destination, structure destination and reciprocal edge.
It rejects mutations that drop a repeat backlink or redirect a citation to
a different valid bibliography entry. The model exhausts 81 states at
depth four with two entry orders and up to three citation choices. It
compares resolved IDs against an independent authored identity lookup
and requires the first missing declaration to abort at its citing block.
The fixture group exercises eight located failures through bytes and chunk
preparation and compares ordinary and reported PDF output.

The three fixture PDFs and handbook variant pass explicit veraPDF `4`
and `ua2`. The WTPDF snapshot also passes `wt1a`. Arlington 1.30.2
evaluates the same four files and reports one
`StructureAttributesDict#1` disagreement at each specified bibliography
section attribute object path. The whitelist recognizes uppercase
`/Role`. The writer uses the case-sensitive lowercase key specified
by WTPDF. The Arlington harness pins the exact rule, occurrence count
and object path. Independent PDF inspection verifies the enclosing Sect,
the exact dictionary, the PDF 1.7 roles and the authored graph.

| Fixture | x64musl allocations | Allocated bytes | Citations | Ref edges |
| --- | ---: | ---: | ---: | ---: |
| Small graph | 2,459 | 7,056,890 | 2 | 4 |
| Large graph | 3,919 | 9,713,266 | 20 | 40 |
| WTPDF | 2,461 | 7,060,484 | 2 | 4 |
| Sixteen rejected deliveries and one accepted graph | 3,708 | 7,302,978 | 2 | 4 |

The allocation boundary starts before fixture dispatch. The harness
enforces exact counts, deterministic work, and the 110% byte ceiling.
The development checks ran on x64musl. Native arm64mac execution and
cross-target byte equality are checked in the shared workflow.
