import KernelFacadePages
import KernelFacadeSemantics
import KernelPageLayout
import Semantics
import Text

## Compact preparation-report facts, collected once from the stages that
## own them while those stages are live. Every fact is a scalar keyed by a
## normalized index (leaf block, group, custom block, figure) or a page
## index; no fact holds a PDF object identity, a stage plan, a scene, or a
## resource payload, so collecting them keeps nothing alive past
## preparation. `Pdf` materializes them into the public report and maps
## each index back to its authored path.
KernelFacadeReport :: [].{

	## A page-layout unit: a leaf block, or a table row by its row group.
	Unit : [LeafUnit(U64), RowUnit(U64)]

	## A preference the accepted pagination relaxed, at its declaring unit.
	Relaxation : { page : U64, rank : KernelPageLayout.Rank, unit : Unit }

	## The layout policy outcomes of pagination: relaxed preferences, each
	## figure's applied scale in thousandths, the pages on which continued
	## tables repaint header rows and split rows continue, and the page of
	## each custom block.
	LayoutFacts : {
		panels : List({ custom : U64, page : U64 }),
		relaxations : List(Relaxation),
		repeats : List(KernelFacadePages.Repeat),
		scales : List(U64),
		splits : List(KernelFacadePages.RowContinuation),
	}

	## One leaf block's final layout: its first and last page and its
	## fragment count (zero for a block with no painted fragment).
	BlockSpan : { first_page : U64, fragments : U64, last_page : U64 }

	## Consecutive final text runs of one leaf block in one font instance
	## and script, with their scalar count.
	Coverage : { block : U64, font : U64, scalars : U64, script : Str }

	## `pages` holds each page's fragment count.
	Facts : { blocks : List(BlockSpan), coverage : List(Coverage), layout : LayoutFacts, pages : List(U64) }

	## Whether preparation collects report facts. Ordinary preparation does
	## not, and allocates nothing for them.
	Request : [Collect, NoCollect]

	## The pagination outcomes, from the pages plan. O(relaxations + figures
	## + repeats + splits + custom blocks).
	layout : KernelFacadePages.Plan -> LayoutFacts
	layout = |pages| {
		units = KernelFacadePages.Plan.units(pages)
		flow = KernelFacadePages.Plan.flow(pages)
		relaxed = KernelFacadePages.Plan.relaxations(pages)
		var $relaxations = List.with_capacity(relaxed.len())
		for relaxation in relaxed {
			unit = if units.is_empty() {
				LeafUnit(relaxation.block)
			} else {
				match units.get(relaxation.block) {
					Ok(LeafUnit(leaf)) => LeafUnit(leaf)
					Ok(RowUnit(group)) => RowUnit(group)
					Err(OutOfBounds) => LeafUnit(relaxation.block)
				}
			}
			$relaxations = $relaxations.append({ page: relaxation.page, rank: relaxation.rank, unit })
		}
		{
			panels: flow.panels.map(|panel| { custom: panel.custom, page: panel.page }),
			relaxations: $relaxations,
			repeats: KernelFacadePages.Plan.repeats(pages),
			scales: flow.figure_scales,
			splits: KernelFacadePages.Plan.splits(pages),
		}
	}

	## Final block spans, per-page fragment counts, and text coverage, from
	## the semantic block ownership, the final layout fragments, and the
	## final text runs. O(blocks + occurrences + fragments + runs).
	collect : LayoutFacts, List(KernelFacadeSemantics.BlockOwnership), List(Semantics.LayoutFragment), Text.Store, U64 -> Facts
	collect = |layout_facts, ownership, fragments, text, page_count| {
		owners = occurrence_owners(ownership)
		none = U64.highest
		var $blocks = List.repeat({ first_page: none, fragments: 0, last_page: 0 }, ownership.len())
		var $pages = List.repeat(0, page_count)
		for fragment in fragments {
			page = fragment.page.index()
			if page < $pages.len() {
				$pages = list_set($pages, page, list_at($pages, page) + 1)
			}
			occurrence = fragment.occurrence.index()
			if occurrence < owners.len() {
				block = list_at(owners, occurrence)
				if block < $blocks.len() {
					span = list_at($blocks, block)
					$blocks = list_set($blocks, block, { first_page: U64.min(span.first_page, page), fragments: span.fragments + 1, last_page: U64.max(span.last_page, page) })
				}
			}
		}
		var $coverage = []
		for run in text.runs {
			match run.unicode {
				OccurrenceText(occurrence) => {
					index = occurrence.index()
					if index < owners.len() {
						block = list_at(owners, index)
						font = run.instance.index()
						script = run.script.as_str()
						scalars = run.source.scalars.length()
						last = $coverage.len()
						merged = if last == 0 {
							False
						} else {
							previous = list_at($coverage, last - 1)
							previous.block == block and previous.font == font and previous.script == script
						}
						if merged {
							previous = list_at($coverage, last - 1)
							$coverage = list_set($coverage, last - 1, { ..previous, scalars: previous.scalars + scalars })
						} else {
							$coverage = $coverage.append({ block, font, scalars, script })
						}
					}
				}
				ArtifactText(_) => {}
			}
		}
		{ blocks: $blocks, coverage: $coverage, layout: layout_facts, pages: $pages }
	}
}

## The leaf block that owns each semantic occurrence: a block's body or
## rich occurrences and its generated label.
occurrence_owners : List(KernelFacadeSemantics.BlockOwnership) -> List(U64)
occurrence_owners = |ownership| {
	var $count = 0
	for owned in ownership {
		end = match owned {
			TextBlock({ body, label, level: _ }) => U64.max(body.index() + 1, label_end(label))
			RichTextBlock({ label, level: _, occurrences }) => U64.max(occurrences.start() + occurrences.length(), label_end(label))
			ContentlessCell => 0
		}
		$count = U64.max($count, end)
	}
	var $owners = List.repeat(U64.highest, $count)
	var $block = 0
	for owned in ownership {
		match owned {
			TextBlock({ body, label, level: _ }) => {
				$owners = list_set($owners, body.index(), $block)
				match label {
					Label(occurrence) => {
						$owners = list_set($owners, occurrence.index(), $block)
					}
					NoLabel => {}
				}
			}
			RichTextBlock({ label, level: _, occurrences }) => {
				var $occurrence = occurrences.start()
				while $occurrence < occurrences.start() + occurrences.length() {
					$owners = list_set($owners, $occurrence, $block)
					$occurrence = $occurrence + 1
				}
				match label {
					Label(occurrence) => {
						$owners = list_set($owners, occurrence.index(), $block)
					}
					NoLabel => {}
				}
			}
			ContentlessCell => {}
		}
		$block = $block + 1
	}
	$owners
}

label_end : [Label(Semantics.OccurrenceId), NoLabel] -> U64
label_end = |label| match label {
	Label(occurrence) => occurrence.index() + 1
	NoLabel => 0
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "report fact index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "report fact write escaped"
	}
	Ok(updated) => updated
}
