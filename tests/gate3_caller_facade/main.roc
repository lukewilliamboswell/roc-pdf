app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Font
import pdf.Pdf
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/CallerFont-Restricted.ttf" as restricted_font_bytes : List(U8)

## This unregistered focused fixture is deliberately kept outside spec.json
## until its dev-backend allocation baseline is reviewed with the pending
## Gate 3 rebaseline. It exercises the public facade rather than a private
## evidence module.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	match mode {
		"positive" => positive(args.len())
		"restricted" => restricted(args.len())
		_ => crash "Gate 3 caller facade mode is invalid"
	}
}

positive : U64 -> { bytes : List(U8), work : List(U64) }
positive = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "Gate 3 caller facade argument count is invalid"
	}
	registered = match Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "caller fixture registration failed"
		Ok(value) => value
	}
	theme = Theme.with_font(Theme.default, registered.face)
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), registered.registry)
	document = Pdf.document({
		contents: [
			Pdf.paragraph("Café PDF"),
			Pdf.paragraph("Café PDF"),
			Pdf.paragraph("Café PDF"),
		],
		language: "en-AU",
		title: "Caller facade",
	})
	bytes = match Pdf.to_bytes_with(document, options) {
		Err(_) => crash "caller facade output failed"
		Ok(value) => value
	}
	store = registered.registry.store()
	{
		bytes,
		work: [
			registered.work.input_bytes,
			registered.work.retained_input_bytes,
			registered.work.copied_input_bytes,
			registered.work.table_visits,
			registered.work.glyph_visits,
			registered.work.cmap_mapping_visits,
			registered.work.component_edge_visits,
			store.resources.len(),
			store.faces.len(),
			store.instances.len(),
			store.policies.len(),
			document.block_count(),
		],
	}
}

## Invalid caller bytes never yield a registry handle. Since the only facade
## entry point that can receive caller resources takes a Registry, this error
## is atomic: no document plan or PDF byte list exists on this branch.
restricted : U64 -> { bytes : List(U8), work : List(U64) }
restricted = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "Gate 3 caller facade argument count is invalid"
	}
	match Font.Registry.empty.register(
		restricted_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(EmbeddingRightsProhibited(_)) => { bytes: [], work: [1, 0] }
		_ => crash "restricted caller font was accepted"
	}
}

## The fixture validates its runtime guard before deriving these limits. The
## alternate branch remains a real error policy rather than a compiler-known
## assertion about imported fixture bytes.
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
	Err(OutOfBounds) => crash "Gate 3 caller facade argument missing"
}
