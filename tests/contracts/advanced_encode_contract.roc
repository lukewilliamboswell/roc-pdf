app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Encode
import pdf.Metadata

## Authored metadata makes timestamps and identifier derivation explicit.
expect {
	metadata : Metadata.Logical
	metadata = {
		created: Omitted,
		identifier: Derived,
		language: "en-AU",
		modified: Omitted,
		title: "Quarterly report",
	}

	metadata.created == Omitted and metadata.identifier == Derived
}

## Canonical byte policy is fixed rather than supplied through Pdf.Options.
expect {
	policy : Encode.Policy
	policy = Encode.canonical

	policy.numbers.max_fractional_digits == 9
		and policy.ordering.dictionary_keys == UnsignedByteLexicographic
			and policy.compression.streams.window_bits == 15
				and policy.compression.xref == Uncompressed
					and Metadata.authoring.visible_title == RequiredForAccessibleArchive
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
