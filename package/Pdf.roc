import Conformance
import Document
import KernelLex
import Theme

Pdf :: [].{
	Profile := [AccessibleArchive, Archive, Standard]

	PageSize := [A4, Letter]
	ChunkRetention := [OwnChunks, ShareUnchangedResources]

	Feature := [Pdf20Generation]
	Error := [
		CapabilityUnavailable(Feature),
		InvalidDocument(List(Conformance.Diagnostic)),
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

	Encode :: U64.{}
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

	## Gate 0 defines the facade contract without claiming Gate 1 emission.
	## These entrypoints fail transactionally and return no bytes until the
	## structural kernel is implemented and evidenced.
	to_bytes : Document -> Try(List(U8), Error)
	to_bytes = |_document| Err(CapabilityUnavailable(Pdf20Generation))

	to_bytes_with : Document, Options -> Try(List(U8), Error)
	to_bytes_with = |_document, _options| Err(CapabilityUnavailable(Pdf20Generation))

	to_chunks : Document -> Try(Encode, Error)
	to_chunks = |_document| Err(CapabilityUnavailable(Pdf20Generation))

	to_chunks_with : Document, Options -> Try(Encode, Error)
	to_chunks_with = |_document, _options| Err(CapabilityUnavailable(Pdf20Generation))

	next_chunk : Encode -> ChunkStep
	next_chunk = |_encode| Done
}

## Public profiles map to exact claim sets without enabling orthogonal WTPDF claims.
expect {
	claims = Pdf.claims_for_profile(Pdf.Profile.AccessibleArchive)

	claims.pdf20 and claims.static_pdf_a4 and claims.pdf_ua2 and !claims.wtpdf_accessibility
}

## The lexical implementation remains a private package module.
expect KernelLex.boolean(True) == Str.to_utf8("true")

## Gate 0 facade calls fail transactionally instead of emitting placeholder bytes.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})

	match Pdf.to_bytes(document) {
		Err(CapabilityUnavailable(Pdf20Generation)) => True
		_ => False
	}
}
