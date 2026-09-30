import pdf.Conformance
import pdf.Document
import pdf.KernelBuiltInFont
import pdf.KernelFacadeLines
import pdf.KernelFacadePages
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFont
import pdf.KernelLineLayout
import pdf.KernelPageLayout
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Pdf
import pdf.Theme

## Lists, explicit breaks, keeps, and ranked layout policies through the
## public `Pdf` constructors.
##
## - `lists`: a numbered list nested three deep (decimal, bullet, lower
##   alpha) whose items hold paragraphs, a rich paragraph, a continuation
##   paragraph, and nested lists; an upper-Roman list; and the legacy
##   plain-text bullets, each `L` with its `ListNumbering`.
## - `breaks`: letterhead and address blocks with explicit line breaks, a
##   wrapping link across a line break, spacers, a signature block kept
##   together, and a page break before the schedule section.
## - `keeps`: a keep-together group that moves whole across a page boundary,
##   a required keep-with-next chain moved with its last block, a preferred
##   keep relaxed at an explicit break (R2), and a heading relaxed before a
##   group that can only share a page with it (R1).
## - `relaxations`: a one-line flow region where a preferred keep (R2), the
##   orphan minimum (R4), and the widow minimum (R5) are each relaxed and
##   reported.
## - `groups xN`: N keep-together groups each followed by a one-item list,
##   the scale pair for linear keep and list planning and pagination.
## - `heading_chain xN`: N consecutive headings, each preferring to keep with
##   the next, so no break satisfies R1: the adversarial pair proving the
##   page scan's candidate visits stay linear.
## - `atomic_negatives`: every list, break, and keep rejection with its
##   stable dotted code and authored path, and no bytes.
##
## Bytes come from `Pdf.to_bytes_with`. Work comes from one semantic
## planning pass and the shaping, line, and page stages over the same
## normalized authoring.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, InvalidScale, MissingRejection(U64)]

	lists : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	lists = |context| evidence(lists_document(context), Theme.default)

	breaks : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	breaks = |context| evidence(breaks_document(context), Theme.default)

	keeps : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	keeps = |context| evidence(keeps_document(context), Theme.default)

	relaxations : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	relaxations = |context| evidence(relaxations_document(context), one_line_theme)

	groups : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	groups = |count| {
		if count == 0 or count > 500 {
			return Err(InvalidScale)
		}
		evidence(groups_document(count), Theme.default)
	}

	heading_chain : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	heading_chain = |count| {
		if count == 0 or count > 1000 {
			return Err(InvalidScale)
		}
		evidence(heading_chain_document(count), Theme.default)
	}

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)
}

item : Str -> Pdf.ListItem
item = |text| Pdf.list_item([Pdf.paragraph(text)])

suffix_for : U64 -> Str
suffix_for = |context| if context == 0 "" else " (${context.to_str()})"

lists_document : U64 -> Document
lists_document = |context| Pdf.document({
	contents: [
		Pdf.title("Outlook priorities${suffix_for(context)}"),
		Pdf.heading(1, "4 Outlook"),
		Pdf.paragraph("Three priorities carry the operations plan into the next quarter."),
		Pdf.numbered_list(
			{ start: 1, style: Decimal },
			[
				item("Extend the certified timber programme to every active supplier."),
				Pdf.list_item([
					Pdf.rich_paragraph([Pdf.text("Open the second dispatch dock "), Pdf.emphasis([Pdf.text("before winter")]), Pdf.text(", in three stages:")]),
					Pdf.bullet_list([
						item("Pour and cure the concrete slab."),
						Pdf.list_item([
							Pdf.paragraph("Fit the loading equipment:"),
							Pdf.numbered_list({ start: 1, style: LowerAlpha }, [item("two dock levellers,"), item("one overhead door, and"), item("weather seals.")]),
						]),
						item("Commission the dock with two crews rostered."),
					]),
					Pdf.paragraph("The dock remains closed to deliveries until the final inspection has been signed off by the site manager."),
				]),
				item("Keep warranty claims below one per cent of units shipped."),
			],
		),
		Pdf.paragraph("The appendices follow the priorities."),
		Pdf.numbered_list({ start: 1, style: UpperRoman }, [item("Supplier register"), item("Freight rates"), item("Audit schedule")]),
		Pdf.bullets(["Plain-text bullets keep their generated disc", "and their ListNumbering attribute"]),
	],
	language: "en-AU",
	title: "Outlook priorities${suffix_for(context)}",
})

breaks_document : U64 -> Document
breaks_document = |context| Pdf.document({
	contents: [
		Pdf.division([
			Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])]),
			Pdf.rich_paragraph([
				Pdf.text("Level 3, 18 Wharf Street"),
				Pdf.line_break,
				Pdf.text("Hobart TAS 7000"),
				Pdf.line_break,
				Pdf.text("ABN 00 123 456 789"),
				Pdf.line_break,
				Pdf.text("accounts@harbourfinch.example · (03) 5550 0142"),
			]),
		]),
		Pdf.paragraph("21 September 2026${suffix_for(context)}"),
		Pdf.rich_paragraph([
			Pdf.text("Ms Priya Raman"),
			Pdf.line_break,
			Pdf.text("Operations Manager"),
			Pdf.line_break,
			Pdf.text("Northstar Cooperative Ltd"),
			Pdf.line_break,
			Pdf.text("42 Kestrel Parade"),
			Pdf.line_break,
			Pdf.text("Fremantle WA 6160"),
		]),
		Pdf.spacer(Layout.Unit.points(12)),
		Pdf.paragraph("Dear Ms Raman,"),
		Pdf.rich_paragraph([Pdf.text("Subject: "), Pdf.strong([Pdf.text("Extended warranty for your Level 2 to 5 fit-out")])]),
		Pdf.rich_paragraph([
			Pdf.text("Thank you for choosing Harbour & Finch for the fit-out of your offices. We are pleased to extend the warranty on every item we supplied to five years from the date of installation. You can read "),
			Pdf.inline_link([Pdf.text("the extended warranty terms"), Pdf.line_break, Pdf.text("on our website")], "https://www.harbourfinch.example/warranty"),
			Pdf.text(" at any time, and our team will contact you before each annual inspection."),
		]),
		Pdf.keep_together([
			Pdf.paragraph("Yours sincerely,"),
			Pdf.spacer(Layout.Unit.points(36)),
			Pdf.paragraph("Tom Finch"),
			Pdf.paragraph("Director, Harbour & Finch Pty Ltd"),
		]),
		Pdf.paragraph("Enclosure: Schedule 1, covered items"),
		Pdf.page_break,
		Pdf.section([
			Pdf.heading(1, "Schedule 1. Covered items"),
			Pdf.paragraph("Every desk frame, desktop, task chair, lamp, and cable tray supplied under purchase order PO 88213 is covered."),
		]),
	],
	language: "en-AU",
	title: "Letter to Northstar Cooperative about the warranty extension${suffix_for(context)}",
})

keeps_document : U64 -> Document
keeps_document = |context| Pdf.document({
	contents: [
		Pdf.title("Keeps${suffix_for(context)}"),
		Pdf.paragraph("The space below fills most of the first page, so the next group cannot fit beside it."),
		Pdf.spacer(Layout.Unit.points(560)),
		Pdf.paragraph("This paragraph still fits at the foot of the first page."),
		Pdf.keep_together([
			Pdf.paragraph("Yours sincerely,"),
			Pdf.spacer(Layout.Unit.points(36)),
			Pdf.paragraph("Tom Finch"),
			Pdf.paragraph("Director, Harbour & Finch Pty Ltd"),
		]),
		Pdf.paragraph("The signature block above moved whole to this page."),
		Pdf.spacer(Layout.Unit.points(548)),
		Pdf.keep_with_next(Required, Pdf.paragraph("Step one keeps with step two.")),
		Pdf.keep_with_next(Required, Pdf.paragraph("Step two keeps with step three.")),
		Pdf.paragraph("Step three ends the required chain, which moved as one unit."),
		Pdf.keep_with_next(Preferred, Pdf.paragraph("This paragraph prefers its successor, but an explicit break follows.")),
		Pdf.page_break,
		Pdf.heading(1, "A heading before a tall group"),
		Pdf.keep_together([
			Pdf.paragraph("The group opens here."),
			Pdf.spacer(Layout.Unit.points(640)),
			Pdf.paragraph("The group closes here."),
		]),
		Pdf.paragraph("The last paragraph follows the group."),
	],
	language: "en-AU",
	title: "Keeps${suffix_for(context)}",
})

## A flow region one body line tall.
one_line_theme : Theme
one_line_theme = Theme.with_page_margin(
	Theme.default,
	{
		bottom: Layout.Unit.points(754),
		left: Layout.Unit.points(72),
		right: Layout.Unit.points(72),
		top: Layout.Unit.points(72),
	},
)

relaxations_document : U64 -> Document
relaxations_document = |context| Pdf.document({
	contents: [
		Pdf.keep_with_next(Preferred, Pdf.paragraph("A preferred keep${suffix_for(context)}")),
		Pdf.paragraph("This paragraph wraps onto three lines in the one-line flow region, so no break can satisfy both its orphan minimum and its widow minimum; each relaxation is recorded with its rank, block, and page."),
	],
	language: "en-AU",
	title: "Relaxations${suffix_for(context)}",
})

groups_document : U64 -> Document
groups_document = |count| {
	var $contents = List.with_capacity(count * 2 + 1)
	$contents = $contents.append(Pdf.title("Keep groups"))
	var $index = 0
	while $index < count {
		label = (1 + $index).to_str()
		$contents = $contents.append(Pdf.keep_together([Pdf.paragraph("Group ${label} opens."), Pdf.paragraph("Group ${label} closes on the same page.")]))
		$contents = $contents.append(Pdf.bullet_list([item("Item ${label} follows its group.")]))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Keep groups" })
}

heading_chain_document : U64 -> Document
heading_chain_document = |count| {
	var $contents = List.with_capacity(count + 1)
	var $index = 0
	while $index < count {
		$contents = $contents.append(Pdf.heading(2, "Heading ${(1 + $index).to_str()}"))
		$index = $index + 1
	}
	$contents = $contents.append(Pdf.paragraph("The chain ends with this paragraph."))
	Pdf.document({ contents: $contents, language: "en-AU", title: "Heading chain" })
}

evidence : Document, Theme -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document, theme| {
	bytes = Pdf.to_bytes_with(document, Pdf.Options.with_theme(Pdf.Options.default, theme)) ? |_| EvidenceFailure
	authoring = Document.normalize(document)
	semantics = KernelFacadeSemantics.Plan.build(authoring, semantic_limits) ? |_| EvidenceFailure
	work = KernelFacadeSemantics.Plan.work(semantics)
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(semantics)))
	semantic_work = KernelSemantics.Plan.work(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(semantics)))
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	shape = KernelFacadeShape.Plan.build(authoring, KernelFacadeSemantics.Plan.block_ownership(semantics), store, source_store, font, theme, shape_limits) ? |_| EvidenceFailure
	lines = KernelFacadeLines.Plan.build(shape, source_store, page_size, theme, line_limits) ? |_| EvidenceFailure
	pages = KernelFacadePages.Plan.build(authoring, shape, lines, page_size, theme, page_limits) ? |_| EvidenceFailure
	page_work = KernelFacadePages.Plan.work(pages).page
	relaxed = KernelFacadePages.Plan.relaxations(pages)
	rank_count = |rank| relaxed.count_if(|relaxation| relaxation.rank == rank)
	Ok({
		bytes,
		work: [
			work.node_writes,
			work.lists,
			work.list_items,
			work.content_writes,
			work.occurrence_writes,
			semantic_work.max_semantic_depth,
			KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines)).len(),
			page_work.page_writes,
			page_work.fragment_writes,
			page_work.candidate_visits,
			rank_count(HeadingKeep),
			rank_count(AuthorKeep),
			rank_count(Orphan),
			rank_count(Widow),
			bytes.len(),
		],
	})
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

rejects : Document, Conformance.DiagnosticCode, Str, List(Str) -> U64
rejects = |document, expected_code, expected_feature, expected_paths| match Pdf.to_bytes(document) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == expected_paths 1 else 0
	_ => 0
}

nest_lists : U64 -> Pdf.ListItem
nest_lists = |depth| {
	var $item = item("Deepest")
	var $level = 1
	while $level < depth {
		$item = Pdf.list_item([Pdf.paragraph("Level"), Pdf.bullet_list([$item])])
		$level = $level + 1
	}
	$item
}

## Each document differs from a valid authoring in one list, break, or keep
## fact. Every rejection is transactional: a stable code, the authored path
## of each participating source, and no bytes.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Layout negatives" else "guarded"
	document = |contents| Pdf.document({ contents, language: "en-AU", title })
	offset = U64.mod_by(context, 1)
	lead = Pdf.paragraph("Lead")
	tall = Layout.Unit.points(700 + offset.to_i64_wrap())
	checks = [
		rejects(document([lead, Pdf.keep_together([Pdf.paragraph("Yours sincerely,"), Pdf.spacer(tall), Pdf.paragraph("Tom Finch")])]), LayoutConstraintViolated, "layout.keep_conflict", ["contents[1]", "contents[1].contents[0]", "contents[1].contents[2]"]),
		rejects(document([lead, Pdf.keep_together([Pdf.paragraph("Items"), Pdf.page_break, Pdf.paragraph("Payment")])]), LayoutConstraintViolated, "layout.keep_conflict", ["contents[1].contents[1]", "contents[1]"]),
		rejects(document([lead, Pdf.keep_with_next(Required, Pdf.paragraph("Kept")), Pdf.page_break, Pdf.paragraph("Next")]), LayoutConstraintViolated, "layout.keep_conflict", ["contents[1]", "contents[2]"]),
		rejects(document([lead, Pdf.keep_with_next(Required, Pdf.paragraph("Nothing follows"))]), LayoutConstraintViolated, "layout.keep_conflict", ["contents[1]"]),
		rejects(document([lead, Pdf.keep_with_next(Required, Pdf.paragraph("Kept")), Pdf.keep_together([Pdf.paragraph("Tall"), Pdf.spacer(tall), Pdf.paragraph("group")])]), LayoutConstraintViolated, "layout.keep_conflict", ["contents[2]", "contents[2].contents[0]", "contents[2].contents[2]"]),
		rejects(document([lead, Pdf.heading(1, Str.repeat("An unsplittable heading that never fits. ", 150 + offset))]), LayoutConstraintViolated, "layout.oversize_block", ["contents[1]"]),
		rejects(document([lead, Pdf.keep_together([])]), LayoutConstraintViolated, "layout.keep_empty", ["contents[1]"]),
		rejects(document([lead, Pdf.keep_with_next(Preferred, Pdf.spacer(Layout.Unit.points(12)))]), LayoutConstraintViolated, "layout.keep_empty", ["contents[1]"]),
		rejects(document([lead, Pdf.spacer(Layout.Unit.points(-12)), Pdf.paragraph("After")]), LayoutConstraintViolated, "layout.spacer_negative", ["contents[1]"]),
		rejects(document([Pdf.page_break, lead]), LayoutConstraintViolated, "layout.page_break_position", ["contents[0]"]),
		rejects(document([lead, Pdf.page_break]), LayoutConstraintViolated, "layout.page_break_position", ["contents[1]"]),
		rejects(document([lead, Pdf.section([Pdf.page_break, Pdf.page_break, Pdf.paragraph("After")])]), LayoutConstraintViolated, "layout.page_break_position", ["contents[1].contents[1]"]),
		rejects(document([lead, Pdf.bullet_list([])]), InvalidRelationship, "semantics.list_empty", ["contents[1]"]),
		rejects(document([lead, Pdf.bullet_list([item("One"), Pdf.list_item([])])]), InvalidRelationship, "semantics.list_item_empty", ["contents[1].items[1]"]),
		rejects(document([lead, Pdf.bullet_list([Pdf.list_item([Pdf.bullet_list([item("Nested first")])])])]), InvalidRelationship, "semantics.list_item_content", ["contents[1].items[0]"]),
		rejects(document([lead, Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("One"), Pdf.heading(2, "Not in a list item")])])]), InvalidRelationship, "semantics.list_item_content", ["contents[1].items[0].contents[1]"]),
		rejects(document([lead, Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("One"), Pdf.section([Pdf.paragraph("Grouped")])])])]), InvalidRelationship, "semantics.list_item_content", ["contents[1].items[0].contents[1]"]),
		rejects(document([lead, Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("One"), Pdf.page_break, Pdf.paragraph("Two")])])]), InvalidRelationship, "semantics.list_item_content", ["contents[1].items[0].contents[1]"]),
		rejects(document([lead, Pdf.bullet_list([nest_lists(5 + offset)])]), BudgetExceeded, "semantics.list_depth", ["contents[1]${Str.repeat(".items[0].contents[1]", 4)}"]),
		rejects(document([lead, Pdf.numbered_list({ start: 3998 + offset, style: UpperRoman }, [item("MMMCMXCVIII"), item("MMMCMXCIX"), item("Beyond")])]), InvalidRelationship, "semantics.list_numbering", ["contents[1]"]),
		rejects(document([lead, Pdf.numbered_list({ start: 0, style: LowerAlpha }, [item("No letter zero")])]), InvalidRelationship, "semantics.list_numbering", ["contents[1]"]),
		rejects(document([lead, Pdf.numbered_list({ start: 1000 + offset, style: Decimal }, [item("A wide label")])]), LayoutConstraintViolated, "layout.list_label_width", ["contents[1].items[0]"]),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.line_break, Pdf.text("Leading")])]), InvalidRelationship, "semantics.line_break_position", ["contents[1].inlines[0]"]),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Trailing"), Pdf.strong([Pdf.text("text")]), Pdf.line_break])]), InvalidRelationship, "semantics.line_break_position", ["contents[1].inlines[2]"]),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("One"), Pdf.emphasis([Pdf.line_break, Pdf.line_break, Pdf.text("Two")])])]), InvalidRelationship, "semantics.line_break_position", ["contents[1].inlines[1].inlines[1]"]),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}

	## The deepest accepted list nesting is the facade bound itself.
	boundary = Pdf.to_bytes(document([Pdf.title("Boundary"), Pdf.bullet_list([nest_lists(4 + offset)])])) ? |_| EvidenceFailure
	carrier = Pdf.to_bytes(document([Pdf.title("Layout carrier"), Pdf.bullet_list([item("A valid list item.")])])) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed, boundary.len(), carrier.len()] })
}

shape_limits : KernelFacadeShape.Limits
shape_limits = KernelFacadeShape.Limits.make({ max_requests: 2048, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) })

line_limits : KernelFacadeLines.Limits
line_limits = KernelFacadeLines.Limits.make({
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
})

page_limits : KernelFacadePages.Limits
page_limits = KernelFacadePages.Limits.make({
	max_blocks: 2048,
	max_rows: 1000000,
	page: KernelPageLayout.Limits.make({ max_blocks: 2048, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
})

## The facade's semantic-planning limits (package/Pdf.roc).
semantic_limits : KernelFacadeSemantics.Limits
semantic_limits = KernelFacadeSemantics.Limits.make({
	max_container_depth: 16,
	max_content_spine: 8192,
	max_inline_depth: 8,
	max_nodes: 4096,
	max_occurrences: 2048,
	max_properties: 2048,
	max_source_inputs: 2048,
	semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 1, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 48 }),
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
