import KernelSha256
import KernelTimestamp

## Validate the authoring registry before layout or payload traversal. The
## sorted registry owns one handle to each opaque caller payload.
KernelAssociatedFiles :: [].{
	Relationship := [Alternative, Data, Source, Supplement].{
		is_eq : _
	}

	Necessity := [RequiredToUnderstand, Supplemental].{
		is_eq : _
	}

	File := {
		bytes : List(U8),
		description : Str,
		filename : Str,
		media_type : Str,
		modified : Str,
		necessity : Necessity,
		relationship : Relationship,
	}

	Limits : { count : U64, description_bytes : U64, file_bytes : U64, media_type_bytes : U64, total_bytes : U64 }

	key_bytes : U64
	key_bytes = filename_bytes + 3

	Error : [
		AccessibleDependency(U64),
		CountLimit({ actual : U64, maximum : U64 }),
		Description(U64),
		DescriptionLimit({ actual : U64, index : U64, maximum : U64 }),
		Duplicate(U64),
		Filename(U64),
		FileLimit({ actual : U64, index : U64, maximum : U64 }),
		FileRepresentationLimit({ actual : U64, index : U64, maximum : U64 }),
		MediaType(U64),
		MediaTypeLimit({ actual : U64, index : U64, maximum : U64 }),
		MediaNameRepresentationLimit(U64),
		Modified(U64),
		TotalLimit({ index : U64, maximum : U64 }),
		TextRepresentationLimit(U64),
	]

	Entry : {
		bytes : List(U8),
		description : Str,
		filename : Str,
		key : List(U8),
		legacy_filename : Str,
		media_type : List(U8),
		modified : Str,
		necessity : Necessity,
		position : U64,
		relationship : Relationship,
	}

	Plan :: { entries : List(Entry), media_type_bytes : U64, payload_bytes : U64, text_bytes : U64 }.{
		entries : Plan -> List(Entry)
		entries = |plan| plan.entries

		## Decoded name bytes for the MIME /Subtype values.
		media_type_bytes : Plan -> U64
		media_type_bytes = |plan| plan.media_type_bytes

		payload_bytes : Plan -> U64
		payload_bytes = |plan| plan.payload_bytes

		## Exact source bytes for the four text strings lowered per file.
		text_bytes : Plan -> U64
		text_bytes = |plan| plan.text_bytes

		build : List(File), Bool, Limits -> Try(Plan, Error)
		build = |files, accessible, bounds| {
			if files.len() > bounds.count {
				return Err(CountLimit({ actual: files.len(), maximum: bounds.count }))
			}
			var $remaining = bounds.total_bytes
			var $index = 0
			for file in files {
				size = file.bytes.len()
				if size > bounds.file_bytes {
					return Err(FileLimit({ actual: size, index: $index, maximum: bounds.file_bytes }))
				}
				# Sealing hashes each exact payload. The SHA-256 input bound
				# also keeps the PDF /Size integer within the signed range.
				if size > KernelSha256.max_input_length {
					return Err(FileRepresentationLimit({ actual: size, index: $index, maximum: KernelSha256.max_input_length }))
				}
				if size > $remaining {
					return Err(TotalLimit({ index: $index, maximum: bounds.total_bytes }))
				}
				$remaining = $remaining - size
				$index = $index + 1
			}
			var $entries = List.with_capacity(files.len())
			var $media_type_bytes = 0
			var $text_bytes = 0
			$index = 0
			for file in files {
				entry = prepare_entry(file, accessible, $index, { description: bounds.description_bytes, media_type: bounds.media_type_bytes })?
				$media_type_bytes = U64.plus_try($media_type_bytes, entry.media_type.len()) ? |_| MediaNameRepresentationLimit($index)
				# The portable Unicode and legacy filenames and the validated
				# date have a small fixed combined bound. The description does not.
				name_and_date = entry.filename.count_utf8_bytes() + entry.legacy_filename.count_utf8_bytes() + entry.modified.count_utf8_bytes()
				file_text = U64.plus_try(name_and_date, entry.description.count_utf8_bytes()) ? |_| TextRepresentationLimit($index)
				$text_bytes = U64.plus_try($text_bytes, file_text) ? |_| TextRepresentationLimit($index)
				$entries = $entries.append(entry)
				$index = $index + 1
			}
			sorted = $entries.sort_with(
				|left, right| {
					match compare_keys(left.key, right.key) {
						Same => if (left.position < right.position) Before else if (left.position > right.position) After else Same
						order => order
					}
				},
			)
			$index = 1
			while $index < sorted.len() {
				current = list_at(sorted, $index)
				if list_at(sorted, $index - 1).key == current.key {
					return Err(Duplicate(current.position))
				}
				$index = $index + 1
			}
			Ok(Plan.{ entries: sorted, media_type_bytes: $media_type_bytes, payload_bytes: bounds.total_bytes - $remaining, text_bytes: $text_bytes })
		}
	}
}

filename_bytes : U64
filename_bytes = 255

prepare_entry : KernelAssociatedFiles.File, Bool, U64, { description : U64, media_type : U64 } -> Try(KernelAssociatedFiles.Entry, KernelAssociatedFiles.Error)
prepare_entry = |file, accessible, position, limits| {
	if accessible and file.necessity == RequiredToUnderstand {
		return Err(AccessibleDependency(position))
	}
	name = Str.to_utf8(file.filename)
	if name.is_empty() or name.len() > filename_bytes or file.filename == "." or file.filename == ".." {
		return Err(Filename(position))
	}
	for byte in name {
		if byte < 32 or byte == 127 or byte == 47 or byte == 92 or byte == 58 {
			return Err(Filename(position))
		}
	}
	ending = list_at(name, name.len() - 1)
	if ending == 32 or ending == 46 {
		return Err(Filename(position))
	}
	description_bytes = file.description.count_utf8_bytes()
	if description_bytes > limits.description {
		return Err(DescriptionLimit({ actual: description_bytes, index: position, maximum: limits.description }))
	}
	if file.description.trim().is_empty() {
		return Err(Description(position))
	}
	for byte in Str.to_utf8(file.description) {
		if byte < 32 or byte == 127 {
			return Err(Description(position))
		}
	}
	media_bytes = file.media_type.count_utf8_bytes()
	if media_bytes > limits.media_type {
		return Err(MediaTypeLimit({ actual: media_bytes, index: position, maximum: limits.media_type }))
	}
	mime = Str.to_utf8(file.media_type)
	if !valid_media_type(mime) {
		return Err(MediaType(position))
	}
	# ISO 32000-2:2020 14.13.2 requires the associated file's ModDate.
	modified = Str.to_utf8(file.modified)
	match KernelTimestamp.invalid_utc(modified) {
		NoViolation => {}
		ViolationAt(_) => return Err(Modified(position))
	}
	var $pdf_date = List.with_capacity(17).append(68).append(58)
	for byte in modified {
		if (byte >= 48 and byte <= 57) or byte == 90 {
			$pdf_date = $pdf_date.append(byte)
		}
	}
	# ISO 32000-2 7.9.2.2.3 and 7.9.6. Text keys use exactly UTF-8 with
	# BOM and are sorted by unsigned encoded bytes. No Unicode normalization.
	var $key = List.with_capacity(name.len() + 3)
	$key = $key.append(239).append(187).append(191)
	var $legacy = List.with_capacity(name.len())
	for byte in name {
		$key = $key.append(byte)
		if byte == 37 or byte >= 127 {
			$legacy = $legacy.append(37).append(hex_digit(U8.div_by(byte, 16))).append(hex_digit(U8.mod_by(byte, 16)))
		} else {
			$legacy = $legacy.append(byte)
		}
	}
	Ok({
		bytes: file.bytes,
		description: file.description,
		filename: file.filename,
		key: $key,
		legacy_filename: Str.from_utf8($legacy) ?? crash "portable associated filename must be ASCII",
		media_type: mime,
		modified: Str.from_utf8($pdf_date) ?? crash "the validated PDF date is ASCII",
		necessity: file.necessity,
		position,
		relationship: file.relationship,
	})
}

hex_digit : U8 -> U8
hex_digit = |digit| if (digit < 10) 48 + digit else 55 + digit

## ISO 32000-2:2020 7.11.4 Table 44 (errata) and ISO 19005-4:2020
## 6.9. Use the parameter-free ASCII registered-name subset of media types.
## RFC 6838 §4.2 limits each component to 127 characters.
media_component_bytes : U64
media_component_bytes = 127

valid_media_type : List(U8) -> Bool
valid_media_type = |mime| {
	if mime.len() < 3 or mime.len() > 2 * media_component_bytes + 1 {
		return False
	}
	var $saw_slash = False
	var $part_length = 0
	for byte in mime {
		if byte == 47 {
			if $saw_slash or $part_length == 0 {
				return False
			}
			$saw_slash = True
			$part_length = 0
		} else {
			alphanumeric = (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
			if $part_length == media_component_bytes or (!alphanumeric and ($part_length == 0 or (byte != 43 and byte != 45 and byte != 46 and byte != 95))) {
				return False
			}
			$part_length = $part_length + 1
		}
	}
	$saw_slash and $part_length != 0
}

expect {
	part = Str.repeat("a", 127)
	over = Str.repeat("a", 128)
	valid_media_type(Str.to_utf8("${part}/${part}"))
		and !valid_media_type(Str.to_utf8("${over}/a"))
		and !valid_media_type(Str.to_utf8("a/${over}"))
}

compare_keys : List(U8), List(U8) -> [After, Before, Same]
compare_keys = |left, right| {
	common = if (left.len() < right.len()) left.len() else right.len()
	var $index = 0
	while $index < common {
		a = list_at(left, $index)
		b = list_at(right, $index)
		if a != b {
			return if (a < b) Before else After
		}
		$index = $index + 1
	}
	if (left.len() < right.len()) Before else if (left.len() > right.len()) After else Same
}

list_at : List(a), U64 -> a
list_at = |list, index| list.get(index) ?? crash "validated associated-file registry index escaped its list"
