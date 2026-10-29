app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import pdf.Pdf
import ProfileKernels
import ProfileWorkloads

## Allocation profiling, not a property campaign. The first input byte selects
## one workload: a document (`ProfileWorkloads`), each of whose stages is
## measured with named `Fuzz.measure!` regions, or, past the documents, a single
## kernel (`ProfileKernels`). An empty input runs every workload. `./scripts/profile.py` replays one input
## per workload and tabulates the printed `PROFILE` lines, so a change to one
## stage can be checked in isolation without the end-to-end suite.
target = Fuzz.from_bytes!({
	name: "roc-pdf-allocation-profile",
	examples: [],
	test!: |bytes| {
		match bytes.first() {
			Ok(selector) => {
				documents = ProfileWorkloads.all.len()
				if selector.to_u64() < documents {
					run!(ProfileWorkloads.select(selector.to_u64()))
				} else {
					match ProfileKernels.all.get(selector.to_u64() - documents) {
						Ok(kernel) => run_kernel!(kernel)
						Err(OutOfBounds) => 1
					}
				}
			}
			Err(ListWasEmpty) => {
				for workload in ProfileWorkloads.all {
					_ = run!(workload)
				}
				for kernel in ProfileKernels.all {
					_ = run_kernel!(kernel)
				}
				0
			}
		}
	},
})

run! : ProfileWorkloads.Workload => U8
run! = |workload| {
	name = ProfileWorkloads.name(workload)
	fonts = Fuzz.measure!("fonts", || ProfileWorkloads.fonts(workload))
	font_allocs = (fonts.stats.allocs + fonts.stats.reallocs)
	report!(name, "fonts", font_allocs)
	match fonts.value {
		Err(_) => crash "${name}: font registration failed"
		Ok(setup) => {
			document = Fuzz.measure!("author", || ProfileWorkloads.document(workload, setup))
			author_allocs = (document.stats.allocs + document.stats.reallocs)
			report!(name, "author", author_allocs)
			prepared = Fuzz.measure!("prepare", || Pdf.prepare(document.value, setup.options))
			prepare_allocs = (prepared.stats.allocs + prepared.stats.reallocs)
			report!(name, "prepare", prepare_allocs)
			match prepared.value {
				Err(_) => crash "${name}: prepare failed"
				Ok(ready) => {
					emitted = Fuzz.measure!("emit", || Pdf.to_bytes_prepared(ready))
					emit_allocs = (emitted.stats.allocs + emitted.stats.reallocs)
					report!(name, "emit", emit_allocs)
					match emitted.value {
						Err(_) => crash "${name}: emission failed"
						Ok(output) => {
							total = font_allocs + author_allocs + prepare_allocs + emit_allocs
							report!(name, "total", total)
							report!(name, "pdf_bytes", output.len())
							report!(name, "pdf_fnv", fnv(output))
							0
						}
					}
				}
			}
		}
	}
}

run_kernel! : ProfileKernels.Kernel => U8
run_kernel! = |kernel| {
	input = (kernel.input)(1)
	measured = Fuzz.measure!(kernel.name, || (kernel.run)(input))
	report!(kernel.name, "total", (measured.stats.allocs + measured.stats.reallocs))
	report!(kernel.name, "output", measured.value)
	0
}

## FNV-1a over the PDF, so a change that alters output bytes shows up in the
## profile even when the length is unchanged. Independent of the package's
## own hashing on purpose.
fnv : List(U8) -> U64
fnv = |bytes| {
	var $hash = 14695981039346656037
	for byte in bytes {
		$hash = U64.times_wrap($hash.bitwise_xor(byte.to_u64()), 1099511628211)
	}
	$hash
}

report! : Str, Str, U64 => {}
report! = |workload, stage, value| {
	dbg "PROFILE ${workload} ${stage} ${value.to_str()}"
	{}
}
