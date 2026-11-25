import fuzz.Model
import pdf.Color
import pdf.Image
import pdf.KernelContent
import pdf.KernelFixture
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelTagged
import pdf.Scene
import pdf.Semantics
import pdf.Text
import StructureOracle

ContentScopeModel := [].{}

Scope : [Graphics, Marked, TextObject]

Operator : StructureOracle.ScopeOperator

ScopeError : [
	Crossed({ actual : Scope, expected : Scope, operator : U64, stream : U64 }),
	MarkedAcrossStreams(U64),
	NestedText({ operator : U64, stream : U64 }),
	TextAcrossStreams(U64),
	TextOperatorOutside({ operator : U64, stream : U64 }),
	UnclosedGraphics,
	UnexpectedClose({ operator : U64, scope : Scope, stream : U64 }),
]

# Each physical stream supplies its own lexical tokens. Graphics scopes can
# continue through a page's Contents array. Marked content must close locally.
# Text is also local in the emission subset exercised here.
check : List(List(Operator)) -> Try({}, ScopeError)
check = |streams| {
	var $stack = []
	var $stream = 0
	for operators in streams {
		var $index = 0
		for operator in operators {
			match stack_action(operator) {
				Push(scope) => {
					if scope == TextObject and $stack.contains(TextObject) {
						return Err(NestedText({ operator: $index, stream: $stream }))
					}
					$stack = $stack.append(scope)
				}
				Pop(scope) => {
					if $stack.is_empty() {
						return Err(UnexpectedClose({ operator: $index, scope, stream: $stream }))
					}
					expected = get($stack, $stack.len() - 1)
					if scope != expected {
						return Err(Crossed({ actual: scope, expected, operator: $index, stream: $stream }))
					}
					$stack = $stack.drop_last(1)
				}
				ReadText => if !$stack.contains(TextObject) {
					return Err(TextOperatorOutside({ operator: $index, stream: $stream }))
				}
			}
			$index = $index + 1
		}
		if $stack.contains(Marked) {
			return Err(MarkedAcrossStreams($stream))
		}
		if $stack.contains(TextObject) {
			return Err(TextAcrossStreams($stream))
		}
		$stream = $stream + 1
	}
	if ($stack.is_empty()) Ok({}) else Err(UnclosedGraphics)
}

stack_action : Operator -> [Pop(Scope), Push(Scope), ReadText]
stack_action = |operator| match operator {
	BeginGraphics => Push(Graphics)
	EndGraphics => Pop(Graphics)
	BeginMarked => Push(Marked)
	EndMarked => Pop(Marked)
	BeginText => Push(TextObject)
	EndText => Pop(TextObject)
	UseText => ReadText
}

# Page-array and single-stream discriminators. Independent per-kind balances
# accept the crossing, and an unconditional stream reset rejects legal q/Q.
expect check([[BeginGraphics, BeginMarked, EndMarked], [BeginMarked, EndMarked, EndGraphics]]) == Ok({})
expect check([[BeginGraphics, BeginMarked], [EndMarked, EndGraphics]]) == Err(MarkedAcrossStreams(0))
expect check([[BeginMarked, BeginGraphics, EndMarked, EndGraphics]]) == Err(Crossed({ actual: Marked, expected: Graphics, operator: 2, stream: 0 }))
expect check([[BeginGraphics]]) == Err(UnclosedGraphics)
expect check([[BeginText, BeginText, EndText, EndText]]) == Err(NestedText({ operator: 1, stream: 0 }))
expect check([[BeginText, BeginGraphics, EndGraphics, EndText]]) == Ok({})

# Scope-like bytes in an operand do not become operators.
expect StructureOracle.content_scope_operators(Str.to_utf8("/Span << /Literal (Q BT ET EMC) /Name /q >> BDC\nEMC\n")) == Ok([BeginMarked, EndMarked])

World : { actual : Bool, artifact_first : Bool, depth : U64 }

Action : [AddTransform, EnableActualText, SwapPaintOrder]

machine : Model.Machine(World, Action)
machine = {
	init: { actual: False, artifact_first: False, depth: 0 },
	actions: |world| {
		var $actions = []
		if world.depth < 3 {
			$actions = $actions.append(AddTransform)
		}
		if !world.actual {
			$actions = $actions.append(EnableActualText)
		}
		if !world.artifact_first {
			$actions = $actions.append(SwapPaintOrder)
		}
		$actions
	},
	step: |world, action| match action {
		AddTransform => { ..world, depth: world.depth + 1 }
		EnableActualText => { ..world, actual: True }
		SwapPaintOrder => { ..world, artifact_first: True }
	},
	rules: [
		Model.always("the emitted scope order agrees with the authored page and remains properly nested", agrees),
		Model.sometimes("an ActualText sequence sits inside multiple graphics scopes", |world| world.depth == 3 and world.actual),
		Model.sometimes("a sibling artifact paints before the text fragment", |world| world.artifact_first),
	],
}

expect {
	report = Model.explore(machine, { depth: 6, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 16 and report.steps == 28 and report.depth == 5 and report.reached.len() == 2
}

agrees : World -> Bool
agrees = |world| match emitted(world) {
	Err(_) => False
	Ok(bytes) => match StructureOracle.content_scope_operators(bytes) {
		Err(_) => False
		Ok(operators) => operators == expected(world) and check([operators]) == Ok({})
	}
}

# The fixture authors one text fragment and one independent artifact image.
# The trace predicts each scope from those facts, including scopes that could
# disappear in matched pairs while leaving an otherwise balanced stream.
expected : World -> List(Operator)
expected = |world| {
	var $text = [BeginMarked].concat(List.repeat(BeginGraphics, world.depth))
	if world.actual {
		$text = $text.append(BeginMarked)
	}
	$text = $text.concat([BeginText, UseText, UseText, UseText, EndText])
	if world.actual {
		$text = $text.append(EndMarked)
	}
	$text = $text.concat(List.repeat(EndGraphics, world.depth)).append(EndMarked)
	artifact = [BeginMarked, BeginGraphics, EndGraphics, EndMarked]
	if (world.artifact_first) artifact.concat($text) else $text.concat(artifact)
}

emitted : World -> Try(List(U8), [FixtureInvalid])
emitted = |world| {
	store = KernelFixture.scene
	var $commands = []
	var $depth = 0
	while $depth < world.depth {
		$commands = $commands.append(Transform({ children: range($depth + 1, 1), matrix: identity }))
		$depth = $depth + 1
	}
	$commands = $commands.append(DrawText({ run: Text.RunId.from_index(0), paint: { fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) }, mode: Fill, opacity: 65535, stroke: NoStroke } }))
	$commands = $commands.append(DrawImage({ image: Image.Id.from_index(0), placement: KernelFixture.rect(4000, 5000, 2000, 1000) }))
	artifact = { ..get(store.groups, 1), commands: range(world.depth + 1, 1) }
	page_groups = if (world.artifact_first) [Scene.GroupId.from_index(1), Scene.GroupId.from_index(0)] else store.page_groups
	semantic_store = KernelFixture.semantics
	semantics = KernelSemantics.Plan.build(semantic_store, 1, 1, KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })) ? |_| FixtureInvalid
	scenes = KernelScene.Plan.build({ ..store, commands: $commands, groups: [get(store.groups, 0), artifact], page_groups }, KernelScene.Resources.with_text({ color_spaces: 1, images: 1, text_runs: 1 }), KernelScene.Limits.make({ max_commands: 5, max_dash_lengths: 0, max_graphics_depth: 4, max_groups: 2, max_pages: 1, max_path_segments: 1, max_paths: 1 })) ? |_| FixtureInvalid
	tagged = KernelTagged.Plan.build(semantics, scenes) ? |_| FixtureInvalid
	actual_text_begin = if (world.actual) Str.to_utf8("/Span <</ActualText <FEFF0041>>> BDC\n") else []
	text = KernelContent.TextPlan.make([{ actual_text_begin, body: Str.to_utf8("<0001> Tj\n"), close_actual_text: world.actual, font: 0, size: KernelFixture.unit(12000) }])
	plan = KernelContent.Plan.build_with_text(tagged, text, KernelContent.Limits.make({ max_content_bytes: 1024, max_content_streams: 1 })) ? |_| FixtureInvalid
	Ok(KernelContent.Plan.stream(plan, Semantics.ContentStreamId.from_index(0)).bytes)
}

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

identity : Scene.Matrix
identity = { a: KernelFixture.unit(1000), b: KernelFixture.unit(0), c: KernelFixture.unit(0), d: KernelFixture.unit(1000), e: KernelFixture.unit(0), f: KernelFixture.unit(0) }

get : List(a), U64 -> a
get = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "content scope fixture index escaped"
}
