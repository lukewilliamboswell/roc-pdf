## Decoded examples and their mutations bypass generator bounds. Keep the
## original entropy-sized domain explicit before any document work begins.
InputBounds :: [].{
	Block : { items : List(Str), kind : U8, level : U8, text : Str }
	document : { blocks : List(Block), title : Str } -> Bool
	document = |{ blocks, title }| {
		if blocks.len() > 8 {
			return False
		}
		var $bytes = title.count_utf8_bytes()
		for block in blocks {
			if block.items.len() > 4 {
				return False
			}
			$bytes = $bytes + block.text.count_utf8_bytes()
			for item in block.items {
				$bytes = $bytes + item.count_utf8_bytes()
			}
		}
		$bytes <= 4096
	}
	navigation : { sections : List({ kind : U8, name : U8, uri : U8, words : Str }), text : Str } -> Bool
	navigation = |{ sections, text }| {
		var $bytes = text.count_utf8_bytes()
		for section in sections {
			$bytes = $bytes + section.words.count_utf8_bytes()
		}
		$bytes <= 4096
	}
}

expect InputBounds.document({ blocks: [], title: Str.repeat("x", 4096) })
expect !InputBounds.document({ blocks: [], title: Str.repeat("x", 4097) })
expect !InputBounds.document({ blocks: List.repeat({ items: [], kind: 2, level: 0, text: "" }, 9), title: "" })
expect !InputBounds.navigation({ sections: [{ kind: 0, name: 0, uri: 0, words: "x" }], text: Str.repeat("x", 4096) })
