import fuzz.Model
import pdf.Document

DocumentBuilderModel := [].{}

Action : [
	AddTitle,
	AddHeading,
	AddParagraph,
	AddParagraphs,
	AddEmptyParagraphs,
	AddBullets,
	AddEmptyBullets,
	AddUriLink,
	AddInternalLink,
	AddDestinationHeading(U8),
	AddDestinationParagraph,
]

Kind : [
	Title,
	Heading(U8),
	Paragraph,
	Bullet({ item : U64, list : U64 }),
	Link(Str),
	InternalLink(Str),
	DestinationHeading({ level : U8, name : Str }),
	DestinationParagraph(Str),
	Other,
]

Leaf : { kind : Kind, parent : U64, text : Str }

Reference : { leaves : List(Leaf), authored : U64, sources : U64, next_list : U64 }

World : { builder : Document.Builder, reference : Reference, history : List(Action) }

metadata = { language: "en-AU", title: "Builder model" }

choices : List(Action)
choices = [
	AddTitle,
	AddHeading,
	AddParagraph,
	AddParagraphs,
	AddEmptyParagraphs,
	AddBullets,
	AddEmptyBullets,
	AddUriLink,
	AddInternalLink,
	AddDestinationHeading(1),
	AddDestinationHeading(9),
	AddDestinationHeading(255),
	AddDestinationParagraph,
]

machine : Model.Machine(World, Action)
machine = {
	init: { builder: Document.builder(metadata), reference: { leaves: [], authored: 0, sources: 0, next_list: 0 }, history: [] },
	actions: |world| if (world.history.len() < 3) choices else [],
	step: |world, action| {
		builder: apply_builder(world.builder, action),
		reference: apply_reference(world.reference, action),
		history: world.history.append(action),
	},
	rules: [
		Model.always("normalized leaves preserve order, text, and identity", same_leaves),
		Model.always("compact counts match the authored blocks and strings", |world|
			world.builder.stats() == { blocks: world.reference.authored, text_sources: world.reference.sources }),
		Model.sometimes("a paragraph batch precedes bullets", |world| world.history == [AddParagraphs, AddBullets]),
		Model.sometimes("empty bullets precede a populated list", |world| world.history == [AddEmptyBullets, AddBullets]),
		Model.sometimes("links and destinations share the string store", |world| world.history == [AddUriLink, AddInternalLink, AddDestinationHeading(1)]),
	],
}

apply_builder : Document.Builder, Action -> Document.Builder
apply_builder = |builder, action| match action {
	AddTitle => builder.add_title("Title")
	AddHeading => builder.add_heading({ level: 6, text: "Heading" })
	AddParagraph => builder.add_paragraph("Paragraph")
	AddParagraphs => builder.add_paragraphs(["Batch first", "Batch second"])
	AddEmptyParagraphs => builder.add_paragraphs([])
	AddBullets => builder.add_bullets(["Bullet first", "Bullet second"])
	AddEmptyBullets => builder.add_bullets([])
	AddUriLink => builder.add_link({ text: "Link", uri: "https://example.com/model" })
	AddInternalLink => builder.add_internal_link({ text: "Jump", destination: "local" })
	AddDestinationHeading(level) => builder.add_destination_heading({ level, name: "section", text: "Section" })
	AddDestinationParagraph => builder.add_destination_paragraph({ name: "detail", text: "Detail" })
}

apply_reference : Reference, Action -> Reference
apply_reference = |reference, action| match action {
	AddTitle => append_leaf(reference, Title, "Title", 1)
	AddHeading => append_leaf(reference, Heading(6), "Heading", 1)
	AddParagraph => append_leaf(reference, Paragraph, "Paragraph", 1)
	AddParagraphs => append_leaf(append_leaf(reference, Paragraph, "Batch first", 1), Paragraph, "Batch second", 1)
	AddEmptyParagraphs => reference
	AddBullets => {
		list = reference.next_list
		{
			authored: reference.authored + 1,
			leaves: reference.leaves.append(leaf(Bullet({ item: 0, list }), "Bullet first")).append(leaf(Bullet({ item: 1, list }), "Bullet second")),
			next_list: list + 1,
			sources: reference.sources + 2,
		}
	}
	AddEmptyBullets => { ..reference, authored: reference.authored + 1, next_list: reference.next_list + 1 }
	AddUriLink => append_leaf(reference, Link("https://example.com/model"), "Link", 2)
	AddInternalLink => append_leaf(reference, InternalLink("local"), "Jump", 2)
	AddDestinationHeading(level) => append_leaf(reference, DestinationHeading({ level, name: "section" }), "Section", 2)
	AddDestinationParagraph => append_leaf(reference, DestinationParagraph("detail"), "Detail", 2)
}

append_leaf : Reference, Kind, Str, U64 -> Reference
append_leaf = |reference, kind, text, sources| {
	..reference,
	authored: reference.authored + 1,
	leaves: reference.leaves.append(leaf(kind, text)),
	sources: reference.sources + sources,
}

leaf : Kind, Str -> Leaf
leaf = |kind, text| { kind, parent: 0, text }

same_leaves : World -> Bool
same_leaves = |world| {
	normalized = Document.normalize(world.builder.finish())
	normalized.language == metadata.language and normalized.metadata_title == metadata.title and
		normalized.blocks.map(observe) == world.reference.leaves
}

observe : Document.NormalizedBlock -> Leaf
observe = |block| {
	kind = match block.kind {
		Title => Title
		Heading(level) => Heading(level)
		Paragraph => Paragraph
		Bullet(position) => Bullet(position)
		Link({ uri }) => Link(uri)
		InternalLink({ destination }) => InternalLink(destination)
		DestinationHeading(facts) => DestinationHeading(facts)
		DestinationParagraph({ name }) => DestinationParagraph(name)
		_ => Other
	}
	{ kind, parent: block.parent, text: block.text }
}

expect {
	# Ordered actions are a lossless key for the bounded, deterministic machine.
	# Depth four proves exhaustion after the final states at depth three.
	report = Model.explore(machine, { depth: 4, key: |world| world.history, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 2380 and report.steps == 2379 and report.depth == 3 and report.reached.len() == 3
}
