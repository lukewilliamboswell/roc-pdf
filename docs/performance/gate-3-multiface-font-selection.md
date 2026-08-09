# Gate 3 ordered multi-face cluster planning

This slice makes font selection an explicit, finite policy boundary. A caller
registers validated faces as before, then `Font.Registry.with_policy` accepts
an ordered list of opaque faces and produces an opaque policy ID. Empty,
unknown, and duplicate-face policies reject before a plan is returned. A
duplicate would make the selected policy ambiguous, so it is not normalized or
silently deduplicated.

`Font.Registry.plan` consumes prior grapheme-cluster scalar and per-cluster
script facts plus the request language/source identities. It neither decodes source UTF-8 nor
discovers boundaries. For each cluster it visits the ordered validated faces,
checks the retained cmap coverage spans once for every eligible candidate, and
returns coalesced dense `FaceRange` facts containing the selected static
instance. No subsequent stage can infer a face from glyph IDs, a font name, or
reader behaviour. A missing cluster is a transactional `MissingCoverage`
rejection; it produces no usable plan.

The focused `Gate 3 ordered multi-face cluster selection` case registers the
external 7,816-byte caller Latin fixture and the 2,104-byte test-only CJK
fixture, builds the ordered policy `[caller, cjk]`, and selects three source
clusters `C`, `中`, `é` itemized as `Latn`, `Hani`, `Latn` and selects instance
ranges `[caller, cjk, caller]`. It proves
the two payloads are retained once with zero copied input bytes, two resources,
two faces/instances, and one added ordered policy. The same case atomically
rejects U+10FFFF coverage, a Latin `C` falsely itemized as `Hani`, a duplicate
caller face (ambiguous policy), and an unknown face (invalid policy). It emits
the established blank structural
carrier solely for the harness protocol; planning failures never emit PDF
bytes.

On the local pinned dev backend (`release-fast-64c9d73d`, x64musl), this
planning evidence records 75 allocation events and deterministic work:
7,816/2,104 input and retained bytes, zero copied bytes, two resources/faces/
instances, three policies, three grapheme visits, four face visits, 15 cmap
span visits, three face ranges, and 667 carrier bytes. The only added storage
is the bounded policy instance list and the selected range list; both scale
with their explicit inputs. The fixture deliberately does not claim a
cross-platform rebaseline.

This is not public multi-face PDF output yet. `Theme` and the current facade
still select one body face and `KernelFacadeShape` still produces one-font
runs. The next integration must carry these selected `FaceRange` facts through
shape, global subset planning, scene runs, and resource lowering without
retesting coverage or falling back to the packaged face. It must separately
establish public mixed-face extraction/rendering, source retention through
final subset emission, and allocation evidence.
