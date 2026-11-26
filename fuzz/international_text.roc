app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import pdf.Font
import pdf.KernelBidiBoundary
import pdf.KernelInternationalBatch
import pdf.KernelInternationalLine
import pdf.KernelInternationalSelection
import pdf.KernelInternationalText
import pdf.KernelLineLayout
import pdf.KernelUnicode
import pdf.Layout
import pdf.Semantics
import "../examples/bilingual-invoice/fonts/IBMPlexSansHebrew-Regular.ttf" as hebrew : List(U8)
import "../examples/arabic-invoice/fonts/IBMPlexSansArabic-Regular.ttf" as arabic : List(U8)
import "../examples/hindi-statement/fonts/IBMPlexSansDevanagari-Regular.ttf" as hindi : List(U8)
import "../examples/thai-notice/fonts/IBMPlexSansThaiLooped-Regular.ttf" as thai : List(U8)

Input := { sample : U8, width : U8, repeats : U8, styled : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { sample: Fuzz.u8, width: Fuzz.u8, repeats: Fuzz.u8, styled: Fuzz.u8 }.Fuzz
}

target = Fuzz.suite([
	Fuzz.target({
		name: "roc-pdf-international-text",
		examples: [
			Fuzz.example({ name: "hebrew-bidi-address", revision: "1", make: || Input.{ sample: 0, width: 0, repeats: 3, styled: 1 } }),
			Fuzz.example({ name: "arabic-joined-word", revision: "1", make: || Input.{ sample: 1, width: 2, repeats: 2, styled: 0 } }),
			Fuzz.example({ name: "hindi-grapheme", revision: "1", make: || Input.{ sample: 2, width: 3, repeats: 3, styled: 1 } }),
			Fuzz.example({ name: "thai-unspaced-wrap", revision: "1", make: || Input.{ sample: 3, width: 0, repeats: 3, styled: 1 } }),
			Fuzz.example({ name: "bidi-control", revision: "1", make: || Input.{ sample: 4, width: 1, repeats: 1, styled: 1 } }),
			Fuzz.example({ name: "missing-complete-coverage", revision: "1", make: || Input.{ sample: 5, width: 3, repeats: 1, styled: 0 } }),
			Fuzz.example({ name: "unsupported-grapheme", revision: "1", make: || Input.{ sample: 6, width: 2, repeats: 1, styled: 1 } }),
			Fuzz.example({ name: "unsupported-script", revision: "1", make: || Input.{ sample: 7, width: 4, repeats: 1, styled: 0 } }),
		],
		test,
		show: Str.inspect,
	}),
])

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	sample = input.sample % 8
	(word, language) = match sample {
		0 if input.width == 0 => ("A אב  12", "he")
		0 => ("אב רחוב 24 תל אביב  (PO-1042)", "he")
		1 => ("شركة السلام AE-118", "ar")
		2 => ("वित्तीय विवरण IN-42", "hi")
		3 => ("กรุณาชำระเงินภายในวันนี้", "th")
		4 => ("אב\u(2067)24", "he")
		5 => ("שלום", "he")
		6 => ("שָ", "he")
		_ => ("Aم", "en")
	}
	policy = require(make_policy(sample))
	text = Str.join_with(List.repeat(word, (input.repeats % 4).to_u64() + 1), " ")
	suffix = " X-42"
	source = "${text}${suffix}"
	initial = require(KernelUnicode.analyze(source, KernelUnicode.default_limits))
	analysis = if sample == 3 {
		dictionary = require(KernelUnicode.thai_dictionary({ revision: "notice-v1", words: ["กรุณา", "ชำระ", "เงิน", "ภายใน", "วันนี้"] }))
		require(KernelUnicode.tailor_thai(source, initial, dictionary))
	} else {
		initial
	}
	sources = [{ analysis, unicode: source }]
	scalars = analysis.work.scalar_visits
	bytes = source.count_utf8_bytes()
	requests = if input.styled % 2 == 1 {
		[request(0, language, span(0, scalars - 5), span(0, bytes - 5)), request(1, "en", span(scalars - 5, 5), span(bytes - 5, 5))]
	} else {
		[request(0, language, span(0, scalars), span(0, bytes))]
	}
	result = KernelInternationalBatch.build(sources, requests, policy, { max_clusters: 256, max_scalars: 256, max_source_bytes: 1024, max_requests: 256, max_glyphs: 384 })
	width = Layout.Unit.points(if (sample == 0 and input.width == 0) 28 else 78 + (input.width % 41).to_i64())
	accepted = match (sample, result) {
		(4, Err(Paragraph({ cause: UnsupportedControl(_), request: 0 }))) => True
		(5, Err(Coverage({ cause: NoCoverage(_), request: 0 }))) => True
		(6, Err(Paragraph({ cause: UnsupportedCluster(_), request: 0 }))) => True
		(7, Err(Paragraph({ cause: UnsupportedScript(_), request: 0 }))) => True
		(index, Ok(value)) if index < 4 => match positioned(sources, value, width) {
			Ok(valid) => valid
			Err(error) => crash "international positioning case ${sample.to_str()} failed: ${Str.inspect(error)}"
		}
		_ => False
	}
	if accepted {
		Fuzz.keep
	} else {
		crash "international text oracle disagreed for case ${sample.to_str()}"
	}
}

make_policy : U8 -> Try(KernelInternationalSelection.Policy, [Setup])
make_policy = |sample| {
	latin = Font.Registry.register_built_in(Font.Registry.empty, Font.ValidationLimits.default) ? |_| Setup
	if sample == 5 {
		policy = KernelInternationalSelection.for_repertoire(latin.registry, latin.policy, UnpointedHebrewLatin) ? |_| Setup
		return Ok(policy)
	}
	(script, font, repertoire) = match sample {
		1 => ("Arab", arabic, UnpointedArabicLatin)
		2 => ("Deva", hindi, ModernHindiLatin)
		3 => ("Thai", thai, ThaiWithLatin)
		_ => ("Hebr", hebrew, UnpointedHebrewLatin)
	}
	registered = latin.registry.register({ bytes: font, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924(script)] }, limits: Font.ValidationLimits.default }) ? |_| Setup
	selection = registered.registry.with_policy([latin.face, registered.face]) ? |_| Setup
	policy = KernelInternationalSelection.for_repertoire(selection.registry, selection.policy, repertoire) ? |_| Setup
	Ok(policy)
}

positioned : List({ analysis : KernelUnicode.UnicodeAnalysis, unicode : Str }), KernelInternationalBatch.Plan, Layout.Unit -> Try(Bool, [InvalidParagraph, Line(KernelLineLayout.Error), Position(KernelInternationalLine.Error)])
positioned = |sources, batch, width| {
	store = batch.batch.store
	line_limits = KernelLineLayout.Limits.make({ max_boundaries: 257, max_candidates: 1024, max_clusters: 256, max_glyph_indices: 384, max_glyphs: 384, max_lines: 256 })
	limits = KernelLineLayout.BatchLimits.make({ line: line_limits, max_key_probes: 0, max_lines: 256, max_runs: 256, max_table_slots: 0, max_templates: 1 })
	source = Semantics.TextSourceId.from_index(0)
	layout = KernelLineLayout.BatchPlan.build_international(sources, store, [{ source, width, runs: span(0, store.runs.len()) }], [], limits) ? Line
	bidi = match require(batch.paragraphs.get(0)) {
		Analyzed(paragraph) => paragraph
		Unseen => return Err(InvalidParagraph)
	}
	analysis = require(sources.get(0)).analysis
	owners = KernelInternationalLine.cluster_owners(store) ? Position
	bidi_limits = KernelBidiBoundary.Limits.make({ max_clusters: 256, max_scalars: 256, max_visual_order: 256 })
	var $next_cluster = 0
	var $scalar = 0
	for line in KernelLineLayout.BatchPlan.lines(layout) {
		if line.clusters.start() != $next_cluster or line.source.scalars.start() != $scalar or line.advance > width {
			return Ok(False)
		}
		view = KernelInternationalLine.position(bidi, store, owners, line, bidi_limits) ? Position
		for piece in view.pieces {
			if piece.clusters.start() != $next_cluster or piece.origin < 0 or piece.origin > width {
				return Ok(False)
			}
			$next_cluster = $next_cluster + piece.clusters.length()
		}
		$scalar = $scalar + line.source.scalars.length()
		if $next_cluster != line.clusters.start() + line.clusters.length() or require(analysis.line_boundaries.get($scalar)).decision == Prohibited {
			return Ok(False)
		}
	}
	Ok($next_cluster == store.clusters.len() and $scalar == analysis.work.scalar_visits)
}

request : U64, Str, Semantics.IndexRange, Semantics.IndexRange -> KernelInternationalBatch.Request
request = |id, language, scalars, utf8_bytes| {
	occurrence = Semantics.OccurrenceId.from_index(id)
	{
		authored: { id: occurrence, language: Language(language), source: { scalars, utf8_bytes } },
		segment: 0,
		shape: { occurrence, size: 11, source: Semantics.TextSourceId.from_index(0) },
	}
}

span : U64, U64 -> Semantics.IndexRange
span = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

require : Try(a, e) -> a
require = |result| match result {
	Ok(value) => value
	Err(error) => crash "international target could not construct its fixture: ${Str.inspect(error)}"
}
