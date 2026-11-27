app [main!] {
	pdf: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import Bench
import pdf.Document
import pdf.Font
import pdf.Pdf
import pdf.RocFont
import weaver.Cli
import "../examples/ordered-han/fonts/ReceivingHan-Regular.ttf" as han_bytes : List(U8)

main! = |args| {
	limits = Font.ValidationLimits.default
	latin = RocFont.register(Font.Registry.empty, limits) ? FontRejected
	han = latin.registry.register({ bytes: han_bytes, registration: { provision: BuiltIn, scripts: ["Hani"] }, limits }) ? FontRejected
	ordered = han.registry.with_policy([latin.body, han.face]) ? InvalidPolicy
	defaults = Pdf.Options.{ profile: Standard, fonts: Registered(ordered.registry), theme: { font_selection: Policy(ordered.policy) } }
	builder = Cli.map(Bench.common_args(64), |common| { common, workload: {} })
	Bench.run_configured!(args, { name: "pdf-mixed-script-bench", description: "Shape one paragraph with alternating Latin and Han scripts." }, builder, { defaults, max_units: 65536 }, document)
}

document : U64, U64, {} -> Document
document = |units, iteration, _| Pdf.document({
	title: "Receiving handover, run ${iteration.to_str()}",
	language: "en-AU",
	contents: [Pdf.paragraph(Str.repeat("A仓", units))],
})
