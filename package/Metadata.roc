Metadata :: [].{
	TimestampInput : [Explicit(Str), Omitted]

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
