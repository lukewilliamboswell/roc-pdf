app [main!] {
	pdf: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}
import pdf.Layout
import pdf.Scene
import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt

parser = Cli.assert_valid(
	Cli.finish(
		{
			depth: Opt.u64({ short: "", long: "depth", help: "Nested translation groups.", default: Value(1024) }),
			iterations: Opt.u64({ short: "", long: "iterations", help: "Drawings to build and inspect.", default: Value(3) }),
		}.Cli,
		{ name: "drawing-authoring", version: "unversioned", authors: [], description: "Count the commands in increasingly deep drawings.", text_style: Plain },
	),
)

main! = |args| {
	config = match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
		Ok(value) => value
		Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
		Err(InvalidUsage(message)) => return Err(Usage(message))
	}
	var $iteration = 0
	var $command_count = 0
	while $iteration < config.iterations {
		var $drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 16, height: 10 }), color: "#316575" })
		var $depth = 0
		while $depth < config.depth {
			$drawing = Scene.Drawing.empty.group({ offset: Layout.point({ x: 0, y: 0 }), drawing: $drawing })
			$depth = $depth + 1
		}
		$command_count = $command_count + $drawing.commands().len()
		$iteration = $iteration + 1
	}
	Stdout.line!("Drawing command count: ${$command_count.to_str()}").map_err(|error| OutputFailed(error))
}
