app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Font
import pdf.Document
import pdf.Pdf
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)

## Ordered multi-face facade negatives. Every mode is a stable typed
## selection error that emits zero PDF bytes; the zero-byte output is the
## transactional result, not a blank fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	match mode {
		"missing-coverage" => rejected(args.len(), "z", MissingCoverageExpected)
		"undeclared-script" => rejected(args.len(), "α", UndeclaredScriptExpected)
		"unknown-policy" => unknown_policy(args.len())
		"builtin-policy" => builtin_policy(args.len())
		_ => crash "text-layout multiface facade negative mode is invalid"
	}
}

Registered := {
	cjk : { face : Font.FaceId, work : Font.RegistrationWork },
	latin : { face : Font.FaceId, work : Font.RegistrationWork },
	policy : Font.PolicyId,
	registry : Font.Registry,
}

register_faces : U64 -> Registered
register_faces = |runtime_argument_count| {
	latin = match Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "multiface negative Latin registration failed"
		Ok(value) => value
	}
	cjk = match latin.registry.register(
		cjk_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "multiface negative Han registration failed"
		Ok(value) => value
	}
	configured = match cjk.registry.with_policy([latin.face, cjk.face]) {
		Err(_) => crash "multiface negative policy construction failed"
		Ok(value) => value
	}
	{
		cjk: { face: cjk.face, work: cjk.work },
		latin: { face: latin.face, work: latin.work },
		policy: configured.policy,
		registry: configured.registry,
	}
}

mixed_document : {} -> Document
mixed_document = |_| Pdf.document({
	contents: [Pdf.paragraph("C中é")],
	language: "en-AU",
	title: "Multiface facade",
})

ExpectedRejection := [MissingCoverageExpected, UndeclaredScriptExpected]

## A stable typed selection error carries no PDF bytes: the zero-byte output
## is the transactional negative result, not a blank fallback.
rejected : U64, Str, ExpectedRejection -> { bytes : List(U8), work : List(U64) }
rejected = |runtime_argument_count, text, expected| {
	if runtime_argument_count != 2 {
		crash "text-layout multiface facade negative argument count is invalid"
	}
	registered = register_faces(runtime_argument_count)
	theme = Theme.with_font_policy(Theme.default, registered.policy)
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), registered.registry)
	document = Pdf.document({
		contents: [Pdf.paragraph(text)],
		language: "en-AU",
		title: "Multiface rejection",
	})
	matched = match (expected, Pdf.to_bytes_with(document, options)) {
		(MissingCoverageExpected, Err(InvalidFontSelection([MissingCoverage(_)]))) => 1
		(UndeclaredScriptExpected, Err(InvalidFontSelection([UnsupportedBuiltInShaping(_)]))) => 1
		_ => 0
	}
	if matched != 1 {
		crash "multiface facade rejection was not the stable typed error"
	}
	{ bytes: [], work: [1, 0] }
}

unknown_policy : U64 -> { bytes : List(U8), work : List(U64) }
unknown_policy = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout multiface facade negative argument count is invalid"
	}
	registered = register_faces(runtime_argument_count)
	theme = Theme.with_font_policy(Theme.default, Font.PolicyId.from_index(99))
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), registered.registry)
	matched = match Pdf.to_bytes_with(mixed_document({}), options) {
		Err(InvalidFontSelection([InvalidPolicy(policy)])) => if policy.index() == 99 1 else 0
		_ => 0
	}
	if matched != 1 {
		crash "multiface facade unknown policy was not the stable typed error"
	}
	{ bytes: [], work: [1, 0] }
}

## A policy selection without the caller registry that constructed it is a
## stable error: the packaged built-in face defines no policies.
builtin_policy : U64 -> { bytes : List(U8), work : List(U64) }
builtin_policy = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout multiface facade negative argument count is invalid"
	}

	## The policy index is derived from the validated runtime argument count,
	## so this is a real runtime request rather than a constant the compiler
	## could fold away.
	theme = Theme.with_font_policy(Theme.default, Font.PolicyId.from_index(runtime_argument_count - 2))
	options = Pdf.Options.with_theme(Pdf.Options.default, theme)
	matched = match Pdf.to_bytes_with(mixed_document({}), options) {
		Err(InvalidFontSelection([InvalidPolicy(policy)])) => if policy.index() == 0 1 else 0
		_ => 0
	}
	if matched != 1 {
		crash "multiface facade builtin policy was not the stable typed error"
	}
	{ bytes: [], work: [1, 0] }
}

facade_limits : U64 -> Font.ValidationLimits
facade_limits = |runtime_argument_count| {
	if runtime_argument_count == 2 {
		Font.ValidationLimits.default
	} else {
		Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "text-layout multiface facade negative argument missing"
}
