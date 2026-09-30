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

	## `LibdeflateLevel(n)` is libdeflate's compression level `n`, through the
	## pinned pure-Roc `roc-deflate` port.
	DeflatePolicy : [LibdeflateLevel(U8)]

	## Every non-stream object is stored in FlateDecode object streams of at
	## most `max_objects` members, in plan order.
	ObjectStreamPolicy : { max_objects : U64 }

	## The cross-reference stream is FlateDecode with the PNG Up predictor.
	XrefCompression : [FlateUpPredictor]
	CompressionPolicy : {
		object_streams : ObjectStreamPolicy,
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
			object_streams: { max_objects: 400 },
			streams: LibdeflateLevel(10),
			xref: FlateUpPredictor,
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

# Canonical numbers normalize negative zero and never use host formatting.
expect Encode.canonical.numbers.negative_zero == NormalizeToZero

# Canonical streams use libdeflate level 10.
expect Encode.canonical.compression.streams == LibdeflateLevel(10)

# Non-stream objects go into object streams; the xref stream is compressed.
expect Encode.canonical.compression.object_streams.max_objects == 400 and Encode.canonical.compression.xref == FlateUpPredictor

# Document identifiers use a versioned domain-separated digest input.
expect Encode.canonical.identifiers.domain_separator == "roc-pdf:document-id:v1"
