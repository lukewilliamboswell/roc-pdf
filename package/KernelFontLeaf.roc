import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelPdfFont
import KernelResourceGraph

## Canonical font-leaf identity.
##
## One emitted Type 0 bundle (FontFile2 subset program, identity CIDToGIDMap,
## ToUnicode CMap, descriptor, CIDFontType2 descendant, and Type 0 parent) is
## one inseparable canonical resource. Its identity payload is a typed recipe,
## bijective with the emitted bundle: every emitted dictionary fact serialized
## in its exact emitted form, followed by the exact sanitized subset-program
## bytes. The recipe is derived once from validated earlier-stage facts —
## inspection, glyph-closure plan, sanitized subset, descriptor policy, and
## the collected Unicode mappings — never from caller payload bytes, authored
## dense IDs, emitted resource names, object numbers, or serialized content.
##
## Facts that are constants of the one emission site are not serialized and
## cannot differ between two bundles that reach emission: Identity-H encoding,
## horizontal writing mode, CIDSystemInfo Adobe-Identity-0, `/DW 1000`, the
## `/W [0 [...]]` array shape, the unfiltered FontFile2 with `/Length1`, and
## the fixed ToUnicode header/footer/blocking. Embedding-permission and
## hinting differences live inside the sanitized program's retained tables,
## so they are inside the recipe's subset bytes.
##
## The digest over this recipe is a candidate only: the canonical graph run
## partitions by exact descriptor and byte length and confirms every merge by
## exact payload equality. Because the recipe embeds the subset bytes, exact
## recipe equality is simultaneously typed-fact equality and exact
## relevant-byte equality.
KernelFontLeaf :: [].{
	Error : [
		ArithmeticOverflow,

		## The descriptor policy or inspected units-per-em cannot produce
		## the emitted integers (negative flags, non-positive StemV, or a
		## zero units-per-em divisor).
		DescriptorInvalid,
		EmptyUnicodeMapping({ cid : U32 }),

		## The glyph-closure plan is not the dense CID-equals-subset-glyph
		## shape the emitted CID map and width array require.
		FontPlanInvalid,
		InvalidPostScriptName,

		## The deterministic subset tag is not six uppercase ASCII letters.
		InvalidSubsetTag,
		InvalidUnicodeScalar(U32),

		## A content CID has no collected Unicode mapping, so the emitted
		## ToUnicode CMap would be incomplete.
		MissingUnicodeMapping({ cid : U32 }),

		## The sanitized subset bytes disagree with their recorded length.
		SubsetLengthMismatch({ actual : U64, recorded : U64 }),

		## A mapping arrived for a CID that is not a content CID or arrived
		## out of dense CID order.
		UnexpectedUnicodeMapping({ cid : U32 }),
	]

	## The validated earlier-stage facts one emitted Type 0 bundle consumes.
	## The same bundle value feeds identity derivation here and object
	## lowering in `KernelPdfFont`, so a recipe and its emitted bundle cannot
	## disagree.
	Bundle : {
		descriptor : KernelPdfFont.Descriptor,
		font : KernelFont.Inspection,
		mappings : List(KernelPdfFont.UnicodeMapping),
		plan : KernelFontPlan.Plan,
		subset : KernelFontSubset.Subset,
	}

	Work : {
		mapping_scalars : U64,
		recipe_bytes : U64,
		subset_bytes : U64,
		unicode_mappings : U64,
		width_entries : U64,
	}

	Leaf :: { descriptor : KernelResourceGraph.Descriptor, recipe : List(U8), work : Work }.{
		build : Bundle -> Try(Leaf, Error)
		build = |bundle| build_leaf(bundle)

		descriptor : Leaf -> KernelResourceGraph.Descriptor
		descriptor = |leaf| leaf.descriptor

		recipe : Leaf -> List(U8)
		recipe = |leaf| leaf.recipe

		work : Leaf -> Work
		work = |leaf| leaf.work
	}
}

## The recipe tag: version 1 of the supported TrueType-flavoured
## CIDFontType2 bundle shape.
font_bundle_recipe_tag : U8
font_bundle_recipe_tag = 1

build_leaf : KernelFontLeaf.Bundle -> Try(KernelFontLeaf.Leaf, KernelFontLeaf.Error)
build_leaf = |bundle| {
	if bundle.descriptor.flags < 0 or bundle.descriptor.stem_v <= 0 {
		return Err(DescriptorInvalid)
	}
	units_per_em = bundle.font.metrics.units_per_em
	if units_per_em == 0 {
		return Err(DescriptorInvalid)
	}
	if !valid_subset_tag(bundle.plan.prefix) {
		return Err(InvalidSubsetTag)
	}
	postscript_name = KernelFont.postscript_name(bundle.font)
	if !KernelPdfFont.valid_font_name_bytes(postscript_name) {
		return Err(InvalidPostScriptName)
	}
	if bundle.plan.entries.len() == 0 or bundle.plan.entries.len() > 65535 {
		return Err(FontPlanInvalid)
	}
	if bundle.subset.bytes.len() != bundle.subset.work.output_bytes {
		return Err(SubsetLengthMismatch({ actual: bundle.subset.bytes.len(), recorded: bundle.subset.work.output_bytes }))
	}

	## Exact size first, so the recipe is one allocation.
	mapping_totals = validate_mappings(bundle.plan, bundle.mappings)?
	name_bytes = postscript_name.len()
	entry_bytes = checked_times(bundle.plan.entries.len(), 9)?
	mapping_bytes = checked_add(checked_times(bundle.mappings.len(), 12)?, checked_times(mapping_totals.scalars, 4)?)?
	fixed_bytes = 1 + 6 + 8 + 24 + 56 + 8 + 8 + 8
	size = checked_add(checked_add(checked_add(checked_add(fixed_bytes, name_bytes)?, entry_bytes)?, mapping_bytes)?, bundle.subset.bytes.len())?

	var $recipe = List.with_capacity(size)
	$recipe = $recipe.append(font_bundle_recipe_tag)

	## The emitted BaseFont: the deterministic subset tag and the validated
	## PostScript name (the `+` separator is a constant of the emission
	## site).
	$recipe = append_all($recipe, bundle.plan.prefix)
	$recipe = append_u64_bytes($recipe, name_bytes)
	$recipe = append_all($recipe, postscript_name)

	## Descriptor policy facts, exactly as emitted.
	$recipe = append_i64_bytes($recipe, bundle.descriptor.flags)
	$recipe = append_i64_bytes($recipe, bundle.descriptor.italic_angle)
	$recipe = append_i64_bytes($recipe, bundle.descriptor.stem_v)

	## Metrics exactly as the descriptor emits them, through the shared
	## scaling helpers the object lowering uses.
	$recipe = append_i64_bytes($recipe, scaled_signed(bundle.font.metrics.ascent, units_per_em)?)
	$recipe = append_i64_bytes($recipe, scaled_signed(bundle.font.metrics.cap_height, units_per_em)?)
	$recipe = append_i64_bytes($recipe, scaled_signed(bundle.font.metrics.descent, units_per_em)?)
	$recipe = append_i64_bytes($recipe, scaled_signed(bundle.font.metrics.x_min, units_per_em)?)
	$recipe = append_i64_bytes($recipe, scaled_signed(bundle.font.metrics.y_min, units_per_em)?)
	$recipe = append_i64_bytes($recipe, scaled_signed(bundle.font.metrics.x_max, units_per_em)?)
	$recipe = append_i64_bytes($recipe, scaled_signed(bundle.font.metrics.y_max, units_per_em)?)

	## The width table: per CID the exact emitted `/W` integer and the
	## content flag. The entry count also commits the identity CIDToGIDMap
	## stream, because CID = subset glyph ID is validated below.
	$recipe = append_u64_bytes($recipe, bundle.plan.entries.len())
	var $entry_index = 0
	var $failure = NoFailure
	while $entry_index < bundle.plan.entries.len() and $failure == NoFailure {
		entry = list_at(bundle.plan.entries, $entry_index)
		if entry.cid.to_u64() != $entry_index or entry.subset_glyph != entry.cid {
			$failure = Failed(FontPlanInvalid)
		} else {
			match scaled_unsigned(entry.width, units_per_em) {
				Err(error) => {
					$failure = Failed(error)
				}
				Ok(width) => {
					$recipe = append_u64_bytes($recipe, width)
					$recipe = $recipe.append(if entry.content 1 else 0)
				}
			}
		}
		$entry_index = $entry_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## The ToUnicode facts: the exact `bfchar` content of the emitted CMap.
	$recipe = append_u64_bytes($recipe, bundle.mappings.len())
	var $mapping_index = 0
	while $mapping_index < bundle.mappings.len() {
		mapping = list_at(bundle.mappings, $mapping_index)
		$recipe = append_u32_bytes($recipe, mapping.cid)
		$recipe = append_u64_bytes($recipe, mapping.scalars.len())
		var $scalar_index = 0
		while $scalar_index < mapping.scalars.len() {
			$recipe = append_u32_bytes($recipe, list_at(mapping.scalars, $scalar_index))
			$scalar_index = $scalar_index + 1
		}
		$mapping_index = $mapping_index + 1
	}

	## The exact sanitized subset-program bytes: the relevant-byte authority
	## that exact equality confirms after any digest candidate.
	$recipe = append_u64_bytes($recipe, bundle.subset.bytes.len())
	$recipe = append_all($recipe, bundle.subset.bytes)

	Ok(
		KernelFontLeaf.Leaf.{
			descriptor: {
				bit_depth: 0,
				components: 0,
				flags: 0,
				height: 0,
				kind: Font,
				subtype: 0,
				width: 0,
			},
			recipe: $recipe,
			work: {
				mapping_scalars: mapping_totals.scalars,
				recipe_bytes: $recipe.len(),
				subset_bytes: bundle.subset.bytes.len(),
				unicode_mappings: bundle.mappings.len(),
				width_entries: bundle.plan.entries.len(),
			},
		},
	)
}

## The collected mappings must agree with the plan's content flags exactly:
## one mapping per content CID in dense CID order, no mapping for a
## dependency-only CID, no empty mapping, and no invalid scalar. The same
## agreement is re-validated by the object lowering, so a recipe and its
## emitted ToUnicode stream cannot disagree.
validate_mappings : KernelFontPlan.Plan, List(KernelPdfFont.UnicodeMapping) -> Try({ scalars : U64 }, KernelFontLeaf.Error)
validate_mappings = |plan, mappings| {
	var $mapping_index = 0
	var $scalar_count = 0
	var $entry_index = 0
	while $entry_index < plan.entries.len() {
		entry = list_at(plan.entries, $entry_index)
		if entry.content {
			if $mapping_index >= mappings.len() {
				return Err(MissingUnicodeMapping({ cid: entry.cid }))
			}
			mapping = list_at(mappings, $mapping_index)
			if mapping.cid != entry.cid {
				return if mapping.cid < entry.cid Err(UnexpectedUnicodeMapping({ cid: mapping.cid })) else Err(MissingUnicodeMapping({ cid: entry.cid }))
			}
			if mapping.scalars.len() == 0 {
				return Err(EmptyUnicodeMapping({ cid: entry.cid }))
			}
			var $scalar_index = 0
			while $scalar_index < mapping.scalars.len() {
				scalar = list_at(mapping.scalars, $scalar_index)
				if scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff) {
					return Err(InvalidUnicodeScalar(scalar))
				}
				$scalar_index = $scalar_index + 1
			}
			$scalar_count = checked_add($scalar_count, mapping.scalars.len())?
			$mapping_index = $mapping_index + 1
		}
		$entry_index = $entry_index + 1
	}
	if $mapping_index != mappings.len() {
		return Err(UnexpectedUnicodeMapping({ cid: list_at(mappings, $mapping_index).cid }))
	}
	Ok({ scalars: $scalar_count })
}

valid_subset_tag : List(U8) -> Bool
valid_subset_tag = |prefix| {
	if prefix.len() != 6 {
		return Bool.False
	}
	var $index = 0
	var $valid = Bool.True
	while $valid and $index < prefix.len() {
		byte = list_at(prefix, $index)
		if byte < 0x41 or byte > 0x5a {
			$valid = Bool.False
		}
		$index = $index + 1
	}
	$valid
}

scaled_signed : I64, U16 -> Try(I64, KernelFontLeaf.Error)
scaled_signed = |value, units_per_em| match KernelPdfFont.scaled_signed_metric(value, units_per_em) {
	Err(ArithmeticOverflow) => Err(ArithmeticOverflow)
	Err(_) => Err(DescriptorInvalid)
	Ok(scaled) => Ok(scaled)
}

scaled_unsigned : U16, U16 -> Try(U64, KernelFontLeaf.Error)
scaled_unsigned = |value, units_per_em| match KernelPdfFont.scaled_unsigned_metric(value, units_per_em) {
	Err(ArithmeticOverflow) => Err(ArithmeticOverflow)
	Err(_) => Err(DescriptorInvalid)
	Ok(scaled) => Ok(scaled)
}

append_all : List(U8), List(U8) -> List(U8)
append_all = |target, source| {
	var $result = target
	var $index = 0
	while $index < source.len() {
		$result = $result.append(list_at(source, $index))
		$index = $index + 1
	}
	$result
}

append_u64_bytes : List(U8), U64 -> List(U8)
append_u64_bytes = |output, value| output
	.append(value.shr_wrap(56).to_u8_wrap())
	.append(value.shr_wrap(48).to_u8_wrap())
	.append(value.shr_wrap(40).to_u8_wrap())
	.append(value.shr_wrap(32).to_u8_wrap())
	.append(value.shr_wrap(24).to_u8_wrap())
	.append(value.shr_wrap(16).to_u8_wrap())
	.append(value.shr_wrap(8).to_u8_wrap())
	.append(value.to_u8_wrap())

append_i64_bytes : List(U8), I64 -> List(U8)
append_i64_bytes = |output, value| append_u64_bytes(output, value.to_u64_wrap())

append_u32_bytes : List(U8), U32 -> List(U8)
append_u32_bytes = |output, value| output
	.append(value.shr_wrap(24).to_u8_wrap())
	.append(value.shr_wrap(16).to_u8_wrap())
	.append(value.shr_wrap(8).to_u8_wrap())
	.append(value.to_u8_wrap())

checked_add : U64, U64 -> Try(U64, KernelFontLeaf.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelFontLeaf.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated font-leaf index escaped"
	}
}

## A minimal hand-built inspection whose PostScript name is `Test` and whose
## metrics scale exactly at 1000 units per em, so expected recipe integers
## are the raw metric values.
test_inspection : {} -> KernelFont.Inspection
test_inspection = |_| {
	bytes: [0, 0x54, 0, 0x65, 0, 0x73, 0, 0x74],
	cmap: Format12({ groups: [] }),
	components: [],
	coverage: [],
	digest: List.repeat(7, 32),
	embedding_rights: Installable,
	loca_offsets: [],
	metrics: {
		ascent: 800,
		cap_height: 700,
		descent: -200,
		glyph_count: 3,
		index_to_loc_format: 1,
		line_gap: 0,
		number_of_h_metrics: 3,
		units_per_em: 1000,
		x_max: 900,
		x_min: -50,
		y_max: 950,
		y_min: -250,
	},
	names: {
		family_utf16be: { length: 0, offset: 0 },
		full_utf16be: { length: 0, offset: 0 },
		postscript_utf16be: { length: 8, offset: 0 },
	},
	tables: [],
	work: {
		checksum_bytes: 0,
		cmap_mapping_visits: 0,
		component_edge_visits: 0,
		directory_entries: 0,
		glyph_visits: 0,
		loca_entries: 0,
		overlap_comparisons: 0,
	},
}

test_plan : {} -> KernelFontPlan.Plan
test_plan = |_| {
	entries: [
		{ cid: 0, content: Bool.False, left_side_bearing: 0, original_glyph: 0, subset_glyph: 0, width: 500 },
		{ cid: 1, content: Bool.True, left_side_bearing: 10, original_glyph: 2, subset_glyph: 1, width: 600 },
	],
	original_to_subset: [0, 0xffffffff, 1],
	prefix: [0x41, 0x42, 0x43, 0x44, 0x45, 0x46],
	retained: [1, 0, 2],
	work: { component_edge_visits: 0, component_index_visits: 0, glyph_scans: 3, retained_glyphs: 2, usage_visits: 1 },
}

test_subset : {} -> KernelFontSubset.Subset
test_subset = |_| {
	bytes: [9, 8, 7, 6],
	work: { cmap_mappings: 1, component_rewrites: 0, entry_visits: 2, glyf_bytes: 0, hmtx_bytes: 8, loca_bytes: 8, output_bytes: 4, source_glyph_bytes: 0, tables: 14 },
}

test_bundle : {} -> KernelFontLeaf.Bundle
test_bundle = |_| {
	descriptor: { flags: 32, italic_angle: 0, stem_v: 80 },
	font: test_inspection({}),
	mappings: [{ cid: 1, scalars: [0x41] }],
	plan: test_plan({}),
	subset: test_subset({}),
}

## The recipe serializes every emitted fact in fixed order and embeds the
## exact subset bytes, and derivation is deterministic.
expect {
	leaf = KernelFontLeaf.Leaf.build(test_bundle({}))?
	again = KernelFontLeaf.Leaf.build(test_bundle({}))?
	expected = append_u64_bytes(
		append_i64_bytes(
			append_i64_bytes(
				append_i64_bytes(
					append_i64_bytes(
						append_i64_bytes(
							append_i64_bytes(
								append_i64_bytes(
									append_i64_bytes(
										append_i64_bytes(
											append_i64_bytes(
												append_all(
													append_u64_bytes(append_all([font_bundle_recipe_tag], [0x41, 0x42, 0x43, 0x44, 0x45, 0x46]), 4),
													[0x54, 0x65, 0x73, 0x74],
												),
												32,
											),
											0,
										),
										80,
									),
									800,
								),
								700,
							),
							-200,
						),
						-50,
					),
					-250,
				),
				900,
			),
			950,
		),
		2,
	)
		.concat(append_u64_bytes([], 500).append(0))
		.concat(append_u64_bytes([], 600).append(1))
		.concat(append_u64_bytes([], 1))
		.concat(append_u32_bytes([], 1))
		.concat(append_u64_bytes([], 1))
		.concat(append_u32_bytes([], 0x41))
		.concat(append_u64_bytes([], 4))
		.concat([9, 8, 7, 6])
	work = KernelFontLeaf.Leaf.work(leaf)
	descriptor = KernelFontLeaf.Leaf.descriptor(leaf)
	KernelFontLeaf.Leaf.recipe(leaf) == expected and
		KernelFontLeaf.Leaf.recipe(again) == expected and
			work.recipe_bytes == expected.len() and
				work.subset_bytes == 4 and
					work.width_entries == 2 and
						work.unicode_mappings == 1 and
							work.mapping_scalars == 1 and
								descriptor.kind == Font and descriptor.subtype == 0
}

## Every identity axis flips the recipe: mappings, widths, subset bytes,
## descriptor policy, and the subset tag each produce a distinct payload
## while a byte-identical bundle reproduces it exactly.
expect {
	bundle = test_bundle({})
	base = KernelFontLeaf.Leaf.build(bundle)?
	other_mapping = KernelFontLeaf.Leaf.build({ ..bundle, mappings: [{ cid: 1, scalars: [0xc5] }] })?
	base_plan = test_plan({})
	wider = KernelFontLeaf.Leaf.build({
		..bundle,
		plan: {
			..base_plan,
			entries: [
				{ cid: 0, content: Bool.False, left_side_bearing: 0, original_glyph: 0, subset_glyph: 0, width: 500 },
				{ cid: 1, content: Bool.True, left_side_bearing: 10, original_glyph: 2, subset_glyph: 1, width: 700 },
			],
		},
	})?
	other_subset = KernelFontLeaf.Leaf.build({
		..bundle,
		subset: {
			bytes: [9, 8, 7, 5],
			work: { cmap_mappings: 1, component_rewrites: 0, entry_visits: 2, glyf_bytes: 0, hmtx_bytes: 8, loca_bytes: 8, output_bytes: 4, source_glyph_bytes: 0, tables: 14 },
		},
	})?
	other_policy = KernelFontLeaf.Leaf.build({ ..bundle, descriptor: { flags: 32, italic_angle: 0, stem_v: 90 } })?
	other_tag = KernelFontLeaf.Leaf.build({
		..bundle,
		plan: { ..base_plan, prefix: [0x47, 0x42, 0x43, 0x44, 0x45, 0x46] },
	})?
	recipes = [
		KernelFontLeaf.Leaf.recipe(base),
		KernelFontLeaf.Leaf.recipe(other_mapping),
		KernelFontLeaf.Leaf.recipe(wider),
		KernelFontLeaf.Leaf.recipe(other_subset),
		KernelFontLeaf.Leaf.recipe(other_policy),
		KernelFontLeaf.Leaf.recipe(other_tag),
	]
	var $index = 0
	var $distinct = Bool.True
	while $index < recipes.len() {
		var $other = $index + 1
		while $other < recipes.len() {
			if list_at(recipes, $index) == list_at(recipes, $other) {
				$distinct = Bool.False
			}
			$other = $other + 1
		}
		$index = $index + 1
	}
	$distinct
}

## Metric scaling in the recipe matches the emitted descriptor integers for
## a non-trivial units-per-em (2048: 800 font units emit 391).
expect {
	base = test_inspection({})
	source = test_bundle({})
	bundle = { ..source, font: { ..base, metrics: { ..base.metrics, units_per_em: 2048 } } }
	leaf = KernelFontLeaf.Leaf.build(bundle)?
	expected_ascent = KernelPdfFont.scaled_signed_metric(800, 2048)?
	recipe = KernelFontLeaf.Leaf.recipe(leaf)
	slice_start = 1 + 6 + 8 + 4 + 24
	var $value = 0
	var $index = 0
	while $index < 8 {
		$value = $value * 256 + list_at(recipe, slice_start + $index).to_u64()
		$index = $index + 1
	}
	expected_ascent == 391 and $value == 391
}

## Each identity-boundary rejection is a distinct typed error and no recipe
## escapes.
expect {
	bundle = test_bundle({})
	bad_descriptor = match KernelFontLeaf.Leaf.build({ ..bundle, descriptor: { flags: 32, italic_angle: 0, stem_v: 0 } }) {
		Err(DescriptorInvalid) => Bool.True
		_ => Bool.False
	}
	base = test_inspection({})
	bad_units = match KernelFontLeaf.Leaf.build({ ..bundle, font: { ..base, metrics: { ..base.metrics, units_per_em: 0 } } }) {
		Err(DescriptorInvalid) => Bool.True
		_ => Bool.False
	}
	base_plan = test_plan({})
	bad_tag = match KernelFontLeaf.Leaf.build({ ..bundle, plan: { ..base_plan, prefix: [0x41, 0x42, 0x43] } }) {
		Err(InvalidSubsetTag) => Bool.True
		_ => Bool.False
	}
	lower_tag = match KernelFontLeaf.Leaf.build({ ..bundle, plan: { ..base_plan, prefix: [0x61, 0x42, 0x43, 0x44, 0x45, 0x46] } }) {
		Err(InvalidSubsetTag) => Bool.True
		_ => Bool.False
	}
	bad_name = match KernelFontLeaf.Leaf.build({ ..bundle, font: { ..base, names: { ..base.names, postscript_utf16be: { length: 0, offset: 0 } } } }) {
		Err(InvalidPostScriptName) => Bool.True
		_ => Bool.False
	}
	empty_plan = match KernelFontLeaf.Leaf.build({ ..bundle, plan: { ..base_plan, entries: [] } }) {
		Err(FontPlanInvalid) => Bool.True
		_ => Bool.False
	}
	sparse_plan = match KernelFontLeaf.Leaf.build({
		..bundle,
		plan: {
			..base_plan,
			entries: [
				{ cid: 0, content: Bool.False, left_side_bearing: 0, original_glyph: 0, subset_glyph: 0, width: 500 },
				{ cid: 2, content: Bool.True, left_side_bearing: 10, original_glyph: 2, subset_glyph: 2, width: 600 },
			],
		},
		mappings: [{ cid: 2, scalars: [0x41] }],
	}) {
		Err(FontPlanInvalid) => Bool.True
		_ => Bool.False
	}
	short_subset = match KernelFontLeaf.Leaf.build({
		..bundle,
		subset: {
			bytes: [9, 8, 7],
			work: { cmap_mappings: 1, component_rewrites: 0, entry_visits: 2, glyf_bytes: 0, hmtx_bytes: 8, loca_bytes: 8, output_bytes: 4, source_glyph_bytes: 0, tables: 14 },
		},
	}) {
		Err(SubsetLengthMismatch({ actual: 3, recorded: 4 })) => Bool.True
		_ => Bool.False
	}
	missing_mapping = match KernelFontLeaf.Leaf.build({ ..bundle, mappings: [] }) {
		Err(MissingUnicodeMapping({ cid: 1 })) => Bool.True
		_ => Bool.False
	}
	unexpected_mapping = match KernelFontLeaf.Leaf.build({ ..bundle, mappings: [{ cid: 0, scalars: [0x41] }, { cid: 1, scalars: [0x41] }] }) {
		Err(UnexpectedUnicodeMapping({ cid: 0 })) => Bool.True
		_ => Bool.False
	}
	trailing_mapping = match KernelFontLeaf.Leaf.build({ ..bundle, mappings: [{ cid: 1, scalars: [0x41] }, { cid: 5, scalars: [0x42] }] }) {
		Err(UnexpectedUnicodeMapping({ cid: 5 })) => Bool.True
		_ => Bool.False
	}
	empty_mapping = match KernelFontLeaf.Leaf.build({ ..bundle, mappings: [{ cid: 1, scalars: [] }] }) {
		Err(EmptyUnicodeMapping({ cid: 1 })) => Bool.True
		_ => Bool.False
	}
	surrogate = match KernelFontLeaf.Leaf.build({ ..bundle, mappings: [{ cid: 1, scalars: [0xd800] }] }) {
		Err(InvalidUnicodeScalar(0xd800)) => Bool.True
		_ => Bool.False
	}
	bad_descriptor and bad_units and bad_tag and lower_tag and bad_name and empty_plan and sparse_plan and short_subset and missing_mapping and unexpected_mapping and trailing_mapping and empty_mapping and surrogate
}
