import KernelFont

## This is deliberately a narrow inspection boundary. It does not shape text
## and it does not retain GSUB in a subset. It proves one declared Type-4
## ligature relationship against the selected script, language system, feature,
## and lookup before an advanced run can carry that relationship forward.
KernelGsub :: [].{
	Language : [Default, Tagged(U32)]
	Limits :: { max_feature_lookups : U64, max_ligature_components : U64, max_ligatures : U64, max_subtables : U64 }.{
		make : { max_feature_lookups : U64, max_ligature_components : U64, max_ligatures : U64, max_subtables : U64 } -> Limits
		make = |limits| Limits.(limits)
	}
	Request : { feature : U32, input : List(U32), language : Language, output : U32, script : U32 }
	Fact : { feature : U32, input : List(U32), language : Language, lookup : U16, output : U32, script : U32 }
	Work : { component_reads : U64, coverage_records : U64, feature_indices : U64, feature_records : U64, ligature_records : U64, lookup_records : U64, subtable_records : U64 }
	Validated : { fact : Fact, work : Work }
	Error : [
		FeatureMissing(U32),
		InputMissing,
		InvalidGsub,
		InvalidLigature,
		LanguageMissing(Language),
		LimitExceeded({ attempted : U64, limit : U64 }),
		LigatureMissing,
		OutputMismatch(U32),
		ScriptMissing(U32),
		UnsupportedGsubVersion(U32),
	]

	validate_ligature : KernelFont.Inspection, Request, Limits -> Try(Validated, Error)
	validate_ligature = |font, request, limits| validate(font, request, limits)
}

validate : KernelFont.Inspection, KernelGsub.Request, KernelGsub.Limits -> Try(KernelGsub.Validated, KernelGsub.Error)
validate = |font, request, limits| {
	if request.input.len() < 2 {
		return Err(InputMissing)
	}
	if request.output == 0 or request.output.to_u64() >= font.metrics.glyph_count or !glyphs_valid(request.input, font.metrics.glyph_count) {
		return Err(InvalidLigature)
	}
	table = gsub_table(font)?
	end = table_end(font.bytes, table)?
	if table.length < 10 {
		return Err(InvalidGsub)
	}
	version = read_u32(font.bytes, table.offset)
	if version != 0x00010000 {
		return Err(UnsupportedGsubVersion(version))
	}
	script_list = at(table.offset, end, read_u16(font.bytes, table.offset + 4).to_u64(), 2)?
	feature_list = at(table.offset, end, read_u16(font.bytes, table.offset + 6).to_u64(), 2)?
	lookup_list = at(table.offset, end, read_u16(font.bytes, table.offset + 8).to_u64(), 2)?
	language_system = select_language_system(font.bytes, script_list, end, request.script, request.language)?
	feature = select_feature(font.bytes, language_system, end, feature_list, request.feature)?
	lookups = feature_lookups(font.bytes, feature, end, lookup_list, limits.max_feature_lookups)?
	matched = scan_lookups(font.bytes, end, lookup_list, lookups.indices, request, limits)?
	match matched.fact {
		Some(fact) => Ok({
			fact,
			work: {
				component_reads: matched.component_reads,
				coverage_records: matched.coverage_records,
				feature_indices: lookups.indices.len(),
				feature_records: feature.records,
				ligature_records: matched.ligature_records,
				lookup_records: lookups.indices.len(),
				subtable_records: matched.subtable_records,
			},
		})
		None => if matched.output_seen Err(OutputMismatch(request.output)) else Err(LigatureMissing)
	}
}

gsub_table : KernelFont.Inspection -> Try(KernelFont.Table, KernelGsub.Error)
gsub_table = |font| {
	var $index = 0
	while $index < font.tables.len() {
		table = list_at(font.tables, $index)
		if table.tag == tag_gsub {
			return Ok(table)
		}
		$index = $index + 1
	}
	Err(InvalidGsub)
}

table_end : List(U8), KernelFont.Table -> Try(U64, KernelGsub.Error)
table_end = |bytes, table| {
	if table.offset > bytes.len() or table.length > bytes.len() - table.offset {
		Err(InvalidGsub)
	} else {
		Ok(table.offset + table.length)
	}
}

select_language_system : List(U8), U64, U64, U32, KernelGsub.Language -> Try(U64, KernelGsub.Error)
select_language_system = |bytes, script_list, end, wanted_script, language| {
	script_count = count_at(bytes, script_list, end)?
	var $index = 0
	var $script = NoScript
	while $index < script_count and $script == NoScript {
		record = checked_offset(script_list, 2 + $index * 6, end, 6)?
		if read_u32(bytes, record) == wanted_script {
			$script = FoundScript(at(script_list, end, read_u16(bytes, record + 4).to_u64(), 4)?)
		}
		$index = $index + 1
	}
	match $script {
		NoScript => Err(ScriptMissing(wanted_script))
		FoundScript(offset) => {
			default_offset = read_u16(bytes, offset).to_u64()
			language_count = read_u16_checked(bytes, offset + 2, end, 2)?
			match language {
				Default => if default_offset == 0 Err(LanguageMissing(language)) else at(offset, end, default_offset, 6)
				Tagged(wanted) => select_tagged_language(bytes, offset, end, language_count, wanted, language)
			}
		}
	}
}

select_tagged_language : List(U8), U64, U64, U16, U32, KernelGsub.Language -> Try(U64, KernelGsub.Error)
select_tagged_language = |bytes, script, end, count, wanted, language| {
	var $index = 0
	while $index < count.to_u64() {
		record = checked_offset(script, 4 + $index * 6, end, 6)?
		if read_u32(bytes, record) == wanted {
			return at(script, end, read_u16(bytes, record + 4).to_u64(), 6)
		}
		$index = $index + 1
	}
	Err(LanguageMissing(language))
}

select_feature : List(U8), U64, U64, U64, U32 -> Try({ offset : U64, records : U64 }, KernelGsub.Error)
select_feature = |bytes, language_system, end, feature_list, wanted| {
	if read_u16_checked(bytes, language_system, end, 2)? != 0 {
		return Err(InvalidGsub)
	}
	feature_index_count = read_u16_checked(bytes, language_system + 4, end, 2)?.to_u64()
	_ = checked_offset(language_system, 6, end, feature_index_count * 2)?
	feature_count = count_at(bytes, feature_list, end)?
	required_index = read_u16_checked(bytes, language_system + 2, end, 2)?.to_u64()
	var $index = 0
	var $found = NoFeature
	if required_index != 0xffff {
		if required_index >= feature_count {
			return Err(InvalidGsub)
		}
		record = checked_offset(feature_list, 2 + required_index * 6, end, 6)?
		if read_u32(bytes, record) == wanted {
			$found = FoundFeature(at(feature_list, end, read_u16(bytes, record + 4).to_u64(), 4)?)
		}
	}
	while $index < feature_index_count {
		feature_index = read_u16_checked(bytes, language_system + 6 + $index * 2, end, 2)?.to_u64()
		if feature_index >= feature_count {
			return Err(InvalidGsub)
		}
		record = checked_offset(feature_list, 2 + feature_index * 6, end, 6)?
		if read_u32(bytes, record) == wanted {
			if $found != NoFeature {
				return Err(InvalidGsub)
			}
			$found = FoundFeature(at(feature_list, end, read_u16(bytes, record + 4).to_u64(), 4)?)
		}
		$index = $index + 1
	}
	match $found {
		NoFeature => Err(FeatureMissing(wanted))
		FoundFeature(offset) => Ok({ offset, records: feature_index_count + if required_index == 0xffff 0 else 1 })
	}
}

feature_lookups : List(U8), { offset : U64, records : U64 }, U64, U64, U64 -> Try({ indices : List(U16) }, KernelGsub.Error)
feature_lookups = |bytes, feature, end, lookup_list, limit| {
	if read_u16_checked(bytes, feature.offset, end, 2)? != 0 {
		return Err(InvalidGsub)
	}
	count = read_u16_checked(bytes, feature.offset + 2, end, 2)?.to_u64()
	if count > limit {
		return Err(LimitExceeded({ attempted: count, limit }))
	}
	_ = checked_offset(feature.offset, 4, end, count * 2)?
	lookup_count = count_at(bytes, lookup_list, end)?
	var $indices = List.with_capacity(count)
	var $index = 0
	while $index < count {
		lookup = read_u16_checked(bytes, feature.offset + 4 + $index * 2, end, 2)?
		if lookup.to_u64() >= lookup_count {
			return Err(InvalidGsub)
		}
		$indices = $indices.append(lookup)
		$index = $index + 1
	}
	Ok({ indices: $indices })
}

scan_lookups : List(U8), U64, U64, List(U16), KernelGsub.Request, KernelGsub.Limits -> Try({ component_reads : U64, coverage_records : U64, fact : [None, Some(KernelGsub.Fact)], ligature_records : U64, output_seen : Bool, subtable_records : U64 }, KernelGsub.Error)
scan_lookups = |bytes, end, lookup_list, lookups, request, limits| {
	lookup_count = count_at(bytes, lookup_list, end)?
	var $lookup_index = 0
	var $subtables = 0
	var $ligatures = 0
	var $coverage = 0
	var $components = 0
	var $output_seen = False
	var $fact = None
	while $lookup_index < lookups.len() and $fact == None {
		lookup_id = list_at(lookups, $lookup_index)
		if lookup_id.to_u64() >= lookup_count {
			return Err(InvalidGsub)
		}
		lookup = at(lookup_list, end, read_u16_checked(bytes, lookup_list + 2 + lookup_id.to_u64() * 2, end, 2)?.to_u64(), 6)?
		subtable_count = read_u16_checked(bytes, lookup + 4, end, 2)?.to_u64()
		if $subtables + subtable_count > limits.max_subtables {
			return Err(LimitExceeded({ attempted: $subtables + subtable_count, limit: limits.max_subtables }))
		}
		_ = checked_offset(lookup, 6, end, subtable_count * 2)?
		var $subtable_index = 0
		while $subtable_index < subtable_count and $fact == None {
			$subtables = $subtables + 1
			subtable = at(lookup, end, read_u16(bytes, lookup + 6 + $subtable_index * 2).to_u64(), 2)?
			resolved = resolve_ligature_subtable(bytes, subtable, end, read_u16(bytes, lookup))?
			match resolved {
				NoLigatureSubtable => {}
				LigatureSubtable(offset) => {
					result = scan_ligature_subtable(bytes, offset, end, request, lookup_id, limits, $ligatures, $coverage, $components)?
					$ligatures = result.ligature_records
					$coverage = result.coverage_records
					$components = result.component_reads
					$output_seen = $output_seen or result.output_seen
					$fact = result.fact
				}
			}
			$subtable_index = $subtable_index + 1
		}
		$lookup_index = $lookup_index + 1
	}
	Ok({ component_reads: $components, coverage_records: $coverage, fact: $fact, ligature_records: $ligatures, output_seen: $output_seen, subtable_records: $subtables })
}

resolve_ligature_subtable : List(U8), U64, U64, U16 -> Try([NoLigatureSubtable, LigatureSubtable(U64)], KernelGsub.Error)
resolve_ligature_subtable = |bytes, subtable, end, lookup_type| {
	if lookup_type == 4 {
		Ok(LigatureSubtable(subtable))
	} else if lookup_type == 7 {
		if read_u16_checked(bytes, subtable, end, 8)? != 1 or read_u16(bytes, subtable + 2) != 4 {
			Err(InvalidGsub)
		} else {
			Ok(LigatureSubtable(at(subtable, end, read_u32(bytes, subtable + 4).to_u64(), 2)?))
		}
	} else {
		Ok(NoLigatureSubtable)
	}
}

scan_ligature_subtable : List(U8), U64, U64, KernelGsub.Request, U16, KernelGsub.Limits, U64, U64, U64 -> Try({ component_reads : U64, coverage_records : U64, fact : [None, Some(KernelGsub.Fact)], ligature_records : U64, output_seen : Bool }, KernelGsub.Error)
scan_ligature_subtable = |bytes, subtable, end, request, lookup, limits, prior_ligatures, prior_coverage, prior_components| {
	if read_u16_checked(bytes, subtable, end, 6)? != 1 {
		return Err(InvalidGsub)
	}
	coverage = at(subtable, end, read_u16(bytes, subtable + 2).to_u64(), 4)?
	set_count = read_u16(bytes, subtable + 4).to_u64()
	_ = checked_offset(subtable, 6, end, set_count * 2)?
	coverage_index = coverage_index_for(bytes, coverage, end, request.input, prior_coverage)?
	match coverage_index {
		NoCoverage(result) => Ok({ component_reads: prior_components, coverage_records: result, fact: None, ligature_records: prior_ligatures, output_seen: False })
		Coverage(index, coverage_records, coverage_count) => {
			if index >= set_count or coverage_count != set_count {
				return Err(InvalidGsub)
			}
			set = at(subtable, end, read_u16(bytes, subtable + 6 + index * 2).to_u64(), 2)?
			count = read_u16_checked(bytes, set, end, 2)?.to_u64()
			if prior_ligatures + count > limits.max_ligatures {
				return Err(LimitExceeded({ attempted: prior_ligatures + count, limit: limits.max_ligatures }))
			}
			_ = checked_offset(set, 2, end, count * 2)?
			var $ligature_index = 0
			var $fact = None
			var $output_seen = False
			var $components = prior_components
			while $ligature_index < count and $fact == None {
				ligature = at(set, end, read_u16(bytes, set + 2 + $ligature_index * 2).to_u64(), 4)?
				output = read_u16(bytes, ligature).to_u32()
				component_count = read_u16(bytes, ligature + 2).to_u64()
				if component_count < 2 or component_count > limits.max_ligature_components {
					return Err(InvalidLigature)
				}
				_ = checked_offset(ligature, 4, end, (component_count - 1) * 2)?
				$components = $components + component_count - 1
				if ligature_input_matches(bytes, ligature, component_count, request.input) {
					$output_seen = True
					if output == request.output {
						$fact = Some({ feature: request.feature, input: request.input, language: request.language, lookup, output: request.output, script: request.script })
					}
				}
				$ligature_index = $ligature_index + 1
			}
			Ok({ component_reads: $components, coverage_records, fact: $fact, ligature_records: prior_ligatures + count, output_seen: $output_seen })
		}
	}
}

coverage_index_for : List(U8), U64, U64, List(U32), U64 -> Try([NoCoverage(U64), Coverage(U64, U64, U64)], KernelGsub.Error)
coverage_index_for = |bytes, coverage, end, input, prior| {
	format = read_u16_checked(bytes, coverage, end, 4)?
	first = list_at(input, 0)
	if format == 1 {
		count = read_u16(bytes, coverage + 2).to_u64()
		_ = checked_offset(coverage, 4, end, count * 2)?
		var $index = 0
		while $index < count {
			if read_u16(bytes, coverage + 4 + $index * 2).to_u32() == first {
				return Ok(Coverage($index, prior + count, count))
			}
			$index = $index + 1
		}
		Ok(NoCoverage(prior + count))
	} else if format == 2 {
		count = read_u16(bytes, coverage + 2).to_u64()
		_ = checked_offset(coverage, 4, end, count * 6)?
		var $index = 0
		while $index < count {
			record = coverage + 4 + $index * 6
			start = read_u16(bytes, record).to_u32()
			finish = read_u16(bytes, record + 2).to_u32()
			coverage_index = read_u16(bytes, record + 4).to_u64()
			if start > finish {
				return Err(InvalidGsub)
			}
			if first >= start and first <= finish {
				return Ok(Coverage(coverage_index + first.to_u64() - start.to_u64(), prior + count, count))
			}
			$index = $index + 1
		}
		Ok(NoCoverage(prior + count))
	} else {
		Err(InvalidGsub)
	}
}

ligature_input_matches : List(U8), U64, U64, List(U32) -> Bool
ligature_input_matches = |bytes, ligature, component_count, input| {
	if component_count != input.len() or read_u16(bytes, ligature).to_u32() == 0 {
		return False
	}
	var $index = 1
	while $index < component_count {
		if read_u16(bytes, ligature + 4 + ($index - 1) * 2).to_u32() != list_at(input, $index) {
			return False
		}
		$index = $index + 1
	}
	True
}

glyphs_valid : List(U32), U64 -> Bool
glyphs_valid = |glyphs, count| {
	var $index = 0
	while $index < glyphs.len() {
		glyph = list_at(glyphs, $index)
		if glyph == 0 or glyph.to_u64() >= count {
			return False
		}
		$index = $index + 1
	}
	True
}

count_at : List(U8), U64, U64 -> Try(U64, KernelGsub.Error)
count_at = |bytes, offset, end| {
	value = read_u16_checked(bytes, offset, end, 2)?
	Ok(value.to_u64())
}

at : U64, U64, U64, U64 -> Try(U64, KernelGsub.Error)
at = |base, end, relative, needed| checked_offset(base, relative, end, needed)

checked_offset : U64, U64, U64, U64 -> Try(U64, KernelGsub.Error)
checked_offset = |base, relative, end, needed| {
	if base > end or relative > end - base {
		Err(InvalidGsub)
	} else {
		offset = base + relative
		if needed > end - offset Err(InvalidGsub) else Ok(offset)
	}
}

read_u16_checked : List(U8), U64, U64, U64 -> Try(U16, KernelGsub.Error)
read_u16_checked = |bytes, offset, end, needed| {
	_ = checked_offset(offset, 0, end, needed)?
	Ok(read_u16(bytes, offset))
}

read_u16 : List(U8), U64 -> U16
read_u16 = |bytes, offset| list_at(bytes, offset).to_u16() * 256 + list_at(bytes, offset + 1).to_u16()

read_u32 : List(U8), U64 -> U32
read_u32 = |bytes, offset| list_at(bytes, offset).to_u32() * 16777216 + list_at(bytes, offset + 1).to_u32() * 65536 + list_at(bytes, offset + 2).to_u32() * 256 + list_at(bytes, offset + 3).to_u32()

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "validated GSUB index escaped"
}

tag_gsub : U32
tag_gsub = 0x47535542
