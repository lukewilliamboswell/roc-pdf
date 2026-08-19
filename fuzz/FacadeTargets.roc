import pdf.Document
import pdf.Pdf

FacadeTargets :: [].{
	Block : { items : List(Str), kind : U8, level : U8, text : Str }
	Input : { blocks : List(Block), language : U8, title : Str }

	## Drive the public facade over generated typed documents and check the
	## enduring output contracts rather than a private stage:
	##
	## - identical explicit inputs produce identical bytes (core invariant 12),
	## - the buffered and chunked encoders are byte-identical because they drive
	##   one emission transition,
	## - the chunk retention policy changes allocation and copying only, never
	##   bytes,
	## - and a rejected document is rejected the same way every time, with no
	##   partial file emitted.
	facade_output : Input -> Bool
	facade_output = |input| {
		document = Pdf.document({
			contents: input.blocks.map(block_for),
			language: language_for(input.language),
			title: input.title,
		})
		shared = shared_options
		owned = owned_options

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
				drained(document, owned) == Some(first)
			}
			_ => False
		}
	}
}

shared_options : Pdf.Options
shared_options = Pdf.Options.with_chunk_retention(Pdf.Options.default, ShareUnchangedResources)

owned_options : Pdf.Options
owned_options = Pdf.Options.with_chunk_retention(Pdf.Options.default, OwnChunks)

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
