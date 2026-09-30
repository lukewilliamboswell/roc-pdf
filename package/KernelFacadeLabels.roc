import Color
import Document
import Font
import KernelFacadeSources
import KernelFacadeText
import KernelFont
import KernelShape
import Layout
import Scene
import Semantics
import Text
import unicode.Scalar

## Text labels inside drawings (`Scene.Drawing.text`).
##
## Labels are shaped after pagination, once the drawings' final positions
## and figure scales are facts: a figure's drawing is anchored at its first
## painted line and scaled by its applied fit scale, and a custom block's
## panel sits at its measured box. Each label is shaped whole in the body
## face at its size (scaled with its figure), aligned to its anchor by its
## exact advance, proved to lie inside its drawing, and placed as one
## `Decoration` artifact run. Label text is artifact text: its Unicode
## sources follow the furniture sources, and it belongs to no structure
## element. Nothing here consults semantics beyond the figure anchors.
KernelFacadeLabels :: [].{

	## The drawing a label belongs to: figure `k` in authored order, or the
	## panel of custom block `k`.
	Owner : [FigureOwner(U64), PanelOwner(U64)]

	## `label` counts the owner's labels in drawing order, from 0.
	Error : [
		ArithmeticOverflow,

		## A figure or panel with labels was not placed on any page.
		InvalidPlacement(Owner),

		## A label's shaped extent leaves its drawing: `left` and `right`
		## are its horizontal extent and `top` its top (the baseline plus the
		## size), in thousandths of a point in drawing coordinates.
		LabelBounds({ height : I64, label : U64, left : I64, owner : Owner, right : I64, top : I64, width : I64 }),

		## A label the body face cannot shape: a scalar it does not cover,
		## a script outside the convenience path, or a multi-scalar cluster.
		LabelText({ label : U64, owner : Owner, reason : [Cluster, Coverage(U32), Script(Str)] }),

		## Labels shape in the body face; under an ordered font policy there
		## is no single body face to shape them in.
		LabelPolicy,
		LimitExceeded({ attempted : U64, limit : U64 }),
		Shape(KernelShape.Error),
		Sources(KernelFacadeSources.Error),
	]

	Limits :: { max_labels : U64, shape : KernelShape.Limits, sources : KernelFacadeSources.Limits }.{
		make : { max_labels : U64, shape : KernelShape.Limits, sources : KernelFacadeSources.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	## The placed label runs: one piece per label, in page order; the
	## shaped store whose runs carry artifact sources starting at the
	## source base; and the label sources in text-source order.
	Plan : { labels : U64, pieces : List(KernelFacadeText.LabelPiece), sources : List(Str), store : Text.Store }

	## `source_base` is the number of text sources before the labels'
	## (semantic sources, then furniture sources).
	build : Document.NormalizedAuthoring, KernelFacadeText.Plan, Semantics.Store, KernelFont.Inspection, Semantics.Language, U64, Limits -> Try([Labels(Plan), NoLabels], Error)
	build = |authoring, text, store, font, language, source_base, limits| build_labels(authoring, text, store, font, language, source_base, limits)

	## Whether any figure or panel drawing holds a label. Documents without
	## one skip the stage and allocate nothing for it.
	has_labels : Document.NormalizedAuthoring -> Bool
	has_labels = |authoring| authoring.figures.any(|figure| drawing_has_labels(figure.drawing)) or authoring.customs.any(|custom| drawing_has_labels(custom.panel))
}

## One label before shaping: its owner and ordinal, text, local baseline
## anchor and alignment, paint, and its drawing's placement.
Entry : { align : Scene.LabelAlign, anchor : Layout.Point, color : Color.SourceValue, height : I64, label : U64, local : Layout.Point, owner : KernelFacadeLabels.Owner, page : U64, scale : I64, size : Layout.Unit, text : Str, width : I64 }

## A drawing's anchor on a page: its bottom-left corner and scale in
## thousandths.
Anchor : [Placed({ origin : Layout.Point, page : U64 }), Unplaced]

drawing_has_labels : Document.ValidatedDrawing -> Bool
drawing_has_labels = |drawing| match drawing {
	ValidDrawing(value) => value.commands.any(
		|command| match command {
			FlowText(_) => Bool.True
			_ => Bool.False
		},
	)
	InvalidDrawing(_) => Bool.False
}

build_labels : Document.NormalizedAuthoring, KernelFacadeText.Plan, Semantics.Store, KernelFont.Inspection, Semantics.Language, U64, KernelFacadeLabels.Limits -> Try([Labels(KernelFacadeLabels.Plan), NoLabels], KernelFacadeLabels.Error)
build_labels = |authoring, text, store, font, language, source_base, limits| {
	if !KernelFacadeLabels.has_labels(authoring) {
		return Ok(NoLabels)
	}
	anchors = figure_anchors(authoring, text, store)?
	flow = KernelFacadeText.Plan.flow(text)

	## Every label, figures first, then panels, each in drawing order.
	var $entries = []
	var $figure = 0
	while $figure < authoring.figures.len() {
		drawing = list_at(authoring.figures, $figure).drawing
		if drawing_has_labels(drawing) {
			owner = FigureOwner($figure)
			placed = match list_at(anchors, $figure) {
				Placed(value) => value
				Unplaced => return Err(InvalidPlacement(owner))
			}
			scale = list_at(flow.figure_scales, $figure).to_i64_wrap()
			$entries = append_entries($entries, drawing, owner, placed, scale)?
		}
		$figure = $figure + 1
	}
	var $custom = 0
	while $custom < authoring.customs.len() {
		drawing = list_at(authoring.customs, $custom).panel
		if drawing_has_labels(drawing) {
			owner = PanelOwner($custom)
			placed = match flow.panels.find_first(|paint| paint.custom == $custom) {
				Ok(paint) => { origin: paint.origin, page: paint.page }
				Err(_) => return Err(InvalidPlacement(owner))
			}
			$entries = append_entries($entries, drawing, owner, placed, 1000)?
		}
		$custom = $custom + 1
	}
	if $entries.len() > limits.max_labels {
		return Err(LimitExceeded({ attempted: $entries.len(), limit: limits.max_labels }))
	}
	entries = $entries

	## Intern every label text once and prove the body face can shape it
	## before shaping, so a failure names its label.
	interned = KernelFacadeSources.Plan.build(entries.map(|entry| entry.text), limits.sources) ? Sources
	unique = KernelFacadeSources.Plan.sources(interned)
	input_sources = KernelFacadeSources.Plan.input_sources(interned)
	var $checked = List.repeat(Bool.False, unique.len())
	var $index = 0
	while $index < entries.len() {
		source_index = list_at(input_sources, $index).index()
		if !list_at($checked, source_index) {
			entry = list_at(entries, $index)
			match shapeable(font, list_at(unique, source_index)) {
				Shapeable => {}
				NotShapeable(reason) => return Err(LabelText({ label: entry.label, owner: entry.owner, reason }))
			}
			$checked = list_set($checked, source_index, Bool.True)
		}
		$index = $index + 1
	}

	## One run per label, at its scaled size, in entry order.
	var $requests = List.with_capacity(entries.len())
	$index = 0
	while $index < entries.len() {
		entry = list_at(entries, $index)
		$requests = $requests.append({ occurrence: Semantics.OccurrenceId.from_index($index), size: scaled(entry.size, entry.scale), source: list_at(input_sources, $index) })
		$index = $index + 1
	}
	options = { direction: LeftToRight, instance: Font.InstanceId.from_index(0), language, script: Font.Script.from_iso15924("Latn"), writing_mode: Horizontal }
	batch = KernelShape.shape_simple_batch(font, unique, options, $requests, limits.shape) ? Shape
	shaped = { ..batch.store, runs: batch.store.runs.map(|run| { ..run, unicode: ArtifactText(Semantics.TextSourceId.from_index(source_base + list_at(input_sources, run.id.index()).index())) }) }

	## Align each run to its anchor by its exact advance, prove it lies
	## inside its drawing, and place it on its page.
	var $pieces = List.with_capacity(entries.len())
	$index = 0
	while $index < entries.len() {
		entry = list_at(entries, $index)
		advance = list_at(batch.advances, $index).raw()
		shift = match entry.align {
			Start => 0
			Center => advance // 2
			End => advance
		}

		## Drawing coordinates in thousandths of a point: the page advance
		## divided by the figure scale.
		local_advance = advance * 1000 // entry.scale
		local_shift = shift * 1000 // entry.scale
		left = entry.local.x.raw() - local_shift
		right = left + local_advance
		top = entry.local.y.raw() + entry.size.raw()
		if left < 0 or right > entry.width or top > entry.height {
			return Err(LabelBounds({ height: entry.height, label: entry.label, left, owner: entry.owner, right, top, width: entry.width }))
		}
		origin = {
			x: Layout.Unit.from_raw(entry.anchor.x.raw() + left * entry.scale // 1000),
			y: Layout.Unit.from_raw(entry.anchor.y.raw() + entry.local.y.raw() * entry.scale // 1000),
		}
		$pieces = $pieces.append({ color: entry.color, origin, page: entry.page, run: $index, size: scaled(entry.size, entry.scale) })
		$index = $index + 1
	}

	## Pieces join their pages in page order; within a page they keep
	## entry order (the run index is the entry index).
	pieces = $pieces.sort_with(|left, right| if left.page < right.page Before else if left.page > right.page After else if left.run < right.run Before else if left.run > right.run After else Same)
	Ok(Labels({ labels: entries.len(), pieces, sources: unique.map(|source| source.unicode), store: shaped }))
}

## Append one drawing's labels as entries.
append_entries : List(Entry), Document.ValidatedDrawing, KernelFacadeLabels.Owner, { origin : Layout.Point, page : U64 }, I64 -> Try(List(Entry), KernelFacadeLabels.Error)
append_entries = |entries, drawing, owner, placed, scale| match drawing {
	InvalidDrawing(_) => Err(InvalidPlacement(owner))
	ValidDrawing(value) => {
		var $entries = entries
		var $label = 0
		for command in value.commands {
			match command {
				FlowText(boxed) => {
					label = Box.unbox(boxed)
					$entries = $entries.append({ align: label.align, anchor: placed.origin, color: label.color, height: value.height.to_i64_wrap(), label: $label, local: label.origin, owner, page: placed.page, scale, size: label.size, text: label.text, width: value.width.to_i64_wrap() })
					$label = $label + 1
				}
				_ => {}
			}
		}
		Ok($entries)
	}
}

## Each figure's anchor: the origin and page of the first painted run of
## its occurrence, where scenes also anchor its drawing.
figure_anchors : Document.NormalizedAuthoring, KernelFacadeText.Plan, Semantics.Store -> Try(List(Anchor), KernelFacadeLabels.Error)
figure_anchors = |authoring, text, store| {
	if authoring.figures.is_empty() {
		return Ok([])
	}
	var $by_occurrence = List.repeat(authoring.figures.len(), store.occurrences.len())
	var $figure = 0
	for node in store.nodes {
		if node.role.local_name == "Figure" {
			occurrence = match store.content_spine.get(node.content.start()) {
				Ok(ContentOccurrence(id)) => id.index()
				_ => return Err(InvalidPlacement(FigureOwner($figure)))
			}
			if occurrence >= $by_occurrence.len() or $figure >= authoring.figures.len() {
				return Err(InvalidPlacement(FigureOwner($figure)))
			}
			$by_occurrence = list_set($by_occurrence, occurrence, $figure)
			$figure = $figure + 1
		}
	}
	var $anchors = List.repeat(Unplaced, authoring.figures.len())
	runs = KernelFacadeText.Plan.text(text).runs
	placements = KernelFacadeText.Plan.placements(text)
	var $run = 0
	while $run < runs.len() {
		match list_at(runs, $run).unicode {
			OccurrenceText(occurrence) => if occurrence.index() < $by_occurrence.len() {
				figure = list_at($by_occurrence, occurrence.index())
				if figure < authoring.figures.len() and list_at($anchors, figure) == Unplaced {
					placement = list_at(placements, $run)
					$anchors = list_set($anchors, figure, Placed({ origin: placement.origin, page: placement.page.index() }))
				}
			}
			_ => {}
		}
		$run = $run + 1
	}
	Ok($anchors)
}

## The body face covers every scalar of a label's source, one scalar per
## cluster, in a script the convenience path shapes.
shapeable : KernelFont.Inspection, KernelFacadeSources.Source -> [NotShapeable([Cluster, Coverage(U32), Script(Str)]), Shapeable]
shapeable = |font, source| {
	for run in source.analysis.script_runs {
		if run.script != "Latn" and run.script != "Zyyy" and run.script != "Zinh" {
			return NotShapeable(Script(run.script))
		}
	}
	for grapheme in source.analysis.graphemes {
		if grapheme.scalar_end != grapheme.scalar_start + 1 {
			return NotShapeable(Cluster)
		}
	}
	for located in Scalar.iter(source.unicode) {
		scalar = Scalar.to_u32(located.scalar)
		match KernelFont.glyph_for_scalar(font, scalar) {
			Some(glyph) if glyph != 0 => {}
			_ => return NotShapeable(Coverage(scalar))
		}
	}
	Shapeable
}

scaled : Layout.Unit, I64 -> Layout.Unit
scaled = |size, scale| Layout.Unit.from_raw(size.raw() * scale // 1000)

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "validated drawing label index escaped"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => crash "validated drawing label write escaped"
}
