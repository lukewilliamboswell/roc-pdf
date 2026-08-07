import Document
import KernelEmit
import KernelStructure

Gate3FacadeEvidence :: [].{
	normalize_builder : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	normalize_builder = |repetitions| normalize(repetitions, Builder)

	normalize_simple : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	normalize_simple = |repetitions| normalize(repetitions, Simple)
}

Authoring := [Builder, Simple]

normalize : U64, Authoring -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
normalize = |repetitions, authoring| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	document = match authoring {
		Builder => build_with_builder(repetitions)
		Simple => build_with_list(repetitions)
	}
	store = Document.normalize(document)
	work = inspect(store) ? |_| EvidenceFailure
	plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions + 3,
			store.blocks.len(),
			work.text_bytes,
			work.titles,
			work.headings,
			work.paragraphs,
			work.bullets,
			work.lists,
			bytes.len(),
		],
	})
}

build_with_list : U64 -> Document
build_with_list = |repetitions| {
	var $blocks = [Document.title("Report"), Document.heading(1, "Summary")]
	var $index = 0
	while $index < repetitions {
		$blocks = $blocks.append(Document.paragraph("Body"))
		$index = $index + 1
	}
	$blocks = $blocks.append(Document.bullets(["One", "Two"]))
	Document.from_blocks({ contents: $blocks, language: "en-AU", title: "Report" })
}

build_with_builder : U64 -> Document
build_with_builder = |repetitions| {
	var $builder = Document.builder({ language: "en-AU", title: "Report" })
		.add_title("Report")
		.add_heading(1, "Summary")
	$builder = $builder.add_paragraphs(List.repeat("Body", repetitions))
	$builder.add_bullets(["One", "Two"]).finish()
}

NormalizationWork := {
	bullets : U64,
	headings : U64,
	lists : U64,
	paragraphs : U64,
	text_bytes : U64,
	titles : U64,
}

inspect : Document.NormalizedAuthoring -> Try(NormalizationWork, [InvalidStore])
inspect = |store| {
	var $bullets = 0
	var $headings = 0
	var $lists = 0
	var $paragraphs = 0
	var $text_bytes = 0
	var $titles = 0
	var $next_list = 0
	var $expected_item = 0
	var $index = 0
	while $index < store.blocks.len() {
		block = list_at(store.blocks, $index)
		$text_bytes = $text_bytes + block.text.count_utf8_bytes()
		match block.kind {
			Bullet({ item, list }) => {
				if item == 0 {
					if list != $next_list {
						return Err(InvalidStore)
					}
					$lists = $lists + 1
					$next_list = $next_list + 1
					$expected_item = 0
				} else if list + 1 != $next_list {
					return Err(InvalidStore)
				}
				if item != $expected_item {
					return Err(InvalidStore)
				}
				$expected_item = $expected_item + 1
				$bullets = $bullets + 1
			}
			Heading(_) => {
				$headings = $headings + 1
			}
			PageArtifact(_) => return Err(InvalidStore)
			Paragraph => {
				$paragraphs = $paragraphs + 1
			}
			Title => {
				$titles = $titles + 1
			}
		}
		$index = $index + 1
	}
	Ok({ bullets: $bullets, headings: $headings, lists: $lists, paragraphs: $paragraphs, text_bytes: $text_bytes, titles: $titles })
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 facade evidence index escaped"
	}
	Ok(value) => value
}

expect {
	simple = Gate3FacadeEvidence.normalize_simple(2)?
	builder = Gate3FacadeEvidence.normalize_builder(2)?
	simple.work == [5, 6, 27, 1, 1, 2, 2, 1, 667] and builder.work == simple.work and builder.bytes == simple.bytes
}
