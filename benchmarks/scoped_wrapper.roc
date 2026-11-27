app [main!] {
	pdf: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import Bench
import pdf.Color
import pdf.Document
import pdf.Pdf
import weaver.Cli
import weaver.Opt

main! = |args| {
	depth = Opt.u64({ short: "", long: "scope-depth", help: "Inherited wrappers between the colored scope and the body.", default: Value(0) })
	builder = Cli.weave(Bench.common_args(64), depth, |common, workload| { common, workload })
	Bench.run_configured!(
		args,
		{ name: "pdf-scoped-wrapper-bench", description: "Prepare identical paragraphs below a configurable chain of inherited scopes." },
		builder,
		{ defaults: Pdf.Options.{ profile: Standard }, max_units: 4096 },
		document,
	)
}

document : U64, U64, U64 -> Document
document = |units, iteration, depth| {
	ink = Color.srgb8({ red: 0, green: 50, blue: 80 })
	var $contents = List.repeat(Pdf.paragraph("Check the receiving station and record the scheduled service."), units)
	var $level = 0
	while $level < depth {
		$contents = [Pdf.scoped({}, $contents)]
		$level = $level + 1
	}
	Pdf.document({ contents: [Pdf.scoped({ text: Themed(ink) }, $contents)], language: "en-AU", title: "Station checks, run ${iteration.to_str()}" })
}
