# text-layout caller-font registration slice

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
remain required text-layout evidence rather than silent fallbacks.

## The built-in face in a registry

`Font.Registry.register_built_in(registry, limits)` registers the package's
built-in face (`package/RocPdfSans-Regular.ttf`, the face of `Theme.default`)
as an ordinary registered face for the Latin script. Before it, a document
that wanted a caller face for one role (a monospace `Code` face) beside the
built-in body face had to import a copy of the built-in font bytes, because
the registry was the only path to a second face and the packaged face was
not public. The function calls the same transactional `register` path with
the package's own byte list, so validation, inspection, and retention are
identical to caller bytes: the registry retains the package allocation and
copies nothing (`copied_input_bytes` 0). It takes validation limits like
`register`, which also keeps a caller's compile-time constant registration
from being evaluated away.

Evidence, `text-layout built-in face through a registry`: the packaged face
registered as face 0 and the Noto Sans Mono fixture as face 1. A document
through the registered built-in face produces exactly the bytes of the same
document through the unregistered default (the fixture crashes otherwise),
and the snapshot is a rich paragraph whose `Code` run paints in the
monospace face over the registered built-in body face (5,207 allocations;
PDF/A-4 and rich-inline validators). There is no new failure mode: the
built-in face passes `ValidationLimits.default`, and tighter limits reject
it exactly as they would reject caller bytes.
