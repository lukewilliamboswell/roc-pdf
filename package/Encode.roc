import KernelDeflate

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

	## The level behind each `Pdf.Compression` choice. A document's
	## `Pdf.Options.compression` selects exactly one of them for every
	## FlateDecode stream, object stream, and the cross-reference stream.
	DeflatePresets : {
		balanced : DeflatePolicy,
		fastest : DeflatePolicy,
		smallest : DeflatePolicy,
	}

	## Every non-stream object is stored in FlateDecode object streams of at
	## most `max_objects` members, in plan order.
	ObjectStreamPolicy : { max_objects : U64 }

	## The cross-reference stream is FlateDecode with the PNG Up predictor.
	XrefCompression : [FlateUpPredictor]
	CompressionPolicy : {
		object_streams : ObjectStreamPolicy,
		streams : DeflatePresets,
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

	## This policy is a package-versioned byte contract. The only author
	## choice in it is which stream preset `Pdf.Options.compression` selects.
	canonical : Policy
	canonical = {
		compression: {
			object_streams: { max_objects: 400 },
			streams: {
				balanced: LibdeflateLevel(6),
				fastest: LibdeflateLevel(1),
				smallest: LibdeflateLevel(10),
			},
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

# The stream presets name the levels the compressor seam actually uses.
expect {
	presets = Encode.canonical.compression.streams
	presets.balanced == LibdeflateLevel(KernelDeflate.Level.libdeflate(KernelDeflate.Level.balanced).to_u8_wrap()) and
		presets.fastest == LibdeflateLevel(KernelDeflate.Level.libdeflate(KernelDeflate.Level.fastest).to_u8_wrap()) and
			presets.smallest == LibdeflateLevel(KernelDeflate.Level.libdeflate(KernelDeflate.Level.smallest).to_u8_wrap())
}

# Non-stream objects go into object streams; the xref stream is compressed.
expect Encode.canonical.compression.object_streams.max_objects == 400 and Encode.canonical.compression.xref == FlateUpPredictor

# Document identifiers use a versioned domain-separated digest input.
expect Encode.canonical.identifiers.domain_separator == "roc-pdf:document-id:v1"
