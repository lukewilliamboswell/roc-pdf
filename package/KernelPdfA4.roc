## The static PDF/A-4 profile boundary. A requested claim is a typed input
## selected by the facade from the public profile; every construct that
## reaches a claimed file is either eligible by construction or checked here
## against an explicit whitelist, and absence from the whitelist is rejection.
##
## Validation runs in two stages over facts earlier stages already produced:
##
## - Profile validation (`validate_text`) consumes the prepared text facts —
##   the exact ToUnicode mappings and the first ActualText run that carries a
##   private-use scalar — which only the text planner can state without
##   re-reading emitted content streams.
## - Lowered-plan validation (`validate_lowered`) consumes the sealed object
##   store before serialization. It classifies each interned name once into a
##   dense tag vector (the only allocation) and then checks every dictionary,
##   stream dictionary, the catalog's metadata and output-intent facts, and
##   the canonical XMP packet in one bounded pass.
##
## A plan without the claim performs only the identification agreement check:
## an unclaimed packet that declares PDF/A identification is a false
## conformance declaration and is rejected without scanning the store.
##
## The first violation in deterministic store order is returned; diagnostics
## never rescan the rejected plan.
import KernelLex
import KernelMetadata
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelSeal
import KernelSrgbProfile
import KernelStructure
import KernelXmp

KernelPdfA4 :: [].{
	Claim : [NoArchiveClaim, StaticPdfA4Claim]

	## One tag per ledger requirement with a runtime check. Requirements that
	## hold by construction (file header, cross-reference streams, string and
	## indirect-object syntax, predefined CMaps, width agreement, and glyph
	## coverage) are pinned by their owning module's expects and recorded in
	## the conformance ledger rather than re-derived here.
	Requirement : [
		ActualTextPrivateUse,
		Actions,
		AdditionalActions,
		AnnotationAppearance,
		AnnotationFlags,
		AnnotationTypes,
		BlendMode,
		CatalogVersion,
		CompositeFont,
		DocumentInformation,
		EmbeddedFiles,
		Encryption,
		FontDictionary,
		FontEmbedding,
		FormXObject,
		GraphicsState,
		Identification,
		ImageDictionary,
		InteractiveForms,
		MetadataStream,
		NameEncoding,
		OptionalContent,
		OutputIntent,
		Permissions,
		Presentations,
		ReferenceXObject,
		RequirementsKey,
		StreamFilters,
		StreamExternal,
		ToUnicodeValues,
	]

	## The stable conformance-ledger identifier for each requirement.
	requirement_code : Requirement -> Str
	requirement_code = |requirement| match requirement {
		ActualTextPrivateUse => "ROC-PDF-PDFA4-6-2-10-8-ACTUAL-TEXT"
		Actions => "ROC-PDF-PDFA4-6-6-1-ACTIONS"
		AdditionalActions => "ROC-PDF-PDFA4-6-6-3-ADDITIONAL-ACTIONS"
		AnnotationAppearance => "ROC-PDF-PDFA4-6-3-3-ANNOTATION-APPEARANCES"
		AnnotationFlags => "ROC-PDF-PDFA4-6-3-2-ANNOTATION-FLAGS"
		AnnotationTypes => "ROC-PDF-PDFA4-6-3-1-ANNOTATION-TYPES"
		BlendMode => "ROC-PDF-PDFA4-6-2-9-TRANSPARENCY"
		CatalogVersion => "ROC-PDF-PDFA4-6-1-12-VERSION"
		CompositeFont => "ROC-PDF-PDFA4-6-2-10-3-COMPOSITE-FONTS"
		DocumentInformation => "ROC-PDF-PDFA4-6-1-3-DOCUMENT-INFORMATION"
		EmbeddedFiles => "ROC-PDF-PDFA4-6-9-EMBEDDED-FILES"
		Encryption => "ROC-PDF-PDFA4-6-1-3-ENCRYPTION"
		FontDictionary => "ROC-PDF-PDFA4-6-2-10-2-FONT-DICTIONARIES"
		FontEmbedding => "ROC-PDF-PDFA4-6-2-10-4-FONT-EMBEDDING"
		FormXObject => "ROC-PDF-PDFA4-6-2-8-1-FORM-XOBJECTS"
		GraphicsState => "ROC-PDF-PDFA4-6-2-5-GRAPHICS-STATE"
		Identification => "ROC-PDF-PDFA4-6-7-3-IDENTIFICATION"
		ImageDictionary => "ROC-PDF-PDFA4-6-2-7-1-IMAGES"
		InteractiveForms => "ROC-PDF-PDFA4-6-4-INTERACTIVE-FORMS"
		MetadataStream => "ROC-PDF-PDFA4-6-7-2-METADATA"
		NameEncoding => "ROC-PDF-PDFA4-6-1-7-NAMES"
		OptionalContent => "ROC-PDF-PDFA4-6-10-OPTIONAL-CONTENT"
		OutputIntent => "ROC-PDF-PDFA4-6-2-3-OUTPUT-INTENT"
		Permissions => "ROC-PDF-PDFA4-6-1-11-PERMISSIONS"
		Presentations => "ROC-PDF-PDFA4-6-11-PRESENTATIONS"
		ReferenceXObject => "ROC-PDF-PDFA4-6-2-8-2-REFERENCE-XOBJECTS"
		RequirementsKey => "ROC-PDF-PDFA4-6-12-REQUIREMENTS"
		StreamExternal => "ROC-PDF-PDFA4-6-1-6-1-EXTERNAL-STREAMS"
		StreamFilters => "ROC-PDF-PDFA4-6-1-6-2-FILTERS"
		ToUnicodeValues => "ROC-PDF-PDFA4-6-2-10-7-TO-UNICODE"
	}

	## The ISO 19005-4:2020 clause each requirement implements.
	clause : Requirement -> Str
	clause = |requirement| match requirement {
		ActualTextPrivateUse => "ISO 19005-4:2020 6.2.10.8"
		Actions => "ISO 19005-4:2020 6.6.1"
		AdditionalActions => "ISO 19005-4:2020 6.6.3"
		AnnotationAppearance => "ISO 19005-4:2020 6.3.3"
		AnnotationFlags => "ISO 19005-4:2020 6.3.2"
		AnnotationTypes => "ISO 19005-4:2020 6.3.1"
		BlendMode => "ISO 19005-4:2020 6.2.9"
		CatalogVersion => "ISO 19005-4:2020 6.1.12"
		CompositeFont => "ISO 19005-4:2020 6.2.10.3"
		DocumentInformation => "ISO 19005-4:2020 6.1.3"
		EmbeddedFiles => "ISO 19005-4:2020 6.9"
		Encryption => "ISO 19005-4:2020 6.1.3"
		FontDictionary => "ISO 19005-4:2020 6.2.10.2"
		FontEmbedding => "ISO 19005-4:2020 6.2.10.4"
		FormXObject => "ISO 19005-4:2020 6.2.8.1"
		GraphicsState => "ISO 19005-4:2020 6.2.5"
		Identification => "ISO 19005-4:2020 6.7.3"
		ImageDictionary => "ISO 19005-4:2020 6.2.7.1"
		InteractiveForms => "ISO 19005-4:2020 6.4"
		MetadataStream => "ISO 19005-4:2020 6.7.2"
		NameEncoding => "ISO 19005-4:2020 6.1.7"
		OptionalContent => "ISO 19005-4:2020 6.10"
		OutputIntent => "ISO 19005-4:2020 6.2.3"
		Permissions => "ISO 19005-4:2020 6.1.11"
		Presentations => "ISO 19005-4:2020 6.11"
		ReferenceXObject => "ISO 19005-4:2020 6.2.8.2"
		RequirementsKey => "ISO 19005-4:2020 6.12"
		StreamExternal => "ISO 19005-4:2020 6.1.6.1"
		StreamFilters => "ISO 19005-4:2020 6.1.6.2"
		ToUnicodeValues => "ISO 19005-4:2020 6.2.10.7"
	}

	## A short author-facing statement of what the requirement forbids.
	summary : Requirement -> Str
	summary = |requirement| match requirement {
		ActualTextPrivateUse => "ActualText replacement text must not contain Private Use Area characters"
		Actions => "only URI and GoTo actions without chained actions are supported"
		AdditionalActions => "additional-action (AA) entries are not permitted"
		AnnotationAppearance => "an annotation appearance must be a single normal appearance stream"
		AnnotationFlags => "annotations must be printable and never hidden"
		AnnotationTypes => "only link annotations are supported"
		BlendMode => "only the Normal blend mode is supported"
		CatalogVersion => "the catalog version must be a PDF 2.x version"
		CompositeFont => "CIDFontType2 fonts must carry a CIDToGIDMap"
		DocumentInformation => "document-information and PieceInfo data are not permitted"
		EmbeddedFiles => "embedded and associated files are not permitted"
		Encryption => "encryption is not permitted"
		FontDictionary => "only embedded Type 0 fonts with CIDFontType2 descendants are supported"
		FontEmbedding => "every font program must be embedded as FontFile2"
		FormXObject => "form XObjects must not carry OPI data"
		GraphicsState => "transfer functions and halftones are not permitted"
		Identification => "the XMP packet must declare exactly the requested PDF/A identification"
		ImageDictionary => "images must use a permitted bit depth without interpolation, alternates, or OPI"
		InteractiveForms => "interactive forms are not permitted"
		MetadataStream => "the catalog must reference an unfiltered XML metadata stream"
		NameEncoding => "PDF names must be valid UTF-8"
		OptionalContent => "optional content is not permitted"
		OutputIntent => "exactly one PDF/A output intent with an embedded monitor or output profile is required"
		Permissions => "permissions dictionaries are not permitted"
		Presentations => "alternate presentations and presentation steps are not permitted"
		ReferenceXObject => "reference XObjects are not permitted"
		RequirementsKey => "document requirements are not permitted"
		StreamExternal => "streams must not reference external files"
		StreamFilters => "only FlateDecode and DCTDecode filters are supported"
		ToUnicodeValues => "ToUnicode mappings must not contain U+0000, U+FEFF, or U+FFFE"
	}

	## `position` is the dense store value, stream, or text-fact index at which
	## the violation was found; it is deterministic and never an object number
	## exposed to authors.
	Violation : { position : U64, requirement : Requirement }

	## The prepared text facts consumed by profile validation.
	TextFacts : {
		actual_text : KernelPdfText.ActualTextPrivateUse,
		mappings : List(List(KernelPdfFont.UnicodeMapping)),
	}

	TextWork : { mappings_checked : U64, scalars_checked : U64 }

	## Profile validation over the prepared text facts.
	validate_text : Claim, TextFacts -> Try(TextWork, Violation)
	validate_text = |claim, facts| check_text(claim, facts)

	LoweredWork : {
		entries_checked : U64,
		names_classified : U64,
		packet_bytes_compared : U64,
		streams_checked : U64,
		values_checked : U64,
	}

	## The lowered-plan facts: the sealed store, its catalog, and the exact
	## canonical packet the facade built for this claim.
	LoweredInput : {
		packet : KernelXmp.Packet,
		root : KernelObject.ObjectId,
		sealed : KernelSeal.Plan,
	}

	## Lowered-plan validation over the sealed store before serialization.
	validate_lowered : Claim, LoweredInput -> Try(LoweredWork, Violation)
	validate_lowered = |claim, input| check_lowered(claim, input)

	## The identification a claim requires in its canonical packet.
	identification : Claim -> KernelXmp.Identification
	identification = |claim| match claim {
		NoArchiveClaim => NoIdentification
		StaticPdfA4Claim => PdfA4Identification
	}
}

check_text : KernelPdfA4.Claim, KernelPdfA4.TextFacts -> Try(KernelPdfA4.TextWork, KernelPdfA4.Violation)
check_text = |claim, facts| match claim {
	NoArchiveClaim => Ok({ mappings_checked: 0, scalars_checked: 0 })
	StaticPdfA4Claim => {
		match facts.actual_text {
			PrivateUseInRun(run) => return Err({ position: run, requirement: ActualTextPrivateUse })
			NoPrivateUse => {}
		}
		var $mappings_checked = 0
		var $scalars_checked = 0
		var $font = 0
		while $font < facts.mappings.len() {
			mappings = list_at(facts.mappings, $font)
			var $mapping = 0
			while $mapping < mappings.len() {
				scalars = list_at(mappings, $mapping).scalars
				var $scalar = 0
				while $scalar < scalars.len() {
					value = list_at(scalars, $scalar)
					if value == 0 or value == 0xFEFF or value == 0xFFFE {
						return Err({ position: $mappings_checked, requirement: ToUnicodeValues })
					}
					$scalar = $scalar + 1
				}
				$scalars_checked = $scalars_checked + scalars.len()
				$mappings_checked = $mappings_checked + 1
				$mapping = $mapping + 1
			}
			$font = $font + 1
		}
		Ok({ mappings_checked: $mappings_checked, scalars_checked: $scalars_checked })
	}
}

## ISO 19005-4 6.1.7 constrains the UTF-8 form of font, colorant, and
## structure-type names; checking every interned name is the whitelist
## superset because no other name family is exempt in package output.
NameClass : [
	Other,
	Aa,
	AcroForm,
	Af,
	AlternatePresentations,
	Alternates,
	Annot,
	Ap,
	BitsPerComponent,
	Bm,
	CidFontType2,
	CidToGidMap,
	DctDecode,
	DestOutputProfile,
	DestOutputProfileRef,
	EmbeddedFiles,
	Encrypt,
	F,
	FDecodeParms,
	FFilter,
	Filter,
	FlateDecode,
	Font,
	FontDescriptor,
	FontFile,
	FontFile2,
	FontFile3,
	Form,
	GoTo,
	GoTo3DView,
	GoToDp,
	GoToE,
	GoToR,
	GtsPdfa1,
	Hide,
	Ht,
	Hto,
	Image,
	ImageMask,
	ImportData,
	Interpolate,
	JavaScript,
	Js,
	Launch,
	Link,
	Metadata,
	Movie,
	N,
	Named,
	NeedAppearances,
	NeedsRendering,
	Next,
	Nop,
	Normal,
	Oc,
	OcProperties,
	Opi,
	OutputIntents,
	Perms,
	PieceInfo,
	PresSteps,
	Ref,
	Rendition,
	Requirements,
	ResetForm,
	RichMediaExecute,
	S,
	SetOCGState,
	SetState,
	Sound,
	SubmitForm,
	Subtype,
	Thread,
	Tr,
	Tr2,
	Trans,
	Type,
	Type0,
	Uri,
	Version,
	XObject,
	Xfa,
	Xml,
]

Summary : {
	ap : [Absent, Present(KernelObject.ValueId)],
	bits : [Absent, Present(I64)],
	cid_to_gid : Bool,
	flags : [Absent, Present(I64)],
	font_file2 : Bool,
	image_mask : Bool,
	next : Bool,
	opi : Bool,
	other_font_file : Bool,
	s : NameClass,
	subtype : NameClass,
	type_name : NameClass,
}

DictionaryKind : [PlainDictionary, StreamDictionary]

empty_summary : Summary
empty_summary = {
	ap: Absent,
	bits: Absent,
	cid_to_gid: False,
	flags: Absent,
	font_file2: False,
	image_mask: False,
	next: False,
	opi: False,
	other_font_file: False,
	s: Other,
	subtype: Other,
	type_name: Other,
}

check_lowered : KernelPdfA4.Claim, KernelPdfA4.LoweredInput -> Try(KernelPdfA4.LoweredWork, KernelPdfA4.Violation)
check_lowered = |claim, input| {
	if KernelXmp.Packet.identification(input.packet) != KernelPdfA4.identification(claim) {
		return Err({ position: 0, requirement: Identification })
	}
	match claim {
		NoArchiveClaim => Ok({ entries_checked: 0, names_classified: 0, packet_bytes_compared: 0, streams_checked: 0, values_checked: 0 })
		StaticPdfA4Claim => validate_claimed_store(KernelSeal.Plan.store(input.sealed), input.root, KernelXmp.Packet.bytes(input.packet))
	}
}

validate_claimed_store : KernelObject.Store, KernelObject.ObjectId, List(U8) -> Try(KernelPdfA4.LoweredWork, KernelPdfA4.Violation)
validate_claimed_store = |store, root, packet| {
	classes = classify_names(store.names)?
	var $entries_checked = 0
	var $value = 0
	while $value < store.values.len() {
		match list_at(store.values, $value) {
			Dictionary(span) => {
				check_dictionary(store, classes, span, PlainDictionary, $value)?
				$entries_checked = $entries_checked + span.length
			}
			_ => {}
		}
		$value = $value + 1
	}
	var $stream = 0
	while $stream < store.streams.len() {
		stream = list_at(store.streams, $stream)
		check_dictionary(store, classes, stream.dictionary, StreamDictionary, $stream)?
		$entries_checked = $entries_checked + stream.dictionary.length
		$stream = $stream + 1
	}
	compared = check_catalog(store, classes, root, packet)?
	Ok({
		entries_checked: $entries_checked,
		names_classified: classes.len(),
		packet_bytes_compared: compared,
		streams_checked: store.streams.len(),
		values_checked: store.values.len(),
	})
}

classify_names : List(KernelLex.Name) -> Try(List(NameClass), KernelPdfA4.Violation)
classify_names = |names| {
	var $classes = List.with_capacity(names.len())
	var $index = 0
	while $index < names.len() {
		bytes = KernelLex.Name.bytes(list_at(names, $index))
		if !valid_utf8(bytes) {
			return Err({ position: $index, requirement: NameEncoding })
		}
		$classes = $classes.append(classify(bytes))
		$index = $index + 1
	}
	Ok($classes)
}

classify : List(U8) -> NameClass
classify = |bytes| {
	var $index = 0
	while $index < name_table.len() {
		entry = list_at(name_table, $index)
		if entry.bytes.len() == bytes.len() and entry.bytes == bytes {
			return entry.class
		}
		$index = $index + 1
	}
	Other
}

## Strict UTF-8 structure: no overlong forms, surrogates, or scalars above
## U+10FFFF.
valid_utf8 : List(U8) -> Bool
valid_utf8 = |bytes| {
	var $index = 0
	while $index < bytes.len() {
		lead = list_at(bytes, $index)
		if lead < 0x80 {
			$index = $index + 1
		} else {
			width = if lead >= 0xC2 and lead <= 0xDF 2 else if lead >= 0xE0 and lead <= 0xEF 3 else if lead >= 0xF0 and lead <= 0xF4 4 else 0
			if width == 0 or $index + width > bytes.len() {
				return False
			}
			second = list_at(bytes, $index + 1)
			low = if lead == 0xE0 0xA0 else if lead == 0xF0 0x90 else 0x80
			high = if lead == 0xED 0x9F else if lead == 0xF4 0x8F else 0xBF
			if second < low or second > high {
				return False
			}
			var $continuation = 2
			while $continuation < width {
				byte = list_at(bytes, $index + $continuation)
				if byte < 0x80 or byte > 0xBF {
					return False
				}
				$continuation = $continuation + 1
			}
			$index = $index + width
		}
	}
	True
}

name_class : KernelObject.Store, List(NameClass), KernelObject.NameId -> NameClass
name_class = |_store, classes, name| list_at(classes, KernelObject.NameId.index(name))

value_name_class : KernelObject.Store, List(NameClass), KernelObject.ValueId -> NameClass
value_name_class = |store, classes, value| match list_at(store.values, KernelObject.ValueId.index(value)) {
	Name(name) => name_class(store, classes, name)
	_ => Other
}

## Forbidden keys map directly to their requirement; everything else is
## summarized for the kind-specific checks below.
check_dictionary : KernelObject.Store, List(NameClass), KernelObject.Span, DictionaryKind, U64 -> Try({}, KernelPdfA4.Violation)
check_dictionary = |store, classes, span, kind, position| {
	var $summary = empty_summary
	var $entry = span.start
	end = span.start + span.length
	while $entry < end {
		entry = list_at(store.dictionary_entries, $entry)
		key = name_class(store, classes, entry.key)
		forbidden = forbidden_key(key, kind)
		match forbidden {
			Forbidden(requirement) => return Err({ position, requirement })
			Allowed => {}
		}
		match key {
			Type => {
				$summary = { ..$summary, type_name: value_name_class(store, classes, entry.value) }
			}
			Subtype => {
				$summary = { ..$summary, subtype: value_name_class(store, classes, entry.value) }
			}
			S => {
				$summary = { ..$summary, s: value_name_class(store, classes, entry.value) }
			}
			F => match list_at(store.values, KernelObject.ValueId.index(entry.value)) {
				Integer(value) => {
					$summary = { ..$summary, flags: Present(value) }
				}
				_ => {}
			}
			Ap => {
				$summary = { ..$summary, ap: Present(entry.value) }
			}
			BitsPerComponent => match list_at(store.values, KernelObject.ValueId.index(entry.value)) {
				Integer(value) => {
					$summary = { ..$summary, bits: Present(value) }
				}
				_ => return Err({ position, requirement: ImageDictionary })
			}
			ImageMask => match list_at(store.values, KernelObject.ValueId.index(entry.value)) {
				Boolean(value) => {
					$summary = { ..$summary, image_mask: value }
				}
				_ => {}
			}
			Interpolate => match list_at(store.values, KernelObject.ValueId.index(entry.value)) {
				Boolean(False) => {}
				_ => return Err({ position, requirement: ImageDictionary })
			}
			Bm => if !names_all(store, classes, entry.value, Normal, Normal) {
				return Err({ position, requirement: BlendMode })
			}
			Filter => if !names_all(store, classes, entry.value, FlateDecode, DctDecode) {
				return Err({ position, requirement: StreamFilters })
			}
			CidToGidMap => {
				$summary = { ..$summary, cid_to_gid: True }
			}
			FontFile2 => {
				$summary = { ..$summary, font_file2: True }
			}
			FontFile => {
				$summary = { ..$summary, other_font_file: True }
			}
			FontFile3 => {
				$summary = { ..$summary, other_font_file: True }
			}
			Next => {
				$summary = { ..$summary, next: True }
			}
			Opi => {
				$summary = { ..$summary, opi: True }
			}
			_ => {}
		}
		$entry = $entry + 1
	}
	check_summary(store, classes, $summary, position)
}

ForbiddenKey : [Allowed, Forbidden(KernelPdfA4.Requirement)]

forbidden_key : NameClass, DictionaryKind -> ForbiddenKey
forbidden_key = |key, kind| match key {
	Encrypt => Forbidden(Encryption)
	PieceInfo => Forbidden(DocumentInformation)
	FFilter => Forbidden(StreamExternal)
	FDecodeParms => Forbidden(StreamExternal)
	F => match kind {
		StreamDictionary => Forbidden(StreamExternal)
		PlainDictionary => Allowed
	}
	Perms => Forbidden(Permissions)
	DestOutputProfileRef => Forbidden(OutputIntent)
	Tr => Forbidden(GraphicsState)
	Tr2 => Forbidden(GraphicsState)
	Ht => Forbidden(GraphicsState)
	Hto => Forbidden(GraphicsState)
	Alternates => Forbidden(ImageDictionary)
	Ref => Forbidden(ReferenceXObject)
	AcroForm => Forbidden(InteractiveForms)
	NeedAppearances => Forbidden(InteractiveForms)
	NeedsRendering => Forbidden(InteractiveForms)
	Xfa => Forbidden(InteractiveForms)
	Js => Forbidden(Actions)
	JavaScript => Forbidden(Actions)
	Aa => Forbidden(AdditionalActions)
	EmbeddedFiles => Forbidden(EmbeddedFiles)
	Af => Forbidden(EmbeddedFiles)
	OcProperties => Forbidden(OptionalContent)
	Oc => Forbidden(OptionalContent)
	AlternatePresentations => Forbidden(Presentations)
	PresSteps => Forbidden(Presentations)
	Requirements => Forbidden(RequirementsKey)
	_ => Allowed
}

## A name value, or an array whose items are all names, drawn from at most
## two whitelisted classes.
names_all : KernelObject.Store, List(NameClass), KernelObject.ValueId, NameClass, NameClass -> Bool
names_all = |store, classes, value, first, second| match list_at(store.values, KernelObject.ValueId.index(value)) {
	Name(name) => {
		class = name_class(store, classes, name)
		class == first or class == second
	}
	Array(span) => {
		var $item = span.start
		var $valid = True
		while $valid and $item < span.start + span.length {
			class = value_name_class(store, classes, list_at(store.array_items, $item))
			$valid = class == first or class == second
			$item = $item + 1
		}
		$valid
	}
	_ => False
}

check_summary : KernelObject.Store, List(NameClass), Summary, U64 -> Try({}, KernelPdfA4.Violation)
check_summary = |store, classes, summary, position| {
	if is_action_type(summary.s) {
		if (summary.s != Uri and summary.s != GoTo) or summary.next {
			return Err({ position, requirement: Actions })
		}
	}
	if summary.opi {
		requirement = if summary.subtype == Form FormXObject else ImageDictionary
		return Err({ position, requirement })
	}
	match summary.bits {
		Present(bits) => if (bits != 1 and bits != 2 and bits != 4 and bits != 8 and bits != 16) or (summary.image_mask and bits != 1) {
			return Err({ position, requirement: ImageDictionary })
		}
		Absent => {}
	}
	if summary.type_name == Annot or summary.subtype == Link {
		check_annotation(store, classes, summary, position)?
	}
	if summary.type_name == Font {
		if summary.subtype != Type0 and summary.subtype != CidFontType2 {
			return Err({ position, requirement: FontDictionary })
		}
		if summary.subtype == CidFontType2 and !summary.cid_to_gid {
			return Err({ position, requirement: CompositeFont })
		}
	}
	if summary.type_name == FontDescriptor and (!summary.font_file2 or summary.other_font_file) {
		return Err({ position, requirement: FontEmbedding })
	}
	Ok({})
}

is_action_type : NameClass -> Bool
is_action_type = |class| match class {
	GoTo | GoTo3DView | GoToDp | GoToE | GoToR | Hide | ImportData | JavaScript | Launch | Movie | Named | Nop | Rendition | ResetForm | RichMediaExecute | SetOCGState | SetState | Sound | SubmitForm | Thread | Trans | Uri => True
	_ => False
}

## The package emits only link annotations, always printable and visible.
## ISO 19005-4 6.3.3 exempts link annotations from requiring an appearance,
## so facade links without `/AP` are eligible; an appearance that is present
## must be a single normal appearance stream.
check_annotation : KernelObject.Store, List(NameClass), Summary, U64 -> Try({}, KernelPdfA4.Violation)
check_annotation = |store, classes, summary, position| {
	if summary.subtype != Link {
		return Err({ position, requirement: AnnotationTypes })
	}
	match summary.flags {
		Absent => return Err({ position, requirement: AnnotationFlags })
		Present(flags) => if flags.bitwise_and(4) == 0 or flags.bitwise_and(1 + 2 + 32 + 256) != 0 {
			return Err({ position, requirement: AnnotationFlags })
		}
	}
	match summary.ap {
		Absent => Ok({})
		Present(appearance) => {
			span = match resolve_dictionary(store, appearance) {
				Resolved(found) => found
				NotDictionary => return Err({ position, requirement: AnnotationAppearance })
			}
			if span.length != 1 {
				return Err({ position, requirement: AnnotationAppearance })
			}
			entry = list_at(store.dictionary_entries, span.start)
			if name_class(store, classes, entry.key) != N or !is_stream(store, entry.value) {
				return Err({ position, requirement: AnnotationAppearance })
			}
			Ok({})
		}
	}
}

Resolution : [NotDictionary, Resolved(KernelObject.Span)]

resolve_dictionary : KernelObject.Store, KernelObject.ValueId -> Resolution
resolve_dictionary = |store, value| match list_at(store.values, KernelObject.ValueId.index(value)) {
	Dictionary(span) => Resolved(span)
	Reference(object) => match list_at(store.objects, KernelObject.ObjectId.number(object) - 1).content {
		Stored(stored) => match list_at(store.values, KernelObject.ValueId.index(stored)) {
			Dictionary(span) => Resolved(span)
			_ => NotDictionary
		}
		LengthOf(_) => NotDictionary
	}
	_ => NotDictionary
}

resolve_stream : KernelObject.Store, KernelObject.ValueId -> [NotStream, ResolvedStream(KernelObject.Stream)]
resolve_stream = |store, value| {
	stream_value = match list_at(store.values, KernelObject.ValueId.index(value)) {
		Reference(object) => match list_at(store.objects, KernelObject.ObjectId.number(object) - 1).content {
			Stored(stored) => list_at(store.values, KernelObject.ValueId.index(stored))
			LengthOf(_) => Null
		}
		direct => direct
	}
	match stream_value {
		Stream(stream) => ResolvedStream(list_at(store.streams, KernelObject.StreamId.index(stream)))
		_ => NotStream
	}
}

is_stream : KernelObject.Store, KernelObject.ValueId -> Bool
is_stream = |store, value| match resolve_stream(store, value) {
	ResolvedStream(_) => True
	NotStream => False
}

## The catalog must carry exactly the claim's canonical metadata stream, one
## PDF/A output intent with an embedded monitor or output profile, and no
## pre-2.0 version override.
check_catalog : KernelObject.Store, List(NameClass), KernelObject.ObjectId, List(U8) -> Try(U64, KernelPdfA4.Violation)
check_catalog = |store, classes, root, packet| {
	root_index = KernelObject.ObjectId.number(root) - 1
	catalog = match list_at(store.objects, root_index).content {
		Stored(value) => match list_at(store.values, KernelObject.ValueId.index(value)) {
			Dictionary(span) => span
			_ => return Err({ position: root_index, requirement: MetadataStream })
		}
		LengthOf(_) => return Err({ position: root_index, requirement: MetadataStream })
	}
	var $metadata = Absent
	var $intents = Absent
	var $entry = catalog.start
	while $entry < catalog.start + catalog.length {
		entry = list_at(store.dictionary_entries, $entry)
		match name_class(store, classes, entry.key) {
			Metadata => {
				$metadata = Present(entry.value)
			}
			OutputIntents => {
				$intents = Present(entry.value)
			}
			Version => match list_at(store.values, KernelObject.ValueId.index(entry.value)) {
				Name(name) => {
					bytes = KernelLex.Name.bytes(list_at(store.names, KernelObject.NameId.index(name)))
					if bytes.len() < 3 or list_at(bytes, 0) != 50 or list_at(bytes, 1) != 46 {
						return Err({ position: root_index, requirement: CatalogVersion })
					}
				}
				_ => return Err({ position: root_index, requirement: CatalogVersion })
			}
			_ => {}
		}
		$entry = $entry + 1
	}
	compared = match $metadata {
		Absent => return Err({ position: root_index, requirement: MetadataStream })
		Present(value) => check_metadata(store, classes, value, packet, root_index)?
	}
	match $intents {
		Absent => return Err({ position: root_index, requirement: OutputIntent })
		Present(value) => check_output_intents(store, classes, value, root_index)?
	}
	Ok(compared)
}

check_metadata : KernelObject.Store, List(NameClass), KernelObject.ValueId, List(U8), U64 -> Try(U64, KernelPdfA4.Violation)
check_metadata = |store, classes, value, packet, position| {
	stream = match resolve_stream(store, value) {
		ResolvedStream(found) => found
		NotStream => return Err({ position, requirement: MetadataStream })
	}
	if stream.filter != Unfiltered {
		return Err({ position, requirement: MetadataStream })
	}
	var $type = Other
	var $subtype = Other
	var $entry = stream.dictionary.start
	while $entry < stream.dictionary.start + stream.dictionary.length {
		entry = list_at(store.dictionary_entries, $entry)
		match name_class(store, classes, entry.key) {
			Type => {
				$type = value_name_class(store, classes, entry.value)
			}
			Subtype => {
				$subtype = value_name_class(store, classes, entry.value)
			}
			_ => {}
		}
		$entry = $entry + 1
	}
	if $type != Metadata or $subtype != Xml {
		return Err({ position, requirement: MetadataStream })
	}
	payload = list_at(store.payloads, KernelObject.PayloadId.index(stream.source)).bytes
	if payload.len() != packet.len() or payload != packet {
		return Err({ position, requirement: Identification })
	}
	Ok(packet.len())
}

check_output_intents : KernelObject.Store, List(NameClass), KernelObject.ValueId, U64 -> Try({}, KernelPdfA4.Violation)
check_output_intents = |store, classes, value, position| {
	items = match list_at(store.values, KernelObject.ValueId.index(value)) {
		Array(span) => span
		_ => return Err({ position, requirement: OutputIntent })
	}
	if items.length != 1 {
		return Err({ position, requirement: OutputIntent })
	}
	intent = match resolve_dictionary(store, list_at(store.array_items, items.start)) {
		Resolved(span) => span
		NotDictionary => return Err({ position, requirement: OutputIntent })
	}
	var $subtype = Other
	var $profile = Absent
	var $entry = intent.start
	while $entry < intent.start + intent.length {
		entry = list_at(store.dictionary_entries, $entry)
		match name_class(store, classes, entry.key) {
			S => {
				$subtype = value_name_class(store, classes, entry.value)
			}
			DestOutputProfile => {
				$profile = Present(entry.value)
			}
			_ => {}
		}
		$entry = $entry + 1
	}
	if $subtype != GtsPdfa1 {
		return Err({ position, requirement: OutputIntent })
	}
	stream = match $profile {
		Absent => return Err({ position, requirement: OutputIntent })
		Present(profile) => match resolve_stream(store, profile) {
			ResolvedStream(found) => found
			NotStream => return Err({ position, requirement: OutputIntent })
		}
	}
	profile_bytes = list_at(store.payloads, KernelObject.PayloadId.index(stream.source)).bytes
	if profile_bytes.len() < 128 {
		return Err({ position, requirement: OutputIntent })
	}
	major = list_at(profile_bytes, 8)
	class = profile_bytes.sublist({ start: 12, len: 4 })

	## 'mntr' and 'prtr' device classes; ICC major versions 2 through 4.
	if major < 2 or major > 4 or (class != [109, 110, 116, 114] and class != [112, 114, 116, 114]) {
		return Err({ position, requirement: OutputIntent })
	}
	Ok({})
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "sealed PDF/A-4 store index escaped"
	}
	Ok(value) => value
}

## Classified names, compared by exact bytes. Entries are distinct, so table
## order does not affect the result.
name_table : List({ bytes : List(U8), class : NameClass })
name_table = [
	{ bytes: [70], class: F }, # F
	{ bytes: [78], class: N }, # N
	{ bytes: [83], class: S }, # S
	{ bytes: [65, 65], class: Aa }, # AA
	{ bytes: [65, 70], class: Af }, # AF
	{ bytes: [65, 80], class: Ap }, # AP
	{ bytes: [66, 77], class: Bm }, # BM
	{ bytes: [72, 84], class: Ht }, # HT
	{ bytes: [74, 83], class: Js }, # JS
	{ bytes: [79, 67], class: Oc }, # OC
	{ bytes: [84, 82], class: Tr }, # TR
	{ bytes: [72, 84, 79], class: Hto }, # HTO
	{ bytes: [78, 79, 80], class: Nop }, # NOP
	{ bytes: [79, 80, 73], class: Opi }, # OPI
	{ bytes: [82, 101, 102], class: Ref }, # Ref
	{ bytes: [84, 82, 50], class: Tr2 }, # TR2
	{ bytes: [85, 82, 73], class: Uri }, # URI
	{ bytes: [88, 70, 65], class: Xfa }, # XFA
	{ bytes: [88, 77, 76], class: Xml }, # XML
	{ bytes: [70, 111, 110, 116], class: Font }, # Font
	{ bytes: [70, 111, 114, 109], class: Form }, # Form
	{ bytes: [71, 111, 84, 111], class: GoTo }, # GoTo
	{ bytes: [72, 105, 100, 101], class: Hide }, # Hide
	{ bytes: [76, 105, 110, 107], class: Link }, # Link
	{ bytes: [78, 101, 120, 116], class: Next }, # Next
	{ bytes: [84, 121, 112, 101], class: Type }, # Type
	{ bytes: [65, 110, 110, 111, 116], class: Annot }, # Annot
	{ bytes: [71, 111, 84, 111, 69], class: GoToE }, # GoToE
	{ bytes: [71, 111, 84, 111, 82], class: GoToR }, # GoToR
	{ bytes: [73, 109, 97, 103, 101], class: Image }, # Image
	{ bytes: [77, 111, 118, 105, 101], class: Movie }, # Movie
	{ bytes: [78, 97, 109, 101, 100], class: Named }, # Named
	{ bytes: [80, 101, 114, 109, 115], class: Perms }, # Perms
	{ bytes: [83, 111, 117, 110, 100], class: Sound }, # Sound
	{ bytes: [84, 114, 97, 110, 115], class: Trans }, # Trans
	{ bytes: [84, 121, 112, 101, 48], class: Type0 }, # Type0
	{ bytes: [70, 105, 108, 116, 101, 114], class: Filter }, # Filter
	{ bytes: [71, 111, 84, 111, 68, 112], class: GoToDp }, # GoToDp
	{ bytes: [76, 97, 117, 110, 99, 104], class: Launch }, # Launch
	{ bytes: [78, 111, 114, 109, 97, 108], class: Normal }, # Normal
	{ bytes: [84, 104, 114, 101, 97, 100], class: Thread }, # Thread
	{ bytes: [69, 110, 99, 114, 121, 112, 116], class: Encrypt }, # Encrypt
	{ bytes: [70, 70, 105, 108, 116, 101, 114], class: FFilter }, # FFilter
	{ bytes: [83, 117, 98, 116, 121, 112, 101], class: Subtype }, # Subtype
	{ bytes: [86, 101, 114, 115, 105, 111, 110], class: Version }, # Version
	{ bytes: [88, 79, 98, 106, 101, 99, 116], class: XObject }, # XObject
	{ bytes: [65, 99, 114, 111, 70, 111, 114, 109], class: AcroForm }, # AcroForm
	{ bytes: [70, 111, 110, 116, 70, 105, 108, 101], class: FontFile }, # FontFile
	{ bytes: [77, 101, 116, 97, 100, 97, 116, 97], class: Metadata }, # Metadata
	{ bytes: [83, 101, 116, 83, 116, 97, 116, 101], class: SetState }, # SetState
	{ bytes: [68, 67, 84, 68, 101, 99, 111, 100, 101], class: DctDecode }, # DCTDecode
	{ bytes: [70, 111, 110, 116, 70, 105, 108, 101, 50], class: FontFile2 }, # FontFile2
	{ bytes: [70, 111, 110, 116, 70, 105, 108, 101, 51], class: FontFile3 }, # FontFile3
	{ bytes: [71, 84, 83, 95, 80, 68, 70, 65, 49], class: GtsPdfa1 }, # GTS_PDFA1
	{ bytes: [73, 109, 97, 103, 101, 77, 97, 115, 107], class: ImageMask }, # ImageMask
	{ bytes: [80, 105, 101, 99, 101, 73, 110, 102, 111], class: PieceInfo }, # PieceInfo
	{ bytes: [80, 114, 101, 115, 83, 116, 101, 112, 115], class: PresSteps }, # PresSteps
	{ bytes: [82, 101, 110, 100, 105, 116, 105, 111, 110], class: Rendition }, # Rendition
	{ bytes: [82, 101, 115, 101, 116, 70, 111, 114, 109], class: ResetForm }, # ResetForm
	{ bytes: [65, 108, 116, 101, 114, 110, 97, 116, 101, 115], class: Alternates }, # Alternates
	{ bytes: [71, 111, 84, 111, 51, 68, 86, 105, 101, 119], class: GoTo3DView }, # GoTo3DView
	{ bytes: [73, 109, 112, 111, 114, 116, 68, 97, 116, 97], class: ImportData }, # ImportData
	{ bytes: [74, 97, 118, 97, 83, 99, 114, 105, 112, 116], class: JavaScript }, # JavaScript
	{ bytes: [83, 117, 98, 109, 105, 116, 70, 111, 114, 109], class: SubmitForm }, # SubmitForm
	{ bytes: [67, 73, 68, 84, 111, 71, 73, 68, 77, 97, 112], class: CidToGidMap }, # CIDToGIDMap
	{ bytes: [70, 108, 97, 116, 101, 68, 101, 99, 111, 100, 101], class: FlateDecode }, # FlateDecode
	{ bytes: [73, 110, 116, 101, 114, 112, 111, 108, 97, 116, 101], class: Interpolate }, # Interpolate
	{ bytes: [83, 101, 116, 79, 67, 71, 83, 116, 97, 116, 101], class: SetOCGState }, # SetOCGState
	{ bytes: [67, 73, 68, 70, 111, 110, 116, 84, 121, 112, 101, 50], class: CidFontType2 }, # CIDFontType2
	{ bytes: [70, 68, 101, 99, 111, 100, 101, 80, 97, 114, 109, 115], class: FDecodeParms }, # FDecodeParms
	{ bytes: [79, 67, 80, 114, 111, 112, 101, 114, 116, 105, 101, 115], class: OcProperties }, # OCProperties
	{ bytes: [82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 115], class: Requirements }, # Requirements
	{ bytes: [69, 109, 98, 101, 100, 100, 101, 100, 70, 105, 108, 101, 115], class: EmbeddedFiles }, # EmbeddedFiles
	{ bytes: [79, 117, 116, 112, 117, 116, 73, 110, 116, 101, 110, 116, 115], class: OutputIntents }, # OutputIntents
	{ bytes: [70, 111, 110, 116, 68, 101, 115, 99, 114, 105, 112, 116, 111, 114], class: FontDescriptor }, # FontDescriptor
	{ bytes: [78, 101, 101, 100, 115, 82, 101, 110, 100, 101, 114, 105, 110, 103], class: NeedsRendering }, # NeedsRendering
	{ bytes: [78, 101, 101, 100, 65, 112, 112, 101, 97, 114, 97, 110, 99, 101, 115], class: NeedAppearances }, # NeedAppearances
	{ bytes: [66, 105, 116, 115, 80, 101, 114, 67, 111, 109, 112, 111, 110, 101, 110, 116], class: BitsPerComponent }, # BitsPerComponent
	{ bytes: [82, 105, 99, 104, 77, 101, 100, 105, 97, 69, 120, 101, 99, 117, 116, 101], class: RichMediaExecute }, # RichMediaExecute
	{ bytes: [68, 101, 115, 116, 79, 117, 116, 112, 117, 116, 80, 114, 111, 102, 105, 108, 101], class: DestOutputProfile }, # DestOutputProfile
	{ bytes: [68, 101, 115, 116, 79, 117, 116, 112, 117, 116, 80, 114, 111, 102, 105, 108, 101, 82, 101, 102], class: DestOutputProfileRef }, # DestOutputProfileRef
	{ bytes: [65, 108, 116, 101, 114, 110, 97, 116, 101, 80, 114, 101, 115, 101, 110, 116, 97, 116, 105, 111, 110, 115], class: AlternatePresentations }, # AlternatePresentations
]

test_facts : KernelMetadata.Facts
test_facts = {
	created: Omitted,
	language: "en-AU",
	modified: Omitted,
	title: "Archive",
	title_escapes: { amps: 0, gts: 0, lts: 0 },
}

test_plan : KernelXmp.Packet -> KernelStructure.Plan
test_plan = |packet| match KernelStructure.build_blank_with_facts(
	1,
	A4,
	{
		condition_identifier: KernelMetadata.srgb_condition_identifier,
		language: "en-AU",
		profile_bytes: KernelSrgbProfile.bytes,
		profile_components: 3,
		registry_name: KernelMetadata.icc_registry_name,
		xmp: KernelXmp.Packet.bytes(packet),
	},
) {
	Ok(plan) => plan
	Err(_) => {
		crash "blank archive test plan failed"
	}
}

test_packet : KernelXmp.Identification -> KernelXmp.Packet
test_packet = |identification| match KernelXmp.Packet.build_identified(test_facts, identification, 4096) {
	Ok(packet) => packet
	Err(_) => {
		crash "archive test packet failed"
	}
}

test_input : KernelStructure.Plan, KernelXmp.Packet -> KernelPdfA4.LoweredInput
test_input = |plan, packet| { packet, root: KernelStructure.Plan.root(plan), sealed: KernelStructure.Plan.sealed(plan) }

## Reseal a white-box store mutation so the validator sees a structurally
## sealed store that differs from a valid plan in exactly one fact.
resealed : KernelStructure.Plan, (KernelObject.Store -> KernelObject.Store) -> KernelSeal.Plan
resealed = |plan, mutate| {
	store = mutate(KernelSeal.Plan.store(KernelStructure.Plan.sealed(plan)))
	builder = KernelObject.init({
		max_array_items: 1000000,
		max_byte_string_bytes: 1000000,
		max_byte_strings: 1000000,
		max_dictionary_entries: 1000000,
		max_direct_depth: 64,
		max_name_bytes: 1000000,
		max_names: 1000000,
		max_objects: 1000000,
		max_payload_bytes: 100000000,
		max_payloads: 1000000,
		max_streams: 1000000,
		max_text_string_bytes: 1000000,
		max_text_strings: 1000000,
		max_values: 1000000,
	})
	match KernelSeal.seal({ ..builder, store }) {
		Ok(sealed) => sealed
		Err(_) => {
			crash "white-box archive mutation broke the sealed store shape"
		}
	}
}

## Replace the first name spelled `from` with `to`; every use of that name
## then carries the substituted spelling.
rename : KernelObject.Store, Str, Str -> KernelObject.Store
rename = |store, from, to| {
	var $names = store.names
	var $index = 0
	var $done = False
	while !$done and $index < $names.len() {
		if KernelLex.Name.bytes(list_at($names, $index)) == Str.to_utf8(from) {
			replacement = lex_name(Str.to_utf8(to))
			$names = match $names.set($index, replacement) {
				Ok(updated) => updated
				Err(_) => $names
			}
			$done = True
		}
		$index = $index + 1
	}
	{ ..store, names: $names }
}

lex_name : List(U8) -> KernelLex.Name
lex_name = |bytes| match KernelLex.Name.from_bytes(bytes) {
	Ok(name) => name
	Err(_) => {
		crash "white-box test name was rejected lexically"
	}
}

violation : Try(KernelPdfA4.LoweredWork, KernelPdfA4.Violation) -> [Accepted, Rejected(KernelPdfA4.Requirement)]
violation = |result| match result {
	Ok(_) => Accepted
	Err(found) => Rejected(found.requirement)
}

## A claimed blank plan carrying the identified canonical packet is eligible,
## and the pass compares the complete packet exactly once.
expect {
	packet = test_packet(PdfA4Identification)
	plan = test_plan(packet)
	match KernelPdfA4.validate_lowered(StaticPdfA4Claim, test_input(plan, packet)) {
		Ok(work) => work.packet_bytes_compared == KernelXmp.Packet.bytes(packet).len() and work.names_classified > 0 and work.streams_checked == 3
		Err(_) => False
	}
}

## An unclaimed plan performs only the identification agreement check.
expect {
	packet = test_packet(NoIdentification)
	plan = test_plan(packet)
	KernelPdfA4.validate_lowered(NoArchiveClaim, test_input(plan, packet)) == Ok({ entries_checked: 0, names_classified: 0, packet_bytes_compared: 0, streams_checked: 0, values_checked: 0 })
}

## Declaring PDF/A identification without the claim is a false declaration.
expect {
	packet = test_packet(PdfA4Identification)
	plan = test_plan(packet)
	violation(KernelPdfA4.validate_lowered(NoArchiveClaim, test_input(plan, packet))) == Rejected(Identification)
}

## A claim without the identification schema is rejected before the scan.
expect {
	packet = test_packet(NoIdentification)
	plan = test_plan(packet)
	violation(KernelPdfA4.validate_lowered(StaticPdfA4Claim, test_input(plan, packet))) == Rejected(Identification)
}

## The metadata stream must be exactly the claim's canonical packet.
expect {
	identified = test_packet(PdfA4Identification)
	plan = test_plan(test_packet(NoIdentification))
	violation(KernelPdfA4.validate_lowered(StaticPdfA4Claim, test_input(plan, identified))) == Rejected(Identification)
}

## A compressed metadata stream is rejected.
expect {
	packet = test_packet(PdfA4Identification)
	plan = test_plan(packet)
	sealed = resealed(plan, |store| { ..store, streams: store.streams.map(|stream| if stream.filter == Unfiltered and stream.dictionary.length == 2 { ..stream, filter: Deflate } else stream) })
	violation(KernelPdfA4.validate_lowered(StaticPdfA4Claim, { packet, root: KernelStructure.Plan.root(plan), sealed })) == Rejected(MetadataStream)
}

## Each forbidden key spelled into an otherwise valid plan is rejected with
## its own requirement.
expect {
	packet = test_packet(PdfA4Identification)
	plan = test_plan(packet)
	check = |from, to| violation(KernelPdfA4.validate_lowered(StaticPdfA4Claim, { packet, root: KernelStructure.Plan.root(plan), sealed: resealed(plan, |store| rename(store, from, to)) }))
	check("Lang", "Encrypt") == Rejected(Encryption)
		and check("Lang", "OCProperties") == Rejected(OptionalContent)
			and check("Lang", "AcroForm") == Rejected(InteractiveForms)
				and check("Lang", "AA") == Rejected(AdditionalActions)
					and check("Lang", "OpenAction") == Accepted
						and check("Lang", "Requirements") == Rejected(RequirementsKey)
							and check("Lang", "Perms") == Rejected(Permissions)
								and check("Lang", "PieceInfo") == Rejected(DocumentInformation)
									and check("Lang", "EmbeddedFiles") == Rejected(EmbeddedFiles)
										and check("Lang", "Version") == Rejected(CatalogVersion)
}

## The output intent must be a single GTS_PDFA1 intent with an embedded
## monitor or output profile.
expect {
	packet = test_packet(PdfA4Identification)
	plan = test_plan(packet)
	check = |from, to| violation(KernelPdfA4.validate_lowered(StaticPdfA4Claim, { packet, root: KernelStructure.Plan.root(plan), sealed: resealed(plan, |store| rename(store, from, to)) }))
	check("GTS_PDFA1", "ISO_PDFA") == Rejected(OutputIntent)
		and check("DestOutputProfile", "DestOutputProfileRef") == Rejected(OutputIntent)
			and check("OutputIntents", "OutputIntentz") == Rejected(OutputIntent)
				and check("Metadata", "Metadatum") == Rejected(MetadataStream)
}

## A profile whose device class is neither `mntr` nor `prtr` cannot be the
## output intent.
expect {
	packet = test_packet(PdfA4Identification)
	plan = test_plan(packet)
	sealed = resealed(
		plan,
		|store| {
			payloads = store.payloads.map(|payload| if payload.bytes.len() == KernelSrgbProfile.bytes.len() { ..payload, bytes: payload.bytes.sublist({ start: 0, len: 12 }).concat([115, 99, 110, 114]).concat(payload.bytes.sublist({ start: 16, len: payload.bytes.len() - 16 })) } else payload)
			{ ..store, payloads }
		},
	)
	violation(KernelPdfA4.validate_lowered(StaticPdfA4Claim, { packet, root: KernelStructure.Plan.root(plan), sealed })) == Rejected(OutputIntent)
}

## A name that is not valid UTF-8 is rejected.
expect {
	packet = test_packet(PdfA4Identification)
	plan = test_plan(packet)
	sealed = resealed(
		plan,
		|store| {
			invalid = lex_name([76, 0xC3, 0x28])
			{ ..store, names: store.names.append(invalid) }
		},
	)
	violation(KernelPdfA4.validate_lowered(StaticPdfA4Claim, { packet, root: KernelStructure.Plan.root(plan), sealed })) == Rejected(NameEncoding)
}

## Strict UTF-8 acceptance.
expect valid_utf8(Str.to_utf8("Übersicht 概要 😀")) and !valid_utf8([0xC0, 0x80]) and !valid_utf8([0xED, 0xA0, 0x80]) and !valid_utf8([0xF4, 0x90, 0x80, 0x80]) and !valid_utf8([0xE2, 0x82])

## Text facts: forbidden ToUnicode values and private-use ActualText.
expect {
	clean = { actual_text: NoPrivateUse, mappings: [[{ cid: 1, scalars: [65, 66] }], [{ cid: 2, scalars: [0x1F600] }]] }
	bom = { actual_text: NoPrivateUse, mappings: [[{ cid: 1, scalars: [65, 0xFEFF] }]] }
	reversed = { actual_text: NoPrivateUse, mappings: [[{ cid: 1, scalars: [0xFFFE] }]] }
	private = { actual_text: PrivateUseInRun(3), mappings: [] }
	KernelPdfA4.validate_text(StaticPdfA4Claim, clean) == Ok({ mappings_checked: 2, scalars_checked: 3 })
		and KernelPdfA4.validate_text(StaticPdfA4Claim, bom) == Err({ position: 0, requirement: ToUnicodeValues })
			and KernelPdfA4.validate_text(StaticPdfA4Claim, reversed) == Err({ position: 0, requirement: ToUnicodeValues })
				and KernelPdfA4.validate_text(StaticPdfA4Claim, private) == Err({ position: 3, requirement: ActualTextPrivateUse })
					and KernelPdfA4.validate_text(NoArchiveClaim, bom) == Ok({ mappings_checked: 0, scalars_checked: 0 })
}
