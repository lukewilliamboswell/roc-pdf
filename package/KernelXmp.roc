## Canonical XMP serialization from validated metadata facts. One policy
## produces one byte sequence for one set of facts:
##
## - The packet is UTF-8 with the standard `xpacket` frame, a UTF-8 byte order
##   mark inside the `begin` attribute, no padding, and `end="w"`.
## - Namespace declarations and properties follow the pinned
##   `Metadata.canonical.property_order` policy: ascending namespace URI, then
##   ascending local name. The XMP namespace URI orders before the Dublin Core
##   URI, so explicit timestamps precede `dc:language` and `dc:title`.
## - `dc:title` is an `rdf:Alt` with one `x-default` item; `dc:language` is an
##   `rdf:Bag` with the single validated document language.
## - Omitted timestamps omit their property elements and, when both are
##   omitted, the `xmlns:xmp` declaration; nothing emits empty elements.
## - Text content escapes exactly `&`, `<`, and `>`; validation has already
##   rejected scalars XML 1.0 cannot represent, and no other substitution or
##   whitespace policy applies.
## - Indentation is one tab per element depth with single newlines; the packet
##   carries no trailing newline. There are no XMP identifiers: deterministic
##   document identity remains the trailer `/ID` digest, which hashes the
##   sealed plan (including these metadata bytes) and therefore cannot itself
##   appear inside the packet.
##
## Validation already counted the title's escape substitutions, so the exact
## packet size is known before any byte is written; the packet is emitted once
## into an exactly reserved buffer and rejected against `max_xmp_bytes` before
## that allocation.
import KernelMetadata
import Metadata

KernelXmp :: [].{
	Error : [PacketTooLarge({ attempted : U64, limit : U64 })]

	Work : { packet_bytes : U64, properties : U64, title_escapes : U64 }

	Packet :: { bytes : List(U8), work : Work }.{
		build : KernelMetadata.Facts, U64 -> Try(Packet, Error)
		build = |facts, max_bytes| build_packet(facts, max_bytes)

		bytes : Packet -> List(U8)
		bytes = |packet| packet.bytes

		work : Packet -> Work
		work = |packet| packet.work
	}
}

build_packet : KernelMetadata.Facts, U64 -> Try(KernelXmp.Packet, KernelXmp.Error)
build_packet = |facts, max_bytes| {
	head = Str.to_utf8(head_open)
	bom = [239, 187, 191]
	head_rest = Str.to_utf8(head_close)
	xmp_namespace = Str.to_utf8(xmp_namespace_attribute)
	dc_namespace = Str.to_utf8(dc_namespace_attribute)
	description_end = Str.to_utf8(">\n")
	language_bytes = Str.to_utf8(facts.language)
	language_head = Str.to_utf8(language_open)
	language_tail = Str.to_utf8(language_close)
	title_bytes = Str.to_utf8(facts.title)
	title_head = Str.to_utf8(title_open)
	title_tail = Str.to_utf8(title_close)
	tail = Str.to_utf8(packet_tail)

	created = timestamp_segments(facts.created, "CreateDate")
	modified = timestamp_segments(facts.modified, "ModifyDate")
	timestamp_len = segment_length(created) + segment_length(modified)
	has_timestamps = timestamp_len > 0
	namespace_len = if has_timestamps xmp_namespace.len() else 0

	escapes = facts.title_escapes
	escape_count = escapes.amps + escapes.lts + escapes.gts
	escaped_title_len = title_bytes.len() + escapes.amps * 4 + escapes.lts * 3 + escapes.gts * 3

	total = head.len()
		+ bom.len()
		+ head_rest.len()
		+ namespace_len
		+ dc_namespace.len()
		+ description_end.len()
		+ timestamp_len
		+ language_head.len()
		+ language_bytes.len()
		+ language_tail.len()
		+ title_head.len()
		+ escaped_title_len
		+ title_tail.len()
		+ tail.len()

	if total > max_bytes {
		return Err(PacketTooLarge({ attempted: total, limit: max_bytes }))
	}

	var $out = List.reserve([], total)
	$out = $out.concat(head)
	$out = $out.concat(bom)
	$out = $out.concat(head_rest)
	if has_timestamps {
		$out = $out.concat(xmp_namespace)
	}
	$out = $out.concat(dc_namespace)
	$out = $out.concat(description_end)
	$out = append_segments($out, created)
	$out = append_segments($out, modified)
	$out = $out.concat(language_head)
	$out = $out.concat(language_bytes)
	$out = $out.concat(language_tail)
	$out = $out.concat(title_head)
	$out = append_escaped($out, title_bytes)
	$out = $out.concat(title_tail)
	$out = $out.concat(tail)

	if $out.len() != total {
		crash "canonical XMP length invariant failed"
	}

	properties = 2 + segment_count(created) + segment_count(modified)
	Ok(
		KernelXmp.Packet.{
			bytes: $out,
			work: { packet_bytes: total, properties, title_escapes: escape_count },
		},
	)
}

TimestampSegments : [NoTimestamp, Timestamp({ close : List(U8), open : List(U8), value : List(U8) })]

timestamp_segments : Metadata.TimestampInput, Str -> TimestampSegments
timestamp_segments = |input, local_name| match input {
	Omitted => NoTimestamp
	Explicit(value) => Timestamp({
		close: Str.to_utf8("</xmp:${local_name}>\n"),
		open: Str.to_utf8("\t\t\t<xmp:${local_name}>"),
		value: Str.to_utf8(value),
	})
}

segment_length : TimestampSegments -> U64
segment_length = |segments| match segments {
	NoTimestamp => 0
	Timestamp({ close, open, value }) => open.len() + value.len() + close.len()
}

segment_count : TimestampSegments -> U64
segment_count = |segments| match segments {
	NoTimestamp => 0
	Timestamp(_) => 1
}

append_segments : List(U8), TimestampSegments -> List(U8)
append_segments = |out, segments| match segments {
	NoTimestamp => out
	Timestamp({ close, open, value }) => out.concat(open).concat(value).concat(close)
}

## Escaped emission appends bytes into the exactly reserved buffer without
## per-escape allocations.
append_escaped : List(U8), List(U8) -> List(U8)
append_escaped = |out, bytes| {
	var $out = out
	var $index = 0
	while $index < bytes.len() {
		byte = list_at(bytes, $index)
		if byte == 0x26 {
			$out = $out.append(0x26).append(0x61).append(0x6D).append(0x70).append(0x3B)
		} else if byte == 0x3C {
			$out = $out.append(0x26).append(0x6C).append(0x74).append(0x3B)
		} else if byte == 0x3E {
			$out = $out.append(0x26).append(0x67).append(0x74).append(0x3B)
		} else {
			$out = $out.append(byte)
		}
		$index = $index + 1
	}
	$out
}

head_open : Str
head_open = "<?xpacket begin=\""

head_close : Str
head_close = "\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n\t<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n\t\t<rdf:Description rdf:about=\"\""

xmp_namespace_attribute : Str
xmp_namespace_attribute = " xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\""

dc_namespace_attribute : Str
dc_namespace_attribute = " xmlns:dc=\"http://purl.org/dc/elements/1.1/\""

language_open : Str
language_open = "\t\t\t<dc:language>\n\t\t\t\t<rdf:Bag>\n\t\t\t\t\t<rdf:li>"

language_close : Str
language_close = "</rdf:li>\n\t\t\t\t</rdf:Bag>\n\t\t\t</dc:language>\n"

title_open : Str
title_open = "\t\t\t<dc:title>\n\t\t\t\t<rdf:Alt>\n\t\t\t\t\t<rdf:li xml:lang=\"x-default\">"

title_close : Str
title_close = "</rdf:li>\n\t\t\t\t</rdf:Alt>\n\t\t\t</dc:title>\n"

packet_tail : Str
packet_tail = "\t\t</rdf:Description>\n\t</rdf:RDF>\n</x:xmpmeta>\n<?xpacket end=\"w\"?>"

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "canonical XMP index escaped"
	}
}

no_escapes : KernelMetadata.Escapes
no_escapes = { amps: 0, gts: 0, lts: 0 }

sample_facts : KernelMetadata.Facts
sample_facts = {
	created: Omitted,
	language: "en-AU",
	modified: Omitted,
	title: "Report",
	title_escapes: no_escapes,
}

## The canonical packet for the minimal fact set is pinned byte-for-byte,
## including the frame, the byte order mark, the namespace order, and the
## omission of the unused XMP timestamp namespace.
expect {
	packet = KernelXmp.Packet.build(sample_facts, 4096)?
	expected = Str.to_utf8("<?xpacket begin=\"")
		.concat([239, 187, 191])
		.concat(
			Str.to_utf8(
				"\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n\t<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n\t\t<rdf:Description rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n\t\t\t<dc:language>\n\t\t\t\t<rdf:Bag>\n\t\t\t\t\t<rdf:li>en-AU</rdf:li>\n\t\t\t\t</rdf:Bag>\n\t\t\t</dc:language>\n\t\t\t<dc:title>\n\t\t\t\t<rdf:Alt>\n\t\t\t\t\t<rdf:li xml:lang=\"x-default\">Report</rdf:li>\n\t\t\t\t</rdf:Alt>\n\t\t\t</dc:title>\n\t\t</rdf:Description>\n\t</rdf:RDF>\n</x:xmpmeta>\n<?xpacket end=\"w\"?>",
			),
		)

	KernelXmp.Packet.bytes(packet) == expected and KernelXmp.Packet.work(packet) == { packet_bytes: expected.len(), properties: 2, title_escapes: 0 }
}

## Explicit timestamps add the XMP namespace declaration and order before the
## Dublin Core properties because the XMP namespace URI sorts first.
expect {
	facts = { ..sample_facts, created: Explicit("2026-01-02T03:04:05Z"), modified: Explicit("2026-01-02T03:04:06Z") }
	packet = KernelXmp.Packet.build(facts, 4096)?
	text = match Str.from_utf8(KernelXmp.Packet.bytes(packet)) {
		Ok(value) => value
		Err(_) => {
			crash "canonical XMP produced invalid UTF-8"
		}
	}

	Str.contains(text, " xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">")
		and Str.contains(text, "\t\t\t<xmp:CreateDate>2026-01-02T03:04:05Z</xmp:CreateDate>\n\t\t\t<xmp:ModifyDate>2026-01-02T03:04:06Z</xmp:ModifyDate>\n\t\t\t<dc:language>")
			and KernelXmp.Packet.work(packet).properties == 4
}

## One explicit timestamp emits exactly its own property and no empty twin.
expect {
	facts = { ..sample_facts, modified: Explicit("2026-01-02T03:04:06Z") }
	packet = KernelXmp.Packet.build(facts, 4096)?
	text = match Str.from_utf8(KernelXmp.Packet.bytes(packet)) {
		Ok(value) => value
		Err(_) => {
			crash "canonical XMP produced invalid UTF-8"
		}
	}

	!Str.contains(text, "CreateDate") and Str.contains(text, "<xmp:ModifyDate>") and KernelXmp.Packet.work(packet).properties == 3
}

## Title escaping substitutes exactly the three XML metacharacters and the
## emitted length matches the escape counts recorded by validation.
expect {
	facts = { ..sample_facts, title: "R&D <plan> & more", title_escapes: { amps: 2, gts: 1, lts: 1 } }
	packet = KernelXmp.Packet.build(facts, 4096)?
	text = match Str.from_utf8(KernelXmp.Packet.bytes(packet)) {
		Ok(value) => value
		Err(_) => {
			crash "canonical XMP produced invalid UTF-8"
		}
	}

	Str.contains(text, ">R&amp;D &lt;plan&gt; &amp; more</rdf:li>") and KernelXmp.Packet.work(packet).title_escapes == 4
}

## Non-ASCII UTF-8 title scalars pass through unescaped as canonical UTF-8.
expect {
	facts = { ..sample_facts, title: "Übersicht — 概要" }
	packet = KernelXmp.Packet.build(facts, 4096)?
	text = match Str.from_utf8(KernelXmp.Packet.bytes(packet)) {
		Ok(value) => value
		Err(_) => {
			crash "canonical XMP produced invalid UTF-8"
		}
	}

	Str.contains(text, ">Übersicht — 概要</rdf:li>")
}

## Identical facts serialize to identical bytes.
expect {
	first = KernelXmp.Packet.build(sample_facts, 4096)?
	second = KernelXmp.Packet.build(sample_facts, 4096)?

	KernelXmp.Packet.bytes(first) == KernelXmp.Packet.bytes(second)
}

## The packet budget rejects before the output allocation with exact facts.
expect {
	small = KernelXmp.Packet.build(sample_facts, 4096)?
	limit = KernelXmp.Packet.work(small).packet_bytes - 1
	match KernelXmp.Packet.build(sample_facts, limit) {
		Err(PacketTooLarge({ attempted, limit: reported })) => attempted == limit + 1 and reported == limit
		_ => False
	}
}
