app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Pdf

## The authored chunked facade drives the same sealed plan as the buffered
## facade, so the concatenated chunks are byte-identical by construction.
## The counters pin the deterministic plan-derived chunk sequence: count,
## largest chunk, an order-sensitive offset weight, and the identity bit.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	retention = match list_at(args, 1) {
		"share" => Pdf.ChunkRetention.ShareUnchangedResources
		"own" => Pdf.ChunkRetention.OwnChunks
		_ => crash "Gate 3 chunked facade retention mode is invalid"
	}
	document = Pdf.document({
		contents: [Pdf.paragraph("Café PDF generation in pure Roc.")],
		language: "en-AU",
		title: "Gate 3 public facade output",
	})
	buffered = Pdf.to_bytes(document) ?? []
	options = Pdf.Options.with_chunk_retention(Pdf.Options.default, retention)
	var $encoder = match Pdf.to_chunks_with(document, options) {
		Err(_) => crash "Gate 3 chunked facade encoder failed"
		Ok(value) => value
	}
	var $bytes = []
	var $chunks = 0
	var $max_chunk_bytes = 0
	var $chunk_offset_weight = 0
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(chunk, next) => {
				$chunks = $chunks + 1
				if chunk.len() > $max_chunk_bytes {
					$max_chunk_bytes = chunk.len()
				}
				$chunk_offset_weight = $chunk_offset_weight + $chunks * chunk.len()
				$bytes = append_bytes($bytes, chunk)
				$encoder = next
			}
		}
	}
	byte_identical = if $bytes == buffered 1 else 0
	{ bytes: $bytes, work: [$chunks, $max_chunk_bytes, $chunk_offset_weight, byte_identical, $bytes.len()] }
}

append_bytes : List(U8), List(U8) -> List(U8)
append_bytes = |target, source| {
	length = source.len()
	var $out = List.reserve(target, length)
	var $index = 0
	while $index < length {
		match source.get($index) {
			Ok(byte) => {
				$out = $out.append(byte)
			}
			Err(OutOfBounds) => {
				crash "Gate 3 chunked facade chunk index invariant failed"
			}
		}
		$index = $index + 1
	}
	$out
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "Gate 3 chunked facade argument missing"
	Ok(value) => value
}
