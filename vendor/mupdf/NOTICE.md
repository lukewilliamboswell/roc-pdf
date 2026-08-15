# MuPDF 1.28.2 source archive

The retained `mupdf-1.28.2-source.tgz` is the unmodified MuPDF 1.28.2 source
release artifact (upstream filename `mupdf-1.28.2-source.tar.gz`; only the
local filename differs) used only by the repository's test tooling as the
extended-diversity renderer. `mutool` is compiled from these exact bytes at
test time; no MuPDF code is linked into or invoked by the production Roc
package. It was downloaded from:

https://mupdf.com/downloads/archive/mupdf-1.28.2-source.tar.gz

Its SHA-256 digest is:

`44075a84e329db55b9bef5f342a70fd26d69e48ad1d33cb89d9664581c641156`

Its SHA-512 digest is:

`aa574414f273f2463c98dc65773d33adc0e3909b0424fb5748f437791f85ef7298452a85db5fde342273a2b0fee738a8a5d6b9e1d93750302b647091b55bbfed`

MuPDF is copyright Artifex Software, Inc. and is licensed under the GNU
Affero General Public License version 3 (or a commercial license from
Artifex). The upstream top-level `COPYING` from this archive is retained
beside it as `COPYING.txt`; the archive additionally carries its bundled
third-party components (including FreeType, HarfBuzz, libjpeg, zlib, and the
packaged fonts) under their own licenses in `thirdparty/`, `docs/license.md`,
and `resources/`. The archive is redistributed unmodified with all of that
license and attribution material intact, which satisfies the AGPL's
source-availability terms for this repository's use as a test oracle.
