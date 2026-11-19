import KernelBuiltInFonts
import KernelFont

## The packaged faces are constant bytes, so their validation facts are
## constants too. Each face is inspected once, during compile-time evaluation
## of this module, and registration retains the result instead of re-reading
## the font for every document. Caller-supplied bytes never come through here.
KernelBuiltInFontInspections :: [].{

	## The validation limits a font is held to by default, and that the packaged
	## faces are inspected under.
	validation_limits : { max_bytes : U64, max_cmap_mappings : U64, max_glyphs : U64, max_tables : U64 }
	validation_limits = { max_bytes: 2000000, max_cmap_mappings: 1200000, max_glyphs: 65535, max_tables: 128 }

	inspection : KernelBuiltInFonts.Slot -> Try(KernelFont.Inspection, KernelFont.Error)
	inspection = |slot| match slot.index() {
		0 => sans_regular
		1 => sans_bold
		2 => sans_italic
		3 => sans_bold_italic
		4 => serif_regular
		5 => serif_bold
		6 => serif_italic
		7 => serif_bold_italic
		8 => mono_regular
		9 => mono_bold
		_ => crash "KernelBuiltInFontInspections.inspection: invalid opaque slot"
	}
}

inspected : U64 -> Try(KernelFont.Inspection, KernelFont.Error)
inspected = |slot_index| KernelFont.inspect(KernelBuiltInFonts.Slot.from_index(slot_index).bytes(), KernelFont.Limits.make(KernelBuiltInFontInspections.validation_limits))

sans_regular : Try(KernelFont.Inspection, KernelFont.Error)
sans_regular = inspected(0)

sans_bold : Try(KernelFont.Inspection, KernelFont.Error)
sans_bold = inspected(1)

sans_italic : Try(KernelFont.Inspection, KernelFont.Error)
sans_italic = inspected(2)

sans_bold_italic : Try(KernelFont.Inspection, KernelFont.Error)
sans_bold_italic = inspected(3)

serif_regular : Try(KernelFont.Inspection, KernelFont.Error)
serif_regular = inspected(4)

serif_bold : Try(KernelFont.Inspection, KernelFont.Error)
serif_bold = inspected(5)

serif_italic : Try(KernelFont.Inspection, KernelFont.Error)
serif_italic = inspected(6)

serif_bold_italic : Try(KernelFont.Inspection, KernelFont.Error)
serif_bold_italic = inspected(7)

mono_regular : Try(KernelFont.Inspection, KernelFont.Error)
mono_regular = inspected(8)

mono_bold : Try(KernelFont.Inspection, KernelFont.Error)
mono_bold = inspected(9)
