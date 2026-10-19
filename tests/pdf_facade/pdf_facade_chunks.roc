app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "../platform/main.roc",
}

import pdf.Pdf

## The authored chunked facade drives the same sealed plan as the buffered
## facade, so the concatenated chunks are byte-identical by construction.
## The counters pin the deterministic plan-derived chunk sequence: count,
## largest chunk, an order-sensitive offset weight, and the identity bit.
## The second argument selects the compression choice, which preparation
## seals: the identity bit also requires the prepared buffered output to
## equal the one-shot output. The `smallest` snapshot is byte-identical to the
## file this fixture wrote before the choice existed.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	retention = match list_at(args, 1) {
		"share" => Pdf.ChunkRetention.ShareUnchangedResources
		"own" => Pdf.ChunkRetention.OwnChunks
		_ => crash "text-layout chunked facade retention mode is invalid"
	}
	compression = match list_at(args, 2) {
		"balanced" => Pdf.Compression.Balanced
		"fastest" => Pdf.Compression.Fastest
		"smallest" => Pdf.Compression.Smallest
		_ => crash "text-layout chunked facade compression choice is invalid"
	}
	document = Pdf.document({
		contents: [Pdf.paragraph("Café PDF generation in pure Roc.")],
		language: "en-AU",
		title: "text-layout public facade output",
	})
	options = Pdf.Options.{ chunk_retention: retention, compression }
	buffered = Pdf.to_bytes_with(document, options) ?? []
	prepared = match Pdf.prepare(document, options) {
		Err(_) => crash "text-layout chunked facade preparation failed"
		Ok(value) => value
	}
	prepared_buffered = Pdf.to_bytes_prepared(prepared) ?? []
	var $encoder = match Pdf.to_chunks_prepared(prepared, retention) {
		Err(_) => crash "text-layout chunked facade encoder failed"
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
	byte_identical = if ($bytes == buffered and prepared_buffered == buffered) 1 else 0
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
				crash "text-layout chunked facade chunk index invariant failed"
			}
		}
		$index = $index + 1
	}
	$out
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "text-layout chunked facade argument missing"
	Ok(value) => value
}
