import "fonts/Inter-Regular.ttf" as sans_regular_bytes : List(U8)
import "fonts/Inter-Bold.ttf" as sans_bold_bytes : List(U8)
import "fonts/Inter-Italic.ttf" as sans_italic_bytes : List(U8)
import "fonts/Inter-BoldItalic.ttf" as sans_bold_italic_bytes : List(U8)
import "fonts/Merriweather-Regular.ttf" as serif_regular_bytes : List(U8)
import "fonts/Merriweather-Bold.ttf" as serif_bold_bytes : List(U8)
import "fonts/Merriweather-Italic.ttf" as serif_italic_bytes : List(U8)
import "fonts/Merriweather-BoldItalic.ttf" as serif_bold_italic_bytes : List(U8)
import "fonts/FiraCode-Regular.ttf" as mono_regular_bytes : List(U8)
import "fonts/FiraCode-Bold.ttf" as mono_bold_bytes : List(U8)

## Exact unchanged static rc4 payloads. No runtime acquisition or instancing.
KernelBuiltInFonts :: [].{
	sans_regular : List(U8)
	sans_regular = sans_regular_bytes

	sans_bold : List(U8)
	sans_bold = sans_bold_bytes

	sans_italic : List(U8)
	sans_italic = sans_italic_bytes

	sans_bold_italic : List(U8)
	sans_bold_italic = sans_bold_italic_bytes

	serif_regular : List(U8)
	serif_regular = serif_regular_bytes

	serif_bold : List(U8)
	serif_bold = serif_bold_bytes

	serif_italic : List(U8)
	serif_italic = serif_italic_bytes

	serif_bold_italic : List(U8)
	serif_bold_italic = serif_bold_italic_bytes

	mono_regular : List(U8)
	mono_regular = mono_regular_bytes

	mono_bold : List(U8)
	mono_bold = mono_bold_bytes

	bytes : U64 -> List(U8)
	bytes = |slot| match slot {
		0 => sans_regular_bytes
		1 => sans_bold_bytes
		2 => sans_italic_bytes
		3 => sans_bold_italic_bytes
		4 => serif_regular_bytes
		5 => serif_bold_bytes
		6 => serif_italic_bytes
		7 => serif_bold_italic_bytes
		8 => mono_regular_bytes
		9 => mono_bold_bytes
		_ => crash "packaged font slot escaped fixed demand set"
	}
}
