import pdf.Document
import pdf.KernelNavigation
import pdf.Pdf

## Property fuzzing for the public navigation surface: named destinations, link
## annotations, outlines, and page labels authored through `Pdf.*` and sealed by
## `Pdf.to_bytes`.
##
## Navigation validation runs five stages in a fixed order - destinations, name
## ordering, annotations, outline, then labels - and each stage returns on its
## first rejection. The stages therefore mask one another: a single malformed
## URI hides every outline and label fault in the same document, and a
## duplicated destination name hides the URI fault behind it. A generated
## document that carries several faults cannot be asked which one it "should"
## report, so `deterministic_navigation` asserts only what holds for every
## document whatever its faults:
##
## - the same document sealed twice yields the identical error or the identical
##   bytes, so authored navigation is a pure function of the authoring,
## - a rejected document emits nothing through either output entrypoint, so
##   rejection stays transactional,
## - and an accepted document produces a non-empty file.
##
## Naming a variant needs a document with exactly one fault, which is what
## `single_fault` builds: every case below starts from one valid authoring and
## changes one navigation fact, so the stage that rejects it is the stage under
## test and the reported variant and location are fully determined.
NavigationTargets :: [].{
	Label : { page_code : U8, prefix : U8, start_number : U64, style : U8 }
	Outline : { depth_code : U8, destination : U8, open : U8, title : U8 }
	Section : { kind : U8, name : U8, uri : U8, words : Str }
	Input : {
		arm : U8,
		bulk : U8,
		labels : List(Label),
		outline : List(Outline),
		sections : List(Section),
		text : Str,
	}

	## Seal one generated document twice and check the contracts that survive
	## stage masking. Typed rejection is an ordinary outcome here; only an
	## unrepeatable result, a rejection that still reaches the chunked encoder,
	## or an accepted document with no bytes is a failure.
	deterministic_navigation : Input -> Bool
	deterministic_navigation = |input| {
		document = generated_document(input)
		first = Pdf.to_bytes(document)
		second = Pdf.to_bytes(document)
		if !results_agree(first, second) {
			return False
		}
		match first {

			## The buffered entrypoint rejected the authoring, so the chunked
			## entrypoint must refuse to hand out an encoder rather than emit a
			## prefix of a file that navigation validation already refused.
			Err(_) => match Pdf.to_chunks(document) {
				Err(_) => True
				Ok(_) => False
			}
			Ok(bytes) => bytes.len() > 0
		}
	}

	## One deliberately faulted authoring per case, each differing from
	## `base_authoring` in exactly one navigation fact, plus the accepted
	## boundary cases that prove the neighbouring value is still legal. The
	## limit-derived expectations read their numbers from
	## `KernelNavigation.standard_limit_values`, so a changed bound moves the
	## property with the package instead of failing against a stale literal.
	single_fault : U8 -> Bool
	single_fault = |code| match code.to_u64() % fault_cases {

		## The unfaulted base. Every case below is this authoring with one fact
		## changed, so a failure here means the fault table proves nothing.
		0 => accepted(authored(base_authoring))

		## Destination names. The name is changed in the heading, the internal
		## link, and the outline entry together, so an unresolvable name is not a
		## second fault riding along with the first.
		1 => rejected(with_name(""), |error| error == DestinationNameEmpty({ destination: 0 }))
		2 => rejected(with_name("al pha"), |error| error == DestinationNameInvalidByte({ destination: 0, offset: 2 }))

		## A byte above 0x7E is as invalid as a byte below 0x21; the first
		## lead byte of this name's U+00E1 is 0xC3.
		3 => rejected(with_name("alphá"), |error| error == DestinationNameInvalidByte({ destination: 0, offset: 4 }))
		4 => rejected(
			with_name(name_over_limit),
			|error| error == DestinationNameTooLong({ attempted: max_name_bytes + 1, destination: 0, limit: max_name_bytes }),
		)
		5 => rejected(
			authored({ ..base_authoring, extra: [Pdf.destination_paragraph("alpha", "A second alpha")] }),
			|error| error == DuplicateDestinationName({ first: 0, second: 1 }),
		)

		## Only the internal link moves off the defined name, so the outline
		## entry still resolves and the annotation stage is the one that rejects.
		6 => rejected(authored({ ..base_authoring, target: "missing" }), |error| error == UnknownDestinationName({ annotation: 0 }))

		## Link annotation URIs. The external link is annotation 1 because the
		## internal link precedes it in the authored block order.
		7 => rejected(with_uri(""), |error| error == UriEmpty({ annotation: 1 }))
		8 => rejected(with_uri("example.org/plain"), |error| error == UriMissingScheme({ annotation: 1 }))
		9 => rejected(with_uri("https://example.org/a b"), |error| error == UriInvalidByte({ annotation: 1, offset: 21 }))

		## A percent escape truncated by the end of the URI and a percent escape
		## with non-hex digits are distinct paths to the same variant.
		10 => rejected(with_uri("https://example.org/%2"), |error| error == UriInvalidPercentEncoding({ annotation: 1, offset: 20 }))
		11 => rejected(with_uri("https://example.org/%zz"), |error| error == UriInvalidPercentEncoding({ annotation: 1, offset: 20 }))
		12 => rejected(
			with_uri(uri_over_limit),
			|error| error == UriTooLong({ annotation: 1, attempted: max_uri_bytes + 1, limit: max_uri_bytes }),
		)

		## Outline shape. The authored preorder is the emitted sibling order, so
		## the first entry roots the tree and a deeper entry may only descend one
		## level at a time; a descent of any size is legal and is exercised by
		## the accepted ladder case below.
		13 => rejected(
			with_outline_entries([{ depth: 1, destination: "alpha", open: True, title: "Alpha" }]),
			|error| error == OutlineFirstDepthNonzero({ depth: 1 }),
		)
		14 => rejected(
			with_outline_entries([
				{ depth: 0, destination: "alpha", open: True, title: "Alpha" },
				{ depth: 2, destination: "alpha", open: True, title: "Skipped" },
			]),
			|error| error == OutlineDepthJump({ actual: 2, entry: 1, previous: 0 }),
		)

		## The depth check is `depth >= max_outline_depth`, so climbing one level
		## per entry reaches the first rejected depth exactly at entry
		## `max_outline_depth`.
		15 => rejected(
			with_outline_entries(ladder(max_outline_depth)),
			|error| error == OutlineDepthLimitExceeded({ attempted: max_outline_depth, entry: max_outline_depth, limit: max_outline_depth }),
		)
		16 => rejected(
			with_outline_entries([{ depth: 0, destination: "alpha", open: True, title: "" }]),
			|error| error == OutlineTitleEmpty({ entry: 0 }),
		)
		17 => rejected(
			with_outline_entries([{ depth: 0, destination: "alpha", open: True, title: title_over_limit }]),
			|error| error == OutlineTitleTooLong({ attempted: max_outline_title_bytes + 1, entry: 0, limit: max_outline_title_bytes }),
		)
		18 => rejected(
			with_outline_entries([{ depth: 0, destination: "missing", open: True, title: "Alpha" }]),
			|error| error == OutlineDestinationUnknown({ entry: 0 }),
		)

		## The entry-count check precedes every per-entry check, so a list of
		## otherwise valid entries is the cheapest way to reach this variant.
		19 => rejected(
			with_outline_entries(List.repeat(valid_outline_entry, max_outline_entries + 1)),
			|error| error == OutlineEntryLimitExceeded({ attempted: max_outline_entries + 1, limit: max_outline_entries }),
		)

		## Page labels. Ranges start at physical page zero and ascend strictly.
		20 => rejected(
			with_labels([{ prefix: "", start_number: 1, start_page: 1, style: DecimalArabic }]),
			|error| error == LabelStartPageNotZero({ start: 1 }),
		)
		21 => rejected(
			with_labels([valid_label_range, valid_label_range]),
			|error| error == LabelRangeNotAscending({ range: 1 }),
		)

		## Every style numbers from one; zero has no representation in any of
		## them, including the prefix-only style.
		22 => rejected(
			with_labels([{ prefix: "", start_number: 0, start_page: 0, style: RomanUpper }]),
			|error| error == LabelStartNumberZero({ range: 0 }),
		)
		23 => rejected(
			with_labels([{ prefix: "part-", start_number: 2, start_page: 0, style: NoNumber }]),
			|error| error == LabelNumberWithoutStyle({ range: 0 }),
		)
		24 => rejected(
			with_labels([{ prefix: prefix_over_limit, start_number: 1, start_page: 0, style: DecimalArabic }]),
			|error| error == LabelPrefixTooLong({ attempted: max_label_prefix_bytes + 1, limit: max_label_prefix_bytes, range: 0 }),
		)

		## The page count is a layout outcome rather than an authored fact, so
		## this case starts a range beyond any page count the facade can produce
		## and checks the located fields it does own.
		25 => rejected(
			with_labels([valid_label_range, { prefix: "", start_number: 1, start_page: beyond_pages, style: DecimalArabic }]),
			|error| match error {
				LabelStartPageOutOfRange(details) => details.attempted == beyond_pages and details.range == 1
				_ => False
			},
		)
		26 => rejected(
			with_labels(List.repeat(valid_label_range, max_label_ranges + 1)),
			|error| error == LabelLimitExceeded({ attempted: max_label_ranges + 1, limit: max_label_ranges }),
		)

		## Accepted boundaries. Each of the six label styles must survive
		## validation and emission, not merely validation, so these seal a whole
		## file rather than stopping at the typed rejection.
		27 => accepted(with_labels([{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }]))
		28 => accepted(with_labels([{ prefix: "app-", start_number: 3, start_page: 0, style: LettersLower }]))
		29 => accepted(with_labels([{ prefix: "", start_number: 26, start_page: 0, style: LettersUpper }]))
		30 => accepted(with_labels([{ prefix: "cover", start_number: 1, start_page: 0, style: NoNumber }]))
		31 => accepted(with_labels([{ prefix: "", start_number: 4, start_page: 0, style: RomanLower }]))
		32 => accepted(with_labels([{ prefix: "vol-", start_number: 9, start_page: 0, style: RomanUpper }]))

		## One level below the depth limit is the deepest legal outline, and the
		## descent back to the root in `ladder` is a legal jump of any size.
		33 => accepted(with_outline_entries(ladder(max_outline_depth - 1)))

		## A name and a URI of exactly their limit are legal; the one-byte-longer
		## forms above are the first rejected lengths.
		_ => accepted(
			authored({
				..base_authoring,
				name: name_at_limit,
				outline: [{ depth: 0, destination: name_at_limit, open: True, title: "Alpha" }],
				target: name_at_limit,
				uri: uri_at_limit,
			}),
		)
	}
}

## The number of cases in the fault table, including the accepted boundaries.
fault_cases : U64
fault_cases = 35

## Navigation bounds are read from the package rather than restated, so a
## property can never claim a boundary the pipeline no longer enforces.
max_label_prefix_bytes : U64
max_label_prefix_bytes = KernelNavigation.standard_limit_values.max_label_prefix_bytes

max_label_ranges : U64
max_label_ranges = KernelNavigation.standard_limit_values.max_label_ranges

max_name_bytes : U64
max_name_bytes = KernelNavigation.standard_limit_values.max_name_bytes

max_outline_depth : U64
max_outline_depth = KernelNavigation.standard_limit_values.max_outline_depth

max_outline_entries : U64
max_outline_entries = KernelNavigation.standard_limit_values.max_outline_entries

max_outline_title_bytes : U64
max_outline_title_bytes = KernelNavigation.standard_limit_values.max_outline_title_bytes

max_uri_bytes : U64
max_uri_bytes = KernelNavigation.standard_limit_values.max_uri_bytes

## A page index no automatic pagination can reach: the facade caps a document at
## 1024 pages, so a label range starting here is out of range for every document
## the generator can author.
beyond_pages : U64
beyond_pages = 4096

## One valid authoring, expressed as the facts a fault case overrides. The
## document carries a named destination, an internal link to it, an external
## link, an outline entry, and a page-label range, so every validation stage has
## something to check and any stage can be the one that rejects.
Authoring : {
	extra : List(Document.Block),
	labels : List(Document.PageLabelRange),
	name : Str,
	outline : List(Document.OutlineEntry),
	target : Str,
	uri : Str,
}

base_authoring : Authoring
base_authoring = {
	extra: [],
	labels: [valid_label_range],
	name: "alpha",
	outline: [valid_outline_entry],
	target: "alpha",
	uri: "https://example.org/",
}

valid_label_range : Document.PageLabelRange
valid_label_range = { prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }

valid_outline_entry : Document.OutlineEntry
valid_outline_entry = { depth: 0, destination: "alpha", open: True, title: "Alpha" }

authored : Authoring -> Document
authored = |authoring| {
	contents = [
		Pdf.title("Navigation fuzz"),
		Pdf.destination_heading(authoring.name, 1, "Alpha section"),
		Pdf.paragraph("Body text carrying the destination anchor for this document."),
		Pdf.internal_link("Jump to alpha", authoring.target),
		Pdf.link("Home page", authoring.uri),
	]
	document = Pdf.document({
		contents: contents.concat(authoring.extra),
		language: "en-AU",
		title: "Navigation fuzz",
	})
	document.with_outline(authoring.outline).with_page_labels(authoring.labels)
}

## Rename the destination everywhere it is authored. A name fault is then the
## only fault in the document: the internal link and the outline entry still
## name the destination that exists, whatever that name now is.
with_name : Str -> Document
with_name = |name| authored({
	..base_authoring,
	name: name,
	outline: [{ depth: 0, destination: name, open: True, title: "Alpha" }],
	target: name,
})

with_uri : Str -> Document
with_uri = |uri| authored({ ..base_authoring, uri: uri })

with_outline_entries : List(Document.OutlineEntry) -> Document
with_outline_entries = |entries| authored({ ..base_authoring, outline: entries })

with_labels : List(Document.PageLabelRange) -> Document
with_labels = |ranges| authored({ ..base_authoring, labels: ranges })

## A one-level-per-entry climb from the root to `deepest`, then a single descent
## back to the root. The descent is legal at any size and keeps the ladder a
## complete outline rather than a chain.
ladder : U64 -> List(Document.OutlineEntry)
ladder = |deepest| {
	var $entries = []
	var $depth = 0
	while $depth <= deepest {
		$entries = $entries.append({ depth: $depth, destination: "alpha", open: True, title: "Rung" })
		$depth = $depth + 1
	}
	$entries.append({ depth: 0, destination: "alpha", open: False, title: "Root again" })
}

## `Pdf.Error` carries diagnostic batches that have no equality, so two
## rejections are compared by the fact that both are rejections and, where the
## rejection is the navigation rejection this target is about, by the exact
## typed error and location.
results_agree : Try(List(U8), Pdf.Error), Try(List(U8), Pdf.Error) -> Bool
results_agree = |first, second| match (first, second) {
	(Ok(left), Ok(right)) => left == right
	(Err(InvalidNavigation(left)), Err(InvalidNavigation(right))) => left == right
	(Err(InvalidNavigation(_)), Err(_)) => False
	(Err(_), Err(InvalidNavigation(_))) => False
	(Err(_), Err(_)) => True
	_ => False
}

## Sealing a valid authoring twice must reproduce the file byte for byte.
accepted : Document -> Bool
accepted = |document| match (Pdf.to_bytes(document), Pdf.to_bytes(document)) {
	(Ok(first), Ok(second)) => first.len() > 0 and first == second
	_ => False
}

## A rejected authoring must fail as a typed navigation rejection carrying the
## expected variant and location. Repeatability is the free-form property's
## business; this one is about which stage speaks.
rejected : Document, (Document.NavigationError -> Bool) -> Bool
rejected = |document, matches| match Pdf.to_bytes(document) {
	Err(InvalidNavigation(error)) => matches(error)
	_ => False
}

generated_document : NavigationTargets.Input -> Document
generated_document = |input| {
	document = Pdf.document({
		contents: blocks_for(input),
		language: "en-AU",
		title: "Navigation fuzz",
	})
	document.with_outline(outline_for(input)).with_page_labels(labels_for(input))
}

## A leading title keeps every generated document non-empty, so pagination
## always produces the page that a label range and an annotation need.
blocks_for : NavigationTargets.Input -> List(Document.Block)
blocks_for = |input| {
	var $blocks = [Pdf.title("Navigation fuzz")]
	var $index = 0
	while $index < input.sections.len() {
		section = list_at(input.sections, $index)

		## Empty body text is rejected before navigation runs, which would mask
		## the whole surface under test, so a generated block always says
		## something.
		text = if section.words.is_empty() "Generated body text" else section.words
		name = name_for(section.name, input.text)
		$blocks = $blocks.append(
			match section.kind % 6 {
				0 => Pdf.paragraph(text)
				1 => Pdf.heading(section.uri % 6 + 1, text)
				2 => Pdf.destination_heading(name, section.uri % 6 + 1, text)
				3 => Pdf.destination_paragraph(name, text)
				4 => Pdf.internal_link(text, name)
				_ => Pdf.link(text, uri_for(section.uri, input.text))
			},
		)
		$index = $index + 1
	}
	$blocks
}

## Outline depth is generated as a step from the previous depth rather than as
## an independent number: a ladder that mostly holds or climbs one level reaches
## the destination lookup and the depth limit, where independent depths would
## almost always be rejected by the first jump.
outline_for : NavigationTargets.Input -> List(Document.OutlineEntry)
outline_for = |input| {
	if input.bulk % 16 == 1 or input.bulk % 16 == 3 {
		return List.repeat(valid_outline_entry, max_outline_entries + 1)
	}
	var $entries = []
	var $previous = 0
	var $index = 0
	while $index < input.outline.len() {
		entry = list_at(input.outline, $index)
		depth = depth_for(entry.depth_code, $previous)
		$entries = $entries.append({
			depth: depth,
			destination: name_for(entry.destination, input.text),
			open: entry.open % 2 == 1,
			title: title_for(entry.title, input.text),
		})
		$previous = depth
		$index = $index + 1
	}
	$entries
}

## Label starts are generated the same way and for the same reason: ranges must
## ascend strictly from page zero, so a step from the previous start is the only
## shape that reaches the prefix, numbering, and style checks behind the
## ordering check.
labels_for : NavigationTargets.Input -> List(Document.PageLabelRange)
labels_for = |input| {
	if input.bulk % 16 == 2 or input.bulk % 16 == 3 {
		return List.repeat(valid_label_range, max_label_ranges + 1)
	}
	var $ranges = []
	var $previous = 0
	var $index = 0
	while $index < input.labels.len() {
		label = list_at(input.labels, $index)
		start_page = start_page_for(label.page_code, $previous)
		$ranges = $ranges.append({
			prefix: prefix_for(label.prefix, input.text),
			start_number: label.start_number,
			start_page: start_page,
			style: style_for(label.style),
		})
		$previous = start_page
		$index = $index + 1
	}
	$ranges
}

depth_for : U8, U64 -> U64
depth_for = |code, previous| match code % 8 {
	0 => 0
	1 => previous
	2 => previous + 1
	3 => previous + 2
	4 => if previous == 0 0 else previous - 1
	5 => max_outline_depth - 1
	6 => max_outline_depth
	_ => previous + 3
}

start_page_for : U8, U64 -> U64
start_page_for = |code, previous| match code % 6 {
	0 => 0
	1 => previous
	2 => previous + 1
	3 => previous + 2
	4 => if previous == 0 0 else previous - 1
	_ => beyond_pages
}

style_for : U8 -> Document.PageLabelStyle
style_for = |choice| match choice % 6 {
	0 => DecimalArabic
	1 => LettersLower
	2 => LettersUpper
	3 => NoNumber
	4 => RomanLower
	_ => RomanUpper
}

## Boundary-first pools. Uniform random strings almost never land on a limit or
## on a byte just outside the permitted range, and they never repeat a name, so
## the pools carry the empty, one-byte, at-limit, one-over-limit, and
## just-outside-the-permitted-byte forms explicitly and reuse a handful of
## ordinary names so that duplicates arise on their own. The generated string
## remains reachable as the last choice, which is what lets the fuzzer discover
## a form the pool did not anticipate.
name_for : U8, Str -> Str
name_for = |choice, generated| match choice % 10 {
	0 => ""
	1 => "a"
	2 => name_at_limit
	3 => name_over_limit
	4 => "al pha"
	5 => "alphá"
	6 => "alpha"
	7 => "beta"
	8 => "gamma"
	_ => generated
}

uri_for : U8, Str -> Str
uri_for = |choice, generated| match choice % 10 {
	0 => ""
	1 => "example.org/plain"
	2 => "https://example.org/a b"
	3 => "https://example.org/%2"
	4 => "https://example.org/%zz"
	5 => uri_at_limit
	6 => uri_over_limit
	7 => "https://example.org/"
	8 => "mailto:someone@example.org"
	_ => generated
}

title_for : U8, Str -> Str
title_for = |choice, generated| match choice % 6 {
	0 => ""
	1 => "Alpha"
	2 => "Beta"
	3 => title_at_limit
	4 => title_over_limit
	_ => generated
}

prefix_for : U8, Str -> Str
prefix_for = |choice, generated| match choice % 5 {
	0 => ""
	1 => "part-"
	2 => prefix_at_limit
	3 => prefix_over_limit
	_ => generated
}

name_at_limit : Str
name_at_limit = Str.repeat("n", max_name_bytes)

name_over_limit : Str
name_over_limit = Str.repeat("n", max_name_bytes + 1)

prefix_at_limit : Str
prefix_at_limit = Str.repeat("p", max_label_prefix_bytes)

prefix_over_limit : Str
prefix_over_limit = Str.repeat("p", max_label_prefix_bytes + 1)

title_at_limit : Str
title_at_limit = Str.repeat("t", max_outline_title_bytes)

title_over_limit : Str
title_over_limit = Str.repeat("t", max_outline_title_bytes + 1)

uri_at_limit : Str
uri_at_limit = uri_padded(max_uri_bytes)

uri_over_limit : Str
uri_over_limit = uri_padded(max_uri_bytes + 1)

## A syntactically valid URI padded to an exact byte length, so the length
## checks are reached by length alone rather than by a malformed remainder.
uri_padded : U64 -> Str
uri_padded = |length| {
	prefix = "https://example.org/"
	Str.concat(prefix, Str.repeat("p", length - Str.to_utf8(prefix).len()))
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense index"
	Ok(value) => value
}

## The unfaulted base authoring seals to a file. Every entry in the fault table
## is this document with one navigation fact changed, so this expectation is the
## floor the whole table stands on.
expect NavigationTargets.single_fault(0)

## Stage masking, stated as a test rather than only as a comment: this document
## carries a malformed URI, an unknown outline destination, an empty outline
## title, and a page-label range that does not start at page zero, and the
## annotation stage rejects it first because it runs before the outline and
## label stages. A property that asserted "the injected outline fault is
## reported" would be wrong here, which is why only the single-fault table
## names variants.
expect {
	masked = authored({
		..base_authoring,
		labels: [{ prefix: "", start_number: 1, start_page: 1, style: DecimalArabic }],
		outline: [{ depth: 0, destination: "missing", open: True, title: "" }],
		uri: "example.org/plain",
	})

	match Pdf.to_bytes(masked) {
		Err(InvalidNavigation(error)) => error == UriMissingScheme({ annotation: 1 })
		_ => Bool.False
	}
}

## The outline depth limit is exclusive, so a rung at the limit is the first
## rejected depth. Pinning the rejected side here keeps the off-by-one honest
## without sealing a whole file under `roc test`.
expect NavigationTargets.single_fault(15)

## A depth that skips a level is rejected wherever it appears, while a descent
## of any size is legal; both facts are checked by one authoring.
expect NavigationTargets.single_fault(14)
