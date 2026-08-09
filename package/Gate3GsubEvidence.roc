import KernelFont
import KernelGsub
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

## This module is inspection-only. It deliberately emits no PDF: the retained
## `Fact` is the upstream proof required before a later output slice can create
## a ligature cluster or a CID mapping.
Gate3GsubEvidence :: [].{
	validation_work : {} -> Try(List(U64), EvidenceFailure)
	validation_work = |_| validated_work({})
}

EvidenceFailure : [EvidenceFailure]

validated_work : {} -> Try(List(U64), EvidenceFailure)
validated_work = |_| {
	font = fixture_font({})?
	request = fixture_request(font)?
	validated = match KernelGsub.validate_ligature(font, request, limits({})) {
		Ok(value) => value
		Err(FeatureMissing(_)) => return Err(EvidenceFailure)
		Err(InputMissing) => return Err(EvidenceFailure)
		Err(InvalidGsub) => return Err(EvidenceFailure)
		Err(InvalidLigature) => return Err(EvidenceFailure)
		Err(LanguageMissing(_)) => return Err(EvidenceFailure)
		Err(LimitExceeded(_)) => return Err(EvidenceFailure)
		Err(LigatureMissing) => return Err(EvidenceFailure)
		Err(OutputMismatch(_)) => return Err(EvidenceFailure)
		Err(ScriptMissing(_)) => return Err(EvidenceFailure)
		Err(UnsupportedGsubVersion(_)) => return Err(EvidenceFailure)
	}
	Ok([
		validated.fact.lookup.to_u64(),
		validated.work.feature_indices,
		validated.work.feature_records,
		validated.work.lookup_records,
		validated.work.subtable_records,
		validated.work.coverage_records,
		validated.work.ligature_records,
		validated.work.component_reads,
	])
}

fixture_font : {} -> Try(KernelFont.Inspection, EvidenceFailure)
fixture_font = |_| {
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	) ? |_| EvidenceFailure
	Ok(font)
}

fixture_request : KernelFont.Inspection -> Try(KernelGsub.Request, EvidenceFailure)
fixture_request = |font| {
	base = required_glyph(font, 0x0041)?
	combining_grave = required_glyph(font, 0x0300)?
	Ok({
		feature: 0x63636d70,
		input: [base, combining_grave],
		language: Default,
		output: 5,
		script: 0x6c61746e,
	})
}

required_glyph : KernelFont.Inspection, U32 -> Try(U32, EvidenceFailure)
required_glyph = |font, scalar| match KernelFont.glyph_for_scalar(font, scalar) {
	None => Err(EvidenceFailure)
	Some(glyph) => Ok(glyph)
}

limits : {} -> KernelGsub.Limits
limits = |_| KernelGsub.Limits.make({ max_feature_lookups: 8, max_ligature_components: 8, max_ligatures: 128, max_subtables: 16 })

find_gsub : List(KernelFont.Table) -> Try(KernelFont.Table, EvidenceFailure)
find_gsub = |tables| {
	var $index = 0
	while $index < tables.len() {
		table = list_at(tables, $index)
		if table.tag == 0x47535542 {
			return Ok(table)
		}
		$index = $index + 1
	}
	Err(EvidenceFailure)
}

set_byte : List(U8), U64, U8 -> List(U8)
set_byte = |bytes, index, value| match bytes.set(index, value) {
	Err(OutOfBounds) => crash "validated Gate 3 GSUB fixture offset escaped"
	Ok(updated) => updated
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "validated Gate 3 GSUB fixture index escaped"
	Ok(value) => value
}

## The selected Latin default language system exposes `ccmp`, whose Type-4
## lookup 4 proves the exact A + grave -> glyph 5 relationship. This validates
## the prerequisite without pretending that this font has an `fi` `liga` rule.
expect {
	work = Gate3GsubEvidence.validation_work({})?
	work == [4, 2, 37, 2, 2, 61, 23, 19]
}

## The returned value is the durable stage fact. It records all selection
## inputs, rather than leaving a later advanced-run stage to rediscover them.
expect {
	font = fixture_font({})?
	request = fixture_request(font)?
	validated = KernelGsub.validate_ligature(font, request, limits({}))?
	validated.fact == {
		feature: 0x63636d70,
		input: [2, 873],
		language: Default,
		lookup: 4,
		output: 5,
		script: 0x6c61746e,
	}
}

## An otherwise valid lookup whose declared output glyph is wrong is rejected
## before any advanced run, scene, or object plan can exist.
expect {
	font = fixture_font({})?
	request = fixture_request(font)?
	match KernelGsub.validate_ligature(font, { ..request, output: 6 }, limits({})) {
		Err(OutputMismatch(6)) => True
		_ => False
	}
}

## A corrupt GSUB header is rejected at this boundary, independently of the
## earlier sfnt-directory inspection. No malformed lookup becomes a shaping
## fact merely because the outer font was once inspected successfully.
expect {
	font = fixture_font({})?
	table = find_gsub(font.tables)?
	bad = { ..font, bytes: set_byte(font.bytes, table.offset, 1) }
	request = fixture_request(font)?
	match KernelGsub.validate_ligature(bad, request, limits({})) {
		Err(UnsupportedGsubVersion(_)) => True
		_ => False
	}
}
