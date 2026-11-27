# Ordered Latin and Han coverage

```sh
roc run main.roc
roc run main.roc latin-only
```

The first command writes [ordered-han.pdf](ordered-han.pdf). The ordered
policy tries the packaged Inter Regular face first, then Receiving Han
Regular. The English paragraph contains `仓库交接`, meaning warehouse
handover, in a `zh-Hans` span. The running header uses both faces, and the
right-aligned table cell contains only the digits `28`.

`latin-only` registers the same policy with only Inter. It returns
`text.coverage_missing` for U+4ED3 at `contents[1].inlines[1].inlines[0]`
and exits before opening the output.

Receiving Han is a four-character static subset for this sample.
The OFL terms are in [fonts/OFL.txt](fonts/OFL.txt). Its immutable
[Noto Sans SC source](https://raw.githubusercontent.com/google/fonts/2894aab31764f10f29c421bdfd2340d3b382d384/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf)
is verified and instantiated at weight 400 by the
[font fixture generator](../../scripts/build_cjk_font_fixture.py) with
`--gallery`. The [asset manifest](../../assets/provenance.json) pins the
derived face.
