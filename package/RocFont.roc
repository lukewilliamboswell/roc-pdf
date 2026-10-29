import Font
import Theme
import KernelBuiltInFonts
import "fonts/Inter-OFL.txt" as sans_license : Str
import "fonts/Merriweather-OFL.txt" as serif_license : Str
import "fonts/FiraCode-OFL.txt" as mono_license : Str

## Exact static rc4 families; registration validates each payload once.
RocFont :: [].{
	Faces : { body : Font.FaceId, heading : Font.FaceId, strong : Font.FaceId, emphasis : Font.FaceId, strong_emphasis : Font.FaceId, inline_code : Font.FaceId, source_code : Font.FaceId, sans : Font.FamilyFaces, serif : Font.FamilyFaces, mono : Font.FamilyFaces, registry : Font.Registry }

	register : Font.Registry, Font.ValidationLimits -> Try(Faces, Font.ResourceError)
	register = |registry, limits| {
		registration = { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }
		sans = registry.register({ bytes: KernelBuiltInFonts.sans_regular, registration, limits })?
		sans_face = sans.face
		sans_bold = sans.registry.register({ bytes: KernelBuiltInFonts.sans_bold, registration, limits })?
		sans_bold_face = sans_bold.face
		sans_italic = sans_bold.registry.register({ bytes: KernelBuiltInFonts.sans_italic, registration, limits })?
		sans_italic_face = sans_italic.face
		sans_bold_italic = sans_italic.registry.register({ bytes: KernelBuiltInFonts.sans_bold_italic, registration, limits })?
		sans_bold_italic_face = sans_bold_italic.face
		serif = sans_bold_italic.registry.register({ bytes: KernelBuiltInFonts.serif_regular, registration, limits })?
		serif_face = serif.face
		serif_bold = serif.registry.register({ bytes: KernelBuiltInFonts.serif_bold, registration, limits })?
		serif_bold_face = serif_bold.face
		serif_italic = serif_bold.registry.register({ bytes: KernelBuiltInFonts.serif_italic, registration, limits })?
		serif_italic_face = serif_italic.face
		serif_bold_italic = serif_italic.registry.register({ bytes: KernelBuiltInFonts.serif_bold_italic, registration, limits })?
		serif_bold_italic_face = serif_bold_italic.face
		mono = serif_bold_italic.registry.register({ bytes: KernelBuiltInFonts.mono_regular, registration, limits })?
		mono_face = mono.face
		mono_bold = mono.registry.register({ bytes: KernelBuiltInFonts.mono_bold, registration, limits })?
		mono_bold_face = mono_bold.face
		Ok({ body: sans_face, heading: sans_bold_face, strong: sans_bold_face, emphasis: sans_italic_face, strong_emphasis: sans_bold_italic_face, inline_code: mono_face, source_code: mono_face, sans: { regular: sans_face, bold: Available(sans_bold_face), italic: Available(sans_italic_face), bold_italic: Available(sans_bold_italic_face) }, serif: { regular: serif_face, bold: Available(serif_bold_face), italic: Available(serif_italic_face), bold_italic: Available(serif_bold_italic_face) }, mono: { regular: mono_face, bold: Available(mono_bold_face), italic: Unavailable, bold_italic: Unavailable }, registry: mono_bold.registry })
	}

	## Apply packaged family roles without changing sizes, spacing or colours.
	theme : Faces, Theme -> Theme
	theme = |faces, base| {
		{
			..base,
			face: faces.body,
			family: Registered(faces.sans),
			font_selection: StyleFaces,
			source_code: Face(faces.source_code),
			body: { ..base.body, face: ThemeFace },
			title: { ..base.title, face: Face(faces.heading) },
			headings: { ..base.headings, all: { ..base.headings.all, face: Face(faces.heading) } },
			inline: { ..base.inline, code: { ..base.inline.code, font: Family(Registered(faces.mono)) } },
		}
	}

	licenses : { sans : Str, serif : Str, mono : Str }
	licenses = { sans: sans_license, serif: serif_license, mono: mono_license }
}
