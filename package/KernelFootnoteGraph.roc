import Document

## Resolve names before measurement. Dense targets retain one binding per
## authored citation. Only the earliest citation enters the layout index.
KernelFootnoteGraph :: [].{
	Error : { block : U64, inline : [AtInline(U64), NoInline], feature : Str, message : Str }

	resolve : Document.NormalizedAuthoring -> Try(Document.NormalizedAuthoring, Error)
	resolve = |document| {
		notes = document.footnotes
		citations = document.footnote_citations
		if notes.is_empty() and citations.is_empty() {
			return Ok(document)
		}
		if notes.len() > 128 {
			return Err(for_note(list_at(notes, 128), "count", "A document can declare at most 128 footnotes."))
		}
		if citations.len() > 512 {
			return Err(for_citation(list_at(citations, 512), "citation_count", "A document can cite footnotes at most 512 times."))
		}
		templates = match document.templates {
			NoTemplates => False
			Templates(_) => True
		}
		if templates or !document.page_scopes.is_empty() or !document.tables.is_empty() or !document.callouts.is_empty()
			or !document.customs.is_empty() or !document.page_references.is_empty() or !document.sources.is_empty() or !document.decorations.is_empty() {
			block = if (notes.is_empty()) list_at(citations, 0).block else list_at(notes, 0).block
			return Err({ block, inline: NoInline, feature: "flow", message: "Footnotes require ordinary single-column flow without page templates, tables, callouts, custom blocks, source blocks, decorations, or symbolic page references." })
		}
		if citations.is_empty() {
			return Err(for_note(list_at(notes, 0), "uncited", "Every declared footnote needs at least one citation."))
		}
		if notes.is_empty() {
			return Err(for_citation(list_at(citations, 0), "missing", "Declare a footnote for this citation."))
		}
		body_blocks = list_at(notes, 0).block
		var $index = 0
		for note in notes {
			if note.parent != 0 or note.block != body_blocks + $index or note.block >= document.blocks.len() {
				return Err(for_note(note, "placement", "Declare footnotes together at the end of the document."))
			}
			if !valid_id(note.id) {
				return Err(for_note(note, "id", "Use 1–48 ASCII letters, digits, underscores or hyphens as the footnote ID."))
			}
			if note.label.trim().is_empty() or note.label.count_utf8_bytes() > 128
				or note.body.trim().is_empty() or note.body.count_utf8_bytes() > 2048 {
				return Err(for_note(note, "text", "Supply a visible label of up to 128 UTF-8 bytes and note text of up to 2,048 UTF-8 bytes."))
			}
			$index = $index + 1
		}
		if body_blocks + notes.len() != document.blocks.len() or document.page_breaks.any(|item| item.block >= body_blocks) {
			return Err(for_note(list_at(notes, 0), "placement", "Declare footnotes together at the end of the document."))
		}
		var $keys = List.with_capacity(notes.len())
		$index = 0
		for note in notes {
			$keys = $keys.append({ bytes: Str.to_utf8(note.id), id: $index })
			$index = $index + 1
		}
		sorted = $keys.sort_with(
			|a, b| match key_order(a.bytes, b.bytes) {
				Same => if (a.id < b.id) Before else if (a.id > b.id) After else Same
				order => order
			},
		)
		$index = 1
		while $index < sorted.len() {
			if list_at(sorted, $index - 1).bytes == list_at(sorted, $index).bytes {
				return Err(for_note(list_at(notes, list_at(sorted, $index).id), "duplicate", "Each footnote needs a distinct ID."))
			}
			$index = $index + 1
		}
		var $first = List.repeat(False, notes.len())
		var $placements = List.with_capacity(notes.len())
		var $targets = List.with_capacity(citations.len())
		$index = 0
		for citation in citations {
			text = Str.to_utf8(citation.text)
			if !valid_id(citation.id) or text.is_empty() or text.len() > 32 or text.any(|byte| byte <= 32 or byte > 126) {
				return Err(for_citation(citation, "marker", "Supply a valid note ID and a 1–32 character printable ASCII marker without spaces."))
			}
			target = lookup(sorted, Str.to_utf8(citation.id)) ? |_| for_citation(citation, "missing", "Declare a footnote for this citation.")
			if !list_at($first, target) {
				$first = list_set($first, target, True)
				$placements = $placements.append({ definition: target, citation: $index })
			}
			$targets = $targets.append(target)
			$index = $index + 1
		}
		if $placements.len() < notes.len() {
			$index = 0
			while list_at($first, $index) {
				$index = $index + 1
			}
			return Err(for_note(list_at(notes, $index), "uncited", "Every declared footnote needs at least one citation."))
		}
		Ok({ ..document, footnote_targets: $targets, footnote_placements: $placements })
	}
}

for_note : Document.NormalizedFootnote, Str, Str -> KernelFootnoteGraph.Error
for_note = |note, feature, message| { block: note.block, inline: NoInline, feature, message }

for_citation : Document.NormalizedCitation, Str, Str -> KernelFootnoteGraph.Error
for_citation = |citation, feature, message| { block: citation.block, inline: AtInline(citation.inline), feature, message }

valid_id : Str -> Bool
valid_id = |key| {
	bytes = Str.to_utf8(key)
	!bytes.is_empty() and bytes.len() <= 48 and bytes.all(|byte| (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 45 or byte == 95)
}

Key : { bytes : List(U8), id : U64 }

lookup : List(Key), List(U8) -> Try(U64, {})
lookup = |keys, bytes| {
	var $low = 0
	var $high = keys.len()
	while $low < $high {
		middle = $low + ($high - $low) // 2
		key = list_at(keys, middle)
		match key_order(key.bytes, bytes) {
			Before => {
				$low = middle + 1
			}
			After => {
				$high = middle
			}
			Same => return Ok(key.id)
		}
	}
	Err({})
}

key_order : List(U8), List(U8) -> [Before, Same, After]
key_order = |left, right| {
	common = U64.min(left.len(), right.len())
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
list_at = |items, index| items.get(index) ?? crash "footnote graph index"

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| items.set(index, value) ?? crash "footnote graph index"
