app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Document
import pdf.Pdf

## Atomic public-path negatives for the static PDF/A-4 profile. Each rejection
## is transactional, keeps its authoring-stage cause (the profile never masks
## an earlier failure), and never falls back to Standard output. The facade
## cannot author a construct that only the Archive whitelist rejects: its
## text-support matrix rejects U+0000, U+FEFF, U+FFFE, and uncovered private-use
## scalars before profile validation, and it emits only printable links. Those
## profile rules are exercised by white-box twins in package/Pdf.roc and
## package/KernelPdfA4.roc.
archive : Pdf.Options
archive = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)

rejects_accessible_archive : Str -> Bool
rejects_accessible_archive = |title| {
	document = Pdf.document({ contents: [Pdf.paragraph("Body")], language: "en-AU", title })
	match Pdf.to_bytes_with(document, Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.AccessibleArchive)) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), stage: AuthoringValidation, .. }], .. })) => code == "profile.accessible_archive"
		_ => False
	}
}

keeps_metadata_cause : Str -> Bool
keeps_metadata_cause = |language| {
	document = Pdf.document({ contents: [Pdf.paragraph("Body")], language, title: "Archive" })
	match Pdf.to_bytes_with(document, archive) {
		Err(InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 }))) => True
		_ => False
	}
}

keeps_feature_cause : Str -> Bool
keeps_feature_cause = |summary| {
	document = Pdf.document({ contents: [Pdf.complex_table(summary)], language: "en-AU", title: "Archive" })
	match Pdf.to_bytes_with(document, archive) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), .. }], .. })) => code == "table.complex"
		_ => False
	}
}

keeps_content_cause : Str -> Bool
keeps_content_cause = |text| {
	document = Pdf.document({ contents: [Pdf.paragraph(text)], language: "en-AU", title: "Archive" })
	match Pdf.to_bytes_with(document, archive) {
		Err(UnsupportedAuthoringContent({ blocks: 1 })) => True
		_ => False
	}
}

accepted : Document -> List(U8)
accepted = |document| match Pdf.to_bytes_with(document, archive) {
	Ok(bytes) => bytes
	Err(_) => {
		crash "archive negative control document failed"
	}
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	title = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "archive negative evidence requires a title"
		}
	}
	checks = [
		rejects_accessible_archive(title),
		keeps_metadata_cause("en-au"),
		keeps_feature_cause(title),
		keeps_content_cause("Zero\u(FEFF)width"),
		keeps_content_cause("Private\u(E000)use"),
	]
	var $passed = 0
	var $index = 0
	while $index < checks.len() {
		match checks.get($index) {
			Ok(True) => {
				$passed = $passed + 1
			}
			_ => {}
		}
		$index = $index + 1
	}
	if $passed != checks.len() {
		crash "archive facade negative rejected the wrong way"
	}
	bytes = accepted(Pdf.document({ contents: [Pdf.paragraph(title)], language: "en-AU", title }))
	{ bytes, work: [$passed, bytes.len()] }
}
