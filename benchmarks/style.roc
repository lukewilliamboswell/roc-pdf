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
		Bench.common_args(128),
		Opt.u64({ short: "", long: "paragraph-units", help: "Units per paragraph. Zero uses one paragraph.", default: Value(0) }),
		|common, workload| { common, workload },
	)
	Bench.run_with!(
		args,
		{
			name: "pdf-style-bench",
			description: "Prepare alternating bold and italic text as one long paragraph or smaller paragraphs.",
		},
		builder,
		document,
	)
}

document : U64, U64, U64 -> Document
document = |units, iteration, requested_paragraph_units| {
	paragraph_units = if (requested_paragraph_units == 0) units else requested_paragraph_units
	var $contents = []
	var $index = 0
	while $index < units {
		count = U64.min(paragraph_units, units - $index)
		$contents = $contents.append(paragraph($index, count))
		$index = $index + count
	}
	Pdf.document({
		title: "Inspection register, run ${iteration.to_str()}",
		language: "en-AU",
		contents: $contents,
	})
}

paragraph : U64, U64 -> Document.Block
paragraph = |start, count| {
	var $inlines = []
	var $index = start
	end = start + count
	while $index < end {
		reference = (24001 + $index).to_str()
		$inlines = $inlines.append(Pdf.strong([Pdf.text("Valve ${reference}: ")]))
		$inlines = $inlines.append(Pdf.emphasis([Pdf.text("inspect during the next service. ")]))
		$index = $index + 1
	}
	Pdf.rich_paragraph($inlines)
}
