app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import pdf.Pdf
import ProfileWorkloads

## Allocation profiling, not a property campaign. The first input byte selects
## one workload and every stage of it is measured with `Fuzz.measure_allocs!`;
## an empty input runs every workload. `./scripts/profile.py` replays one input
## per workload and tabulates the printed `PROFILE` lines, so a change to one
## stage can be checked in isolation without the end-to-end suite.
target = Fuzz.from_bytes!({
	name: "roc-pdf-allocation-profile",
	test!: |bytes| {
		match bytes.first() {
			Ok(selector) => run!(ProfileWorkloads.select(selector.to_u64()))
			Err(ListWasEmpty) => {
				for workload in ProfileWorkloads.all {
					_ = run!(workload)
				}
				0
			}
		}
	},
})

run! : ProfileWorkloads.Workload => U8
run! = |workload| {
	name = ProfileWorkloads.name(workload)
	fonts = Fuzz.measure_allocs!(|{}| ProfileWorkloads.fonts(workload))
	report!(name, "fonts", fonts.allocations)
	match fonts.value {
		Err(_) => crash "${name}: font registration failed"
		Ok(setup) => {
			document = Fuzz.measure_allocs!(|{}| ProfileWorkloads.document(workload, setup))
			report!(name, "author", document.allocations)
			prepared = Fuzz.measure_allocs!(|{}| Pdf.prepare(document.value, setup.options))
			report!(name, "prepare", prepared.allocations)
			match prepared.value {
				Err(_) => crash "${name}: prepare failed"
				Ok(ready) => {
					emitted = Fuzz.measure_allocs!(|{}| Pdf.to_bytes_prepared(ready))
					report!(name, "emit", emitted.allocations)
					match emitted.value {
						Err(_) => crash "${name}: emission failed"
						Ok(output) => {
							total = fonts.allocations + document.allocations + prepared.allocations + emitted.allocations
							report!(name, "total", total)
							report!(name, "pdf_bytes", output.len())
							0
						}
					}
				}
			}
		}
	}
}

report! : Str, Str, U64 => {}
report! = |workload, stage, value| {
	dbg "PROFILE ${workload} ${stage} ${value.to_str()}"
	{}
}
