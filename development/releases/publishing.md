# Publishing a release

A release dispatch records one full commit SHA from `main`, runs the complete
applicable checks at that SHA, then publishes the tested artifacts once.
`.roc-version` remains the only package compiler pin. Publishing a version does
not expand any conformance or Gate 7 claim.

## Prepare and validate

1. Author `docs/releases/<version>.md` with the pinned nightly and literal
   `{package-url}` and `{bundle-sha256}` placeholders. Describe user-visible
   behavior and migration; keep the authored placeholders in Git.
2. The PR checks choose the highest authored notes version and build the
   package, examples archive, API/manual archive and PDF. They test the actual
   bundle/archive consumers, render notes with the resulting URL/digest, and
   run `roc bump --old <latest-final-bundle> --expect <version>` under the
   pinned compiler. Both old/new APIs must compile; failures are investigated,
   never skipped or replaced by a guessed compatibility verdict.
3. Merge only after applicable checks pass. Dispatch the release workflow on
   `main` with that authored version and `nightly_validation: true` for an
   end-to-end dry run. This repeats the full Linux/macOS checks, independent
   profile/object-model checks and documentation/archive checks on the recorded
   event SHA. It publishes nothing. Compiler-candidate validation also accepts a branch and
   an omitted tag, deriving the highest authored version; this compatibility
   mode does not establish publication eligibility or an API version verdict.
4. Review the same-run `roc-pdf-release-<sha>` artifact: its manifest records
   the compiler, commit, exact names, lengths and SHA-256 values of all four
   deliverables. Rendered notes are also hash-bound. No source file is rewritten.

## Publish once

Dispatch `release-candidate.yml` from `main` with the same authored version and
`nightly_validation: false`. Existing tags/releases reject before publication.
The protected `release` environment admits `main` alone. A separate job downloads
its own run's artifacts, verifies their manifest/notes/identity and invokes the
full-SHA shared publisher. It checks out no project source and rebuilds nothing.
The publisher creates a draft at the tested SHA, uploads each explicit asset,
downloads and verifies its bytes, and only then publishes. Candidates remain
prereleases; final versions become latest. Immutable hosting and tag rules
prevent modifying a published version.

Assets are the content-addressed package, `roc-pdf-examples-<version>.zip`,
`roc-pdf-docs-<version>.zip`, `roc-pdf-<version>.pdf` and
`release-manifest.json`. The docs archive preserves both the original API site
routes and `/manual/`. Default-branch Pages output says `unreleased`; release
archives carry their exact version.

If publication fails, inspect the named draft and the uploaded/downloaded
files. A draft is never automatically adopted. Delete an unpublished failed
draft before retrying the same run's tested artifacts. Never repair a published
release, move a tag, replace an asset or reconstruct an expired artifact from a
moving branch. Publish changed bytes as a new version.

## How the candidates were published

- rc1 and rc2 were published by this workflow, which at each point accepted
  only that one hard-coded tag (finally `0.1.0-rc2`).
- rc3 to rc6 were created by hand with `gh release create --prerelease`,
  uploading the bundle artifact from a successful bundle job (the PR run for
  rc3, rc5 and rc6; a `nightly_validation` dispatch on `main` for rc4). Their
  bodies were written in the GitHub release and are now copied into
  `docs/releases/`.

The workflow now accepts any `X.Y.Z` or `X.Y.Z-rcN` tag, so later releases do
not need the manual path.

## Bundle identity

`scripts/bundle.sh` is deterministic for a given package tree and Roc
nightly: the bundle built locally from the `ac8dba8` tree with
`nightly-2026-10-18-1df370f` (`FtvjgqwbGNGsm97hoN8kayCX3QacEwMbJo6aPZd7LPEi.tar.zst`,
SHA-256 `d0945e287568f87c79e72beb4777c2ef1403d4eb9a7a5dfa412a93371dac958f`)
is byte-identical to the artifact from the bundle job of
[run 39246645678](https://github.com/lukewilliamboswell/roc-pdf/actions/runs/39246645678),
which built the same tree. The bundle
contains only `package/`, so editing documentation does not change it; any
change to `package/` or `.roc-version` does.
