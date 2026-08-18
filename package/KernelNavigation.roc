## Validated navigation facts for the Gate 4 navigation/annotation slice:
## named internal destinations, URI and internal GoTo link annotations,
## document outline entries, and page-label ranges. Authoring supplies these
## as typed values; this boundary validates them once against the closed
## supported subset and returns dense normalized stores that later stages
## consume verbatim. No later stage re-parses names, re-derives ordering, or
## recovers a fact from serialized bytes.
##
## The supported subset is deliberately closed. Destination names are
## non-empty printable-ASCII byte strings with deterministic byte ordering
## and exact-equality duplicate rejection. Link actions are exactly the URI
## and internal GoTo forms; remote-file destinations, launch/JavaScript/named
## actions, and every other action type have no representation here. Every
## internal destination names both a semantic structure target and an
## explicit layout-anchor occurrence, so lowering can emit the paired `/SD`
## and `/D` facts required by the pinned issue-140/162 resolutions.
## Annotation geometry uses the checked fixed-point layout unit; quadrilateral
## spans are ranges into one flat quad buffer; keyboard order is an explicit
## dense per-page permutation independent of logical spine order.
import Document
import Layout
import Scene
import Semantics

KernelNavigation :: [].{

	## A link annotation's normal appearance is either absent or a reference
	## to a validated Form XObject from the shared scene/resource pipeline.
	## Rollover and down appearances have no representation.
	Appearance : [NoAppearance, NormalAppearance(Scene.FormId)]

	Description : [NoDescription, WithDescription(Str)]

	## Authored actions reference destinations by their authored name; the
	## closed union is the whole supported action vocabulary.
	AuthoredAction : [GoToName(Str), Uri(Str)]

	## One axis-aligned quadrilateral in layout units. The emission order of
	## the eight `/QuadPoints` numbers is pinned by the lowering policy:
	## top-left, top-right, bottom-left, bottom-right.
	Quad : {
		x_left : Layout.Unit,
		x_right : Layout.Unit,
		y_bottom : Layout.Unit,
		y_top : Layout.Unit,
	}

	AnnotationInput : {
		action : AuthoredAction,
		appearance : Appearance,
		description : Description,
		keyboard_order : U64,
		page : Semantics.PageId,
		print : Bool,
		quads : List(Quad),
		rect : Layout.Rect,
	}

	DestinationInput : {
		anchor : Semantics.OccurrenceId,
		name : Str,
		target : Semantics.NodeId,
	}

	Input : {
		annotations : List(AnnotationInput),
		destinations : List(DestinationInput),
		outline : List(Document.OutlineEntry),
		page_labels : List(Document.PageLabelRange),
	}

	## Earlier-stage counts the navigation input is validated against. The
	## annotation list must be one-to-one with the semantic annotation store;
	## deeper ownership agreement is validated by the semantic and tagging
	## stages that own those facts.
	Context : {
		forms : U64,
		nodes : U64,
		occurrences : U64,
		pages : U64,
		semantic_annotations : U64,
	}

	Limits :: {
		max_annotations : U64,
		max_description_bytes : U64,
		max_destinations : U64,
		max_label_prefix_bytes : U64,
		max_label_ranges : U64,
		max_name_bytes : U64,
		max_outline_depth : U64,
		max_outline_entries : U64,
		max_outline_title_bytes : U64,
		max_quads : U64,
		max_uri_bytes : U64,
	}.{
		make : {
			max_annotations : U64,
			max_description_bytes : U64,
			max_destinations : U64,
			max_label_prefix_bytes : U64,
			max_label_ranges : U64,
			max_name_bytes : U64,
			max_outline_depth : U64,
			max_outline_entries : U64,
			max_outline_title_bytes : U64,
			max_quads : U64,
			max_uri_bytes : U64,
		} -> Limits
		make = |limits| Limits.(limits)

		max_outline_depth : Limits -> U64
		max_outline_depth = |Limits.(limits)| limits.max_outline_depth
	}

	## Normalized actions reference the dense destination identity resolved
	## through the deterministic name registry.
	Action : [GoToDestination(Semantics.DestinationId), UriAction(Semantics.Range)]

	Annotation : {
		action : Action,
		appearance : Appearance,
		description : Description,
		keyboard_order : U64,
		page : Semantics.PageId,
		print : Bool,
		quads : Semantics.Range,
		rect : Layout.Rect,
	}

	Destination : {
		anchor : Semantics.OccurrenceId,
		id : Semantics.DestinationId,
		name : Semantics.Range,
		target : Semantics.NodeId,
	}

	OutlineEntry : {
		depth : U64,
		destination : Semantics.DestinationId,
		open : Bool,
		title : Str,
	}

	LabelRange : {
		prefix : Str,
		start_number : U64,
		start_page : U64,
		style : Document.PageLabelStyle,
	}

	## Dense normalized navigation stores. `name_order` lists destination
	## indices in unsigned byte order of their names; `page_annotations` lists
	## annotation indices in the documented total annotation order
	## (page index, then keyboard order), with `page_annotation_offsets` as
	## its per-page prefix sums.
	Store : {
		annotations : List(Annotation),
		destinations : List(Destination),
		label_ranges : List(LabelRange),
		name_bytes : List(U8),
		name_order : List(U64),
		outline_entries : List(OutlineEntry),
		page_annotation_offsets : List(U64),
		page_annotations : List(U64),
		quad_points : List(Quad),
		uri_bytes : List(U8),
	}

	Work : {
		annotations_checked : U64,
		destinations_checked : U64,
		label_ranges_checked : U64,
		name_bytes_checked : U64,
		name_ordering_steps : U64,
		outline_entries_checked : U64,
		quads_checked : U64,
		uri_bytes_checked : U64,
	}

	## Post-layout anchor facts: one optional anchor rectangle per layout
	## fragment, dense by fragment identity, produced from the prepared
	## fragment/page geometry after pagination. Destination resolution is the
	## only consumer; nothing re-derives geometry from scenes or content.
	AnchorRect : [AnchorAt(Layout.Rect), NoAnchor]

	## One destination resolved to both of its paired targets: the semantic
	## structure element for `/SD` and the exact page-space point for `/D`.
	## Both derive from one authored destination record, so a mismatched pair
	## is unrepresentable downstream of a successful resolution.
	ResolvedDestination : {
		left : Layout.Unit,
		page : Semantics.PageId,
		structure_element : Semantics.StructureElementId,
		top : Layout.Unit,
	}

	ResolveWork : { anchor_lookups : U64, destinations_resolved : U64 }

	## Resolve every destination after layout: the anchor occurrence's first
	## layout fragment supplies the page and geometry, and the occurrence's
	## owning node must be exactly the destination's semantic target. A
	## destination whose anchor has no resolvable fragment geometry is
	## rejected; an `/SD`-only link cannot be emitted.
	resolve : Store, Semantics.Store, List(Semantics.NodeId), List(AnchorRect) -> Try({ destinations : List(ResolvedDestination), work : ResolveWork }, Document.NavigationError)
	resolve = |store, semantics, occurrence_owners, anchor_rects| {
		count = store.destinations.len()
		var $resolved = List.with_capacity(count)
		var $lookups = 0
		var $index = 0
		while $index < count {
			destination = list_at(store.destinations, $index)
			anchor_index = destination.anchor.index()
			if anchor_index >= semantics.occurrences.len() or anchor_index >= occurrence_owners.len() {
				return Err(DestinationAnchorOutOfRange({ attempted: anchor_index, destination: $index, occurrences: semantics.occurrences.len() }))
			}
			if destination.target.index() >= semantics.nodes.len() {
				return Err(DestinationTargetOutOfRange({ attempted: destination.target.index(), destination: $index, nodes: semantics.nodes.len() }))
			}
			owner = list_at(occurrence_owners, anchor_index)
			if owner.index() != destination.target.index() {
				return Err(DestinationTargetMismatch({ anchor_owner: owner.index(), destination: $index, target: destination.target.index() }))
			}
			occurrence = list_at(semantics.occurrences, anchor_index)
			if occurrence.fragments.length() == 0 {
				return Err(UnresolvedDestinationAnchor({ destination: $index }))
			}
			fragment_id = list_at(semantics.occurrence_fragments, occurrence.fragments.start())
			fragment_index = fragment_id.index()
			$lookups = $lookups + 1
			if fragment_index >= anchor_rects.len() {
				return Err(UnresolvedDestinationAnchor({ destination: $index }))
			}
			rect = match list_at(anchor_rects, fragment_index) {
				NoAnchor => return Err(UnresolvedDestinationAnchor({ destination: $index }))
				AnchorAt(anchor_rect) => anchor_rect
			}
			if rect.size.height.raw() < 0 {
				return Err(InvalidAnchorGeometry({ destination: $index }))
			}
			top_raw = I64.plus_try(rect.origin.y.raw(), rect.size.height.raw()) ? |_| InvalidAnchorGeometry({ destination: $index })
			node = list_at(semantics.nodes, destination.target.index())
			fragment = list_at(semantics.fragments, fragment_index)
			$resolved = $resolved.append({
				left: rect.origin.x,
				page: fragment.page,
				structure_element: node.structure_element,
				top: Layout.Unit.from_raw(top_raw),
			})
			$index = $index + 1
		}
		Ok({ destinations: $resolved, work: { anchor_lookups: $lookups, destinations_resolved: count } })
	}

	validate : Input, Context, Limits -> Try({ store : Store, work : Work }, Document.NavigationError)
	validate = |input, context, Limits.(limits)| {
		destinations = validate_destinations(input.destinations, context, limits)?
		ordering = order_names(destinations.store, input.destinations.len())?
		annotations = validate_annotations(input.annotations, destinations.store, ordering.order, context, limits)?
		outline = validate_outline(input.outline, destinations.store, ordering.order, limits)?
		labels = validate_labels(input.page_labels, context, limits)?
		Ok({
			store: {
				annotations: annotations.annotations,
				destinations: destinations.store.destinations,
				label_ranges: labels.ranges,
				name_bytes: destinations.store.name_bytes,
				name_order: ordering.order,
				outline_entries: outline.entries,
				page_annotation_offsets: annotations.page_offsets,
				page_annotations: annotations.page_order,
				quad_points: annotations.quad_points,
				uri_bytes: annotations.uri_bytes,
			},
			work: {
				annotations_checked: input.annotations.len(),
				destinations_checked: input.destinations.len(),
				label_ranges_checked: input.page_labels.len(),
				name_bytes_checked: destinations.name_bytes_checked,
				name_ordering_steps: ordering.steps + annotations.lookup_steps + outline.lookup_steps,
				outline_entries_checked: input.outline.len(),
				quads_checked: annotations.quads_checked,
				uri_bytes_checked: annotations.uri_bytes_checked,
			},
		})
	}
}

DestinationStore : {
	destinations : List(KernelNavigation.Destination),
	name_bytes : List(U8),
}

validate_destinations : List(KernelNavigation.DestinationInput), KernelNavigation.Context, { max_annotations : U64, max_description_bytes : U64, max_destinations : U64, max_label_prefix_bytes : U64, max_label_ranges : U64, max_name_bytes : U64, max_outline_depth : U64, max_outline_entries : U64, max_outline_title_bytes : U64, max_quads : U64, max_uri_bytes : U64 } -> Try({ name_bytes_checked : U64, store : DestinationStore }, Document.NavigationError)
validate_destinations = |inputs, context, limits| {
	count = inputs.len()
	if count > limits.max_destinations {
		return Err(DestinationLimitExceeded({ attempted: count, limit: limits.max_destinations }))
	}
	var $destinations = List.with_capacity(count)
	var $name_bytes = []
	var $bytes_checked = 0
	var $index = 0
	while $index < count {
		input = list_at(inputs, $index)
		bytes = Str.to_utf8(input.name)
		length = bytes.len()
		if length == 0 {
			return Err(DestinationNameEmpty({ destination: $index }))
		}
		if length > limits.max_name_bytes {
			return Err(DestinationNameTooLong({ attempted: length, destination: $index, limit: limits.max_name_bytes }))
		}
		var $offset = 0
		while $offset < length {
			byte = list_at(bytes, $offset)
			if byte < 0x21 or byte > 0x7E {
				return Err(DestinationNameInvalidByte({ destination: $index, offset: $offset }))
			}
			$offset = $offset + 1
		}
		$bytes_checked = $bytes_checked + length
		if input.target.index() >= context.nodes {
			return Err(DestinationTargetOutOfRange({ attempted: input.target.index(), destination: $index, nodes: context.nodes }))
		}
		if input.anchor.index() >= context.occurrences {
			return Err(DestinationAnchorOutOfRange({ attempted: input.anchor.index(), destination: $index, occurrences: context.occurrences }))
		}
		start = $name_bytes.len()
		$name_bytes = $name_bytes.concat(bytes)
		$destinations = $destinations.append({
			anchor: input.anchor,
			id: Semantics.DestinationId.from_index($index),
			name: Semantics.Range.from_start_and_length(start, length),
			target: input.target,
		})
		$index = $index + 1
	}
	Ok({
		name_bytes_checked: $bytes_checked,
		store: { destinations: $destinations, name_bytes: $name_bytes },
	})
}

## Deterministic bottom-up merge sort of destination indices by unsigned name
## byte order, shorter key first on a shared prefix. Stable, worst-case
## `O(n log n)` on sorted, reverse-sorted, and equal input; equal names are
## detected by one adjacent pass afterwards.
order_names : DestinationStore, U64 -> Try({ order : List(U64), steps : U64 }, Document.NavigationError)
order_names = |store, count| {
	var $order = List.with_capacity(count)
	var $seed = 0
	while $seed < count {
		$order = $order.append($seed)
		$seed = $seed + 1
	}
	var $steps = 0
	var $width = 1
	while $width < count {
		var $merged = List.with_capacity(count)
		var $left_start = 0
		while $left_start < count {
			right_start = U64.min($left_start + $width, count)
			right_end = U64.min(right_start + $width, count)
			var $left = $left_start
			var $right = right_start
			while $left < right_start or $right < right_end {
				take_left = if $left >= right_start {
					False
				} else if $right >= right_end {
					True
				} else {
					$steps = $steps + 1
					match compare_names(store, list_at($order, $left), list_at($order, $right)) {
						Greater => False
						Less | Equal => True
					}
				}
				if take_left {
					$merged = $merged.append(list_at($order, $left))
					$left = $left + 1
				} else {
					$merged = $merged.append(list_at($order, $right))
					$right = $right + 1
				}
			}
			$left_start = right_end
		}
		$order = $merged
		$width = $width * 2
	}
	var $adjacent = 1
	while $adjacent < count {
		first = list_at($order, $adjacent - 1)
		second = list_at($order, $adjacent)
		$steps = $steps + 1
		match compare_names(store, first, second) {
			Equal => return Err(DuplicateDestinationName({ first, second }))
			Less => {}
			Greater => {
				crash "destination name ordering invariant failed"
			}
		}
		$adjacent = $adjacent + 1
	}
	Ok({ order: $order, steps: $steps })
}

compare_names : DestinationStore, U64, U64 -> [Equal, Greater, Less]
compare_names = |store, left, right| {
	left_range = list_at(store.destinations, left).name
	right_range = list_at(store.destinations, right).name
	shared = U64.min(left_range.length(), right_range.length())
	var $offset = 0
	var $verdict = Equal
	while $offset < shared and $verdict == Equal {
		left_byte = list_at(store.name_bytes, left_range.start() + $offset)
		right_byte = list_at(store.name_bytes, right_range.start() + $offset)
		if left_byte < right_byte {
			$verdict = Less
		} else if left_byte > right_byte {
			$verdict = Greater
		} else {
			$offset = $offset + 1
		}
	}
	match $verdict {
		Equal => if left_range.length() < right_range.length() {
			Less
		} else if left_range.length() > right_range.length() {
			Greater
		} else {
			Equal
		}
		Less => Less
		Greater => Greater
	}
}

## Binary search over the sorted name order; returns the destination index
## whose name equals the probe bytes.
find_name : DestinationStore, List(U64), List(U8) -> { result : [Found(U64), Missing], steps : U64 }
find_name = |store, order, probe| {
	var $low = 0
	var $high = order.len()
	var $steps = 0
	var $found = Missing
	while $low < $high and $found == Missing {
		middle = $low + ($high - $low) // 2
		candidate = list_at(order, middle)
		$steps = $steps + 1
		match compare_name_to_bytes(store, candidate, probe) {
			Equal => {
				$found = Found(candidate)
			}
			Less => {
				$low = middle + 1
			}
			Greater => {
				$high = middle
			}
		}
	}
	{ result: $found, steps: $steps }
}

compare_name_to_bytes : DestinationStore, U64, List(U8) -> [Equal, Greater, Less]
compare_name_to_bytes = |store, index, probe| {
	range = list_at(store.destinations, index).name
	shared = U64.min(range.length(), probe.len())
	var $offset = 0
	var $verdict = Equal
	while $offset < shared and $verdict == Equal {
		name_byte = list_at(store.name_bytes, range.start() + $offset)
		probe_byte = list_at(probe, $offset)
		if name_byte < probe_byte {
			$verdict = Less
		} else if name_byte > probe_byte {
			$verdict = Greater
		} else {
			$offset = $offset + 1
		}
	}
	match $verdict {
		Equal => if range.length() < probe.len() {
			Less
		} else if range.length() > probe.len() {
			Greater
		} else {
			Equal
		}
		Less => Less
		Greater => Greater
	}
}

AnnotationOutcome : {
	annotations : List(KernelNavigation.Annotation),
	lookup_steps : U64,
	page_offsets : List(U64),
	page_order : List(U64),
	quad_points : List(KernelNavigation.Quad),
	quads_checked : U64,
	uri_bytes : List(U8),
	uri_bytes_checked : U64,
}

validate_annotations : List(KernelNavigation.AnnotationInput), DestinationStore, List(U64), KernelNavigation.Context, { max_annotations : U64, max_description_bytes : U64, max_destinations : U64, max_label_prefix_bytes : U64, max_label_ranges : U64, max_name_bytes : U64, max_outline_depth : U64, max_outline_entries : U64, max_outline_title_bytes : U64, max_quads : U64, max_uri_bytes : U64 } -> Try(AnnotationOutcome, Document.NavigationError)
validate_annotations = |inputs, destinations, name_order, context, limits| {
	count = inputs.len()
	if count > limits.max_annotations {
		return Err(AnnotationLimitExceeded({ attempted: count, limit: limits.max_annotations }))
	}
	if count != context.semantic_annotations {
		return Err(AnnotationCountMismatch({ navigation: count, semantics: context.semantic_annotations }))
	}
	var $annotations = List.with_capacity(count)
	var $quad_points = []
	var $uri_bytes = []
	var $quads_checked = 0
	var $uri_bytes_checked = 0
	var $lookup_steps = 0
	var $page_counts = List.repeat(0, context.pages)
	var $index = 0
	while $index < count {
		input = list_at(inputs, $index)
		if input.page.index() >= context.pages {
			return Err(AnnotationPageOutOfRange({ annotation: $index, attempted: input.page.index(), pages: context.pages }))
		}
		rect = validate_rect(input.rect, $index)?
		quad_count = input.quads.len()
		if quad_count == 0 {
			return Err(QuadsEmpty({ annotation: $index }))
		}
		attempted_quads = match U64.plus_try($quads_checked, quad_count) {
			Ok(value) => value
			Err(_) => return Err(QuadLimitExceeded({ attempted: quad_count, limit: limits.max_quads }))
		}
		if attempted_quads > limits.max_quads {
			return Err(QuadLimitExceeded({ attempted: attempted_quads, limit: limits.max_quads }))
		}
		quad_start = $quad_points.len()
		var $quad = 0
		while $quad < quad_count {
			quad = list_at(input.quads, $quad)
			if quad.x_left.raw() >= quad.x_right.raw() or quad.y_bottom.raw() >= quad.y_top.raw() {
				return Err(InvalidQuad({ annotation: $index, quad: $quad }))
			}
			if quad.x_left.raw() < rect.x_left or quad.x_right.raw() > rect.x_right or quad.y_bottom.raw() < rect.y_bottom or quad.y_top.raw() > rect.y_top {
				return Err(QuadOutsideRect({ annotation: $index, quad: $quad }))
			}
			$quad_points = $quad_points.append(quad)
			$quad = $quad + 1
		}
		$quads_checked = attempted_quads
		action = match input.action {
			Uri(uri) => {
				uri_bytes = validate_uri(uri, $index, limits.max_uri_bytes)?
				start = $uri_bytes.len()
				$uri_bytes = $uri_bytes.concat(uri_bytes)
				$uri_bytes_checked = $uri_bytes_checked + uri_bytes.len()
				UriAction(Semantics.Range.from_start_and_length(start, uri_bytes.len()))
			}
			GoToName(name) => {
				probe = Str.to_utf8(name)
				lookup = find_name(destinations, name_order, probe)
				$lookup_steps = $lookup_steps + lookup.steps
				match lookup.result {
					Found(destination) => GoToDestination(Semantics.DestinationId.from_index(destination))
					Missing => return Err(UnknownDestinationName({ annotation: $index }))
				}
			}
		}
		match input.description {
			NoDescription => {}
			WithDescription(text) => {
				bytes = Str.to_utf8(text).len()
				if bytes == 0 {
					return Err(DescriptionEmpty({ annotation: $index }))
				}
				if bytes > limits.max_description_bytes {
					return Err(DescriptionTooLong({ annotation: $index, attempted: bytes, limit: limits.max_description_bytes }))
				}
			}
		}
		match input.appearance {
			NoAppearance => {}
			NormalAppearance(form) => if form.index() >= context.forms {
				return Err(AppearanceFormOutOfRange({ annotation: $index, attempted: form.index(), forms: context.forms }))
			}
		}
		page_index = input.page.index()
		$page_counts = list_set($page_counts, page_index, list_at($page_counts, page_index) + 1)
		$annotations = $annotations.append({
			action,
			appearance: input.appearance,
			description: input.description,
			keyboard_order: input.keyboard_order,
			page: input.page,
			print: input.print,
			quads: Semantics.Range.from_start_and_length(quad_start, quad_count),
			rect: input.rect,
		})
		$index = $index + 1
	}
	ordered = order_page_annotations($annotations, $page_counts, context.pages)?
	Ok({
		annotations: $annotations,
		lookup_steps: $lookup_steps,
		page_offsets: ordered.offsets,
		page_order: ordered.order,
		quad_points: $quad_points,
		quads_checked: $quads_checked,
		uri_bytes: $uri_bytes,
		uri_bytes_checked: $uri_bytes_checked,
	})
}

RectBounds : { x_left : I64, x_right : I64, y_bottom : I64, y_top : I64 }

validate_rect : Layout.Rect, U64 -> Try(RectBounds, Document.NavigationError)
validate_rect = |rect, annotation| {
	width = rect.size.width.raw()
	height = rect.size.height.raw()
	if width <= 0 or height <= 0 {
		return Err(InvalidAnnotationRect({ annotation: annotation }))
	}
	x_left = rect.origin.x.raw()
	y_bottom = rect.origin.y.raw()
	x_right = I64.plus_try(x_left, width) ? |_| InvalidAnnotationRect({ annotation: annotation })
	y_top = I64.plus_try(y_bottom, height) ? |_| InvalidAnnotationRect({ annotation: annotation })
	Ok({ x_left, x_right, y_bottom, y_top })
}

## The accepted URI subset is the RFC 3986 character set with a required
## scheme and checked percent-encoding: printable ASCII from the unreserved,
## reserved, and percent-encoded productions, no spaces, no controls, no
## non-ASCII bytes. The URI is recorded for the reader; nothing dereferences
## it.
validate_uri : Str, U64, U64 -> Try(List(U8), Document.NavigationError)
validate_uri = |uri, annotation, max_bytes| {
	bytes = Str.to_utf8(uri)
	length = bytes.len()
	if length == 0 {
		return Err(UriEmpty({ annotation: annotation }))
	}
	if length > max_bytes {
		return Err(UriTooLong({ annotation: annotation, attempted: length, limit: max_bytes }))
	}
	first = list_at(bytes, 0)
	if !is_ascii_alpha(first) {
		return Err(UriMissingScheme({ annotation: annotation }))
	}
	var $offset = 1
	var $scheme_end = 0
	while $offset < length and $scheme_end == 0 {
		byte = list_at(bytes, $offset)
		if byte == ':' {
			$scheme_end = $offset
		} else if is_ascii_alpha(byte) or is_ascii_digit(byte) or byte == '+' or byte == '-' or byte == '.' {
			$offset = $offset + 1
		} else {
			return Err(UriMissingScheme({ annotation: annotation }))
		}
	}
	if $scheme_end == 0 {
		return Err(UriMissingScheme({ annotation: annotation }))
	}
	var $index = $scheme_end
	while $index < length {
		byte = list_at(bytes, $index)
		if byte == '%' {
			if $index + 2 >= length {
				return Err(UriInvalidPercentEncoding({ annotation: annotation, offset: $index }))
			}
			if !is_ascii_hex(list_at(bytes, $index + 1)) or !is_ascii_hex(list_at(bytes, $index + 2)) {
				return Err(UriInvalidPercentEncoding({ annotation: annotation, offset: $index }))
			}
			$index = $index + 3
		} else if is_uri_byte(byte) {
			$index = $index + 1
		} else {
			return Err(UriInvalidByte({ annotation: annotation, offset: $index }))
		}
	}
	Ok(bytes)
}

## Counting sort of annotation indices into the documented total order:
## page index, then the explicit keyboard order, which must be a dense
## `0..count-1` permutation on every page.
order_page_annotations : List(KernelNavigation.Annotation), List(U64), U64 -> Try({ offsets : List(U64), order : List(U64) }, Document.NavigationError)
order_page_annotations = |annotations, page_counts, pages| {
	total = annotations.len()
	var $offsets = List.with_capacity(pages + 1)
	var $running = 0
	var $page = 0
	$offsets = $offsets.append(0)
	while $page < pages {
		$running = $running + list_at(page_counts, $page)
		$offsets = $offsets.append($running)
		$page = $page + 1
	}
	sentinel = total
	var $order = List.repeat(sentinel, total)
	var $index = 0
	while $index < total {
		annotation = list_at(annotations, $index)
		page_index = annotation.page.index()
		page_count = list_at(page_counts, page_index)
		if annotation.keyboard_order >= page_count {
			return Err(KeyboardOrderOutOfRange({ annotation: $index, attempted: annotation.keyboard_order, page_annotations: page_count }))
		}
		slot = list_at($offsets, page_index) + annotation.keyboard_order
		existing = list_at($order, slot)
		if existing != sentinel {
			return Err(DuplicateKeyboardOrder({ first: existing, second: $index }))
		}
		$order = list_set($order, slot, $index)
		$index = $index + 1
	}
	Ok({ offsets: $offsets, order: $order })
}

validate_outline : List(Document.OutlineEntry), DestinationStore, List(U64), { max_annotations : U64, max_description_bytes : U64, max_destinations : U64, max_label_prefix_bytes : U64, max_label_ranges : U64, max_name_bytes : U64, max_outline_depth : U64, max_outline_entries : U64, max_outline_title_bytes : U64, max_quads : U64, max_uri_bytes : U64 } -> Try({ entries : List(KernelNavigation.OutlineEntry), lookup_steps : U64 }, Document.NavigationError)
validate_outline = |inputs, destinations, name_order, limits| {
	count = inputs.len()
	if count > limits.max_outline_entries {
		return Err(OutlineEntryLimitExceeded({ attempted: count, limit: limits.max_outline_entries }))
	}
	var $entries = List.with_capacity(count)
	var $lookup_steps = 0
	var $previous_depth = 0
	var $index = 0
	while $index < count {
		input = list_at(inputs, $index)
		title_bytes = Str.to_utf8(input.title).len()
		if title_bytes == 0 {
			return Err(OutlineTitleEmpty({ entry: $index }))
		}
		if title_bytes > limits.max_outline_title_bytes {
			return Err(OutlineTitleTooLong({ attempted: title_bytes, entry: $index, limit: limits.max_outline_title_bytes }))
		}
		if $index == 0 {
			if input.depth != 0 {
				return Err(OutlineFirstDepthNonzero({ depth: input.depth }))
			}
		} else if input.depth > $previous_depth and input.depth != $previous_depth + 1 {
			return Err(OutlineDepthJump({ actual: input.depth, entry: $index, previous: $previous_depth }))
		}
		if input.depth >= limits.max_outline_depth {
			return Err(OutlineDepthLimitExceeded({ attempted: input.depth, entry: $index, limit: limits.max_outline_depth }))
		}
		probe = Str.to_utf8(input.destination)
		lookup = find_name(destinations, name_order, probe)
		$lookup_steps = $lookup_steps + lookup.steps
		destination = match lookup.result {
			Found(found) => Semantics.DestinationId.from_index(found)
			Missing => return Err(OutlineDestinationUnknown({ entry: $index }))
		}
		$entries = $entries.append({
			depth: input.depth,
			destination,
			open: input.open,
			title: input.title,
		})
		$previous_depth = input.depth
		$index = $index + 1
	}
	Ok({ entries: $entries, lookup_steps: $lookup_steps })
}

validate_labels : List(Document.PageLabelRange), KernelNavigation.Context, { max_annotations : U64, max_description_bytes : U64, max_destinations : U64, max_label_prefix_bytes : U64, max_label_ranges : U64, max_name_bytes : U64, max_outline_depth : U64, max_outline_entries : U64, max_outline_title_bytes : U64, max_quads : U64, max_uri_bytes : U64 } -> Try({ ranges : List(KernelNavigation.LabelRange) }, Document.NavigationError)
validate_labels = |inputs, context, limits| {
	count = inputs.len()
	if count > limits.max_label_ranges {
		return Err(LabelLimitExceeded({ attempted: count, limit: limits.max_label_ranges }))
	}
	var $ranges = List.with_capacity(count)
	var $previous = 0
	var $index = 0
	while $index < count {
		input = list_at(inputs, $index)
		if $index == 0 {
			if input.start_page != 0 {
				return Err(LabelStartPageNotZero({ start: input.start_page }))
			}
		} else if input.start_page <= $previous {
			return Err(LabelRangeNotAscending({ range: $index }))
		}
		if input.start_page >= context.pages {
			return Err(LabelStartPageOutOfRange({ attempted: input.start_page, pages: context.pages, range: $index }))
		}
		prefix_bytes = Str.to_utf8(input.prefix).len()
		if prefix_bytes > limits.max_label_prefix_bytes {
			return Err(LabelPrefixTooLong({ attempted: prefix_bytes, limit: limits.max_label_prefix_bytes, range: $index }))
		}
		if input.start_number == 0 {
			return Err(LabelStartNumberZero({ range: $index }))
		}
		match input.style {
			NoNumber => if input.start_number != 1 {
				return Err(LabelNumberWithoutStyle({ range: $index }))
			}
			DecimalArabic | LettersLower | LettersUpper | RomanLower | RomanUpper => {}
		}
		$ranges = $ranges.append({
			prefix: input.prefix,
			start_number: input.start_number,
			start_page: input.start_page,
			style: input.style,
		})
		$previous = input.start_page
		$index = $index + 1
	}
	Ok({ ranges: $ranges })
}

is_ascii_alpha : U8 -> Bool
is_ascii_alpha = |byte| (byte >= 'A' and byte <= 'Z') or (byte >= 'a' and byte <= 'z')

is_ascii_digit : U8 -> Bool
is_ascii_digit = |byte| byte >= '0' and byte <= '9'

is_ascii_hex : U8 -> Bool
is_ascii_hex = |byte| is_ascii_digit(byte) or (byte >= 'A' and byte <= 'F') or (byte >= 'a' and byte <= 'f')

## RFC 3986 unreserved, gen-delims, and sub-delims characters; `%` is handled
## by the percent-encoding check.
is_uri_byte : U8 -> Bool
is_uri_byte = |byte| is_ascii_alpha(byte) or
	is_ascii_digit(byte) or
		byte == '-' or
			byte == '.' or
				byte == '_' or
					byte == '~' or
						byte == ':' or
							byte == '/' or
								byte == '?' or
									byte == '#' or
										byte == '[' or
											byte == ']' or
												byte == '@' or
													byte == '!' or
														byte == '$' or
															byte == '&' or
																byte == '\'' or
																	byte == '(' or
																		byte == ')' or
																			byte == '*' or
																				byte == '+' or
																					byte == ',' or
																						byte == ';' or
																							byte == '='

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated navigation index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => {
		crash "validated navigation write escaped"
	}
}

test_limits : KernelNavigation.Limits
test_limits = KernelNavigation.Limits.make({
	max_annotations: 16,
	max_description_bytes: 64,
	max_destinations: 8,
	max_label_prefix_bytes: 16,
	max_label_ranges: 8,
	max_name_bytes: 32,
	max_outline_depth: 4,
	max_outline_entries: 8,
	max_outline_title_bytes: 64,
	max_quads: 16,
	max_uri_bytes: 128,
})

test_context : KernelNavigation.Context
test_context = { forms: 1, nodes: 4, occurrences: 4, pages: 2, semantic_annotations: 2 }

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

test_rect : Layout.Rect
test_rect = {
	origin: { x: unit(72000), y: unit(700000) },
	size: { height: unit(12000), width: unit(120000) },
}

test_quad : KernelNavigation.Quad
test_quad = { x_left: unit(72000), x_right: unit(192000), y_bottom: unit(700000), y_top: unit(712000) }

test_destination : KernelNavigation.DestinationInput
test_destination = {
	anchor: Semantics.OccurrenceId.from_index(1),
	name: "section-2",
	target: Semantics.NodeId.from_index(2),
}

test_uri_annotation : KernelNavigation.AnnotationInput
test_uri_annotation = {
	action: Uri("https://example.org/a?x=1#top"),
	appearance: NoAppearance,
	description: NoDescription,
	keyboard_order: 0,
	page: Semantics.PageId.from_index(0),
	print: True,
	quads: [test_quad],
	rect: test_rect,
}

test_goto_annotation : KernelNavigation.AnnotationInput
test_goto_annotation = {
	action: GoToName("section-2"),
	appearance: NormalAppearance(Scene.FormId.from_index(0)),
	description: WithDescription("Section two"),
	keyboard_order: 0,
	page: Semantics.PageId.from_index(1),
	print: True,
	quads: [test_quad],
	rect: test_rect,
}

test_input : KernelNavigation.Input
test_input = {
	annotations: [test_uri_annotation, test_goto_annotation],
	destinations: [test_destination, { ..test_destination, name: "intro", anchor: Semantics.OccurrenceId.from_index(0), target: Semantics.NodeId.from_index(1) }],
	outline: [
		{ depth: 0, destination: "intro", open: True, title: "Introduction" },
		{ depth: 1, destination: "section-2", open: False, title: "Section two" },
	],
	page_labels: [
		{ prefix: "", start_number: 1, start_page: 0, style: RomanLower },
		{ prefix: "A-", start_number: 5, start_page: 1, style: DecimalArabic },
	],
}

## The showcase input validates into dense stores with exact work counters.
expect {
	result = KernelNavigation.validate(test_input, test_context, test_limits)?
	store = result.store

	store.destinations.len() == 2 and
		store.annotations.len() == 2 and
			store.outline_entries.len() == 2 and
				store.label_ranges.len() == 2 and
					store.quad_points.len() == 2 and
						result.work.annotations_checked == 2 and
							result.work.destinations_checked == 2 and
								result.work.name_bytes_checked == 14 and
									result.work.outline_entries_checked == 2 and
										result.work.label_ranges_checked == 2 and
											result.work.quads_checked == 2
}

## Name ordering is unsigned byte order independent of authoring order, and
## actions resolve through it to dense destination identities.
expect {
	result = KernelNavigation.validate(test_input, test_context, test_limits)?
	store = result.store

	first_sorted = list_at(store.name_order, 0)
	second_sorted = list_at(store.name_order, 1)
	goto = list_at(store.annotations, 1)
	outline_first = list_at(store.outline_entries, 0)

	goto_resolved = match goto.action {
		GoToDestination(destination) => destination.index() == 0
		UriAction(_) => False
	}

	first_sorted == 1 and
		second_sorted == 0 and
			goto_resolved and
				outline_first.destination.index() == 1
}

## The total annotation order is page index then keyboard order.
expect {
	result = KernelNavigation.validate(test_input, test_context, test_limits)?
	store = result.store

	store.page_annotations == [0, 1] and store.page_annotation_offsets == [0, 1, 2]
}

## Keyboard order within one page orders the /Annots array independently of
## authoring order.
expect {
	swapped = { ..test_uri_annotation, keyboard_order: 1 }
	other = { ..test_goto_annotation, page: Semantics.PageId.from_index(0), keyboard_order: 0 }
	input = { ..test_input, annotations: [swapped, other] }
	result = KernelNavigation.validate(input, test_context, test_limits)?

	result.store.page_annotations == [1, 0] and result.store.page_annotation_offsets == [0, 2, 2]
}

## Duplicate destination names are exact-equality rejections naming both
## authored indices.
expect {
	input = { ..test_input, destinations: [test_destination, test_destination], annotations: [], outline: [], page_labels: [] }
	context = { ..test_context, semantic_annotations: 0 }

	match KernelNavigation.validate(input, context, test_limits) {
		Err(DuplicateDestinationName({ first: 0, second: 1 })) => True
		_ => False
	}
}

## Destination names are bounded printable ASCII with exact offsets.
expect {
	invalid = { ..test_destination, name: "bad name" }
	input = { ..test_input, destinations: [invalid], annotations: [], outline: [], page_labels: [] }
	context = { ..test_context, semantic_annotations: 0 }

	match KernelNavigation.validate(input, context, test_limits) {
		Err(DestinationNameInvalidByte({ destination: 0, offset: 3 })) => True
		_ => False
	}
}

## Empty and oversized destination names are distinct rejections.
expect {
	empty_input = { ..test_input, destinations: [{ ..test_destination, name: "" }], annotations: [], outline: [], page_labels: [] }
	long_input = { ..test_input, destinations: [{ ..test_destination, name: "a-very-long-destination-name-over-limit" }], annotations: [], outline: [], page_labels: [] }
	context = { ..test_context, semantic_annotations: 0 }

	empty = match KernelNavigation.validate(empty_input, context, test_limits) {
		Err(DestinationNameEmpty({ destination: 0 })) => True
		_ => False
	}
	long = match KernelNavigation.validate(long_input, context, test_limits) {
		Err(DestinationNameTooLong({ attempted: 39, destination: 0, limit: 32 })) => True
		_ => False
	}
	empty and long
}

## Destination targets and anchors validate against the semantic counts.
expect {
	bad_target = { ..test_input, destinations: [{ ..test_destination, target: Semantics.NodeId.from_index(9) }], annotations: [], outline: [], page_labels: [] }
	bad_anchor = { ..test_input, destinations: [{ ..test_destination, anchor: Semantics.OccurrenceId.from_index(9) }], annotations: [], outline: [], page_labels: [] }
	context = { ..test_context, semantic_annotations: 0 }

	target = match KernelNavigation.validate(bad_target, context, test_limits) {
		Err(DestinationTargetOutOfRange({ attempted: 9, destination: 0, nodes: 4 })) => True
		_ => False
	}
	anchor = match KernelNavigation.validate(bad_anchor, context, test_limits) {
		Err(DestinationAnchorOutOfRange({ attempted: 9, destination: 0, occurrences: 4 })) => True
		_ => False
	}
	target and anchor
}

## An unknown destination name on a link is a stable rejection.
expect {
	input = { ..test_input, annotations: [{ ..test_goto_annotation, action: GoToName("missing") }, test_uri_annotation] }

	match KernelNavigation.validate(input, test_context, test_limits) {
		Err(UnknownDestinationName({ annotation: 0 })) => True
		_ => False
	}
}

## URI validation requires a scheme, checked percent-encoding, and the RFC
## 3986 byte set, with exact offsets.
expect {
	no_scheme = { ..test_input, annotations: [{ ..test_uri_annotation, action: Uri("example.org/x y") }, test_goto_annotation] }
	bad_byte = { ..test_input, annotations: [{ ..test_uri_annotation, action: Uri("https://example.org/x y") }, test_goto_annotation] }
	bad_percent = { ..test_input, annotations: [{ ..test_uri_annotation, action: Uri("https://example.org/%zz") }, test_goto_annotation] }
	empty = { ..test_input, annotations: [{ ..test_uri_annotation, action: Uri("") }, test_goto_annotation] }

	scheme = match KernelNavigation.validate(no_scheme, test_context, test_limits) {
		Err(UriMissingScheme({ annotation: 0 })) => True
		_ => False
	}
	byte = match KernelNavigation.validate(bad_byte, test_context, test_limits) {
		Err(UriInvalidByte({ annotation: 0, offset: 21 })) => True
		_ => False
	}
	percent = match KernelNavigation.validate(bad_percent, test_context, test_limits) {
		Err(UriInvalidPercentEncoding({ annotation: 0, offset: 20 })) => True
		_ => False
	}
	missing = match KernelNavigation.validate(empty, test_context, test_limits) {
		Err(UriEmpty({ annotation: 0 })) => True
		_ => False
	}
	scheme and byte and percent and missing
}

## Rects must be normalized with positive extents.
expect {
	degenerate = { ..test_rect, size: { height: unit(0), width: unit(120000) } }
	input = { ..test_input, annotations: [{ ..test_uri_annotation, rect: degenerate, quads: [test_quad] }, test_goto_annotation] }

	match KernelNavigation.validate(input, test_context, test_limits) {
		Err(InvalidAnnotationRect({ annotation: 0 })) => True
		_ => False
	}
}

## Malformed quads and quads escaping their rect are distinct rejections.
expect {
	inverted = { ..test_quad, x_left: unit(192000), x_right: unit(72000) }
	outside = { ..test_quad, y_top: unit(713000) }
	inverted_input = { ..test_input, annotations: [{ ..test_uri_annotation, quads: [inverted] }, test_goto_annotation] }
	outside_input = { ..test_input, annotations: [{ ..test_uri_annotation, quads: [test_quad, outside] }, test_goto_annotation] }

	malformed = match KernelNavigation.validate(inverted_input, test_context, test_limits) {
		Err(InvalidQuad({ annotation: 0, quad: 0 })) => True
		_ => False
	}
	escape = match KernelNavigation.validate(outside_input, test_context, test_limits) {
		Err(QuadOutsideRect({ annotation: 0, quad: 1 })) => True
		_ => False
	}
	malformed and escape
}

## An annotation must carry at least one quad.
expect {
	input = { ..test_input, annotations: [{ ..test_uri_annotation, quads: [] }, test_goto_annotation] }

	match KernelNavigation.validate(input, test_context, test_limits) {
		Err(QuadsEmpty({ annotation: 0 })) => True
		_ => False
	}
}

## Annotation page association validates against the page count.
expect {
	input = { ..test_input, annotations: [{ ..test_uri_annotation, page: Semantics.PageId.from_index(5) }, test_goto_annotation] }

	match KernelNavigation.validate(input, test_context, test_limits) {
		Err(AnnotationPageOutOfRange({ annotation: 0, attempted: 5, pages: 2 })) => True
		_ => False
	}
}

## The navigation annotation list must be one-to-one with the semantic
## annotation store.
expect {
	context = { ..test_context, semantic_annotations: 3 }

	match KernelNavigation.validate(test_input, context, test_limits) {
		Err(AnnotationCountMismatch({ navigation: 2, semantics: 3 })) => True
		_ => False
	}
}

## Keyboard order must be a dense per-page permutation: out-of-range and
## duplicate orders are distinct rejections.
expect {
	out_of_range = { ..test_input, annotations: [{ ..test_uri_annotation, keyboard_order: 1 }, test_goto_annotation] }
	both_zero = {
		..test_input,
		annotations: [
			test_uri_annotation,
			{ ..test_goto_annotation, page: Semantics.PageId.from_index(0) },
		],
	}

	range = match KernelNavigation.validate(out_of_range, test_context, test_limits) {
		Err(KeyboardOrderOutOfRange({ annotation: 0, attempted: 1, page_annotations: 1 })) => True
		_ => False
	}
	duplicate = match KernelNavigation.validate(both_zero, test_context, test_limits) {
		Err(DuplicateKeyboardOrder({ first: 0, second: 1 })) => True
		_ => False
	}
	range and duplicate
}

## Appearance references validate against the form count; descriptions are
## bounded and non-empty.
expect {
	bad_form = { ..test_input, annotations: [test_uri_annotation, { ..test_goto_annotation, appearance: NormalAppearance(Scene.FormId.from_index(3)) }] }
	empty_description = { ..test_input, annotations: [test_uri_annotation, { ..test_goto_annotation, description: WithDescription("") }] }

	form = match KernelNavigation.validate(bad_form, test_context, test_limits) {
		Err(AppearanceFormOutOfRange({ annotation: 1, attempted: 3, forms: 1 })) => True
		_ => False
	}
	description = match KernelNavigation.validate(empty_description, test_context, test_limits) {
		Err(DescriptionEmpty({ annotation: 1 })) => True
		_ => False
	}
	form and description
}

## Outline entries validate preorder depth rules against the authored list.
expect {
	nonzero_first = { ..test_input, outline: [{ depth: 1, destination: "intro", open: True, title: "Broken" }] }
	jump = {
		..test_input,
		outline: [
			{ depth: 0, destination: "intro", open: True, title: "One" },
			{ depth: 2, destination: "section-2", open: True, title: "Two" },
		],
	}
	deep = {
		..test_input,
		outline: [
			{ depth: 0, destination: "intro", open: True, title: "A" },
			{ depth: 1, destination: "intro", open: True, title: "B" },
			{ depth: 2, destination: "intro", open: True, title: "C" },
			{ depth: 3, destination: "intro", open: True, title: "D" },
			{ depth: 4, destination: "intro", open: True, title: "E" },
		],
	}

	first = match KernelNavigation.validate(nonzero_first, test_context, test_limits) {
		Err(OutlineFirstDepthNonzero({ depth: 1 })) => True
		_ => False
	}
	jumped = match KernelNavigation.validate(jump, test_context, test_limits) {
		Err(OutlineDepthJump({ actual: 2, entry: 1, previous: 0 })) => True
		_ => False
	}
	limited = match KernelNavigation.validate(deep, test_context, test_limits) {
		Err(OutlineDepthLimitExceeded({ attempted: 4, entry: 4, limit: 4 })) => True
		_ => False
	}
	first and jumped and limited
}

## Outline titles are bounded non-empty text; unknown outline destinations
## are stable rejections.
expect {
	empty_title = { ..test_input, outline: [{ depth: 0, destination: "intro", open: True, title: "" }] }
	unknown = { ..test_input, outline: [{ depth: 0, destination: "missing", open: True, title: "X" }] }

	title = match KernelNavigation.validate(empty_title, test_context, test_limits) {
		Err(OutlineTitleEmpty({ entry: 0 })) => True
		_ => False
	}
	destination = match KernelNavigation.validate(unknown, test_context, test_limits) {
		Err(OutlineDestinationUnknown({ entry: 0 })) => True
		_ => False
	}
	title and destination
}

## Page-label ranges must start at page zero, ascend strictly, stay within
## the page count, and carry positive start numbers.
expect {
	not_zero = { ..test_input, page_labels: [{ prefix: "", start_number: 1, start_page: 1, style: DecimalArabic }] }
	not_ascending = {
		..test_input,
		page_labels: [
			{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic },
			{ prefix: "", start_number: 1, start_page: 0, style: RomanLower },
		],
	}
	out_of_range = {
		..test_input,
		page_labels: [
			{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic },
			{ prefix: "", start_number: 1, start_page: 7, style: RomanLower },
		],
	}
	zero_number = { ..test_input, page_labels: [{ prefix: "", start_number: 0, start_page: 0, style: DecimalArabic }] }
	no_number_start = { ..test_input, page_labels: [{ prefix: "P", start_number: 2, start_page: 0, style: NoNumber }] }

	zero = match KernelNavigation.validate(not_zero, test_context, test_limits) {
		Err(LabelStartPageNotZero({ start: 1 })) => True
		_ => False
	}
	ascending = match KernelNavigation.validate(not_ascending, test_context, test_limits) {
		Err(LabelRangeNotAscending({ range: 1 })) => True
		_ => False
	}
	range = match KernelNavigation.validate(out_of_range, test_context, test_limits) {
		Err(LabelStartPageOutOfRange({ attempted: 7, pages: 2, range: 1 })) => True
		_ => False
	}
	number = match KernelNavigation.validate(zero_number, test_context, test_limits) {
		Err(LabelStartNumberZero({ range: 0 })) => True
		_ => False
	}
	without_style = match KernelNavigation.validate(no_number_start, test_context, test_limits) {
		Err(LabelNumberWithoutStyle({ range: 0 })) => True
		_ => False
	}
	zero and ascending and range and number and without_style
}

## Count limits reject before any store allocation.
expect {
	tiny = KernelNavigation.Limits.make({
		max_annotations: 1,
		max_description_bytes: 64,
		max_destinations: 1,
		max_label_prefix_bytes: 16,
		max_label_ranges: 1,
		max_name_bytes: 32,
		max_outline_depth: 4,
		max_outline_entries: 1,
		max_outline_title_bytes: 64,
		max_quads: 1,
		max_uri_bytes: 128,
	})

	destinations = match KernelNavigation.validate(test_input, test_context, tiny) {
		Err(DestinationLimitExceeded({ attempted: 2, limit: 1 })) => True
		_ => False
	}
	destinations
}

## The per-document quad budget rejects transactionally.
expect {
	two_quads = { ..test_uri_annotation, quads: [test_quad, test_quad] }
	input = { ..test_input, annotations: [two_quads, test_goto_annotation] }
	limits = KernelNavigation.Limits.make({
		max_annotations: 16,
		max_description_bytes: 64,
		max_destinations: 8,
		max_label_prefix_bytes: 16,
		max_label_ranges: 8,
		max_name_bytes: 32,
		max_outline_depth: 4,
		max_outline_entries: 8,
		max_outline_title_bytes: 64,
		max_quads: 2,
		max_uri_bytes: 128,
	})

	match KernelNavigation.validate(input, test_context, limits) {
		Err(QuadLimitExceeded({ attempted: 3, limit: 2 })) => True
		_ => False
	}
}

## Identical validated input produces identical stores and work.
expect {
	first = KernelNavigation.validate(test_input, test_context, test_limits)?
	second = KernelNavigation.validate(test_input, test_context, test_limits)?

	first.store == second.store and first.work == second.work
}

empty_semantic_range : Semantics.Range
empty_semantic_range = Semantics.Range.from_start_and_length(0, 0)

resolve_node : U64, Str -> Semantics.Node
resolve_node = |index, role| {
	attributes: empty_semantic_range,
	content: empty_semantic_range,
	element_identifier: NoElementIdentifier,
	id: Semantics.NodeId.from_index(index),
	language: Inherited,
	parent: if index == 0 DocumentRoot else ParentNode(Semantics.NodeId.from_index(0)),
	role: { local_name: role, namespace: Semantics.NamespaceId.from_index(0) },
	structure_element: Semantics.StructureElementId.from_index(index),
	text_properties: empty_semantic_range,
}

resolve_fragment : U64, U64, U64 -> Semantics.LayoutFragment
resolve_fragment = |index, occurrence, page| {
	content_stream: Semantics.ContentStreamId.from_index(page),
	continuation_index: 0,
	id: Semantics.FragmentId.from_index(index),
	occurrence: Semantics.OccurrenceId.from_index(occurrence),
	page: Semantics.PageId.from_index(page),
	source_range: ByteRange(empty_semantic_range),
}

resolve_occurrence : U64, U64 -> Semantics.ContentOccurrence
resolve_occurrence = |index, fragment_start| {
	fragments: Semantics.Range.from_start_and_length(fragment_start, 1),
	id: Semantics.OccurrenceId.from_index(index),
	language: Inherited,
	source: NonText(Semantics.NonTextSourceId.from_index(index), ByteRange(empty_semantic_range)),
	text_properties: empty_semantic_range,
}

resolve_semantics : Semantics.Store
resolve_semantics = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [],
	content_spine: [],
	contextual_artifacts: [],
	document_root: Semantics.NodeId.from_index(0),
	fragments: [resolve_fragment(0, 0, 0), resolve_fragment(1, 1, 1)],
	element_identifiers: [],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: [resolve_node(0, "Document"), resolve_node(1, "P"), resolve_node(2, "Link")],
	non_text_sources: [[], []],
	occurrence_fragments: [Semantics.FragmentId.from_index(0), Semantics.FragmentId.from_index(1)],
	occurrences: [resolve_occurrence(0, 0), resolve_occurrence(1, 1)],
	relationships: [],
	role_mappings: [],
	text_properties: [],
	text_sources: [],
}

resolve_owners : List(Semantics.NodeId)
resolve_owners = [Semantics.NodeId.from_index(1), Semantics.NodeId.from_index(2)]

resolve_anchor_rects : List(KernelNavigation.AnchorRect)
resolve_anchor_rects = [
	AnchorAt({ origin: { x: unit(72000), y: unit(700000) }, size: { height: unit(12000), width: unit(120000) } }),
	AnchorAt({ origin: { x: unit(72000), y: unit(300000) }, size: { height: unit(24000), width: unit(120000) } }),
]

## Destination resolution pairs the semantic structure element with the
## anchor fragment's exact page and top-left geometry from one authored
## record.
expect {
	validated = KernelNavigation.validate(test_input, test_context, test_limits)?
	resolved = KernelNavigation.resolve(validated.store, resolve_semantics, resolve_owners, resolve_anchor_rects)?
	section = list_at(resolved.destinations, 0)
	intro = list_at(resolved.destinations, 1)

	section.page.index() == 1 and
		section.structure_element.index() == 2 and
			section.left.raw() == 72000 and
				section.top.raw() == 324000 and
					intro.page.index() == 0 and
						intro.structure_element.index() == 1 and
							intro.top.raw() == 712000 and
								resolved.work == { anchor_lookups: 2, destinations_resolved: 2 }
}

## A destination whose anchor occurrence is owned by a different node than
## its semantic target is a paired-target mismatch.
expect {
	validated = KernelNavigation.validate(test_input, test_context, test_limits)?
	owners = [Semantics.NodeId.from_index(1), Semantics.NodeId.from_index(1)]

	match KernelNavigation.resolve(validated.store, resolve_semantics, owners, resolve_anchor_rects) {
		Err(DestinationTargetMismatch({ anchor_owner: 1, destination: 0, target: 2 })) => True
		_ => False
	}
}

## A destination without resolvable anchor geometry is rejected rather than
## emitted as an /SD-only target: a missing anchor rect, a fragmentless
## occurrence, and an out-of-range anchor list are each unresolvable.
expect {
	validated = KernelNavigation.validate(test_input, test_context, test_limits)?
	no_rect = [AnchorAt({ origin: { x: unit(0), y: unit(0) }, size: { height: unit(1), width: unit(1) } }), NoAnchor]
	fragmentless = {
		..resolve_semantics,
		occurrences: [resolve_occurrence(0, 0), { ..resolve_occurrence(1, 1), fragments: empty_semantic_range }],
	}

	missing = match KernelNavigation.resolve(validated.store, resolve_semantics, resolve_owners, no_rect) {
		Err(UnresolvedDestinationAnchor({ destination: 0 })) => True
		_ => False
	}
	unpainted = match KernelNavigation.resolve(validated.store, fragmentless, resolve_owners, resolve_anchor_rects) {
		Err(UnresolvedDestinationAnchor({ destination: 0 })) => True
		_ => False
	}
	short_list = match KernelNavigation.resolve(validated.store, resolve_semantics, resolve_owners, [list_at(resolve_anchor_rects, 0)]) {
		Err(UnresolvedDestinationAnchor({ destination: 0 })) => True
		_ => False
	}
	missing and unpainted and short_list
}

## Anchor geometry that cannot produce a finite top coordinate is rejected.
expect {
	validated = KernelNavigation.validate(test_input, test_context, test_limits)?
	overflowing = [
		list_at(resolve_anchor_rects, 0),
		AnchorAt({ origin: { x: unit(0), y: unit(9223372036854775800) }, size: { height: unit(9223372036854775800), width: unit(1) } }),
	]

	match KernelNavigation.resolve(validated.store, resolve_semantics, resolve_owners, overflowing) {
		Err(InvalidAnchorGeometry({ destination: 0 })) => True
		_ => False
	}
}
