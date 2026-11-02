import pdf.Color
import pdf.Layout
import pdf.Scene
import pdf.Conformance
import pdf.Document
import pdf.Font
import pdf.KernelFacadeFonts
import pdf.Pdf
import pdf.RocFont
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_bytes : List(U8)

## Bytes come from the public facade. A separate resolver pass over the same
## authoring supplies actual font-work counters; it never supplies PDF oracle
## expectations. The 10/100 pair scales inline leaves and source blocks while
## the packaged inspections remain bounded by the finite demanded face set.
Fixture :: [].{
	Error : [Evidence(Str), Font(Font.ResourceError), Pdf(Pdf.Error), Resolution(KernelFacadeFonts.Error)]

	family : Font.Family, U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	family = |kind, context| {
		if context != 0 {
			return Err(Evidence("invalid family case"))
		}
		theme = match kind {
			Sans => Theme.default
			Serif => Theme.{ family: BuiltIn(Serif) }
			Mono => Theme.{ family: BuiltIn(Mono) }
		}
		label = match kind {
			Sans => "Sans"
			Serif => "Serif"
			Mono => "Mono"
		}
		base = [Pdf.title("${label} family"), Pdf.heading(1, "${label} heading"), Pdf.paragraph(if (kind == Sans) "Sans regular ⌘K" else "${label} regular"), Pdf.rich_paragraph([Pdf.strong([Pdf.text("${label} bold")])])]
		contents = if kind == Mono {
			base
		} else {
			base.append(Pdf.rich_paragraph([Pdf.emphasis([Pdf.text("${label} italic")])]))
				.append(Pdf.rich_paragraph([Pdf.strong([Pdf.emphasis([Pdf.text("${label} strong emphasis")])])]))
				.append(Pdf.rich_paragraph([Pdf.emphasis([Pdf.strong([Pdf.text("${label} emphasis strong")])])]))
		}
		doc = Pdf.document({
			title: "${label} family acceptance ${context.to_str()}",
			language: "en",
			contents: contents
				.append(Pdf.rich_paragraph([Pdf.code("Fira regular ⌘K")]))
				.append(Pdf.rich_paragraph([Pdf.strong([Pdf.code("Fira bold")])]))
				.append(Pdf.source_block({ text: "source = 42 ⌘K" })),
		})
		evidence(doc, { options: Pdf.Options.{ theme }, origin: Packaged, registry: Font.Registry.empty })
	}

	exact_override : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	exact_override = |context| {
		if context != 0 {
			return Err(Evidence("invalid override case"))
		}
		faces = RocFont.register(Font.Registry.empty, Font.ValidationLimits.default) ? Font
		theme = Theme.{ family: BuiltIn(Mono), inline: { emphasis: { font: Face(faces.emphasis) }, strong_emphasis: { font: Face(faces.strong_emphasis) } } }
		doc = Pdf.document({ title: "Explicit exact font styles ${context.to_str()}", language: "en", contents: [Pdf.paragraph("Mono regular"), Pdf.rich_paragraph([Pdf.emphasis([Pdf.code("Exact italic override")])]), Pdf.rich_paragraph([Pdf.strong([Pdf.emphasis([Pdf.text("Exact combined override")])])]), Pdf.rich_paragraph([Pdf.emphasis([Pdf.strong([Pdf.text("Exact combined reverse")])])])] })
		evidence(doc, { options: Pdf.Options.{ fonts: Registered(faces.registry), theme }, origin: Caller, registry: faces.registry })
	}

	scale : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	scale = |count| {
		if count != 10 and count != 100 {
			return Err(Evidence("invalid scale pair"))
		}
		var $contents = List.with_capacity(count * 2)
		var $index = 0
		while $index < count {
			$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("Scale regular "), Pdf.strong([Pdf.text("bold ")]), Pdf.emphasis([Pdf.text("italic ")]), Pdf.strong([Pdf.emphasis([Pdf.text("combined ")])]), Pdf.code("code")]))
			$contents = $contents.append(Pdf.source_block({ text: "source = 42" }))
			$index = $index + 1
		}
		doc = Pdf.document({ title: "Font demand scale", language: "en", contents: $contents })
		evidence(doc, { options: Pdf.Options.default, origin: Packaged, registry: Font.Registry.empty })
	}

	negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	negatives = |context| {
		if context != 0 {
			return Err(Evidence("invalid negatives case"))
		}
		lead = [Pdf.paragraph("Lead paragraph"), Pdf.rich_paragraph([Pdf.text("An earlier rich paragraph")])]
		code_italic = Pdf.document({ title: "Missing mono italic", language: "en", contents: lead.append(Pdf.rich_paragraph([Pdf.emphasis([Pdf.code("italic code")])])) })
		code_combined = Pdf.document({ title: "Missing mono bold italic", language: "en", contents: lead.append(Pdf.rich_paragraph([Pdf.strong([Pdf.emphasis([Pdf.code("combined code")])])])) })
		mono_italic = Pdf.document({ title: "Missing family italic", language: "en", contents: lead.append(Pdf.rich_paragraph([Pdf.emphasis([Pdf.text("italic mono")])])) })
		serif_symbol = Pdf.document({ title: "Missing serif coverage", language: "en", contents: lead.append(Pdf.paragraph("Missing command: ⌘")) })
		missing_source = Pdf.document({ title: "Missing source style", language: "en", contents: lead.append(Pdf.source_block({ face: BuiltIn({ family: Mono, style: Italic }), text: "source = 42" })) })
		check_rejection(code_italic, { options: Pdf.Options.default, code: FeatureUnavailable, feature: "text.style_unavailable", location: AtPath("contents[2].inlines[0]") })?
		check_rejection(code_combined, { options: Pdf.Options.default, code: FeatureUnavailable, feature: "text.style_unavailable", location: AtPath("contents[2].inlines[0]") })?
		check_rejection(mono_italic, { options: Pdf.Options.{ theme: { family: BuiltIn(Mono) } }, code: FeatureUnavailable, feature: "text.style_unavailable", location: AtPath("contents[2].inlines[0]") })?
		check_rejection(serif_symbol, { options: Pdf.Options.{ theme: { family: BuiltIn(Serif) } }, code: FontCoverageMissing, feature: "text.coverage_missing", location: AtPath("contents[2]") })?
		check_rejection(missing_source, { options: Pdf.Options.default, code: FeatureUnavailable, feature: "text.style_unavailable", location: AtPath("contents[2]") })?
		custom = Font.Registry.empty.register({ bytes: caller_bytes, registration: { provision: BuiltIn, scripts: ["Latn"] }, limits: Font.ValidationLimits.default }) ? Font
		custom_doc = Pdf.document({ title: "Missing caller style", language: "en", contents: [Pdf.paragraph("Café PDF"), Pdf.rich_paragraph([Pdf.text("Café")]), Pdf.rich_paragraph([Pdf.strong([Pdf.text("Café")])])] })
		check_rejection(custom_doc, { options: Pdf.Options.{ fonts: Registered(custom.registry), theme: { family: Registered({ regular: custom.face }) } }, code: FeatureUnavailable, feature: "text.style_unavailable", location: AtPath("contents[2].inlines[0]") })?
		policy_doc = Pdf.document({ title: "Ordered policy rejects exact combined overrides", language: "en", contents: [Pdf.paragraph("Café PDF"), Pdf.rich_paragraph([Pdf.strong([Pdf.emphasis([Pdf.text("Café")])])])] })
		family_options = Pdf.Options.{ fonts: Registered(custom.registry), theme: { face: custom.face, font_selection: Policy(custom.policy), inline: { strong_emphasis: { font: Family(BuiltIn(Mono)) } } } }
		face_options = Pdf.Options.{ fonts: Registered(custom.registry), theme: { face: custom.face, font_selection: Policy(custom.policy), inline: { strong_emphasis: { font: Face(custom.face) } } } }
		check_rejection(policy_doc, { options: family_options, code: FeatureUnavailable, feature: "text.inline_font_policy", location: DocumentScope })?
		check_rejection(policy_doc, { options: face_options, code: FeatureUnavailable, feature: "text.inline_font_policy", location: DocumentScope })?
		labelled = Scene.Drawing.empty
			.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 120, height: 60 }), color: Color.srgb8({ red: 255, green: 255, blue: 255 }) })
			.text({ origin: Layout.point({ x: 4, y: 36 }), size: 10, text: "Body label" })
			.text_in({ role: Emphasis, label: { origin: Layout.point({ x: 4, y: 20 }), size: 10, text: "Italic label" } })
		figure = Pdf.figure({ drawing: labelled, alt: "An annotated mark", caption: Pdf.no_caption })
		panel = Pdf.custom_block({ name: "Annotated panel", panel: labelled, contents: [Pdf.paragraph("Inside panel")], inset: 4, size: { width: 120, height: 60 }, fragmentation: Unsplittable })
		later_figure = Pdf.document({ title: "Drawing style owner", language: "en", contents: [Pdf.paragraph("Lead paragraph"), figure] })
		# The earlier panel must retain its role's owner even though the
		# resolver visits figure blocks before its separate panel traversal.
		earlier_panel = Pdf.document({ title: "First drawing style owner", language: "en", contents: [Pdf.paragraph("Lead paragraph"), panel, figure] })
		mono_options = Pdf.Options.{ theme: { family: BuiltIn(Mono) } }
		check_rejection(later_figure, { options: mono_options, code: FeatureUnavailable, feature: "text.style_unavailable", location: AtDrawingLabel({ path: "contents[1]", label: 1 }) })?
		check_rejection(earlier_panel, { options: mono_options, code: FeatureUnavailable, feature: "text.style_unavailable", location: AtDrawingLabel({ path: "contents[1]", label: 1 }) })?
		Ok({ bytes: [], work: [10, 8, 2, 0] })
	}
}

evidence : Document, { options : Pdf.Options, origin : KernelFacadeFonts.Origin, registry : Font.Registry } -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
evidence = |doc, { options, origin, registry }| {
	theme = options.theme
	bytes = Pdf.to_bytes_with(doc, options) ? Pdf
	authoring = Document.normalize(doc)
	resolved = KernelFacadeFonts.resolve(authoring, { origin, registry, theme }) ? Resolution
	work = resolved.work
	if work.copied_input_bytes != 0 {
		return Err(Evidence("resolver copied caller/font input bytes"))
	}
	Ok({ bytes, work: [work.packaged_inspections, work.registered_font_bytes, work.inline_visits, work.source_visits, work.copied_input_bytes, authoring.blocks.len(), authoring.inlines.len(), authoring.sources.len(), bytes.len()] })
}

check_rejection : Document, { options : Pdf.Options, code : Conformance.DiagnosticCode, feature : Str, location : [AtDrawingLabel({ path : Str, label : U64 }), AtPath(Str), DocumentScope] } -> Try({}, Fixture.Error)
check_rejection = |doc, { options, code, feature, location }| match Pdf.to_bytes_with(doc, options) {
	Err(InvalidDocument({ diagnostics: [diagnostic], .. })) => {
		located = match location {
			AtPath(path) => diagnostic.details.any(|detail| detail.starts_with(path))
			AtDrawingLabel({ path, label }) => diagnostic.details == [path] and diagnostic.message.contains("Drawing label ${label.to_str()}")
			DocumentScope => diagnostic.details.is_empty()
		}
		if diagnostic.code == code and diagnostic.feature == Feature(feature) and located {
			Ok({})
		} else {
			Err(Evidence("wrong located rejection: ${Str.inspect(diagnostic)}"))
		}
	}
	Err(error) => Err(Evidence("wrong rejection: ${Str.inspect(error)}"))
	Ok(_) => Err(Evidence("unsupported font style or coverage produced bytes"))
}
