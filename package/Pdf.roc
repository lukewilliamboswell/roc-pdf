import Conformance
import Document
import KernelLex
import KernelEmit
import KernelUnicode
import KernelObject
import KernelSeal
import KernelStructure
import Theme

Pdf :: [].{
	Profile := [AccessibleArchive, Archive, Standard]

	PageSize := [A4, Letter]
	ChunkRetention := [OwnChunks, ShareUnchangedResources]

	Feature := [AuthoringContent, Pdf20Generation, PdfA4Generation, PdfUa2Generation]
	Error := [
		CapabilityUnavailable(Feature),
		InternalGenerationFailure,
		InvalidDocument(List(Conformance.Diagnostic)),
		UnsupportedAuthoringContent({ blocks : U64 }),
	]

	Options :: {
		chunk_retention : ChunkRetention,
		page_size : PageSize,
		profile : Profile,
		theme : Theme,
	}.{
		default : Options
		default = Options.{
			chunk_retention: ShareUnchangedResources,
			page_size: A4,
			profile: Standard,
			theme: Theme.default,
		}

		with_profile : Options, Profile -> Options
		with_profile = |options, profile| { ..options, profile }

		with_page_size : Options, PageSize -> Options
		with_page_size = |options, page_size| { ..options, page_size }

		with_theme : Options, Theme -> Options
		with_theme = |options, theme| { ..options, theme }

		with_chunk_retention : Options, ChunkRetention -> Options
		with_chunk_retention = |options, chunk_retention| { ..options, chunk_retention }
	}

	Encode :: KernelEmit.Encoder.{}
	ChunkStep : [Done, Emit(List(U8), Encode)]

	claims_for_profile : Profile -> Conformance.ClaimSet
	claims_for_profile = |profile| match profile {
		Standard => Conformance.claims_for_profile(Standard)
		Archive => Conformance.claims_for_profile(Archive)
		AccessibleArchive => Conformance.claims_for_profile(AccessibleArchive)
	}

	document : { contents : List(Document.Block), language : Str, title : Str } -> Document
	document = |input| Document.from_blocks(input)

	title : Str -> Document.Block
	title = |text| Document.title(text)

	heading : U8, Str -> Document.Block
	heading = |level, text| Document.heading(level, text)

	paragraph : Str -> Document.Block
	paragraph = |text| Document.paragraph(text)

	bullets : List(Str) -> Document.Block
	bullets = |items| Document.bullets(items)

	page_header : Str -> Document.Block
	page_header = |text| Document.page_header(text)

	page_footer : Str -> Document.Block
	page_footer = |text| Document.page_footer(text)

	## Gate 1 emits a structural blank document only. Meaningful authoring
	## content and stricter profiles remain explicit unavailable capabilities.
	to_bytes : Document -> Try(List(U8), Error)
	to_bytes = |doc| to_bytes_with(doc, Options.default)

	to_bytes_with : Document, Options -> Try(List(U8), Error)
	to_bytes_with = |doc, options| {
		validate_gate_1_request(doc, options)?
		plan = KernelStructure.build_blank(1, structure_page_size(options.page_size)) ? |_| InternalGenerationFailure
		bytes = KernelEmit.to_bytes(plan) ? |_| InternalGenerationFailure
		Ok(bytes)
	}

	to_chunks : Document -> Try(Encode, Error)
	to_chunks = |doc| to_chunks_with(doc, Options.default)

	to_chunks_with : Document, Options -> Try(Encode, Error)
	to_chunks_with = |doc, options| {
		validate_gate_1_request(doc, options)?
		plan = KernelStructure.build_blank(1, structure_page_size(options.page_size)) ? |_| InternalGenerationFailure
		retention = match options.chunk_retention {
			OwnChunks => OwnResourceChunks
			ShareUnchangedResources => ShareResourceChunks
		}
		encoder = KernelEmit.start(plan, retention) ? |_| InternalGenerationFailure
		Ok(Encode.(encoder))
	}

	next_chunk : Encode -> ChunkStep
	next_chunk = |Encode.(encoder)| match KernelEmit.Encoder.next_infallible(encoder) {
		Done => Done
		Emit(segment, next) => Emit(segment.bytes, Encode.(next))
	}
}

validate_gate_1_request : Document, Pdf.Options -> Try({}, Pdf.Error)
validate_gate_1_request = |doc, options| {
	match options.profile {
		Archive => Err(Pdf.Error.CapabilityUnavailable(Pdf.Feature.PdfA4Generation))
		AccessibleArchive => Err(Pdf.Error.CapabilityUnavailable(Pdf.Feature.PdfUa2Generation))
		Standard => {
			blocks = Document.block_count(doc)
			if blocks == 0 {
				Ok({})
			} else {
				Err(Pdf.Error.UnsupportedAuthoringContent({ blocks: blocks }))
			}
		}
	}
}

structure_page_size : Pdf.PageSize -> KernelStructure.PageSize
structure_page_size = |page_size| match page_size {
	A4 => KernelStructure.PageSize.A4
	Letter => KernelStructure.PageSize.Letter
}

## Public profiles map to exact claim sets without enabling orthogonal WTPDF claims.
expect {
	claims = Pdf.claims_for_profile(Pdf.Profile.AccessibleArchive)

	claims.pdf20 and claims.static_pdf_a4 and claims.pdf_ua2 and !claims.wtpdf_accessibility
}

## The lexical implementation remains a private package module.
expect KernelLex.boolean(True) == Str.to_utf8("true")

## Gate 3 Unicode analysis is pinned to the local Unicode 17 package until a
## reviewed package release can replace this source dependency.
expect KernelUnicode.version == "17.0.0"

## Object/value/edge storage is likewise package-private.
expect KernelObject.counts(
	KernelObject.init({
		max_array_items: 0,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 0,
		max_direct_depth: 0,
		max_name_bytes: 0,
		max_names: 0,
		max_objects: 0,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: 0,
	}),
).objects == 0

## Sealing remains private and accepts the empty construction store.
expect match KernelSeal.seal(
	KernelObject.init({
		max_array_items: 0,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 0,
		max_direct_depth: 0,
		max_name_bytes: 0,
		max_names: 0,
		max_objects: 0,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: 0,
	}),
) {
	Ok(_) => True
	Err(_) => False
}

## The blank-page structural lowerer is private to the package.
expect match KernelStructure.build_blank(1, KernelStructure.PageSize.A4) {
	Ok(plan) => KernelStructure.Plan.object_count(plan) == 5
	Err(_) => False
}

## The private buffered and chunk transitions share one emitter.
expect {
	plan = KernelStructure.build_blank(1, KernelStructure.PageSize.A4)?
	bytes = KernelEmit.to_bytes(plan)?

	bytes.len() > 0
}

## Unsupported authoring content fails transactionally instead of emitting a blank fallback.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})

	match Pdf.to_bytes(document) {
		Err(UnsupportedAuthoringContent({ blocks })) => blocks == 2
		_ => False
	}
}

## Empty Standard documents emit one structural PDF 2.0 page.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(document)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n")
}

## Archive remains unavailable rather than silently emitting Standard output.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Archive" })
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)

	match Pdf.to_bytes_with(document, options) {
		Err(CapabilityUnavailable(PdfA4Generation)) => True
		_ => False
	}
}

## AccessibleArchive remains unavailable rather than dropping its UA claim.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Accessible" })
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.AccessibleArchive)

	match Pdf.to_bytes_with(document, options) {
		Err(CapabilityUnavailable(PdfUa2Generation)) => True
		_ => False
	}
}

## Chunked facade output is byte-identical with buffered output.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	expected = Pdf.to_bytes(document)?
	var $encoder = Pdf.to_chunks(document)?
	var $actual = []
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(bytes, next) => {
				$actual = append_pdf_bytes($actual, bytes)
				$encoder = next
			}
		}
	}

	$actual == expected
}

append_pdf_bytes : List(U8), List(U8) -> List(U8)
append_pdf_bytes = |target, source| {
	length = source.len()
	var $out = List.reserve(target, length)
	var $index = 0
	while $index < length {
		match source.get($index) {
			Ok(byte) => {
				$out = $out.append(byte)
			}
			Err(OutOfBounds) => {
				crash "PDF chunk test index invariant failed"
			}
		}
		$index = $index + 1
	}
	$out
}
