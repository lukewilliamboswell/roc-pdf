import pdf.Document
import pdf.Pdf

FacadeTargets :: [].{
	Block : { items : List(Str), kind : U8, level : U8, text : Str }
	Input : { blocks : List(Block), compression : U8, language : U8, title : Str }

	## Drive the public facade over generated typed documents and check the
	## enduring output contracts rather than a private stage:
	##
	## - identical explicit inputs produce identical bytes (core invariant 12),
	## - the buffered and chunked encoders are byte-identical because they drive
	##   one emission transition,
	## - the chunk retention policy changes allocation and copying only, never
	##   bytes,
	## - every compression choice is sealed by preparation, so the prepared
	##   buffered and chunked paths agree with the one-shot paths under the
	##   generated choice,
	## - and a rejected document is rejected the same way every time, with no
	##   partial file emitted.
	facade_output : Input -> Bool
	facade_output = |input| {
		document = Pdf.document({
			contents: input.blocks.map(block_for),
			language: language_for(input.language),
			title: input.title,
		})
		compression = compression_for(input.compression)
		shared = Pdf.Options.{ chunk_retention: ShareUnchangedResources, compression }
		owned = Pdf.Options.{ chunk_retention: OwnChunks, compression }

		match (Pdf.to_bytes_with(document, shared), Pdf.to_bytes_with(document, shared)) {

			## Transactional failure is an ordinary outcome, but it must repeat.
			(Err(_), Err(_)) => match Pdf.to_chunks_with(document, shared) {
				Err(_) => True
				Ok(_) => False
			}
			(Ok(first), Ok(second)) => {
				if first != second {
					return False
				}
				if drained(document, shared) != Some(first) {
					return False
				}
				if prepared_output(document, owned) != Some(first) {
					return False
				}
				drained(document, owned) == Some(first)
			}
			_ => False
		}
	}
}

compression_for : U8 -> Pdf.Compression
compression_for = |choice| match choice % 3 {
	0 => Balanced
	1 => Fastest
	_ => Smallest
}

## One preparation drives both prepared emission paths; they must agree with
## each other and, through the caller, with the one-shot output.
prepared_output : Document, Pdf.Options -> [None, Some(List(U8))]
prepared_output = |document, options| match Pdf.prepare(document, options) {
	Err(_) => None
	Ok(prepared) => match (Pdf.to_bytes_prepared(prepared), Pdf.to_chunks_prepared(prepared, options.chunk_retention)) {
		(Ok(buffered), Ok(encoder)) => if (drain(encoder) == buffered) Some(buffered) else None
		_ => None
	}
}

## Sealing already succeeded for the buffered path, so a chunked failure here is
## a disagreement between two entrypoints over one sealed plan.
drained : Document, Pdf.Options -> [None, Some(List(U8))]
drained = |document, options| match Pdf.to_chunks_with(document, options) {
	Err(_) => None
	Ok(encoder) => Some(drain(encoder))
}

drain : Pdf.Encode -> List(U8)
drain = |encoder| {
	var $encoder = encoder
	var $bytes = []
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(chunk, next) => {
				$bytes = append_all($bytes, chunk)
				$encoder = next
			}
		}
	}
	$bytes
}

block_for : FacadeTargets.Block -> Document.Block
block_for = |block| match block.kind % 4 {
	0 => Pdf.title(block.text)
	1 => Pdf.heading(block.level % 6 + 1, block.text)
	2 => Pdf.paragraph(block.text)
	_ => Pdf.bullets(block.items)
}

## A closed set of valid tags keeps most generated documents past metadata
## validation, so the generator spends its budget on content and output rather
## than on rediscovering that a malformed language tag is rejected.
language_for : U8 -> Str
language_for = |choice| match choice % 4 {
	0 => "en-AU"
	1 => "en-GB"
	2 => "de-DE"
	_ => "ja-JP"
}

append_all : List(a), List(a) -> List(a)
append_all = |left, right| {
	var $result = left
	var $index = 0
	while $index < right.len() {
		$result = $result.append(list_at(right, $index))
		$index = $index + 1
	}
	$result
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense index"
	Ok(value) => value
}
