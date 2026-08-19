# ICC sRGB2014 profile

The retained `sRGB2014.icc` is the International Color Consortium's official
sRGB v2 profile, byte-for-byte as published at:

https://www.color.org/profiles/sRGB2014.icc

(linked from the ICC's sRGB profile page,
https://www.color.org/srgbprofiles.xalter). It is a reviewed production data
asset: the production-visual color pipeline embeds these exact bytes as the ICCBased sRGB
profile stream, and the later static-archive slices reuse the same bytes for
the sRGB output intent. `scripts/build_srgb_profile.py` emits the private
`package/KernelSrgbProfile.roc` byte module from this exact asset, so the pure
Roc package carries the profile as compiled package data and performs no file
access.

Its SHA-256 digest is:

`384b832de3412066743b52a75ee906b6fb9fb8d9e09e936fc2c43223815c6e0a`

Its SHA-512 digest is:

`5a46bbebc6c6c028204a39fd8f01fc76fee3b6b14e6c97c43dc055873eb89f136246c3d14a21d10a36f67109abbc9f4f5f2dd2eb4a56f812fa796ce1d1581667`

The profile identifies itself as `sRGB2014` (its `desc` tag), version 2.0,
RGB display class, created 2015-02-15, 3,024 bytes, with the embedded
copyright tag "Copyright International Color Consortium, 2015". Its ICC
profile ID header field carries the MD5 `3d0eb2deae9397be9b6726ce8c0a43ce`,
which matches the MD5 recomputed over the profile with the flags, rendering
intent, and profile ID header fields zeroed, exactly as ISO 15076-1 defines
the profile ID.

Because color.org fronts its downloads with an interactive challenge that
blocks reproducible non-browser retrieval, the bytes were retrieved from two
independent hosts that vendor this exact upstream file — the Qt project's
`qtbase` repository (`src/3rdparty/icc/sRGB2014.icc`, whose REUSE attribution
records the same color.org origin and ICC license) on both
`github.com/qt/qtbase` and `code.qt.io/cgit/qt/qtbase.git` — and verified to
be byte-identical across hosts, to carry the embedded ICC identification
above, and to satisfy the internal profile-ID MD5 self-check. An upgrade must
verify a replacement against color.org directly.

The profile is licensed under the ICC's published terms for profiles whose
copyright owner is the ICC, which permit copying, distribution, and embedding
without restriction while forbidding altered versions from carrying the
original identification; the exact wording and its source are retained beside
this notice in `LICENSE.txt`. The asset is redistributed unmodified. The
choice of the v2 `sRGB2014` profile over the v4 sRGB preference profile is
deliberate: PDF output intents and ICCBased spaces want colorimetric sRGB,
not the v4 profile's perceptual preference re-rendering, and the v2 profile
is a twentieth the size of the v4 one in every generated file. ISO 32000-2
accepts ICC profiles up to v4 and does not accept iccMAX, so neither newer
family displaces this pin.
