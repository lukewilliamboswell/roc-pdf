# Vendored test dependencies

This directory retains small, redistributable release artifacts used by the
repository's independent test oracles. They are test-only: no file here is a
production Roc dependency or a fallback path in generated documents.

CI consumes the checked-in bytes directly and never downloads a replacement
when an artifact is missing or has the wrong digest. Every binary is covered
by `assets/provenance.json`, including its exact byte length, SHA-256 digest,
immutable origin, license, attribution, and redistribution decision. The
repository contract checker hashes every tracked binary before Roc allocation
measurements begin.

Current retained tools are:

- Apache PDFBox 3.0.8's standalone application JAR;
- qpdf 12.3.2's Linux x86-64 binary archive; and
- PDFium Chromium 7988's Linux x64 archive.

Keep upstream archives byte-for-byte intact. To update one, review its license
and bundled notices, download the exact immutable release, verify the upstream
digest, replace the artifact and attribution together, update the provenance
record and CI reference, run `./scripts/test.py`, and commit the whole upgrade
atomically. Do not use Git LFS or add a download fallback.

Whole Roc/Zig toolchains, JDK distributions, and container images are too
large and platform-specific for Git. Hermetic deployments should preload those
exactly pinned dependencies into an immutable runner image.
