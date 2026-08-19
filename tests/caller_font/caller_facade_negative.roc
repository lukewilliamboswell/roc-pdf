app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Font
import "../assets/CallerFont-Restricted.ttf" as restricted_font_bytes : List(U8)

## Registration is the only public boundary through which caller font bytes can
## reach Pdf.Options. Restricted bytes fail there, before a registry, theme,
## document plan, or fallback PDF can exist.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| restricted(args.len())

restricted : U64 -> { bytes : List(U8), work : List(U64) }
restricted = |runtime_argument_count| {
	if runtime_argument_count != 1 {
		crash "text-layout caller facade negative argument count is invalid"
	}
	match Font.Registry.empty.register(
		restricted_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		limits(runtime_argument_count),
	) {
		Err(EmbeddingRightsProhibited(_)) => { bytes: [], work: [1, 0] }
		_ => crash "restricted caller font was accepted"
	}
}

limits : U64 -> Font.ValidationLimits
limits = |runtime_argument_count| {
	if runtime_argument_count == 1 {
		Font.ValidationLimits.default
	} else {
		Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	}
}
