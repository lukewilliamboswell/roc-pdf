import fuzz.Model
import fuzz.Solve
import pdf.Document
import pdf.KernelSpan
import pdf.KernelWidgetFields
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
		[Append(0), Append(1), Append(2), Append(3), Append(4), Append(5), Finalize]
	},
	step: |world, action| match action {
		Append(index) => { ..world, fields: world.fields.append(index) }
		Finalize => { ..world, closed: True }
	},
	rules: [
		Model.always("public preparation retains valid widgets in authored page order", |world| !world.closed or agrees(world.fields)),
		Model.sometimes("a duplicate ID has two different labels", |world| world.closed and world.fields == [0, 3]),
		Model.sometimes("reordered blank and filled fields", |world| world.closed and world.fields == [1, 0]),
		Model.sometimes("mixed preparation crosses a page boundary", |world| world.closed and world.fields == [1, 2, 4]),
		Model.sometimes("checked options have distinct visible labels and one export token", |world| world.closed and world.fields == [2, 5, 4]),
	],
}

identifier : U8 -> Str
identifier = |code| match code {
	1 => "reference"
	2 => "approved"
	4 => "visit"
	5 => "consent"
	_ => "contact"
}

label : U8 -> Str
label = |code| match code {
	0 => "Name"
	1 => "Reference"
	2 => "Approved label"
	4 => "Visit request"
	5 => "Consent label"
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
			if code == 2 or code == 4 or code == 5 {
				$page = $page.place_checkbox({ field: { id: identifier(code), label: label(code), state: if (code == 4) Unchecked else Checked }, origin })
			} else {
				$page = $page.place_text_field({ field: { id: identifier(code), label: label(code), width: 150, value: if (code == 1) Prefilled("R7") else Blank }, origin })
			}
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
		(Err(InvalidDocument({ diagnostics: [{ feature: Feature(feature), details: [path], .. }], .. })), At(duplicate)) => {
			code = codes.get(duplicate) ?? crash "duplicate model index"
			expected = if (code == 2 or code == 4 or code == 5) "form.checkbox.duplicate_id" else "form.text.duplicate_id"
			page = duplicate // 2
			placement = duplicate % 2 + 1
			feature == expected and path == "pages[${page.to_str()}].placements[${placement.to_str()}].field.id"
		}
		(Ok({ report, prepared }), None) => {
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
			planned_values_agree(doc, codes) and Pdf.to_bytes_prepared(prepared).is_ok()
		}
		_ => False
	}
}

## The public facade above checks owner, order and accepted lowering. Compare
## its production field-planning input against an authored truth table without
## deriving initial values or labels from a PDF dictionary.
planned_values_agree : Document, List(U8) -> Bool
planned_values_agree = |doc, codes| {
	view = match Document.normalize_fixed(doc, { max_pages: 2, max_placements: 5, max_rectangles: 0 }) {
		Ok(Fixed(normalized)) => Document.NormalizedFixed.view(normalized)
		_ => return False
	}
	plan = KernelWidgetFields.prepare(view.widget_fields, KernelWidgetFields.Budgets.default) ?? return False
	fields = KernelWidgetFields.Plan.fields(plan)
	if fields.len() != codes.len() {
		return False
	}
	var $order = 0
	for field in fields {
		code = codes.get($order) ?? crash "field model index"
		value_agrees = match (code, field.value) {
			(1, Text("R7")) => True
			(2, Checkbox(Checked)) | (5, Checkbox(Checked)) => True
			(4, Checkbox(Unchecked)) => True
			(0, Text("")) | (3, Text("")) => True
			_ => False
		}
		if !value_agrees or field.label != label(code) or field.id != identifier(code) or field.location.page != $order // 2 {
			return False
		}
		$order = $order + 1
	}
	True
}

expect {
	report = Model.explore(machine, { depth: 5, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash Model.explain(report)
	}
	report.states == 518 and report.steps == 517 and report.depth == 4 and report.reached.len() == 4
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

## A live checkbox reserves the widget, its gap and the complete label.
expect Solve.prove_within(
	{ start: Solve.u64_in(0, 14400000), available: Solve.u64_in(0, 14400000) }.Solve,
	|{ start, available }| {
		end = KernelSpan.Arithmetic.wrapped_end(start, Solve.num(266000))
		fits = KernelSpan.Arithmetic.fits(start, end, available, |left, right| left.lte(right), |left, right| Solve.all([left, right]))
		fits.implies(Solve.all([(start + 22000).lt(start + 26000), (start + 26000 + 240000).eq(end)]))
	},
	5000,
) == Ok(Proved)
