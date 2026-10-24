# Publishing a release

`.github/workflows/release-candidate.yml` builds the package bundle with the
pinned Roc nightly, smoke-tests the gallery against it, and, when dispatched
with a `release_tag`, publishes that bundle as the release asset with
`docs/releases/<tag>.md` as the release body. Tags of the form `X.Y.Z-rcN`
become prereleases; `X.Y.Z` becomes a full release marked latest.

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

## Steps

1. Land every change that affects `package/` or `.roc-version`, including the
   final compiler pin, on `main`. Main CI must pass.
2. Compute the bundle name and digest, either with
   `ROC=/abs/path/to/pinned/roc ./scripts/bundle.sh --output-dir dist` and
   `sha256sum dist/*.tar.zst`, or by dispatching the workflow on `main` with
   `nightly_validation: true` and downloading its `roc-pdf-release-bundle`
   artifact.
3. Replace every `TODO(release)` placeholder in `docs/releases/<tag>.md` and
   `README.md`: the Roc nightly from `.roc-version`, the bundle URL
   `https://github.com/lukewilliamboswell/roc-pdf/releases/download/<tag>/<bundle-name>`,
   and the bundle SHA-256. Merge that documentation change to `main`.
4. Dispatch the workflow on `main` with `release_tag: <tag>` and
   `nightly_validation: false`:

   ```sh
   gh workflow run release-candidate.yml --ref main -f release_tag=0.1.0
   ```

   The bundle job rejects a missing notes file, a remaining `TODO(release)`
   placeholder, or notes that do not name the pinned nightly. The publish job
   rejects notes that do not name the exact bundle URL and SHA-256 it
   validated, or a tag that already has a release. It rewrites relative links
   in the notes to links pinned to the dispatched commit, then creates the tag
   at that commit and the release with the bundle attached.
5. Consume the published URL from a fresh application outside the repository
   (see the [rc1 consumer smoke test](0.1.0-rc1-consumer-smoke-test.md)) and
   confirm it builds and writes a PDF.

Publishing 0.1.0 does not close Gate 7 or change any capability claim in the
[feature roadmap](../../feature-roadmap.md); the release notes claim only the
closed capabilities.
