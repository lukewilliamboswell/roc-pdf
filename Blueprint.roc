# Contributor tooling for roc-pdf. See development/blueprint.md.
#
# The package compiler is not fetched here. `.roc-version` stays its only pin:
# CI installs that nightly with roc-lang/setup-roc, contributors put it on PATH
# as `roc`, and the scripts refuse any other compiler. Zig is fetched by digest
# because the test platform hosts need exactly 0.16.0.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

import pf.Config
import pf.System

config = [
	Name("roc-pdf"),
	Systems(["x86_64-linux", "aarch64-darwin"]),
	Environment("package", [Expect(["roc", "python3", "bash", "tar"])]),
	Environment("dev", [Extend("package"), Programs([Fetch("zig", zig)])]),
	Environment("docs", [Extend("package"), Expect(["rg"])]),
	Shell("default", [Use("dev")]),
	Task("test", [Use("dev"), Run(["python3", "scripts/test.py"])]),
	Task("fuzz", [Use("dev"), Run(["python3", "scripts/fuzz.py"])]),
	Task("gallery", [Use("package"), Run(["python3", "scripts/check_gallery.py"])]),
	Task("bundle", [Use("package"), Run(["bash", "scripts/bundle.sh"])]),
	Task("bundle-consumer", [Use("package"), Run(["python3", "scripts/test_bundle_consumer.py"])]),
	Task("docs", [Use("docs"), Run(["bash", "scripts/docs.sh"])]),
]

zig : System -> Config.Download
zig = |system| {
	base = "https://ziglang.org/download/0.16.0"
	match system {
		"x86_64-linux" => Archive("${base}/zig-x86_64-linux-0.16.0.tar.xz", TarXz, "zig-x86_64-linux-0.16.0/zig")
		"aarch64-darwin" => Archive("${base}/zig-aarch64-macos-0.16.0.tar.xz", TarXz, "zig-aarch64-macos-0.16.0/zig")
		_ => Unavailable
	}
}
