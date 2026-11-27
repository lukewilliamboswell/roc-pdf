import shaping.Font as BuiltInFaces

## Exact static faces exposed by the pinned roc-font dependency.
KernelBuiltInFonts :: [].{
	sans_regular : List(U8)
	sans_regular = BuiltInFaces.sans_bytes

	sans_bold : List(U8)
	sans_bold = BuiltInFaces.sans_bold_bytes

	sans_italic : List(U8)
	sans_italic = BuiltInFaces.sans_italic_bytes

	sans_bold_italic : List(U8)
	sans_bold_italic = BuiltInFaces.sans_bold_italic_bytes

	serif_regular : List(U8)
	serif_regular = BuiltInFaces.serif_bytes

	serif_bold : List(U8)
	serif_bold = BuiltInFaces.serif_bold_bytes

	serif_italic : List(U8)
	serif_italic = BuiltInFaces.serif_italic_bytes

	serif_bold_italic : List(U8)
	serif_bold_italic = BuiltInFaces.serif_bold_italic_bytes

	mono_regular : List(U8)
	mono_regular = BuiltInFaces.mono_bytes

	mono_bold : List(U8)
	mono_bold = BuiltInFaces.mono_bold_bytes

	## Canonical dense storage has one slot per supported packaged face.
	count : U64
	count = 10

	## Only this module assigns numeric slots. The resolver stores their indexes
	## in dense tables; selection must already have rejected unavailable styles.
	## Structural input keeps this asset owner independent of Font, its caller.
	Slot :: U64.{
		from_selection : { family : [Sans, Serif, Mono], style : [Regular, Bold, Italic, BoldItalic] } -> Slot
		from_selection = |{ family, style }| Slot.(
			match (family, style) {
				(Sans, Regular) => 0
				(Sans, Bold) => 1
				(Sans, Italic) => 2
				(Sans, BoldItalic) => 3
				(Serif, Regular) => 4
				(Serif, Bold) => 5
				(Serif, Italic) => 6
				(Serif, BoldItalic) => 7
				(Mono, Regular) => 8
				(Mono, Bold) => 9
				(Mono, Italic) | (Mono, BoldItalic) => crash "KernelBuiltInFonts.Slot.from_selection: unavailable style escaped font selection"
			},
		)

		## Re-enter from a bounded dense traversal, never a caller font handle.
		from_index : U64 -> Slot
		from_index = |slot_index| {
			if slot_index >= count {
				crash "KernelBuiltInFonts.Slot.from_index: index exceeds the packaged face count"
			}
			Slot.(slot_index)
		}

		index : Slot -> U64
		index = |Slot.(slot_index)| slot_index

		bytes : Slot -> List(U8)
		bytes = |Slot.(slot_index)| match slot_index {
			0 => BuiltInFaces.sans_bytes
			1 => BuiltInFaces.sans_bold_bytes
			2 => BuiltInFaces.sans_italic_bytes
			3 => BuiltInFaces.sans_bold_italic_bytes
			4 => BuiltInFaces.serif_bytes
			5 => BuiltInFaces.serif_bold_bytes
			6 => BuiltInFaces.serif_italic_bytes
			7 => BuiltInFaces.serif_bold_italic_bytes
			8 => BuiltInFaces.mono_bytes
			9 => BuiltInFaces.mono_bold_bytes
			_ => crash "KernelBuiltInFonts.Slot.bytes: invalid opaque slot"
		}
	}
}

## Every supported selection names its exact source bytes in canonical order.
expect {
	selections : List({ family : [Sans, Serif, Mono], style : [Regular, Bold, Italic, BoldItalic] })
	selections = [
		{ family: Sans, style: Regular },
		{ family: Sans, style: Bold },
		{ family: Sans, style: Italic },
		{ family: Sans, style: BoldItalic },
		{ family: Serif, style: Regular },
		{ family: Serif, style: Bold },
		{ family: Serif, style: Italic },
		{ family: Serif, style: BoldItalic },
		{ family: Mono, style: Regular },
		{ family: Mono, style: Bold },
	]
	slots = selections.map(KernelBuiltInFonts.Slot.from_selection)
	actual = {
		count: KernelBuiltInFonts.count,
		indexes: slots.map(|slot| slot.index()),
		bytes: slots.map(|slot| slot.bytes()),
		replayed_bytes: slots.map(|slot| KernelBuiltInFonts.Slot.from_index(slot.index()).bytes()),
	}
	expected_bytes = [
		BuiltInFaces.sans_bytes,
		BuiltInFaces.sans_bold_bytes,
		BuiltInFaces.sans_italic_bytes,
		BuiltInFaces.sans_bold_italic_bytes,
		BuiltInFaces.serif_bytes,
		BuiltInFaces.serif_bold_bytes,
		BuiltInFaces.serif_italic_bytes,
		BuiltInFaces.serif_bold_italic_bytes,
		BuiltInFaces.mono_bytes,
		BuiltInFaces.mono_bold_bytes,
	]
	actual == { count: selections.len(), indexes: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], bytes: expected_bytes, replayed_bytes: expected_bytes }
}
