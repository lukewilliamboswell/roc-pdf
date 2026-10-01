import Semantics

Color :: [].{
	ProfileId :: U64.{
		is_eq : _
		to_hash : _

		from_index : U64 -> ProfileId
		from_index = |index| ProfileId.(index)

		index : ProfileId -> U64
		index = |ProfileId.(index)| index
	}

	SpaceId :: U64.{
		is_eq : _
		to_hash : _

		from_index : U64 -> SpaceId
		from_index = |index| SpaceId.(index)

		index : SpaceId -> U64
		index = |SpaceId.(index)| index
	}

	TagSignature :: U32.{
		is_eq : _
		to_hash : _

		from_raw : U32 -> TagSignature
		from_raw = |raw| TagSignature.(raw)

		raw : TagSignature -> U32
		raw = |TagSignature.(raw)| raw
	}

	ComponentCount : [One, Three]
	ProfileVersion : [IccV2, IccV4]

	IccTag : {
		bytes : Semantics.Range,
		signature : TagSignature,
	}

	## Profile bytes are retained once; tags are validated ranges into them.
	IccProfile : {
		bytes : List(U8),
		components : ComponentCount,
		id : ProfileId,
		tags : Semantics.Range,
		version : ProfileVersion,
	}

	## Tristimulus values use signed millionths and avoid floating-point syntax.
	Tristimulus : { x : I64, y : I64, z : I64 }
	Space : [
		CalibratedGray({ black_point : Tristimulus, white_point : Tristimulus }),
		IccBased({ components : ComponentCount, profile : ProfileId }),
		Srgb(ProfileId),
	]

	SpaceRecord : {
		id : SpaceId,
		space : Space,
	}

	Channels : [Gray(U16), Rgb({ blue : U16, green : U16, red : U16 })]

	## Authoring colors name their source space without inventing a resource ID.
	## Preparation resolves that space to an exact validated store entry.
	##
	## A string literal where a `SourceValue` is expected is an sRGB hex
	## color, `"#RRGGBB"` (upper- or lowercase digits), exactly as
	## `srgb8` with those channels: `navy : Color.SourceValue` then
	## `navy = "#183454"`. Any other spelling is a compile-time error at the
	## literal; the color's space is always sRGB, never guessed.
	SourceValue := [Srgb(Channels)].{
		is_eq : _

		from_quote : Str -> Try(SourceValue, [BadQuotedBytes(Str)])
		from_quote = |text| match text.to_utf8() {
			['#', r1, r0, g1, g0, b1, b0] => match (hex_pair(r1, r0), hex_pair(g1, g0), hex_pair(b1, b0)) {
				(Ok(red), Ok(green), Ok(blue)) => Ok(Color.srgb8({ blue, green, red }))
				_ => Err(BadQuotedBytes(hex_color_message))
			}
			_ => Err(BadQuotedBytes(hex_color_message))
		}
	}

	## Construct an sRGB authoring color from exact 16-bit channels.
	srgb16 : { blue : U16, green : U16, red : U16 } -> SourceValue
	srgb16 = |channels| Srgb(Rgb(channels))

	## Construct an sRGB authoring color from familiar 8-bit channels.
	srgb8 : { blue : U8, green : U8, red : U8 } -> SourceValue
	srgb8 = |channels| Srgb(Rgb({ blue: channels.blue.to_u16() * 257, green: channels.green.to_u16() * 257, red: channels.red.to_u16() * 257 }))

	## Construct a neutral sRGB gray from an exact 16-bit level.
	gray16 : U16 -> SourceValue
	gray16 = |level| Srgb(Gray(level))

	## Construct a neutral sRGB gray from an 8-bit level.
	gray8 : U8 -> SourceValue
	gray8 = |level| Srgb(Gray(level.to_u16() * 257))
	Value : { channels : Channels, space : SpaceId }
	BlendMode : [Normal]
	BlendSpace : { space : SpaceId }

	OutputIntent : {
		profile : ProfileId,
		registry_name : Str,
	}

	InspectionWork : {
		bytes_checked : U64,
		tag_edges_checked : U64,
		tags_checked : U64,
	}

	Store : {
		profiles : List(IccProfile),
		spaces : List(SpaceRecord),
		tags : List(IccTag),
	}
}

# ICC profile IDs preserve their dense index.
expect Color.ProfileId.from_index(3).index() == 3

# Color-space IDs preserve their dense index.
expect Color.SpaceId.from_index(5).index() == 5

# ICC tag signatures remain compact opaque U32 values.
expect Color.TagSignature.from_raw(0x64657363).raw() == 0x64657363

hex_color_message : Str
hex_color_message = "a color literal is an sRGB hex color \"#RRGGBB\": a hash and six hexadecimal digits, such as \"#183454\""

## One byte from two hexadecimal digits, upper- or lowercase.
hex_pair : U8, U8 -> Try(U8, [NotHex])
hex_pair = |high, low| {
	digit = |c| if c >= '0' and c <= '9' Ok(c - '0') else if c >= 'a' and c <= 'f' Ok(c - 'a' + 10) else if c >= 'A' and c <= 'F' Ok(c - 'A' + 10) else Err(NotHex)
	Ok(digit(high)? * 16 + digit(low)?)
}

# A hex literal is the sRGB color of its 8-bit channels.
expect {
	navy : Color.SourceValue
	navy = "#183454"
	lower : Color.SourceValue
	lower = "#c49640"
	navy == Color.srgb8({ red: 24, green: 52, blue: 84 }) and lower == Color.srgb8({ red: 196, green: 150, blue: 64 })
}

# Any other spelling is rejected.
expect Color.SourceValue.from_quote("183454").is_err() and Color.SourceValue.from_quote("#18345").is_err() and Color.SourceValue.from_quote("#18345g").is_err() and Color.SourceValue.from_quote("#1834540").is_err()
