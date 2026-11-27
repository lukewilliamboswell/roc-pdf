import handbook.Footnotes
import pdf.Document
import pdf.Pdf

Cases :: [].{
	Case : [Handbook, HandbookWtpdf, Scale({ count : U64 }), Rejections]
	Stats : { bytes : List(U8), work : List(U64) }

	run : Case -> Stats
	run = |selected| {
		result = match selected {
			Handbook => evidence(Footnotes.document(False), Footnotes.options, 0)
			HandbookWtpdf => evidence(Footnotes.document(False), { ..Footnotes.options, wtpdf: DeclareAccessibility }, 0)
			Scale({ count }) => evidence(scale(count), Footnotes.options, 0)
			Rejections => rejections({})
		}
		match result {
			Ok(value) => value
			Err(error) => crash "footnote fixture failed: ${Str.inspect(error)}"
		}
	}
}

scale : U64 -> Document
scale = |count| {
	var $body = [Pdf.title("Response procedures")]
	var $index = 0
	while $index < count {
		number = $index.to_str()
		$body = $body.append(
			Pdf.rich_paragraph([
				Pdf.text("Control ${number} uses the procedure "),
				Pdf.footnote_marker({ id: "control-${number}", text: "[N${number}]" }),
				Pdf.text("."),
			]),
		)
		$index = $index + 1
	}
	$body = $body.append(Pdf.page_break).append(
		Pdf.rich_paragraph([
			Pdf.text("Check the first procedure again "),
			Pdf.footnote_marker({ id: "control-0", text: "[N0]" }),
			Pdf.text("."),
		]),
	)
	$index = count
	while $index > 0 {
		$index = $index - 1
		number = $index.to_str()
		$body = $body.append(Pdf.footnote_definition({ id: "control-${number}", label: "[N${number}]", body: "Information ${number} remains on its first citation page." }))
	}
	doc($body)
}

doc : List(Document.Block) -> Document
doc = |contents| Pdf.document({ contents, title: "Response procedures", language: "en-AU" })

evidence : Document, Pdf.Options, U64 -> Try(Cases.Stats, Pdf.Error)
evidence = |document, options, rejects| {
	{ prepared, report } = Pdf.prepare_with_report(document, { options: options })?
	bytes = Pdf.to_bytes_prepared(prepared)?
	chunks = verify_chunks(bytes, Pdf.to_chunks_prepared(prepared, ShareUnchangedResources)?)
	notes = report.facts.blocks.count_if(|block| block.role == "FENote" and block.first_page > 0 and block.first_page == block.last_page)
	Ok({ bytes, work: [report.facts.pages.len(), notes, chunks, bytes.len(), rejects] })
}

verify_chunks : List(U8), Pdf.Encode -> U64
verify_chunks = |bytes, encoder| {
	var $encoder = encoder
	var $offset = 0
	var $count = 0
	while True {
		match Pdf.next_chunk($encoder) {
			Done => {
				if $offset != bytes.len() {
					crash "footnote byte paths differ"
				}
				return $count
			}
			Emit(chunk, next) => {
				if chunk != bytes.sublist({ start: $offset, len: chunk.len() }) {
					crash "footnote byte paths differ"
				}
				$offset = $offset + chunk.len()
				$count = $count + 1
				$encoder = next
			}
		}
	}
}

rejections : {} -> Try(Cases.Stats, Pdf.Error)
rejections = |_| {
	marker = Pdf.rich_paragraph([Pdf.text("Clock "), Pdf.footnote_marker({ id: "clock", text: "[1]" })])
	note = Pdf.footnote_definition({ id: "clock", label: "[1]", body: "Response clock note." })
	samples = [
		(Footnotes.document(True), "document.footnote.fit", "contents[8]"),
		(doc([marker]), "document.footnote.missing", "contents[0].inlines[1]"),
		(doc([Pdf.paragraph("No reference"), note]), "document.footnote.uncited", "contents[1]"),
		(doc([marker, note, note]), "document.footnote.duplicate", "contents[2]"),
		(doc([note, marker]), "document.footnote.placement", "contents[0]"),
		(doc([Pdf.rich_paragraph([Pdf.footnote_marker({ id: "clock", text: "bad marker" })]), note]), "document.footnote.marker", "contents[0].inlines[0]"),
	]
	for (document, feature, path) in samples {
		if !rejects(Pdf.prepare(document, Footnotes.options), feature, path)
			or !rejects(Pdf.to_bytes_with(document, Footnotes.options), feature, path)
			or !rejects(Pdf.to_chunks_with(document, Footnotes.options), feature, path) {
			crash "expected atomic footnote rejection: ${feature} at ${path}"
		}
	}
	evidence(Footnotes.document(False), Footnotes.options, samples.len() * 3)
}

rejects : Try(a, Pdf.Error), Str, Str -> Bool
rejects = |result, expected, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), details: [location], .. }], .. })) => actual == expected and location == path
	_ => False
}
