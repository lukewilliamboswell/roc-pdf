app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Font
import pdf.Document
import pdf.Pdf
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/CallerFont-Restricted.ttf" as restricted_font_bytes : List(U8)
import "../assets/CallerFont-Unhinted.ttf" as unhinted_font_bytes : List(U8)
import "../assets/NotoSansMono-Code-Fixture.ttf" as mono_font_bytes : List(U8)

## This focused fixture exercises the public facade rather than a private
## evidence module. Its registered dev-backend work proves one retained source
## inspection is selected for three placements.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	match mode {
		"positive" => positive(args.len())
		"shared-registry" => shared_registry(args.len())
		"unique-registries" => unique_registries(args.len())
		"restricted" => restricted(args.len())
		"unhinted" => unhinted(args.len())
		"built-in-registry" => built_in_registry(args.len())
		_ => crash "text-layout caller facade mode is invalid"
	}
}

positive : U64 -> { bytes : List(U8), work : List(U64) }
positive = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout caller facade argument count is invalid"
	}
	registered = match Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "caller fixture registration failed"
		Ok(value) => value
	}
	theme = Theme.{ face: registered.face }
	options = Pdf.Options.{ theme: theme, fonts: Registered(registered.registry) }
	selected = match registered.registry.prepared_face(registered.face) {
		Err(_) => crash "caller fixture selected face is unavailable"
		Ok(value) => value
	}
	document = Pdf.document({
		contents: [
			Pdf.paragraph("Café PDF"),
			Pdf.paragraph("Café PDF"),
			Pdf.paragraph("Café PDF"),
		],
		language: "en-AU",
		title: "Caller facade",
	})
	bytes = match Pdf.to_bytes_with(document, options) {
		Err(_) => crash "caller facade output failed"
		Ok(value) => value
	}
	store = registered.registry.store()
	{
		bytes,
		work: [
			registered.work.input_bytes,
			registered.work.retained_input_bytes,
			registered.work.copied_input_bytes,
			registered.work.table_visits,
			registered.work.glyph_visits,
			registered.work.cmap_mapping_visits,
			registered.work.component_edge_visits,
			store.resources.len(),
			store.faces.len(),
			store.instances.len(),
			store.policies.len(),
			document.block_count(),
			selected.bytes.len(),
		],
	}
}

## An unhinted caller font (no cvt, fpgm, gasp, or prep table) registers
## and embeds: its subset carries only the ten required tables.
unhinted : U64 -> { bytes : List(U8), work : List(U64) }
unhinted = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout caller facade argument count is invalid"
	}
	registered = match Font.Registry.empty.register(
		unhinted_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "unhinted caller fixture registration failed"
		Ok(value) => value
	}
	theme = Theme.{ face: registered.face }
	options = Pdf.Options.{ theme: theme, fonts: Registered(registered.registry) }
	document = caller_document({})
	bytes = match Pdf.to_bytes_with(document, options) {
		Err(_) => crash "unhinted caller facade output failed"
		Ok(value) => value
	}
	{
		bytes,
		work: [
			registered.work.input_bytes,
			registered.work.table_visits,
			registered.work.glyph_visits,
			registered.work.cmap_mapping_visits,
			document.block_count(),
			bytes.len(),
		],
	}
}

## The public built-in registration puts the packaged face in a registry
## beside a caller monospace face for `Code`. Registered, the built-in face
## produces exactly the bytes of the unregistered default; the snapshot is
## the code-face document over the registered built-in body face.
built_in_registry : U64 -> { bytes : List(U8), work : List(U64) }
built_in_registry = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout caller facade argument count is invalid"
	}
	body = match Font.Registry.empty.register_built_in(facade_limits(runtime_argument_count)) {
		Err(_) => crash "built-in registration failed"
		Ok(value) => value
	}
	mono = match body.registry.register(
		mono_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "monospace registration failed"
		Ok(value) => value
	}
	registered_options = Pdf.Options.{ theme: Theme.{ face: body.face }, fonts: Registered(body.registry) }
	default_options = if runtime_argument_count == 2 Pdf.Options.default else registered_options
	default_bytes = match Pdf.to_bytes_with(caller_document({}), default_options) {
		Err(_) => crash "default output failed"
		Ok(value) => value
	}
	registered_bytes = match Pdf.to_bytes_with(caller_document({}), registered_options) {
		Err(_) => crash "registered built-in output failed"
		Ok(value) => value
	}
	if default_bytes != registered_bytes {
		crash "the registered built-in face changed the default output"
	}
	theme = Theme.{ face: body.face, inline: { code: { font: Face(mono.face) } } }
	options = Pdf.Options.{ theme: theme, fonts: Registered(mono.registry) }
	document = Pdf.document({
		contents: [Pdf.rich_paragraph([Pdf.text("Run "), Pdf.code("roc build"), Pdf.text(" before the release.")])],
		language: "en-AU",
		title: "Built-in registry",
	})
	bytes = match Pdf.to_bytes_with(document, options) {
		Err(_) => crash "built-in code-face output failed"
		Ok(value) => value
	}
	{
		bytes,
		work: [
			body.face.index(),
			mono.face.index(),
			body.work.input_bytes,
			body.work.copied_input_bytes,
			registered_bytes.len(),
			bytes.len(),
		],
	}
}

## This performance-only positive uses two independently authored documents
## while both options retain the same completed registry value. Registration
## performs the one inspection; each facade pipeline receives that retained
## inspection and must still produce the same final subset bytes.
shared_registry : U64 -> { bytes : List(U8), work : List(U64) }
shared_registry = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout caller facade shared-registry argument count is invalid"
	}
	registered = match Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "caller shared-registry registration failed"
		Ok(value) => value
	}
	theme = Theme.{ face: registered.face }
	first_options = Pdf.Options.{ theme: theme, fonts: Registered(registered.registry) }
	second_options = Pdf.Options.{ theme: theme, fonts: Registered(registered.registry) }
	first_document = caller_document({})
	second_document = caller_document({})
	first_bytes = match Pdf.to_bytes_with(first_document, first_options) {
		Err(_) => crash "caller shared-registry first output failed"
		Ok(value) => value
	}
	second_bytes = match Pdf.to_bytes_with(second_document, second_options) {
		Err(_) => crash "caller shared-registry second output failed"
		Ok(value) => value
	}
	if first_bytes != second_bytes {
		crash "caller shared-registry outputs diverged"
	}
	selected_after_outputs = match registered.registry.prepared_face(registered.face) {
		Err(_) => crash "caller shared-registry selected face is unavailable"
		Ok(value) => value
	}
	store = registered.registry.store()
	{
		bytes: second_bytes,
		work: [
			registered.work.input_bytes,
			registered.work.retained_input_bytes,
			registered.work.copied_input_bytes,
			registered.work.table_visits,
			registered.work.glyph_visits,
			registered.work.cmap_mapping_visits,
			registered.work.component_edge_visits,
			store.resources.len(),
			store.faces.len(),
			store.instances.len(),
			store.policies.len(),
			2,
			first_bytes.len(),
			second_bytes.len(),
			selected_after_outputs.bytes.len(),
		],
	}
}

## This control deliberately creates a second caller allocation with identical
## font bytes and registers each allocation independently. It establishes the
## contrasting ownership shape: no registry-level content deduplication is
## claimed, and each complete caller input has one inspection and one retained
## resource through its own final subset emission.
unique_registries : U64 -> { bytes : List(U8), work : List(U64) }
unique_registries = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout caller facade unique-registries argument count is invalid"
	}
	second_input = copy_bytes(caller_font_bytes)
	first = match Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "caller unique-registry first registration failed"
		Ok(value) => value
	}
	second = match Font.Registry.empty.register(
		second_input,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(_) => crash "caller unique-registry second registration failed"
		Ok(value) => value
	}
	first_theme = Theme.{ face: first.face }
	second_theme = Theme.{ face: second.face }
	first_options = Pdf.Options.{ theme: first_theme, fonts: Registered(first.registry) }
	second_options = Pdf.Options.{ theme: second_theme, fonts: Registered(second.registry) }
	first_bytes = match Pdf.to_bytes_with(caller_document({}), first_options) {
		Err(_) => crash "caller unique-registry first output failed"
		Ok(value) => value
	}
	second_bytes = match Pdf.to_bytes_with(caller_document({}), second_options) {
		Err(_) => crash "caller unique-registry second output failed"
		Ok(value) => value
	}
	if first_bytes != second_bytes {
		crash "caller unique-registry outputs diverged"
	}
	first_selected = match first.registry.prepared_face(first.face) {
		Err(_) => crash "caller unique-registry first selected face is unavailable"
		Ok(value) => value
	}
	second_selected = match second.registry.prepared_face(second.face) {
		Err(_) => crash "caller unique-registry second selected face is unavailable"
		Ok(value) => value
	}
	first_store = first.registry.store()
	second_store = second.registry.store()
	{
		bytes: second_bytes,
		work: [
			2,
			first.work.input_bytes + second.work.input_bytes,
			first.work.retained_input_bytes + second.work.retained_input_bytes,
			first.work.copied_input_bytes + second.work.copied_input_bytes,
			second_input.len(),
			first.work.table_visits + second.work.table_visits,
			first.work.glyph_visits + second.work.glyph_visits,
			first.work.cmap_mapping_visits + second.work.cmap_mapping_visits,
			first.work.component_edge_visits + second.work.component_edge_visits,
			first_store.resources.len() + second_store.resources.len(),
			first_store.faces.len() + second_store.faces.len(),
			first_store.instances.len() + second_store.instances.len(),
			first_store.policies.len() + second_store.policies.len(),
			2,
			first_bytes.len(),
			second_bytes.len(),
			first_selected.bytes.len() + second_selected.bytes.len(),
		],
	}
}

caller_document : {} -> Document
caller_document = |_| Pdf.document({
	contents: [
		Pdf.paragraph("Café PDF"),
		Pdf.paragraph("Café PDF"),
		Pdf.paragraph("Café PDF"),
	],
	language: "en-AU",
	title: "Caller facade",
})

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

## Invalid caller bytes never yield a registry handle. Since the only facade
## entry point that can receive caller resources takes a Registry, this error
## is atomic: no document plan or PDF byte list exists on this branch.
restricted : U64 -> { bytes : List(U8), work : List(U64) }
restricted = |runtime_argument_count| {
	if runtime_argument_count != 2 {
		crash "text-layout caller facade argument count is invalid"
	}
	match Font.Registry.empty.register(
		restricted_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		facade_limits(runtime_argument_count),
	) {
		Err(EmbeddingRightsProhibited(_)) => { bytes: [], work: [1, 0] }
		_ => crash "restricted caller font was accepted"
	}
}

## The fixture validates its runtime guard before deriving these limits. The
## alternate branch remains a real error policy rather than a compiler-known
## assertion about imported fixture bytes.
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
	Err(OutOfBounds) => crash "text-layout caller facade argument missing"
}
