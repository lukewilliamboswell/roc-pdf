# veraPDF corpus: PDF/A-4 subset

`verapdf-corpus-pdfa4-49de56c.tgz` holds the `PDF_A-4` tree and the
`README.md` of the veraPDF test corpus, at the commit its 1.30 validation
profiles were released against:

https://github.com/veraPDF/veraPDF-corpus/archive/49de56cd987929932c9e4fbbbe67d052bf44ef83.tar.gz

The full upstream archive has SHA-256
`5c1a138e0fd89fafa51d03a23a1a0bf0a9bcb028430e1d5dd125364e19b87f57`. At
142 MB it exceeds a single repository blob, so only the PDF/A-4 subset is
retained. `scripts/build_verapdf_corpus_subset.py` repacks that subset
deterministically from the pinned upstream archive; the retained files are
byte-identical to upstream, and `conformance/verapdf-corpus-pdfa4.json`
records each file's SHA-256 so any copy of the upstream archive can confirm
the subset.

The corpus is used only by the repository's extended validator lane, to
confirm that the pinned veraPDF validator returns its expected pass/fail
result for each PDF/A-4 test file (`scripts/check_pdfa4.py --corpus`).
Nothing from it is linked into or used by the production Roc package.

The veraPDF corpus is copyright the veraPDF Consortium and contributors and
is licensed under the Creative Commons Attribution 4.0 International license
(CC BY 4.0, https://creativecommons.org/licenses/by/4.0/), as stated in the
retained upstream `README.md`.
