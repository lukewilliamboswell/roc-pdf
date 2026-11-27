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
	workload_args = Cli.weave(
		Opt.u64({ short: "", long: "lines-per-block", help: "Maximum source lines per block. Zero uses one block.", default: Value(4096) }),
		Opt.flag({ short: "", long: "highlight", help: "Highlight a key on every authored line." }),
		|lines_per_block, highlight| { lines_per_block, highlight },
	)
	builder = Cli.weave(Bench.common_args(256), workload_args, |common, workload| { common, workload })
	Bench.run_with!(args, { name: "pdf-source-bench", description: "Paginate source blocks with explicit indentation and optional foreground ranges." }, builder, document)
}

document : U64, U64, { lines_per_block : U64, highlight : Bool } -> Document
document = |units, iteration, { lines_per_block, highlight }| {
	block_lines = if (lines_per_block == 0) units else lines_per_block
	var $remaining = units
	var $contents = [Pdf.heading(1, "Equipment log")]
	while $remaining > 0 {
		count = U64.min($remaining, block_lines)
		$contents = $contents.append(source_block(count, highlight))
		$remaining = $remaining - count
	}
	Pdf.document({ title: "Equipment log, run ${iteration.to_str()}", language: "en-AU", contents: $contents })
}

source_block : U64, Bool -> Document.Block
source_block = |lines, highlight| {
	line = "\tstation: drying-yard; status: reviewed; dispatch: 14:30"
	next_line = "\n${line}"
	text = Str.concat(line, Str.repeat(next_line, lines - 1))
	stride = next_line.count_utf8_bytes()
	var $foregrounds = []
	if highlight {
		var $index = 0
		while $index < lines {
			start = $index * stride + 1
			$foregrounds = $foregrounds.append({ start, end: start + 7, color: "#0050A0" })
			$index = $index + 1
		}
	}
	Pdf.source_block({ text, tabs: ExpandTo(4), foregrounds: $foregrounds })
}
