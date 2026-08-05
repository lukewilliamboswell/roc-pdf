platform ""
	requires {
		main! : List(Str) => {
			backing : List(U8),
			bytes : List(U8),
			owned : List(U8),
			shared : List(U8),
			source : List(U8),
			work : List(U64),
		}
	}
	exposes []
	packages {}
	provides { "roc_main": main_for_host! }
	targets: {
		inputs_dir: "../platform/targets/",
		arm64mac: { inputs: ["libretention_host.a", app] },
		x64musl: { inputs: ["crt1.o", "libretention_host.a", app, "libc.a"] },
	}

main_for_host! : List(Str) => {
	backing : List(U8),
	bytes : List(U8),
	owned : List(U8),
	shared : List(U8),
	source : List(U8),
	work : List(U64),
}
main_for_host! = |args| main!(args)
