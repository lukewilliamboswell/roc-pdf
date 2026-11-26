import fuzz.Model
import fuzz.Solve
import pdf.Document
import pdf.KernelSpan
import pdf.Layout
import pdf.Pdf

WidgetFormsModel := [].{}

World : { fields : List(U8), closed : Bool }

Action : [Append(U8), Finalize]

## Three fields in authored order, with a boundary after the second
## placement. Different labels can share the same field ID, which must
## reject at the next occurrence. The world carries no PDF object numbers.
machine : Model.Machine(World, Action)
machine = {
	init: { fields: [], closed: False },
	actions: |world| if world.closed {
		[]
	} else if world.fields.len() == 3 {
		[Finalize]
	} else {
		[Append(0), Append(1), Append(2), Append(3), Finalize]
	},
	step: |world, action| match action {
		Append(index) => { ..world, fields: world.fields.append(index) }
		Finalize => { ..world, closed: True }
	},
	rules: [
		Model.always("public preparation retains valid widgets in authored page order", |world| !world.closed or agrees(world.fields)),
		Model.sometimes("a duplicate ID has two different labels", |world| world.closed and world.fields == [0, 3]),
		Model.sometimes("reordered blank and filled fields", |world| world.closed and world.fields == [1, 0]),
		Model.sometimes("preparation crosses a page boundary", |world| world.closed and world.fields == [1, 2, 0]),
	],
}

identifier : U8 -> Str
identifier = |code| match code {
	1 => "reference"
	2 => "approved"
	_ => "contact"
}

label : U8 -> Str
label = |code| match code {
	0 => "Name"
	1 => "Reference"
	2 => "Approved label"
	_ => "Other name"
}

form_document : List(U8) -> Document
form_document = |codes| {
	var $pages = []
	var $index = 0
	while $index < U64.max(1, codes.len()) {
		var $page = Pdf.fixed_page({ width: 595, height: 842 })
			.place({ block: Pdf.paragraph("Intake"), frame: Layout.rect({ x: 56, y: 700, width: 200, height: 30 }) })
		var $slot = 0
		while $slot < 2 and $index < codes.len() {
			code = codes.get($index) ?? crash "model field index"
			origin : Layout.Point
			origin = { x: 56, y: Layout.Unit.points(630 - $slot.to_i64_wrap() * 60) }
			$page = $page.place_text_field({ field: { id: identifier(code), label: label(code), width: 150, value: if (code == 1) Prefilled("R7") else Blank }, origin })
			$index = $index + 1
			$slot = $slot + 1
		}
		$pages = $pages.append($page.finish())
		if codes.is_empty() {
			break
		}
	}
	Pdf.fixed_document({ pages: $pages, language: "en", title: "Form model" })
}

agrees : List(U8) -> Bool
agrees = |codes| {
	doc = form_document(codes)
	options = Pdf.Options.{ profile: AccessibleForm }
	expected_ids = codes.map(identifier)
	var $first_duplicate = None
	var $index = 0
	while $index < expected_ids.len() {
		id = expected_ids.get($index) ?? crash "model identifier index"
		if expected_ids.sublist({ start: 0, len: $index }).contains(id) {
			$first_duplicate = At($index)
			break
		}
		$index = $index + 1
	}
	match (
		Pdf.prepare_with_report(
			doc,
			{ options: options },
		),
		$first_duplicate,
	) {
		(Err(InvalidDocument({ diagnostics: [{ feature: Feature("form.fields_required"), .. }], .. })), None) => codes.is_empty()
		(Err(InvalidDocument({ diagnostics: [{ feature: Feature("form.text.duplicate_id"), details: [path], .. }], .. })), At(duplicate)) => {
			page = duplicate // 2
			placement = duplicate % 2 + 1
			path == "pages[${page.to_str()}].placements[${placement.to_str()}].field.id"
		}
		(Ok({ report, .. }), None) => {
			labels = report.facts.blocks.keep_if(|block| block.role == "Lbl")
			if labels.len() != codes.len() or report.facts.pages.len() != (codes.len() + 1) // 2 {
				return False
			}
			var $slot = 0
			for entry in labels {
				page = $slot // 2
				placement = $slot % 2 + 1
				if entry.first_page != page + 1 or entry.last_page != page + 1 or entry.fragments != 1 or entry.path != "pages[${page.to_str()}].placements[${placement.to_str()}]" {
					return False
				}
				$slot = $slot + 1
			}
			True
		}
		_ => False
	}
}

expect {
	report = Model.explore(machine, { depth: 5, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash Model.explain(report)
	}
	report.states == 170 and report.steps == 169 and report.depth == 4 and report.reached.len() == 3
}

## The widest admitted page bounds checked coordinates. The label occupies
## the top half of the exact vertical footprint; its origin and upper edge
## therefore fit the same checked span used by fixed-widget geometry.
expect Solve.prove_within(
	{ start: Solve.u64_in(0, 14400000), available: Solve.u64_in(0, 14400000) }.Solve,
	|{ start, available }| {
		length = Solve.num(48000)
		end = KernelSpan.Arithmetic.wrapped_end(start, length)
		fits = KernelSpan.Arithmetic.fits(start, end, available, |left, right| left.lte(right), |left, right| Solve.all([left, right]))
		fits.implies(
			Solve.all([
				(start + 24000).lte(end),
				(start + 22000).lt(start + 24000),
				(start + 24000 + 24000).eq(end),
			]),
		)
	},
	5000,
) == Ok(Proved)
