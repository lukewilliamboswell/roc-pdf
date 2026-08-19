platform ""
	requires {
		main! : List(Str) => { bytes : List(U8), work : List(U64) }
	}
	exposes [Metrics]
	packages {}
	provides { "roc_main": main_for_host! }
	hosted {
		"roc_host_reset_allocations": Metrics.reset_allocations!,
	}
	targets: {
		inputs_dir: "targets/",
		arm64mac: { inputs: ["libhost.a", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
	}

import Metrics

main_for_host! : List(Str) => { bytes : List(U8), work : List(U64) }
main_for_host! = |args| main!(args)
