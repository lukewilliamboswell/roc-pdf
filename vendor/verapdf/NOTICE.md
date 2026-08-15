# veraPDF greenfield 1.30.2 installer

The retained `verapdf-greenfield-1.30.2-installer.zip` is the unmodified
veraPDF greenfield 1.30.2 release installer used only by the repository's
test tooling. The greenfield flavour is deliberately selected over the
PDFBox-backed flavour so the validator does not share a parser with the
repository's separate Apache PDFBox oracle. The installer is executed at
provisioning time to lay down the pinned validator; nothing from it is linked
into or invoked by the production Roc package. It was downloaded from:

https://software.verapdf.org/releases/1.30/verapdf-greenfield-1.30.2-installer.zip

Its SHA-256 digest is:

`6cc6341cb1af644044054b81f00a6590a7918abb18f762243de115258bcad838`

Its SHA-512 digest is:

`c323f50378963cadc87cc43a51569d11a1fc1e205dc5f0b21e24090ed3822f0e0c15a6ed70d27a6b24e5c671c744a9d3417acef6e71c8314bb093525d16babed`

The upstream detached PGP signature is retained beside the archive as
`verapdf-greenfield-1.30.2-installer.zip.asc` and verifies as a good
signature from RSA key `13DD102B4DD69354D12DE5A83184863278B17FE7`
("Carl Wilson <techlead@verapdf.org>", fetched from keyserver.ubuntu.com at
retrieval time).

veraPDF is copyright the veraPDF Consortium and is dual-licensed under
MPL-2.0 and GPL-3.0-or-later. The installer archive carries the authoritative
license and attribution material for veraPDF and its bundled components.
