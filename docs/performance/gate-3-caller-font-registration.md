# Gate 3 caller-font registration slice

This slice establishes the public pure-Roc resource boundary for fonts acquired
by an application or optional asset package. `Font.Registry.register` accepts a
complete replayable `List(U8)`, an explicit shaping provision and ISO 15924
script list, and caller-visible validation limits. It runs the same bounded
TrueType inspection used for packaged fonts before allocating any usable
handle.

Successful registration allocates dense resource, face, static-instance, and
single-instance policy handles. Coverage comes only from the validated cmap;
embedding rights come only from the inspected OS/2 table; declared scripts are
canonical four-byte tags. The registry retains the original byte allocation and
the once-produced inspection facts. Its work evidence therefore records zero
input-payload copying and equal input/retained byte counts. `Theme.with_font`
selects the returned face without a system-font name or caller-assigned ID.

The compile-checked public example imports the fixture as `List(U8)`, registers
it, inspects the public store shape, and selects its returned face through the
theme. The fixture is a deterministic 7,816-byte subset of the separately
attributed Inter 4.1 source, lives under `tests/assets`, and is absent from the
core package dependency closure.

The pinned optimized evidence is identical on `arm64mac` and `x64musl`: 75 Roc
allocations; 7,816 input and retained bytes; zero copied input bytes; 17 table,
15 glyph, 9 cmap-mapping, 4 composite-edge, and 7 coverage-span visits; dense
face, instance, and policy IDs of zero; and exactly one resource, face,
instance, and policy. The evidence emits the established 667-byte blank
structural snapshot because this slice measures registration, not final text
emission. The one-allocation increase from the initial slice materializes the
small public PostScript-name fact; the input font payload remains uncopied.

## Boundary and remaining evidence

Malformed signature bytes receive `UnsupportedFormat` without a partial
registry. The subsequent caller-text slice adds the checksum-valid
embedding-prohibited twin and caller-face shaping, subsetting, embedding,
extraction, and rendering evidence. Source-allocation reference counts through
final emission, multi-placement parse reuse, and public facade generation still
remain required Gate 3 evidence rather than silent fallbacks.
