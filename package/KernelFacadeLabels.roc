import Color
import Document
import Font
import KernelFacadeSemantics
import KernelFacadeShape
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
## panel sits at its measured box. Each label is shaped whole in its face
## (the body face, or under style faces the output font of its inline
## role's face) at its size (scaled with its figure), aligned to its anchor by its
## exact advance and proved to lie inside its drawing. Figure labels paint
## the occurrences assigned by the semantic stage. Panel labels remain
## decoration artifacts, with Unicode sources following the furniture.
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
	## shaped store whose runs carry their prepared Unicode ownership,
	## and the panel artifact sources in text-source order.
	Plan : { labels : U64, pieces : List(KernelFacadeText.LabelPiece), sources : List(Str), store : Text.Store }

	## The faces labels are set in: the one body font, or the dense output
	## fonts of style faces with the output font of each inline role's face
	## (the body font, 0, for a role without one).
	Fonts : [SingleFont(KernelFont.Inspection), StyledFonts({ fonts : List(KernelFont.Inspection), instances : KernelFacadeShape.LabelInstances })]

	## `source_base` is the number of text sources before the labels'
	## (semantic sources, then furniture sources).
	build : Document.NormalizedAuthoring, KernelFacadeText.Plan, List(KernelFacadeSemantics.BlockOwnership), KernelFacadeSemantics.FigureLabels, Fonts, Semantics.Language, U64, Limits -> Try([Labels(Plan), NoLabels], Error)
	build = |authoring, text, blocks, figures, fonts, language, source_base, limits| build_labels(authoring, text, blocks, figures, fonts, language, source_base, limits)

	## Whether any figure or panel drawing holds a label. Documents without
	## one skip the stage and allocate nothing for it.
	has_labels : Document.NormalizedAuthoring -> Bool
	has_labels = |authoring| authoring.figures.any(|figure| drawing_has_labels(figure.drawing)) or authoring.customs.any(|custom| drawing_has_labels(custom.panel))
}

## One label before shaping: its owner and ordinal, text, local baseline
## anchor and alignment, paint, and its drawing's placement.
Entry : { align : Scene.LabelAlign, anchor : Layout.Point, color : Color.SourceValue, face : Scene.LabelFace, height : I64, label : U64, local : Layout.Point, owner : KernelFacadeLabels.Owner, page : U64, scale : I64, size : Layout.Unit, text : Str, width : I64 }

## A drawing's anchor on a page: its bottom-left corner and scale in
## thousandths.
Anchor : [Placed({ origin : Layout.Point, page : U64 }), Unplaced]

drawing_has_labels : Document.ValidatedDrawing -> Bool
drawing_has_labels = |drawing| match drawing {
	ValidDrawing(value) => value.commands.any(
		|command| match command {
			FlowText(_) => True
			_ => False
		},
	)
	InvalidDrawing(_) => False
}

build_labels : Document.NormalizedAuthoring, KernelFacadeText.Plan, List(KernelFacadeSemantics.BlockOwnership), KernelFacadeSemantics.FigureLabels, KernelFacadeLabels.Fonts, Semantics.Language, U64, KernelFacadeLabels.Limits -> Try([Labels(KernelFacadeLabels.Plan), NoLabels], KernelFacadeLabels.Error)
build_labels = |authoring, text, blocks, figures, fonts, language, source_base, limits| {
	anchors = match figures {
		NoFigureLabels => []
		FigureLabels(labels) => figure_anchors(authoring, text, blocks, labels.owners, labels.first)
	}
	flow = KernelFacadeText.Plan.flow(text)

	# Every label, figures first, then panels, each in drawing order.
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
	figure_count = $entries.len()
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

	# Figure Unicode was interned during semantic preparation. Panels
	# use a separate bank with distinct artifact source identities.
	figure = match figures {
		NoFigureLabels => { first: 0, inputs: [], unique: [] }
		FigureLabels(labels) => { first: labels.first, inputs: KernelFacadeSources.Plan.input_sources(labels.sources), unique: KernelFacadeSources.Plan.sources(labels.sources) }
	}
	if figure_count != figure.inputs.len() {
		crash "prepared Figure label coverage escaped"
	}
	panel = if figure_count == entries.len() {
		{ inputs: [], unique: [] }
	} else {
		interned = KernelFacadeSources.Plan.build(entries.sublist({ start: figure_count, len: entries.len() - figure_count }).map(|entry| entry.text), limits.sources) ? Sources
		{ inputs: KernelFacadeSources.Plan.input_sources(interned), unique: KernelFacadeSources.Plan.sources(interned) }
	}
	unique = if panel.unique.is_empty() {
		figure.unique
	} else {
		figure.unique.concat(panel.unique)
	}
	figure_sources = figure.unique.len()
	input_sources = if panel.inputs.is_empty() {
		figure.inputs
	} else {
		figure.inputs.concat(panel.inputs.map(|source| Semantics.TextSourceId.from_index(figure_sources + source.index())))
	}

	# Check each source before shaping so failures name its label. Cache the
	# last face a source was checked in.
	var $checked = List.repeat(0, unique.len())
	var $index = 0
	while $index < entries.len() {
		source_index = list_at(input_sources, $index).index()
		entry = list_at(entries, $index)
		instance = face_instance(fonts, entry.face)
		if list_at($checked, source_index) != instance + 1 {
			match shapeable(face_font(fonts, instance), list_at(unique, source_index)) {
				Shapeable => {}
				NotShapeable(reason) => return Err(LabelText({ label: entry.label, owner: entry.owner, reason }))
			}
			$checked = list_set($checked, source_index, instance + 1)
		}
		$index = $index + 1
	}

	## One run per label, at its scaled size, in entry order: through the
	## one body font, or, under style faces, each in its face's output font.
	batch = match fonts {
		SingleFont(font) => {
			var $requests = List.with_capacity(entries.len())
			$index = 0
			while $index < entries.len() {
				entry = list_at(entries, $index)
				$requests = $requests.append({ occurrence: Semantics.OccurrenceId.from_index($index), size: scaled(entry.size, entry.scale), source: list_at(input_sources, $index) })
				$index = $index + 1
			}
			options = { direction: LeftToRight, instance: Font.InstanceId.from_index(0), language, script: Font.Script.from_iso15924("Latn"), writing_mode: Horizontal }
			KernelShape.shape_simple_batch(font, unique, options, $requests, limits.shape) ? Shape
		}
		StyledFonts(styled) => {
			latin = Font.Script.from_iso15924("Latn")
			var $selected = List.with_capacity(entries.len())
			$index = 0
			while $index < entries.len() {
				entry = list_at(entries, $index)
				source = list_at(input_sources, $index)
				$selected = $selected.append({
					clusters: Semantics.IndexRange.from_start_and_length({ start: 0, length: list_at(unique, source.index()).analysis.graphemes.len() }),
					instance: Font.InstanceId.from_index(face_instance(fonts, entry.face)),
					language,
					occurrence: Semantics.OccurrenceId.from_index($index),
					script: latin,
					size: scaled(entry.size, entry.scale),
					source,
				})
				$index = $index + 1
			}
			KernelShape.shape_selected_batch(styled.fonts, unique, { direction: LeftToRight, language, writing_mode: Horizontal }, $selected, limits.shape) ? Shape
		}
	}

	## The runs are rewritten in place rather than with `map`: dev builds
	## never reuse `List.map`'s list.
	{ advances, store: batch_store, .. } = batch
	var $runs = batch_store.runs
	var $run_index = 0
	while $run_index < $runs.len() {
		run = list_at($runs, $run_index)
		entry = run.id.index()
		unicode = if entry < figure_count {
			OccurrenceText(Semantics.OccurrenceId.from_index(figure.first + entry))
		} else {
			source = list_at(input_sources, entry).index() - figure_sources
			ArtifactText(Semantics.TextSourceId.from_index(source_base + source))
		}
		$runs = list_set($runs, $run_index, { ..run, unicode })
		$run_index = $run_index + 1
	}
	shaped = { ..batch_store, runs: $runs }

	# Align each run to its anchor by its exact advance, prove it lies
	# inside its drawing, and place it on its page.
	var $pieces = List.with_capacity(entries.len())
	$index = 0
	while $index < entries.len() {
		entry = list_at(entries, $index)
		advance = list_at(advances, $index).raw()
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
	pieces = $pieces.sort_with(|left, right| if (left.page < right.page) Before else if (left.page > right.page) After else if (left.run < right.run) Before else if (left.run > right.run) After else Same)
	Ok(Labels({ labels: entries.len(), pieces, sources: panel.unique.map(|source| source.unicode), store: shaped }))
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
					$entries = $entries.append({ align: label.align, anchor: placed.origin, color: label.color, face: label.face, height: value.height.to_i64_wrap(), label: $label, local: label.origin, owner, page: placed.page, scale, size: label.size, text: label.text, width: value.width.to_i64_wrap() })
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
figure_anchors : Document.NormalizedAuthoring, KernelFacadeText.Plan, List(KernelFacadeSemantics.BlockOwnership), List(U64), U64 -> List(Anchor)
figure_anchors = |authoring, text, blocks, label_owners, body_count| {
	sentinel = authoring.figures.len()
	var $by_occurrence = List.repeat(sentinel, body_count)
	var $previous = U64.highest
	for block in label_owners {
		if block != $previous {
			figure = match list_at(authoring.blocks, block).kind {
				Figure(index) => index
				_ => crash "prepared Figure label owner escaped"
			}
			occurrence = match list_at(blocks, block) {
				TextBlock(owned) => owned.body.index()
				_ => crash "prepared Figure drawing anchor escaped"
			}
			$by_occurrence = list_set($by_occurrence, occurrence, figure)
			$previous = block
		}
	}
	var $anchors = List.repeat(Unplaced, sentinel)
	runs = KernelFacadeText.Plan.text(text).runs
	placements = KernelFacadeText.Plan.placements(text)
	var $run = 0
	while $run < runs.len() {
		match list_at(runs, $run).unicode {
			OccurrenceText(occurrence) => if occurrence.index() < body_count {
				figure = list_at($by_occurrence, occurrence.index())
				if figure != sentinel and list_at($anchors, figure) == Unplaced {
					placement = list_at(placements, $run)
					$anchors = list_set($anchors, figure, Placed({ origin: placement.origin, page: placement.page.index() }))
				}
			}
			_ => {}
		}
		$run = $run + 1
	}
	$anchors
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

## The output font a label face is set in: always the body font through
## one font; under style faces, its role's face's output font.
face_instance : KernelFacadeLabels.Fonts, Scene.LabelFace -> U64
face_instance = |fonts, face| match (fonts, face) {
	(SingleFont(_), _) | (_, BodyFace) => 0
	(StyledFonts(styled), RoleFace(Code)) => styled.instances.code
	(StyledFonts(styled), RoleFace(Emphasis)) => styled.instances.emphasis
	(StyledFonts(styled), RoleFace(Quote)) => styled.instances.quote
	(StyledFonts(styled), RoleFace(Strong)) => styled.instances.strong
}

face_font : KernelFacadeLabels.Fonts, U64 -> KernelFont.Inspection
face_font = |fonts, instance| match fonts {
	SingleFont(font) => font
	StyledFonts(styled) => list_at(styled.fonts, instance)
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
