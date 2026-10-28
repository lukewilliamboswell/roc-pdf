import Font
import Theme
import "fonts/Inter-Regular.ttf" as sans_bytes : List(U8)
import "fonts/Inter-Bold.ttf" as bold_bytes : List(U8)
import "fonts/FiraCode-Regular.ttf" as mono_bytes : List(U8)
import "fonts/Inter-OFL.txt" as sans_license : Str
import "fonts/FiraCode-OFL.txt" as mono_license : Str

## Static PDF instances of roc-font's reviewed sans and mono assets.
## Registration validates each instance once; reuse the returned registry.
RocFont :: [].{
	Faces : { body : Font.FaceId, heading : Font.FaceId, strong : Font.FaceId, inline_code : Font.FaceId, source_code : Font.FaceId, registry : Font.Registry }

	## Append to any caller registry; returned IDs never assume insertion order.
	## Inter is fixed at optical size 14, weights 400/700; Fira Code at 400.
	## Only Latin shaping is declared. No italic face or synthetic style is supplied.
	register : Font.Registry, Font.ValidationLimits -> Try(Faces, Font.ResourceError)
	register = |registry, limits| {
		registration = { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }
		body = registry.register(sans_bytes, registration, limits)?
		bold = body.registry.register(bold_bytes, registration, limits)?
		mono = bold.registry.register(mono_bytes, registration, limits)?
		Ok({ body: body.face, heading: bold.face, strong: bold.face, inline_code: mono.face, source_code: mono.face, registry: mono.registry })
	}

	## Apply the role faces to a theme, preserving its sizes, colors and spacing.
	## Emphasis inherits the surrounding face. Supply a genuine italic face via
	## theme.inline.emphasis.font if desired. Source blocks use faces.source_code.
	theme : Faces, Theme -> Theme
	theme = |faces, base| {
		{
			..base,
			face: faces.body,
			font_selection: StyleFaces,
			body: { ..base.body, face: Face(faces.body) },
			title: { ..base.title, face: Face(faces.heading) },
			headings: { ..base.headings, all: { ..base.headings.all, face: Face(faces.heading) } },
			inline: {
				..base.inline,
				code: { ..base.inline.code, font: Face(faces.inline_code) },
				strong: { ..base.inline.strong, font: Face(faces.strong) },
			},
		}
	}

	## Redistributable OFL notices for the selected families.
	licenses : { sans : Str, mono : Str }
	licenses = { sans: sans_license, mono: mono_license }
}
