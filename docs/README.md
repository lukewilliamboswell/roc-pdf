# Using roc-pdf

These guides describe the 0.3.0 API. When using the
published 0.2.0 bundle, follow its
[versioned authoring guide](https://github.com/lukewilliamboswell/roc-pdf/blob/0.2.0/docs/authoring.md).
Match the manual's version label to the package version you use.

- [User manual](https://lukewilliamboswell.github.io/roc-pdf/manual/): read the
  connected guides in HTML or download the searchable PDF and chapter Markdown.
- [Authoring guide](authoring.md): create documents, choose fonts and styles,
  add tables and figures, and handle diagnostics.
- [Composing a technical manual](manual-composition.md): printed page references,
  chapter headers, numbered instructions, continued callouts and vector diagrams.
- [Built-in and caller fonts](roc-font.md): default families, genuine styles, caller mappings and coverage errors.
- [Destination page references](destination-page-references.md): print
  destination page numbers and configured page labels.
- [Example gallery](../examples/README.md): complete runnable documents and PDFs.
- [API reference](https://lukewilliamboswell.github.io/roc-pdf/): public types
  and functions.
- [Named-argument migration](migrating-named-arguments.md): update 0.2.0 calls
  to the 0.3.0 API.
- [0.3.0 changes](releases/0.3.0.md): new font defaults, diagnostics
  and migration impact.

The default `Archive` profile produces tagged PDF 2.0 with static PDF/A-4.
PDF/UA-2 is not currently claimed. See the
[authoring guide](authoring.md) for profile options and supported content.

For repository development and validation records, see the
[contributor documentation](../development/README.md).

## Release notes

- [0.3.0 changes](releases/0.3.0.md): genuine font families, named arguments and located diagnostics
- [0.2.0](releases/0.2.0.md): aligned contents entries and the Inter/Fira Code preset
- [0.2.0-rc1](releases/0.2.0-rc1.md): aligned, wrapped contents entries
- [0.1.1](releases/0.1.1.md): builds on Roc nightlies from 2026-10-24
- [0.1.0](releases/0.1.0.md)
- Release candidates: [rc6](releases/0.1.0-rc6.md),
  [rc5](releases/0.1.0-rc5.md), [rc4](releases/0.1.0-rc4.md),
  [rc3](releases/0.1.0-rc3.md), [rc2](releases/0.1.0-rc2.md) with its
  [migration guide](migrating-to-rc2.md), and [rc1](releases/0.1.0-rc1.md)
