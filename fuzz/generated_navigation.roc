app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/main.roc",
}

import fuzz.Fuzz
import pdf.Document
import pdf.Layout
import pdf.Pdf

Input := { count : U8, depth : U8, mode : U8, width : U8 }.{
	parser_for : _
	encoder_for : _
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { count: Fuzz.u8, depth: Fuzz.u8, mode: Fuzz.u8, width: Fuzz.u8 }.Fuzz
}

target = Fuzz.suite([
	Fuzz.target({
		name: "roc-pdf-generated-navigation",
		examples: [
			Fuzz.example({ name: "scoped-depth-and-shared-destination", revision: "1", make: || Input.{ count: 5, depth: 0, mode: 0, width: 33 } }),
			Fuzz.example({ name: "extra-level-and-exact-target-order", revision: "1", make: || Input.{ count: 7, depth: 1, mode: 0, width: 19 } }),
			Fuzz.example({ name: "missing-scope", revision: "1", make: || Input.{ count: 6, depth: 1, mode: 1, width: 9 } }),
			Fuzz.example({ name: "duplicate-term", revision: "1", make: || Input.{ count: 5, depth: 0, mode: 2, width: 9 } }),
			Fuzz.example({ name: "duplicate-location", revision: "1", make: || Input.{ count: 3, depth: 1, mode: 3, width: 27 } }),
		],
		test,
		show: |input| Str.inspect(input),
	}),
])

test : Input -> Fuzz.Outcome
test = |Input.({ count: selector, depth: depth_input, mode: mode_input, width: width_input })| {
	mode = mode_input % 4
	depth = depth_input % 2 + 1
	width = Layout.Unit.points((width_input % 48 + 12).to_i64())
	count = (selector % 10).to_u64() + 2
	scope = if (mode == 1) Under("missing") else Under("root")
	var $blocks = [
		Pdf.generated_contents({ scope, depth, page_width: width }),
		Pdf.destination_heading({ name: "root", level: 1, text: "Recovery" }),
	]
	var $expected = []
	var $i = 0.U64
	while $i < count {
		name = "step-${$i.to_str()}"
		level = if ($i % 2 == 0) 2 else 3
		$blocks = $blocks.append(Pdf.destination_heading({ name, level, text: "Recovery check" }))
		if level == 2 or depth == 2 {
			$expected = $expected.append(name)
		}
		$i = $i + 1
	}
	first = { term: "Escalation", destinations: ["step-1"] }
	next = { term: if (mode == 2) "Escalation" else "Drill", destinations: if (mode == 3) ["step-0", "step-0"] else ["step-0", "step-1"] }
	index = Pdf.index({ entries: [first, next], page_width: width })
	$blocks = $blocks.append(Pdf.destination_heading({ name: "appendix", level: 1, text: "Appendix" })).append(index)
	document = Pdf.document({ title: "Recovery handbook", language: "en-AU", contents: $blocks })
	valid = match Document.resolve_generated_contents(document) {
		Ok(resolved) => {
			normalized = Document.normalize(resolved)
			order = normalized.page_references.map(|record| record.spec.destination)
			fields = normalized.page_references.all(|record| record.spec.width == width)
			index_locations = [$expected.len(), $expected.len() + 1, $expected.len() + 2].map(
				|reference| Document.index_location(normalized, reference),
			)
			normalized.contents_entries.len() == $expected.len() and fields and mode == 0 and
				order == $expected.concat(["step-0", "step-1", "step-1"]) and index_locations == [IndexLocation(0), IndexLocation(1), IndexLocation(0)]
		}
		Err(Selection({ error: MissingScope, position: 0 })) => mode == 1
		Err(InvalidIndex({ error: DuplicateTerm(1), position })) => mode == 2 and position == count + 3
		Err(InvalidIndex({ error: DuplicateTarget({ entry: 1, target: 1 }), position })) => mode == 3 and position == count + 3
		Err(_) => False
	}
	if valid {
		Fuzz.keep
	} else {
		crash "generated navigation diverged from authored targets or rejected the wrong input"
	}
}
