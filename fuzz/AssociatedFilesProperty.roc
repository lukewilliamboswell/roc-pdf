import fuzz.Fuzz
import pdf.Pdf

AssociatedFilesProperty :: [].{
	target = Fuzz.target({
		name: "roc-pdf-associated-files",
		examples: [
			Fuzz.example({ name: "different-opaque-payloads", revision: "1", make: || Input.{ variant: 0, payload: [0, 255, 17, 81], reverse: 0 } }),
			Fuzz.example({ name: "duplicate-filename", revision: "1", make: || Input.{ variant: 1, payload: [], reverse: 1 } }),
			Fuzz.example({ name: "invalid-mime", revision: "1", make: || Input.{ variant: 2, payload: [47], reverse: 0 } }),
			Fuzz.example({ name: "count-budget", revision: "1", make: || Input.{ variant: 3, payload: [4, 8, 16], reverse: 0 } }),
			Fuzz.example({ name: "invalid-filename", revision: "1", make: || Input.{ variant: 4, payload: [92], reverse: 1 } }),
			Fuzz.example({ name: "missing-purpose", revision: "1", make: || Input.{ variant: 5, payload: [1], reverse: 0 } }),
			Fuzz.example({ name: "necessary-payload", revision: "1", make: || Input.{ variant: 6, payload: [33], reverse: 1 } }),
		],
		test,
		show: |input| Str.inspect(input),
	})
}

Input := { variant : U8, payload : List(U8), reverse : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { variant: Fuzz.u8, payload: Fuzz.list(Fuzz.u8, 64), reverse: Fuzz.u8 }.Fuzz
}

test : Input -> Fuzz.Outcome
test = |input| {
	variant = input.variant % 7
	data : Pdf.AssociatedFile
	data = {
		bytes: input.payload,
		description: "Raw data attached to the full report",
		filename: "samples.raw",
		media_type: "application/octet-stream",
		modified: "2024-02-29T00:00:00Z",
		relationship: Data,
		necessity: Supplemental,
	}
	other : Pdf.AssociatedFile
	other = {
		bytes: Str.to_utf8("opaque attachment bytes"),
		description: if (variant == 5) "" else "Table of display categories",
		filename: match variant {
			1 => "samples.raw"
			4 => "../invalid.csv"
			_ => "catégories.csv"
		},
		media_type: if (variant == 2) "text/csv;charset=ascii" else "text/csv",
		modified: "2024-02-20T00:00:00Z",
		relationship: Supplement,
		necessity: if (variant == 6) RequiredToUnderstand else Supplemental,
	}
	attachments = if variant == 3 {
		List.repeat(data, 129)
	} else if input.reverse % 2 == 1 {
		[other, data]
	} else {
		[data, other]
	}
	root = Pdf.document({ contents: [Pdf.paragraph("The complete report stands on its own.")], language: "en", title: "Attachment fuzz property" })
	document = root.with_associated_files(attachments)
	options = Pdf.Options.{ profile: AccessibleArchiveWithFiles }
	if variant == 0 {
		reversed = if (input.reverse % 2 == 1) [data, other] else [other, data]
		match (Pdf.to_bytes_with(document, options), Pdf.to_bytes_with(root.with_associated_files(reversed), options)) {
			(Ok(first), Ok(second)) => if first == second and embeds(first, data.bytes) and embeds(first, other.bytes) {
				return Fuzz.keep
			}
			_ => {}
		}
		crash "opaque associated payloads or canonical insertion order were lost"
	}
	feature = match variant {
		1 => "attachment.duplicate"
		2 => "attachment.media_type"
		3 => "attachment.count_limit"
		4 => "attachment.filename"
		5 => "attachment.description"
		_ => "attachment.required"
	}
	if rejected(Pdf.to_bytes_with(document, options), feature) and rejected(Pdf.to_chunks_with(document, options), feature) {
		Fuzz.keep
	} else {
		crash "malformed associated file did not reject atomically"
	}
}

rejected : Try(a, Pdf.Error), Str -> Bool
rejected = |result, feature| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), .. }], truncation: Complete, .. })) => feature == actual
	_ => False
}

## Associated-file stream content is opaque and unfiltered. Check whole
## stream payloads with their enclosing Type and stream/endstream markers.
embeds : List(U8), List(U8) -> Bool
embeds = |pdf, payload| {
	marker = Str.to_utf8("/Type /EmbeddedFile >>\nstream\n")
	tail = Str.to_utf8("\nendstream\n")
	remaining = marker.len() + payload.len() + tail.len()
	var $offset = 0
	while $offset + remaining <= pdf.len() {
		if pdf.get($offset) == Ok(47) and pdf.sublist({ start: $offset, len: marker.len() }) == marker {
			start = $offset + marker.len()
			if pdf.sublist({ start, len: payload.len() }) == payload and pdf.sublist({ start: start + payload.len(), len: tail.len() }) == tail {
				return True
			}
		}
		$offset = $offset + 1
	}
	False
}
