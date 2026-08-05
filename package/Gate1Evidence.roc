import KernelEmit
import KernelSeal
import KernelStructure

Gate1Evidence :: [].{
	generate_blank : U64 -> { bytes : List(U8), work : List(U64) }
	generate_blank = |page_count| {
		plan = match KernelStructure.build_blank(page_count, A4) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 1 stress plan invariant failed"
			}
		}
		sealed = KernelStructure.Plan.sealed(plan)
		counts = KernelSeal.Plan.counts(sealed)
		build = KernelSeal.Plan.build_work(sealed)
		seal = KernelSeal.Plan.seal_work(sealed)
		bytes = match KernelEmit.to_bytes(plan) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 1 stress emission invariant failed"
			}
		}

		{
			bytes,
			work: [
				page_count,
				KernelStructure.Plan.tree_node_count(plan),
				counts.objects,
				counts.values,
				counts.array_items,
				counts.dictionary_entries,
				build.edges_appended,
				seal.references_checked,
				bytes.len(),
			],
		}
	}
}
