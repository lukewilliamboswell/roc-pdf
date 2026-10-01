import pdf.Color
import pdf.Conformance
import pdf.Document
import pdf.Font
import pdf.KernelBuiltInFont
import pdf.KernelColor
import pdf.KernelContent
import pdf.KernelFacadeFragments
import pdf.KernelFacadeLines
import pdf.KernelFacadeOutput
import pdf.KernelFacadePages
import pdf.KernelFacadePipeline
import pdf.KernelFacadeScenes
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFacadeText
import pdf.KernelFont
import pdf.KernelFontPlan
import pdf.KernelImage
import pdf.KernelLineLayout
import pdf.KernelNavigation
import pdf.KernelObject
import pdf.KernelObjectPlan
import pdf.KernelPageLayout
import pdf.KernelPdfFont
import pdf.KernelPdfText
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.Semantics
import pdf.KernelSrgbProfile
import pdf.KernelTaggedTextStructure
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)
import "../assets/NotoSansMono-Code-Fixture.ttf" as mono_font_bytes : List(U8)

## Rich inline evidence through the public `Pdf` constructors.
##
## - `mixed`: styled runs (themed `Strong`, `Em`, and `Code` colors),
##   expansions with `/E`, French `Span`s inside `en-AU` text (one inside a
##   `Quote`), nested inline elements inside a section beside a bulleted list
##   and a plain paragraph, an inline internal link to a destination heading,
##   and an inline URI link containing `Strong` that wraps across a line
##   break.
## - `paragraphs xN`: N rich paragraphs, each with eight inline elements
##   including a URI link, the scale pair for linear inline planning,
##   shaping, line layout, and annotation lowering.
## - `ordered`: a rich paragraph through an ordered caller-font policy, with
##   a `zh-Hans` span selected onto the Han face and a French span.
## - `code_face`: the mixed document with a monospace caller face for
##   `Code` (`inline.code.font`) beside the packaged face registered
##   as the body face; code runs, including code nested in `Strong`, paint
##   in the second output font. Its rejections: a code face under an
##   ordered policy (`text.inline_font_policy`), code text the monospace
##   face does not cover (`text.coverage_missing` at the code inline), and
##   a code face without a font registry (`InvalidFontResource`).
## - `shared_source xN`: N table rows and N paragraph pairs in which the same
##   text occurs plainly and inside `Strong`, with a registered strong face.
##   Identical text interns to one source, so its occurrences carry
##   different font splits; each paints in its own face. The scale pair
##   shows the per-split templates stay linear. Its rejection: strong text
##   the strong face does not cover (`text.coverage_missing` at the inline).
## - `heading_faces xN`: N sections of a level-1 and a level-2 heading and a
##   paragraph under a title. The title and level-1 headings take the
##   monospace face (a second registered face) at their own size and color;
##   level-2 headings keep the body face at a smaller size. Its rejections:
##   a heading face without a font registry (`InvalidFontResource`), a
##   heading face under an ordered policy (`text.block_font_policy`), and
##   heading text the heading face does not cover (`text.coverage_missing`
##   at the heading).
## - `scaled_code xN`: N rich paragraphs with `Code` runs in the monospace
##   face at 85% of the paragraph size (`inline.code.scale`), a
##   paragraph that is all code, and a table row whose one cell is all code.
##   Scaled runs share their line's baseline and leading. Its rejections:
##   scales of 49% and 101% (`text.inline_scale` at the theme path); 50%
##   and 100% are accepted.
## - `link_style xN`: N rich paragraphs whose inline URI link (with a
##   nested `Strong` run in its own theme color) wraps across a line, and N
##   link blocks, under the theme's `link.color` and
##   `link.underline`. Every painted line run of a link gets a
##   `Decoration` artifact underline in its fill color. Its rejections: a
##   negative offset, a zero thickness, and an underline taller than the
##   body leading's room (`text.link_underline`).
## - `scoped_text xN`: N dark-panel callouts whose scope paints ordinary
##   text near-white, the `Strong` label amber, and link text sky blue,
##   beside a scoped heading and bullet list whose text and generated
##   labels take a slate text color, and a table inside the scope whose
##   themed header color still wins. Like `scoped_colors`, it proves the
##   scope adds no semantic node, content item, or occurrence. The 10/50
##   pair is the linear scale pair.
## - `scoped_colors xN`: N warning and note callouts, each a `Pdf.scoped`
##   group whose `Strong` label and link take the callout's own colors
##   (amber or teal) over the theme's, one nested scope that overrides its
##   outer scope, and a scoped custom block. Scopes add no structure
##   element: the scoped document's semantic node and content writes equal
##   those of the same document without scopes. Its rejections: an empty
##   scope (`semantics.scope_empty`) and a scope inside a list item
##   (`semantics.list_item_content`).
## - `code_holds xN`: N paragraphs whose code span `--lumen-indigo-accent`
##   is moved across the line end one letter at a time, a paragraph that
##   is one long spaced command, and a table whose content column holds
##   hyphenated commands. Line layout must never end a line inside a code
##   word: the work counts the code holds applied and the lines that end
##   inside one (zero), and the same document with each code span written
##   as plain text must break inside at least one identifier, which shows
##   the positions reach a hyphen break. Its rejection: a code word wider
##   than its fixed column (`layout.unbreakable_token`). The 14/140 pair is
##   the linear scale pair.
## - `atomic_negatives`: every inline rejection with its stable dotted code
##   and inline path, the eight-deep accepted boundary, and no bytes.
##
## Bytes always come from `Pdf.to_bytes_with` (the default `Archive`
## profile). Work comes from one additional semantic planning pass and one
## facade pipeline build over the same normalized authoring.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, InvalidScale, MissingRejection(U64)]

	mixed : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	mixed = |context| {
		theme = Theme.{ inline: { code: { color: Themed(Color.srgb8({ blue: 60, green: 100, red: 20 })) }, emphasis: { color: Themed(Color.srgb8({ blue: 140, green: 70, red: 20 })) }, strong: { color: Themed(Color.srgb8({ blue: 30, green: 30, red: 150 })) } } }
		evidence(mixed_document(context), theme, BuiltInFace)
	}

	paragraphs : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	paragraphs = |count| {
		if count == 0 or count > 1000 {
			return Err(InvalidScale)
		}
		evidence(paragraph_document(count), Theme.default, BuiltInFace)
	}

	ordered : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	ordered = |context| {
		registered = register_faces(context)?
		evidence(ordered_document(context), Theme.{ font_selection: Policy(registered.policy) }, Policy(registered))
	}

	code_face : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	code_face = |context| run_code_face(context)

	shared_source : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	shared_source = |count| run_shared_source(count)

	heading_faces : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	heading_faces = |count| run_heading_faces(count)

	scaled_code : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	scaled_code = |count| run_scaled_code(count)

	link_style : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	link_style = |count| run_link_style(count)

	scoped_colors : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	scoped_colors = |count| run_scoped_colors(count)

	scoped_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	scoped_text = |count| run_scoped_text(count)

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)

	code_holds : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	code_holds = |count| {
		if count == 0 or count > 1000 {
			return Err(InvalidScale)
		}
		run_code_holds(count)
	}
}

## The identifiers the code-holds document sets, as code or as plain text.
held_identifier : Str
held_identifier = "--lumen-indigo-accent"

code_holds_document : U64, (Str -> Pdf.Inline) -> Document
code_holds_document = |count, inline| {
	var $contents = [Pdf.title("Code holds")]
	var $index = 0
	while $index < count {
		lead = "x${Str.repeat("a", $index % 14)} Set the colour token in the stylesheet for tinted panels as "
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.text(lead), inline(held_identifier), Pdf.text(" and keep the rest of the palette.")]))
		$index = $index + 1
	}
	command_row = |command, purpose| Pdf.row([Pdf.header_cell(Row, [inline(command)]), Pdf.cell([Pdf.text(purpose)])])
	$contents = $contents
		.append(Pdf.rich_paragraph([inline("kestrel migrate scenarios/ --to toml --write --dry-run --verbose --keep-comments --in-place")]))
		.append(
			Pdf.table({
				body_rows: [
					command_row("kubectl rollout undo --to-revision=N", "Return a deployment to an earlier revision."),
					command_row("payctl migrations --pending", "List ledger migrations applied since the last release."),
				],
				caption: Pdf.no_caption,
				columns: [{ align: Start, width: Content }, { align: Start, width: Share(1) }],
				footer_rows: [],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Command")]), Pdf.header_cell(Column, [Pdf.text("Purpose")])])],
				row_split: KeepRows,
			}),
		)
	Pdf.document({ contents: $contents, language: "en-AU", title: "Code holds (${count.to_str()})" })
}

## The lines of `document` that end strictly inside one of `ranges`: for
## each leaf block, its scalar ranges (per source) and every line but the
## last of each explicit-line-break segment.
lines_ending_inside : Document, (Document.NormalizedAuthoring, KernelFacadeShape.Plan, U64, List(KernelFacadeSources.Source) -> List(Semantics.Range)) -> Try({ holds : U64, inside : U64 }, Fixture.EvidenceError)
lines_ending_inside = |document, ranges_of| {
	authoring = Document.normalize(document)
	semantics = KernelFacadeSemantics.Plan.build(authoring, semantic_limits) ? |_| EvidenceFailure
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(semantics)))
	sources = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	shape = KernelFacadeShape.Plan.build(authoring, KernelFacadeSemantics.Plan.block_ownership(semantics), store, sources, font, Theme.default, KernelFacadeShape.Limits.make({ max_requests: 65536, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) })) ? |_| EvidenceFailure
	lines = KernelFacadeLines.Plan.build_authoring(authoring, shape, sources, page_size, Theme.default, KernelFacadeLines.Limits.make({ line: KernelLineLayout.BatchLimits.make({ line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }), max_key_probes: 4000000, max_lines: 1000000, max_runs: 65536, max_table_slots: 262144, max_templates: 65536 }), max_blocks: 16384, max_runs: 65536 })) ? |_| EvidenceFailure
	all_lines = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines))
	var $holds = 0
	var $inside = 0
	var $block = 0
	for block_lines in KernelFacadeLines.Plan.blocks(lines) {
		match block_lines {
			TextBlock({ body, body_offset: _, label: _ }) => {
				ranges = ranges_of(authoring, shape, $block, sources)
				$holds = $holds + ranges.len()
				var $line = body.lines.start()
				while $line + 1 < body.lines.start() + body.lines.length() {
					current = list_at(all_lines, $line).source.scalars
					next = list_at(all_lines, $line + 1).source.scalars
					end = current.start() + current.length()

					# A segment's last line is followed by a mandatory break
					# (the next line restarts at scalar 0 of its source).
					if next.start() == end {
						if ranges.any(|range| range.start() < end and end < range.start() + range.length()) {
							$inside = $inside + 1
						}
					}
					$line = $line + 1
				}
			}
			ContentlessCell => {}
		}
		$block = $block + 1
	}
	Ok({ holds: $holds, inside: $inside })
}

## The scalar range of `held_identifier` in a block's source, if the block
## holds it. The document's text is ASCII, so bytes are scalars.
identifier_ranges : Document.NormalizedAuthoring, KernelFacadeShape.Plan, U64, List(KernelFacadeSources.Source) -> List(Semantics.Range)
identifier_ranges = |authoring, _shape, block, _sources| {
	bytes = list_at(authoring.blocks, block).text.to_utf8()
	needle = held_identifier.to_utf8()
	var $start = 0
	while $start + needle.len() <= bytes.len() {
		if bytes.sublist({ start: $start, len: needle.len() }) == needle {
			return [Semantics.Range.from_start_and_length($start, needle.len())]
		}
		$start = $start + 1
	}
	[]
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "rich-inline evidence index escaped"
}

run_code_holds : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_code_holds = |count| {
	document = code_holds_document(count, Pdf.code)
	evidenced = evidence_with_limits(document, Theme.default, BuiltInFace, shared_source_limits)?
	held = lines_ending_inside(document, |authoring, shape, block, sources| KernelFacadeShape.Plan.code_holds(shape, authoring, block, sources).map(|hold| hold.scalars))?
	control = lines_ending_inside(code_holds_document(count, Pdf.text), identifier_ranges)?
	if held.inside != 0 or control.inside == 0 {
		return Err(EvidenceFailure)
	}
	narrow = Pdf.document({
		contents: [Pdf.table({ body_rows: [Pdf.row([Pdf.header_cell(Row, [Pdf.code("--to-revision=N")]), Pdf.cell([Pdf.text("Roll back.")])])], caption: Pdf.no_caption, columns: [{ align: Start, width: Fixed(Layout.Unit.points(40 + (count % 1).to_i64_wrap())) }, { align: Start, width: Share(1) }], footer_rows: [], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Flag")]), Pdf.header_cell(Column, [Pdf.text("Use")])])], row_split: KeepRows })],
		language: "en-AU",
		title: "Narrow code",
	})
	rejected = rejects(narrow, LayoutConstraintViolated, "layout.unbreakable_token", "contents[0].table.body_rows[0].cells[0]")
	if rejected != 1 {
		return Err(MissingRejection(rejected))
	}
	Ok({ bytes: evidenced.bytes, work: evidenced.work.append(held.holds).append(held.inside).append(control.inside).append(rejected) })
}

## The packaged face as body face 0 and the monospace fixture as face 1.
code_faces : U64 -> Try({ body : Font.FaceId, mono : Font.FaceId, registry : Font.Registry }, Fixture.EvidenceError)
code_faces = |context| {
	limits = if context == 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	body = match Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	mono = match body.registry.register(mono_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	Ok({ body: body.face, mono: mono.face, registry: mono.registry })
}

run_code_face : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_code_face = |context| {
	faces = code_faces(context)?
	theme = Theme.{ inline: { code: { color: Themed(Color.srgb8({ blue: 60, green: 100, red: 20 })), font: Face(faces.mono) } } }
	options = Pdf.Options.{ theme: theme, fonts: Registered(faces.registry) }
	document = mixed_document(context)
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure

	## The same fonts through the styled pipeline give the shaping and
	## output work: two used faces, body first. Themed colors change only
	## paint facts, so work uses the uncolored theme.
	body_font = faces.registry.prepared_face(faces.body) ? |_| EvidenceFailure
	mono_font = faces.registry.prepared_face(faces.mono) ? |_| EvidenceFailure
	styled = { faces: [faces.body, faces.mono], fonts: [body_font, mono_font], roles: { code: Candidate(1), emphasis: Inherited, quote: Inherited, strong: Inherited } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, Theme.{ inline: { code: { font: Face(faces.mono) } } }, page_size, descriptor, NoDocumentFacts, pipeline_limits) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)

	## Rejections: each is transactional, with no bytes.
	lead = Pdf.paragraph("Lead")
	policy = match faces.registry.with_policy([faces.body, faces.mono]) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	policy_options = Pdf.Options.{ theme: { ..theme, font_selection: Policy(policy.policy) }, fonts: Registered(policy.registry) }
	under_policy = match Pdf.to_bytes_with(document, policy_options) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature("text.inline_font_policy"), .. }], .. })) => 1
		_ => 0
	}
	uncovered_document = Pdf.document({ contents: [lead, Pdf.rich_paragraph([Pdf.text("Run "), Pdf.code("café")])], language: "en-AU", title: "Code coverage" })
	uncovered = match Pdf.to_bytes_with(uncovered_document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FontCoverageMissing, details: ["contents[1].inlines[1].inlines[0]"], feature: Feature("text.coverage_missing"), .. }], .. })) => 1
		_ => 0
	}
	unregistered = match Pdf.to_bytes_with(document, Pdf.Options.{ theme: theme }) {
		Err(InvalidFontResource(UnknownFace(face))) => if face == faces.mono 1 else 0
		_ => 0
	}
	rejections = under_policy + uncovered + unregistered
	if rejections != 3 {
		return Err(MissingRejection(rejections))
	}
	Ok({
		bytes,
		work: [
			flow.shaped_runs,
			flow.lines,
			flow.final_runs,
			flow.pages,
			rejections,
			bytes.len(),
		],
	})
}

## The same cell and paragraph texts plain and strong: `Revision 10` and
## `n/a` intern to one source each, shared by plain and strong occurrences.
shared_source_document : U64 -> Document
shared_source_document = |count| {
	var $rows = List.with_capacity(count)
	var $contents = List.with_capacity(2 * count + 4)
	$contents = $contents.append(Pdf.heading(1, "Shared sources"))

	## One paragraph text twice: plain, then with its second half strong in
	## the wider monospace face. Both begin with a body-face run, so only
	## the exact run sequence tells their line templates apart.
	$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("Throughput rose in every scenario of the reference suite, and the slowest percentile fell by nearly half against the previous release.")]))
	$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("Throughput rose in every scenario of the reference suite, "), Pdf.strong([Pdf.text("and the slowest percentile fell by nearly half against the previous release.")])]))
	var $index = 0
	while $index < count {
		$rows = $rows.append(
			Pdf.row([
				Pdf.header_cell(Row, [Pdf.text("Row ${($index + 1).to_str()}")]),
				Pdf.cell([Pdf.text("10")]),
				Pdf.cell([Pdf.strong([Pdf.text("10")])]),
				Pdf.cell([Pdf.strong([Pdf.text("n/a")])]),
				Pdf.cell([Pdf.text("n/a")]),
			]),
		)
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("Revision 10")]))
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.strong([Pdf.text("Revision 10")])]))
		$index = $index + 1
	}
	table = Pdf.table({
		body_rows: $rows,
		caption: Pdf.caption("Plain and strong occurrences of shared text"),
		columns: [
			{ align: Start, width: Share(2) },
			{ align: Center, width: Share(1) },
			{ align: Center, width: Share(1) },
			{ align: Center, width: Share(1) },
			{ align: Center, width: Share(1) },
		],
		footer_rows: [],
		header_rows: [
			Pdf.row([
				Pdf.header_cell(Column, [Pdf.text("Row")]),
				Pdf.header_cell(Column, [Pdf.text("Plain")]),
				Pdf.header_cell(Column, [Pdf.text("Strong")]),
				Pdf.header_cell(Column, [Pdf.text("Strong n/a")]),
				Pdf.header_cell(Column, [Pdf.text("Plain n/a")]),
			]),
		],
		row_split: SplitRows,
	})
	Pdf.document({ contents: $contents.append(table), language: "en-AU", title: "Shared sources" })
}

run_shared_source : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_shared_source = |count| {
	if count == 0 or count > 1000 {
		return Err(InvalidScale)
	}
	faces = code_faces(0)?
	theme = Theme.{ inline: { strong: { font: Face(faces.mono) } } }
	options = Pdf.Options.{ theme: theme, fonts: Registered(faces.registry) }
	document = shared_source_document(count)
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	body_font = faces.registry.prepared_face(faces.body) ? |_| EvidenceFailure
	mono_font = faces.registry.prepared_face(faces.mono) ? |_| EvidenceFailure
	styled = { faces: [faces.body, faces.mono], fonts: [body_font, mono_font], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Candidate(1) } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, NoDocumentFacts, shared_source_limits) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)

	## Strong text the strong face does not cover is located at its inline;
	## the body face is never substituted.
	uncovered_document = Pdf.document({ contents: [Pdf.paragraph("Café"), Pdf.rich_paragraph([Pdf.strong([Pdf.text("Café")])])], language: "en-AU", title: "Strong coverage" })
	uncovered = match Pdf.to_bytes_with(uncovered_document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FontCoverageMissing, details: ["contents[1].inlines[0].inlines[0]"], feature: Feature("text.coverage_missing"), .. }], .. })) => 1
		_ => 0
	}
	if uncovered != 1 {
		return Err(MissingRejection(uncovered))
	}
	Ok({
		bytes,
		work: [
			flow.shaped_runs,
			flow.lines,
			flow.final_runs,
			flow.pages,
			uncovered,
			bytes.len(),
		],
	})
}

heading_faces_theme : Font.FaceId, Font.FaceId, Color.SourceValue -> Theme
heading_faces_theme = |body, heading, h1_color| {
	face: body,
	title: { face: Face(heading) },
	headings: {
		h1: Own({ color: h1_color, face: Face(heading), leading: Layout.Unit.points(22), size: Layout.Unit.points(17) }),
		h2: Own({ leading: Layout.Unit.points(16), size: Layout.Unit.points(12) }),
	},
}

heading_faces_document : U64 -> Document
heading_faces_document = |count| {
	var $contents = List.with_capacity(3 * count + 1)
	$contents = $contents.append(Pdf.title("Operations review"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		$contents = $contents.append(Pdf.heading(1, "${number} Region ${number}"))
		$contents = $contents.append(Pdf.heading(2, "${number}.1 Findings"))
		$contents = $contents.append(Pdf.paragraph("Stock counts matched the warehouse system in every aisle, and returns were processed within two days."))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Heading faces" })
}

run_heading_faces : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_heading_faces = |count| {
	if count == 0 or count > 1000 {
		return Err(InvalidScale)
	}
	faces = code_faces(0)?
	theme = heading_faces_theme(faces.body, faces.mono, Color.srgb8({ blue: 150, green: 60, red: 30 }))
	options = Pdf.Options.{ theme: theme, fonts: Registered(faces.registry) }
	document = heading_faces_document(count)
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	body_font = faces.registry.prepared_face(faces.body) ? |_| EvidenceFailure
	mono_font = faces.registry.prepared_face(faces.mono) ? |_| EvidenceFailure
	styled = { faces: [faces.body, faces.mono], fonts: [body_font, mono_font], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }

	## Colors change only paint facts, so work uses the uncolored theme.
	uncolored = heading_faces_theme(faces.body, faces.mono, Color.srgb8({ blue: 0, green: 0, red: 0 }))
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, uncolored, page_size, descriptor, NoDocumentFacts, shared_source_limits) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)

	## Rejections: each is transactional, with no bytes.
	unregistered = match Pdf.to_bytes_with(document, Pdf.Options.{ theme: theme }) {
		Err(InvalidFontResource(UnknownFace(face))) => if face == faces.mono 1 else 0
		_ => 0
	}
	policy = match faces.registry.with_policy([faces.body, faces.mono]) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	policy_options = Pdf.Options.{ theme: { ..theme, font_selection: Policy(policy.policy) }, fonts: Registered(policy.registry) }
	under_policy = match Pdf.to_bytes_with(document, policy_options) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature("text.block_font_policy"), .. }], .. })) => 1
		_ => 0
	}
	uncovered_document = Pdf.document({ contents: [Pdf.paragraph("Lead"), Pdf.heading(1, "Café")], language: "en-AU", title: "Heading coverage" })
	uncovered = match Pdf.to_bytes_with(uncovered_document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FontCoverageMissing, details: ["contents[1]"], feature: Feature("text.coverage_missing"), .. }], .. })) => 1
		_ => 0
	}
	rejections = unregistered + under_policy + uncovered
	if rejections != 3 {
		return Err(MissingRejection(rejections))
	}
	Ok({
		bytes,
		work: [
			flow.shaped_runs,
			flow.lines,
			flow.final_runs,
			flow.pages,
			rejections,
			bytes.len(),
		],
	})
}

scaled_code_document : U64 -> Document
scaled_code_document = |count| {
	var $contents = List.with_capacity(count + 3)
	$contents = $contents.append(Pdf.heading(1, "Build commands"))
	var $index = 0
	while $index < count {
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("Step ${($index + 1).to_str()}: run "), Pdf.code("roc build --opt=size"), Pdf.text(" and then "), Pdf.strong([Pdf.code("roc test")]), Pdf.text(" before you publish the release notes for review.")]))
		$index = $index + 1
	}
	$contents = $contents.append(Pdf.rich_paragraph([Pdf.code("roc check main.roc")]))
	table = Pdf.table({
		body_rows: [Pdf.row([Pdf.header_cell(Row, [Pdf.text("Check")]), Pdf.cell([Pdf.code("roc check")])])],
		caption: Pdf.no_caption,
		columns: [{ align: Start, width: Share(1) }, { align: Start, width: Share(1) }],
		footer_rows: [],
		header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Task")]), Pdf.header_cell(Column, [Pdf.text("Command")])])],
		row_split: SplitRows,
	})
	Pdf.document({ contents: $contents.append(table), language: "en-AU", title: "Scaled code" })
}

run_scaled_code : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_scaled_code = |count| {
	if count == 0 or count > 1000 {
		return Err(InvalidScale)
	}
	faces = code_faces(0)?
	base = Theme.{ inline: { code: { font: Face(faces.mono) } } }
	theme = { ..base, inline: { ..base.inline, code: { ..base.inline.code, scale: Percent(85) } } }
	options = Pdf.Options.{ theme: theme, fonts: Registered(faces.registry) }
	document = scaled_code_document(count)
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	body_font = faces.registry.prepared_face(faces.body) ? |_| EvidenceFailure
	mono_font = faces.registry.prepared_face(faces.mono) ? |_| EvidenceFailure
	styled = { faces: [faces.body, faces.mono], fonts: [body_font, mono_font], roles: { code: Candidate(1), emphasis: Inherited, quote: Inherited, strong: Inherited } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, NoDocumentFacts, shared_source_limits) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)

	## The accepted boundaries, then the two rejected neighbours.
	boundary = |percent| Pdf.Options.{ theme: { ..base, inline: { ..base.inline, code: { ..base.inline.code, scale: Percent(percent) } } }, fonts: Registered(faces.registry) }
	lower = match Pdf.to_bytes_with(document, boundary(50)) {
		Ok(_) => 1
		Err(_) => 0
	}
	upper = match Pdf.to_bytes_with(document, boundary(100)) {
		Ok(_) => 1
		Err(_) => 0
	}
	below = match Pdf.to_bytes_with(document, boundary(49)) {
		Err(InvalidDocument({ diagnostics: [{ code: LayoutConstraintViolated, details: ["theme.inline_scale.code"], feature: Feature("text.inline_scale"), .. }], .. })) => 1
		_ => 0
	}
	above = match Pdf.to_bytes_with(document, boundary(101)) {
		Err(InvalidDocument({ diagnostics: [{ code: LayoutConstraintViolated, details: ["theme.inline_scale.code"], feature: Feature("text.inline_scale"), .. }], .. })) => 1
		_ => 0
	}
	checks = lower + upper + below + above
	if checks != 4 {
		return Err(MissingRejection(checks))
	}
	Ok({
		bytes,
		work: [
			flow.shaped_runs,
			flow.lines,
			flow.final_runs,
			flow.pages,
			checks,
			bytes.len(),
		],
	})
}

link_style_document : U64 -> Document
link_style_document = |count| {
	var $contents = List.with_capacity(2 * count + 1)
	$contents = $contents.append(Pdf.heading(1, "Further reading"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		$contents = $contents.append(
			Pdf.rich_paragraph([
				Pdf.text("Item ${number}: the release checklist lives in "),
				Pdf.inline_link([Pdf.text("the operations handbook, section "), Pdf.strong([Pdf.text("four")]), Pdf.text(", which lists every pre-flight step")], "https://example.org/handbook/${number}"),
				Pdf.text(" and who signs it off."),
			]),
		)
		$contents = $contents.append(Pdf.link("Status page ${number}", "https://status.example.org/${number}"))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Link style" })
}

link_style_theme : Theme.LinkUnderline -> Theme
link_style_theme = |underline|
	Theme.{ inline: { strong: { color: Themed(Color.srgb8({ blue: 30, green: 30, red: 150 })) } }, link: { color: Themed(Color.srgb8({ blue: 180, green: 80, red: 20 })), underline: underline } }

run_link_style : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_link_style = |count| {
	if count == 0 or count > 1000 {
		return Err(InvalidScale)
	}
	underline = Underline({ offset: Layout.Unit.from_raw(1200), thickness: Layout.Unit.from_raw(600) })
	document = link_style_document(count)
	bytes = Pdf.to_bytes_with(document, Pdf.Options.{ theme: link_style_theme(underline) }) ? |_| EvidenceFailure

	## The rejected underlines: body leading 14 pt less size 11 pt leaves 3 pt.
	rejected = |value| match Pdf.to_bytes_with(document, Pdf.Options.{ theme: link_style_theme(value) }) {
		Err(InvalidDocument({ diagnostics: [{ code: LayoutConstraintViolated, details: ["theme.link_underline"], feature: Feature("text.link_underline"), .. }], .. })) => 1
		_ => 0
	}
	negative = rejected(Underline({ offset: Layout.Unit.from_raw(-100), thickness: Layout.Unit.from_raw(600) }))
	thin = rejected(Underline({ offset: Layout.Unit.from_raw(1200), thickness: Layout.Unit.from_raw(0) }))
	tall = rejected(Underline({ offset: Layout.Unit.from_raw(2500), thickness: Layout.Unit.from_raw(600) }))
	rejections = negative + thin + tall
	if rejections != 3 {
		return Err(MissingRejection(rejections))
	}
	Ok({ bytes, work: [count, rejections, bytes.len()] })
}

amber : Color.SourceValue
amber = Color.srgb8({ blue: 0, green: 110, red: 180 })

teal : Color.SourceValue
teal = Color.srgb8({ blue: 120, green: 110, red: 0 })

## Each callout's blocks, wrapped in its scope when `scoped` is true, so the
## same content can be compared with and without scopes.
scoped_colors_document : U64, Bool -> Document
scoped_colors_document = |count, scoped| {
	wrap = |scope, blocks| if scoped [Pdf.scoped(scope, blocks)] else blocks
	warning = Theme.Scope.{ strong: Themed(amber), link: Themed(amber) }
	note = Theme.Scope.{ strong: Themed(teal), link: Themed(teal) }
	var $contents = List.with_capacity(2 * count + 3)
	$contents = $contents.append(Pdf.heading(1, "Callouts"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		for block in wrap(warning, [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Warning ${number}.")]), Pdf.text(" Rotate the signing key before the release; see "), Pdf.inline_link([Pdf.text("the key policy")], "https://example.org/keys/${number}"), Pdf.text(".")])]) {
			$contents = $contents.append(block)
		}
		for block in wrap(note, [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Note ${number}.")]), Pdf.text(" Mirrors refresh every hour.")])]) {
			$contents = $contents.append(block)
		}
		$index = $index + 1
	}

	## An inner scope overrides its outer scope; the outer still colors the
	## role the inner leaves inherited.
	inner = Theme.Scope.{ strong: Themed(teal) }
	nested = if scoped [Pdf.scoped(warning, [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Outer")]), Pdf.text(" and "), Pdf.inline_link([Pdf.text("outer link")], "https://example.org/outer")]), Pdf.scoped(inner, [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Inner")]), Pdf.text(" and "), Pdf.inline_link([Pdf.text("inner link")], "https://example.org/inner")])])])] else [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Outer")]), Pdf.text(" and "), Pdf.inline_link([Pdf.text("outer link")], "https://example.org/outer")]), Pdf.rich_paragraph([Pdf.strong([Pdf.text("Inner")]), Pdf.text(" and "), Pdf.inline_link([Pdf.text("inner link")], "https://example.org/inner")])]
	for block in nested {
		$contents = $contents.append(block)
	}
	panel = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 300, 60), Color.srgb8({ blue: 220, green: 240, red: 250 }))
	callout = Pdf.custom_block({ contents: [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Scoped callout.")]), Pdf.text(" Its label takes the scope's amber.")])], fragmentation: Unsplittable, inset: Layout.Unit.points(8), name: "Scoped callout", panel, size: { height: Layout.Unit.points(60), width: Layout.Unit.points(300) } })
	for block in wrap(warning, [callout]) {
		$contents = $contents.append(block)
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Scoped colors" })
}

scoped_text_document : U64, Bool -> Document
scoped_text_document = |count, scoped| {
	wrap = |scope, blocks| if scoped [Pdf.scoped(scope, blocks)] else blocks
	near_white = Color.srgb8({ blue: 245, green: 242, red: 240 })
	dark = Theme.Scope.{ text: Themed(near_white), strong: Themed(amber), link: Themed(Color.srgb8({ blue: 250, green: 205, red: 125 })), code: Themed(near_white) }
	slate = Theme.Scope.{ text: Themed(Color.srgb8({ blue: 105, green: 85, red: 70 })) }
	panel = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 420, 40), Color.srgb8({ blue: 70, green: 40, red: 20 }))
	var $contents = List.with_capacity(count + 4)
	for block in wrap(
		slate,
		[
			Pdf.heading(1, "Release checklist"),
			Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Tag the release")]), Pdf.list_item([Pdf.paragraph("Publish the notes")])]),
			Pdf.table({
				body_rows: [Pdf.row([Pdf.header_cell(Row, [Pdf.text("Owner")]), Pdf.cell([Pdf.text("Release team")])])],
				caption: Pdf.no_caption,
				columns: [{ align: Start, width: Content }, { align: Start, width: Share(1) }],
				footer_rows: [],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Field")]), Pdf.header_cell(Column, [Pdf.text("Value")])])],
				row_split: KeepRows,
			}),
		],
	) {
		$contents = $contents.append(block)
	}
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		callout = Pdf.custom_block({
			contents: [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Step ${number}.")]), Pdf.text(" Run "), Pdf.code("make release"), Pdf.text(" and read "), Pdf.inline_link([Pdf.text("the guide")], "https://example.org/release/${number}"), Pdf.text(".")])],
			fragmentation: Unsplittable,
			inset: Layout.Unit.points(12),
			name: "Dark callout",
			panel,
			size: { height: Layout.Unit.points(40), width: Layout.Unit.points(420) },
		})
		for block in wrap(dark, [callout]) {
			$contents = $contents.append(block)
		}
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Scoped text" })
}

run_scoped_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_scoped_text = |count| {
	if count == 0 or count > 1000 {
		return Err(InvalidScale)
	}
	theme = Theme.{ table: { header_color: Themed(Color.srgb8({ blue: 140, green: 70, red: 10 })) } }
	document = scoped_text_document(count, True)
	bytes = Pdf.to_bytes_with(document, Pdf.Options.{ theme: theme }) ? |_| EvidenceFailure
	scoped_plan = KernelFacadeSemantics.Plan.build(Document.normalize(document), semantic_limits) ? |_| EvidenceFailure
	plain_plan = KernelFacadeSemantics.Plan.build(Document.normalize(scoped_text_document(count, False)), semantic_limits) ? |_| EvidenceFailure
	scoped_work = KernelFacadeSemantics.Plan.work(scoped_plan)
	plain_work = KernelFacadeSemantics.Plan.work(plain_plan)
	if scoped_work.node_writes != plain_work.node_writes or scoped_work.content_writes != plain_work.content_writes or scoped_work.occurrence_writes != plain_work.occurrence_writes {
		return Err(EvidenceFailure)
	}
	Ok({ bytes, work: [scoped_work.node_writes, scoped_work.content_writes, scoped_work.occurrence_writes, bytes.len()] })
}

run_scoped_colors : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_scoped_colors = |count| {
	if count == 0 or count > 1000 {
		return Err(InvalidScale)
	}
	theme = Theme.{ inline: { strong: { color: Themed(Color.srgb8({ blue: 30, green: 30, red: 150 })) } }, link: { color: Themed(Color.srgb8({ blue: 180, green: 80, red: 20 })) } }
	options = Pdf.Options.{ theme: theme }
	document = scoped_colors_document(count, True)
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure

	## Scopes are presentation only: the same content without them plans the
	## same semantic nodes, content items, and occurrences.
	scoped_plan = KernelFacadeSemantics.Plan.build(Document.normalize(document), semantic_limits) ? |_| EvidenceFailure
	plain_plan = KernelFacadeSemantics.Plan.build(Document.normalize(scoped_colors_document(count, False)), semantic_limits) ? |_| EvidenceFailure
	scoped_work = KernelFacadeSemantics.Plan.work(scoped_plan)
	plain_work = KernelFacadeSemantics.Plan.work(plain_plan)
	if scoped_work.node_writes != plain_work.node_writes or scoped_work.content_writes != plain_work.content_writes or scoped_work.occurrence_writes != plain_work.occurrence_writes {
		return Err(EvidenceFailure)
	}

	## Rejections: each is transactional, with no bytes.
	empty = match Pdf.to_bytes_with(Pdf.document({ contents: [Pdf.paragraph("Lead ${count.to_str()}"), Pdf.scoped(Theme.Scope.{}, [])], language: "en-AU", title: "Empty scope" }), options) {
		Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: ["contents[1]"], feature: Feature("semantics.scope_empty"), .. }], .. })) => 1
		_ => 0
	}
	in_item = match Pdf.to_bytes_with(Pdf.document({ contents: [Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Item ${count.to_str()}"), Pdf.scoped(Theme.Scope.{}, [Pdf.paragraph("Scoped")])])])], language: "en-AU", title: "Scoped item" }), options) {
		Err(InvalidDocument({ diagnostics: [{ feature: Feature("semantics.list_item_content"), .. }], .. })) => 1
		_ => 0
	}
	rejections = empty + in_item
	if rejections != 2 {
		return Err(MissingRejection(rejections))
	}
	Ok({ bytes, work: [scoped_work.node_writes, scoped_work.content_writes, scoped_work.occurrence_writes, rejections, bytes.len()] })
}

Faces : [BuiltInFace, Policy({ policy : Font.PolicyId, registry : Font.Registry })]

mixed_document : U64 -> Document
mixed_document = |context| {
	suffix = if context == 0 "" else " (${context.to_str()})"
	Pdf.document({
		contents: [
			Pdf.title("Quarterly summary${suffix}"),
			Pdf.destination_heading("summary", 1, "1 Summary"),
			Pdf.rich_paragraph([
				Pdf.text("Q1 "),
				Pdf.expansion("FY2027", "financial year 2027"),
				Pdf.text(": July to September 2026 · Prepared by the finance team."),
			]),
			Pdf.rich_paragraph([
				Pdf.text("Revenue rose "),
				Pdf.strong([Pdf.text("5.0%")]),
				Pdf.text(" to AUD 9.22 million, led by "),
				Pdf.emphasis([Pdf.text("Queensland")]),
				Pdf.text(". Freight costs fell for the second quarter; see "),
				Pdf.inline_internal_link([Pdf.text("section 3, "), Pdf.emphasis([Pdf.text("Operations")])], "operations"),
				Pdf.text("."),
			]),
			Pdf.rich_paragraph([
				Pdf.text("Revenue is reported net of "),
				Pdf.expansion("GST", "Goods and Services Tax"),
				Pdf.text(". Stock counts come from the warehouse system "),
				Pdf.code("WMS-7"),
				Pdf.text(", which records every "),
				Pdf.in_language("fr", [Pdf.text("Cafetière « Élégance »")]),
				Pdf.text(" shipment."),
			]),
			Pdf.destination_heading("operations", 1, "3 Operations"),
			Pdf.rich_paragraph([
				Pdf.text("Our oak supplier "),
				Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
				Pdf.text(" puts it simply: "),
				Pdf.quote([Pdf.in_language("fr", [Pdf.text("« Le bois ne ment pas. »")])]),
				Pdf.text(" Read "),
				Pdf.inline_link(
					[
						Pdf.text("our published sustainability commitments, including the "),
						Pdf.strong([Pdf.text("2026 timber audit")]),
						Pdf.text(" and its appendix"),
					],
					"https://harbourfinch.example/sustainability",
				),
				Pdf.text(" before the next review."),
			]),
			Pdf.section([
				Pdf.rich_paragraph([
					Pdf.emphasis([Pdf.text("Nested "), Pdf.strong([Pdf.text("strong and "), Pdf.code("code")]), Pdf.text(" text")]),
					Pdf.text(" closes the summary."),
				]),
				Pdf.bullets(["Receiving hours are 7 am to 3 pm", "Dispatch follows confirmation order"]),
				Pdf.paragraph("A plain paragraph shares the page with rich text."),
			]),
		],
		language: "en-AU",
		title: "Quarterly summary${suffix}",
	})
}

paragraph_document : U64 -> Document
paragraph_document = |count| {
	var $contents = List.with_capacity(count + 1)
	$contents = $contents.append(Pdf.title("Inline scale"))
	var $index = 0
	while $index < count {
		label = (1 + $index).to_str()
		$contents = $contents.append(
			Pdf.rich_paragraph([
				Pdf.text("Entry ${label} reports "),
				Pdf.strong([Pdf.text("${label}.0%")]),
				Pdf.text(" growth in "),
				Pdf.emphasis([Pdf.text("Queensland")]),
				Pdf.text(" under "),
				Pdf.expansion("GST", "Goods and Services Tax"),
				Pdf.text(", supplied by "),
				Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
				Pdf.text(", counted in "),
				Pdf.code("WMS-${label}"),
				Pdf.text(", and quoted as "),
				Pdf.quote([Pdf.text("“steady”")]),
				Pdf.text("; see "),
				Pdf.inline_link([Pdf.text("the "), Pdf.emphasis([Pdf.text("entry ${label}")]), Pdf.text(" record")], "https://harbourfinch.example/entries/${label}"),
				Pdf.text("."),
			]),
		)
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Inline scale" })
}

ordered_document : U64 -> Document
ordered_document = |context| {
	suffix = if context == 0 "" else " ${context.to_str()}"
	Pdf.document({
		contents: [
			Pdf.rich_paragraph([
				Pdf.in_language("fr", [Pdf.text("Café")]),
				Pdf.in_language("zh-Hans", [Pdf.text("中")]),
				Pdf.emphasis([Pdf.text("PDF${suffix}")]),
			]),
		],
		language: "en-AU",
		title: "Ordered spans",
	})
}

register_faces : U64 -> Try({ policy : Font.PolicyId, registry : Font.Registry }, Fixture.EvidenceError)
register_faces = |context| {
	limits = if context == 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	latin = match Font.Registry.empty.register(caller_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	cjk = match latin.registry.register(cjk_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	configured = match cjk.registry.with_policy([latin.face, cjk.face]) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	Ok({ policy: configured.policy, registry: configured.registry })
}

evidence : Document, Theme, Faces -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document, theme, faces| evidence_with_limits(document, theme, faces, pipeline_limits)

## `evidence` under explicit pipeline limits (a document with a table needs
## scene paths for its rules).
evidence_with_limits : Document, Theme, Faces, KernelFacadePipeline.Limits -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence_with_limits = |document, theme, faces, limits| {
	options = match faces {
		BuiltInFace => Pdf.Options.{ theme: theme }
		Policy(policy) => Pdf.Options.{ theme: theme, fonts: Registered(policy.registry) }
	}
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	authoring = Document.normalize(document)
	plan = KernelFacadeSemantics.Plan.build(authoring, semantic_limits) ? |_| EvidenceFailure
	work = KernelFacadeSemantics.Plan.work(plan)
	semantic_work = KernelSemantics.Plan.work(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))

	## Work comes from the default theme: themed inline colors change only
	## paint facts, never shaping, line, page, or fragment counts.
	pipeline = match faces {
		BuiltInFace => {
			font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
			KernelFacadePipeline.Plan.build(authoring, font, Theme.default, page_size, descriptor, limits) ? |_| EvidenceFailure
		}
		Policy(policy) => KernelFacadePipeline.Plan.build_ordered(authoring, policy, theme, page_size, descriptor, limits) ? |_| EvidenceFailure
	}
	flow = KernelFacadePipeline.Plan.work(pipeline)
	Ok({
		bytes,
		work: [
			work.node_writes,
			work.inline_elements,
			work.inline_leaves,
			work.content_writes,
			work.occurrence_writes,
			semantic_work.node_visits,
			semantic_work.containment_edges,
			flow.shaped_runs,
			flow.lines,
			flow.final_runs,
			flow.fragments,
			flow.pages,
			bytes.len(),
		],
	})
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

rejects : Document, Conformance.DiagnosticCode, Str, Str -> U64
rejects = |document, expected_code, expected_feature, expected_path| match Pdf.to_bytes(document) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == [expected_path] 1 else 0
	_ => 0
}

nest_emphasis : List(Pdf.Inline), U64 -> Pdf.Inline
nest_emphasis = |inner, depth| {
	var $inline = Pdf.emphasis(inner)
	var $level = 1
	while $level < depth {
		$inline = Pdf.emphasis([$inline])
		$level = $level + 1
	}
	$inline
}

## Each document differs from a valid authoring in one inline fact. Every
## rejection is transactional: a stable code, the inline's authored path,
## and no bytes.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Inline negatives" else "guarded"
	document = |contents| Pdf.document({ contents, language: "en-AU", title })
	offset = U64.mod_by(context, 1)
	lead = Pdf.paragraph("Lead")
	uri = "https://harbourfinch.example/"
	checks = [
		rejects(document([lead, Pdf.rich_paragraph([])]), InvalidRelationship, "semantics.inline_empty", "contents[1]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Lead "), Pdf.emphasis([Pdf.text("")])])]), InvalidRelationship, "semantics.inline_empty", "contents[1].inlines[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.strong([]), Pdf.text("after")])]), InvalidRelationship, "semantics.inline_empty", "contents[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("See "), Pdf.inline_link([], uri)])]), InvalidRelationship, "semantics.link_text_empty", "contents[1].inlines[1]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.inline_link([Pdf.text("outer "), Pdf.emphasis([Pdf.inline_link([Pdf.text("inner")], uri)])], uri)])]), InvalidRelationship, "semantics.nested_link", "contents[1].inlines[0].inlines[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Deep "), nest_emphasis([Pdf.text("text")], 9 + offset)])]), BudgetExceeded, "semantics.inline_depth", "contents[1].inlines[1]${Str.repeat(".inlines[0]", 8)}"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.in_language("fr_CA", [Pdf.text("Québec")])])]), InvalidLanguage, "semantics.language_tag", "contents[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Visit "), Pdf.inline_link([Pdf.text("the site")], "harbourfinch example")])]), InvalidRelationship, "semantics.link_uri", "contents[1].inlines[1]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Greek "), Pdf.in_language("el", [Pdf.text("Ωμέγα")])])]), FontCoverageMissing, "text.unsupported_script", "contents[1].inlines[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Cafe"), Pdf.emphasis([Pdf.text("\u(301)")])])]), FontCoverageMissing, "text.unsupported_cluster", "contents[1].inlines[0]"),
		rejects(document([lead, Pdf.paragraph("Customer شركة الشمال")]), FontCoverageMissing, "text.unsupported_script", "contents[1]"),
		rejects(document([lead, Pdf.paragraph("Address 北京")]), FontCoverageMissing, "text.coverage_missing", "contents[1]"),
		rejects(document([lead, Pdf.paragraph("Cafe\u(301) crème")]), FontCoverageMissing, "text.unsupported_cluster", "contents[1]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Ship to "), Pdf.strong([Pdf.text("北京")])])]), FontCoverageMissing, "text.coverage_missing", "contents[1].inlines[1].inlines[0]"),
		rejects(document([lead, Pdf.bullet_list([Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Soft\u(AD)hyphen")])])])]), FontCoverageMissing, "text.coverage_missing", "contents[1].items[0].contents[0].inlines[0]"),
		rejects(document([Pdf.section([Pdf.heading(1, "Grouped"), Pdf.rich_paragraph([Pdf.text("Empty "), Pdf.strong([])])])]), InvalidRelationship, "semantics.inline_empty", "contents[0].contents[1].inlines[1]"),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	unknown = match Pdf.to_bytes(document([Pdf.rich_paragraph([Pdf.text("Go to${Str.repeat(" ", offset)} "), Pdf.inline_internal_link([Pdf.text("nowhere")], "missing")])])) {
		Err(InvalidNavigation(UnknownDestinationName({ annotation: 0 }))) => 1
		_ => return Err(MissingRejection(passed))
	}

	## The deepest accepted inline nesting is the facade bound itself.
	boundary = Pdf.to_bytes(document([Pdf.title("Boundary"), Pdf.rich_paragraph([Pdf.text("Deep "), nest_emphasis([Pdf.text("text")], 8 + offset)])])) ? |_| EvidenceFailure
	carrier = Pdf.to_bytes(document([Pdf.title("Inline carrier"), Pdf.rich_paragraph([Pdf.text("A "), Pdf.strong([Pdf.text("valid")]), Pdf.text(" rich paragraph.")])])) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed + unknown, boundary.len(), carrier.len()] })
}

pipeline_limits : KernelFacadePipeline.Limits
pipeline_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 100000, max_namespaces: 2, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 100000, max_occurrences: 2048, max_pages: 1024 }),
	navigation: KernelNavigation.standard_limits,
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
			max_key_probes: 1000000,
			max_lines: 1000000,
			max_runs: 2048,
			max_table_slots: 8192,
			max_templates: 2048,
		}),
		max_blocks: 2048,
		max_runs: 2048,
	}),
	output: KernelFacadeOutput.Limits.make({
		content: KernelContent.Limits.make({ max_content_bytes: 16000000, max_content_streams: 1024 }),
		font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 10000 }),
		images: KernelImage.Limits.make({ max_decoded_bytes: 67108864, max_encoded_bytes: 67108864, max_height: 16384, max_markers: 4096, max_resources: 2048, max_width: 16384 }),
		max_objects: 65536,
		objects: KernelObjectPlan.Limits.make({ max_objects: 65527, max_pages: 1024 }),
		structure: KernelTaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 1000000, max_unicode_mappings: 10000, max_unicode_scalars: 1000000 }),
			object_limits: object_limits,
		}),
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 1000000, max_content_bytes: 16000000, max_mappings: 10000, max_placements: 0, max_source_scalars: 1000000 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 2048,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: 2048, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 2, max_tags: KernelSrgbProfile.tag_count }),
		max_commands: 2000000,
		max_groups: 1000000,
		max_page_group_edges: 1000000,
		max_pages: 1024,
		scene: KernelScene.Limits.make({ max_commands: 2000000, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1000000, max_pages: 1024, max_path_segments: 0, max_paths: 0 }),
	}),
	semantics: KernelFacadeSemantics.Limits.make({
		max_container_depth: 16,
		max_content_spine: 8192,
		max_inline_depth: 8,
		max_nodes: 4096,
		max_occurrences: 2048,
		max_properties: 2048,
		max_source_inputs: 2048,
		semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 2, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
		sources: KernelFacadeSources.Limits.make({
			max_hash_probes: 1000000,
			max_inputs: 2048,
			max_source_bytes: 1000000,
			max_source_scalars: 1000000,
			max_table_slots: 8192,
			max_unique_sources: 2048,
			unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
		}),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2048, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 2048 }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 2048, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
})

## The rich-inline limits with scene paths for the shared-source table's
## rules.
shared_source_limits : KernelFacadePipeline.Limits
shared_source_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 100000, max_namespaces: 2, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 100000, max_occurrences: 2048, max_pages: 1024 }),
	navigation: KernelNavigation.standard_limits,
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
			max_key_probes: 1000000,
			max_lines: 1000000,
			max_runs: 2048,
			max_table_slots: 8192,
			max_templates: 2048,
		}),
		max_blocks: 2048,
		max_runs: 2048,
	}),
	output: KernelFacadeOutput.Limits.make({
		content: KernelContent.Limits.make({ max_content_bytes: 16000000, max_content_streams: 1024 }),
		font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 10000 }),
		images: KernelImage.Limits.make({ max_decoded_bytes: 67108864, max_encoded_bytes: 67108864, max_height: 16384, max_markers: 4096, max_resources: 2048, max_width: 16384 }),
		max_objects: 65536,
		objects: KernelObjectPlan.Limits.make({ max_objects: 65527, max_pages: 1024 }),
		structure: KernelTaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 1000000, max_unicode_mappings: 10000, max_unicode_scalars: 1000000 }),
			object_limits: object_limits,
		}),
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 1000000, max_content_bytes: 16000000, max_mappings: 10000, max_placements: 0, max_source_scalars: 1000000 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 2048,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: 2048, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 2, max_tags: KernelSrgbProfile.tag_count }),
		max_commands: 2000000,
		max_groups: 1000000,
		max_page_group_edges: 1000000,
		max_pages: 1024,
		scene: KernelScene.Limits.make({ max_commands: 2000000, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1000000, max_pages: 1024, max_path_segments: 1000000, max_paths: 1000000 }),
	}),
	semantics: KernelFacadeSemantics.Limits.make({
		max_container_depth: 16,
		max_content_spine: 8192,
		max_inline_depth: 8,
		max_nodes: 4096,
		max_occurrences: 2048,
		max_properties: 2048,
		max_source_inputs: 2048,
		semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 2, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
		sources: KernelFacadeSources.Limits.make({
			max_hash_probes: 1000000,
			max_inputs: 2048,
			max_source_bytes: 1000000,
			max_source_scalars: 1000000,
			max_table_slots: 8192,
			max_unique_sources: 2048,
			unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
		}),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2048, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 2048 }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 2048, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
})

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 1000000,
	max_byte_string_bytes: 1048576,
	max_byte_strings: 65536,
	max_dictionary_entries: 1000000,
	max_direct_depth: 8,
	max_name_bytes: 8192,
	max_names: 100000,
	max_objects: 65536,
	max_payload_bytes: 16000000,
	max_payloads: 100000,
	max_streams: 100000,
	max_text_string_bytes: 1000000,
	max_text_strings: 16384,
	max_values: 1000000,
}

semantic_limits : KernelFacadeSemantics.Limits
semantic_limits = KernelFacadeSemantics.Limits.make({
	max_container_depth: 16,
	max_content_spine: 8192,
	max_inline_depth: 8,
	max_nodes: 4096,
	max_occurrences: 2048,
	max_properties: 2048,
	max_source_inputs: 2048,
	semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 2, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 1000000,
		max_inputs: 2048,
		max_source_bytes: 1000000,
		max_source_scalars: 1000000,
		max_table_slots: 8192,
		max_unique_sources: 2048,
		unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2048, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 2048 }),
})
