Encode :: [].{
	Rounding : [HalfEven]
	NegativeZero : [NormalizeToZero]
	NumberPolicy : {
		max_fractional_digits : U8,
		negative_zero : NegativeZero,
		rounding : Rounding,
	}

	DictionaryKeyOrder : [UnsignedByteLexicographic]
	ObjectOrder : [SealedPlanOrder]
	ResourceNameOrder : [ResourceKindThenDenseIdentity]
	TreePartition : [FixedFanoutLeftPacked]
	OrderingPolicy : {
		dictionary_keys : DictionaryKeyOrder,
		objects : ObjectOrder,
		resource_names : ResourceNameOrder,
		trees : TreePartition,
	}

	DigestAlgorithm : [Sha256]
	IdentifierInput : [NormalizedPlanFacts]
	IdentifierPolicy : {
		algorithm : DigestAlgorithm,
		domain_separator : Str,
		input : IdentifierInput,
		version : U16,
	}

	HuffmanPolicy : [Dynamic]
	XrefCompression : [Uncompressed]
	DeflatePolicy : {
		block_input_limit : U64,
		huffman : HuffmanPolicy,
		match_search_limit : U16,
		window_bits : U8,
	}
	CompressionPolicy : {
		streams : DeflatePolicy,
		xref : XrefCompression,
	}

	Newline : [LineFeed]
	Escaping : [CanonicalPdf20]
	Policy : {
		compression : CompressionPolicy,
		escaping : Escaping,
		identifiers : IdentifierPolicy,
		newline : Newline,
		numbers : NumberPolicy,
		ordering : OrderingPolicy,
	}

	## This policy is a package-versioned byte contract, not an author option.
	canonical : Policy
	canonical = {
		compression: {
			streams: {
				block_input_limit: 65535,
				huffman: Dynamic,
				match_search_limit: 128,
				window_bits: 15,
			},
			xref: Uncompressed,
		},
		escaping: CanonicalPdf20,
		identifiers: {
			algorithm: Sha256,
			domain_separator: "roc-pdf:document-id:v1",
			input: NormalizedPlanFacts,
			version: 1,
		},
		newline: LineFeed,
		numbers: {
			max_fractional_digits: 9,
			negative_zero: NormalizeToZero,
			rounding: HalfEven,
		},
		ordering: {
			dictionary_keys: UnsignedByteLexicographic,
			objects: SealedPlanOrder,
			resource_names: ResourceKindThenDenseIdentity,
			trees: FixedFanoutLeftPacked,
		},
	}
}

## Canonical numbers normalize negative zero and never use host formatting.
expect Encode.canonical.numbers.negative_zero == NormalizeToZero

## Canonical stream work has an exact bounded match search.
expect Encode.canonical.compression.streams.match_search_limit == 128

## The initial xref stream remains uncompressed.
expect Encode.canonical.compression.xref == Uncompressed

## Document identifiers use a versioned domain-separated digest input.
expect Encode.canonical.identifiers.domain_separator == "roc-pdf:document-id:v1"
