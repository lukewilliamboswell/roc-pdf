app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Pdf

collect = |encoder, bytes| match Pdf.next_chunk(encoder) {
	Done => bytes
	Emit(chunk, next) => collect(next, bytes.concat(chunk))
}

main! = |_args| {
	document = Pdf.document({
		title: "Data export",
		language: "en",
		contents: [
			Pdf.title("Data export"),
			Pdf.paragraph("Chunked delivery uses the same sealed plan and produces byte-identical output."),
			Pdf.bullets(["No partial document on validation failure", "Explicit chunk-retention policy", "Deterministic ordering"]),
		],
	})
	prepared = Pdf.prepare(document, Pdf.Options.default).map_err(|err| PdfFailed(err))?
	encoder = Pdf.to_chunks_prepared(prepared, ShareUnchangedResources).map_err(|err| EmitFailed(err))?
	output : Path
	output = "chunked-export.pdf"
	output.write_bytes!(collect(encoder, [])).map_err(|err| WriteFailed(err))?
	Ok({})
}
