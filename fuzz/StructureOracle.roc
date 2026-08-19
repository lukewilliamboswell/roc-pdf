import "../tests/structural_kernel/blank.pdf" as blank_document : List(U8)
import "../tests/structural_kernel/deflate.pdf" as deflate_document : List(U8)
import "../tests/color_images/color_images.pdf" as image_document : List(U8)

## An independent structural oracle over emitted PDF bytes.
##
## Architectural position. `AGENTS.md` keeps this a generation-only package and
## forbids introducing PDF reading, so nothing here may migrate into
## `package/`. This module lives in `fuzz/`, which `fuzz/README.md` documents as
## evidence-only applications outside the production package: it is a test-time
## structural checker in the same category as `scripts/check_pdf_structure.py`,
## and it must never become reachable from the public facade.
##
## Independence is the whole point of the module, so it imports no package
## module at all -- not `pdf.KernelLex`, `pdf.KernelEmit`, `pdf.KernelSeal`,
## `pdf.KernelStructure`, `pdf.KernelSha256`, or `pdf.KernelDeflate`. Every
## expected byte shape below is written out from the file format rather than
## produced by the writers under test. Building expectations out of the
## emitter's own writers would make the oracle agree with the emitter by
## construction on exactly the number formatting, object numbering, and offset
## arithmetic where a defect would live, which is the same reason
## `fuzz/FontTargets.roc` reimplements TrueType checksum arithmetic instead of
## reusing `KernelFont`. The fuzz root `fuzz/facade_structure.roc` is the only
## file in this pair that touches `pdf.Pdf` and `pdf.Document`, and it uses them
## only to produce bytes.
##
## Parsing strategy. The oracle never scans for an `N 0 obj` header, because
## stream payloads carry deflate, JPEG, ICC, and font bytes that can contain
## that sequence anywhere. It drives from the trailing `startxref` to the
## cross-reference stream and derives every object boundary from the recorded
## offsets, so it always knows which byte ranges are payload and must be left
## untokenized.
StructureOracle :: [].{

	## Every rejection names the object it was found in where one applies, so a
	## fuzz crash points at the object to look at rather than only reporting
	## that something somewhere was wrong.
	Failure : [
		BadContiguity(U64),
		BadEndOfFile,
		BadFilter(U64),
		BadHeader,
		BadObjectHeader(U64),
		BadStartxref,
		BadStreamFraming(U64),
		BadStreamLength(U64),
		BadToken(U64),
		BadXrefDictionary,
		BadXrefEntry(U64),
		BadXrefFraming,
		DanglingReference(U64),
		KeysOutOfOrder(U64),
		RootNotCatalog,
		TooShort,
		UnbalancedObject(U64),
	]

	## Accept a document only if it is a structurally valid file under the
	## grammar the emitter actually writes. A typed failure is returned rather
	## than a bare `False` so a fuzz crash message can name the defect.
	check : List(U8) -> Try({}, Failure)
	check = |bytes| inspect_document(bytes)

	## The boolean form, for callers that only need the verdict.
	accepts : List(U8) -> Bool
	accepts = |bytes| match inspect_document(bytes) {
		Err(_) => Bool.False
		Ok(_) => Bool.True
	}
}

## `%PDF-2.0\n` and the binary comment marker, exactly fifteen bytes, which is
## why object one always begins at offset fifteen.
header_bytes : List(U8)
header_bytes = [37, 80, 68, 70, 45, 50, 46, 48, 10, 37, 226, 227, 207, 211, 10]

eof_bytes : List(U8)
eof_bytes = Str.to_utf8("%%EOF\n")

startxref_bytes : List(U8)
startxref_bytes = Str.to_utf8("startxref\n")

## An object header ends with a newline rather than a space, and objects are
## contiguous: object `n + 1` begins exactly where object `n`'s `\nendobj\n`
## ends, with no padding between them.
object_header_bytes : List(U8)
object_header_bytes = Str.to_utf8(" 0 obj\n")

end_object_bytes : List(U8)
end_object_bytes = Str.to_utf8("\nendobj\n")

stream_keyword_bytes : List(U8)
stream_keyword_bytes = Str.to_utf8("\nstream\n")

end_stream_bytes : List(U8)
end_stream_bytes = Str.to_utf8("\nendstream\nendobj\n")

## The cross-reference dictionary is written from a fixed sequence of writers
## with no conditional parts, so its canonical shape can be spelled out
## verbatim and matched in one pass.
xref_prefix_bytes : List(U8)
xref_prefix_bytes = Str.to_utf8("<< /ID [<")

xref_id_gap_bytes : List(U8)
xref_id_gap_bytes = Str.to_utf8("> <")

xref_index_bytes : List(U8)
xref_index_bytes = Str.to_utf8(">] /Index [0 ")

xref_length_bytes : List(U8)
xref_length_bytes = Str.to_utf8("] /Length ")

xref_root_bytes : List(U8)
xref_root_bytes = Str.to_utf8(" /Root ")

xref_size_bytes : List(U8)
xref_size_bytes = Str.to_utf8(" 0 R /Size ")

xref_suffix_bytes : List(U8)
xref_suffix_bytes = Str.to_utf8(" /Type /XRef /W [1 8 2] >>")

true_bytes : List(U8)
true_bytes = Str.to_utf8("true")

false_bytes : List(U8)
false_bytes = Str.to_utf8("false")

null_bytes : List(U8)
null_bytes = Str.to_utf8("null")

flate_decode_bytes : List(U8)
flate_decode_bytes = Str.to_utf8("FlateDecode")

dct_decode_bytes : List(U8)
dct_decode_bytes = Str.to_utf8("DCTDecode")

length_key_bytes : List(U8)
length_key_bytes = Str.to_utf8("Length")

filter_key_bytes : List(U8)
filter_key_bytes = Str.to_utf8("Filter")

type_key_bytes : List(U8)
type_key_bytes = Str.to_utf8("Type")

catalog_bytes : List(U8)
catalog_bytes = Str.to_utf8("Catalog")

## `/W [1 8 2]` is hardcoded by the emitter, so every cross-reference entry is
## one type byte, an eight-byte big-endian offset, and a two-byte big-endian
## generation.
entry_width : U64
entry_width = 11

Xref : { end : U64, length : U64, root : U64, size : U64 }

inspect_document : List(U8) -> Try({}, StructureOracle.Failure)
inspect_document = |bytes| {
	total = bytes.len()

	## Tier one starts with framing, which needs no tokenizer at all: the header
	## is fixed, and `%%EOF\n` is the last six bytes with nothing after it.
	if total < 21 {
		return Err(TooShort)
	}
	if bytes.sublist({ start: 0, len: 15 }) != header_bytes {
		return Err(BadHeader)
	}
	if bytes.sublist({ start: total - 6, len: 6 }) != eof_bytes {
		return Err(BadEndOfFile)
	}

	startxref = read_startxref(bytes)?
	header = read_object_header(bytes, startxref.xref_offset, total) ? |_| BadXrefFraming
	if header.number == 0 {
		return Err(BadXrefFraming)
	}
	xref_object = header.number

	dictionary = read_xref_dictionary(bytes, header.body, total)?
	if dictionary.size != xref_object + 1 or dictionary.length != dictionary.size * entry_width {
		return Err(BadXrefDictionary)
	}

	## The cross-reference stream is the one stream with a direct `/Length`, and
	## its payload is raw big-endian binary with no filter and no predictor,
	## which is what makes reading it here tractable at all.
	if !matches_at(bytes, dictionary.end, stream_keyword_bytes) {
		return Err(BadXrefFraming)
	}
	payload_start = dictionary.end + stream_keyword_bytes.len()
	if dictionary.length > total or payload_start + dictionary.length + end_stream_bytes.len() != startxref.keyword {
		return Err(BadXrefFraming)
	}
	if !matches_at(bytes, payload_start + dictionary.length, end_stream_bytes) {
		return Err(BadXrefFraming)
	}

	offsets = read_entries(bytes, payload_start, dictionary.size, total)?
	if list_at(offsets, 1) != 15 or list_at(offsets, xref_object) != startxref.xref_offset {
		return Err(BadXrefEntry(0))
	}

	## The single most valuable check here: every recorded offset must land on
	## the header of exactly the object it claims to describe, so any offset
	## drift or object-numbering mismatch dies on the spot.
	var $number = 1
	while $number < dictionary.size {
		object_header = read_object_header(bytes, list_at(offsets, $number), total) ? |_| BadObjectHeader($number)
		if object_header.number != $number {
			return Err(BadObjectHeader($number))
		}
		if $number + 1 < dictionary.size and !ends_at(bytes, list_at(offsets, $number + 1), end_object_bytes) {
			return Err(BadContiguity($number))
		}
		$number = $number + 1
	}

	if dictionary.root == 0 or dictionary.root >= xref_object {
		return Err(RootNotCatalog)
	}

	inspect_objects(bytes, offsets, dictionary, xref_object)
}

## Read the trailing `startxref\n<offset>\n%%EOF\n` backwards. Backwards is the
## only safe direction, because a forward search for the same bytes could match
## inside a stream payload.
read_startxref : List(U8) -> Try({ keyword : U64, xref_offset : U64 }, StructureOracle.Failure)
read_startxref = |bytes| {
	total = bytes.len()
	if list_at(bytes, total - 7) != 10 {
		return Err(BadStartxref)
	}
	var $digits = total - 7
	while $digits > 0 and is_digit(list_at(bytes, $digits - 1)) {
		$digits = $digits - 1
	}
	if $digits == total - 7 or $digits < startxref_bytes.len() {
		return Err(BadStartxref)
	}
	keyword = $digits - startxref_bytes.len()
	if !matches_at(bytes, keyword, startxref_bytes) {
		return Err(BadStartxref)
	}
	xref_offset = read_decimal(bytes, $digits, total - 7) ? |_| BadStartxref
	if xref_offset < 15 or xref_offset >= keyword {
		return Err(BadStartxref)
	}
	Ok({ keyword, xref_offset })
}

## Demand the exact canonical cross-reference dictionary:
##
##     << /ID [<64 hex> <64 hex>] /Index [0 SIZE] /Length <int> /Root <n> 0 R
##        /Size SIZE /Type /XRef /W [1 8 2] >>
##
## Checking the whole shape at once is the cheapest way to catch a miscounted
## object family. A plan that appends objects without moving the
## cross-reference object shows up here as a `/Size` that no longer agrees with
## the object number, long before any renderer would notice.
read_xref_dictionary : List(U8), U64, U64 -> Try(Xref, StructureOracle.Failure)
read_xref_dictionary = |bytes, from, total| {
	first_id = expect_bytes(bytes, from, xref_prefix_bytes) ? |_| BadXrefDictionary
	after_first_id = expect_hex_digits(bytes, first_id, 64) ? |_| BadXrefDictionary
	second_id = expect_bytes(bytes, after_first_id, xref_id_gap_bytes) ? |_| BadXrefDictionary
	after_second_id = expect_hex_digits(bytes, second_id, 64) ? |_| BadXrefDictionary

	## Both halves of `/ID` stay the same digest until a document is updated in
	## place, and this emitter never writes an incremental update.
	if bytes.sublist({ start: first_id, len: 64 }) != bytes.sublist({ start: second_id, len: 64 }) {
		return Err(BadXrefDictionary)
	}

	index_start = expect_bytes(bytes, after_second_id, xref_index_bytes) ? |_| BadXrefDictionary
	index_size = read_unsigned(bytes, index_start, total) ? |_| BadXrefDictionary
	length_start = expect_bytes(bytes, index_size.end, xref_length_bytes) ? |_| BadXrefDictionary
	length = read_unsigned(bytes, length_start, total) ? |_| BadXrefDictionary
	root_start = expect_bytes(bytes, length.end, xref_root_bytes) ? |_| BadXrefDictionary
	root = read_unsigned(bytes, root_start, total) ? |_| BadXrefDictionary
	size_start = expect_bytes(bytes, root.end, xref_size_bytes) ? |_| BadXrefDictionary
	size = read_unsigned(bytes, size_start, total) ? |_| BadXrefDictionary
	dictionary_end = expect_bytes(bytes, size.end, xref_suffix_bytes) ? |_| BadXrefDictionary

	## `/Index [0 SIZE]` is what makes the subsection contiguous, so a mismatch
	## means the recorded entries do not describe objects zero upwards.
	if index_size.value != size.value {
		return Err(BadXrefDictionary)
	}
	Ok({ end: dictionary_end, length: length.value, root: root.value, size: size.value })
}

## Decode the raw eleven-byte entries into a dense offset table. Entry zero is
## the free head, every other entry is an in-use object at generation zero, and
## a type-two compressed entry never occurs because this emitter writes no
## object streams.
read_entries : List(U8), U64, U64, U64 -> Try(List(U64), StructureOracle.Failure)
read_entries = |bytes, payload_start, size, total| {
	var $offsets = List.with_capacity(size)
	var $previous = 0
	var $number = 0
	while $number < size {
		base = payload_start + $number * entry_width
		kind = list_at(bytes, base)
		offset = read_big_endian(bytes, base + 1, 8)
		generation = read_big_endian(bytes, base + 9, 2)
		if $number == 0 {
			if kind != 0 or offset != 0 or generation != 65535 {
				return Err(BadXrefEntry(0))
			}
			$offsets = $offsets.append(0)
		} else {
			if kind != 1 or generation != 0 or offset >= total or offset <= $previous {
				return Err(BadXrefEntry($number))
			}
			$previous = offset
			$offsets = $offsets.append(offset)
		}
		$number = $number + 1
	}
	Ok($offsets)
}

## Tier two walks each stored object between its recorded offsets. The offsets
## give exact boundaries, so the dictionary region and the payload region are
## known separately and the payload is never tokenized.
inspect_objects : List(U8), List(U64), Xref, U64 -> Try({}, StructureOracle.Failure)
inspect_objects = |bytes, offsets, dictionary, xref_object| {
	var $root_seen = Bool.False
	var $number = 1
	while $number < xref_object {
		start = list_at(offsets, $number)
		end = list_at(offsets, $number + 1)
		header = read_object_header(bytes, start, end) ? |_| BadObjectHeader($number)
		marker = find_bytes(bytes, header.body, end, stream_keyword_bytes)
		body_end = match marker {
			Found(position) => position
			Missing => end - end_object_bytes.len()
		}
		tokens = tokenize(bytes, header.body, body_end, $number)?
		top_keys = walk_structure(bytes, tokens, $number, dictionary.size)?

		match marker {
			Missing => {}
			Found(position) => {
				payload_start = position + stream_keyword_bytes.len()
				payload_length = read_stream_length(bytes, offsets, tokens, top_keys, $number, xref_object)?
				if payload_length > bytes.len() or payload_start + payload_length + end_stream_bytes.len() != end {
					return Err(BadStreamFraming($number))
				}
				if !matches_at(bytes, payload_start + payload_length, end_stream_bytes) {
					return Err(BadStreamFraming($number))
				}
				check_filter(bytes, tokens, top_keys, payload_start, payload_length, $number)?
			}
		}

		if $number == dictionary.root {
			match top_key_value(bytes, tokens, top_keys, type_key_bytes) {
				Missing => return Err(RootNotCatalog)
				Found(token) => {
					if token.kind != NameToken or !region_equals(bytes, token.start, token.len, catalog_bytes) {
						return Err(RootNotCatalog)
					}
					$root_seen = Bool.True
				}
			}
		}

		$number = $number + 1
	}
	if !$root_seen {
		return Err(RootNotCatalog)
	}
	Ok({})
}

## Every stream except the cross-reference stream carries an indirect
## `/Length m 0 R`, and sealing requires `m` to be the very next object, whose
## whole body is one bare decimal integer. Resolving the length that way and
## then requiring it to land exactly on `\nendstream\nendobj\n` is what ties a
## declared length to the real payload extent.
read_stream_length : List(U8), List(U64), List(Token), List(TopKey), U64, U64 -> Try(U64, StructureOracle.Failure)
read_stream_length = |bytes, offsets, tokens, top_keys, number, xref_object| {
	index = match top_key_index(bytes, top_keys, length_key_bytes) {
		Missing => return Err(BadStreamLength(number))
		Found(value) => value
	}
	if !is_reference(tokens, index) {
		return Err(BadStreamLength(number))
	}
	length_object = list_at(tokens, index).value
	if length_object != number + 1 or length_object >= xref_object {
		return Err(BadStreamLength(number))
	}
	start = list_at(offsets, length_object)
	end = list_at(offsets, length_object + 1)
	header = read_object_header(bytes, start, end) ? |_| BadStreamLength(number)
	if !ends_at(bytes, end, end_object_bytes) {
		return Err(BadStreamLength(number))
	}
	declared = read_decimal(bytes, header.body, end - end_object_bytes.len()) ? |_| BadStreamLength(number)
	Ok(declared)
}

## A filtered payload announces itself in its own first bytes, so the declared
## filter and the payload have to agree. An absent `/Filter` means the payload
## is stored unchanged, which is how XMP metadata and ICC profiles are written,
## and there is nothing to assert about those bytes from out here.
check_filter : List(U8), List(Token), List(TopKey), U64, U64, U64 -> Try({}, StructureOracle.Failure)
check_filter = |bytes, tokens, top_keys, payload_start, payload_length, number| match top_key_value(bytes, tokens, top_keys, filter_key_bytes) {
	Missing => Ok({})
	Found(token) => {
		if token.kind != NameToken {
			return Err(BadFilter(number))
		}
		if region_equals(bytes, token.start, token.len, flate_decode_bytes) {
			if payload_length < 2 or list_at(bytes, payload_start) != 0x78 or list_at(bytes, payload_start + 1) != 0x9c {
				return Err(BadFilter(number))
			}
			Ok({})
		} else if region_equals(bytes, token.start, token.len, dct_decode_bytes) {
			if payload_length < 4 or
				list_at(bytes, payload_start) != 0xff or
					list_at(bytes, payload_start + 1) != 0xd8 or
						list_at(bytes, payload_start + payload_length - 2) != 0xff or
							list_at(bytes, payload_start + payload_length - 1) != 0xd9 {
				return Err(BadFilter(number))
			}
			Ok({})
		} else {
			Err(BadFilter(number))
		}
	}
}

## The emitted grammar is far smaller than real PDF: single-space separation, no
## literal `( )` strings, no comments inside objects, and a newline only at
## framing positions. Tokenizing exactly that grammar and rejecting everything
## else makes the tokenizer itself a canonical-output check.
Kind : [ArrayClose, ArrayOpen, DictClose, DictOpen, FalseToken, HexToken, IntegerToken, NameToken, NullToken, NumberToken, ReferenceToken, TrueToken]

Token : { kind : Kind, len : U64, start : U64, value : U64 }

TopKey : { key_len : U64, key_start : U64, value_index : U64 }

tokenize : List(U8), U64, U64, U64 -> Try(List(Token), StructureOracle.Failure)
tokenize = |bytes, from, to, number| {
	if to < from or to > bytes.len() {
		return Err(BadToken(number))
	}
	var $tokens = List.with_capacity(32)
	var $index = from
	while $index < to {
		byte = list_at(bytes, $index)
		if byte == 32 {
			$index = $index + 1
		} else if byte == 60 {

			## A dictionary opener and a hex string are told apart by peeking one
			## byte past the `<`.
			if $index + 1 < to and list_at(bytes, $index + 1) == 60 {
				$tokens = $tokens.append({ kind: DictOpen, len: 0, start: $index, value: 0 })
				$index = $index + 2
			} else {
				var $scan = $index + 1
				while $scan < to and is_hex_digit(list_at(bytes, $scan)) {
					$scan = $scan + 1
				}
				digits = $scan - $index - 1
				if $scan >= to or list_at(bytes, $scan) != 62 or digits % 2 != 0 {
					return Err(BadToken(number))
				}
				$tokens = $tokens.append({ kind: HexToken, len: digits, start: $index + 1, value: 0 })
				$index = $scan + 1
			}
		} else if byte == 62 {
			if $index + 1 >= to or list_at(bytes, $index + 1) != 62 {
				return Err(BadToken(number))
			}
			$tokens = $tokens.append({ kind: DictClose, len: 0, start: $index, value: 0 })
			$index = $index + 2
		} else if byte == 91 {
			$tokens = $tokens.append({ kind: ArrayOpen, len: 0, start: $index, value: 0 })
			$index = $index + 1
		} else if byte == 93 {
			$tokens = $tokens.append({ kind: ArrayClose, len: 0, start: $index, value: 0 })
			$index = $index + 1
		} else if byte == 47 {
			var $scan = $index + 1
			while $scan < to and is_regular(list_at(bytes, $scan)) {
				$scan = $scan + 1
			}
			$tokens = $tokens.append({ kind: NameToken, len: $scan - $index - 1, start: $index + 1, value: 0 })
			$index = $scan
		} else if is_regular(byte) {
			var $scan = $index
			while $scan < to and is_regular(list_at(bytes, $scan)) {
				$scan = $scan + 1
			}
			$tokens = $tokens.append(classify(bytes, $index, $scan, number)?)
			$index = $scan
		} else {
			return Err(BadToken(number))
		}
	}
	Ok($tokens)
}

## Bare tokens are `true`, `false`, `null`, `R`, canonical unsigned integers,
## and signed or fractional numbers such as `-0.025`. Anything else is a token
## this emitter does not write.
classify : List(U8), U64, U64, U64 -> Try(Token, StructureOracle.Failure)
classify = |bytes, from, to, number| {
	length = to - from
	if length == 0 {
		return Err(BadToken(number))
	}
	if length == 4 and matches_at(bytes, from, true_bytes) {
		return Ok({ kind: TrueToken, len: length, start: from, value: 0 })
	}
	if length == 5 and matches_at(bytes, from, false_bytes) {
		return Ok({ kind: FalseToken, len: length, start: from, value: 0 })
	}
	if length == 4 and matches_at(bytes, from, null_bytes) {
		return Ok({ kind: NullToken, len: length, start: from, value: 0 })
	}
	if length == 1 and list_at(bytes, from) == 82 {
		return Ok({ kind: ReferenceToken, len: length, start: from, value: 0 })
	}
	negative = list_at(bytes, from) == 45
	var $cursor = if negative from + 1 else from
	whole_start = $cursor
	while $cursor < to and is_digit(list_at(bytes, $cursor)) {
		$cursor = $cursor + 1
	}
	if $cursor == whole_start {
		return Err(BadToken(number))
	}
	if $cursor == to {

		## Only a non-negative integer can take part in a reference, so a signed
		## whole number stays an ordinary number token.
		if negative {
			return Ok({ kind: NumberToken, len: length, start: from, value: 0 })
		}
		value = read_decimal(bytes, from, to) ? |_| BadToken(number)
		return Ok({ kind: IntegerToken, len: length, start: from, value })
	}
	if list_at(bytes, $cursor) != 46 {
		return Err(BadToken(number))
	}
	fraction_start = $cursor + 1
	$cursor = fraction_start
	while $cursor < to and is_digit(list_at(bytes, $cursor)) {
		$cursor = $cursor + 1
	}
	if $cursor != to or $cursor == fraction_start {
		return Err(BadToken(number))
	}
	Ok({ kind: NumberToken, len: length, start: from, value: 0 })
}

Frame : { expecting_key : Bool, has_key : Bool, is_dict : Bool, key_len : U64, key_start : U64 }

## Walk the token stream as a value grammar: dictionaries alternate key and
## value, arrays hold values, and `<int> 0 R` is one value rather than three
## tokens.
##
## Three properties fall out of the same walk. Brackets and dictionary markers
## must balance. Every reference must name an object the cross-reference stream
## actually records. And dictionary keys must be in strictly increasing
## unsigned-byte order at every nesting level, which nothing else in the
## repository checks today: it holds across every dictionary in every committed
## fixture, and it is the property a merge-order or planning-order defect would
## break first. Keys are compared as their raw emitted bytes, which is exact
## because the emitter writes no `#XX` escape in a key.
walk_structure : List(U8), List(Token), U64, U64 -> Try(List(TopKey), StructureOracle.Failure)
walk_structure = |bytes, tokens, number, size| {
	var $stack = []
	var $top_keys = []
	var $depth = 0
	var $index = 0
	while $index < tokens.len() {
		token = list_at(tokens, $index)
		awaiting_key = if $depth == 0 Bool.False else {
			frame = list_at($stack, $depth - 1)
			frame.is_dict and frame.expecting_key
		}
		if awaiting_key {
			frame = list_at($stack, $depth - 1)
			match token.kind {
				DictClose => {
					$depth = $depth - 1
					$stack = complete_value($stack, $depth)
					$index = $index + 1
				}
				NameToken => {
					if frame.has_key and compare_regions(bytes, frame.key_start, frame.key_len, token.start, token.len) != Less {
						return Err(KeysOutOfOrder(number))
					}
					if $depth == 1 {
						$top_keys = $top_keys.append({ key_len: token.len, key_start: token.start, value_index: $index + 1 })
					}
					$stack = list_put($stack, $depth - 1, { ..frame, expecting_key: Bool.False, has_key: Bool.True, key_len: token.len, key_start: token.start })
					$index = $index + 1
				}
				_ => return Err(UnbalancedObject(number))
			}
		} else {
			match token.kind {
				DictOpen => {
					$stack = push_frame($stack, $depth, { expecting_key: Bool.True, has_key: Bool.False, is_dict: Bool.True, key_len: 0, key_start: 0 })
					$depth = $depth + 1
					$index = $index + 1
				}
				ArrayOpen => {
					$stack = push_frame($stack, $depth, { expecting_key: Bool.False, has_key: Bool.False, is_dict: Bool.False, key_len: 0, key_start: 0 })
					$depth = $depth + 1
					$index = $index + 1
				}
				ArrayClose => {
					if $depth == 0 or list_at($stack, $depth - 1).is_dict {
						return Err(UnbalancedObject(number))
					}
					$depth = $depth - 1
					$stack = complete_value($stack, $depth)
					$index = $index + 1
				}

				## A dictionary that closes where a value belongs left a key
				## dangling, and a bare `R` outside a reference is a stray token.
				DictClose => return Err(UnbalancedObject(number))
				ReferenceToken => return Err(BadToken(number))
				IntegerToken => {
					if is_reference(tokens, $index) {
						if token.value == 0 or token.value >= size {
							return Err(DanglingReference(number))
						}
						$index = $index + 3
					} else {
						$index = $index + 1
					}
					$stack = complete_value($stack, $depth)
				}
				_ => {
					$index = $index + 1
					$stack = complete_value($stack, $depth)
				}
			}
		}
	}
	if $depth != 0 {
		return Err(UnbalancedObject(number))
	}
	Ok($top_keys)
}

## The frame stack is reused rather than truncated, so a nested object costs one
## allocation per depth ever reached rather than one per push.
push_frame : List(Frame), U64, Frame -> List(Frame)
push_frame = |stack, depth, frame| if depth < stack.len() list_put(stack, depth, frame) else stack.append(frame)

complete_value : List(Frame), U64 -> List(Frame)
complete_value = |stack, depth| if depth == 0 stack else {
	frame = list_at(stack, depth - 1)
	if frame.is_dict list_put(stack, depth - 1, { ..frame, expecting_key: Bool.True }) else stack
}

is_reference : List(Token), U64 -> Bool
is_reference = |tokens, index| {
	if index + 2 >= tokens.len() {
		return Bool.False
	}
	generation = list_at(tokens, index + 1)
	keyword = list_at(tokens, index + 2)
	list_at(tokens, index).kind == IntegerToken and
		generation.kind == IntegerToken and
			generation.value == 0 and
				keyword.kind == ReferenceToken
}

top_key_index : List(U8), List(TopKey), List(U8) -> [Found(U64), Missing]
top_key_index = |bytes, top_keys, name| {
	var $index = 0
	while $index < top_keys.len() {
		entry = list_at(top_keys, $index)
		if region_equals(bytes, entry.key_start, entry.key_len, name) {
			return Found(entry.value_index)
		}
		$index = $index + 1
	}
	Missing
}

top_key_value : List(U8), List(Token), List(TopKey), List(U8) -> [Found(Token), Missing]
top_key_value = |bytes, tokens, top_keys, name| match top_key_index(bytes, top_keys, name) {
	Missing => Missing
	Found(index) => if index < tokens.len() Found(list_at(tokens, index)) else Missing
}

read_object_header : List(U8), U64, U64 -> Try({ body : U64, number : U64 }, [Malformed])
read_object_header = |bytes, from, limit| {
	if from >= limit {
		return Err(Malformed)
	}
	var $cursor = from
	while $cursor < limit and is_digit(list_at(bytes, $cursor)) {
		$cursor = $cursor + 1
	}
	number = read_decimal(bytes, from, $cursor)?
	if !matches_at(bytes, $cursor, object_header_bytes) {
		return Err(Malformed)
	}
	Ok({ body: $cursor + object_header_bytes.len(), number })
}

read_unsigned : List(U8), U64, U64 -> Try({ end : U64, value : U64 }, [Malformed])
read_unsigned = |bytes, from, limit| {
	var $cursor = from
	while $cursor < limit and is_digit(list_at(bytes, $cursor)) {
		$cursor = $cursor + 1
	}
	value = read_decimal(bytes, from, $cursor)?
	Ok({ end: $cursor, value })
}

## Decimal integers the emitter writes are canonical: at least one digit, and a
## leading zero only when the value is zero itself. Rejecting a padded
## rendering is deliberate, because a stray leading zero is a formatting defect
## even where the value it encodes is right.
read_decimal : List(U8), U64, U64 -> Try(U64, [Malformed])
read_decimal = |bytes, from, to| {
	if to <= from or to - from > 19 {
		return Err(Malformed)
	}
	if to - from > 1 and list_at(bytes, from) == 48 {
		return Err(Malformed)
	}
	var $value = 0
	var $index = from
	while $index < to {
		digit = list_at(bytes, $index)
		if !is_digit(digit) {
			return Err(Malformed)
		}
		$value = $value * 10 + (digit - 48).to_u64()
		$index = $index + 1
	}
	Ok($value)
}

read_big_endian : List(U8), U64, U64 -> U64
read_big_endian = |bytes, from, width| {
	var $value = 0
	var $index = 0
	while $index < width {
		$value = $value * 256 + list_at(bytes, from + $index).to_u64()
		$index = $index + 1
	}
	$value
}

expect_bytes : List(U8), U64, List(U8) -> Try(U64, [Malformed])
expect_bytes = |bytes, from, needle| if matches_at(bytes, from, needle) Ok(from + needle.len()) else Err(Malformed)

expect_hex_digits : List(U8), U64, U64 -> Try(U64, [Malformed])
expect_hex_digits = |bytes, from, count| {
	if from + count > bytes.len() {
		return Err(Malformed)
	}
	var $index = 0
	while $index < count {
		if !is_hex_digit(list_at(bytes, from + $index)) {
			return Err(Malformed)
		}
		$index = $index + 1
	}
	Ok(from + count)
}

matches_at : List(U8), U64, List(U8) -> Bool
matches_at = |bytes, from, needle| {
	if from + needle.len() > bytes.len() {
		return Bool.False
	}
	var $index = 0
	while $index < needle.len() {
		if list_at(bytes, from + $index) != list_at(needle, $index) {
			return Bool.False
		}
		$index = $index + 1
	}
	Bool.True
}

ends_at : List(U8), U64, List(U8) -> Bool
ends_at = |bytes, at, needle| if at < needle.len() Bool.False else matches_at(bytes, at - needle.len(), needle)

## Scan for a marker inside a known non-payload window only. The dictionary of a
## stream object carries no newline, so the first `\nstream\n` at or after the
## object body is always the real one.
find_bytes : List(U8), U64, U64, List(U8) -> [Found(U64), Missing]
find_bytes = |bytes, from, to, needle| {
	if to < needle.len() {
		return Missing
	}
	var $index = from
	while $index + needle.len() <= to {
		if matches_at(bytes, $index, needle) {
			return Found($index)
		}
		$index = $index + 1
	}
	Missing
}

region_equals : List(U8), U64, U64, List(U8) -> Bool
region_equals = |bytes, start, len, needle| len == needle.len() and matches_at(bytes, start, needle)

compare_regions : List(U8), U64, U64, U64, U64 -> [Equal, Greater, Less]
compare_regions = |bytes, left_start, left_len, right_start, right_len| {
	shared = if left_len < right_len left_len else right_len
	var $index = 0
	while $index < shared {
		left = list_at(bytes, left_start + $index)
		right = list_at(bytes, right_start + $index)
		if left < right {
			return Less
		}
		if left > right {
			return Greater
		}
		$index = $index + 1
	}
	if left_len < right_len Less else if left_len > right_len Greater else Equal
}

is_digit : U8 -> Bool
is_digit = |byte| byte >= 48 and byte <= 57

is_hex_digit : U8 -> Bool
is_hex_digit = |byte| is_digit(byte) or (byte >= 65 and byte <= 70)

## A regular character is anything that is neither a delimiter nor whitespace,
## which is what ends a name or a bare token.
is_regular : U8 -> Bool
is_regular = |byte| {
	if byte <= 32 or byte == 127 {
		return Bool.False
	}
	byte != 37 and
		byte != 40 and
			byte != 41 and
				byte != 47 and
					byte != 60 and
						byte != 62 and
							byte != 91 and
								byte != 93 and
									byte != 123 and
										byte != 125
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense index"
	Ok(value) => value
}

list_put : List(a), U64, a -> List(a)
list_put = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense update"
	Ok(updated) => updated
}

## Corrupt one byte of a committed document, so each negative expect below says
## exactly which byte it moved.
corrupted : List(U8), U64 -> List(U8)
corrupted = |bytes, index| {
	byte = list_at(bytes, index)
	list_put(bytes, index, if byte == 48 49 else 48)
}

## The positive expects pin the oracle against real emitter output rather than a
## hand-written sample: a facade document with no visible content, a document
## whose content stream is deflated, and a document carrying a JPEG image and an
## unfiltered ICC profile. Committed snapshots are used rather than documents
## generated here so no part of the emitter runs at compile time;
## `fuzz/facade_structure.roc` generates documents at run time.
expect StructureOracle.check(blank_document) == Ok({})
expect StructureOracle.check(deflate_document) == Ok({})
expect StructureOracle.check(image_document) == Ok({})

## An oracle that never rejects is worthless, so these prove that it does.
## `scripts/check_pdf_structure.py --self-test` exists for the same reason.

## Moving the last digit of the `startxref` offset points it at bytes that are
## not the cross-reference object header.
expect StructureOracle.check(corrupted(blank_document, blank_document.len() - 8)) != Ok({})

## Dropping the final newline destroys the `%%EOF\n` marker.
expect StructureOracle.check(blank_document.sublist({ start: 0, len: blank_document.len() - 1 })) == Err(BadEndOfFile)

## Object one always starts at offset fifteen, so renumbering its header makes
## the recorded offset describe a different object than the one it indexes.
expect StructureOracle.check(corrupted(blank_document, 15)) == Err(BadObjectHeader(1))

## Corrupting the header, and the empty document, are both rejected before any
## parsing begins.
expect StructureOracle.check(corrupted(blank_document, 1)) == Err(BadHeader)
expect StructureOracle.check([]) == Err(TooShort)
