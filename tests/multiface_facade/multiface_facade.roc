app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Font
import pdf.Document
import pdf.Pdf
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)

## The public ordered multi-face boundary: a Theme-selected finite policy
## over two caller faces, per-cluster coverage selection, and one mixed
## Latin/Han/Latin paragraph through the one-import facade, plus the shared
## and deliberately unique registry retention modes.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	match mode {
		"positive" => positive(args.len())
		"shared-registry" => shared_registry(args.len())
		"unique-registries" => unique_registries(args.len())
		_ => crash "text-layout multiface facade mode is invalid"
	}
}

Registered := {
	cjk : { face : Font.FaceId, work : Font.RegistrationWork },
	latin : { face : Font.FaceId, work : Font.RegistrationWork },
	policy : Font.PolicyId,
	registry : Font.Registry,
}

register_faces : U64 -> Registered
register_faces = |runtime_argument_count| {
	latin = match Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "multiface fixture Latin registration failed"
		Ok(value) => value
	}
	cjk = match latin.registry.register(
		cjk_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "multiface fixture Han registration failed"
		Ok(value) => value
	}
	configured = match cjk.registry.with_policy([latin.face, cjk.face]) {
		Err(_) => crash "multiface fixture policy construction failed"
		Ok(value) => value
	}
	{
		cjk: { face: cjk.face, work: cjk.work },
		latin: { face: latin.face, work: latin.work },
		policy: configured.policy,
		registry: configured.registry,
	}
}

mixed_document : {} -> Document
mixed_document = |_| Pdf.document({
	contents: [Pdf.paragraph("C中é")],
	language: "en-AU",
	title: "Multiface facade",
})

positive : U64 -> { bytes : List(U8), work : List(U64) }
positive = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout multiface facade argument count is invalid"
	}
	registered = register_faces(runtime_argument_count)
	theme = Theme.with_font_policy(Theme.default, registered.policy)
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), registered.registry)
	document = mixed_document({})
	bytes = match Pdf.to_bytes_with(document, options) {
		Err(_) => crash "multiface facade output failed"
		Ok(value) => value
	}
	store = registered.registry.store()
	faces = match registered.registry.policy_faces(registered.policy) {
		Err(_) => crash "multiface fixture policy faces are unavailable"
		Ok(value) => value
	}
	{
		bytes,
		work: [
			registered.latin.work.input_bytes,
			registered.cjk.work.input_bytes,
			registered.latin.work.retained_input_bytes,
			registered.cjk.work.retained_input_bytes,
			registered.latin.work.copied_input_bytes + registered.cjk.work.copied_input_bytes,
			store.resources.len(),
			store.faces.len(),
			store.instances.len(),
			store.policies.len(),
			faces.len(),
			document.block_count(),
			bytes.len(),
		],
	}
}

## Two independently authored documents share one completed registry value:
## registration performs one inspection per face, both pipelines reuse the
## retained inspections, and the outputs are identical.
shared_registry : U64 -> { bytes : List(U8), work : List(U64) }
shared_registry = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout multiface facade shared-registry argument count is invalid"
	}
	registered = register_faces(runtime_argument_count)
	theme = Theme.with_font_policy(Theme.default, registered.policy)
	first_options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), registered.registry)
	second_options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), registered.registry)
	first_bytes = match Pdf.to_bytes_with(mixed_document({}), first_options) {
		Err(_) => crash "multiface shared-registry first output failed"
		Ok(value) => value
	}
	second_bytes = match Pdf.to_bytes_with(mixed_document({}), second_options) {
		Err(_) => crash "multiface shared-registry second output failed"
		Ok(value) => value
	}
	if first_bytes != second_bytes {
		crash "multiface shared-registry outputs diverged"
	}
	latin_selected = match registered.registry.prepared_face(registered.latin.face) {
		Err(_) => crash "multiface shared-registry Latin face is unavailable"
		Ok(value) => value
	}
	cjk_selected = match registered.registry.prepared_face(registered.cjk.face) {
		Err(_) => crash "multiface shared-registry Han face is unavailable"
		Ok(value) => value
	}
	store = registered.registry.store()
	{
		bytes: second_bytes,
		work: [
			registered.latin.work.input_bytes + registered.cjk.work.input_bytes,
			registered.latin.work.retained_input_bytes + registered.cjk.work.retained_input_bytes,
			registered.latin.work.copied_input_bytes + registered.cjk.work.copied_input_bytes,
			store.resources.len(),
			store.faces.len(),
			store.instances.len(),
			store.policies.len(),
			2,
			first_bytes.len(),
			second_bytes.len(),
			latin_selected.bytes.len() + cjk_selected.bytes.len(),
		],
	}
}

## The deliberate control: identical font bytes copied into a second caller
## allocation and registered independently double every ownership dimension.
## No registry-level content deduplication is claimed.
unique_registries : U64 -> { bytes : List(U8), work : List(U64) }
unique_registries = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout multiface facade unique-registries argument count is invalid"
	}
	first = register_faces(runtime_argument_count)
	second_caller = copy_bytes(caller_font_bytes)
	second_cjk = copy_bytes(cjk_font_bytes)
	second_latin = match Font.Registry.empty.register(
		second_caller,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "multiface unique-registry Latin registration failed"
		Ok(value) => value
	}
	second_han = match second_latin.registry.register(
		second_cjk,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "multiface unique-registry Han registration failed"
		Ok(value) => value
	}
	second_configured = match second_han.registry.with_policy([second_latin.face, second_han.face]) {
		Err(_) => crash "multiface unique-registry policy construction failed"
		Ok(value) => value
	}
	first_theme = Theme.with_font_policy(Theme.default, first.policy)
	second_theme = Theme.with_font_policy(Theme.default, second_configured.policy)
	first_options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, first_theme), first.registry)
	second_options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, second_theme), second_configured.registry)
	first_bytes = match Pdf.to_bytes_with(mixed_document({}), first_options) {
		Err(_) => crash "multiface unique-registry first output failed"
		Ok(value) => value
	}
	second_bytes = match Pdf.to_bytes_with(mixed_document({}), second_options) {
		Err(_) => crash "multiface unique-registry second output failed"
		Ok(value) => value
	}
	if first_bytes != second_bytes {
		crash "multiface unique-registry outputs diverged"
	}
	first_store = first.registry.store()
	second_store = second_configured.registry.store()
	{
		bytes: second_bytes,
		work: [
			2,
			first.latin.work.input_bytes + first.cjk.work.input_bytes + second_latin.work.input_bytes + second_han.work.input_bytes,
			first.latin.work.retained_input_bytes + first.cjk.work.retained_input_bytes + second_latin.work.retained_input_bytes + second_han.work.retained_input_bytes,
			first.latin.work.copied_input_bytes + first.cjk.work.copied_input_bytes + second_latin.work.copied_input_bytes + second_han.work.copied_input_bytes,
			second_caller.len() + second_cjk.len(),
			first_store.resources.len() + second_store.resources.len(),
			first_store.faces.len() + second_store.faces.len(),
			first_store.instances.len() + second_store.instances.len(),
			first_store.policies.len() + second_store.policies.len(),
			2,
			first_bytes.len(),
			second_bytes.len(),
		],
	}
}

copy_bytes : List(U8) -> List(U8)
copy_bytes = |source| {
	var $copy = List.with_capacity(source.len())
	var $index = 0
	while $index < source.len() {
		$copy = $copy.append(list_at(source, $index))
		$index = $index + 1
	}
	$copy
}

facade_limits : U64 -> Font.ValidationLimits
facade_limits = |runtime_argument_count| {
	if runtime_argument_count == 2 {
		Font.ValidationLimits.default
	} else {
		Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "text-layout multiface facade argument missing"
}
