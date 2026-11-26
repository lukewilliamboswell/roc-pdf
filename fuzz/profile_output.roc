app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/main.roc",
}

import fuzz.Fuzz
import pdf.Document
import pdf.Pdf

Input := {
	request : U8,
	authoring : U8,
	compression : U8,
	copies : U8,
}.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { request: Fuzz.u8, authoring: Fuzz.u8, compression: Fuzz.u8, copies: Fuzz.u8 }.Fuzz
}

target = Fuzz.suite([
	Fuzz.target({
		name: "roc-pdf-profile-output",
		examples: [
			Fuzz.example({ name: "standard-tagged", revision: "1", make: || Input.{ request: 0, authoring: 0, compression: 0, copies: 0 } }),
			Fuzz.example({ name: "archive-blank", revision: "1", make: || Input.{ request: 1, authoring: 1, compression: 1, copies: 0 } }),
			Fuzz.example({ name: "accessible-archive", revision: "1", make: || Input.{ request: 2, authoring: 0, compression: 2, copies: 1 } }),
			Fuzz.example({ name: "wtpdf-accessibility", revision: "1", make: || Input.{ request: 5, authoring: 0, compression: 0, copies: 2 } }),
			Fuzz.example({ name: "blank-structure-rejection", revision: "1", make: || Input.{ request: 2, authoring: 1, compression: 0, copies: 0 } }),
			Fuzz.example({ name: "language-placeholder-rejection", revision: "1", make: || Input.{ request: 2, authoring: 2, compression: 0, copies: 0 } }),
			Fuzz.example({ name: "incompatible-wtpdf-rejection", revision: "1", make: || Input.{ request: 4, authoring: 0, compression: 0, copies: 0 } }),
		],
		test,
		show: |input| Str.inspect(input),
	}),
])

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	profile = match input.request % 3 {
		0 => Pdf.Profile.Standard
		1 => Pdf.Profile.Archive
		_ => Pdf.Profile.AccessibleArchive
	}
	declare = input.request % 6 >= 3
	authoring = input.authoring % 3
	compression = match input.compression % 3 {
		0 => Pdf.Compression.Balanced
		1 => Pdf.Compression.Fastest
		_ => Pdf.Compression.Smallest
	}
	document = make_document(authoring, 1 + (input.copies % 3).to_u64())
	options = Pdf.Options.{ profile, wtpdf: if (declare) DeclareAccessibility else NoWtpdfDeclaration, compression }
	expected = if declare and profile != AccessibleArchive {
		Reject({ feature: "profile.wtpdf_accessibility", path: "options.wtpdf" })
	} else if profile == AccessibleArchive and authoring == 1 {
		Reject({ feature: "profile.accessible_archive.empty_structure", path: "contents" })
	} else if profile == AccessibleArchive and authoring == 2 {
		Reject({ feature: "profile.accessible_archive.language", path: "language" })
	} else {
		Output
	}
	held = match expected {
		Reject({ feature, path }) => {
			rejected(Pdf.prepare(document, options), feature, path)
				and rejected(Pdf.to_bytes_with(document, options), feature, path)
				and rejected(Pdf.to_chunks_with(document, options), feature, path)
		}
		Output => match (Pdf.to_bytes_with(document, options), Pdf.to_chunks_with(document, options)) {
			(Ok(bytes), Ok(encoder)) => identified(bytes, profile, declare) and same_bytes(bytes, encoder)
			_ => False
		}
	}
	if held {
		Fuzz.keep
	} else {
		crash "profile identification or atomic rejection differed from the authored request"
	}
}

make_document : U8, U64 -> Document
make_document = |authoring, copies| {
	body = Pdf.paragraph("The report records a checked delivery.")
	contents = if (authoring == 1) [] else List.repeat(body, copies)
	Pdf.document({ contents, language: if (authoring == 2) "und" else "en-AU", title: "Delivery report" })
}

rejected : Try(a, Pdf.Error), Str, Str -> Bool
rejected = |outcome, feature, path| match outcome {
	Err(InvalidDocument({ diagnostics: [{ code: ProfileRequirementViolated, feature: Feature(actual), details: [location], .. }], truncation: Complete, .. })) => actual == feature and location == path
	_ => False
}

identified : List(U8), Pdf.Profile, Bool -> Bool
identified = |bytes, profile, declare| {
	archive = profile != Standard
	accessible = profile == AccessibleArchive
	bytes.sublist({ start: 0, len: 9 }) == "%PDF-2.0\n".to_utf8()
		and archive == contains(bytes, "xmlns:pdfaid=")
		and archive == contains(bytes, "<pdfaid:part>4</pdfaid:part>")
		and archive == contains(bytes, "<pdfaid:rev>2020</pdfaid:rev>")
		and !contains(bytes, "pdfaid:conformance")
		and accessible == contains(bytes, "xmlns:pdfuaid=")
		and accessible == contains(bytes, "<pdfuaid:part>2</pdfuaid:part>")
		and accessible == contains(bytes, "<pdfuaid:rev>2024</pdfuaid:rev>")
		and declare == contains(bytes, "<pdfd:declarations>")
		and declare == contains(bytes, "<pdfd:conformsTo>http://pdfa.org/declarations/wtpdf#accessibility1.0</pdfd:conformsTo>")
}

## The fixed ASCII metadata and text do not carry these markers. XMP is
## written uncompressed, regardless of the selected content compression.
contains : List(U8), Str -> Bool
contains = |bytes, marker| {
	pattern = marker.to_utf8()
	first = pattern.get(0)
	var $offset = 0
	while $offset + pattern.len() <= bytes.len() {
		if bytes.get($offset) == first and bytes.sublist({ start: $offset, len: pattern.len() }) == pattern {
			return True
		}
		$offset = $offset + 1
	}
	False
}

## Consume the chunk stream in order without allocating a second PDF buffer.
same_bytes : List(U8), Pdf.Encode -> Bool
same_bytes = |expected, encoder| {
	var $encoder = encoder
	var $offset = 0
	while $offset <= expected.len() {
		match Pdf.next_chunk($encoder) {
			Done => return $offset == expected.len()
			Emit(chunk, next) => {
				if chunk.is_empty() or chunk.len() > expected.len() - $offset or expected.sublist({ start: $offset, len: chunk.len() }) != chunk {
					return False
				}
				$offset = $offset + chunk.len()
				$encoder = next
			}
		}
	}
	False
}
