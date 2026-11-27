app [main!] {
	pdf: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import Bench
import pdf.Document
import pdf.Pdf
import weaver.Cli
import weaver.Opt

main! = |args| {
	builder = Cli.weave(
		Bench.common_args(8),
		Opt.number_single({ short: "", long: "slots", help: "Reserved-width scalar slots in the running header, from 1 to 1024.", default: Value(256) }, parse_slots),
		|common, workload| { common, workload },
	)
	Bench.run_configured!(
		args,
		{
			name: "pdf-furniture-bench",
			description: "Repeat one running header per page with fixed-width, one-scalar fields. Units are the page count.",
		},
		builder,
		{ defaults: options, max_units: 128 },
		document,
	)
}

parse_slots : Str -> Try(U64, [InvalidSlotCount])
parse_slots = |text| {
	slots = U64.from_str(text) ? |_| InvalidSlotCount
	if (slots == 0 or slots > 1024) Err(InvalidSlotCount) else Ok(slots)
}

options : Pdf.Options
options = {
	page_size: Custom({ width: 13000, height: 842 }),
	profile: Standard,
	theme: { latin_shaping: NominalGlyphs },
}

document : U64, U64, U64 -> Document
document = |pages, iteration, slots| {
	# Each reserved box remains a separate segment. The whole line is one
	# nominal run with one cluster per scalar and the same source per page.
	field = Pdf.reserved_width({ width: 12, align: End, contents: [Pdf.text("1")] })
	header = Pdf.region({ height: 16, start: [Pdf.furniture_text(List.repeat(field, slots))] })
	page_templates = Templates({
		first: Pdf.first_page_template({ header, gap: 12 }),
		continuation: Pdf.page_template({ header, gap: 12 }),
	})
	paragraph = Pdf.paragraph("Body text.")
	var $contents = List.with_capacity(2 * pages - 1).append(paragraph)
	var $page = 1
	while $page < pages {
		$contents = $contents.append(Pdf.page_break).append(paragraph)
		$page = $page + 1
	}
	Pdf.document({
		contents: $contents,
		language: "en",
		page_templates,
		title: "Running header, run ${iteration.to_str()}",
	})
}
