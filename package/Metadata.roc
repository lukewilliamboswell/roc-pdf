Metadata :: [].{
	TimestampInput : [Explicit(Str), Omitted]

	## Stable typed rejections for authored metadata facts. Language values
	## are validated as canonical-case RFC 5646 `language[-script][-region]`
	## tags: malformed shapes, well-formed-but-unsupported forms, and
	## non-canonical letter case are distinct rejections, and nothing is
	## silently normalized. Timestamps accept exactly the canonical UTC form
	## `YYYY-MM-DDThh:mm:ssZ`. Titles must be non-empty, bounded, and free of
	## scalars that XML 1.0 cannot represent.
	Error : [
		EmptyLanguage,
		EmptyTitle,
		InvalidTimestamp({ field : [Created, Modified], offset : U64 }),
		InvalidTitleScalar({ offset : U64 }),
		LanguageNotCanonicalCase({ offset : U64 }),
		LanguageTooLong({ attempted : U64, limit : U64 }),
		MalformedLanguageTag({ offset : U64 }),
		TitleTooLong({ attempted : U64, limit : U64 }),
		UnsupportedLanguageForm({ offset : U64 }),
	]

	IdentifierInput : [
		Derived,
		Explicit({ changing : List(U8), permanent : List(U8) }),
	]

	## Logical metadata contains only authored or explicitly omitted facts. It
	## never reads a clock, locale, hostname, environment, or random source.
	Logical : {
		created : TimestampInput,
		identifier : IdentifierInput,
		language : Str,
		modified : TimestampInput,
		title : Str,
	}

	XmlVersion : [Xml10FifthEdition]
	PropertyOrder : [NamespaceUriThenLocalName]
	TitlePolicy : [RequireAuthoredAndDcTitleAgreement]
	TimestampPolicy : [ExplicitOrOmitted]
	RequiredAuthorFact : [Required]
	VisibleTitlePolicy : [RequiredForAccessibleArchive]

	AuthoringPolicy : {
		language : RequiredAuthorFact,
		metadata_title : RequiredAuthorFact,
		visible_title : VisibleTitlePolicy,
	}

	CanonicalPolicy : {
		property_order : PropertyOrder,
		timestamps : TimestampPolicy,
		title : TitlePolicy,
		xml : XmlVersion,
	}

	canonical : CanonicalPolicy
	canonical = {
		property_order: NamespaceUriThenLocalName,
		timestamps: ExplicitOrOmitted,
		title: RequireAuthoredAndDcTitleAgreement,
		xml: Xml10FifthEdition,
	}

	authoring : AuthoringPolicy
	authoring = {
		language: Required,
		metadata_title: Required,
		visible_title: RequiredForAccessibleArchive,
	}
}

## Canonical metadata never obtains an implicit timestamp.
expect Metadata.canonical.timestamps == ExplicitOrOmitted

## Canonical metadata orders properties independently of map iteration.
expect Metadata.canonical.property_order == NamespaceUriThenLocalName

## Accessible archival facade output requires a distinct visible semantic title.
expect Metadata.authoring.visible_title == RequiredForAccessibleArchive
