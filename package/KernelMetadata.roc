## Validated document-metadata facts for the Gate 4 metadata/output-intent
## slice. Authoring supplies a metadata title, a document language, and
## explicit-or-omitted timestamps; this boundary validates them once against
## the pinned RFC 5646 and XML 1.0 policies and returns typed facts that later
## stages consume verbatim. No later stage re-parses, re-normalizes, or
## recovers these values from serialized bytes.
##
## The language policy accepts the canonical-case well-formed RFC 5646 subset
## `language["-" script]["-" region]`: a two- or three-letter lowercase
## primary language, an optional four-letter titlecase script, and an optional
## uppercase two-letter or three-digit region. Well-formed tags outside that
## subset (extended language subtags, variants, extensions, private use, and
## single-letter primaries) are rejected as unsupported rather than silently
## accepted, and non-canonical letter case is rejected rather than silently
## normalized. Registry validity beyond RFC 5646 syntax is out of scope
## because the IANA subtag registry is not a pinned data dependency.
##
## The timestamp policy accepts exactly the canonical UTC form
## `YYYY-MM-DDThh:mm:ssZ` with a valid proleptic-Gregorian calendar date.
## Titles must be non-empty UTF-8 whose scalars are valid XML 1.0 characters
## outside the C0/DEL controls; the validation pass also counts the XML escape
## substitutions once so canonical XMP serialization can reserve its exact
## output size without rescanning.
import Color
import KernelObject
import KernelSrgbProfile
import Metadata

KernelMetadata :: [].{

	## XML escape counts for the validated title, produced by the same
	## validation scan that checks its scalars.
	Escapes : { amps : U64, gts : U64, lts : U64 }

	Facts : {
		created : Metadata.TimestampInput,
		language : Str,
		modified : Metadata.TimestampInput,
		title : Str,
		title_escapes : Escapes,
	}

	Limits :: { max_language_bytes : U64, max_title_bytes : U64 }.{
		make : { max_language_bytes : U64, max_title_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : { language_bytes : U64, timestamp_bytes : U64, title_bytes : U64 }

	## Output-intent configuration errors are kernel-boundary rejections: the
	## public facade constructs its intent from the packaged profile identity
	## directly, so these states are unrepresentable through `Pdf`.
	IntentError : [
		IntentComponentMismatch({ expected : U64, profile : U64 }),
		IntentProfileMismatch({ bytes_compared : U64, profile : U64 }),
		IntentProfileOutOfRange({ attempted : U64, profiles : U64 }),
		UnsupportedConditionIdentifier,
		UnsupportedIntentRegistry,
	]

	IntentWork : { intent_bytes_compared : U64 }

	## The document-fact input threaded through structure planning. Absent
	## facts keep every existing plan byte-identical; present facts add the
	## catalog language, the canonical XMP metadata stream, and the packaged
	## sRGB output intent to the lowered plan.
	PlanFacts : [
		NoDocumentFacts,
		WithDocumentFacts(
			{
				condition_identifier : Str,
				profile : Color.ProfileId,
				registry_name : Str,
				language : Str,
				xmp : List(U8),
			},
		),
	]

	## Catalog-writer input resolved from `PlanFacts`: the planner has already
	## assigned the metadata-stream and ICC profile-stream object identities.
	CatalogFacts : [
		NoCatalogFacts,
		WithCatalogFacts(
			{
				condition_identifier : Str,
				language : Str,
				metadata_stream : KernelObject.ObjectId,
				profile_stream : KernelObject.ObjectId,
				registry_name : Str,
			},
		),
	]

	## Object identities appended by the metadata phase after an existing
	## planned object count: the metadata stream, its indirect length, and the
	## shifted xref position.
	Objects : { length : KernelObject.ObjectId, stream : KernelObject.ObjectId, xref : KernelObject.ObjectId }

	## The output-intent identifier facts for the packaged profile: sRGB2014
	## is the ICC's published identifier for the pinned asset, and color.org
	## is its registry.
	srgb_condition_identifier : Str
	srgb_condition_identifier = "sRGB2014"

	icc_registry_name : Str
	icc_registry_name = "http://www.color.org"

	validate : { created : Metadata.TimestampInput, language : Str, modified : Metadata.TimestampInput, title : Str }, Limits -> Try({ facts : Facts, work : Work }, Metadata.Error)
	validate = |input, Limits.(limits)| {
		language = validate_language(input.language, limits.max_language_bytes)?
		title = validate_title(input.title, limits.max_title_bytes)?
		created = validate_timestamp(input.created, Created)?
		modified = validate_timestamp(input.modified, Modified)?
		Ok({
			facts: {
				created: input.created,
				language: input.language,
				modified: input.modified,
				title: input.title,
				title_escapes: title.escapes,
			},
			work: {
				language_bytes: language.bytes,
				timestamp_bytes: created + modified,
				title_bytes: title.bytes,
			},
		})
	}

	## Validate an output-intent request against the validated color store.
	## The implemented capability is exactly the packaged sRGB profile, so the
	## referenced profile must match its bytes exactly; the comparison runs
	## once here and its cost is reported as explicit work.
	validate_intent : Color.OutputIntent, Str, Color.Store -> Try(IntentWork, IntentError)
	validate_intent = |intent, condition_identifier, store| {
		if intent.registry_name != icc_registry_name {
			return Err(UnsupportedIntentRegistry)
		}
		if condition_identifier != srgb_condition_identifier {
			return Err(UnsupportedConditionIdentifier)
		}
		index = intent.profile.index()
		if index >= store.profiles.len() {
			return Err(IntentProfileOutOfRange({ attempted: index, profiles: store.profiles.len() }))
		}
		profile = list_at(store.profiles, index)
		match profile.components {
			Three => {}
			One => return Err(IntentComponentMismatch({ expected: 3, profile: index }))
		}
		compared = compare_packaged_bytes(profile.bytes)
		match compared {
			Equal(bytes) => Ok({ intent_bytes_compared: bytes })
			Diverged(bytes) => Err(IntentProfileMismatch({ bytes_compared: bytes, profile: index }))
		}
	}

	## Metadata-phase object identities appended after `base_count` planned
	## objects.
	plan_objects : U64 -> Try(Objects, [ObjectNumberOverflow])
	plan_objects = |base_count| {
		stream = object_id(checked(base_count, 1)?)?
		length = object_id(checked(base_count, 2)?)?
		xref = object_id(checked(base_count, 3)?)?
		Ok({ length, stream, xref })
	}
}

## The packaged profile equality probe compares at most one profile length and
## stops at the first diverging byte.
compare_packaged_bytes : List(U8) -> [Diverged(U64), Equal(U64)]
compare_packaged_bytes = |bytes| {
	packaged = KernelSrgbProfile.bytes
	if bytes.len() != packaged.len() {
		Diverged(0)
	} else {
		var $index = 0
		var $diverged = False
		while $index < packaged.len() and $diverged == False {
			if list_at(bytes, $index) != list_at(packaged, $index) {
				$diverged = True
			} else {
				$index = $index + 1
			}
		}
		if $diverged Diverged($index + 1) else Equal($index)
	}
}

validate_language : Str, U64 -> Try({ bytes : U64 }, Metadata.Error)
validate_language = |language, max_bytes| {
	bytes = Str.to_utf8(language)
	length = bytes.len()
	if length == 0 {
		return Err(EmptyLanguage)
	}
	if length > max_bytes {
		return Err(LanguageTooLong({ attempted: length, limit: max_bytes }))
	}
	var $start = 0
	var $index = 0
	var $position = PrimaryLanguage
	var $outcome = Scanning
	while $index <= length and $outcome == Scanning {
		at_end = $index == length
		byte = if at_end 0x2D else list_at(bytes, $index)
		if byte == 0x2D {
			match classify_subtag(bytes, $start, $index, $position) {
				Err(error) => {
					$outcome = Rejected(error)
				}
				Ok(next_position) => if at_end {
					$outcome = Accepted
				} else {
					$position = next_position
					$start = $index + 1
				}
			}
		} else if !is_alphanumeric(byte) {
			$outcome = Rejected(MalformedLanguageTag({ offset: $index }))
		}
		$index = $index + 1
	}
	match $outcome {
		Accepted => Ok({ bytes: length })
		Rejected(error) => Err(error)
		Scanning => {
			crash "language subtag scan invariant failed"
		}
	}
}

SubtagPosition : [Complete, PrimaryLanguage, RegionOnly, ScriptOrRegion]

## Classify one subtag against the canonical-case
## `language["-" script]["-" region]` subset. Well-formed RFC 5646 shapes
## outside the subset reject as unsupported; shapes RFC 5646 itself does not
## permit reject as malformed; wrong letter case in an otherwise supported
## subtag rejects as non-canonical.
classify_subtag : List(U8), U64, U64, SubtagPosition -> Try(SubtagPosition, Metadata.Error)
classify_subtag = |bytes, start, end, position| {
	length = end - start
	if length == 0 {
		return Err(MalformedLanguageTag({ offset: start }))
	}
	shape = subtag_shape(bytes, start, end)
	match position {
		PrimaryLanguage => match shape {
			LowerAlpha => if length >= 2 and length <= 3 {
				Ok(ScriptOrRegion)
			} else {
				subtag_outside_subset(length, start)
			}
			MixedAlpha | UpperAlpha | TitleAlpha => if length >= 2 and length <= 3 {
				Err(LanguageNotCanonicalCase({ offset: start }))
			} else {
				subtag_outside_subset(length, start)
			}
			Digits | MixedAlphanumeric => Err(MalformedLanguageTag({ offset: start }))
		}
		ScriptOrRegion => match shape {
			TitleAlpha => if length == 4 {
				Ok(RegionOnly)
			} else {
				Err(LanguageNotCanonicalCase({ offset: start }))
			}
			UpperAlpha => if length == 2 {
				Ok(Complete)
			} else if length == 4 {
				Err(LanguageNotCanonicalCase({ offset: start }))
			} else {
				subtag_outside_subset(length, start)
			}
			Digits => if length == 3 {
				Ok(Complete)
			} else {
				subtag_outside_subset(length, start)
			}
			LowerAlpha | MixedAlpha => if length == 2 or length == 4 {
				Err(LanguageNotCanonicalCase({ offset: start }))
			} else {
				subtag_outside_subset(length, start)
			}
			MixedAlphanumeric => subtag_outside_subset(length, start)
		}
		RegionOnly => match shape {
			UpperAlpha => if length == 2 {
				Ok(Complete)
			} else {
				subtag_outside_subset(length, start)
			}
			Digits => if length == 3 {
				Ok(Complete)
			} else {
				subtag_outside_subset(length, start)
			}
			LowerAlpha | MixedAlpha | TitleAlpha => if length == 2 {
				Err(LanguageNotCanonicalCase({ offset: start }))
			} else {
				subtag_outside_subset(length, start)
			}
			MixedAlphanumeric => subtag_outside_subset(length, start)
		}
		Complete => subtag_outside_subset(length, start)
	}
}

## Subtags RFC 5646 can represent but the subset does not (singletons,
## variants, extended language subtags, and anything after a region) reject as
## unsupported; shapes with no RFC 5646 production reject as malformed.
subtag_outside_subset : U64, U64 -> Try(SubtagPosition, Metadata.Error)
subtag_outside_subset = |length, start| if length == 1 or (length >= 3 and length <= 8) {
	Err(UnsupportedLanguageForm({ offset: start }))
} else {
	Err(MalformedLanguageTag({ offset: start }))
}

SubtagShape : [Digits, LowerAlpha, MixedAlpha, MixedAlphanumeric, TitleAlpha, UpperAlpha]

subtag_shape : List(U8), U64, U64 -> SubtagShape
subtag_shape = |bytes, start, end| {
	var $lower = 0
	var $upper = 0
	var $digit = 0
	var $index = start
	while $index < end {
		byte = list_at(bytes, $index)
		if is_lower(byte) {
			$lower = $lower + 1
		} else if is_upper(byte) {
			$upper = $upper + 1
		} else {
			$digit = $digit + 1
		}
		$index = $index + 1
	}
	length = end - start
	if $digit == length {
		Digits
	} else if $digit > 0 {
		MixedAlphanumeric
	} else if $lower == length {
		LowerAlpha
	} else if $upper == length {
		UpperAlpha
	} else if $upper == 1 and is_upper(list_at(bytes, start)) {
		TitleAlpha
	} else {
		MixedAlpha
	}
}

validate_title : Str, U64 -> Try({ bytes : U64, escapes : KernelMetadata.Escapes }, Metadata.Error)
validate_title = |title, max_bytes| {
	bytes = Str.to_utf8(title)
	length = bytes.len()
	if length == 0 {
		return Err(EmptyTitle)
	}
	if length > max_bytes {
		return Err(TitleTooLong({ attempted: length, limit: max_bytes }))
	}
	var $amps = 0
	var $lts = 0
	var $gts = 0
	var $index = 0
	var $invalid = NoInvalid
	while $index < length and $invalid == NoInvalid {
		byte = list_at(bytes, $index)
		if byte < 0x20 or byte == 0x7F {
			$invalid = InvalidAt($index)
		} else if byte == 0xEF and $index + 2 < length and list_at(bytes, $index + 1) == 0xBF and list_at(bytes, $index + 2) >= 0xBE {

			## U+FFFE and U+FFFF are excluded from XML 1.0 characters.
			$invalid = InvalidAt($index)
		} else {
			if byte == 0x26 {
				$amps = $amps + 1
			} else if byte == 0x3C {
				$lts = $lts + 1
			} else if byte == 0x3E {
				$gts = $gts + 1
			}
			$index = $index + 1
		}
	}
	match $invalid {
		InvalidAt(offset) => Err(InvalidTitleScalar({ offset: offset }))
		NoInvalid => Ok({ bytes: length, escapes: { amps: $amps, gts: $gts, lts: $lts } })
	}
}

validate_timestamp : Metadata.TimestampInput, [Created, Modified] -> Try(U64, Metadata.Error)
validate_timestamp = |input, field| match input {
	Omitted => Ok(0)
	Explicit(text) => {
		bytes = Str.to_utf8(text)
		if bytes.len() != 20 {
			Err(InvalidTimestamp({ field: field, offset: bytes.len() }))
		} else {
			match timestamp_violation(bytes) {
				NoViolation => Ok(20)
				ViolationAt(offset) => Err(InvalidTimestamp({ field: field, offset: offset }))
			}
		}
	}
}

## The canonical timestamp form is `YYYY-MM-DDThh:mm:ssZ`: a UTC instant with
## a valid proleptic-Gregorian date and no fractional seconds or offsets.
timestamp_violation : List(U8) -> [NoViolation, ViolationAt(U64)]
timestamp_violation = |bytes| {
	digits_ok = digit_run_ok(bytes, 0, 4) and digit_run_ok(bytes, 5, 2) and digit_run_ok(bytes, 8, 2) and digit_run_ok(bytes, 11, 2) and digit_run_ok(bytes, 14, 2) and digit_run_ok(bytes, 17, 2)
	if !digits_ok {
		first_bad_digit(bytes)
	} else if list_at(bytes, 4) != 0x2D {
		ViolationAt(4)
	} else if list_at(bytes, 7) != 0x2D {
		ViolationAt(7)
	} else if list_at(bytes, 10) != 0x54 {
		ViolationAt(10)
	} else if list_at(bytes, 13) != 0x3A {
		ViolationAt(13)
	} else if list_at(bytes, 16) != 0x3A {
		ViolationAt(16)
	} else if list_at(bytes, 19) != 0x5A {
		ViolationAt(19)
	} else {
		year = digit_run_value(bytes, 0, 4)
		month = digit_run_value(bytes, 5, 2)
		day = digit_run_value(bytes, 8, 2)
		hour = digit_run_value(bytes, 11, 2)
		minute = digit_run_value(bytes, 14, 2)
		second = digit_run_value(bytes, 17, 2)
		if year == 0 {
			ViolationAt(0)
		} else if month == 0 or month > 12 {
			ViolationAt(5)
		} else if day == 0 or day > days_in_month(year, month) {
			ViolationAt(8)
		} else if hour > 23 {
			ViolationAt(11)
		} else if minute > 59 {
			ViolationAt(14)
		} else if second > 59 {
			ViolationAt(17)
		} else {
			NoViolation
		}
	}
}

first_bad_digit : List(U8) -> [NoViolation, ViolationAt(U64)]
first_bad_digit = |bytes| {
	var $offset = NoViolation
	var $index = 0
	while $index < 20 and $offset == NoViolation {
		in_digit_run = $index <= 3 or ($index >= 5 and $index <= 6) or ($index >= 8 and $index <= 9) or ($index >= 11 and $index <= 12) or ($index >= 14 and $index <= 15) or ($index >= 17 and $index <= 18)
		if in_digit_run and !is_digit(list_at(bytes, $index)) {
			$offset = ViolationAt($index)
		}
		$index = $index + 1
	}
	$offset
}

digit_run_ok : List(U8), U64, U64 -> Bool
digit_run_ok = |bytes, start, count| {
	var $index = 0
	var $ok = True
	while $index < count and $ok {
		if !is_digit(list_at(bytes, start + $index)) {
			$ok = False
		}
		$index = $index + 1
	}
	$ok
}

digit_run_value : List(U8), U64, U64 -> U64
digit_run_value = |bytes, start, count| {
	var $value = 0
	var $index = 0
	while $index < count {
		$value = $value * 10 + (list_at(bytes, start + $index) - 0x30).to_u64()
		$index = $index + 1
	}
	$value
}

days_in_month : U64, U64 -> U64
days_in_month = |year, month| if month == 2 {
	leap = U64.mod_by(year, 4) == 0 and (U64.mod_by(year, 100) != 0 or U64.mod_by(year, 400) == 0)
	if leap 29 else 28
} else if month == 4 or month == 6 or month == 9 or month == 11 {
	30
} else {
	31
}

is_lower : U8 -> Bool
is_lower = |byte| byte >= 0x61 and byte <= 0x7A

is_upper : U8 -> Bool
is_upper = |byte| byte >= 0x41 and byte <= 0x5A

is_digit : U8 -> Bool
is_digit = |byte| byte >= 0x30 and byte <= 0x39

is_alphanumeric : U8 -> Bool
is_alphanumeric = |byte| is_lower(byte) or is_upper(byte) or is_digit(byte)

object_id : U64 -> Try(KernelObject.ObjectId, [ObjectNumberOverflow])
object_id = |number| {
	id = KernelObject.ObjectId.from_number(number) ? |_| ObjectNumberOverflow
	Ok(id)
}

checked : U64, U64 -> Try(U64, [ObjectNumberOverflow])
checked = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ObjectNumberOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated metadata index escaped"
	}
}

test_limits : KernelMetadata.Limits
test_limits = KernelMetadata.Limits.make({ max_language_bytes: 64, max_title_bytes: 2048 })

valid_input : { created : Metadata.TimestampInput, language : Str, modified : Metadata.TimestampInput, title : Str }
valid_input = { created: Omitted, language: "en-AU", modified: Omitted, title: "Report" }

## Canonical language, script, and region forms validate with exact work.
expect {
	result = KernelMetadata.validate(valid_input, test_limits)?

	result.facts.language == "en-AU" and result.work == { language_bytes: 5, timestamp_bytes: 0, title_bytes: 6 }
}

## The full canonical language-script-region subset is accepted.
expect {
	forms = ["en", "de-DE", "zh-Hans", "zh-Hans-CN", "yue", "es-419", "und"]
	var $index = 0
	var $ok = True
	while $index < forms.len() {
		form = list_at(forms, $index)
		match KernelMetadata.validate({ ..valid_input, language: form }, test_limits) {
			Ok(_) => {}
			Err(_) => {
				$ok = False
			}
		}
		$index = $index + 1
	}
	$ok
}

## Non-canonical letter case rejects rather than silently normalizing.
expect match KernelMetadata.validate({ ..valid_input, language: "en-au" }, test_limits) {
	Err(LanguageNotCanonicalCase({ offset: 3 })) => True
	_ => False
}

## Uppercase primary subtags are the non-canonical form of a supported tag.
expect match KernelMetadata.validate({ ..valid_input, language: "EN" }, test_limits) {
	Err(LanguageNotCanonicalCase({ offset: 0 })) => True
	_ => False
}

## Lowercase script subtags reject as non-canonical case.
expect match KernelMetadata.validate({ ..valid_input, language: "zh-hans" }, test_limits) {
	Err(LanguageNotCanonicalCase({ offset: 3 })) => True
	_ => False
}

## Well-formed RFC 5646 forms outside the subset reject as unsupported:
## private use, singletons, variants, and extended language subtags.
expect {
	forms = ["x-private", "en-x-priv", "de-DE-1996", "zh-yue-HK", "en-a-bbbb"]
	var $index = 0
	var $ok = True
	while $index < forms.len() {
		form = list_at(forms, $index)
		match KernelMetadata.validate({ ..valid_input, language: form }, test_limits) {
			Err(UnsupportedLanguageForm(_)) => {}
			_ => {
				$ok = False
			}
		}
		$index = $index + 1
	}
	$ok
}

## Shapes RFC 5646 cannot produce reject as malformed with the byte offset.
expect match KernelMetadata.validate({ ..valid_input, language: "en--AU" }, test_limits) {
	Err(MalformedLanguageTag({ offset: 3 })) => True
	_ => False
}

## Non-alphanumeric bytes are malformed at their exact offset.
expect match KernelMetadata.validate({ ..valid_input, language: "en_AU" }, test_limits) {
	Err(MalformedLanguageTag({ offset: 2 })) => True
	_ => False
}

## A trailing hyphen is malformed, not an empty trailing subtag.
expect match KernelMetadata.validate({ ..valid_input, language: "en-" }, test_limits) {
	Err(MalformedLanguageTag({ offset: 3 })) => True
	_ => False
}

## Digit-bearing primary subtags have no RFC 5646 production.
expect match KernelMetadata.validate({ ..valid_input, language: "e1" }, test_limits) {
	Err(MalformedLanguageTag({ offset: 0 })) => True
	_ => False
}

## A second region after a complete tag is malformed.
expect match KernelMetadata.validate({ ..valid_input, language: "en-AU-NZ" }, test_limits) {
	Err(MalformedLanguageTag({ offset: 6 })) => True
	_ => False
}

## Empty and oversized language values reject with their exact bounds.
expect match KernelMetadata.validate({ ..valid_input, language: "" }, test_limits) {
	Err(EmptyLanguage) => True
	_ => False
}

expect {
	limits = KernelMetadata.Limits.make({ max_language_bytes: 4, max_title_bytes: 2048 })
	match KernelMetadata.validate(valid_input, limits) {
		Err(LanguageTooLong({ attempted: 5, limit: 4 })) => True
		_ => False
	}
}

## Titles retain exact escape counts for canonical XMP serialization.
expect {
	result = KernelMetadata.validate({ ..valid_input, title: "R&D <plan> & more" }, test_limits)?

	result.facts.title_escapes == { amps: 2, gts: 1, lts: 1 }
}

## Empty titles, oversized titles, and XML-invalid scalars reject atomically.
expect match KernelMetadata.validate({ ..valid_input, title: "" }, test_limits) {
	Err(EmptyTitle) => True
	_ => False
}

expect {
	limits = KernelMetadata.Limits.make({ max_language_bytes: 64, max_title_bytes: 5 })
	match KernelMetadata.validate(valid_input, limits) {
		Err(TitleTooLong({ attempted: 6, limit: 5 })) => True
		_ => False
	}
}

expect match KernelMetadata.validate({ ..valid_input, title: "Tab\tseparated" }, test_limits) {
	Err(InvalidTitleScalar({ offset: 3 })) => True
	_ => False
}

## U+FFFF is not an XML 1.0 character even though it is valid UTF-8.
expect {
	title = match Str.from_utf8(Str.to_utf8("Bad ").concat([0xEF, 0xBF, 0xBF]).concat(Str.to_utf8("end"))) {
		Ok(value) => value
		Err(_) => {
			crash "test title construction failed"
		}
	}
	match KernelMetadata.validate({ ..valid_input, title }, test_limits) {
		Err(InvalidTitleScalar({ offset: 4 })) => True
		_ => False
	}
}

## U+FFFD remains a valid XML scalar adjacent to the excluded pair.
expect {
	title = match Str.from_utf8(Str.to_utf8("Ok ").concat([0xEF, 0xBF, 0xBD])) {
		Ok(value) => value
		Err(_) => {
			crash "test title construction failed"
		}
	}
	match KernelMetadata.validate({ ..valid_input, title }, test_limits) {
		Ok(_) => True
		Err(_) => False
	}
}

## Canonical UTC timestamps validate, including a leap-year day.
expect {
	result = KernelMetadata.validate(
		{ ..valid_input, created: Explicit("2024-02-29T23:59:59Z"), modified: Explicit("2026-08-18T09:30:00Z") },
		test_limits,
	)?

	result.work.timestamp_bytes == 40
}

## Non-leap February 29, bad separators, and out-of-range fields reject with
## the exact field and offset.
expect match KernelMetadata.validate({ ..valid_input, created: Explicit("2023-02-29T00:00:00Z") }, test_limits) {
	Err(InvalidTimestamp({ field: Created, offset: 8 })) => True
	_ => False
}

expect match KernelMetadata.validate({ ..valid_input, modified: Explicit("2026-08-18 09:30:00Z") }, test_limits) {
	Err(InvalidTimestamp({ field: Modified, offset: 10 })) => True
	_ => False
}

expect match KernelMetadata.validate({ ..valid_input, created: Explicit("2026-13-01T00:00:00Z") }, test_limits) {
	Err(InvalidTimestamp({ field: Created, offset: 5 })) => True
	_ => False
}

expect match KernelMetadata.validate({ ..valid_input, created: Explicit("2026-08-18T24:00:00Z") }, test_limits) {
	Err(InvalidTimestamp({ field: Created, offset: 11 })) => True
	_ => False
}

## Timestamps with offsets or fractional seconds are not the canonical form.
expect match KernelMetadata.validate({ ..valid_input, created: Explicit("2026-08-18T09:30:00+10:00") }, test_limits) {
	Err(InvalidTimestamp({ field: Created, offset: 25 })) => True
	_ => False
}

## The packaged-profile output intent validates against the exact store entry.
expect {
	store : Color.Store
	store = {
		profiles: [KernelSrgbProfile.profile(0, 0)],
		spaces: [],
		tags: KernelSrgbProfile.tags,
	}
	work = KernelMetadata.validate_intent(
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		store,
	)?

	work.intent_bytes_compared == KernelSrgbProfile.byte_count
}

## An altered profile byte rejects with the exact diverging position.
expect {
	altered = match KernelSrgbProfile.bytes.set(100, 255) {
		Ok(bytes) => bytes
		Err(OutOfBounds) => {
			crash "test profile mutation failed"
		}
	}

	store : Color.Store
	store = {
		profiles: [{ ..KernelSrgbProfile.profile(0, 0), bytes: altered }],
		spaces: [],
		tags: KernelSrgbProfile.tags,
	}
	match KernelMetadata.validate_intent(
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		store,
	) {
		Err(IntentProfileMismatch({ bytes_compared: 101, profile: 0 })) => True
		_ => False
	}
}

## Truncated packaged bytes reject before any byte comparison.
expect {
	truncated = KernelSrgbProfile.bytes.sublist({ start: 0, len: 100 })

	store : Color.Store
	store = {
		profiles: [{ ..KernelSrgbProfile.profile(0, 0), bytes: truncated }],
		spaces: [],
		tags: KernelSrgbProfile.tags,
	}
	match KernelMetadata.validate_intent(
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		store,
	) {
		Err(IntentProfileMismatch({ bytes_compared: 0, profile: 0 })) => True
		_ => False
	}
}

## Unsupported registries, identifiers, and out-of-range profiles reject.
expect {
	store : Color.Store
	store = { profiles: [KernelSrgbProfile.profile(0, 0)], spaces: [], tags: KernelSrgbProfile.tags }
	registry = KernelMetadata.validate_intent(
		{ profile: Color.ProfileId.from_index(0), registry_name: "http://example.com" },
		KernelMetadata.srgb_condition_identifier,
		store,
	)
	identifier = KernelMetadata.validate_intent(
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		"AdobeRGB",
		store,
	)
	range = KernelMetadata.validate_intent(
		{ profile: Color.ProfileId.from_index(1), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		store,
	)
	registry_ok = match registry {
		Err(UnsupportedIntentRegistry) => True
		_ => False
	}
	identifier_ok = match identifier {
		Err(UnsupportedConditionIdentifier) => True
		_ => False
	}
	range_ok = match range {
		Err(IntentProfileOutOfRange({ attempted: 1, profiles: 1 })) => True
		_ => False
	}
	registry_ok and identifier_ok and range_ok
}

## A grayscale profile cannot satisfy the three-component sRGB intent.
expect {
	store : Color.Store
	store = {
		profiles: [{ ..KernelSrgbProfile.profile(0, 0), components: One }],
		spaces: [],
		tags: KernelSrgbProfile.tags,
	}
	match KernelMetadata.validate_intent(
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		store,
	) {
		Err(IntentComponentMismatch({ expected: 3, profile: 0 })) => True
		_ => False
	}
}

## Metadata-phase objects append immediately after the planned base count.
expect {
	objects = KernelMetadata.plan_objects(47)?

	KernelObject.ObjectId.number(objects.stream) == 48 and KernelObject.ObjectId.number(objects.length) == 49 and KernelObject.ObjectId.number(objects.xref) == 50
}
