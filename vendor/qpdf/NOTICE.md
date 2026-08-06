# qpdf 12.3.2 Linux x86-64

The retained `qpdf-12.3.2-bin-linux-x86_64.zip` is the unmodified qpdf release
artifact used only by the repository's test tooling. It was downloaded from:

https://github.com/qpdf/qpdf/releases/download/v12.3.2/qpdf-12.3.2-bin-linux-x86_64.zip

Its SHA-256 digest is:

`44f2c53bf784c0143128d80d2b9946e9793962c5bb403b75c0024cb4d8e346b9`

Its SHA-512 digest is:

`02b30b8a1c2c24b68907ba8ae4a326d81416b0b80acb6e6e5678c2b5f369a66c60158e00423dbe372244588a7cc9f5ee0573b8537c083a162a3d91b05a94bf8c`

qpdf is copyright 2005-2021 Jay Berkenbilt and 2022-2026 Jay
Berkenbilt and Manfred Holger and is licensed under Apache-2.0. The matching
upstream `LICENSE.txt` and `UPSTREAM-NOTICE.md` from tag `v12.3.2` are retained
beside the archive.

The unmodified upstream binary archive also carries dynamically linked builds
of libffi, GnuTLS, Nettle/Hogweed, GNU libidn2, libjpeg-turbo, p11-kit, GNU
libtasn1, and GNU libunistring. Those components remain under their respective
upstream licenses; no bundled library is modified or linked into the
production Roc package. Their filenames and versioned ABI identities remain
inside the checksum-pinned upstream archive.
