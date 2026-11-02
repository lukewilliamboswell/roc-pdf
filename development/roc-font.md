# Packaged roc-font families

Current assets come from roc-font [0.1.0-rc4](https://github.com/lukewilliamboswell/roc-font/releases/tag/0.1.0-rc4).
The exact published bundle is
`3Es9Gca6KTySYDqcDPHwVqpAqJk6KwT9G4xkcLoYaSsx.tar.zst`, SHA-256
`0b2705f8c4ebff64ffe2fd79ef0b335fc84561693e121fa48d1e88ae2407350c`.
All ten retained TTFs were extracted from that verified bundle and compared
with rc4's upstream archive/member/digest manifest. They are unchanged, static
files, not generated variable instances. The three OFL notices ship alongside
them. Merriweather retains its Reserved Font Name because its files are unchanged.

`python3 scripts/build_roc_font_instances.py --check` verifies all retained font
and licence bytes offline. Add `--bundle PATH` to compare against the exact
published bundle. `--install --bundle PATH` reproduces those files after checking
the complete bundle's length and digest. This current procedure needs only
Python's standard library and tar/zstd; fontTools remains necessary for unrelated
legacy fixtures, not these default assets.

## Selection, ownership and work

The ordinary facade now resolves exact family/style intent before shaping.
Default body/headings use Inter; explicit serif selects Merriweather; code uses
Fira Code. Strong/emphasis compose to genuine Bold Italic irrespective of nesting
order. Missing styles and coverage reject without fallback. The user guide records
the supported per-family/style/script matrix and the upstream unsupported cases.

The resolver first collects named demands into a fixed ten-slot set, then
registers only demanded packaged faces in canonical order through the ordinary
validated resource boundary. The full payload totals 7,070,508 bytes; the largest
face is 1,198,568 bytes. All fit the unchanged explicit 2 MB public registration
limit. The private legacy helper's former 200 KB limit is replaced for the new
assets. The explicit `RocFont.register` adapter intentionally registers all ten
once; reusing its registry/family mappings does not register them again.

Registration consumes one registry, extracts each scalar handle before its next
append, and retains the original immutable byte allocation and inspection facts.
Inline style flags propagate once through normalized preorder parents; no per-leaf
ancestry walk is required. A dense face-to-candidate map avoids repeated scans
when source blocks introduce many distinct caller fonts. Candidate inspection
stores contain selected faces; final output compacts to painted faces and embeds
only their sanitized subsets. Temporary style/demand tables do not enter sealed
PDF plans. Each stage retains its own explicit facts rather than identifying a
family by a PostScript name, glyph ID or insertion accident.

Deterministic resolver counters are `packaged_inspections`,
`registered_font_bytes`, `inline_visits`, `source_visits` and
`copied_input_bytes`. The last counts resource-input copies and remains zero;
new subset bytes are distinct output work. Inline/source counters cover every
resolution traversal, including dense exact-face materialization. The default
asset migration deliberately changes applicable facade measurements, pagination,
font programs, snapshot bytes and allocations. The integration review records
these causes before any evidence baseline is updated.

Facade layout-work probes consume the same resolved family/style facts as their
public outputs. Custom-block evidence measures selected-font line layout and
pagination; final report facts independently cover fragments and placements.
It does not substitute the legacy regression face or lower colored panels
without document intent facts. Replacing its former legacy-face TextReady probe
changes that fixture's measurement boundary, so both targets must be measured
again before allocation baselines are accepted.

## Source metadata and exact angles

Inspection now retains source post angle/fixed-pitch facts and validates
head/OS2 Bold/Italic style-link consistency. The subset post header preserves
the exact original angle and fixed-pitch value; head/OS2 style declarations are
copied unchanged. Descriptor style facts are resolved before canonical resource
identity. Italic/Oblique and FixedPitch flags follow those retained facts.
Positive OS/2 family-class/PANOSE declarations set Serif; unknown/conflicting
classification never consults a name. All supplied rc4 faces have unclassified
serif metadata (family-class zero; Merriweather/Fira PANOSE all zero; Inter
PANOSE family 2 with serif-style zero), so the package does not invent that flag.

The source Inter italic angle is exactly `-616038/65536` degrees and
Merriweather's is `-511180/65536`; neither is an integer. A separate bounded
signed-16.16 number primitive emits these exact finite decimals without floating
point or rounding. Unit witnesses cover the full signed endpoints, sub-unit
angles, canonical zero and an independent Oblique flag. Source formats follow
the primary [post](https://learn.microsoft.com/en-us/typography/opentype/spec/post),
[head](https://learn.microsoft.com/en-us/typography/opentype/spec/head), and
[OS/2](https://learn.microsoft.com/en-us/typography/opentype/spec/os2) definitions.

Canonical font-leaf recipe schema 2 explicitly changes its angle field from
integer degrees to raw signed 16.16. The unchanged eight-byte width adds no
recipe bytes or traversal work, but the new version changes resource/file
identities even for upright zero-angle faces. It does not change those faces'
metrics or the source-digest/glyph-closure subset-tag procedure. Exact style
metadata and larger inspection records are deliberate migration causes, not
automatically accepted baseline drift.
The direct subset control isolates the runtime 32-byte subset `post` header
allocation from descriptor resolution. Review that control and the expanded
inline inspection storage with the [allocation baseline protocol](testing.md#allocation-baselines).

## Legacy fixture fonts

Older regression fixtures use the source pins in
`vendor/fonts/roc-font/rc3-upstream-pins.json` and the recipe
`vendor/fonts/roc-font/build_rc3_instances.py`. Keep their recorded source bytes,
licenses and generator requirements together; updating the default families does
not silently regenerate those independent fixtures.
