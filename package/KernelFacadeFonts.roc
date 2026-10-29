import Document
import Font
import KernelBuiltInFonts
import KernelFacadeShape
import KernelFacadeLabels
import Theme

## Named family/style demand becomes exact validated IDs before shaping.
KernelFacadeFonts :: [].{
	Error : [DrawingStyleUnavailable({ owner : KernelFacadeLabels.Owner, label : U64, style : Font.Style, family : FamilyIdentity }), Resource(Font.ResourceError), StyleUnavailable({ block : U64, inline : [AtInline(U64), NoInline], style : Font.Style, family : FamilyIdentity })]
	Origin : [Packaged, Caller]
	FamilyIdentity : [Packaged(Font.Family), CallerFace(Font.FaceId)]
	StyleFailure : { style : Font.Style, family : FamilyIdentity }
	Work : { packaged_inspections : U64, registered_font_bytes : U64, inline_visits : U64, source_visits : U64, copied_input_bytes : U64 }
	Resolved : { authoring : Document.NormalizedAuthoring, fonts : KernelFacadeShape.StyledFaces, theme : Theme, work : Work }

	resolve : Document.NormalizedAuthoring, { origin : Origin, registry : Font.Registry, theme : Theme } -> Try(Resolved, Error)
	resolve = |authoring, { origin, registry, theme }| {
		if origin == Packaged and theme.family == FromOptions and theme.face.index() != 0 {
			return Err(Resource(UnknownFace(theme.face)))
		}
		caller_faces = registry.store().faces.len()
		validate_choices(theme, { count: caller_faces, origin: origin }) ? Resource
		for source in authoring.sources {
			match source.face {
				Face(face) => {
					check_face(face, caller_faces) ? Resource
				}
				_ => {}
			}
		}
		family = match theme.family {
			FromOptions => if (origin == Caller) Registered(single_family(theme.face)) else BuiltIn(Sans)
			BuiltIn(value) => BuiltIn(value)
			Registered(value) => Registered(value)
		}
		body_family = match theme.body.face {
			ThemeFace => family
			Face(face) => Registered(single_family(face))
		}
		body = choose(body_family, { style: Regular, override: Inherited }) ? |failure| StyleUnavailable({ block: 0, inline: NoInline, style: failure.style, family: failure.family })
		var $demand = mark(List.repeat(False, 10), body)
		var $styles = List.repeat(body, 8)
		var $inline_choices = List.repeat(body, authoring.inlines.len())
		var $labels = List.repeat(NotRequested, 4)
		# The preorder arena carries parent identity. Propagate four style bits
		# once rather than walking an ancestry chain for every text leaf.
		var $flags = List.with_capacity(authoring.inlines.len())
		for inline in authoring.inlines {
			inherited : U8
			inherited = if (inline.parent == 0) 0 else list_at($flags, inline.parent - 1)
			own : U8
			own = match inline.kind {
				Strong => 1
				Emphasis => 2
				Code => 4
				Quote => 8
				_ => 0
			}
			$flags = $flags.append(inherited.bitwise_or(own))
		}
		var $block = 0
		while $block < authoring.blocks.len() {
			match list_at(authoring.blocks, $block).kind {
				Title => {
					selected = block_choice(theme.title.face, family) ? |failure| StyleUnavailable({ block: $block, inline: NoInline, style: failure.style, family: failure.family })
					$styles = set_at($styles, { index: 1, value: selected })
					$demand = mark($demand, selected)
				}
				Heading(level) | DestinationHeading({ level, .. }) => {
					# The semantic stage owns invalid heading-level diagnostics.
					if level >= 1 and level <= 6 {
						selected = block_choice(heading_style(theme, level).face, family) ? |failure| StyleUnavailable({ block: $block, inline: NoInline, style: failure.style, family: failure.family })
						$styles = set_at($styles, { index: level.to_u64() + 1, value: selected })
						$demand = mark($demand, selected)
					}
				}
				RichParagraph(index) => {
					paragraph = list_at(authoring.rich_paragraphs, index)
					var $inline = paragraph.inlines
					while $inline < paragraph.inlines + paragraph.length {
						record = list_at(authoring.inlines, $inline)
						match record.kind {
							Text(_) | PageReference(_) => {
								selected = leaf_choice(list_at($flags, $inline), { body: body_family, theme: theme }) ? |failure| StyleUnavailable({ block: $block, inline: AtInline($inline), style: failure.style, family: failure.family })
								$inline_choices = set_at($inline_choices, { index: $inline, value: selected })
								$demand = mark($demand, selected)
							}
							_ => {}
						}
						$inline = $inline + 1
					}
				}
				Figure(index) => {
					$labels = drawing_roles($labels, { drawing: list_at(authoring.figures, index).drawing, owner: FigureOwner(index), first_block: $block })
				}
				_ => {}
			}
			$block = $block + 1
		}
		var $custom = 0
		for custom in authoring.customs {
			$labels = drawing_roles($labels, { drawing: custom.panel, owner: PanelOwner($custom), first_block: list_at(authoring.groups, custom.group).first_block })
			$custom = $custom + 1
		}
		# Normalization rejects labels in decorations; the semantic stage owns
		# that rejection. Decorations produce no valid drawing-label demands.
		var $label = 0
		while $label < 4 {
			match list_at($labels, $label) {
				Requested(request) => {
					role = role_at($label)
					base = if (role == Code) family_for(theme.inline.code.font, BuiltIn(Mono)) else body_family
					style = role_style(role)
					selected = choose(base, { style: style, override: Theme.inline_font(theme, role) }) ? |failure| DrawingStyleUnavailable({ owner: request.owner, label: request.label, style: failure.style, family: failure.family })
					$labels = set_at($labels, { index: $label, value: Selected(selected) })
					$demand = mark($demand, selected)
				}
				NotRequested | Selected(_) => {}
			}
			$label = $label + 1
		}
		var $source_choices = List.with_capacity(authoring.sources.len())
		for source in authoring.sources {
			selected = match source.face {
				ThemeCode => theme.source_code
				Face(face) => Face(face)
				BuiltIn(value) => BuiltIn(value)
			}
			# An unavailable packaged style is rejected before inspecting any bytes.
			match selected {
				BuiltIn({ family: Mono, style: Italic }) => return Err(StyleUnavailable({ block: list_at(authoring.groups, source.group).first_block, inline: NoInline, style: Italic, family: Packaged(Mono) }))
				BuiltIn({ family: Mono, style: BoldItalic }) => return Err(StyleUnavailable({ block: list_at(authoring.groups, source.group).first_block, inline: NoInline, style: BoldItalic, family: Packaged(Mono) }))
				_ => {}
			}
			$source_choices = $source_choices.append(selected)
			$demand = mark($demand, selected)
		}
		# Consumption-shaped registration: every path replaces the consumed registry
		# or returns immediately. Scalar handles are extracted before the next append.
		var $registry = registry
		var $handles = List.repeat(Unavailable, 10)
		var $inspections = 0
		var $font_bytes = 0
		var $copied_bytes = 0
		var $slot = 0
		while $slot < 10 {
			if list_at($demand, $slot) {
				bytes = KernelBuiltInFonts.bytes($slot)
				$font_bytes = $font_bytes + bytes.len()
				match $registry.register({ bytes, registration: { provision: BuiltIn, scripts: ["Latn"] }, limits: Font.ValidationLimits.default }) {
					Ok(registered) => {
						face = registered.face
						copied = registered.work.copied_input_bytes
						$registry = registered.registry
						$copied_bytes = $copied_bytes + copied
						$handles = set_at($handles, { index: $slot, value: Available(face) })
						$inspections = $inspections + 1
					}
					Err(error) => return Err(Resource(error))
				}
			}
			$slot = $slot + 1
		}
		body_face = exact(body, $handles)
		var $used = List.repeat(False, $registry.store().faces.len())
		check_face(body_face, $used.len()) ? Resource
		$used = set_at($used, { index: (body_face).index(), value: True })
		var $resolved_styles = List.with_capacity(8)
		for selected in $styles {
			face = exact(selected, $handles)
			$resolved_styles = $resolved_styles.append(face)
			check_face(face, $used.len()) ? Resource
			$used = set_at($used, { index: (face).index(), value: True })
		}
		# Furniture owns an independent exact face only when explicitly selected.
		match theme.furniture {
			Own(style) => match style.face {
				Face(face) => {
					check_face(face, $used.len()) ? Resource
					$used = set_at($used, { index: face.index(), value: True })
				}
				ThemeFace => {}
			}
			BodyStyle => {}
		}
		var $inline_faces = List.with_capacity($inline_choices.len())
		for selected in $inline_choices {
			face = exact(selected, $handles)
			$inline_faces = $inline_faces.append(face)
			check_face(face, $used.len()) ? Resource
			$used = set_at($used, { index: (face).index(), value: True })
		}
		var $sources = List.with_capacity(authoring.sources.len())
		var $source = 0
		for source in authoring.sources {
			face = exact(list_at($source_choices, $source), $handles)
			$sources = $sources.append({ ..source, face: Face(face) })
			check_face(face, $used.len()) ? Resource
			$used = set_at($used, { index: (face).index(), value: True })
			$source = $source + 1
		}
		for selected in $labels {
			match selected {
				Selected(choice) => {
					face = exact(choice, $handles)
					check_face(face, $used.len()) ? Resource
					$used = set_at($used, { index: face.index(), value: True })
				}
				_ => {}
			}
		}
		# Compact the demanded candidates once; the dense reverse map prevents
		# rich-text selection from rescanning an unbounded caller/source registry.
		body_inspection = $registry.prepared_face(body_face) ? Resource
		var $faces = [body_face]
		var $fonts = [body_inspection]
		var $indexes = List.repeat(U64.highest, $used.len())
		$indexes = set_at($indexes, { index: body_face.index(), value: 0 })
		var $index = 0
		while $index < $used.len() {
			if list_at($used, $index) and $index != body_face.index() {
				face = Font.FaceId.from_index($index)
				font = $registry.prepared_face(face) ? Resource
				$indexes = set_at($indexes, { index: $index, value: $faces.len() })
				$faces = $faces.append(face)
				$fonts = $fonts.append(font)
			}
			$index = $index + 1
		}
		role = |index| match list_at($labels, index) {
			Selected(choice) => Candidate(list_at($indexes, exact(choice, $handles).index()))
			_ => Inherited
		}
		resolved_theme = {
			..theme,
			face: body_face,
			body: { ..theme.body, face: Face(body_face) },
			title: { ..theme.title, face: Face(list_at($resolved_styles, 1)) },
			headings: {
				..theme.headings,
				h1: Own({ ..heading_style(theme, 1), face: Face(list_at($resolved_styles, 2)) }),
				h2: Own({ ..heading_style(theme, 2), face: Face(list_at($resolved_styles, 3)) }),
				h3: Own({ ..heading_style(theme, 3), face: Face(list_at($resolved_styles, 4)) }),
				h4: Own({ ..heading_style(theme, 4), face: Face(list_at($resolved_styles, 5)) }),
				h5: Own({ ..heading_style(theme, 5), face: Face(list_at($resolved_styles, 6)) }),
				h6: Own({ ..heading_style(theme, 6), face: Face(list_at($resolved_styles, 7)) }),
			},
		}
		Ok({ authoring: { ..authoring, sources: $sources }, fonts: { faces: $faces, fonts: $fonts, face_indexes: $indexes, inline_faces: $inline_faces, roles: { code: role(0), emphasis: role(1), quote: role(2), strong: role(3) } }, theme: resolved_theme, work: { packaged_inspections: $inspections, registered_font_bytes: $font_bytes, inline_visits: authoring.inlines.len() * 3, source_visits: $source * 3, copied_input_bytes: $copied_bytes } })
	}
}

LabelRequest : { first_block : U64, owner : KernelFacadeLabels.Owner, label : U64 }

LabelChoice : [NotRequested, Requested(LabelRequest), Selected(Font.SourceDefault)]

single_family : Font.FaceId -> Font.FamilyFaces
single_family = |face| { regular: face, bold: Unavailable, italic: Unavailable, bold_italic: Unavailable }

family_for : Theme.InlineFont, Font.FamilySelection -> Font.FamilySelection
family_for = |choice, inherited| match choice {
	Inherited => inherited
	Face(face) => Registered(single_family(face))
	Family(value) => value
}

choose : Font.FamilySelection, { style : Font.Style, override : Theme.InlineFont } -> Try(Font.SourceDefault, KernelFacadeFonts.StyleFailure)
choose = |inherited, { style, override }| {
	match override {
		Face(face) => return Ok(Face(face))
		_ => {}
	}
	match family_for(override, inherited) {
		BuiltIn(Mono) if style == Italic or style == BoldItalic => Err({ style, family: Packaged(Mono) })
		BuiltIn(family) => Ok(BuiltIn({ family, style }))
		Registered(faces) => match Font.style_face(faces, style) {
			Available(face) => Ok(Face(face))
			Unavailable => Err({ style, family: CallerFace(faces.regular) })
		}
	}
}

block_choice : Theme.FaceChoice, Font.FamilySelection -> Try(Font.SourceDefault, KernelFacadeFonts.StyleFailure)
block_choice = |choice, family| match choice {
	Face(face) => Ok(Face(face))
	ThemeFace => choose(family, { style: Bold, override: Inherited })
}

leaf_choice : U8, { body : Font.FamilySelection, theme : Theme } -> Try(Font.SourceDefault, KernelFacadeFonts.StyleFailure)
leaf_choice = |flags, { body, theme }| {
	strong = flags.bitwise_and(1) != 0
	emphasis = flags.bitwise_and(2) != 0
	code = flags.bitwise_and(4) != 0
	quote = flags.bitwise_and(8) != 0
	base = if (code) family_for(theme.inline.code.font, BuiltIn(Mono)) else if (quote) family_for(theme.inline.quote.font, body) else body
	style = if (strong and emphasis) BoldItalic else if (strong) Bold else if (emphasis) Italic else Regular
	override = if (strong and emphasis) theme.inline.strong_emphasis.font else if (strong) theme.inline.strong.font else if (emphasis) theme.inline.emphasis.font else Inherited
	choose(base, { style: style, override: override })
}

slot_of : { family : Font.Family, style : Font.Style } -> U64
slot_of = |{ family, style }| {
	base = match family {
		Sans => 0
		Serif => 4
		Mono => 8
	}
	base + match style {
		Regular => 0
		Bold => 1
		Italic => 2
		BoldItalic => 3
	}
}

mark : List(Bool), Font.SourceDefault -> List(Bool)
mark = |demand, choice| match choice {
	Face(_) => demand
	BuiltIn(named) => set_at(demand, { index: slot_of(named), value: True })
}

exact : Font.SourceDefault, List(Font.StyleFace) -> Font.FaceId
exact = |choice, handles| match choice {
	Face(face) => face
	BuiltIn(named) => match list_at(handles, slot_of(named)) {
		Available(face) => face
		Unavailable => crash "named font escaped the explicit demand set"
	}
}

check_face : Font.FaceId, U64 -> Try({}, Font.ResourceError)
check_face = |face, count| {
	if face.index() >= count {
		return Err(UnknownFace(face))
	}
	Ok({})
}

## Validate caller handles before adding packaged resources. A coincident
## later packaged index cannot make an invalid caller handle valid.
validate_choices : Theme, { count : U64, origin : KernelFacadeFonts.Origin } -> Try({}, Font.ResourceError)
validate_choices = |theme, { count, origin }| {
	match theme.family {
		FromOptions if origin == Caller => {
			check_face(theme.face, count)?
		}
		Registered(faces) => {
			check_family(faces, count)?
		}
		_ => {}
	}
	for choice in [theme.body.face, theme.title.face, heading_style(theme, 1).face, heading_style(theme, 2).face, heading_style(theme, 3).face, heading_style(theme, 4).face, heading_style(theme, 5).face, heading_style(theme, 6).face] {
		match choice {
			Face(face) => {
				check_face(face, count)?
			}
			ThemeFace => {}
		}
	}
	for choice in [theme.inline.code.font, theme.inline.emphasis.font, theme.inline.quote.font, theme.inline.strong.font, theme.inline.strong_emphasis.font] {
		match choice {
			Face(face) => {
				check_face(face, count)?
			}
			Family(Registered(faces)) => {
				check_family(faces, count)?
			}
			_ => {}
		}
	}
	match theme.source_code {
		Face(face) => {
			check_face(face, count)?
		}
		BuiltIn(_) => {}
	}
	match theme.furniture {
		Own(style) => match style.face {
			Face(face) => {
				check_face(face, count)?
			}
			ThemeFace => {}
		}
		BodyStyle => {}
	}
	Ok({})
}

check_family : Font.FamilyFaces, U64 -> Try({}, Font.ResourceError)
check_family = |faces, count| {
	check_face(faces.regular, count)?
	for choice in [faces.bold, faces.italic, faces.bold_italic] {
		match choice {
			Available(face) => {
				check_face(face, count)?
			}
			Unavailable => {}
		}
	}
	Ok({})
}

heading_style : Theme, U8 -> Theme.HeadingStyle
heading_style = |theme, level| {
	selected = match level {
		1 => theme.headings.h1
		2 => theme.headings.h2
		3 => theme.headings.h3
		4 => theme.headings.h4
		5 => theme.headings.h5
		_ => theme.headings.h6
	}
	match selected {
		Own(style) => style
		SameAsAll => theme.headings.all
	}
}

## Retain the first authored owner of each finite drawing role. Figures
## are visited with body blocks and panels afterwards, so compare the explicit
## normalized first-block fact instead of letting traversal order choose blame.
drawing_roles : List(LabelChoice), { drawing : Document.ValidatedDrawing, owner : KernelFacadeLabels.Owner, first_block : U64 } -> List(LabelChoice)
drawing_roles = |roles, { drawing, owner, first_block }| {
	var $roles = roles
	var $label = 0
	match drawing {
		InvalidDrawing(_) => {}
		ValidDrawing(value) => {
			for command in value.commands {
				match command {
					FlowText(label) => {
						match Box.unbox(label).face {
							BodyFace => {}
							RoleFace(role) => {
								index = role_index(role)
								earlier = match list_at($roles, index) {
									Requested(previous) => previous.first_block <= first_block
									NotRequested => False
									Selected(_) => crash "drawing demand collection follows role resolution"
								}
								if !earlier {
									$roles = set_at($roles, { index: index, value: Requested({ owner, first_block, label: $label }) })
								}
							}
						}
						$label = $label + 1
					}
					_ => {}
				}
			}
		}
	}
	$roles
}

role_index : Theme.InlineRole -> U64
role_index = |role| match role {
	Code => 0
	Emphasis => 1
	Quote => 2
	Strong => 3
}

role_at : U64 -> Theme.InlineRole
role_at = |index| match index {
	0 => Code
	1 => Emphasis
	2 => Quote
	_ => Strong
}

role_style : Theme.InlineRole -> Font.Style
role_style = |role| match role {
	Strong => Bold
	Emphasis => Italic
	_ => Regular
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "font resolution index escaped normalized input"
}

set_at : List(a), { index : U64, value : a } -> List(a)
set_at = |items, { index, value }| match items.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => crash "font resolution index escaped its exact table"
}
