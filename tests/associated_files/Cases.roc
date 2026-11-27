import invoice.Invoice
import pdf.Document
import pdf.Pdf

Cases :: [].{
	Case : [
		Invoice,
		Permutation,
		ArchiveInvoice,
		Files({ count : U64, volume : U64 }),
		Wtpdf,
		Blank,
		AtomicNegatives,
	]
	Stats : { bytes : List(U8), work : List(U64) }

	run : Case -> Stats
	run = |case| {
		result = match case {
			Invoice => evidence(Invoice.document, { profile: AccessibleArchiveWithFiles }, 1, 0)
			ArchiveInvoice => evidence(Invoice.document, { profile: ArchiveWithFiles }, 0, 0)
			Files({ count, volume }) => evidence(flow_document(files(count, volume)), { profile: AccessibleArchiveWithFiles }, 1, 0)
			Permutation => check_permutation({})
			Wtpdf => evidence(flow_document(files(4, 16)), { profile: AccessibleArchiveWithFiles, wtpdf: DeclareAccessibility }, 1, 0)
			Blank => evidence(Pdf.document({ contents: [], language: "en", title: "Empty archive" }).with_associated_files(files(4, 16)), { profile: ArchiveWithFiles }, 0, 0)
			AtomicNegatives => atomic_negatives({})
		}
		result ?? crash "associated-file public fixture failed"
	}
}

files : U64, U64 -> List(Pdf.AssociatedFile)
files = |count, volume| {
	var $out = List.with_capacity(count)
	var $index = 0
	while $index < count {
		index = $index
		filename = match $index {
			0 => "statement"
			1 => "statement.xml"
			2 => "résumé.csv"
			3 => "rate%book.csv"
			_ => "part-${index.to_str()}.csv"
		}
		# Two distinct filenames carry equal caller data without merging
		# their stream identities. Remaining payloads differ by authored index.
		seed = if ($index < 2) 32 else 32 + $index.to_u8_wrap()
		relationship = match $index % 4 {
			0 => Data
			1 => Supplement
			2 => Source
			_ => Alternative
		}
		file_bytes = List.repeat(seed, volume)
		$out = $out.append(
			Pdf.AssociatedFile.{
				bytes: file_bytes,
				description: "Purpose of ${filename}",
				filename,
				media_type: if ($index == 1) "application/xml" else "text/csv",
				modified: "2024-02-29T12:34:56Z",
				necessity: Supplemental,
				relationship,
			},
		)
		$index = $index + 1
	}
	$out
}

flow_document : List(Pdf.AssociatedFile) -> Document
flow_document = |attachments| Pdf.document({
	contents: [
		Pdf.destination_heading({ name: "start", level: 1, text: "Complete statement" }),
		Pdf.rich_paragraph([Pdf.inline_internal_link([Pdf.text("Return to the statement heading")], "start")]),
	],
	language: "en",
	title: "Associated statement data",
}).with_associated_files(attachments)

evidence : Document, Pdf.Options, U64, U64 -> Try(Cases.Stats, Pdf.Error)
evidence = |document, options, accessible, rejections| {
	{ prepared, report } = Pdf.prepare_with_report(document, { options: options })?
	files_count = Document.associated_files(document).len()
	descriptions = report.obligations.count_if(
		|entry| match entry.obligation {
			AttachmentPurposeMeaningful => True
			_ => False
		},
	)
	supplemental = report.obligations.count_if(
		|entry| match entry.obligation {
			AttachmentSupplemental => True
			_ => False
		},
	)
	if descriptions != files_count or supplemental != files_count * accessible {
		crash "attachment report lost author obligations"
	}
	bytes = Pdf.to_bytes_prepared(prepared)?
	share_chunks = check_chunks(bytes, Pdf.to_chunks_prepared(prepared, ShareUnchangedResources)?)
	owned_chunks = check_chunks(bytes, Pdf.to_chunks_prepared(prepared, OwnChunks)?)
	if share_chunks != owned_chunks {
		crash "attachment chunk streams differed"
	}
	source_bytes = Document.associated_files(document).map(|file| file.bytes.len()).sum()
	Ok({ bytes, work: [files_count, source_bytes, share_chunks, descriptions, supplemental, rejections, bytes.len()] })
}

check_chunks : List(U8), Pdf.Encode -> U64
check_chunks = |expected, encoder| {
	var $encoder = encoder
	var $chunks = 0
	var $offset = 0
	while $offset <= expected.len() {
		match Pdf.next_chunk($encoder) {
			Done => {
				if $offset != expected.len() {
					crash "attachment chunk stream ended early"
				}
				return $chunks
			}
			Emit(chunk, next) => {
				if chunk.is_empty() or chunk.len() > expected.len() - $offset or expected.sublist({ start: $offset, len: chunk.len() }) != chunk {
					crash "attachment chunk stream differs from buffered output"
				}
				$offset = $offset + chunk.len()
				$chunks = $chunks + 1
				$encoder = next
			}
		}
	}
	crash "attachment chunk byte accounting"
}

check_permutation : {} -> Try(Cases.Stats, Pdf.Error)
check_permutation = |_| {
	input = files(4, 16)
	result = evidence(flow_document(input), { profile: AccessibleArchiveWithFiles }, 1, 0)?
	reversed = input.rev()
	permuted = Pdf.to_bytes_with(flow_document(reversed), { profile: AccessibleArchiveWithFiles })?
	if result.bytes != permuted {
		crash "file registry must be independent of insertion order"
	}
	Ok(result)
}

atomic_negatives : {} -> Try(Cases.Stats, Pdf.Error)
atomic_negatives = |_| {
	file = files(1, 1).get(0) ?? crash "missing file seed"
	Pdf.AssociatedFile.(record) = file
	files_profile = Pdf.Options.{ profile: AccessibleArchiveWithFiles }
	large = List.repeat(1, 4194304)
	per_file = large.append(1)
	samples = [
		([file], Pdf.Options.{}, "attachment.profile", "options.profile"),
		([file], Pdf.Options.{ profile: Archive }, "attachment.profile", "options.profile"),
		([file], Pdf.Options.{ profile: Standard }, "attachment.profile", "options.profile"),
		([], files_profile, "attachment.missing", "associated_files"),
		([file, file], files_profile, "attachment.duplicate", "associated_files[1].filename"),
		([Pdf.AssociatedFile.{ ..record, filename: "../part.xml" }], files_profile, "attachment.filename", "associated_files[0].filename"),
		([Pdf.AssociatedFile.{ ..record, description: " " }], files_profile, "attachment.description", "associated_files[0].description"),
		([Pdf.AssociatedFile.{ ..record, media_type: "text/csv; charset=utf-8" }], files_profile, "attachment.media_type", "associated_files[0].media_type"),
		([Pdf.AssociatedFile.{ ..record, modified: "2025-02-29T00:00:00Z" }], files_profile, "attachment.modified", "associated_files[0].modified"),
		([Pdf.AssociatedFile.{ ..record, necessity: RequiredToUnderstand }], files_profile, "attachment.required", "associated_files[0].necessity"),
		([Pdf.AssociatedFile.{ ..record, description: "Private-use \u(E000)" }], files_profile, "profile.accessible_archive.private_use_text", "associated_files[0].description"),
		(List.repeat(file, 129), files_profile, "attachment.count_limit", "associated_files"),
		([Pdf.AssociatedFile.{ ..record, bytes: per_file }], files_profile, "attachment.file_limit", "associated_files[0].bytes"),
		([Pdf.AssociatedFile.{ ..record, bytes: large }, Pdf.AssociatedFile.{ ..record, bytes: large }, file], files_profile, "attachment.total_limit", "associated_files[2].bytes"),
	]
	for (attachment_list, options, feature, path) in samples {
		doc = flow_document(attachment_list)
		if !rejects(Pdf.prepare(doc, options), feature, path)
			or !rejects(Pdf.to_bytes_with(doc, options), feature, path)
			or !rejects(Pdf.to_chunks_with(doc, options), feature, path)
			or !rejects(Pdf.prepare_with_report(doc, { options: options }), feature, path) {
			crash "expected atomic attachment rejection: ${feature} at ${path}"
		}
	}
	# Exact public limits are accepted. The snapshots below stay small: this
	# witness only prepares the document and checks that the plan survived.
	exact_volume = [
		Pdf.AssociatedFile.{ ..record, bytes: large, filename: "limit-a.bin" },
		Pdf.AssociatedFile.{ ..record, bytes: large, filename: "limit-b.bin" },
	]
	_ = Pdf.prepare(flow_document(exact_volume), files_profile)?
	_ = Pdf.prepare(flow_document(files(128, 0)), files_profile)?
	evidence(flow_document(files(4, 16)), files_profile, 1, samples.len() * 4)
}

rejects : Try(a, Pdf.Error), Str, Str -> Bool
rejects = |result, feature, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), details: [location], .. }], truncation: Complete, .. })) => actual == feature and location == path
	_ => False
}
