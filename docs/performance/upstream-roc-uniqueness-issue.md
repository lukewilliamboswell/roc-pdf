# Upstream issue draft: dev-backend uniqueness losses and related defects

Status: **draft, not filed.** The maintainer reviews and files it. It was
written during slice S6b ([lowering-uniqueness.md](lowering-uniqueness.md)),
where these behaviours made the package's object lowering and semantic
planning copy whole lists once per element.

The draft holds four independent reports (A to C, and E) and one note (D).
Each can be filed on its own. A mattered most to S6b; E, added during slice
S6c ([emission-linearity.md](emission-linearity.md)), mattered most to
content emission.

## Environment

- Roc `nightly-2026-09-26-d6267b4` (`roc version`: `Roc compiler version
  nightly-2026-09-26-d6267b4`).
- Linux x86-64 (Ubuntu 24.04, kernel 7.0), target `x64musl`.
- `--opt=dev` unless noted; `--opt=speed` results are given for comparison.
- Measurements use a minimal Zig host whose `roc_alloc` and `roc_realloc`
  count events and sum the requested sizes (`allocated_bytes`: the size of
  every `roc_alloc` plus the new size of every `roc_realloc`). Any host that
  counts calls shows the same allocation counts.

## Reproduction

One file, `main.roc`, run as `./repro MODE N`. The work value is the result.

```roc
app [main!] { pf: platform "platform/main.roc" }

Buffers : { items : List(U64), other : List(U64) }

## Appends to `items` after a (never failing) bounds check.
push : Buffers, U64 -> Try(Buffers, [Full])
push = |buffers, item| {
	{ items, other } = buffers
	if items.len() > 1000000000 {
		Err(Full)
	} else {
		Ok({ items: items.append(item), other })
	}
}

## The same without the Try.
push_plain : Buffers, U64 -> Buffers
push_plain = |buffers, item| {
	{ items, other } = buffers
	{ items: items.append(item), other }
}

## `?`, then the caller appends to a field of the unwrapped record.
question : U64 -> Try(U64, [Full])
question = |n| {
	var $buffers = { items: [], other: [] }
	var $index = 0
	while $index < n {
		pushed = push($buffers, $index)?
		$buffers = { ..pushed, items: pushed.items.append($index) }
		$index = $index + 1
	}
	Ok($buffers.items.len())
}

## Identical, but the callee returns the record without a Try.
plain : U64 -> U64
plain = |n| {
	var $buffers = { items: [], other: [] }
	var $index = 0
	while $index < n {
		pushed = push_plain($buffers, $index)
		$buffers = { ..pushed, items: pushed.items.append($index) }
		$index = $index + 1
	}
	$buffers.items.len()
}

## Identical to `question`, with the Try matched explicitly.
matched : U64 -> U64
matched = |n| {
	var $buffers = { items: [], other: [] }
	var $index = 0
	while $index < n {
		$buffers = match push($buffers, $index) {
			Ok(pushed) => { ..pushed, items: pushed.items.append($index) }
			Err(Full) => crash "unreachable"
		}
		$index = $index + 1
	}
	$buffers.items.len()
}

## Accumulating with `List.concat` of a two-element list.
concat : U64 -> U64
concat = |n| {
	var $items = []
	var $index = 0
	while $index < n {
		$items = $items.concat([$index, $index])
		$index = $index + 1
	}
	$items.len()
}

## The same accumulation with two appends.
appends : U64 -> U64
appends = |n| {
	var $items = []
	var $index = 0
	while $index < n {
		$items = $items.append($index).append($index)
		$index = $index + 1
	}
	$items.len()
}

identity : U64 -> U64
identity = |value| value

## A `var` reassigned inside a `match` that is a call argument.
match_argument : U64 -> U64
match_argument = |n| {
	var $count = 0
	var $index = 0
	while $index < n {
		_ = identity(
			match $index % 2 {
				0 => {
					$count = $count + 1
					1
				}
				_ => 0
			},
		)
		$index = $index + 1
	}
	$count
}

parse : Str -> U64
parse = |text| {
	var $value = 0
	var $index = 0
	bytes = text.to_utf8()
	while $index < bytes.len() {
		$value = $value * 10 + (bytes.get($index) ?? 48).to_u64() - 48
		$index = $index + 1
	}
	$value
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = args.get(1) ?? ""
	n = parse(args.get(2) ?? "0")
	result = if mode == "question" {
		question(n) ?? 0
	} else if mode == "plain" {
		plain(n)
	} else if mode == "matched" {
		matched(n)
	} else if mode == "concat" {
		concat(n)
	} else if mode == "appends" {
		appends(n)
	} else {
		match_argument(n)
	}
	{ bytes: [], work: [result] }
}
```

Build it twice into one empty cache, keeping both binaries:

```sh
rm -rf cache
XDG_CACHE_HOME=$PWD/cache roc build main.roc --opt=dev --target=x64musl --output=./repro_first
XDG_CACHE_HOME=$PWD/cache roc build main.roc --opt=dev --target=x64musl --output=./repro_second
```

## Observed

`--opt=dev`, allocation events and allocated bytes:

| Mode | N | First build | Second build (same source, warm cache) |
| --- | ---: | --- | --- |
| `question` | 1,000 | 2,002 / 20,273,212 | 2,002 / 20,273,212 |
| `question` | 2,000 | 4,002 / 80,285,212 | 4,002 / 80,285,212 |
| `question` | 4,000 | 8,002 / 320,309,212 | 8,002 / 320,309,212 |
| `plain` | 1,000 | 13 / 58,164 | 13 / 58,164 |
| `plain` | 4,000 | 16 / 205,932 | 16 / 205,932 |
| `matched` | 1,000 | 13 / 58,164 | 2,001 / 20,281,180 |
| `matched` | 2,000 | 15 / 135,940 | 4,001 / 80,301,180 |
| `matched` | 4,000 | 16 / 205,932 | 8,001 / 320,341,180 |
| `concat` | 1,000 | 2,001 / 8,040,004 | 2,001 / 8,040,004 |
| `concat` | 2,000 | 4,001 / 32,080,004 | 4,001 / 32,080,004 |
| `concat` | 4,000 | 8,001 / 128,160,004 | 8,001 / 128,160,004 |
| `appends` | 4,000 | 16 / 205,932 | 16 / 205,932 |

(`concat`'s allocation count includes the 1,000 to 4,000 two-element list
literals; its bytes are the point.)

`--opt=speed`, both builds: `question` and `matched` allocate 13 / 58,220
at N = 1,000 and 16 / 205,988 at N = 4,000; `concat` is unchanged
(8,001 / 128,160,060 at N = 4,000).

`match_argument` returns **0** for `N = 10` with both `--opt=dev` and
`--opt=speed`; the expected value is 5.

## A. A list reached through `?` is copied when the caller updates it

**Expected:** `question` behaves like `plain`: amortized-linear appends, about
16 allocation events and 206 KB at N = 4,000.

**Observed:** every iteration copies `items` (allocations = 2N + 2, bytes
quadratic in N), in both builds. `plain` differs only in the callee returning
`Buffers` instead of `Try(Buffers, _)`.

**Why the list should be unique:** `$buffers` is passed to `push` as its last
use (it is reassigned from the result). `push` destructures its argument and
returns a record built from the appended list. On the `Ok` path the payload
record is the only holder of `items`, and `pushed` dies once `$buffers` is
rebuilt from it. Nothing else can observe the old list, so `append` should
find a reference count of 1. The Err path returns early and holds nothing.

The same happens when the unwrapped record is destructured, when both of
its fields are projected into the next call (`f(r.builder, r.values)`), and
when a projected list is passed to a plain function that updates it
(`set_first(pushed.items, …)`). Passing the unwrapped value straight into
another `Try`-returning function that appends does *not* copy. In roc-pdf,
this made every structure element, every table cell, and every page-tree node
copy the object store's lists once (see
[lowering-uniqueness.md](lowering-uniqueness.md)).

## B. Code generation depends on the cache state

**Expected:** building the same source twice produces the same program.

**Observed:** `matched` is linear in the first build and copies on every
iteration in the second build, which reuses the first build's cache. The
difference is only in the cache contents. It appears in larger programs as
cache-dependent allocation counts for identical source: in roc-pdf the same
fixture built alone into an empty cache and built after the test suite's
`roc check`/`roc test` runs gave 100,900 and 110,221 allocations.

**A likely cause (not verified):** a procedure loaded from the object cache
is marked `external`, and `lir/arc_solve.zig` gives it only the signature
fields stored in the pack (`rc_borrowed_params`, `rc_ret_borrowed`,
`rc_ret_lenders`). The in-memory `RcSig` also carries `ret_unique`,
`ret_unique_fields`, `ret_conditions`, `read_only_params`, and `outcomes`
(restitution per returned discriminant). Callers of a cached procedure would
then see a pessimistic signature, for example no unique `Ok` payload, while
callers compiled together with the procedure see the full one.

## C. `List.concat` does not grow geometrically

**Expected:** `concat` accumulating two elements per iteration is
amortized-linear, like `appends`.

**Observed:** quadratic bytes in both backends. `listConcat` reallocates the
first list to exactly `len(a) + len(b)`. The explicit `List.reserve` also
sizes exactly (documented in `listReserve`), so a helper that calls
`List.reserve(target, source.len())` before appending, or a loop that
concatenates onto an accumulator, reallocates the whole accumulator on every
call. Appends are geometric (`listReserveForAppend`). Growing `concat`
geometrically when the first list is unique would make the common
accumulation pattern linear. If exact sizing is intended, documenting it on
`concat` would help.

## D. A `var` reassigned inside a `match` that is a call argument loses the update

**Expected:** `match_argument(10)` returns 5.

**Observed:** it returns 0 with both `--opt=dev` and `--opt=speed`. Binding
the `match` to a name first (`value = match … ; _ = identity(value)`) returns
5. This is a miscompilation rather than a performance issue.

## E. A `var` that is dead after a join stays live across a call

A second file, `dead.roc`, run as `./dead MODE N` on the same platform:

```roc
app [main!] { pf: platform "platform/main.roc" }

## One branch of the tail `if` passes `$out` on as its value, the other
## reassigns it first.
branch : List(U64), U64 -> List(U64)
branch = |list, i| {
	var $out = list.append(i)
	if i % 2 == 0 {
		$out.append(1)
	} else {
		$out = $out.append(2)
		$out
	}
}

## The same values without a reassigned `var` in the branches.
branch_fixed : List(U64), U64 -> List(U64)
branch_fixed = |list, i| {
	out = list.append(i)
	if i % 2 == 0 out.append(1) else out.append(2)
}

State : { items : List(U64), left : U64 }

step : State -> [Done, Next(State)]
step = |state| {
	{ items, left } = state
	if left == 0 Done else Next({ items: items.append(left), left: left - 1 })
}

## A flag loop: the `Done` arm keeps `$state`, which nothing reads after the loop.
flag : U64 -> U64
flag = |n| {
	var $state = { items: [], left: n }
	var $steps = 0
	var $done = Bool.False
	while !$done {
		match step($state) {
			Done => {
				$done = Bool.True
			}
			Next(next) => {
				$state = next
				$steps = $steps + 1
			}
		}
	}
	$steps
}

## The same loop returning from the `Done` arm.
flag_return : U64 -> U64
flag_return = |n| {
	var $state = { items: [], left: n }
	var $steps = 0
	while Bool.True {
		match step($state) {
			Done => {
				return $steps
			}
			Next(next) => {
				$state = next
				$steps = $steps + 1
			}
		}
	}
	$steps
}

parse : Str -> U64
parse = |text| {
	var $value = 0
	var $index = 0
	bytes = text.to_utf8()
	while $index < bytes.len() {
		$value = $value * 10 + (bytes.get($index) ?? 48).to_u64() - 48
		$index = $index + 1
	}
	$value
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = args.get(1) ?? ""
	n = parse(args.get(2) ?? "0")
	result = if mode == "branch" or mode == "branch_fixed" {
		var $list = []
		var $i = 0
		while $i < n {
			$list = if mode == "branch" branch($list, $i) else branch_fixed($list, $i)
			$i = $i + 1
		}
		$list.len()
	} else if mode == "flag" {
		flag(n)
	} else {
		flag_return(n)
	}
	{ bytes: [], work: [result] }
}
```

Built with `roc build dead.roc --no-cache --target=x64musl`, allocation
events and allocated bytes:

| Mode | `--opt=dev`, N = 1,000 | `--opt=dev`, N = 4,000 | `--opt=speed`, N = 4,000 |
| --- | --- | --- | --- |
| `branch` | 1,004 / 10,139,244 | 4,004 / 160,163,244 | 4,004 / 160,163,300 |
| `branch_fixed` | 13 / 58,164 | 16 / 205,932 | 16 / 205,988 |
| `flag` | 1,002 / 4,012,084 | 4,002 / 64,048,084 | 15 / 135,996 |
| `flag_return` | 11 / 23,588 | 15 / 135,940 | 15 / 135,996 |

**Expected:** `branch` behaves like `branch_fixed`, and `flag` like
`flag_return`: amortized-linear appends.

**Observed:** `branch` copies the list on every call in both backends, and
`flag` copies the state's list on every step with `--opt=dev`.

**Why the list should be unique:** in `branch`, `$out` is dead after the
`if` (the `if` is the function's result). The final LIR carries the `var`
beside the branch value in the join after the `if`: the `then` branch sets
both join parameters from the same `$out`, with an `incref`, so the
`append` inside the branch value sees a second reference. In `flag`, the
loop's join carries `$state` into the `Done` arm, where it is kept although
nothing reads it after the loop, so `step($state)` is passed an extra
reference each iteration. In both cases the carried value is dead on every
path that keeps it. Dropping join parameters (or `var` state) that are dead
after the join, or releasing them before the call, would make both linear.

In roc-pdf, `branch`'s shape was `KernelLex.append_decimal` (every whole
number written into a content stream copied the stream) and the color and
dash emitters; `flag`'s shape was the buffered emission loop, which copied
the encoder's object offsets once per object.

## Not reproduced

Two further copies in roc-pdf did not reduce to a small program:

- **Aggregate joins at loop exits.** In `KernelFacadeScenes`, two
  consecutive inner loops over the same three list accumulators copied all
  three once per outer iteration. The LIR packed the first loop's exit state
  into a struct, read its list fields with an `incref` each, and the
  second loop's entry `list_map_prepare_reuse` (inserted by
  `loop_append_promote`) ran before the struct was released. A statement
  `match` whose arm reassigned two list `var`s behind `?` exits did the
  same, once per iteration. Minimal nested loops, `match`es, and early exits
  of the same shape stayed linear. `scalarize_joins` only splits join
  parameters; the exit struct is a plain local.
- **A borrowed specialization chosen through a projection.** A caller that
  still read a projection of a record (`store = plan_store(encoder.plan)`)
  after passing the record to a function called that function's borrowed
  specialization, whose field reads `incref` the lists, so the append in it
  copied. Reading the projection before the call made the call use the owned
  specialization.

The S6b note that `KernelContent.emit_commands` copied its byte list because
of an unsplit sixteen-variable join was wrong: the copies were in the
helpers it called, from report E's `branch` shape.

A nested `while` loop whose inner loop appends to an outer `var` list did not
allocate per outer iteration in a minimal program (3 allocations for 40 × 40
appends into a preallocated list, in both builds). A loop that copies per
iteration because a match arm keeps the old value (`Err(_) => $list` after
`$list.set(…)`) is expected behaviour, since the old list is still live on
that path.
