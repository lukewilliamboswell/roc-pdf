import Semantics

Color :: [].{
	ProfileId :: U64.{
		from_index : U64 -> ProfileId
		from_index = |index| ProfileId.(index)

		index : ProfileId -> U64
		index = |ProfileId.(index)| index
	}

	SpaceId :: U64.{
		from_index : U64 -> SpaceId
		from_index = |index| SpaceId.(index)

		index : SpaceId -> U64
		index = |SpaceId.(index)| index
	}

	TagSignature :: U32.{
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
	SourceValue : [Srgb(Channels)]

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

## ICC profile IDs preserve their dense index.
expect Color.ProfileId.from_index(3).index() == 3

## Color-space IDs preserve their dense index.
expect Color.SpaceId.from_index(5).index() == 5

## ICC tag signatures remain compact opaque U32 values.
expect Color.TagSignature.from_raw(0x64657363).raw() == 0x64657363
