platform ""
	requires {
		main! : List(Str) => { bytes : List(U8), work : List(U64) }
	}
	exposes []
	packages {}
	provides { "roc_main": main_for_host! }
	targets: {
		inputs_dir: "targets/",
		arm64mac: { inputs: ["libhost.a", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
	}

main_for_host! : List(Str) => { bytes : List(U8), work : List(U64) }
main_for_host! = |args| main!(args)
