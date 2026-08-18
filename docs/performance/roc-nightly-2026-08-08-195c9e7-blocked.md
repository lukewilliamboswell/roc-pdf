# Roc nightly 2026-08-08 upgrade and temporary patched compiler

## Decision

The proposed move to `nightly-2026-08-08-195c9e7` was blocked by a compiler
bug introduced between
the two nightlies: `roc build` crashes deterministically (SIGSEGV, or
`BITCODE PARSE ERROR` + `LLVMCompilationFailed`, depending on code layout) on
`tests/gate3_authoring/main.roc` and other Gate 3 apps, while `roc check`
reports zero errors. Local Gate 3 work now temporarily selects the patched
`release-fast-64c9d73d` compiler while an official fixed nightly is pending.

## Root cause (upstream)

Roc commit `556673b043` ("Pack scalar compile-time lists into shared blobs",
2026-08-06) stores compile-time-evaluated scalar lists as packed blobs. In
this package, `KernelFont.inspect(built_in_font_bytes, limits)` is
compile-time evaluable, so the embedded 166,300-byte font is such a constant,
restored in every evidence-function body that uses it. The LLVM backend's
`staticRefcountedBytes` cached a function-local GEP instruction in a
module-lifetime map; the second function body to restore the same constant
consumed the first body's instruction handle, producing out-of-bounds
instruction references (compiler SIGSEGV) or invalid bitcode.

Upstream references:

- Bug: [roc-lang/roc#10697](https://github.com/roc-lang/roc/issues/10697)
- Fix (draft PR): [roc-lang/roc#10700](https://github.com/roc-lang/roc/pull/10700)
- Related latent issues found during the investigation (neither blocks the
  pinned compiler): [roc-lang/roc#10698](https://github.com/roc-lang/roc/issues/10698)
  (debug-only capture-lift invariant for `? |_| Tag({ field: $var })` inside
  `while`, present since at least the current pin) and
  [roc-lang/roc#10699](https://github.com/roc-lang/roc/issues/10699)
  (release compilers segfault instead of reporting a type error).

## Patched-compiler requirement

Until the fix lands in an official nightly, building this package with any
compiler at or after `195c9e77` requires a compiler built from source with the
#10700 patch applied. Verified locally on 2026-08-09: a `ReleaseFast` compiler
built from the PR branch (`issue-10697-static-refcounted-bytes-gep`,
`release-fast-64c9d73d`) builds all 20 `tests/*/main.roc` apps with the suite
flags (`--opt=dev --target=x64musl`) and every app runs its first
spec scenario successfully.

The temporary `.roc-version` pin is not an official downloadable nightly.
Local `scripts/test.py` selects the sibling patched worktree when present.
Remote CI must explicitly provision the same compiler commit before this pin
is portable. Allocation baselines are being reviewed under the dev backend;
they must be updated atomically rather than copied from the former compiler.

## Next steps

1. Track [roc-lang/roc#10700](https://github.com/roc-lang/roc/pull/10700)
   until merged and shipped in a nightly.
2. Re-run the suite against that nightly with the dev backend, then use
   `--compare-baselines` under the proposed compiler.
3. Review the allocation delta table (the #10635 page-path regression review
   pattern applies) and update `.roc-version`, both target baselines, and the
   performance record atomically.
4. Independently of the upgrade, consider rewriting the
   `? |_| Tag({ field: $var })` capture sites (`KernelPageLayout.roc`,
   `KernelShape.roc`) to bind an immutable copy first, once
   [roc-lang/roc#10698](https://github.com/roc-lang/roc/issues/10698) is
   resolved upstream or if debug-built compilers become part of the local
   workflow; the pattern is legal Roc and the pinned release compiler handles
   it correctly today.
